extends Node3D

var _failures: int = 0
var _sandbox: TestSandbox

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	seed(42)
	Game.is_in_match = false
	Game.rules = MatchRules.new()
	Network.players[1] = PlayerInfo.new(1, "Host", 1)
	Game.rules.bot_count = 3
	Game.rules.bot_difficulty = 2
	Network._reconcile_bots()
	_check(Network.players.size() == 4, "Host can play alone with three bots")
	for player in Network.get_all_players():
		if player.is_bot:
			_check(player.peer_id <= -1000 and player.peer_id != -1, "Bot IDs cannot collide with draw or human IDs")
			var copy := PlayerInfo.from_dict(player.to_dict())
			_check(copy.is_bot and copy.is_ready and copy.bot_difficulty == 2, "Bot info round-trips for clients")
	var copy_rules := MatchRules.new()
	copy_rules.load_dict(Game.rules.to_dict())
	_check(copy_rules.bot_count == 3 and copy_rules.bot_difficulty == 2, "Bot settings synchronize")
	copy_rules.load_dict({"bot_count": 100, "bot_difficulty": -3})
	_check(copy_rules.bot_count == 8 and copy_rules.bot_difficulty == 0, "Invalid bot settings are clamped")
	Game.rules.bot_count = 8
	Network._reconcile_bots()
	_check(Network.players.size() == 8, "Autofill creates at most eight participants")
	Network.players[42] = PlayerInfo.new(42, "Client", 1)
	Network._reconcile_bots()
	_check(Network.players.size() == 8 and Network.get_human_player_count() == 2, "Joining human replaces a bot")
	Network.players.erase(42)
	Network._reconcile_bots()
	_check(Network.players.size() == 8, "Autofill restores a free lobby slot")
	Game.rules.is_team_mode = true
	Network._balance_bot_teams()
	var teams := {1: 0, 2: 0}
	for player in Network.get_all_players():
		teams[player.team_id] += 1
	_check(teams[1] == 4 and teams[2] == 4, "Bot teams are balanced around human players")
	Network.is_host = true
	Network.set_bot_team(-1000, 1)
	Network._reconcile_bots()
	_check(Network.players[-1000].team_id == 1, "Manual bot team survives applying unchanged lobby settings")
	Network.is_host = false
	for path in ["res://lobby/lobby.tscn", "res://lobby/lobby_screen.tscn"]:
		var screen := (load(path) as PackedScene).instantiate()
		add_child(screen)
		_check(screen.opt_bot_count.item_count == 9, "Lobby offers count and autofill")
		_check(screen.opt_bot_difficulty.item_count == 3, "Lobby offers three difficulties")
		await get_tree().process_frame
		_check(screen.opt_bot_count.get_global_rect().end.x <= get_viewport().get_visible_rect().size.x, "Bot settings fit viewport")
		screen.queue_free()
	await get_tree().process_frame
	# Используем настоящую арену, контроллер раундов и серверную симуляцию без сокетов.
	Game.rules.bot_count = 3
	Game.rules.is_team_mode = false
	Network._reconcile_bots()
	_sandbox = preload("res://maps/test_sandbox.tscn").instantiate() as TestSandbox
	add_child(_sandbox)
	await get_tree().process_frame
	_sandbox._set_solo_tanks_active(false)
	for player in Network.get_all_players():
		_sandbox._server_spawn_tank_for_peer(player.peer_id)
	var controller := _sandbox.match_controller
	controller.set_process(false)
	controller.start_new_match()
	_check(controller._pending_draft_peers == [1], "Only human drafts are awaited")
	var bots: Array[Tank] = []
	for tank in controller._get_all_tanks():
		if tank.peer_id <= -1000:
			bots.append(tank)
			_check(tank.build.cards.size() == 1, "Bot chooses a valid draft card immediately")
	_check(bots.size() == 3, "All configured bots have actual tank instances")
	controller._server_start_combat()
	var first := bots[0]
	var ally := bots[1]
	Game.rules.is_team_mode = true
	first.team_id = 1
	ally.team_id = 1
	var enemy := bots[2]
	enemy.team_id = 2
	first.net_sync.bot_brain._choose_target()
	_check(first.net_sync.bot_brain.target != ally, "AI never selects a teammate")
	var hp := ally.health.current_health
	_check(not ally.health.take_damage(20, first) and ally.health.current_health == hp, "Friendly fire disabled protects teammates")
	Game.rules.friendly_fire = true
	_check(ally.health.take_damage(20, first), "Friendly fire setting is respected")
	Game.rules.friendly_fire = false
	Game.rules.is_team_mode = false
	# Хост — неподвижная цель; проверяем, что решения дают реальное движение и выстрелы.
	var host := _sandbox.spawned_tanks.get_node("Tank_1") as Tank
	host.input.enabled = false
	var initial_position := first.position
	var shots := [0]
	for bot in bots:
		bot.weapon.shot_fired.connect(func(_projectile): shots[0] += 1)
	for frame in range(240):
		await get_tree().physics_frame
	_check(first.position.distance_to(initial_position) > 0.5, "Bot moves through actual physics")
	_check(shots[0] > 0, "Bots aim and fire real projectiles")
	var navigation := _sandbox.current_arena.get_node("BotNavigation") as BotNavigation
	_check(navigation.is_built and navigation.graph.get_point_count() > 20, "Arena navigation graph is built")
	_check(navigation.find_path(host.position, first.position).size() > 0, "Bot navigation finds arena routes")
	# Победа бота должна учитываться как победа, а не ничья.
	controller.current_state = MatchController.State.PLAYING
	controller._server_end_round(first.peer_id)
	_check(Network.get_player_info(first.peer_id).round_wins == 1, "Bot victory increments round score")
	_check(controller.last_round_winner_id == first.peer_id, "Bot winner is distinct from draw")
	var previous_cards := first.build.cards.size()
	controller._server_prepare_round()
	_check(controller._pending_draft_peers == [1], "Bot drafts never delay next rounds")
	_check(first.build.cards.size() == previous_cards, "Winning bot does not draft after victory")
	controller._set_all_tanks_frozen(true)
	for map_name in MatchRules.MAP_SCENES:
		_sandbox.load_map(map_name)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var nav := _sandbox.current_arena.get_node("BotNavigation") as BotNavigation
		_check(nav.is_built and nav.graph.get_point_count() > 20, "Navigation exists on " + map_name)
		var spawns := _sandbox.current_arena.get_spawn_points()
		var reachable := 0
		for spawn in spawns:
			var route := nav.find_path(spawns[0].global_position, spawn.global_position)
			if not route.is_empty() and route[-1].distance_to(spawn.global_position) < 3.0:
				reachable += 1
		print("BOT NAV ", map_name, ": ", nav.graph.get_point_count(), " nodes; ", reachable, "/", spawns.size(), " spawns reachable")
		_check(reachable >= 2, "Bots can reach other spawn areas on " + map_name)
	Game.rules.bot_count = 0
	Game.is_in_match = false
	Network._reconcile_bots()
	_check(Network.players.size() == 1, "Disabling bots removes bot participants")
	_sandbox.queue_free()
	await get_tree().process_frame
	await _test_solo_difficulties()
	Network.players.clear()
	Game.rules = MatchRules.new()
	Game.reset_match()
	print("BOTS: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)

func _test_solo_difficulties() -> void:
	for level in range(3):
		for projectile in get_tree().get_nodes_in_group("projectiles"):
			projectile.queue_free()
		await get_tree().process_frame
		Network.players.clear()
		Network.players[1] = PlayerInfo.new(1, "Solo", 1)
		Game.is_in_match = false
		Game.rules = MatchRules.new()
		Game.rules.bot_count = 1
		Game.rules.bot_difficulty = level
		Game.rules.target_round_wins = 1
		Network._reconcile_bots()
		var arena := preload("res://maps/test_sandbox.tscn").instantiate() as TestSandbox
		add_child(arena)
		await get_tree().process_frame
		arena._set_solo_tanks_active(false)
		for player in Network.get_all_players():
			arena._server_spawn_tank_for_peer(player.peer_id)
		var controller := arena.match_controller
		controller.set_process(false)
		controller.current_round = 1
		var host := arena.spawned_tanks.get_node("Tank_1") as Tank
		host.input.enabled = false
		Game.is_in_match = true
		controller._server_reset_and_place_tanks()
		controller._server_start_combat()
		var enemy := arena.spawned_tanks.get_node("Tank_-1000") as Tank
		if enemy.net_sync.bot_brain == null:
			enemy.net_sync.bot_brain = TankBotController.new(enemy, level)
		enemy.net_sync.bot_brain._rng.seed = 400 + level
		var shots := [0]
		enemy.weapon.shot_fired.connect(func(_projectile): shots[0] += 1)
		var frame := 0
		while frame < 2700 and controller.current_state == MatchController.State.PLAYING:
			await get_tree().physics_frame
			controller._server_check_round_end_condition()
			frame += 1
		_check(controller.current_state == MatchController.State.MATCH_END, "Solo bot can finish match on difficulty %d" % level)
		_check(Network.get_player_info(-1000).round_wins == 1, "Bot earns match victory on difficulty %d" % level)
		_check(shots[0] > 0, "Solo bot fires real projectiles on difficulty %d" % level)
		print("BOT SOLO ", level, ": finished after ", snappedf(frame / 60.0, 0.1), " simulated seconds")
		arena.queue_free()
		await get_tree().process_frame
