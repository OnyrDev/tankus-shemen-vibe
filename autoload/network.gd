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

const DEFAULT_PORT: int = 7000
const MAX_CLIENTS: int = 8

var players: Dictionary = {} # peer_id: int -> PlayerInfo
var local_player_name: String = "Player"
var local_team_id: int = 1
var local_is_ready: bool = false
var is_host: bool = false

var _ping_timer: float = 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("Network: Не удалось создать ENet сервер на порту %d: %s" % [port, error_string(err)])
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	players.clear()

	var local_info := PlayerInfo.new(1, local_player_name, local_team_id)
	players[1] = local_info

	server_created.emit()
	player_list_updated.emit()
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

	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK

func disconnect_session() -> void:
	if multiplayer.has_multiplayer_peer():
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer != null and not (peer is OfflineMultiplayerPeer):
			peer.close()
		multiplayer.multiplayer_peer = null

	players.clear()
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
		_sync_all_players.rpc(_get_players_data_array())

	peer_disconnected.emit(id)
	player_list_updated.emit()

func _on_connected_to_server() -> void:
	connected_to_server.emit()
	# Клиент регистрирует себя на сервере
	_register_player.rpc_id(1, local_player_name, local_team_id)

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
		players[my_id].team_id = team_val
	player_list_updated.emit()

	if is_server():
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
	s2c_match_rules_updated.rpc(rules_dict)
	match_rules_updated.emit()

# --- RPC методы синхронизации лобби ---

@rpc("any_peer", "reliable")
func c2s_set_ready(ready_val: bool, p_peer_id: int = 0) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0 and p_peer_id != 0:
		sender_id = p_peer_id
	elif p_peer_id != 0:
		sender_id = p_peer_id

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
	if sender_id == 0 and p_peer_id != 0:
		sender_id = p_peer_id
	elif p_peer_id != 0:
		sender_id = p_peer_id

	if players.has(sender_id):
		players[sender_id].team_id = team_val
		_sync_all_players.rpc(_get_players_data_array())
		player_list_updated.emit()

@rpc("any_peer", "reliable")
func c2s_set_name(new_name: String, p_peer_id: int = 0) -> void:
	if not is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0 and p_peer_id != 0:
		sender_id = p_peer_id
	elif p_peer_id != 0:
		sender_id = p_peer_id

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
func _register_player(p_name: String, p_team: int) -> void:
	if not is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var player_name := p_name.strip_edges()
	if player_name.is_empty():
		player_name = "Player_%d" % sender_id

	# Автоматически назначаем команду, если не задана
	var team := p_team
	if team <= 0:
		team = (players.size() % 4) + 1

	var new_player := PlayerInfo.new(sender_id, player_name, team)
	players[sender_id] = new_player

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

	player_list_updated.emit()

func _get_players_data_array() -> Array:
	var data: Array = []
	for p in players.values():
		if p is PlayerInfo:
			data.append(p.to_dict())
	return data
