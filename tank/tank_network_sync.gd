class_name TankNetworkSync
extends Node

## Компонент сетевой синхронизации танка TANKUS (Server-Authoritative).
## На сервере: принимает намерения ввода клиента и реплицирует авторитетное состояние танка.
## На клиенте: предсказывает локальное движение, повторяет неподтверждённый
## ввод после серверной коррекции и интерполирует удалённые танки.

@export var sync_rate_hz: float = 30.0
@export var prediction_enabled: bool = true

const MAX_INPUT_HISTORY: int = 180
const INPUT_REDUNDANCY: int = 6
const INPUT_TIMEOUT_SEC: float = 0.25

var simulated_latency_ms: int = 0 # Задержка в одну сторону, только для отладки движения.
var last_correction_distance: float = 0.0
var reconciliation_count: int = 0
var _input_sequence: int = 0
var _last_received_input: int = 0
var _last_processed_input: int = 0
var _motion_epoch: int = 0
var _snapshot_id: int = 0
var _last_snapshot_id: int = -1
var _snapshot_timer: float = 0.0
var _input_age: float = 0.0
var _server_commands: Array[Dictionary] = []
var _pending_inputs: Array[Dictionary] = []
var _recent_inputs: Array[Dictionary] = []
var _delayed_inputs: Array[Dictionary] = []
var _delayed_snapshots: Array[Dictionary] = []
var _prediction_ready: bool = false
var _awaiting_motion_reset: bool = false
var _last_frozen: bool = false
var _visual_offset: Vector3 = Vector3.ZERO
var _visual_rest_position: Vector3 = Vector3.ZERO
var _owner_server_position: Vector3 = Vector3.ZERO
var _owner_server_yaw: float = 0.0

var synced_position: Vector3 = Vector3.ZERO
var synced_rotation_y: float = 0.0
var synced_turret_yaw: float = 0.0
var synced_turret_pitch: float = 0.0
var synced_health: float = 100.0:
	set(val):
		synced_health = val
		if not _is_server() and is_node_ready():
			_client_sync_gameplay_state()

var synced_ammo: int = 6:
	set(val):
		synced_ammo = val
		if not _is_server() and is_node_ready():
			_apply_synced_weapon_state()

var synced_is_reloading: bool = false
var synced_is_blocking: bool = false
var synced_team_color: Color = Color.WHITE

var synced_is_active: bool = true:
	set(val):
		synced_is_active = val
		if not _is_server() and is_node_ready():
			_client_sync_gameplay_state()

var synced_tank_scale: float = 1.0:
	set(val):
		synced_tank_scale = val
		if not _is_server() and is_node_ready():
			_apply_synced_scale()

var synced_is_frozen: bool = false:
	set(val):
		synced_is_frozen = val
		if _tank:
			if val and not _tank.is_frozen and not _is_server():
				_clear_prediction_history()
			_tank.is_frozen = val

var bot_brain: TankBotController = null
var synced_team_id: int = 0

var _tank: Tank = null
var _synchronizer: MultiplayerSynchronizer = null
var _is_local_owner: bool = false

# Серверный буфер клиентского ввода
var _client_move_dir: Vector3 = Vector3.ZERO
var _client_aim_point: Vector3 = Vector3.ZERO
var _client_is_aim_valid: bool = false
var _client_wants_jump: bool = false
var _client_wants_fire: bool = false
var _client_is_fire_held: bool = false
var _client_wants_reload: bool = false
var _client_wants_block: bool = false

func _is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

func _get_unique_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

func _ready() -> void:
	_tank = get_parent() as Tank
	if not _tank:
		return

	if _tank.name.begins_with("Tank_"):
		var id_str := _tank.name.trim_prefix("Tank_")
		if id_str.is_valid_int():
			_tank.peer_id = id_str.to_int()

	_is_local_owner = (_tank.peer_id == _get_unique_id())

	simulated_latency_ms = Network.debug_movement_latency_ms
	prediction_enabled = prediction_enabled and Network.movement_prediction_enabled
	_visual_rest_position = _tank.get_node("Visuals").position
	_setup_synchronizer()
	_configure_local_input()

	if _is_server():
		_update_synced_properties_from_tank()

func _setup_synchronizer() -> void:
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "NetSync"
	_synchronizer.replication_interval = 1.0 / sync_rate_hz
	_synchronizer.delta_interval = 0.0

	var config := SceneReplicationConfig.new()

	_add_replicated_property(config, NodePath(".:synced_position"), true)
	_add_replicated_property(config, NodePath(".:synced_rotation_y"), true)
	_add_replicated_property(config, NodePath(".:synced_turret_yaw"), true)
	_add_replicated_property(config, NodePath(".:synced_turret_pitch"), true)
	_add_replicated_property(config, NodePath(".:synced_health"), true)
	_add_replicated_property(config, NodePath(".:synced_ammo"), true)
	_add_replicated_property(config, NodePath(".:synced_is_reloading"), true)
	_add_replicated_property(config, NodePath(".:synced_is_blocking"), true)
	_add_replicated_property(config, NodePath(".:synced_team_color"), true)
	_add_replicated_property(config, NodePath(".:synced_team_id"), true)
	_add_replicated_property(config, NodePath(".:synced_is_active"), true)
	_add_replicated_property(config, NodePath(".:synced_tank_scale"), true)
	_add_replicated_property(config, NodePath(".:synced_is_frozen"), true)


	_synchronizer.replication_config = config
	_synchronizer.set_multiplayer_authority(1) # Сервер всегда является источником репликации
	add_child(_synchronizer)

func _add_replicated_property(config: SceneReplicationConfig, prop_path: NodePath, always_sync: bool) -> void:
	config.add_property(prop_path)
	config.property_set_spawn(prop_path, true)
	if always_sync:
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	else:
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

func _configure_local_input() -> void:
	if not _tank or not _tank.input:
		return

	# Ввод с клавиатуры/мыши активен ТОЛЬКО для локального владельца танка
	if _is_local_owner:
		_tank.input.enabled = true
	else:
		_tank.input.enabled = false

func is_local_owner() -> bool:
	return _is_local_owner

func set_peer_id(new_peer_id: int) -> void:
	if not _tank:
		return
	_tank.peer_id = new_peer_id
	_is_local_owner = (_tank.peer_id == _get_unique_id())
	_configure_local_input()

func _process(delta: float) -> void:
	if not _tank:
		return

	if not _is_server():
		_client_sync_gameplay_state()
		if not _is_local_owner:
			_interpolate_remote_tank(delta)

	# Локальный клиент для мгновенной отзывчивости наводит локальную башню на свой прицел
	if _is_local_owner and _tank.turret and _tank.input and _tank.input.is_aim_valid:
		_tank.turret.aim_at(_tank.input.aim_point, delta)

func _physics_process(delta: float) -> void:
	if not _tank:
		return

	if _is_server():
		if _last_frozen != _tank.is_frozen:
			reset_movement_prediction()
		_server_take_input(delta)
		_server_process_tank_physics(delta)
		_update_synced_properties_from_tank()
		_snapshot_timer += delta
		if _snapshot_timer >= 1.0 / sync_rate_hz:
			_snapshot_timer = 0.0
			_server_send_movement_snapshot()
	else:
		_client_sync_gameplay_state()
		if _is_local_owner and Network.is_multiplayer_active():
			_client_apply_due_snapshots()
			_client_gather_and_send_input(delta)
			_client_flush_delayed_inputs()
			if not prediction_enabled and not _awaiting_motion_reset:
				_tank.global_position = _tank.global_position.lerp(_owner_server_position, clampf(25.0 * delta, 0.0, 1.0))
				_tank.rotation.y = lerp_angle(_tank.rotation.y, _owner_server_yaw, clampf(20.0 * delta, 0.0, 1.0))
			if _tank.controller:
				_tank.controller.update_tilt_only(delta)
			_visual_offset *= exp(-18.0 * delta)
			if _tank.visuals:
				_tank.visuals.position = _visual_rest_position + _tank.global_basis.inverse() * _visual_offset

func _server_take_input(delta: float) -> void:
	_input_age += delta
	_client_wants_jump = false
	_client_wants_fire = false
	_client_wants_reload = false
	_client_wants_block = false
	if not _server_commands.is_empty():
		var command: Dictionary = _server_commands.pop_front()
		_last_processed_input = command.seq
		_input_age = 0.0
		_client_move_dir = command.move
		_client_aim_point = command.aim
		_client_is_aim_valid = command.aim_valid
		_client_wants_jump = command.jump
		_client_wants_fire = command.fire
		_client_is_fire_held = command.held
		_client_wants_reload = command.reload
		_client_wants_block = command.block
	elif _input_age > INPUT_TIMEOUT_SEC:
		_client_move_dir = Vector3.ZERO
		_client_is_fire_held = false

func _server_process_tank_physics(delta: float) -> void:
	if not _tank.is_active:
		return

	if _tank.is_frozen:
		_tank.velocity.x = 0.0
		_tank.velocity.z = 0.0
		if not _tank.is_on_floor():
			_tank.velocity.y -= (_tank.controller.gravity if _tank.controller else 18.0) * delta
			_tank.move_and_slide()
		else:
			_tank.velocity.y = 0.0

		if _tank.controller:
			_tank.controller.update_tilt_only(delta)

		if _is_local_owner:
			if _tank.turret and _tank.input and _tank.input.is_aim_valid:
				_tank.turret.aim_at(_tank.input.aim_point, delta)
		else:
			if _tank.turret and _client_is_aim_valid:
				_tank.turret.aim_at(_client_aim_point, delta)
		return

	var player := Network.get_player_info(_tank.peer_id)
	if player and player.is_bot:
		if bot_brain == null:
			bot_brain = TankBotController.new(_tank, player.bot_difficulty)
		bot_brain.difficulty = player.bot_difficulty
		var decision := bot_brain.update(delta)
		if _tank.controller:
			_tank.controller.process_movement(decision.move, decision.jump, delta)
		if _tank.turret and decision.aim_valid:
			_tank.turret.aim_at(decision.aim, delta)
		if decision.fire and _tank.weapon:
			_tank.weapon.try_fire()
		if decision.reload and _tank.weapon:
			_tank.weapon.start_reload()
		if decision.block and _tank.block:
			_tank.block.activate_block()
		return

	# Если танк принадлежит хосту, ввод читается напрямую из локального TankInput
	if _is_local_owner:
		if _tank.controller:
			_tank.controller.process_physics(_tank.input, delta)
		if _tank.turret and _tank.input and _tank.input.is_aim_valid:
			_tank.turret.aim_at(_tank.input.aim_point, delta)
		_tank._process_combat_input()
	else:
		# Танк принадлежит удаленному клиенту: сервер симулирует его по полученному буферу ввода
		_server_apply_client_movement(delta)
		_server_apply_client_combat()

func _server_apply_client_movement(delta: float) -> void:
	if _tank.controller:
		_tank.controller.process_movement(_client_move_dir, _client_wants_jump, delta)
	_client_wants_jump = false
	if _tank.turret and _client_is_aim_valid:
		_tank.turret.aim_at(_client_aim_point, delta)

func _server_apply_client_combat() -> void:
	if _client_wants_block:
		_client_wants_block = false
		if _tank.block:
			_tank.block.activate_block()

	if _client_wants_reload:
		_client_wants_reload = false
		if _tank.weapon:
			_tank.weapon.start_reload()

	if _client_wants_fire or _client_is_fire_held:
		_client_wants_fire = false
		if _tank.weapon:
			_tank.weapon.try_fire()

func _client_gather_and_send_input(delta: float) -> void:
	if not _tank.input or not _tank.input.enabled:
		return
	var can_move := _tank.is_active and not _tank.is_frozen and not _awaiting_motion_reset
	var jump := _tank.input.consume_jump()
	var fire := _tank.input.consume_fire()
	var reload := _tank.input.consume_reload()
	var block := _tank.input.consume_block()
	if not _prediction_ready or _awaiting_motion_reset:
		return
	_input_sequence += 1
	var command := {
		"seq": _input_sequence, "epoch": _motion_epoch,
		"move": _tank.input.move_direction_world if can_move else Vector3.ZERO,
		"aim": _tank.input.aim_point, "aim_valid": _tank.input.is_aim_valid,
		"jump": jump and can_move, "fire": fire and can_move,
		"held": _tank.input.is_fire_held() and can_move,
		"reload": reload and can_move, "block": block and can_move
	}
	if prediction_enabled and can_move and _tank.controller:
		_tank.controller.process_movement(command.move, command.jump, delta, false)
	_pending_inputs.append({"command": command, "position": _tank.global_position,
		"velocity": _tank.velocity})
	if _pending_inputs.size() > MAX_INPUT_HISTORY:
		_pending_inputs.pop_front()
	_recent_inputs.append(command)
	if _recent_inputs.size() > INPUT_REDUNDANCY:
		_recent_inputs.pop_front()
	# Компактный пакет: словари с повторяющимися строковыми ключами превышали MTU.
	var batch: Array = []
	for recent in _recent_inputs:
		var flags: int = int(recent.aim_valid) | (int(recent.jump) << 1) | (int(recent.fire) << 2) | (int(recent.held) << 3) | (int(recent.reload) << 4) | (int(recent.block) << 5)
		batch.append([recent.seq, recent.epoch, recent.move, recent.aim, flags])
	if simulated_latency_ms > 0:
		_delayed_inputs.append({"due": Time.get_ticks_msec() + simulated_latency_ms, "batch": batch})
		if _delayed_inputs.size() > MAX_INPUT_HISTORY:
			_delayed_inputs.pop_front()
	else:
		c2s_send_inputs.rpc_id(1, batch)

func _client_flush_delayed_inputs() -> void:
	while not _delayed_inputs.is_empty() and _delayed_inputs[0].due <= Time.get_ticks_msec():
		var packet: Dictionary = _delayed_inputs.pop_front()
		c2s_send_inputs.rpc_id(1, packet.batch)

## Номера команд позволяют подтвердить именно выполненный ввод. Повтор последних
## команд восстанавливает небольшую потерю пакетов без повторного прыжка/выстрела.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c2s_send_inputs(commands: Array) -> void:
	if not _is_server() or multiplayer.get_remote_sender_id() != _tank.peer_id:
		return
	if commands.size() > INPUT_REDUNDANCY:
		return
	for value in commands:
		var command := _decode_input_command(value)
		if command.is_empty():
			continue
		if command.epoch != _motion_epoch or command.seq <= _last_received_input:
			continue
		if _server_commands.size() >= MAX_INPUT_HISTORY:
			break
		_last_received_input = command.seq
		_server_commands.append(command)

func _decode_input_command(value: Variant) -> Dictionary:
	if not value is Array or value.size() != 5:
		return {}
	if not value[0] is int or value[0] < 1 or not value[1] is int or value[1] < 0:
		return {}
	if not value[2] is Vector3 or not value[3] is Vector3:
		return {}
	if not value[2].is_finite() or not value[3].is_finite():
		return {}
	if not value[4] is int or value[4] < 0 or value[4] > 63:
		return {}
	var flags: int = value[4]
	var direction: Vector3 = value[2]
	return {"seq": value[0], "epoch": value[1],
		"move": Vector3(direction.x, 0.0, direction.z).limit_length(1.0), "aim": value[3],
		"aim_valid": (flags & 1) != 0, "jump": (flags & 2) != 0,
		"fire": (flags & 4) != 0, "held": (flags & 8) != 0,
		"reload": (flags & 16) != 0, "block": (flags & 32) != 0}

func _server_send_movement_snapshot() -> void:
	if _is_local_owner or not Network.is_multiplayer_active() or not _tank.controller:
		return
	if _tank.peer_id not in multiplayer.get_peers():
		return
	_snapshot_id += 1
	s2c_movement_snapshot.rpc_id(_tank.peer_id, {
		"id": _snapshot_id, "epoch": _motion_epoch, "ack": _last_processed_input,
		"position": _tank.global_position, "yaw": _tank.rotation.y,
		"velocity": _tank.velocity, "movement": _tank.controller.capture_movement_state()
	})

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func s2c_movement_snapshot(snapshot: Dictionary) -> void:
	if _is_server() or not _is_local_owner:
		return
	_delayed_snapshots.append({"due": Time.get_ticks_msec() + simulated_latency_ms, "snapshot": snapshot})
	if _delayed_snapshots.size() > MAX_INPUT_HISTORY:
		_delayed_snapshots.pop_front()

func _client_apply_due_snapshots() -> void:
	var newest: Dictionary = {}
	while not _delayed_snapshots.is_empty() and _delayed_snapshots[0].due <= Time.get_ticks_msec():
		newest = _delayed_snapshots.pop_front().snapshot
	if not newest.is_empty():
		_reconcile_movement(newest)

func _reconcile_movement(snapshot: Dictionary) -> void:
	if snapshot.id <= _last_snapshot_id or snapshot.epoch < _motion_epoch:
		return
	if _awaiting_motion_reset and snapshot.epoch <= _motion_epoch:
		return
	_last_snapshot_id = snapshot.id
	var reset: bool = snapshot.epoch != _motion_epoch or not _prediction_ready
	_motion_epoch = snapshot.epoch
	_prediction_ready = true
	_awaiting_motion_reset = false
	_input_sequence = maxi(_input_sequence, snapshot.ack)
	var acknowledged: Dictionary = {}
	while not _pending_inputs.is_empty() and _pending_inputs[0].command.seq <= snapshot.ack:
		acknowledged = _pending_inputs.pop_front()
	if reset:
		_clear_prediction_history()
	var error: float = snapshot.position.distance_to(acknowledged.get("position", _tank.global_position))
	last_correction_distance = error
	_owner_server_position = snapshot.position
	_owner_server_yaw = snapshot.yaw
	if not prediction_enabled and not reset:
		return
	# Сравниваем с предсказанием в момент подтверждённой команды, а не с
	# текущей позицией: она закономерно опережает сервер на время RTT.
	if not reset and prediction_enabled and not acknowledged.is_empty():
		if error < 0.015 and snapshot.velocity.distance_to(acknowledged.velocity) < 0.1:
			return
	var old_visible_position := _tank.global_position + _visual_offset
	_tank.global_position = snapshot.position
	_tank.rotation.y = snapshot.yaw
	_tank.velocity = snapshot.velocity
	_tank.controller.restore_movement_state(snapshot.movement)
	if prediction_enabled and _tank.is_active and not _tank.is_frozen:
		var step := 1.0 / float(Engine.physics_ticks_per_second)
		for pending in _pending_inputs:
			_tank.controller.process_movement(pending.command.move, pending.command.jump, step, false, true)
			pending.position = _tank.global_position
			pending.velocity = _tank.velocity
	if reset or old_visible_position.distance_to(_tank.global_position) > 2.5:
		_visual_offset = Vector3.ZERO
	else:
		_visual_offset = old_visible_position - _tank.global_position
	reconciliation_count += 1

func _clear_prediction_history() -> void:
	_pending_inputs.clear()
	_recent_inputs.clear()
	_delayed_inputs.clear()
	_visual_offset = Vector3.ZERO
	if _tank and _tank.visuals:
		_tank.visuals.position = _visual_rest_position

## Респавн, начало раунда и телепорт создают новую эпоху. Запоздалый ввод
## прошлой жизни не может сдвинуть танк обратно или повторить действие.
func reset_movement_prediction() -> void:
	_clear_prediction_history()
	if bot_brain:
		bot_brain.reset()
	if _tank and _tank.controller:
		_tank.controller.reset_movement_state()
	if _is_server():
		_motion_epoch += 1
		_server_commands.clear()
		_last_processed_input = _last_received_input
		_client_move_dir = Vector3.ZERO
		_client_is_fire_held = false
		_last_frozen = _tank.is_frozen
		_server_send_movement_snapshot()
	elif _is_local_owner:
		_awaiting_motion_reset = true

func get_pending_input_count() -> int:
	return _pending_inputs.size()

@rpc("any_peer", "reliable")
func c2s_choose_card(card_id: String) -> void:
	if not _is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != _tank.peer_id:
		return

	var card_def := CardDatabase.get_card(card_id)
	if not card_def:
		return

	if _tank and _tank.build:
		_tank.build.add_card(card_def)
		if _tank.stats:
			synced_tank_scale = _tank.stats.tank_scale

	# Рассылаем всем клиентам добавление карты для этого танка
	if multiplayer.has_multiplayer_peer():
		s2c_card_added.rpc(card_id)


@rpc("authority", "reliable")
func s2c_card_added(card_id: String) -> void:
	if _is_server() or not _tank or not _tank.build:
		return

	# Локальный владелец уже добавил карту в локальном интерфейсе драфта, не дублируем
	if _is_local_owner:
		return

	var card_def := CardDatabase.get_card(card_id)
	if card_def:
		_tank.build.add_card(card_def)


@rpc("authority", "unreliable")
func s2c_spawn_ground_slam_vfx(origin: Vector3, radius: float) -> void:
	if _is_server() or not _tank:
		return
	var spawn_parent: Node = _tank.get_parent() if _tank.get_parent() else get_tree().current_scene
	if spawn_parent:
		CardDatabase.GroundSlamEffect.spawn_shockwave_vfx(spawn_parent, origin, radius, _tank.team_color)

@rpc("authority", "unreliable")
func s2c_spawn_block_shockwave_vfx(origin: Vector3, radius: float) -> void:
	if _is_server() or not _tank:
		return
	var spawn_parent: Node = _tank.get_parent() if _tank.get_parent() else get_tree().current_scene
	if spawn_parent:
		var wave_col: Color = _tank.team_color.lightened(0.35) if _tank else Color(0.2, 0.85, 1.0)
		CardDatabase.ShockwaveEffect.spawn_shockwave_vfx(spawn_parent, origin, radius, wave_col)

@rpc("authority", "reliable")
func s2c_spawn_jump_mine(mine_id: int, origin: Vector3, stacks: int = 1) -> void:
	if _is_server() or not _tank:
		return
	CardDatabase.JumpMineEffect.spawn_client_mine(mine_id, origin, _tank, stacks)

@rpc("authority", "reliable")
func s2c_detonate_jump_mine(mine_id: int, exploded: bool) -> void:
	if _is_server():
		return
	CardDatabase.JumpMineEffect.remove_mine_by_id(mine_id, exploded, _tank)

@rpc("any_peer", "reliable")
func c2s_remove_card(card_id: String) -> void:
	if not _is_server() or not Game.rules.allow_admin_panel:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != _tank.peer_id:
		return
	var card_def := CardDatabase.get_card(card_id)
	if not card_def:
		return
	if _tank and _tank.build:
		_tank.build.remove_card(card_def)
		if _tank.stats:
			synced_tank_scale = _tank.stats.tank_scale
	if multiplayer.has_multiplayer_peer():
		s2c_card_removed.rpc(card_id)

@rpc("authority", "reliable")
func s2c_card_removed(card_id: String) -> void:
	if _is_server() or not _tank or not _tank.build or _is_local_owner:
		return
	var card_def := CardDatabase.get_card(card_id)
	if card_def:
		_tank.build.remove_card(card_def)

@rpc("any_peer", "reliable")
func c2s_clear_build() -> void:
	if not _is_server() or not Game.rules.allow_admin_panel:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != _tank.peer_id:
		return
	if _tank and _tank.build:
		_tank.build.clear_build()
		if _tank.stats:
			synced_tank_scale = _tank.stats.tank_scale
	if multiplayer.has_multiplayer_peer():
		s2c_build_cleared.rpc()

@rpc("authority", "reliable")
func s2c_build_cleared() -> void:
	if _is_server() or not _tank or not _tank.build or _is_local_owner:
		return
	_tank.build.clear_build()

@rpc("any_peer", "reliable")
func c2s_heal_tank() -> void:
	if not _is_server() or not Game.rules.allow_admin_panel:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != _tank.peer_id:
		return
	if _tank and _tank.health:
		_tank.health.current_health = _tank.health.max_health
		_tank.health.health_changed.emit(_tank.health.current_health, _tank.health.max_health)
		synced_health = _tank.health.current_health

func _update_synced_properties_from_tank() -> void:
	synced_position = _tank.global_position
	synced_rotation_y = _tank.rotation.y
	synced_team_id = _tank.team_id
	synced_team_color = _tank.team_color
	synced_is_active = _tank.is_active
	synced_is_frozen = _tank.is_frozen

	if _tank.stats:
		synced_tank_scale = _tank.stats.tank_scale


	if _tank.turret:
		synced_turret_yaw = _tank.turret.rotation.y
		if _tank.turret.barrel_mount:
			synced_turret_pitch = _tank.turret.barrel_mount.rotation.x

	if _tank.health:
		synced_health = _tank.health.current_health

	if _tank.weapon:
		synced_ammo = _tank.weapon.current_ammo
		synced_is_reloading = _tank.weapon.is_reloading()

	if _tank.block:
		synced_is_blocking = _tank.block.is_blocking()

func _interpolate_remote_tank(delta: float) -> void:
	if _tank.global_position.distance_to(synced_position) > 2.5:
		_tank.global_position = synced_position
		_tank.rotation.y = synced_rotation_y
		_tank.velocity = Vector3.ZERO
	else:
		_tank.global_position = _tank.global_position.lerp(synced_position, clampf(18.0 * delta, 0.0, 1.0))
		_tank.rotation.y = lerp_angle(_tank.rotation.y, synced_rotation_y, clampf(15.0 * delta, 0.0, 1.0))

	if _tank.controller:
		_tank.controller.update_tilt_only(delta)

	if _tank.turret:
		_tank.turret.rotation.y = lerp_angle(_tank.turret.rotation.y, synced_turret_yaw, clampf(22.0 * delta, 0.0, 1.0))
		_tank.turret.rotation.x = 0.0
		_tank.turret.rotation.z = 0.0
		if _tank.turret.barrel_mount:
			_tank.turret.barrel_mount.rotation.x = lerp_angle(_tank.turret.barrel_mount.rotation.x, synced_turret_pitch, clampf(18.0 * delta, 0.0, 1.0))
			_tank.turret.barrel_mount.rotation.y = 0.0
			_tank.turret.barrel_mount.rotation.z = 0.0

# --- Клиентская синхронизация авторитетного геймплейного состояния с сервера ---

func _client_sync_gameplay_state() -> void:
	if _is_server() or not _tank:
		return

	_apply_synced_health_change()

	if _tank.is_active and (not synced_is_active or synced_health <= 0.0):
		_handle_client_tank_death()
	elif not _tank.is_active and synced_is_active and synced_health > 0.0:
		_handle_client_tank_respawn()

	_apply_synced_weapon_state()
	_apply_synced_visual_state()
	_apply_synced_scale()


func _apply_synced_health_change() -> void:
	if not _tank or not _tank.health:
		return

	var health_diff := _tank.health.current_health - synced_health
	if absf(health_diff) > 0.01:
		if health_diff > 0.0:
			# Получение урона от попадания
			_tank.health._play_hit_flash()
			_tank.health.damage_taken.emit(health_diff, null)
			if _tank.events:
				_tank.events.emit_damage_taken(health_diff, null)
		elif health_diff < 0.0:
			# Восстановление HP
			_tank.health.healed.emit(-health_diff)

		_tank.health.current_health = synced_health
		_tank.health.health_changed.emit(_tank.health.current_health, _tank.health.max_health)

func _handle_client_tank_death() -> void:
	if not _tank:
		return

	_clear_prediction_history()
	_tank.is_active = false
	_tank.velocity = Vector3.ZERO
	if _tank.visuals:
		_tank.visuals.visible = false

	if _tank.health:
		_tank.health.current_health = 0.0
		_tank.health.health_changed.emit(0.0, _tank.health.max_health)
		_tank.health._spawn_death_explosion()
		_tank.health.died.emit(null)

func _handle_client_tank_respawn() -> void:
	if not _tank:
		return

	_clear_prediction_history()
	_tank.is_active = true
	_tank.global_position = synced_position
	_tank.rotation.y = synced_rotation_y
	_tank.velocity = Vector3.ZERO
	if _tank.controller:
		_tank.controller.reset_tilt()

	if _tank.visuals:
		_tank.visuals.visible = true

	if _tank.turret:
		_tank.turret.rotation = Vector3.ZERO

	if _tank.health:
		_tank.health.reset()
		_tank.health.current_health = synced_health
		_tank.health.health_changed.emit(_tank.health.current_health, _tank.health.max_health)

	if _tank.weapon:
		_tank.weapon.reset()

	if _tank.block:
		_tank.block.reset()

	_tank._apply_team_color()
	_apply_synced_scale()

func _apply_synced_weapon_state() -> void:
	if not _tank or not _tank.weapon:
		return

	if _tank.weapon.current_ammo != synced_ammo:
		_tank.weapon.current_ammo = synced_ammo
		_tank.weapon.ammo_changed.emit(synced_ammo, _tank.weapon.magazine_size)

	if synced_is_reloading and not _tank.weapon.is_reloading():
		_tank.weapon.start_reload()
	elif not synced_is_reloading and _tank.weapon.is_reloading():
		_tank.weapon._complete_reload()

func _apply_synced_visual_state() -> void:
	if not _tank:
		return

	if _tank.shield_mesh:
		_tank.shield_mesh.visible = synced_is_blocking

	_tank.team_id = synced_team_id
	if _tank.team_color != synced_team_color:
		_tank.set_team_color(synced_team_color)

func _apply_synced_scale() -> void:
	if not _tank:
		return

	if _tank.visuals and not is_equal_approx(_tank.visuals.scale.x, synced_tank_scale):
		_tank.visuals.scale = Vector3.ONE * synced_tank_scale

	var col_shape := _tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_shape and not is_equal_approx(col_shape.scale.x, synced_tank_scale):
		col_shape.scale = Vector3.ONE * synced_tank_scale

