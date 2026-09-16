class_name TankNetworkSync
extends Node

## Компонент сетевой синхронизации танка TANKUS (Server-Authoritative).
## На сервере: принимает намерения ввода клиента и реплицирует авторитетное состояние танка.
## На клиенте: считывает локальный ввод и интерполирует удаленные танки.

@export var sync_rate_hz: float = 30.0

var synced_position: Vector3 = Vector3.ZERO
var synced_rotation_y: float = 0.0
var synced_turret_yaw: float = 0.0
var synced_turret_pitch: float = 0.0
var synced_health: float = 100.0:
	set(val):
		synced_health = val
		if not _is_server() and is_node_ready():
			_client_sync_gameplay_state()

var synced_ammo: int = 4:
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
	_add_replicated_property(config, NodePath(".:synced_is_active"), true)

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
		# СЕРВЕРНЫЙ АВТОРИТЕТ
		_server_process_tank_physics(delta)
		_update_synced_properties_from_tank()
	else:
		# КЛИЕНТ
		_client_sync_gameplay_state()
		if _is_local_owner:
			_client_gather_and_send_input()
			if _tank.global_position.distance_to(synced_position) > 2.5:
				_tank.global_position = synced_position
				_tank.rotation.y = synced_rotation_y
			else:
				_tank.global_position = _tank.global_position.lerp(synced_position, clampf(25.0 * delta, 0.0, 1.0))
				_tank.rotation.y = lerp_angle(_tank.rotation.y, synced_rotation_y, clampf(20.0 * delta, 0.0, 1.0))

func _server_process_tank_physics(delta: float) -> void:
	if not _tank.is_active:
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
	if not _tank.controller:
		return

	var on_floor := _tank.is_on_floor()

	# Прыжок
	if _client_wants_jump and on_floor:
		_tank.velocity.y = _tank.controller.jump_velocity
		_client_wants_jump = false
		if _tank.events:
			_tank.events.emit_jump()
	elif not on_floor:
		_tank.velocity.y -= _tank.controller.gravity * delta
	else:
		_tank.velocity.y = 0.0

	# Горизонтальное движение
	var current_accel: float = _tank.controller.acceleration if on_floor else (_tank.controller.acceleration * _tank.controller.air_control)
	var current_brake: float = _tank.controller.braking if on_floor else (_tank.controller.braking * _tank.controller.air_control)
	var effective_speed := _tank.controller.move_speed * _tank.controller.speed_multiplier

	if _client_move_dir.length_squared() > 0.01:
		var target_vel := _client_move_dir * effective_speed
		_tank.velocity.x = move_toward(_tank.velocity.x, target_vel.x, current_accel * delta)
		_tank.velocity.z = move_toward(_tank.velocity.z, target_vel.z, current_accel * delta)
	else:
		_tank.velocity.x = move_toward(_tank.velocity.x, 0.0, current_brake * delta)
		_tank.velocity.z = move_toward(_tank.velocity.z, 0.0, current_brake * delta)

	# Поворот корпуса по фактической скорости
	var flat_vel := Vector3(_tank.velocity.x, 0.0, _tank.velocity.z)
	if flat_vel.length_squared() > 0.35:
		var vel_dir := flat_vel.normalized()
		var target_yaw := atan2(-vel_dir.x, -vel_dir.z)
		var diff := wrapf(target_yaw - _tank.rotation.y, -PI, PI)
		if absf(diff) > 0.005:
			_tank.rotation.y += signf(diff) * minf(absf(diff), _tank.controller.body_turn_speed * delta)

	_tank.move_and_slide()

	# Доворот башни на сервере
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

func _client_gather_and_send_input() -> void:
	if not _tank.input or not _tank.input.enabled:
		return

	var move_dir := _tank.input.move_direction_world
	var aim := _tank.input.aim_point
	var is_aim_valid := _tank.input.is_aim_valid
	var jump := _tank.input.consume_jump()
	var fire := _tank.input.consume_fire()
	var fire_held := _tank.input.is_fire_held()
	var reload := _tank.input.consume_reload()
	var block := _tank.input.consume_block()

	c2s_send_input.rpc_id(1, move_dir, aim, is_aim_valid, jump, fire, fire_held, reload, block)

@rpc("any_peer", "unreliable_ordered")
func c2s_send_input(move_dir: Vector3, aim: Vector3, is_aim_valid: bool, jump: bool, fire: bool, fire_held: bool, reload: bool, block: bool) -> void:
	if not _is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != _tank.peer_id:
		return # Игнорируем попытку чужого пира управлять этим танком

	_client_move_dir = move_dir.limit_length(1.0)
	_client_aim_point = aim
	_client_is_aim_valid = is_aim_valid

	if jump:
		_client_wants_jump = true
	if fire:
		_client_wants_fire = true
	_client_is_fire_held = fire_held
	if reload:
		_client_wants_reload = true
	if block:
		_client_wants_block = true

func _update_synced_properties_from_tank() -> void:
	synced_position = _tank.global_position
	synced_rotation_y = _tank.rotation.y
	synced_team_color = _tank.team_color
	synced_is_active = _tank.is_active

	if _tank.turret:
		synced_turret_yaw = _tank.turret.global_rotation.y
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
	else:
		_tank.global_position = _tank.global_position.lerp(synced_position, clampf(18.0 * delta, 0.0, 1.0))
		_tank.rotation.y = lerp_angle(_tank.rotation.y, synced_rotation_y, clampf(15.0 * delta, 0.0, 1.0))

	if _tank.turret:
		_tank.turret.global_rotation.y = lerp_angle(_tank.turret.global_rotation.y, synced_turret_yaw, clampf(22.0 * delta, 0.0, 1.0))
		if _tank.turret.barrel_mount:
			_tank.turret.barrel_mount.rotation.x = lerp_angle(_tank.turret.barrel_mount.rotation.x, synced_turret_pitch, clampf(18.0 * delta, 0.0, 1.0))

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

	_tank.is_active = true
	_tank.global_position = synced_position
	_tank.rotation.y = synced_rotation_y
	_tank.velocity = Vector3.ZERO

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

	if _tank.team_color != synced_team_color:
		_tank.set_team_color(synced_team_color)
