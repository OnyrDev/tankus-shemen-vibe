class_name LobbyScreen
extends Control

## Полноценный автономный экран сетевого лобби TANKUS.
## Отображает 3D-шоурум танка игрока с динамической командной раскраской,
## список подключенных участников с выбором команд и готовностью,
## панель управления правилами матча хостом и запуск боевой арены.

const TEAM_COLORS: Array[Color] = [
	Color(0.18, 0.55, 0.95), # Синий (1)
	Color(0.95, 0.25, 0.25), # Красный (2)
	Color(0.2, 0.85, 0.35),  # Зеленый (3)
	Color(0.95, 0.75, 0.15), # Желтый (4)
	Color(0.75, 0.25, 0.95), # Фиолетовый (5)
	Color(0.15, 0.85, 0.85), # Бирюзовый (6)
	Color(0.95, 0.5, 0.15),  # Оранжевый (7)
	Color(0.85, 0.85, 0.85)  # Серый (8)
]

const MAP_NAMES: Array[String] = [
	"sky_courtyard",
	"iceworks",
	"pendulum_yard",
	"shift",
	"atrium"
]

# --- 3D Showroom ---
@onready var showroom_tank: Node3D = $Showroom3D/ShowroomTank
@onready var showroom_turret: Node3D = $Showroom3D/ShowroomTank/TurretMount
@onready var chassis_mesh: MeshInstance3D = $Showroom3D/ShowroomTank/ChassisMesh
@onready var turret_mesh: MeshInstance3D = $Showroom3D/ShowroomTank/TurretMount/TurretMesh

# --- Заголовок и статус ---
@onready var lbl_header: Label = %LblHeader
@onready var lbl_room_status: Label = %LblStatus

# --- Список игроков ---
@onready var player_list_vbox: VBoxContainer = %PlayerList

# --- Настройки матча (Хост) ---
@onready var host_settings_panel: VBoxContainer = %HostSettings
@onready var opt_game_mode: OptionButton = %OptGameMode
@onready var opt_target_wins: OptionButton = %OptTargetWins
@onready var opt_team_count: OptionButton = %OptTeamCount
@onready var chk_friendly_fire: CheckBox = %ChkFriendlyFire
@onready var opt_map: OptionButton = %OptMap
@onready var lbl_host_only_hint: Label = %LblHostOnlyHint

# --- Нижняя панель действий ---
@onready var btn_ready: Button = %BtnReady
@onready var btn_start_match: Button = %BtnStartMatch
@onready var btn_leave_lobby: Button = %BtnLeaveLobby
@onready var line_edit_name: LineEdit = %LineEditName

var _is_local_ready: bool = false
var _rotation_time: float = 0.0
var _is_transitioning: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_setup_ui_options()
	_connect_signals()
	_update_lobby_ui()
	_sync_settings_from_game_rules()
	_update_tank_team_color()
	_setup_button_audio_recursively(self)

	if MusicManager:
		MusicManager.stop_music(0.0)

func _process(delta: float) -> void:
	_rotation_time += delta
	if showroom_tank:
		showroom_tank.rotate_y(delta * 0.3)
	if showroom_turret:
		showroom_turret.rotation.y = sin(_rotation_time * 0.8) * 0.4

func _connect_signals() -> void:
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_ready_changed.connect(func(_pid, _ready): _on_player_list_updated())
	Network.match_rules_updated.connect(_sync_settings_from_game_rules)
	Network.server_closed.connect(_on_server_disconnected)
	Network.server_disconnected.connect(_on_server_disconnected)

	if btn_ready:
		btn_ready.pressed.connect(_on_btn_ready_pressed)
	if btn_start_match:
		btn_start_match.pressed.connect(_on_btn_start_match_pressed)
	if btn_leave_lobby:
		btn_leave_lobby.pressed.connect(_on_btn_leave_lobby_pressed)
	if line_edit_name:
		line_edit_name.text = Network.local_player_name
		line_edit_name.text_submitted.connect(_on_name_submitted)
		line_edit_name.focus_exited.connect(func(): _on_name_submitted(line_edit_name.text))

	# Сигналы изменения настроек хоста
	if opt_game_mode:
		opt_game_mode.item_selected.connect(_on_host_setting_changed)
	if opt_target_wins:
		opt_target_wins.item_selected.connect(_on_host_setting_changed)
	if opt_team_count:
		opt_team_count.item_selected.connect(_on_host_setting_changed)
	if chk_friendly_fire:
		chk_friendly_fire.toggled.connect(func(_val): _on_host_setting_changed(0))
	if opt_map:
		opt_map.item_selected.connect(_on_host_setting_changed)

func _setup_ui_options() -> void:
	if opt_game_mode:
		opt_game_mode.clear()
		opt_game_mode.add_item("Каждый сам за себя (FFA)", 0)
		opt_game_mode.add_item("Командный бой (Teams)", 1)

	if opt_target_wins:
		opt_target_wins.clear()
		opt_target_wins.add_item("До 3 побед", 3)
		opt_target_wins.add_item("До 5 побед (Стандарт)", 5)
		opt_target_wins.add_item("До 7 побед", 7)
		opt_target_wins.add_item("До 10 побед", 10)
		opt_target_wins.select(1) # 5 побед по умолчанию

	if opt_team_count:
		opt_team_count.clear()
		opt_team_count.add_item("2 команды", 2)
		opt_team_count.add_item("3 команды", 3)
		opt_team_count.add_item("4 команды", 4)

	if opt_map:
		opt_map.clear()
		opt_map.add_item("Sky Courtyard", 0)
		opt_map.add_item("Iceworks", 1)
		opt_map.add_item("Pendulum Yard", 2)
		opt_map.add_item("Shift", 3)

func _update_lobby_ui() -> void:
	var is_host: bool = Network.is_host or not Network.is_multiplayer_active()

	if lbl_header:
		lbl_header.text = "TANKUS — СЕТЕВОЕ ЛОББИ"
	if lbl_room_status:
		if is_host:
			lbl_room_status.text = "Статус: Вы хост лобби. Настройте правила и нажмите 'НАЧАТЬ МАТЧ'."
			lbl_room_status.modulate = Color(0.3, 0.9, 0.4)
		else:
			lbl_room_status.text = "Статус: Подключен к серверу. Выберите команду и нажмите 'Я ГОТОВ!'."
			lbl_room_status.modulate = Color(0.4, 0.7, 1.0)

	if btn_start_match:
		btn_start_match.visible = is_host

	if lbl_host_only_hint:
		lbl_host_only_hint.visible = not is_host

	# Блокируем настройки для клиентов
	if opt_game_mode:
		opt_game_mode.disabled = not is_host
	if opt_target_wins:
		opt_target_wins.disabled = not is_host
	if opt_team_count:
		opt_team_count.disabled = not is_host or (opt_game_mode and opt_game_mode.selected == 0)
	if chk_friendly_fire:
		chk_friendly_fire.disabled = not is_host
	if opt_map:
		opt_map.disabled = not is_host

	_refresh_player_cards()

func _refresh_player_cards() -> void:
	if not player_list_vbox:
		return

	for child in player_list_vbox.get_children():
		child.queue_free()

	var all_players := Network.get_all_players()
	for p in all_players:
		if p is PlayerInfo:
			var card := _create_player_card(p)
			player_list_vbox.add_child(card)

	_update_tank_team_color()

func _create_player_card(player: PlayerInfo) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var team_idx := clampi(player.team_id - 1, 0, TEAM_COLORS.size() - 1)
	var team_color := TEAM_COLORS[team_idx]

	var is_me := (player.peer_id == Network.get_unique_id())

	style.bg_color = Color(0.12, 0.14, 0.20, 0.9)
	style.border_width_left = 6
	style.border_color = team_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	margin.add_child(hbox)

	# Имя и бейджи
	var name_lbl := Label.new()
	var host_badge := " [ХОСТ]" if player.peer_id == 1 else ""
	var me_badge := " [ВЫ]" if is_me else ""
	name_lbl.text = "%s%s%s" % [player.player_name, host_badge, me_badge]
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_lbl)

	# Выбор команды
	if Game.rules.is_team_mode:
		if is_me:
			var team_btn := Button.new()
			team_btn.text = "Команда %d" % player.team_id
			team_btn.custom_minimum_size = Vector2(100, 30)
			team_btn.pressed.connect(func():
				_play_select_sound()
				var next_team := (player.team_id % Game.rules.team_count) + 1
				Network.set_local_team(next_team)
				_update_tank_team_color()
			)
			team_btn.mouse_entered.connect(_play_hover_sound)
			hbox.add_child(team_btn)
		else:
			var team_lbl := Label.new()
			team_lbl.text = "Команда %d" % player.team_id
			team_lbl.modulate = team_color
			hbox.add_child(team_lbl)

	# Пинг
	var ping_lbl := Label.new()
	if player.peer_id == 1:
		ping_lbl.text = "0 ms"
		ping_lbl.modulate = Color(0.4, 0.9, 0.4)
	else:
		ping_lbl.text = "%d ms" % player.ping_ms
		if player.ping_ms < 60:
			ping_lbl.modulate = Color(0.4, 0.9, 0.4)
		elif player.ping_ms < 120:
			ping_lbl.modulate = Color(0.9, 0.8, 0.3)
		else:
			ping_lbl.modulate = Color(0.9, 0.3, 0.3)
	ping_lbl.custom_minimum_size = Vector2(55, 0)
	hbox.add_child(ping_lbl)

	# Статус готовности
	var ready_badge := Label.new()
	ready_badge.custom_minimum_size = Vector2(90, 0)
	ready_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if player.peer_id == 1:
		ready_badge.text = "ХОСТ"
		ready_badge.modulate = Color(0.4, 0.8, 1.0)
	elif player.is_ready:
		ready_badge.text = "ГОТОВ"
		ready_badge.modulate = Color(0.2, 0.9, 0.4)
	else:
		ready_badge.text = "НЕ ГОТОВ"
		ready_badge.modulate = Color(0.6, 0.6, 0.6)
	hbox.add_child(ready_badge)

	return card

func _update_tank_team_color() -> void:
	var my_team := Network.local_team_id
	var team_idx := clampi(my_team - 1, 0, TEAM_COLORS.size() - 1)
	var col := TEAM_COLORS[team_idx]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.25
	mat.roughness = 0.35

	if chassis_mesh:
		chassis_mesh.material_override = mat
	if turret_mesh:
		turret_mesh.material_override = mat

func _on_player_list_updated() -> void:
	_refresh_player_cards()

func _on_btn_ready_pressed() -> void:
	_play_select_sound()
	_is_local_ready = not _is_local_ready
	Network.set_local_ready(_is_local_ready)
	_update_ready_button_text()

func _update_ready_button_text() -> void:
	if not btn_ready:
		return
	if _is_local_ready:
		btn_ready.text = "ОТМЕНА ГОТОВНОСТИ"
		btn_ready.modulate = Color(0.9, 0.4, 0.4)
	else:
		btn_ready.text = "Я ГОТОВ!"
		btn_ready.modulate = Color(0.3, 0.9, 0.4)

func _on_btn_start_match_pressed() -> void:
	_play_select_sound()
	if not Network.is_host and Network.is_multiplayer_active():
		return

	_apply_host_settings_to_rules()

	# Синхронно запускаем боевую арену для всех пиров
	if multiplayer.has_multiplayer_peer() and Network.is_multiplayer_active():
		s2c_launch_match.rpc(Game.rules.selected_map)
	else:
		s2c_launch_match(Game.rules.selected_map)

@rpc("authority", "reliable", "call_local")
func s2c_launch_match(map_name: String) -> void:
	_launch_match_local(map_name)

func _launch_match_local(map_name: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	Game.rules.selected_map = map_name
	Game.is_in_match = true
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://maps/test_sandbox.tscn")

func _on_btn_leave_lobby_pressed() -> void:
	_play_select_sound()
	Network.disconnect_session()
	_leave_to_main_menu()

func _on_server_disconnected() -> void:
	_leave_to_main_menu()

func _leave_to_main_menu() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	var tree := get_tree()
	if tree:
		tree.change_scene_to_file("res://ui/main_menu.tscn")

func _on_name_submitted(new_name: String) -> void:
	Network.set_local_name(new_name)

func _on_host_setting_changed(_idx: int) -> void:
	if not Network.is_host:
		return
	_apply_host_settings_to_rules()

func _apply_host_settings_to_rules() -> void:
	var r := Game.rules
	if opt_game_mode:
		r.is_team_mode = (opt_game_mode.selected == 1)
	if opt_target_wins:
		r.target_round_wins = opt_target_wins.get_selected_id()
	if opt_team_count:
		r.team_count = opt_team_count.get_selected_id()
	if chk_friendly_fire:
		r.friendly_fire = chk_friendly_fire.button_pressed
	if opt_map:
		var map_idx := opt_map.selected
		if map_idx >= 0 and map_idx < MAP_NAMES.size():
			r.selected_map = MAP_NAMES[map_idx]

	if opt_team_count and opt_game_mode:
		opt_team_count.disabled = (opt_game_mode.selected == 0)

	Network.update_match_rules_from_host(r.to_dict())
	_refresh_player_cards()

func _sync_settings_from_game_rules() -> void:
	var r := Game.rules
	if opt_game_mode:
		opt_game_mode.select(1 if r.is_team_mode else 0)
	if opt_target_wins:
		for i in range(opt_target_wins.item_count):
			if opt_target_wins.get_item_id(i) == r.target_round_wins:
				opt_target_wins.select(i)
				break
	if opt_team_count:
		for i in range(opt_team_count.item_count):
			if opt_team_count.get_item_id(i) == r.team_count:
				opt_team_count.select(i)
				break
		if opt_game_mode:
			opt_team_count.disabled = not Network.is_host or not r.is_team_mode
	if chk_friendly_fire:
		chk_friendly_fire.button_pressed = r.friendly_fire
	if opt_map:
		var map_idx := MAP_NAMES.find(r.selected_map)
		if map_idx != -1:
			opt_map.select(map_idx)

	_refresh_player_cards()

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
