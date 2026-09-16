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

const DEFAULT_PORT: int = 7000
const MAX_CLIENTS: int = 8

var players: Dictionary = {} # peer_id: int -> PlayerInfo
var local_player_name: String = "Player"
var local_team_id: int = 0
var is_host: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_server() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true # В одиночной игре поведение серверное
	return multiplayer.is_server()

func get_unique_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 1
	return multiplayer.get_unique_id()

func is_multiplayer_active() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

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
		multiplayer.multiplayer_peer.close()
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

# --- RPC методы синхронизации лобби ---

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
