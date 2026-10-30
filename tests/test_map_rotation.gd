extends Node

var _failures: int = 0
var _network_sandbox: TestSandbox
var _client_ready: bool = false
var _acknowledged: bool = false

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--rotation-server" in args or "--rotation-client" in args:
		await _test_network("--rotation-server" in args)
		return
	# Все доступные арены должны участвовать в выборе, кроме предыдущей.
	var rules := MatchRules.new()
	seed(20261026)
	for previous in MatchRules.MAP_SCENES:
		var seen: Dictionary = {}
		for i in range(200):
			var chosen := rules.pick_random_map(previous)
			_check(chosen != previous, "Consecutive maps must differ")
			_check(MatchRules.MAP_SCENES.has(chosen), "Map must exist in registry")
			seen[chosen] = true
		_check(seen.size() == MatchRules.MAP_SCENES.size() - 1, "Every other map is eligible")

	# Оба лобби содержат только информацию об автоматическом выборе.
	for path in ["res://lobby/lobby.tscn", "res://lobby/lobby_screen.tscn"]:
		var screen := (load(path) as PackedScene).instantiate()
		add_child(screen)
		_check(screen.find_child("OptMap", true, false) == null, "No map selector in " + path)
		_check(screen.find_child("LblMapRotation", true, false) != null, "Rotation hint in " + path)
		screen.queue_free()
	await get_tree().process_frame

	var sandbox := (load("res://maps/test_sandbox.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(sandbox)
	await get_tree().process_frame
	var controller := sandbox.match_controller
	controller.set_process(false)

	# Проверка настоящей загрузки всех арен и удаления старой геометрии из дерева.
	for map_name in MatchRules.MAP_SCENES:
		var old_arena := sandbox.current_arena
		sandbox.s2c_load_map(map_name)
		_check(not old_arena.is_inside_tree(), "Old arena leaves scene immediately")
		_check(sandbox.map_container.get_child_count() == 1, "Only one arena remains")
		_check(sandbox.current_arena.scene_file_path == MatchRules.MAP_SCENES[map_name], "Correct map scene")
		_check(controller.spawn_points_container == sandbox.spawn_points_container, "Spawns follow new arena")
		_check(Game.rules.selected_map == map_name, "Selected map is synchronized")
		await get_tree().process_frame

	# Невалидная карта из одиночных настроек не влияет на случайный старт матча.
	Game.rules.selected_map = "invalid_saved_map"
	controller.start_new_match()
	_check(MatchRules.MAP_SCENES.has(Game.rules.selected_map), "First match map is random and valid")
	for i in range(20):
		var previous := Game.rules.selected_map
		controller.last_round_winner_id = 1
		controller._server_prepare_round()
		_check(Game.rules.selected_map != previous, "Victory changes map")
		_check(sandbox.current_arena.scene_file_path == MatchRules.MAP_SCENES[Game.rules.selected_map], "New map loaded before draft")
		await get_tree().process_frame

	var draw_map := Game.rules.selected_map
	var draw_arena := sandbox.current_arena
	controller.last_round_winner_id = -1
	controller._server_prepare_round()
	_check(Game.rules.selected_map == draw_map and sandbox.current_arena == draw_arena, "Draw keeps map")
	controller.start_new_match()
	_check(Game.rules.selected_map != draw_map, "Rematch excludes last played map")

	sandbox.queue_free()
	await get_tree().process_frame
	print("MAP ROTATION: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)

# Запускается двумя процессами с --rotation-server и --rotation-client.
func _test_network(server: bool) -> void:
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(2))
	_network_sandbox = (load("res://maps/test_sandbox.tscn") as PackedScene).instantiate() as TestSandbox
	_network_sandbox.name = "Arena"
	add_child(_network_sandbox)
	await get_tree().process_frame
	_network_sandbox.match_controller.set_process(false)
	if not server:
		_network_sandbox._set_solo_tanks_active(false)
		Network.connected_to_server.connect(func(): _report_ready.rpc_id(1), CONNECT_DEFERRED)
		_check(Network.join_host("127.0.0.1", 17089) == OK, "Client connects")
		return
	_check(Network.create_host(17089) == OK, "Host creates server")
	while not _client_ready or Network.players.size() < 2:
		await get_tree().process_frame
	var controller := _network_sandbox.match_controller
	controller.start_new_match()
	await _verify_remote()
	for i in range(12):
		var previous := Game.rules.selected_map
		controller.last_round_winner_id = 1
		controller._server_prepare_round()
		_check(previous != Game.rules.selected_map, "Server changes arena after victory")
		await _verify_remote()
	controller.last_round_winner_id = -1
	var previous := Game.rules.selected_map
	controller._server_prepare_round()
	_check(previous == Game.rules.selected_map, "Server preserves arena after draw")
	await _verify_remote()
	controller.start_new_match()
	_check(previous != Game.rules.selected_map, "Server changes arena for rematch")
	await _verify_remote()
	_finish_remote.rpc(_failures)
	print("NETWORK MAP ROTATION: %d failures" % _failures)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _failures == 0 else 1)

func _verify_remote() -> void:
	_acknowledged = false
	_check(_network_sandbox.current_arena.scene_file_path == MatchRules.MAP_SCENES[Game.rules.selected_map], "Server loaded selected arena")
	_verify_snapshot.rpc(Game.rules.selected_map)
	while not _acknowledged:
		await get_tree().process_frame

@rpc("any_peer", "reliable")
func _report_ready() -> void:
	_client_ready = true

@rpc("authority", "reliable")
func _verify_snapshot(expected_map: String) -> void:
	_check(Game.rules.selected_map == expected_map, "Client receives same map as host")
	_check(_network_sandbox.current_arena.scene_file_path == MatchRules.MAP_SCENES[expected_map], "Client loads same arena as host")
	_check(_network_sandbox.map_container.get_child_count() == 1, "Client has exactly one arena")
	_check(_network_sandbox.match_controller.spawn_points_container == _network_sandbox.current_arena.spawn_points_container, "Client uses current arena spawns")
	_acknowledge.rpc_id(1, _failures)

@rpc("any_peer", "reliable")
func _acknowledge(client_failures: int) -> void:
	_failures += client_failures
	_acknowledged = true

@rpc("authority", "reliable")
func _finish_remote(server_failures: int) -> void:
	print("CLIENT MAP ROTATION: %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 and server_failures == 0 else 1)
