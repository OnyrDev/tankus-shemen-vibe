class_name LANDiscovery
extends Node

## Компонент обнаружения игр в локальной сети (LAN Discovery).
## Хост периодически отправляет UDP broadcast с метаданными лобби,
## а клиенты слушают эфир и формируют список доступных серверов без ручного ввода IP.

signal server_found(server_info: Dictionary)
signal server_lost(server_key: String)
signal server_list_updated(servers: Array)

const DEFAULT_BROADCAST_PORT: int = 7001
const BROADCAST_INTERVAL: float = 1.0
const SERVER_EXPIRATION_TIME: float = 3.5

var is_broadcasting: bool = false
var is_listening: bool = false

var host_server_name: String = "TANKUS Host"
var host_game_port: int = 7000
var host_max_players: int = 8

var _udp_broadcaster: PacketPeerUDP = null
var _udp_listener: PacketPeerUDP = null
var _broadcast_timer: float = 0.0

# key: "ip:port" -> Dictionary
var _discovered_servers: Dictionary = {}

func _exit_tree() -> void:
	stop_broadcasting()
	stop_listening()

func start_broadcasting(p_server_name: String, p_game_port: int = 7000, p_max_players: int = 8) -> void:
	stop_broadcasting()
	stop_listening()

	host_server_name = p_server_name.strip_edges()
	if host_server_name.is_empty():
		host_server_name = "TANKUS Host"

	host_game_port = p_game_port
	host_max_players = p_max_players

	_udp_broadcaster = PacketPeerUDP.new()
	_udp_broadcaster.set_broadcast_enabled(true)
	var err := _udp_broadcaster.set_dest_address("255.255.255.255", DEFAULT_BROADCAST_PORT)
	if err != OK:
		push_warning("LANDiscovery: Ошибка установки адреса broadcast: %s" % error_string(err))

	is_broadcasting = true
	_broadcast_timer = 0.0
	_send_broadcast_beacon()

func stop_broadcasting() -> void:
	is_broadcasting = false
	if _udp_broadcaster:
		_udp_broadcaster.close()
		_udp_broadcaster = null

func start_listening(p_listen_port: int = DEFAULT_BROADCAST_PORT) -> Error:
	stop_listening()

	_udp_listener = PacketPeerUDP.new()
	var err := _udp_listener.bind(p_listen_port)
	if err != OK:
		push_warning("LANDiscovery: Порт %d занят (%s). Используйте прямой IP для локального теста." % [p_listen_port, error_string(err)])
		_udp_listener = null
		return err

	is_listening = true
	_discovered_servers.clear()
	server_list_updated.emit([])
	return OK

func stop_listening() -> void:
	is_listening = false
	if _udp_listener:
		_udp_listener.close()
		_udp_listener = null
	_discovered_servers.clear()
	server_list_updated.emit([])

func get_servers() -> Array:
	return _discovered_servers.values()

func _process(delta: float) -> void:
	if is_broadcasting:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_send_broadcast_beacon()

	if is_listening:
		_poll_listener()
		_cleanup_expired_servers()

func _send_broadcast_beacon() -> void:
	if not _udp_broadcaster:
		return

	var current_player_count := 1
	var net_node := get_node_or_null("/root/Network")
	if net_node and "players" in net_node:
		current_player_count = maxi(1, net_node.players.size())

	var payload: Dictionary = {
		"game": "TANKUS",
		"name": host_server_name,
		"port": host_game_port,
		"players": current_player_count,
		"max_players": host_max_players,
		"version": "1.0"
	}

	var json_bytes := JSON.stringify(payload).to_utf8_buffer()
	_udp_broadcaster.put_packet(json_bytes)

func _poll_listener() -> void:
	if not _udp_listener:
		return

	var list_changed := false

	while _udp_listener.get_available_packet_count() > 0:
		var packet := _udp_listener.get_packet()
		var sender_ip := _udp_listener.get_packet_ip()
		var text := packet.get_string_from_utf8()

		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue

		if parsed.get("game") != "TANKUS":
			continue

		var s_port: int = int(parsed.get("port", 7000))
		var key := "%s:%d" % [sender_ip, s_port]
		var is_new := not _discovered_servers.has(key)

		var server_info: Dictionary = {
			"key": key,
			"ip": sender_ip,
			"port": s_port,
			"name": str(parsed.get("name", "TANKUS Server")),
			"players": int(parsed.get("players", 1)),
			"max_players": int(parsed.get("max_players", 8)),
			"last_seen": Time.get_ticks_msec() / 1000.0
		}

		_discovered_servers[key] = server_info
		list_changed = true

		if is_new:
			server_found.emit(server_info)

	if list_changed:
		server_list_updated.emit(_discovered_servers.values())

func _cleanup_expired_servers() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var keys_to_remove: Array[String] = []

	for key in _discovered_servers.keys():
		var info: Dictionary = _discovered_servers[key]
		if (now - info.get("last_seen", 0.0)) > SERVER_EXPIRATION_TIME:
			keys_to_remove.append(key)

	if keys_to_remove.is_empty():
		return

	for key in keys_to_remove:
		_discovered_servers.erase(key)
		server_lost.emit(key)

	server_list_updated.emit(_discovered_servers.values())
