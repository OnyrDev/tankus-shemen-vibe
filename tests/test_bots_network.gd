extends Node

var _failures: int = 0
var _server: bool = true
var _client_ready: bool = false
var _acknowledged: bool = false
var _client_done: bool = false
var _sandbox: TestSandbox
var _winner: int = -1000

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	_server = "--bots-client" not in OS.get_cmdline_user_args()
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit(2))
	Game.rules = MatchRules.new()
	Game.is_in_match = false
	if _server:
		Game.rules.bot_count = 8
		Game.rules.bot_difficulty = 2
	_sandbox = preload("res://maps/test_sandbox.tscn").instantiate() as TestSandbox
	_sandbox.name = "Arena"
	add_child(_sandbox)
	await get_tree().process_frame
	_sandbox.match_controller.set_process(false)
	if not _server:
		_sandbox._set_solo_tanks_active(false)
		Network.connected_to_server.connect(_on_connected, CONNECT_DEFERRED)
		_check(Network.join_host("127.0.0.1", 17210) == OK, "Client connects")
		return
	_check(Network.create_host(17210) == OK, "Host starts")
	while not _client_ready:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(Network.players.size() == 8 and Network.get_human_player_count() == 2, "Human replaces one autofill bot")
	_check(_sandbox.match_controller._get_all_tanks().size() == 8, "Host spawns eight participants")
	await _verify_remote(0)
	var controller := _sandbox.match_controller
	controller.start_new_match()
	_check(controller._pending_draft_peers.size() == 2, "Only two humans need draft input")
	await _verify_remote(1)
	_sandbox.s2c_load_map.rpc("sky_courtyard")
	controller._server_reset_and_place_tanks()
	controller._pending_draft_peers.clear()
	controller.s2c_close_all_drafts.rpc()
	controller._server_start_combat()
	var shots := [0]
	for tank in controller._get_all_tanks():
		if tank.peer_id <= -1000:
			tank.weapon.shot_fired.connect(func(_projectile): shots[0] += 1)
		else:
			tank.input.enabled = false
	await get_tree().create_timer(3.0).timeout
	_check(shots[0] > 0, "Server bots fire in a real ENet match")
	for tank in controller._get_all_tanks():
		if tank.peer_id <= -1000:
			_check(tank.net_sync._last_received_input == 0, "Client cannot send input for bots")
	controller._server_end_round(_winner)
	await _verify_remote(2)
	# Возврат к настройкам позволяет уменьшить состав и изменить сложность.
	Game.reset_match()
	Game.rules.bot_count = 2
	Game.rules.bot_difficulty = 0
	Game.rules.is_team_mode = true
	Network.update_match_rules_from_host(Game.rules.to_dict())
	await get_tree().process_frame
	await _verify_remote(3)
	_check(_sandbox.match_controller._get_all_tanks().size() == 4, "Removing bots despawns their tanks")
	Game.rules.bot_count = 8
	Network.update_match_rules_from_host(Game.rules.to_dict())
	await get_tree().process_frame
	await _verify_remote(4)
	_finish_client.rpc(_failures)
	while not _client_done or Network.get_human_player_count() != 1:
		await get_tree().process_frame
	for frame in range(30):
		if _sandbox.match_controller._get_all_tanks().size() == 8:
			break
		await get_tree().process_frame
	_check(Network.players.size() == 8, "Autofill restores slot after client leaves lobby")
	_check(_sandbox.match_controller._get_all_tanks().size() == 8, "Restored bot also spawns on host")
	print("BOTS NETWORK HOST: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)

func _on_connected() -> void:
	while Network.players.size() != 8 or Game.rules.bot_count != 8:
		await get_tree().process_frame
	_ready_on_server.rpc_id(1)

@rpc("any_peer", "reliable")
func _ready_on_server() -> void:
	_client_ready = true

func _verify_remote(phase: int) -> void:
	_acknowledged = false
	_verify.rpc(phase, Network._get_players_data_array())
	while not _acknowledged:
		await get_tree().process_frame

@rpc("authority", "reliable")
func _verify(phase: int, expected: Array) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if phase >= 3:
		await get_tree().create_timer(0.1).timeout
	_check(Network.players.size() == expected.size(), "Client sees same roster size")
	_check(_sandbox.match_controller._get_all_tanks().size() == expected.size(), "Client sees same spawned tank count")
	for data in expected:
		var player := Network.get_player_info(data.peer_id)
		_check(player != null and player.is_bot == data.is_bot and player.bot_difficulty == data.bot_difficulty, "Bot metadata matches host")
		if player and player.is_bot:
			var tank := _sandbox.spawned_tanks.get_node_or_null("Tank_%d" % player.peer_id) as Tank
			_check(tank != null and tank.net_sync.bot_brain == null, "Client never simulates bot AI")
			if phase >= 3 and tank:
				_check(tank.team_id == player.team_id, "Bot team replicates to clients")
			if phase == 1 and tank:
				_check(tank.build.cards.size() == 1, "Bot draft cards replicate")
	if phase == 1:
		var bot := _sandbox.spawned_tanks.get_node("Tank_%d" % _winner) as Tank
		bot.net_sync.c2s_send_inputs.rpc_id(1, [[999, 0, Vector3.RIGHT, Vector3.ZERO, 0]])
	if phase == 2:
		_check(Network.get_player_info(_winner).round_wins == 1, "Bot round score replicates")
	if phase == 3:
		_check(Game.rules.bot_count == 2 and Game.rules.bot_difficulty == 0, "Changed bot settings replicate")
		_check(_sandbox.lobby.opt_bot_count.selected == 2 and _sandbox.lobby.opt_bot_difficulty.selected == 0, "Client lobby shows bot settings")
		_check(_sandbox.lobby.opt_bot_count.disabled, "Only host edits bots")
	_ack.rpc_id(1, _failures)

@rpc("any_peer", "reliable")
func _ack(client_failures: int) -> void:
	_failures = maxi(_failures, client_failures)
	_acknowledged = true

@rpc("authority", "reliable")
func _finish_client(server_failures: int) -> void:
	print("BOTS NETWORK CLIENT: %d failures" % _failures)
	_client_finished.rpc_id(1)
	await get_tree().create_timer(0.1).timeout
	Network.disconnect_session()
	get_tree().quit(1 if _failures + server_failures > 0 else 0)

@rpc("any_peer", "reliable")
func _client_finished() -> void:
	_client_done = true
