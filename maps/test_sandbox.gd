class_name TestSandbox
extends Node3D

## Скрипт тестовой песочницы TANKUS (Phase 4: Сетевой LAN-слой и песочница).
## Поддерживает как одиночное тестирование механик, так и полноценный сетевой мультиплеер
## с серверным авторитетом, динамическим спавном через MultiplayerSpawner и LAN Discovery.

const TEAM_COLORS: Array[Color] = [
	Color(0.18, 0.55, 0.95), # Синий (Хост)
	Color(0.95, 0.25, 0.25), # Красный
	Color(0.2, 0.85, 0.35),  # Зеленый
	Color(0.95, 0.75, 0.15), # Желтый
	Color(0.75, 0.25, 0.95), # Фиолетовый
	Color(0.15, 0.85, 0.85), # Бирюзовый
	Color(0.95, 0.5, 0.15),  # Оранжевый
	Color(0.85, 0.85, 0.85)  # Белый
]

@onready var tank: Tank = get_node_or_null("Tank")
@onready var dummy_tank: Tank = get_node_or_null("DummyTank")
@onready var camera: TPSCamera = $TPSCamera
@onready var spawn_marker: Marker3D = get_node_or_null("SpawnPoint")
@onready var dummy_spawn_marker: Marker3D = get_node_or_null("DummySpawnPoint")
@onready var kill_volume: Area3D = $KillVolume
@onready var hud: HUD = get_node_or_null("HUD")
@onready var card_draft: CardDraft = get_node_or_null("CardDraft")

@onready var lan_menu: LANMenu = get_node_or_null("LANMenu")
@onready var spawned_tanks: Node3D = get_node_or_null("SpawnedTanks")
@onready var projectiles: Node3D = get_node_or_null("Projectiles")
@onready var spawn_points_container: Node3D = get_node_or_null("SpawnPoints")
@onready var tank_spawner: MultiplayerSpawner = get_node_or_null("TankSpawner")
@onready var proj_spawner: MultiplayerSpawner = get_node_or_null("ProjSpawner")

var _active_local_tank: Tank = null

func _ready() -> void:
	if kill_volume:
		kill_volume.body_entered.connect(_on_kill_volume_body_entered)

	_setup_network_signals()

	if spawned_tanks:
		spawned_tanks.child_entered_tree.connect(_on_spawned_tank_entered)

	# По умолчанию настраиваем одиночный танк
	_setup_solo_mode()

func _setup_network_signals() -> void:
	Network.server_created.connect(_on_server_created)
	Network.server_closed.connect(_on_session_ended)
	Network.connected_to_server.connect(_on_connected_to_server)
	Network.peer_connected.connect(_on_peer_connected)
	Network.peer_disconnected.connect(_on_peer_disconnected)
	Network.server_disconnected.connect(_on_session_ended)

	if lan_menu:
		lan_menu.game_started.connect(_on_lan_game_started)

func _setup_solo_mode() -> void:
	if tank and camera:
		_bind_local_tank(tank)

	if spawn_marker and tank:
		tank.spawn_point = spawn_marker.global_transform
		tank.global_transform = spawn_marker.global_transform

	if dummy_tank:
		dummy_tank.team_id = 1
		dummy_tank.set_team_color(Color(0.95, 0.25, 0.25))
		if dummy_tank.input:
			dummy_tank.input.enabled = false
		if dummy_spawn_marker:
			dummy_tank.spawn_point = dummy_spawn_marker.global_transform
			dummy_tank.global_transform = dummy_spawn_marker.global_transform

func _bind_local_tank(target_tank: Tank) -> void:
	_active_local_tank = target_tank
	if target_tank.input:
		target_tank.input.enabled = true
	if target_tank.net_sync:
		target_tank.net_sync.set_peer_id(target_tank.peer_id)
	if camera:
		camera.target_node = target_tank
		camera.global_position = target_tank.global_position + camera.target_offset
	if hud and target_tank:
		hud.bind_to_tank(target_tank)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_BACKSPACE:
			_respawn_all()
		elif event.keycode == KEY_TAB:
			if card_draft and _active_local_tank:
				if card_draft.visible:
					card_draft.close_draft()
				else:
					card_draft.open_draft(_active_local_tank)
		elif event.keycode == KEY_ESCAPE:
			if lan_menu:
				lan_menu.set_menu_visible(not lan_menu.visible)

# --- Сетевой спавн танков ---

func _on_server_created() -> void:
	# Скрываем локальные соло-танки
	_set_solo_tanks_active(false)

	# Сервер спавнит танк хоста (peer 1)
	_server_spawn_tank_for_peer(1)

func _on_connected_to_server() -> void:
	# Клиент подключился к серверу: скрываем соло-танки
	_set_solo_tanks_active(false)
	_check_and_bind_my_tank()

func _on_peer_connected(peer_id: int) -> void:
	if Network.is_server():
		_server_spawn_tank_for_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if Network.is_server():
		_server_remove_tank_for_peer(peer_id)

var _peer_spawn_slots: Dictionary = {} # peer_id: int -> slot_index: int

func _on_session_ended() -> void:
	_peer_spawn_slots.clear()
	# Очищаем сетевые танки и возвращаем соло режим
	if spawned_tanks:
		for child in spawned_tanks.get_children():
			child.queue_free()

	_set_solo_tanks_active(true)
	if tank:
		_bind_local_tank(tank)
		_respawn_tank()

func _set_solo_tanks_active(is_active_solo: bool) -> void:
	if tank:
		tank.visible = is_active_solo
		tank.is_active = is_active_solo
		tank.process_mode = Node.PROCESS_MODE_INHERIT if is_active_solo else Node.PROCESS_MODE_DISABLED
		var col := tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col:
			col.disabled = not is_active_solo
	if dummy_tank:
		dummy_tank.visible = is_active_solo
		dummy_tank.is_active = is_active_solo
		dummy_tank.process_mode = Node.PROCESS_MODE_INHERIT if is_active_solo else Node.PROCESS_MODE_DISABLED
		var col := dummy_tank.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col:
			col.disabled = not is_active_solo

func _get_or_assign_spawn_slot(peer_id: int) -> int:
	if _peer_spawn_slots.has(peer_id):
		return _peer_spawn_slots[peer_id]

	# Хост (1) всегда занимает слот 0
	if peer_id == 1:
		_peer_spawn_slots[1] = 0
		return 0

	# Клиенты занимают следующий свободный слот от 1 до 7
	var used: Array = _peer_spawn_slots.values()
	for slot in range(1, 8):
		if slot not in used:
			_peer_spawn_slots[peer_id] = slot
			return slot

	var fallback_slot := _peer_spawn_slots.size() % 8
	_peer_spawn_slots[peer_id] = fallback_slot
	return fallback_slot

func _server_spawn_tank_for_peer(peer_id: int) -> void:
	if not Network.is_server() or not spawned_tanks:
		return

	# Проверяем, не заспавнен ли уже танк для этого пира
	var node_name := "Tank_%d" % peer_id
	if spawned_tanks.has_node(node_name):
		return

	var tank_scene := preload("res://tank/tank.tscn")
	var t := tank_scene.instantiate() as Tank
	t.name = node_name
	t.peer_id = peer_id

	var slot := _get_or_assign_spawn_slot(peer_id)
	var spawn_tf := _get_spawn_transform_for_peer(peer_id)
	var team_col := TEAM_COLORS[slot % TEAM_COLORS.size()]

	# Подключаем смерть танка к авто-респавну на сервере через 2 секунды
	t.died.connect(func(killer): _on_tank_died(t, killer))

	spawned_tanks.add_child(t, true)

	t.global_transform = spawn_tf
	t.spawn_point = spawn_tf
	t.setup_network(peer_id, slot, team_col)

func _on_tank_died(dead_tank: Tank, _killer: Node) -> void:
	if not Network.is_server():
		return

	# Автореспавн через 2 секунды в песочнице на СВОЮ точку спавна
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(dead_tank):
			var spawn_tf := _get_spawn_transform_for_peer(dead_tank.peer_id)
			dead_tank.respawn(spawn_tf)
	)

func _server_remove_tank_for_peer(peer_id: int) -> void:
	_peer_spawn_slots.erase(peer_id)
	if not Network.is_server() or not spawned_tanks:
		return

	var node_name := "Tank_%d" % peer_id
	var t := spawned_tanks.get_node_or_null(node_name)
	if t:
		t.queue_free()

func _on_spawned_tank_entered(node: Node) -> void:
	if node is Tank:
		var t := node as Tank
		if t.name.begins_with("Tank_"):
			var id_str := t.name.trim_prefix("Tank_")
			if id_str.is_valid_int():
				t.peer_id = id_str.to_int()

		# Даем кадру пройти для инициализации всех дочерних нод
		await get_tree().process_frame
		if is_instance_valid(t):
			if t.peer_id == Network.get_unique_id():
				_bind_local_tank(t)

func _check_and_bind_my_tank() -> void:
	if not spawned_tanks:
		return
	var my_id := Network.get_unique_id()
	var my_tank_name := "Tank_%d" % my_id
	var t := spawned_tanks.get_node_or_null(my_tank_name) as Tank
	if t:
		if t.name.begins_with("Tank_"):
			var id_str := t.name.trim_prefix("Tank_")
			if id_str.is_valid_int():
				t.peer_id = id_str.to_int()
		_bind_local_tank(t)

func _get_spawn_transform_for_peer(peer_id: int) -> Transform3D:
	var slot := _get_or_assign_spawn_slot(peer_id)
	if spawn_points_container and spawn_points_container.get_child_count() > 0:
		var child_cnt := spawn_points_container.get_child_count()
		var point_idx := slot % child_cnt
		var marker := spawn_points_container.get_child(point_idx) as Marker3D
		if marker:
			return marker.global_transform

	if spawn_marker:
		return spawn_marker.global_transform
	return Transform3D.IDENTITY

func _get_team_for_peer(peer_id: int) -> int:
	var info := Network.get_player_info(peer_id)
	if info:
		return info.team_id
	return (peer_id - 1) % TEAM_COLORS.size()

func _on_lan_game_started() -> void:
	if lan_menu:
		lan_menu.set_menu_visible(false)

# --- Обработка падения и респавн ---

func _on_kill_volume_body_entered(body: Node3D) -> void:
	if body is Tank:
		var t := body as Tank
		t.fell_into_void.emit()

		if Network.is_multiplayer_active():
			# В мультиплеере только сервер выполняет респавн
			if Network.is_server():
				var spawn_tf := _get_spawn_transform_for_peer(t.peer_id)
				t.respawn(spawn_tf)
		else:
			# Одиночный режим
			if t == tank:
				_respawn_tank()
			elif t == dummy_tank and dummy_spawn_marker:
				dummy_tank.respawn(dummy_spawn_marker.global_transform)

func _respawn_tank() -> void:
	if _active_local_tank and spawn_marker:
		_active_local_tank.respawn(spawn_marker.global_transform)
		if camera:
			camera.global_position = spawn_marker.global_position + camera.target_offset

func _respawn_all() -> void:
	if Network.is_multiplayer_active():
		if Network.is_server() and spawned_tanks:
			for child in spawned_tanks.get_children():
				if child is Tank:
					var t := child as Tank
					var spawn_tf := _get_spawn_transform_for_peer(t.peer_id)
					t.respawn(spawn_tf)
	else:
		_respawn_tank()
		if dummy_tank and dummy_spawn_marker:
			dummy_tank.respawn(dummy_spawn_marker.global_transform)
