class_name LANMenu
extends CanvasLayer

## Сетевое меню TANKUS для создания и поиска LAN серверов.
## Поддерживает автоматический поиск лобби через UDP Discovery (LANDiscovery),
## прямое подключение по IP:Port, управление сессией и отображение подключенных игроков.

signal game_started()

@onready var panel_main: Control = $MainContainer
@onready var panel_lobby: Control = $LobbyContainer

# Поля ввода
@onready var line_player_name: LineEdit = $MainContainer/Panel/VBox/HBoxName/LineEditName
@onready var line_server_name: LineEdit = $MainContainer/Panel/VBox/HBoxServerName/LineEditServerName
@onready var line_direct_ip: LineEdit = $MainContainer/Panel/VBox/HBoxDirect/LineEditIP
@onready var line_direct_port: LineEdit = $MainContainer/Panel/VBox/HBoxDirect/LineEditPort

# Кнопки
@onready var btn_create_host: Button = $MainContainer/Panel/VBox/BtnCreateHost
@onready var btn_refresh_lan: Button = $MainContainer/Panel/VBox/HBoxLANHeader/BtnRefreshLAN
@onready var btn_direct_connect: Button = $MainContainer/Panel/VBox/HBoxDirect/BtnDirectConnect
@onready var btn_close_menu: Button = $MainContainer/Panel/VBox/BtnCloseMenu

# Список серверов
@onready var server_list_container: VBoxContainer = $MainContainer/Panel/VBox/ScrollServers/ServerList
@onready var lbl_search_status: Label = $MainContainer/Panel/VBox/LblSearchStatus

# Панель лобби
@onready var lbl_lobby_title: Label = $LobbyContainer/Panel/VBox/LblLobbyTitle
@onready var player_list_container: VBoxContainer = $LobbyContainer/Panel/VBox/ScrollPlayers/PlayerList
@onready var btn_start_game: Button = $LobbyContainer/Panel/VBox/BtnStartGame
@onready var btn_disconnect: Button = $LobbyContainer/Panel/VBox/BtnDisconnect

var _lan_discovery: LANDiscovery = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_lan_discovery()
	_connect_network_signals()
	_connect_ui_signals()

	# Восстанавливаем имя игрока
	if line_player_name:
		line_player_name.text = Network.local_player_name

	_update_ui_state()
	_start_lan_search()

	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func set_menu_visible(p_visible: bool) -> void:
	visible = p_visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_start_lan_search()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_lan_discovery() -> void:
	_lan_discovery = LANDiscovery.new()
	_lan_discovery.name = "LANDiscovery"
	add_child(_lan_discovery)

	_lan_discovery.server_found.connect(_on_server_found)
	_lan_discovery.server_list_updated.connect(_on_server_list_updated)

func _connect_network_signals() -> void:
	Network.server_created.connect(_on_network_session_changed)
	Network.server_closed.connect(_on_network_session_changed)
	Network.connected_to_server.connect(_on_network_session_changed)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	Network.player_list_updated.connect(_refresh_player_list)

func _connect_ui_signals() -> void:
	if btn_create_host:
		btn_create_host.pressed.connect(_on_create_host_pressed)
	if btn_refresh_lan:
		btn_refresh_lan.pressed.connect(_start_lan_search)
	if btn_direct_connect:
		btn_direct_connect.pressed.connect(_on_direct_connect_pressed)
	if btn_close_menu:
		btn_close_menu.pressed.connect(_on_close_menu_pressed)
	if btn_start_game:
		btn_start_game.pressed.connect(_on_start_game_pressed)
	if btn_disconnect:
		btn_disconnect.pressed.connect(_on_disconnect_pressed)
	if line_player_name:
		line_player_name.text_changed.connect(_on_player_name_changed)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			set_menu_visible(not visible)
			get_viewport().set_input_as_handled()

func _on_player_name_changed(new_name: String) -> void:
	var clean := new_name.strip_edges()
	if not clean.is_empty():
		Network.local_player_name = clean

func _on_create_host_pressed() -> void:
	var s_name := "TANKUS Room"
	if line_server_name and not line_server_name.text.strip_edges().is_empty():
		s_name = line_server_name.text.strip_edges()

	var port := Network.DEFAULT_PORT
	if line_direct_port and not line_direct_port.text.strip_edges().is_empty():
		var custom_port := int(line_direct_port.text.strip_edges())
		if custom_port > 0:
			port = custom_port

	var err := Network.create_host(port)
	if err == OK:
		if _lan_discovery:
			_lan_discovery.start_broadcasting(s_name, port, 8)
		_update_ui_state()

func _on_direct_connect_pressed() -> void:
	var ip := "127.0.0.1"
	var port := Network.DEFAULT_PORT

	if line_direct_ip and not line_direct_ip.text.strip_edges().is_empty():
		ip = line_direct_ip.text.strip_edges()

	if line_direct_port and not line_direct_port.text.strip_edges().is_empty():
		port = int(line_direct_port.text.strip_edges())

	_connect_to_ip(ip, port)

func _connect_to_ip(ip: String, port: int) -> void:
	if lbl_search_status:
		lbl_search_status.text = "Подключение к %s:%d..." % [ip, port]

	var err := Network.join_host(ip, port)
	if err != OK:
		if lbl_search_status:
			lbl_search_status.text = "Ошибка подключения: %s" % error_string(err)

func _start_lan_search() -> void:
	if _lan_discovery and not Network.is_host:
		var err := _lan_discovery.start_listening()
		if err == OK:
			if lbl_search_status:
				lbl_search_status.text = "Поиск активных LAN серверов..."
		else:
			if lbl_search_status:
				lbl_search_status.text = "Порт сканера занят. Для второго окна используйте прямое подключение (127.0.0.1)."

func _on_server_found(_server_info: Dictionary) -> void:
	if lbl_search_status:
		lbl_search_status.text = "Найдены серверы в сети:"

func _on_server_list_updated(servers: Array) -> void:
	if not server_list_container:
		return

	# Очищаем старый список
	for child in server_list_container.get_children():
		server_list_container.remove_child(child)
		child.queue_free()

	if servers.is_empty():
		if lbl_search_status:
			lbl_search_status.text = "Серверы не найдены. Создайте свой сервер или обновите поиск."
		return

	if lbl_search_status:
		lbl_search_status.text = "Доступные LAN серверы (%d):" % servers.size()

	for s in servers:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = "%s (%s:%d) [%d/%d]" % [
			s.get("name", "Host"),
			s.get("ip", "127.0.0.1"),
			s.get("port", 7000),
			s.get("players", 1),
			s.get("max_players", 8)
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var join_btn := Button.new()
		join_btn.text = "Войти"
		join_btn.custom_minimum_size = Vector2(80, 0)
		var target_ip: String = s.get("ip", "127.0.0.1")
		var target_port: int = s.get("port", 7000)
		join_btn.pressed.connect(func(): _connect_to_ip(target_ip, target_port))
		row.add_child(join_btn)

		server_list_container.add_child(row)

func _on_connection_failed() -> void:
	if lbl_search_status:
		lbl_search_status.text = "Не удалось подключиться к серверу."
	_update_ui_state()

func _on_server_disconnected() -> void:
	if lbl_search_status:
		lbl_search_status.text = "Связь с сервером потеряна."
	_update_ui_state()

func _on_disconnect_pressed() -> void:
	if _lan_discovery:
		_lan_discovery.stop_broadcasting()
	Network.disconnect_session()
	_update_ui_state()
	_start_lan_search()

func _on_start_game_pressed() -> void:
	if Network.is_host:
		_start_game_rpc.rpc()
	else:
		set_menu_visible(false)
		game_started.emit()

@rpc("authority", "reliable", "call_local")
func _start_game_rpc() -> void:
	set_menu_visible(false)
	game_started.emit()

func _on_close_menu_pressed() -> void:
	set_menu_visible(false)

func _on_network_session_changed() -> void:
	_update_ui_state()
	_refresh_player_list()

func _update_ui_state() -> void:
	var in_session := Network.is_multiplayer_active() or Network.is_host

	if panel_main:
		panel_main.visible = not in_session
	if panel_lobby:
		panel_lobby.visible = in_session

	if in_session:
		if lbl_lobby_title:
			lbl_lobby_title.text = "LAN ЛОББИ: %s" % ("ХОСТ" if Network.is_host else "КЛИЕНТ")
		if btn_start_game:
			btn_start_game.visible = Network.is_host
	else:
		if _lan_discovery and not Network.is_host:
			_lan_discovery.start_listening()

func _refresh_player_list() -> void:
	if not player_list_container:
		return

	for child in player_list_container.get_children():
		player_list_container.remove_child(child)
		child.queue_free()

	for p in Network.get_all_players():
		if p is PlayerInfo:
			var lbl := Label.new()
			var role := " (ХОСТ)" if p.peer_id == 1 else ""
			var is_me := " [ВЫ]" if p.peer_id == Network.get_unique_id() else ""
			lbl.text = "• %s%s%s (Команда %d)" % [p.player_name, role, is_me, p.team_id]
			player_list_container.add_child(lbl)
