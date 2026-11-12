class_name NetworkManager
extends Node

## Сетевой синглтон-фасад TANKUS.
## Изолирует сетевой транспорт (ENet / MultiplayerPeer) от геймплейного кода,
## управляет сессией подключения, пирами и синхронизацией списка игроков.

signal server_created()
signal server_closed()
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal player_list_updated()
signal player_ready_changed(peer_id: int, is_ready: bool)
signal match_rules_updated()

enum Transport { ENET, STEAM }

const DEFAULT_PORT: int = 7000
const MAX_CLIENTS: int = 8
const MAX_PLAYERS: int = 8
const BOT_ID_BASE: int = -1000

var transport: Transport = Transport.ENET
var players: Dictionary = {} # peer_id: int -> PlayerInfo
var local_player_name: String = "Player"
var local_team_id: int = 1
var local_is_ready: bool = false
var is_host: bool = false

# Локальные параметры A/B-проверки; на правила матча и права клиента не влияют.
var debug_movement_latency_ms: int = 0
var movement_prediction_enabled: bool = true

var _ping_timer: float = 0.0
var _bot_balance_signature: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--movement-latency-ms="):
			debug_movement_latency_ms = clampi(arg.get_slice("=", 1).to_int(), 0, 1000)
		elif arg == "--disable-movement-prediction":
			movement_prediction_enabled = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func get_ping_ms() -> int:
	var my_id: int = get_unique_id()
	if players.has(my_id):
		return players[my_id].ping_ms
	return 0

func is_server() -> bool:
	if not is_multiplayer_active():
		return true # В одиночной игре поведение серверное
	return multiplayer.is_server()

func get_unique_id() -> int:
	if not is_multiplayer_active():
		return 1
	return multiplayer.get_unique_id()

func is_multiplayer_active() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func create_host(port: int = DEFAULT_PORT) -> Error:
	disconnect_session()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		push_error("Network: Не удалось создать ENet сервер на порту %d: %s" % [port, error_string(err)])
		return err

	transport = Transport.ENET
	_start_host_with_peer(peer, 0)
	return OK

func join_host(ip: String, port: int = DEFAULT_PORT) -> Error:
	disconnect_session()

	var clean_ip := ip.strip_edges()
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(clean_ip, port)
	if err != OK:
		push_error("Network: Не удалось подключиться к %s:%d: %s" % [clean_ip, port, error_string(err)])
		return err

	transport = Transport.ENET
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK

func create_host_steam(lobby_id: int) -> Error:
	disconnect_session(false)

	var peer := _instantiate_steam_peer()
	if peer == null:
		return ERR_UNAVAILABLE

	var err: Error = int(peer.call("host_with_lobby", lobby_id)) as Error
	if err != OK:
		push_error("Network: Не удалось запустить SteamMultiplayerPeer для лобби %d: %s" % [lobby_id, error_string(err)])
		return err

	transport = Transport.STEAM
	var host_steam_id: int = SteamService.steam_id if SteamService and SteamService.is_available() else 0
	if SteamService and SteamService.is_available() and not SteamService.persona_name.is_empty() and local_player_name == "Player":
		local_player_name = SteamService.persona_name
	_start_host_with_peer(peer, host_steam_id)
	return OK

func join_host_steam(lobby_id: int) -> Error:
	disconnect_session(false)

	var peer := _instantiate_steam_peer()
	if peer == null:
		return ERR_UNAVAILABLE

	var err: Error = int(peer.call("connect_to_lobby", lobby_id)) as Error
	if err != OK:
		push_error("Network: Не удалось подключиться к Steam лобби %d: %s" % [lobby_id, error_string(err)])
		return err

	transport = Transport.STEAM
	if SteamService and SteamService.is_available() and not SteamService.persona_name.is_empty() and local_player_name == "Player":
		local_player_name = SteamService.persona_name
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK

func _instantiate_steam_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer") or not ClassDB.can_instantiate("SteamMultiplayerPeer"):
		push_error("Network: Класс SteamMultiplayerPeer недоступен (аддон GodotSteam не загружен).")
		return null
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer != null and peer.has_method("set_server_relay"):
		peer.call("set_server_relay", true)
	return peer

func _start_host_with_peer(peer: MultiplayerPeer, host_steam_id: int) -> void:
	multiplayer.multiplayer_peer = peer
	is_host = true
	players.clear()

	var local_info := PlayerInfo.new(1, local_player_name, local_team_id)
	local_info.steam_id = host_steam_id
	players[1] = local_info
	Game.is_in_match = false
	_reconcile_bots()

	server_created.emit()
	player_list_updated.emit()

func disconnect_session(leave_steam_lobby: bool = true) -> void:
	if multiplayer.has_multiplayer_peer():
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer != null and not (peer is OfflineMultiplayerPeer):
			peer.close()
		multiplayer.multiplayer_peer = null

	if leave_steam_lobby and SteamService and SteamService.current_lobby_id != 0:
		SteamService.leave_lobby()

	transport = Transport.ENET
	players.clear()
	_bot_balance_signature.clear()
	is_host = false
	server_closed.emit()

func get_player_info(peer_id: int) -> PlayerInfo:
	return players.get(peer_id, null)

func get_all_players() -> Array:
	return players.values()

# --- Внутренние сетевые сигналы ---

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	if is_server():
		players.erase(id)
		if not Game.is_in_match:
			_reconcile_bots()
		_sync_all_players.rpc(_get_players_data_array())

	peer_disconnected.emit(id)
	player_list_updated.emit()

func _on_connected_to_server() -> void:
	connected_to_server.emit()
	# Клиент регистрирует себя на сервере
	var my_steam_id: int = SteamService.steam_id if (transport == Transport.STEAM and SteamService and SteamService.is_available()) else 0
	var game_ver: String = SteamService.GAME_VERSION if SteamService else ""
	_register_player.rpc_id(1, local_player_name, local_team_id, my_steam_id, game_ver)

func _on_connection_failed() -> void:
	disconnect_session()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	disconnect_session()
	server_disconnected.emit()

func _process(delta: float) -> void:
	if not is_multiplayer_active():
		return

	_ping_timer += delta
	if _ping_timer >= 1.5:
		_ping_timer = 0.0
		if not is_server():
			c2s_ping.rpc_id(1, Time.get_ticks_msec())

func set_local_ready(ready_val: bool) -> void:
	local_is_ready = ready_val
	var my_id := get_unique_id()
	if players.has(my_id):
		players[my_id].is_ready = ready_val
	player_ready_changed.emit(my_id, ready_val)
	player_list_updated.emit()

	if is_server():
		_sync_all_players.rpc(_get_players_data_array())
	else:
		c2s_set_ready.rpc_id(1, ready_val, my_id)

func set_local_team(team_val: int) -> void:
	local_team_id = team_val
	var my_id := get_unique_id()
	if players.has(my_id):
		players[my_id].team_id = clampi(team_val, 1, Game.rules.team_count)
	player_list_updated.emit()

	if is_server():
		if not Game.is_in_match:
			_balance_bot_teams()
		_sync_all_players.rpc(_get_players_data_array())
	else:
		c2s_set_team.rpc_id(1, team_val, my_id)

func set_local_name(new_name: String) -> void:
	var clean := new_name.strip_edges()
	if clean.is_empty():
		return
	local_player_name = clean
	var my_id := get_unique_id()
	if players.has(my_id):
		players[my_id].player_name = clean
	player_list_updated.emit()

	if is_server():
		_sync_all_players.rpc(_get_players_data_array())
	elif is_multiplayer_active():
		c2s_set_name.rpc_id(1, clean, my_id)

func update_match_rules_from_host(rules_dict: Dictionary) -> void:
	if not is_server():
		return
	Game.rules.load_dict(rules_dict)
	_reconcile_bots()
	_sync_all_players.rpc(_get_players_data_array())
	s2c_match_rules_updated.rpc(Game.rules.to_dict())
	if transport == Transport.STEAM and SteamService:
		SteamService.update_current_lobby_metadata()
	match_rules_updated.emit()

func get_human_player_count() -> int:
	var count := 0
	for player in players.values():
		if not player.is_bot:
			count += 1
	return count

## Боты занимают обычные места в составе, но не являются ENet-пирами.
## Их идентификаторы не пересекаются с peer_id людей и -1 (ничья).
func _reconcile_bots() -> void:
	if not is_server():
		return
	var available := maxi(0, MAX_PLAYERS - get_human_player_count())
	var wanted := mini(Game.rules.bot_count, available)
	if Game.is_in_match:
		# Во время боя не добавляем новых участников; лишь освобождаем место человеку.
		var existing := 0
		for player in players.values():
			if player.is_bot:
				existing += 1
		wanted = mini(wanted, existing)
	for id in players.keys():
		if players[id].is_bot and (id > BOT_ID_BASE or BOT_ID_BASE - id >= wanted):
			players.erase(id)
	for index in range(wanted):
		var id := BOT_ID_BASE - index
		var bot: PlayerInfo = players.get(id)
		if bot == null:
			bot = PlayerInfo.new(id, "Бот %d" % (index + 1), 1)
			bot.is_bot = true
			players[id] = bot
		bot.bot_difficulty = Game.rules.bot_difficulty
		bot.is_ready = true
	if not Game.is_in_match and _bot_balance_signature != _get_bot_balance_signature():
		_balance_bot_teams()

func _get_bot_balance_signature() -> Array:
	var signature: Array = [Game.rules.is_team_mode, Game.rules.team_count]
	var ids: Array = players.keys()
	ids.sort()
	for id in ids:
		var player: PlayerInfo = players[id]
		signature.append([id] if player.is_bot else [id, player.team_id])
	return signature

func _balance_bot_teams() -> void:
	var counts: Dictionary = {}
	for team in range(1, Game.rules.team_count + 1):
		counts[team] = 0
	for player in players.values():
		if not player.is_bot:
			player.team_id = clampi(player.team_id, 1, Game.rules.team_count)
			counts[player.team_id] += 1
	for player in players.values():
		if player.is_bot:
			var smallest := 1
			for team in counts:
				if counts[team] < counts[smallest]:
					smallest = team
			player.team_id = smallest
			counts[smallest] += 1
	_bot_balance_signature = _get_bot_balance_signature()

func set_bot_team(bot_id: int, team: int) -> void:
	if not is_host or Game.is_in_match or not players.has(bot_id) or not players[bot_id].is_bot:
		return
	players[bot_id].team_id = clampi(team, 1, Game.rules.team_count)
	_sync_all_players.rpc(_get_players_data_array())

# --- RPC методы синхронизации лобби ---

@rpc("any_peer", "reliable")
func c2s_set_ready(ready_val: bool, p_peer_id: int = 0) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = p_peer_id
	if sender_id <= 0 or (players.has(sender_id) and players[sender_id].is_bot):
		return

	if not players.has(sender_id):
		var default_name := "Player_%d" % sender_id
		players[sender_id] = PlayerInfo.new(sender_id, default_name, 1)

	players[sender_id].is_ready = ready_val
	_sync_all_players.rpc(_get_players_data_array())
	player_ready_changed.emit(sender_id, ready_val)
	player_list_updated.emit()

@rpc("any_peer", "reliable")
func c2s_set_team(team_val: int, p_peer_id: int = 0) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = p_peer_id
	if sender_id <= 0 or (players.has(sender_id) and players[sender_id].is_bot):
		return

	if players.has(sender_id):
		players[sender_id].team_id = clampi(team_val, 1, Game.rules.team_count)
		if not Game.is_in_match:
			_balance_bot_teams()
		_sync_all_players.rpc(_get_players_data_array())
		player_list_updated.emit()

@rpc("any_peer", "reliable")
func c2s_set_name(new_name: String, p_peer_id: int = 0) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = p_peer_id
	if sender_id <= 0 or (players.has(sender_id) and players[sender_id].is_bot):
		return

	var clean := new_name.strip_edges()
	if clean.is_empty():
		clean = "Player_%d" % sender_id
	if players.has(sender_id):
		players[sender_id].player_name = clean
		_sync_all_players.rpc(_get_players_data_array())
		player_list_updated.emit()


@rpc("authority", "reliable")
func s2c_match_rules_updated(rules_dict: Dictionary) -> void:
	Game.rules.load_dict(rules_dict)
	match_rules_updated.emit()

@rpc("any_peer", "unreliable")
func c2s_ping(client_timestamp: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	s2c_pong.rpc_id(sender_id, client_timestamp)

@rpc("authority", "unreliable")
func s2c_pong(client_timestamp: int) -> void:
	var rtt := int(Time.get_ticks_msec() - client_timestamp)
	var my_id := get_unique_id()
	if players.has(my_id):
		players[my_id].ping_ms = rtt
	if not is_server():
		c2s_report_ping.rpc_id(1, rtt)
	player_list_updated.emit()

@rpc("any_peer", "unreliable")
func c2s_report_ping(rtt: int) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if players.has(sender_id):
		players[sender_id].ping_ms = rtt
		# периодически или по необходимости рассылаем клиентам
		_sync_ping_to_clients.rpc(sender_id, rtt)

@rpc("authority", "unreliable")
func _sync_ping_to_clients(peer_id: int, rtt: int) -> void:
	if players.has(peer_id):
		players[peer_id].ping_ms = rtt
		player_list_updated.emit()

@rpc("any_peer", "reliable")
func _register_player(p_name: String, p_team: int, p_steam_id: int = 0, p_game_version: String = "") -> void:
	if not is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1:
		return
	if not p_game_version.is_empty() and SteamService and p_game_version != SteamService.GAME_VERSION:
		push_warning("Network: Отклонен пир %d из-за несовпадения версии (%s != %s)." % [sender_id, p_game_version, SteamService.GAME_VERSION])
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	if not players.has(sender_id) and get_human_player_count() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return
	var resolved_steam_id := p_steam_id
	if resolved_steam_id <= 0 and transport == Transport.STEAM and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.has_method("get_steam_id_for_peer_id"):
		resolved_steam_id = int(multiplayer.multiplayer_peer.call("get_steam_id_for_peer_id", sender_id))

	var player_name := p_name.strip_edges()
	if (player_name.is_empty() or player_name == "Player") and resolved_steam_id > 0 and SteamService:
		var steam_nick := SteamService.get_friend_name(resolved_steam_id)
		if not steam_nick.is_empty():
			player_name = steam_nick
	if player_name.is_empty():
		player_name = "Player_%d" % sender_id

	# Автоматически назначаем команду, если не задана
	var team := p_team
	if team <= 0:
		team = (players.size() % 4) + 1

	var new_player := PlayerInfo.new(sender_id, player_name, team)
	new_player.steam_id = resolved_steam_id
	players[sender_id] = new_player
	_reconcile_bots()

	_sync_all_players.rpc(_get_players_data_array())
	# Синхронизируем новому игроку текущие правила матча
	s2c_match_rules_updated.rpc_id(sender_id, Game.rules.to_dict())
	player_list_updated.emit()

@rpc("authority", "reliable", "call_local")
func _sync_all_players(players_data: Array) -> void:
	players.clear()
	for d in players_data:
		if d is Dictionary:
			var info := PlayerInfo.from_dict(d)
			players[info.peer_id] = info

	var local := get_player_info(get_unique_id())
	if local:
		local_team_id = local.team_id
		local_is_ready = local.is_ready
	player_list_updated.emit()

func _get_players_data_array() -> Array:
	var data: Array = []
	for p in players.values():
		if p is PlayerInfo:
			data.append(p.to_dict())
	return data
