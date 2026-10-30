class_name MainMenu
extends Control

## Скрипт автономного Главного Меню TANKUS.
## Обеспечивает навигацию: Одиночный режим (Тренировка), LAN-мультиплеер,
## выбор карты арены, настройки звука/экрана и стильный 3D-шоурум танка.

signal play_solo_requested()
signal map_selected(map_key: String)

const MAP_INFO: Dictionary = {
	"sky_courtyard": {
		"name": "Sky Courtyard",
		"desc": "Парящая цитадель над облаками. Колонны, открытые фланги и глубокие пропасти по периметру."
	},
	"iceworks": {
		"name": "Iceworks",
		"desc": "Ледяной полигон с пониженным трением. Скользкий центральный каток и толкаемые контейнеры."
	},
	"pendulum_yard": {
		"name": "Pendulum Yard",
		"desc": "Инженерный двор с массивным раскачивающимся кинетическим маятником в центре."
	},
	"shift": {
		"name": "Shift",
		"desc": "Кибернетическая платформа с синхронно вращающимися плитами и меняющейся геометрией."
	},
	"ceramic_garden": {
		"name": "Керамический сад — Терракота",
		"desc": "Солнечный керамический сад: две террасы, четыре пандуса, центральная чаша и широкие обходы среди терракотовых клумб."
	},
	"radio_station": {
		"name": "Радиостанция — Малиновая частота",
		"desc": "Два технических двора, центральная антенная платформа с двумя пандусами и широкие обходы. Графитовый металл, малиновые панели и голубая разметка."
	},
	"factory_smelter": {
		"name": "Завод — Плавильня",
		"desc": "Индустриальный цех в стиле Factorio. Открытая печь-топка, высокий мост с шестерёнками над кипящим металлом, конвейеры сброса мусора и анимированные манипуляторы."
	},
	"atrium": {
		"name": "Atrium",
		"desc": "Трехуровневый бруталистский зал. Нижний пит с рикошетными пилонами под 45°, галереи и подвесной мост без перил."
	}
}

# --- 3D Showroom ---
@onready var showroom_tank: Node3D = get_node_or_null("Showroom3D/ShowroomTank")
@onready var showroom_turret: Node3D = get_node_or_null("Showroom3D/ShowroomTank/TurretMount")

# --- UI Панели ---
@onready var panel_main_buttons: VBoxContainer = %MainButtons
@onready var panel_map_select: PanelContainer = %MapSelectPanel
@onready var panel_lan: PanelContainer = %LANPanel
@onready var panel_settings: PanelContainer = %SettingsPanel

# --- Главные кнопки ---
@onready var btn_solo: Button = %BtnSolo
@onready var btn_lan: Button = %BtnLAN
@onready var btn_map: Button = %BtnMap
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit

# --- Элементы выбора карты ---
@onready var map_buttons_container: VBoxContainer = %MapListContainer
@onready var lbl_current_map_desc: Label = %LblMapDesc
@onready var btn_map_back: Button = %BtnMapBack
@onready var lbl_status_map: Label = %LblStatusMap

# --- Элементы LAN ---
@onready var line_player_name: LineEdit = %LinePlayerName
@onready var line_server_name: LineEdit = %LineServerName
@onready var btn_create_host: Button = %BtnCreateHost
@onready var btn_refresh_lan: Button = %BtnRefreshLAN
@onready var server_list_vbox: VBoxContainer = %ServerList
@onready var lbl_lan_status: Label = %LblLANStatus
@onready var line_direct_ip: LineEdit = %LineDirectIP
@onready var line_direct_port: LineEdit = %LineDirectPort
@onready var btn_direct_connect: Button = %BtnDirectConnect
@onready var btn_lan_back: Button = %BtnLANBack

# --- Элементы настроек ---
@onready var slider_sfx: HSlider = %SliderSFX
@onready var lbl_sfx_val: Label = %LblSFXVal
@onready var slider_ui: HSlider = %SliderUI
@onready var lbl_ui_val: Label = %LblUIVal
@onready var slider_music: HSlider = %SliderMusic
@onready var lbl_music_val: Label = %LblMusicVal
@onready var chk_fullscreen: CheckBox = %ChkFullscreen
@onready var chk_vsync: CheckBox = %ChkVSync
@onready var btn_settings_back: Button = %BtnSettingsBack

var _lan_discovery: LANDiscovery = null
var _selected_map_key: String = "sky_courtyard"
var _rotation_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_setup_lan_discovery()
	_connect_signals()
	_init_map_selection()
	_init_settings()
	_setup_button_audio_recursively(self)
	_switch_panel("main")

	if MusicManager:
		MusicManager.stop_music(0.0)

func _process(delta: float) -> void:
	_rotation_time += delta
	if showroom_tank:
		showroom_tank.rotate_y(delta * 0.35)
	if showroom_turret:
		showroom_turret.rotation.y = sin(_rotation_time * 0.9) * 0.45

func _connect_signals() -> void:
	# Главные кнопки
	btn_solo.pressed.connect(_on_btn_solo_pressed)
	btn_lan.pressed.connect(_on_btn_lan_pressed)
	btn_map.pressed.connect(_on_btn_map_pressed)
	btn_settings.pressed.connect(_on_btn_settings_pressed)
	btn_quit.pressed.connect(_on_btn_quit_pressed)

	# Кнопки возврата
	btn_map_back.pressed.connect(func(): _switch_panel("main"))
	btn_lan_back.pressed.connect(func(): _switch_panel("main"))
	btn_settings_back.pressed.connect(func(): _switch_panel("main"))

	# LAN кнопки и ввод
	btn_create_host.pressed.connect(_on_create_host_pressed)
	btn_refresh_lan.pressed.connect(_start_lan_search)
	btn_direct_connect.pressed.connect(_on_direct_connect_pressed)
	if line_player_name:
		var init_name := SettingsManager.get_player_name() if SettingsManager else Network.local_player_name
		line_player_name.text = init_name
		Network.local_player_name = init_name
		line_player_name.text_changed.connect(func(n: String):
			var cleaned: String = n.strip_edges()
			Network.local_player_name = cleaned
			if SettingsManager:
				SettingsManager.set_player_name(cleaned)
		)

	# Настройки
	if slider_sfx:
		slider_sfx.value_changed.connect(_on_sfx_slider_changed)
	if slider_ui:
		slider_ui.value_changed.connect(_on_ui_slider_changed)
	if slider_music:
		slider_music.value_changed.connect(_on_music_slider_changed)
	if chk_fullscreen:
		chk_fullscreen.toggled.connect(_on_fullscreen_toggled)
	if chk_vsync:
		chk_vsync.toggled.connect(_on_vsync_toggled)

	# Сетевые события
	Network.server_created.connect(_on_network_server_created)
	Network.connected_to_server.connect(_on_network_connected_to_server)
	Network.connection_failed.connect(_on_network_connection_failed)

func _setup_lan_discovery() -> void:
	_lan_discovery = LANDiscovery.new()
	_lan_discovery.name = "LANDiscovery"
	add_child(_lan_discovery)

	_lan_discovery.server_found.connect(func(_info): pass)
	_lan_discovery.server_list_updated.connect(_on_lan_server_list_updated)

func _switch_panel(panel_name: String) -> void:
	panel_main_buttons.visible = (panel_name == "main")
	panel_map_select.visible = (panel_name == "map")
	panel_lan.visible = (panel_name == "lan")
	panel_settings.visible = (panel_name == "settings")

	if panel_name == "lan":
		_start_lan_search()

func _on_btn_solo_pressed() -> void:
	_play_select_sound()
	Game.is_solo_practice = true
	Game.rules.selected_map = _selected_map_key
	if Network.is_multiplayer_active() or Network.is_host:
		Network.disconnect_session()

	get_tree().change_scene_to_file("res://maps/test_sandbox.tscn")

func _on_btn_lan_pressed() -> void:
	_play_select_sound()
	_switch_panel("lan")

func _on_btn_map_pressed() -> void:
	_play_select_sound()
	_switch_panel("map")

func _on_btn_settings_pressed() -> void:
	_play_select_sound()
	_switch_panel("settings")

func _on_btn_quit_pressed() -> void:
	_play_select_sound()
	if SettingsManager:
		SettingsManager.save_settings()
	get_tree().quit()

# --- Выбор арены ---

func _init_map_selection() -> void:
	if SettingsManager and not SettingsManager.get_selected_map().is_empty():
		_selected_map_key = SettingsManager.get_selected_map()
		Game.rules.selected_map = _selected_map_key
	elif not Game.rules.selected_map.is_empty():
		_selected_map_key = Game.rules.selected_map
	else:
		_selected_map_key = "sky_courtyard"
		Game.rules.selected_map = _selected_map_key

	_update_map_status_ui()
	_rebuild_map_buttons()

func _rebuild_map_buttons() -> void:
	if not map_buttons_container:
		return

	for c in map_buttons_container.get_children():
		c.queue_free()

	for map_key in MAP_INFO:
		var info: Dictionary = MAP_INFO[map_key]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.text = "%s  %s" % ["★" if map_key == _selected_map_key else "  ", info["name"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)

		btn.pressed.connect(func():
			_selected_map_key = map_key
			Game.rules.selected_map = map_key
			if SettingsManager:
				SettingsManager.set_selected_map(map_key)
			_play_select_sound()
			_update_map_status_ui()
			_rebuild_map_buttons()
		)
		btn.mouse_entered.connect(_play_hover_sound)
		map_buttons_container.add_child(btn)

func _update_map_status_ui() -> void:
	var info: Dictionary = MAP_INFO.get(_selected_map_key, MAP_INFO["sky_courtyard"])
	if lbl_current_map_desc:
		lbl_current_map_desc.text = info["desc"]
	if lbl_status_map:
		lbl_status_map.text = "АРЕНА: %s" % info["name"].to_upper()

# --- Сетевая игра LAN ---

func _start_lan_search() -> void:
	if _lan_discovery and not Network.is_host:
		var err := _lan_discovery.start_listening()
		if err == OK:
			if lbl_lan_status:
				lbl_lan_status.text = "Сканирование локальной сети (UDP Discovery)..."
		else:
			if lbl_lan_status:
				lbl_lan_status.text = "Порт сканера занят. Доступно прямое подключение."

func _on_lan_server_list_updated(servers: Array) -> void:
	if not server_list_vbox:
		return

	for c in server_list_vbox.get_children():
		c.queue_free()

	if servers.is_empty():
		if lbl_lan_status:
			lbl_lan_status.text = "Комнат не обнаружено. Создайте сервер или обновите список."
		return

	if lbl_lan_status:
		lbl_lan_status.text = "Обнаружено комнат в сети: %d" % servers.size()

	for s in servers:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = "%s (%s:%d) — игроки %d/%d" % [
			s.get("name", "Host"),
			s.get("ip", "127.0.0.1"),
			s.get("port", 7000),
			s.get("human_players", s.get("players", 1)),
			s.get("max_players", 8)
		]
		if int(s.get("bots", 0)) > 0:
			lbl.text += ", боты %d" % int(s.bots)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var join_btn := Button.new()
		join_btn.text = "Войти"
		join_btn.custom_minimum_size = Vector2(90, 32)
		var target_ip: String = s.get("ip", "127.0.0.1")
		var target_port: int = s.get("port", 7000)
		join_btn.pressed.connect(func():
			_play_select_sound()
			_connect_to_server(target_ip, target_port)
		)
		join_btn.mouse_entered.connect(_play_hover_sound)
		row.add_child(join_btn)

		server_list_vbox.add_child(row)

func _on_create_host_pressed() -> void:
	_play_select_sound()
	var s_name := "TANKUS Room"
	if line_server_name and not line_server_name.text.strip_edges().is_empty():
		s_name = line_server_name.text.strip_edges()

	var port := Network.DEFAULT_PORT
	if line_direct_port and not line_direct_port.text.strip_edges().is_empty():
		var p_int := int(line_direct_port.text.strip_edges())
		if p_int > 0:
			port = p_int

	var err := Network.create_host(port)
	if err == OK:
		if _lan_discovery:
			_lan_discovery.start_broadcasting(s_name, port, 8)
		# Переходим на самостоятельный экран лобби
		Game.rules.selected_map = _selected_map_key
		get_tree().change_scene_to_file("res://lobby/lobby_screen.tscn")
	else:
		if lbl_lan_status:
			lbl_lan_status.text = "Ошибка создания сервера: %s" % error_string(err)

func _on_direct_connect_pressed() -> void:
	_play_select_sound()
	var ip := "127.0.0.1"
	var port := Network.DEFAULT_PORT

	if line_direct_ip and not line_direct_ip.text.strip_edges().is_empty():
		ip = line_direct_ip.text.strip_edges()
	if line_direct_port and not line_direct_port.text.strip_edges().is_empty():
		var p_int := int(line_direct_port.text.strip_edges())
		if p_int > 0:
			port = p_int

	_connect_to_server(ip, port)

func _connect_to_server(ip: String, port: int) -> void:
	if lbl_lan_status:
		lbl_lan_status.text = "Подключение к %s:%d..." % [ip, port]

	var err := Network.join_host(ip, port)
	if err != OK:
		if lbl_lan_status:
			lbl_lan_status.text = "Не удалось инициировать соединение: %s" % error_string(err)

func _on_network_server_created() -> void:
	pass

func _on_network_connected_to_server() -> void:
	if _lan_discovery:
		_lan_discovery.stop_listening()
	get_tree().change_scene_to_file("res://lobby/lobby_screen.tscn")

func _on_network_connection_failed() -> void:
	if lbl_lan_status:
		lbl_lan_status.text = "Ошибка: не удалось соединиться с хостом."

# --- Настройки звука и дисплея ---

func _init_settings() -> void:
	if SettingsManager:
		if slider_sfx:
			slider_sfx.value = SettingsManager.get_sfx_volume() * 100.0
			if lbl_sfx_val:
				lbl_sfx_val.text = "%d%%" % int(slider_sfx.value)

		if slider_ui:
			slider_ui.value = SettingsManager.get_ui_volume() * 100.0
			if lbl_ui_val:
				lbl_ui_val.text = "%d%%" % int(slider_ui.value)

		if slider_music:
			slider_music.value = SettingsManager.get_music_volume() * 100.0
			if lbl_music_val:
				lbl_music_val.text = "%d%%" % int(slider_music.value)

		if chk_fullscreen:
			chk_fullscreen.button_pressed = SettingsManager.is_fullscreen()
		if chk_vsync:
			chk_vsync.button_pressed = SettingsManager.is_vsync()
	else:
		# Fallback на случай отсутствия синглтона
		var sfx_bus := AudioServer.get_bus_index("SFX")
		if sfx_bus != -1 and slider_sfx:
			var db := AudioServer.get_bus_volume_db(sfx_bus)
			slider_sfx.value = db_to_linear(db) * 100.0
			if lbl_sfx_val:
				lbl_sfx_val.text = "%d%%" % int(slider_sfx.value)

		var ui_bus := AudioServer.get_bus_index("UI")
		if ui_bus != -1 and slider_ui:
			var db := AudioServer.get_bus_volume_db(ui_bus)
			slider_ui.value = db_to_linear(db) * 100.0
			if lbl_ui_val:
				lbl_ui_val.text = "%d%%" % int(slider_ui.value)

		var music_bus := AudioServer.get_bus_index("Music")
		if music_bus != -1 and slider_music:
			var db := AudioServer.get_bus_volume_db(music_bus)
			slider_music.value = db_to_linear(db) * 100.0
			if lbl_music_val:
				lbl_music_val.text = "%d%%" % int(slider_music.value)

		if chk_fullscreen:
			chk_fullscreen.button_pressed = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
		if chk_vsync and DisplayServer.get_name() != "headless":
			chk_vsync.button_pressed = (DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)

func _on_sfx_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_sfx_volume(val / 100.0)
	elif SoundManager:
		SoundManager.set_sfx_volume_linear(val / 100.0)
	elif AudioServer.get_bus_index("SFX") != -1:
		var linear := val / 100.0
		var db := linear_to_db(linear) if linear > 0.001 else -80.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
	if lbl_sfx_val:
		lbl_sfx_val.text = "%d%%" % int(val)

func _on_ui_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_ui_volume(val / 100.0)
	elif SoundManager:
		SoundManager.set_ui_volume_linear(val / 100.0)
	elif AudioServer.get_bus_index("UI") != -1:
		var linear := val / 100.0
		var db := linear_to_db(linear) if linear > 0.001 else -80.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), db)
	if lbl_ui_val:
		lbl_ui_val.text = "%d%%" % int(val)

func _on_music_slider_changed(val: float) -> void:
	if SettingsManager:
		SettingsManager.set_music_volume(val / 100.0)
	elif MusicManager:
		MusicManager.set_music_volume_linear(val / 100.0)
	elif AudioServer.get_bus_index("Music") != -1:
		var linear := val / 100.0
		var db := linear_to_db(linear) if linear > 0.001 else -80.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
	if lbl_music_val:
		lbl_music_val.text = "%d%%" % int(val)

func _on_fullscreen_toggled(toggled_on: bool) -> void:
	_play_select_sound()
	if SettingsManager:
		SettingsManager.set_fullscreen(toggled_on)
	elif toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(toggled_on: bool) -> void:
	_play_select_sound()
	if SettingsManager:
		SettingsManager.set_vsync(toggled_on)
	elif DisplayServer.get_name() != "headless":
		var vsync_mode := DisplayServer.VSYNC_ENABLED if toggled_on else DisplayServer.VSYNC_DISABLED
		DisplayServer.window_set_vsync_mode(vsync_mode)

# --- Аудио UI ---

func _setup_button_audio_recursively(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var btn := child as Button
			if not btn.mouse_entered.is_connected(_play_hover_sound):
				btn.mouse_entered.connect(_play_hover_sound)
		_setup_button_audio_recursively(child)

func _play_hover_sound() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_hover", -6.0)

func _play_select_sound() -> void:
	if SoundManager:
		SoundManager.play_sfx("card_select", -2.0)
