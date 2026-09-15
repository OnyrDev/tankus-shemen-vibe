extends Node

signal server_created()
signal server_closed()
signal connected_to_server()
signal connection_failed()
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal player_list_updated()

const DEFAULT_PORT: int = 7000
const MAX_CLIENTS: int = 8

var players: Dictionary = {} # peer_id: int -> PlayerInfo
var local_player_name: String = "Player"
var is_host: bool = false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func create_host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to create ENet server on port %d: %s" % [port, error_string(err)])
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	players.clear()

	var local_info := PlayerInfo.new(1, local_player_name, 0)
	players[1] = local_info

	server_created.emit()
	player_list_updated.emit()
	return OK

func join_host(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to connect to %s:%d: %s" % [ip, port, error_string(err)])
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK

func disconnect_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	server_closed.emit()

func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_disconnected.emit(id)
	player_list_updated.emit()

func _on_connected_to_server() -> void:
	connected_to_server.emit()

func _on_connection_failed() -> void:
	connection_failed.emit()

func _on_server_disconnected() -> void:
	disconnect_session()
