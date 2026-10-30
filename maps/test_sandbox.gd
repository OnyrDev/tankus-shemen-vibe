class_name TestSandbox
extends Node3D

## Скрипт песочницы и арены TANKUS (Фаза 6: 4 Арены, интерактивная физика и спавн-менеджер).
## Поддерживает одиночное тестирование, сетевой мультиплеер, динамическую смену карт
## (Sky Courtyard, Iceworks, Pendulum Yard, Shift) и разведение спавнов.

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

const MAP_SCENES: Dictionary = MatchRules.MAP_SCENES

@onready var map_container: Node3D = get_node_or_null("MapContainer")
var current_arena: BaseArena = null

@onready var tank: Tank = get_node_or_null("Tank")
@onready var dummy_tank: Tank = get_node_or_null("DummyTank")
@onready var camera: TPSCamera = $TPSCamera
@onready var hud: HUD = get_node_or_null("HUD")
@onready var card_draft: CardDraft = get_node_or_null("CardDraft")

@onready var lan_menu: LANMenu = get_node_or_null("LANMenu")
@onready var spawned_tanks: Node3D = get_node_or_null("SpawnedTanks")
@onready var projectiles: Node3D = get_node_or_null("Projectiles")
@onready var tank_spawner: MultiplayerSpawner = get_node_or_null("TankSpawner")
@onready var proj_spawner: MultiplayerSpawner = get_node_or_null("ProjSpawner")

@onready var match_controller: MatchController = get_node_or_null("MatchController")
@onready var tank_overhead_manager: TankOverheadManager = get_node_or_null("TankOverheadManager")
@onready var scoreboard: Scoreboard = get_node_or_null("Scoreboard")
@onready var lobby: Lobby = get_node_or_null("Lobby")
@onready var pause_menu: CanvasLayer = get_node_or_null("PauseMenu")

var spawn_points_container: Node3D = null
var kill_volume: Area3D = null
var _active_local_tank: Tank = null
var _peer_spawn_slots: Dictionary = {} # peer_id: int -> slot_index: int

func _ready() -> void:
	# Загружаем выбранную карту арены
	load_map(Game.rules.selected_map)

	_setup_network_signals()
	_setup_phase5_systems()

	if pause_menu:
		pause_menu.respawn_requested.connect(_respawn_all)
		pause_menu.open_lan_requested.connect(func():
			if Network.is_multiplayer_active() or Network.is_host:
				get_tree().change_scene_to_file("res://lobby/lobby_screen.tscn")
			elif lan_menu:
				lan_menu.set_menu_visible(true)
		)

	if spawned_tanks:
		spawned_tanks.child_entered_tree.connect(_on_spawned_tank_entered)

	# Если активна сетевая сессия хоста или клиента
	if Network.is_multiplayer_active() or Network.is_host:
		if lan_menu:
			lan_menu.set_menu_visible(false)
		if lobby:
			lobby.close_lobby()
		_set_solo_tanks_active(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		if Network.is_host:
			for peer_id in Network.players.keys():
				_server_spawn_tank_for_peer(peer_id)
			if match_controller:
				match_controller.start_new_match()
		else:
			_check_and_bind_my_tank()
	else:
		# По умолчанию настраиваем одиночный танк
		_setup_solo_mode()
		if Game.is_solo_practice:
			if lan_menu:
				lan_menu.set_menu_visible(false)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Динамическая загрузка и переключение карты арены
func load_map(map_name: String) -> void:
	if not MAP_SCENES.has(map_name):
		map_name = "sky_courtyard"

	var scene_path: String = MAP_SCENES[map_name]
	var packed := load(scene_path) as PackedScene
	if not packed:
		return

	if not map_container:
		map_container = Node3D.new()
		map_container.name = "MapContainer"
		add_child(map_container)
		move_child(map_container, 0)

	# Очищаем предыдущую арену
	current_arena = null
	for child in map_container.get_children():
		map_container.remove_child(child)
		child.queue_free()

	current_arena = packed.instantiate() as BaseArena
	map_container.add_child(current_arena)

	spawn_points_container = current_arena.spawn_points_container if current_arena.spawn_points_container else current_arena.get_node_or_null("SpawnPoints")
	kill_volume = current_arena.kill_volume if current_arena.kill_volume else current_arena.get_node_or_null("KillVolume")

	_ensure_bot_navigation()
	if current_arena:
		current_arena.tank_fell.connect(_on_kill_volume_body_entered)

	if match_controller:
		match_controller.spawn_points_container = spawn_points_container

	if not Network.is_multiplayer_active() and not Network.is_host:
		if tank:
			tank.spawn_point = _get_spawn_transform_for_peer(1)
		if dummy_tank:
			dummy_tank.spawn_point = _get_spawn_transform_for_peer(2)

@rpc("authority", "reliable", "call_local")
func s2c_load_map(map_name: String) -> void:
	Game.rules.selected_map = map_name
	load_map(map_name)

func _setup_phase5_systems() -> void:
	if match_controller:
		match_controller.spawned_tanks_container = spawned_tanks
		match_controller.spawn_points_container = spawn_points_container
		match_controller.camera = camera
		match_controller.hud = hud
		match_controller.card_draft = card_draft
		match_controller.lobby = lobby
		match_controller.map_change_requested.connect(_on_map_change_requested)
		match_controller.returned_to_lobby.connect(_on_returned_to_lobby)
		match_controller.match_started.connect(func():
			if lobby:
				lobby.close_lobby()
		)

	if tank_overhead_manager and spawned_tanks:
		tank_overhead_manager.setup_container(spawned_tanks)

	if scoreboard and spawned_tanks:
		scoreboard.tanks_container = spawned_tanks

	if lobby:
		lobby.match_start_requested.connect(_on_match_start_requested)
		lobby.lobby_left.connect(_on_lobby_left)

	if lan_menu:
		lan_menu.session_joined.connect(_on_session_joined)

func _setup_network_signals() -> void:
	Network.server_created.connect(_on_server_created)
	Network.server_closed.connect(_on_session_ended)
	Network.connected_to_server.connect(_on_connected_to_server)
	Network.peer_connected.connect(_on_peer_connected)
	Network.player_list_updated.connect(_on_roster_updated)
	Network.peer_disconnected.connect(_on_peer_disconnected)
	Network.server_disconnected.connect(_on_session_ended)

	if lan_menu:
		lan_menu.game_started.connect(_on_lan_game_started)

func _setup_solo_mode() -> void:
	var tf1 := _get_spawn_transform_for_peer(1)
	if tank and camera:
		_bind_local_tank(tank)
		tank.peer_id = 1
		tank.team_id = 0
		tank.spawn_point = tf1
		tank.global_transform = tf1
		if not tank.died.is_connected(_on_solo_tank_died):
			tank.died.connect(_on_solo_tank_died)

	var tf2 := _get_spawn_transform_for_peer(2)
	if dummy_tank:
		dummy_tank.peer_id = 2
		dummy_tank.team_id = 1
		dummy_tank.set_team_color(Color(0.95, 0.25, 0.25))
		if dummy_tank.input:
			dummy_tank.input.enabled = false
		dummy_tank.spawn_point = tf2
		dummy_tank.global_transform = tf2
		if not dummy_tank.died.is_connected(_on_dummy_tank_died):
			dummy_tank.died.connect(_on_dummy_tank_died)

	if tank_overhead_manager and dummy_tank:
		tank_overhead_manager._create_overhead_for_tank(dummy_tank)

func _bind_local_tank(target_tank: Tank) -> void:
	_active_local_tank = target_tank
	if target_tank.input:
		target_tank.input.enabled = true
	if target_tank.net_sync:
		target_tank.net_sync.set_peer_id(target_tank.peer_id)
	if camera:
		camera.setup_target(target_tank)
	if hud and target_tank:
		hud.bind_to_tank(target_tank)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if pause_menu and pause_menu.is_open():
				pause_menu.handle_cancel()
				get_viewport().set_input_as_handled()
				return
			if card_draft and card_draft.visible:
				card_draft.close_draft()
				get_viewport().set_input_as_handled()
				return
			if lan_menu and lan_menu.visible:
				lan_menu.set_menu_visible(false)
				get_viewport().set_input_as_handled()
				return
			if lobby and lobby.visible:
				lobby.close_lobby()
				get_viewport().set_input_as_handled()
				return
			if pause_menu:
				pause_menu.open()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_F1 or event.keycode == KEY_BACKSPACE:
			_respawn_all()
		elif event.keycode == KEY_F2:
			if card_draft and _active_local_tank:
				if card_draft.visible:
					card_draft.close_draft()
				else:
					card_draft.open_draft(_active_local_tank)

# --- Сетевой спавн танков ---

func _on_server_created() -> void:
	_set_solo_tanks_active(false)
	_sync_roster_tanks()

func _on_connected_to_server() -> void:
	_set_solo_tanks_active(false)
	_check_and_bind_my_tank()

func _on_peer_connected(_peer_id: int) -> void:
	if Network.is_server():
		_sync_roster_tanks.call_deferred()

func _on_roster_updated() -> void:
	if Network.is_host:
		_sync_roster_tanks.call_deferred()

func _ensure_bot_navigation() -> void:
	if Network.is_server() and Game.rules.bot_count > 0 and current_arena and not current_arena.has_node("BotNavigation"):
		var navigation := BotNavigation.new()
		navigation.name = "BotNavigation"
		current_arena.add_child(navigation)

func _sync_roster_tanks() -> void:
	if not Network.is_host or not spawned_tanks:
		return
	_ensure_bot_navigation()
	for child in spawned_tanks.get_children():
		if child is Tank and not Network.players.has(child.peer_id):
			_server_remove_tank_for_peer(child.peer_id)
	for info in Network.get_all_players():
		_server_spawn_tank_for_peer(info.peer_id)
		var current := spawned_tanks.get_node_or_null("Tank_%d" % info.peer_id) as Tank
		if current:
			var slot := _get_or_assign_spawn_slot(info.peer_id)
			var color_index: int = info.team_id - 1 if Game.rules.is_team_mode else slot
			var team: int = info.team_id if Game.rules.is_team_mode else slot + 1
			current.setup_network(info.peer_id, team, TEAM_COLORS[posmod(color_index, TEAM_COLORS.size())])

func _on_peer_disconnected(peer_id: int) -> void:
	if Network.is_server():
		_server_remove_tank_for_peer(peer_id)

func _on_session_ended() -> void:
	_peer_spawn_slots.clear()
	if spawned_tanks:
		for child in spawned_tanks.get_children():
			child.queue_free()

	_set_solo_tanks_active(true)
	if tank:
		_bind_local_tank(tank)
		_respawn_tank()
	if dummy_tank:
		var tf2 := dummy_tank.spawn_point if dummy_tank.spawn_point != Transform3D.IDENTITY else _get_spawn_transform_for_peer(2)
		dummy_tank.respawn(tf2)
		dummy_tank.peer_id = 2
		dummy_tank.team_id = 1
		dummy_tank.set_team_color(Color(0.95, 0.25, 0.25))
		if dummy_tank.input:
			dummy_tank.input.enabled = false

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

	if peer_id == 1:
		_peer_spawn_slots[1] = 0
		return 0

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

	t.died.connect(func(killer): _on_tank_died(t, killer))

	spawned_tanks.add_child(t, true)

	t.global_transform = spawn_tf
	t.spawn_point = spawn_tf
	var info := Network.get_player_info(peer_id)
	var team := info.team_id if info and Game.rules.is_team_mode else slot + 1
	if Game.rules.is_team_mode:
		team_col = TEAM_COLORS[posmod(team - 1, TEAM_COLORS.size())]
	t.setup_network(peer_id, team, team_col)

func _on_tank_died(dead_tank: Tank, _killer: Node) -> void:
	if dead_tank.peer_id == Network.get_unique_id() and match_controller:
		match_controller.on_local_tank_died()

	if not Game.is_in_match and Network.is_server():
		var timer := get_tree().create_timer(2.0)
		timer.timeout.connect(func():
			if is_instance_valid(dead_tank):
				var spawn_tf := _get_spawn_transform_for_peer(dead_tank.peer_id)
				dead_tank.respawn(spawn_tf)
		)

func _on_dummy_tank_died(_killer: Node) -> void:
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(func():
		if is_instance_valid(dummy_tank) and dummy_tank.is_inside_tree() and (Game.is_solo_practice or not Network.is_multiplayer_active()):
			var tf2 := dummy_tank.spawn_point if dummy_tank.spawn_point != Transform3D.IDENTITY else _get_spawn_transform_for_peer(2)
			dummy_tank.respawn(tf2)
			dummy_tank.peer_id = 2
			dummy_tank.team_id = 1
			dummy_tank.set_team_color(Color(0.95, 0.25, 0.25))
			if dummy_tank.input:
				dummy_tank.input.enabled = false
	)

func _on_solo_tank_died(_killer: Node) -> void:
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(tank) and tank.is_inside_tree() and (Game.is_solo_practice or not Network.is_multiplayer_active()):
			_respawn_tank()
	)

func _on_session_joined() -> void:
	if lobby:
		lobby.open_lobby()

func _on_match_start_requested() -> void:
	if lobby:
		lobby.close_lobby()

	if match_controller and (Network.is_host or not Network.is_multiplayer_active()):
		match_controller.start_new_match()

func _on_map_change_requested(map_name: String) -> void:
	if multiplayer.has_multiplayer_peer():
		s2c_load_map.rpc(map_name)
	else:
		s2c_load_map(map_name)

func _on_lobby_left() -> void:
	Game.return_to_main_menu()

func _on_returned_to_lobby() -> void:
	if multiplayer.has_multiplayer_peer() and Network.is_multiplayer_active():
		s2c_return_to_lobby.rpc()
	else:
		_return_to_lobby_local()

@rpc("authority", "reliable", "call_local")
func s2c_return_to_lobby() -> void:
	_return_to_lobby_local()

func _return_to_lobby_local() -> void:
	Game.is_in_match = false
	get_tree().change_scene_to_file("res://lobby/lobby_screen.tscn")

func _server_remove_tank_for_peer(peer_id: int) -> void:
	_peer_spawn_slots.erase(peer_id)
	if not Network.is_server() or not spawned_tanks:
		return

	var node_name := "Tank_%d" % peer_id
	var t := spawned_tanks.get_node_or_null(node_name)
	if t:
		if projectiles:
			for child in projectiles.get_children():
				if child is Projectile and child.shooter == t:
					child.queue_free()
		spawned_tanks.remove_child(t)
		t.queue_free()

func _on_spawned_tank_entered(node: Node) -> void:
	if node is Tank:
		var t := node as Tank
		if t.name.begins_with("Tank_"):
			var id_str := t.name.trim_prefix("Tank_")
			if id_str.is_valid_int():
				t.peer_id = id_str.to_int()

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
		var markers: Array[Marker3D] = []
		for child in spawn_points_container.get_children():
			if child is Marker3D:
				markers.append(child)
		return SpawnManager.get_fallback_transform(slot, markers)

	return Transform3D.IDENTITY

func _on_lan_game_started() -> void:
	if lan_menu:
		lan_menu.set_menu_visible(false)

# --- Обработка падения и респавн ---

func _on_kill_volume_body_entered(body: Node3D) -> void:
	if body is Tank:
		var t := body as Tank
		t.fell_into_void.emit()

		if Network.is_multiplayer_active():
			if Network.is_server():
				var spawn_tf := _get_spawn_transform_for_peer(t.peer_id)
				_handle_void_fall(t, spawn_tf)
		else:
			if t == tank:
				var spawn_tf := _get_spawn_transform_for_peer(1)
				_handle_void_fall(t, spawn_tf)
			elif t == dummy_tank:
				var tf2 := _get_spawn_transform_for_peer(2)
				_handle_void_fall(t, tf2)
			else:
				var spawn_tf := _get_spawn_transform_for_peer(t.peer_id if t.peer_id != 0 else 1)
				_handle_void_fall(t, spawn_tf)

func _handle_void_fall(t: Tank, spawn_tf: Transform3D) -> void:
	if not t or not t.is_active:
		return
	t.respawn(spawn_tf, false, 5.0)
	if t == _active_local_tank:
		if Game:
			Game.shake_camera(0.25)
		if camera and t.is_active:
			camera.setup_target(t)

func _respawn_tank() -> void:
	if _active_local_tank:
		var spawn_tf := _get_spawn_transform_for_peer(1)
		_active_local_tank.respawn(spawn_tf)
		if camera:
			camera.setup_target(_active_local_tank)

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
		if dummy_tank:
			var tf2 := _get_spawn_transform_for_peer(2)
			dummy_tank.respawn(tf2)
