class_name Lobby
extends CanvasLayer

## Экран сетевого лобби TANKUS.
## Отображает список подключенных игроков, управление готовностью,
## выбор команд, настройки матча хостом (режим FFA/Команды, целевые победы, карта)
## и запуск раундового матча.

signal match_start_requested()
signal lobby_left()

@onready var panel_container: PanelContainer = $Panel
@onready var lbl_header: Label = $Panel/Margin/VBox/Header/LblHeader
@onready var lbl_room_status: Label = $Panel/Margin/VBox/Header/LblStatus

# Список игроков
@onready var player_list_vbox: VBoxContainer = $Panel/Margin/VBox/HSplit/LeftPanel/PlayerScroll/PlayerList

# Настройки матча (Хост)
@onready var host_settings_panel: VBoxContainer = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings
@onready var opt_game_mode: OptionButton = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/GridSettings/OptGameMode
@onready var opt_target_wins: OptionButton = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/GridSettings/OptTargetWins
@onready var opt_team_count: OptionButton = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/GridSettings/OptTeamCount
@onready var chk_friendly_fire: CheckBox = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/GridSettings/ChkFriendlyFire
@onready var opt_map: OptionButton = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/GridSettings/OptMap
@onready var lbl_host_only_hint: Label = $Panel/Margin/VBox/HSplit/RightPanel/HostSettings/LblHostOnlyHint

# Нижняя панель действий
@onready var btn_ready: Button = $Panel/Margin/VBox/Footer/HBox/BtnReady
@onready var btn_start_match: Button = $Panel/Margin/VBox/Footer/HBox/BtnStartMatch
@onready var btn_leave_lobby: Button = $Panel/Margin/VBox/Footer/HBox/BtnLeaveLobby
@onready var line_edit_name: LineEdit = $Panel/Margin/VBox/Footer/HBox/LineEditName

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

var _is_local_ready: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_ui_options()
	_connect_signals()
	_update_lobby_ui()

	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_lobby() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_is_local_ready = false
	_update_ready_button_text()
	_sync_settings_from_game_rules()
	_update_lobby_ui()

func close_lobby() -> void:
	visible = false

func _connect_signals() -> void:
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_ready_changed.connect(func(_pid, _ready): _on_player_list_updated())
	Network.match_rules_updated.connect(_sync_settings_from_game_rules)
	Network.server_closed.connect(close_lobby)
	Network.server_disconnected.connect(close_lobby)
	Game.match_state_changed.connect(_on_match_state_changed)

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

func _on_match_state_changed(new_state: String) -> void:
	if new_state in ["PREPARE", "DRAFT", "COUNTDOWN", "PLAYING", "ROUND_END", "MATCH_END"]:
		close_lobby()

@rpc("authority", "reliable", "call_local")
func s2c_close_lobby() -> void:
	close_lobby()

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
		opt_map.add_item("Sky Courtyard (Test Sandbox)", 0)

func _update_lobby_ui() -> void:
	var is_host: bool = Network.is_host or not Network.is_multiplayer_active()

	if lbl_header:
		lbl_header.text = "TANKUS — ЛОББИ МАТЧА"
	if lbl_room_status:
		if is_host:
			lbl_room_status.text = "Статус: Вы хост комнаты"
			lbl_room_status.modulate = Color(0.3, 0.9, 0.4)
		else:
			lbl_room_status.text = "Статус: Подключено к серверу"
			lbl_room_status.modulate = Color(0.3, 0.7, 1.0)

	# Настройки матча доступны для редактирования только хосту
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
	if lbl_host_only_hint:
		lbl_host_only_hint.visible = not is_host

	if btn_ready:
		btn_ready.visible = not is_host

	if btn_start_match:
		btn_start_match.visible = is_host
		_check_start_button_state()

	_refresh_player_cards()

func _check_start_button_state() -> void:
	if not btn_start_match or not Network.is_host:
		return

	var all_players := Network.get_all_players()
	var all_ready := true
	for p in all_players:
		if p is PlayerInfo and p.peer_id != 1: # клиентов проверяем
			if not p.is_ready:
				all_ready = false
				break

	if all_players.size() <= 1:
		btn_start_match.disabled = false
		btn_start_match.text = "СТАРТ В СОЛО"
	elif all_ready:
		btn_start_match.disabled = false
		btn_start_match.text = "НАЧАТЬ МАТЧ"
	else:
		btn_start_match.disabled = true
		btn_start_match.text = "НАЧАТЬ МАТЧ (Ожидание игроков)"

func _on_player_list_updated() -> void:
	_refresh_player_cards()
	_check_start_button_state()

func _refresh_player_cards() -> void:
	if not player_list_vbox:
		return

	for child in player_list_vbox.get_children():
		player_list_vbox.remove_child(child)
		child.queue_free()

	var my_id := Network.get_unique_id()
	var players_list := Network.get_all_players()

	for p in players_list:
		if not (p is PlayerInfo):
			continue

		var card := _create_player_card(p, p.peer_id == my_id)
		player_list_vbox.add_child(card)

func _create_player_card(player: PlayerInfo, is_me: bool) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 48)

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.11, 0.13, 0.18, 0.9)
	row_style.corner_radius_top_left = 6
	row_style.corner_radius_top_right = 6
	row_style.corner_radius_bottom_right = 6
	row_style.corner_radius_bottom_left = 6
	row_style.content_margin_left = 12
	row_style.content_margin_right = 12
	row_style.content_margin_top = 8
	row_style.content_margin_bottom = 8

	var team_color := TEAM_COLORS[(player.team_id - 1) % TEAM_COLORS.size()] if player.team_id > 0 else TEAM_COLORS[0]
	row_style.border_width_left = 4
	row_style.border_color = team_color
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	# Имя и роли
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
			team_btn.custom_minimum_size = Vector2(95, 0)
			team_btn.pressed.connect(func():
				var next_team := (player.team_id % Game.rules.team_count) + 1
				Network.set_local_team(next_team)
			)
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
	ready_badge.custom_minimum_size = Vector2(85, 0)
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

	return row

func _on_btn_ready_pressed() -> void:
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
	if not Network.is_host and Network.is_multiplayer_active():
		return

	if multiplayer.has_multiplayer_peer():
		s2c_close_lobby.rpc()
	else:
		close_lobby()

	# Передаем актуальные настройки в Game.rules
	_apply_host_settings_to_rules()
	match_start_requested.emit()


func _on_btn_leave_lobby_pressed() -> void:
	Network.disconnect_session()
	close_lobby()
	lobby_left.emit()

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
		opt_team_count.disabled = not r.is_team_mode or not Network.is_host
	if chk_friendly_fire:
		chk_friendly_fire.button_pressed = r.friendly_fire

	_refresh_player_cards()
