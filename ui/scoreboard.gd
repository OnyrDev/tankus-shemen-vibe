class_name Scoreboard
extends CanvasLayer

## Таблица счета и билдов TANKUS (Scoreboard).
## Открывается по нажатию/удержанию клавиши Tab (action: scoreboard).
## Отображает для каждого участника: цвет команды, ник, статус (жив/мертв),
## число побед в раундах, пинг и все собранные карты билда со стаками.

@onready var panel_container: PanelContainer = $Panel
@onready var lbl_match_header: Label = $Panel/Margin/VBox/Header/LblTitle
@onready var lbl_target_wins: Label = $Panel/Margin/VBox/Header/LblTargetWins
@onready var player_rows_container: VBoxContainer = $Panel/Margin/VBox/Scroll/PlayerRows

@export var tanks_container: Node3D = null

const TEAM_COLORS: Array[Color] = [
	Color(0.18, 0.55, 0.95), # Синий
	Color(0.95, 0.25, 0.25), # Красный
	Color(0.2, 0.85, 0.35),  # Зеленый
	Color(0.95, 0.75, 0.15), # Желтый
	Color(0.75, 0.25, 0.95), # Фиолетовый
	Color(0.15, 0.85, 0.85), # Бирюзовый
	Color(0.95, 0.5, 0.15),  # Оранжевый
	Color(0.85, 0.85, 0.85)  # Серый
]

func _ready() -> void:
	layer = 20 # Поверх обычного HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _process(_delta: float) -> void:
	if visible:
		_refresh_scoreboard()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("scoreboard"):
		if event.is_pressed():
			show_scoreboard()
		else:
			hide_scoreboard()

func show_scoreboard() -> void:
	visible = true
	_refresh_scoreboard()

func hide_scoreboard() -> void:
	visible = false

func _refresh_scoreboard() -> void:
	if not player_rows_container:
		return

	if lbl_target_wins:
		var mode_name := "Командный бой" if Game.rules.is_team_mode else "Каждый сам за себя"
		lbl_target_wins.text = "%s • Цель: %d побед в раундах" % [mode_name, Game.rules.target_round_wins]

	for child in player_rows_container.get_children():
		player_rows_container.remove_child(child)
		child.queue_free()

	var my_id := Network.get_unique_id()
	var all_players := Network.get_all_players()

	# Сортируем: сначала больше побед
	all_players.sort_custom(func(a: PlayerInfo, b: PlayerInfo):
		return a.round_wins > b.round_wins
	)

	for p in all_players:
		if not (p is PlayerInfo):
			continue
		var row := _create_player_row(p, p.peer_id == my_id)
		player_rows_container.add_child(row)

func _create_player_row(player: PlayerInfo, is_me: bool) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 52)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	var team_col := TEAM_COLORS[(player.team_id - 1) % TEAM_COLORS.size()] if player.team_id > 0 else TEAM_COLORS[0]
	style.border_width_left = 4
	style.border_color = team_col
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	row.add_child(hbox)

	# Статус Жив / Уничтожен
	var tank := _find_tank_by_peer_id(player.peer_id)
	var is_alive := true
	if tank:
		is_alive = tank.is_active and tank.health and tank.health.current_health > 0

	var status_lbl := Label.new()
	status_lbl.custom_minimum_size = Vector2(24, 0)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_alive:
		status_lbl.text = "●"
		status_lbl.modulate = Color(0.2, 0.9, 0.35) # Зеленая точка
	else:
		status_lbl.text = "💀"
		status_lbl.modulate = Color(0.9, 0.3, 0.3)
	hbox.add_child(status_lbl)

	# Имя игрока
	var name_lbl := Label.new()
	var host_str := " [ХОСТ]" if player.peer_id == 1 else ""
	var me_str := " [ВЫ]" if is_me else ""
	name_lbl.text = "%s%s%s" % [player.player_name, host_str, me_str]
	name_lbl.custom_minimum_size = Vector2(170, 0)
	name_lbl.modulate = Color.WHITE if is_alive else Color(0.6, 0.6, 0.65)
	hbox.add_child(name_lbl)

	# Команда
	if Game.rules.is_team_mode:
		var team_lbl := Label.new()
		team_lbl.text = "Т-%d" % player.team_id
		team_lbl.modulate = team_col
		team_lbl.custom_minimum_size = Vector2(45, 0)
		hbox.add_child(team_lbl)

	# Победы в раундах
	var score_lbl := Label.new()
	score_lbl.text = "★ %d / %d" % [player.round_wins, Game.rules.target_round_wins]
	score_lbl.custom_minimum_size = Vector2(85, 0)
	score_lbl.modulate = Color(1.0, 0.85, 0.2)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(score_lbl)

	# Пинг
	var ping_lbl := Label.new()
	ping_lbl.custom_minimum_size = Vector2(60, 0)
	ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	hbox.add_child(ping_lbl)

	var vsep := VSeparator.new()
	hbox.add_child(vsep)

	# Список собранных карт билда (чипы)
	var cards_container := HFlowContainer.new()
	cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_container.add_theme_constant_override("h_separation", 6)
	cards_container.add_theme_constant_override("v_separation", 4)
	hbox.add_child(cards_container)

	if tank and tank.build and not tank.build.ordered_cards.is_empty():
		for card_id in tank.build.ordered_cards:
			var card_def := CardDatabase.get_card(card_id)
			if not card_def:
				continue

			var stacks: int = tank.build.get_stacks(card_id)
			var chip := PanelContainer.new()
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
			chip_style.border_width_left = 1
			chip_style.border_width_top = 1
			chip_style.border_width_right = 1
			chip_style.border_width_bottom = 1
			chip_style.border_color = card_def.get_category_color()
			chip_style.corner_radius_top_left = 4
			chip_style.corner_radius_top_right = 4
			chip_style.corner_radius_bottom_right = 4
			chip_style.corner_radius_bottom_left = 4
			chip_style.content_margin_left = 6
			chip_style.content_margin_right = 6
			chip_style.content_margin_top = 2
			chip_style.content_margin_bottom = 2
			chip.add_theme_stylebox_override("panel", chip_style)

			var chip_lbl := Label.new()
			if stacks > 1:
				chip_lbl.text = "%s ×%d" % [card_def.display_name, stacks]
			else:
				chip_lbl.text = card_def.display_name
			chip_lbl.add_theme_font_size_override("font_size", 11)
			chip_lbl.modulate = card_def.get_category_color()
			chip.add_child(chip_lbl)

			cards_container.add_child(chip)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = "Базовый танк (нет карт)"
		empty_lbl.modulate = Color(0.5, 0.55, 0.6)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		cards_container.add_child(empty_lbl)

	return row

func _find_tank_by_peer_id(peer_id: int) -> Tank:
	if not tanks_container:
		return null

	var t_name := "Tank_%d" % peer_id
	var t := tanks_container.get_node_or_null(t_name) as Tank
	if t:
		return t

	for child in tanks_container.get_children():
		if child is Tank and child.peer_id == peer_id:
			return child

	return null
