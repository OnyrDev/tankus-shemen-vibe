class_name DebugOverlayClass
extends CanvasLayer

## Оверлей отладки (Debug Mode / Overlay), вызываемый по клавише F3.
## Включает:
## 1. Мониторинг производительности и сети (Top-Left).
## 2. Цифровое отображение всех характеристик танка (Bottom-Left).
## 3. Интерактивный поиск, фильтрацию и добавление карт способностей (Right).

# --- Элементы производительности (Top-Left) ---
@onready var panel: PanelContainer = $PanelContainer
@onready var stats_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsLabel

# --- Цифровые статы танка (Bottom-Left) ---
@onready var tank_stats_panel: PanelContainer = $TankStatsPanel
@onready var tank_stats_header: Label = $TankStatsPanel/Margin/VBox/HeaderLabel
@onready var tank_status_label: Label = $TankStatsPanel/Margin/VBox/TankStatusLabel
@onready var stats_left: Label = $TankStatsPanel/Margin/VBox/StatsColumns/StatsLeft
@onready var stats_right: Label = $TankStatsPanel/Margin/VBox/StatsColumns/StatsRight

# --- Поиск и дебаггер карт (Right) ---
@onready var card_search_panel: PanelContainer = $CardSearchPanel
@onready var title_label: Label = $CardSearchPanel/Margin/VBox/HeaderHBox/Title
@onready var btn_toggle_cursor: Button = $CardSearchPanel/Margin/VBox/HeaderHBox/BtnToggleCursor
@onready var btn_close: Button = $CardSearchPanel/Margin/VBox/HeaderHBox/BtnClose
@onready var btn_clear_build: Button = $CardSearchPanel/Margin/VBox/QuickActionsHBox/BtnClearBuild
@onready var btn_random_card: Button = $CardSearchPanel/Margin/VBox/QuickActionsHBox/BtnRandomCard
@onready var btn_heal: Button = $CardSearchPanel/Margin/VBox/QuickActionsHBox/BtnHeal
@onready var search_box: LineEdit = $CardSearchPanel/Margin/VBox/SearchBox
@onready var btn_cat_all: Button = $CardSearchPanel/Margin/VBox/CategoryHBox/BtnCatAll
@onready var btn_cat_shot: Button = $CardSearchPanel/Margin/VBox/CategoryHBox/BtnCatShot
@onready var btn_cat_block: Button = $CardSearchPanel/Margin/VBox/CategoryHBox/BtnCatBlock
@onready var btn_cat_jump: Button = $CardSearchPanel/Margin/VBox/CategoryHBox/BtnCatJump
@onready var btn_cat_general: Button = $CardSearchPanel/Margin/VBox/CategoryHBox/BtnCatGeneral
@onready var cards_list_vbox: VBoxContainer = $CardSearchPanel/Margin/VBox/ScrollContainer/CardsListVBox
@onready var cards_count_label: Label = $CardSearchPanel/Margin/VBox/FooterHBox/CardsCountLabel

var _update_timer: float = 0.0
var _card_widgets: Dictionary = {} # card_id (String) -> Control
var _active_category: int = -1 # -1: All, 0: Shot, 1: Block, 2: Jump, 3: General

func _ready() -> void:
	visible = false
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS

	_connect_ui_events()
	_init_card_widgets()

	# Отключаем фокус у кнопок, чтобы они не перехватывали Tab-навигацию интерфейса
	for btn in [btn_toggle_cursor, btn_close, btn_clear_build, btn_random_card, btn_heal, btn_cat_all, btn_cat_shot, btn_cat_block, btn_cat_jump, btn_cat_general]:
		if btn:
			btn.focus_mode = Control.FOCUS_NONE

func _connect_ui_events() -> void:
	if btn_close:
		btn_close.pressed.connect(func(): set_debug_visible(false))

	if btn_toggle_cursor:
		btn_toggle_cursor.pressed.connect(_toggle_mouse_capture)

	if btn_clear_build:
		btn_clear_build.pressed.connect(_clear_tank_build)

	if btn_random_card:
		btn_random_card.pressed.connect(_add_random_card)

	if btn_heal:
		btn_heal.pressed.connect(_heal_tank)

	if search_box:
		search_box.text_changed.connect(_on_search_text_changed)
		search_box.focus_entered.connect(func(): _set_local_tank_input_enabled(false))
		search_box.focus_exited.connect(func():
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_set_local_tank_input_enabled(true)
		)

	if btn_cat_all:
		btn_cat_all.pressed.connect(func(): _select_category(-1))
	if btn_cat_shot:
		btn_cat_shot.pressed.connect(func(): _select_category(int(CardDefinition.Category.SHOT)))
	if btn_cat_block:
		btn_cat_block.pressed.connect(func(): _select_category(int(CardDefinition.Category.BLOCK)))
	if btn_cat_jump:
		btn_cat_jump.pressed.connect(func(): _select_category(int(CardDefinition.Category.JUMP)))
	if btn_cat_general:
		btn_cat_general.pressed.connect(func(): _select_category(int(CardDefinition.Category.GENERAL)))

var is_mouse_captured: bool = false

func _input(event: InputEvent) -> void:
	if _handle_debug_key(event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _handle_debug_key(event):
		get_viewport().set_input_as_handled()

func _handle_debug_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false

	if event.keycode == KEY_F3:
		toggle_debug()
		return true

	if visible:
		if event.keycode == KEY_ESCAPE:
			set_debug_visible(false)
			return true
		elif event.keycode == KEY_TAB or event.keycode == KEY_F4 or event.keycode == KEY_QUOTELEFT:
			_toggle_mouse_capture()
			return true

	return false

func toggle_debug() -> void:
	set_debug_visible(not visible)

func set_debug_visible(p_visible: bool) -> void:
	visible = p_visible
	is_mouse_captured = false
	if get_viewport():
		get_viewport().gui_release_focus()

	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if btn_toggle_cursor:
			btn_toggle_cursor.text = "Lock Mouse [Tab]"
		_update_card_stacks()
		_update_debug_text()
		_update_tank_stats()
		_adjust_bottom_left_panel_pos()
	else:
		_set_local_tank_input_enabled(true)
		var local_tank := _find_local_tank()
		if local_tank and local_tank.is_active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_mouse_capture() -> void:
	if not visible:
		return

	if get_viewport():
		get_viewport().gui_release_focus()

	is_mouse_captured = not is_mouse_captured

	if is_mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_local_tank_input_enabled(true)
		if btn_toggle_cursor:
			btn_toggle_cursor.text = "Free Mouse [Tab]"
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_local_tank_input_enabled(false)
		if btn_toggle_cursor:
			btn_toggle_cursor.text = "Lock Mouse [Tab]"

func _set_local_tank_input_enabled(enabled_val: bool) -> void:
	var tank := _find_local_tank()
	if tank and tank.input:
		tank.input.enabled = enabled_val

func _process(delta: float) -> void:
	if not visible:
		return

	_update_timer += delta
	if _update_timer >= 0.1: # 10 обновлений в секунду для чистоты и производительности
		_update_timer = 0.0
		_update_debug_text()
		_update_tank_stats()
		_adjust_bottom_left_panel_pos()

# --- Позиционирование левой нижней панели статов ---

func _adjust_bottom_left_panel_pos() -> void:
	if not tank_stats_panel:
		return
	var tree := get_tree()
	if not tree:
		return

	var hud: CanvasLayer = null
	var hud_nodes := tree.get_nodes_in_group("hud")
	if not hud_nodes.is_empty() and hud_nodes[0] is CanvasLayer:
		hud = hud_nodes[0] as CanvasLayer
	elif has_node("/root/HUD"):
		hud = get_node_or_null("/root/HUD") as CanvasLayer

	# Если HUD отображается, приподнимаем панель статов над шкалой здоровья
	if hud and hud.visible:
		tank_stats_panel.offset_bottom = -112.0
		tank_stats_panel.offset_top = -357.0
	else:
		tank_stats_panel.offset_bottom = -16.0
		tank_stats_panel.offset_top = -261.0

# --- Обновление цифровых статов танка (Bottom-Left) ---

func _update_tank_stats() -> void:
	if not tank_stats_panel:
		return

	var local_tank := _find_local_tank()
	if not local_tank or not is_instance_valid(local_tank):
		tank_stats_header.text = "[ TANK STATS - NO TANK ]"
		tank_status_label.text = "Status: Tank not spawned"
		stats_left.text = "HP: --\nMove Speed: --\nJump Vel: --\nAir Control: --\nDamage: --\nMagazine: --\nTank Scale: --\nKnockback: --"
		stats_right.text = "Proj Speed: --\nBounces: --\nProj Size: --\nFire Rate: --\nReload Time: --\nBlock Dur: --\nBlock CD: --\nLinear Vel: --"
		return

	var st := local_tank.stats
	var hp_curr := local_tank.health.current_health if local_tank.health else 0.0
	var hp_max := st.max_hp if st else (local_tank.health.max_health if local_tank.health else 100.0)
	var ammo_curr := local_tank.weapon.current_ammo if local_tank.weapon else 0
	var ammo_max := st.magazine_size if st else (local_tank.weapon.magazine_size if local_tank.weapon else 6)
	var speed_val := st.move_speed if st else 8.0
	var jump_val := st.jump_velocity if st else 8.0
	var air_ctrl := st.air_control if st else 1.0
	var dmg_val := st.damage if st else 28.0
	var proj_spd := st.projectile_speed if st else 24.0
	var bounces := st.projectile_bounces if st else 0
	var proj_sz := st.projectile_size if st else 1.0
	var fire_int := st.fire_interval if st else 0.55
	var rps := 1.0 / maxf(0.01, fire_int)
	var reload_t := st.reload_time if st else 1.8
	var block_dur := st.block_duration if st else 0.35
	var block_cd := st.block_cooldown if st else 3.0
	var scale_val := st.tank_scale if st else 1.0
	var knock_res := st.knockback_resistance if st else 1.0
	var cur_vel := local_tank.velocity.length()

	var card_count := local_tank.build.cards.size() if local_tank.build else 0
	var total_stacks := 0
	if local_tank.build:
		for cid in local_tank.build.cards:
			total_stacks += local_tank.build.cards[cid]

	tank_stats_header.text = "[ TANK STATS - NUMERIC ]"
	tank_status_label.text = "Tank: %s | Active: %s | Cards: %d (x%d)" % [
		local_tank.name,
		str(local_tank.is_active),
		card_count,
		total_stacks
	]

	stats_left.text = """HP:          %.1f / %.1f
Move Speed:  %.2f m/s
Jump Vel:    %.2f m/s
Air Control: %.2f
Damage:      %.1f
Magazine:    %d (Cur: %d)
Tank Scale:  %.2fx
Knockback:   %.2fx""" % [
		hp_curr, hp_max,
		speed_val,
		jump_val,
		air_ctrl,
		dmg_val,
		ammo_max, ammo_curr,
		scale_val,
		knock_res
	]

	stats_right.text = """Proj Speed:  %.1f m/s
Bounces:     %d
Proj Size:   %.2fx
Fire Rate:   %.2fs (%.1f/s)
Reload Time: %.2fs
Block Dur:   %.2fs
Block CD:    %.2fs
Linear Vel:  %.2f m/s""" % [
		proj_spd,
		bounces,
		proj_sz,
		fire_int, rps,
		reload_t,
		block_dur,
		block_cd,
		cur_vel
	]

# --- Инициализация и поиск карт (Right) ---

func _init_card_widgets() -> void:
	if not cards_list_vbox:
		return

	for child in cards_list_vbox.get_children():
		child.queue_free()
	_card_widgets.clear()

	var all_cards := CardDatabase.get_all_cards()
	all_cards.sort_custom(func(a: CardDefinition, b: CardDefinition) -> bool:
		return a.display_name.nocasecmp_to(b.display_name) < 0
	)

	for card in all_cards:
		var widget := _create_card_row_widget(card)
		cards_list_vbox.add_child(widget)
		_card_widgets[card.id] = widget

	_apply_card_filter()

func _create_card_row_widget(card: CardDefinition) -> Control:
	var panel_item := PanelContainer.new()
	panel_item.set_meta("card_def", card)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.9)
	sb.border_width_left = 2
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = card.get_category_color()
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left = 6
	panel_item.add_theme_stylebox_override("panel", sb)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel_item.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# Заголовочная строка
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	var badge := Label.new()
	badge.text = "[%s]" % card.get_category_name()
	badge.modulate = card.get_category_color()
	badge.add_theme_font_size_override("font_size", 10)
	header.add_child(badge)

	var name_lbl := Label.new()
	name_lbl.text = card.display_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var stacks_lbl := Label.new()
	stacks_lbl.name = "StacksLabel"
	stacks_lbl.add_theme_font_size_override("font_size", 11)
	stacks_lbl.modulate = Color(0.3, 0.95, 0.5)
	stacks_lbl.visible = false
	header.add_child(stacks_lbl)

	var btn_add := Button.new()
	btn_add.name = "BtnAdd"
	btn_add.focus_mode = Control.FOCUS_NONE
	btn_add.text = "+ Add"
	btn_add.add_theme_font_size_override("font_size", 10)
	btn_add.custom_minimum_size = Vector2(46, 22)
	btn_add.pressed.connect(func(): _add_card_to_tank(card))
	header.add_child(btn_add)

	var btn_del := Button.new()
	btn_del.name = "BtnDel"
	btn_del.focus_mode = Control.FOCUS_NONE
	btn_del.text = "- Del"
	btn_del.add_theme_font_size_override("font_size", 10)
	btn_del.custom_minimum_size = Vector2(46, 22)
	btn_del.disabled = true
	btn_del.modulate.a = 0.4
	btn_del.pressed.connect(func(): _remove_card_from_tank(card))
	header.add_child(btn_del)

	vbox.add_child(header)

	# Описание способности
	var desc_lbl := Label.new()
	desc_lbl.text = card.description
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.modulate = Color(0.8, 0.85, 0.9)
	vbox.add_child(desc_lbl)

	# Модификаторы параметров (если есть)
	if not card.stat_modifiers.is_empty():
		var mods_str: Array[String] = []
		for k in card.stat_modifiers:
			var val = card.stat_modifiers[k]
			if str(k).ends_with("_mult"):
				mods_str.append("%s: x%.2f" % [k.trim_suffix("_mult"), float(val)])
			else:
				mods_str.append("%s: %+d" % [k.trim_suffix("_flat"), int(val)])
		var mods_lbl := Label.new()
		mods_lbl.text = ", ".join(mods_str)
		mods_lbl.add_theme_font_size_override("font_size", 9)
		mods_lbl.modulate = Color(0.4, 0.85, 0.7)
		vbox.add_child(mods_lbl)

	return panel_item

func _on_search_text_changed(_new_text: String) -> void:
	_apply_card_filter()

func _select_category(cat: int) -> void:
	_active_category = cat
	if btn_cat_all:
		btn_cat_all.button_pressed = (cat == -1)
	if btn_cat_shot:
		btn_cat_shot.button_pressed = (cat == int(CardDefinition.Category.SHOT))
	if btn_cat_block:
		btn_cat_block.button_pressed = (cat == int(CardDefinition.Category.BLOCK))
	if btn_cat_jump:
		btn_cat_jump.button_pressed = (cat == int(CardDefinition.Category.JUMP))
	if btn_cat_general:
		btn_cat_general.button_pressed = (cat == int(CardDefinition.Category.GENERAL))
	_apply_card_filter()

func _apply_card_filter() -> void:
	var query := search_box.text.strip_edges().to_lower() if search_box else ""
	var visible_count := 0

	for cid in _card_widgets:
		var widget: Control = _card_widgets[cid]
		var card: CardDefinition = widget.get_meta("card_def")

		var match_search := true
		if not query.is_empty():
			var name_match: bool = card.display_name.to_lower().contains(query)
			var id_match: bool = card.id.to_lower().contains(query)
			var desc_match: bool = card.description.to_lower().contains(query)
			match_search = name_match or id_match or desc_match

		var match_cat := true
		if _active_category != -1:
			match_cat = (int(card.category) == _active_category)

		var is_shown: bool = match_search and match_cat
		widget.visible = is_shown
		if is_shown:
			visible_count += 1

	if cards_count_label:
		var tank := _find_local_tank()
		var build_cards := tank.build.cards.size() if (tank and tank.build) else 0
		cards_count_label.text = "Showing %d of %d cards | Local build: %d" % [
			visible_count,
			_card_widgets.size(),
			build_cards
		]

func _update_card_stacks() -> void:
	var tank := _find_local_tank()
	var tank_cards: Dictionary = tank.build.cards if (tank and tank.build) else {}

	for cid in _card_widgets:
		var widget: Control = _card_widgets[cid]
		var stacks_lbl: Label = widget.find_child("StacksLabel", true, false)
		var btn_del: Button = widget.find_child("BtnDel", true, false)

		var count: int = tank_cards.get(cid, 0)
		if count > 0:
			if stacks_lbl:
				stacks_lbl.text = "x%d" % count
				stacks_lbl.visible = true
			if btn_del:
				btn_del.disabled = false
				btn_del.modulate.a = 1.0
		else:
			if stacks_lbl:
				stacks_lbl.text = ""
				stacks_lbl.visible = false
			if btn_del:
				btn_del.disabled = true
				btn_del.modulate.a = 0.4

	_apply_card_filter()

# --- Быстрые действия дебага (Добавление/Удаление) ---

func _add_card_to_tank(card: CardDefinition) -> void:
	var tank := _find_local_tank()
	if not tank or not tank.build:
		return

	tank.build.add_card(card)

	if multiplayer.has_multiplayer_peer() and tank.net_sync:
		if not multiplayer.is_server():
			tank.net_sync.c2s_choose_card.rpc_id(1, card.id)
		else:
			if tank.stats:
				tank.net_sync.synced_tank_scale = tank.stats.tank_scale
			tank.net_sync.s2c_card_added.rpc(card.id)

	if SoundManager:
		SoundManager.play_sfx("card_select", 1.0)

	_update_card_stacks()
	_update_tank_stats()
	_update_debug_text()

func _remove_card_from_tank(card: CardDefinition) -> void:
	var tank := _find_local_tank()
	if not tank or not tank.build:
		return

	tank.build.remove_card(card)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and tank.net_sync and tank.stats:
		tank.net_sync.synced_tank_scale = tank.stats.tank_scale

	if SoundManager:
		SoundManager.play_sfx("card_hover", -2.0)

	_update_card_stacks()
	_update_tank_stats()
	_update_debug_text()

func _clear_tank_build() -> void:
	var tank := _find_local_tank()
	if not tank or not tank.build:
		return

	tank.build.clear_build()

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and tank.net_sync and tank.stats:
		tank.net_sync.synced_tank_scale = tank.stats.tank_scale

	if SoundManager:
		SoundManager.play_sfx("card_hover", 0.0)

	_update_card_stacks()
	_update_tank_stats()
	_update_debug_text()

func _add_random_card() -> void:
	var all_cards := CardDatabase.get_all_cards()
	if all_cards.is_empty():
		return
	var rand_card: CardDefinition = all_cards[randi() % all_cards.size()]
	_add_card_to_tank(rand_card)

func _heal_tank() -> void:
	var tank := _find_local_tank()
	if not tank or not tank.health:
		return
	tank.health.current_health = tank.health.max_health
	tank.health.health_changed.emit(tank.health.current_health, tank.health.max_health)
	if tank.net_sync:
		tank.net_sync.synced_health = tank.health.current_health
	_update_tank_stats()

# --- Системная информация (Top-Left) ---

func _update_debug_text() -> void:
	if not stats_label:
		return

	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(1.0, float(fps))
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)

	# Сетевой статус
	var net_mode := "STANDALONE"
	var peer_id := 1
	var ping := 0
	var peer_count := 1

	var net: Node = get_node_or_null("/root/Network")
	if net:
		peer_id = net.get_unique_id()
		if net.is_multiplayer_active():
			net_mode = "HOST" if net.is_server() else "CLIENT"
			ping = net.get_ping_ms()
			peer_count = net.players.size()
		else:
			net_mode = "STANDALONE"

	# Состояние матча
	var game_node: Node = get_node_or_null("/root/Game")
	var match_state: String = game_node.match_state if game_node else "UNKNOWN"
	var round_num: int = game_node.current_round if game_node else 0
	var map_name: String = game_node.rules.selected_map if game_node and game_node.rules else "None"

	# Локальный танк
	var tank_info := "Tank: Not Spawned"
	var local_tank := _find_local_tank()
	if local_tank and is_instance_valid(local_tank):
		var pos := local_tank.global_position
		var vel := local_tank.velocity.length()
		var hp := local_tank.health.current_health if local_tank.health else 0.0
		var max_hp := local_tank.health.max_health if local_tank.health else 0.0
		var ammo := local_tank.weapon.current_ammo if local_tank.weapon else 0
		var max_ammo := local_tank.weapon.magazine_size if local_tank.weapon else 0

		var cards_str := "None"
		if local_tank.build and not local_tank.build.cards.is_empty():
			var card_names: Array[String] = []
			for c in local_tank.build.cards:
				var count: int = local_tank.build.cards[c]
				card_names.append("%s x%d" % [c, count])
			cards_str = ", ".join(card_names)

		tank_info = "Pos: (%.1f, %.1f, %.1f) | Vel: %.1f m/s\nHP: %.0f/%.0f | Ammo: %d/%d\nCards: %s" % [
			pos.x, pos.y, pos.z, vel, hp, max_hp, ammo, max_ammo, cards_str
		]

		if local_tank.net_sync:
			var sync := local_tank.net_sync
			tank_info += "\nPrediction: %s | Simulated movement RTT: %d ms\nPending inputs: %d | Last correction: %.3f m" % [
				"ON" if sync.prediction_enabled else "OFF", sync.simulated_latency_ms * 2,
				sync.get_pending_input_count(), sync.last_correction_distance]

	var text := """[ PERFORMANCE ]
FPS: %d (%.2f ms)
Draw Calls: %d | Mem: %.1f MB

[ NETWORK ]
Mode: %s | Peer ID: %d
Ping: %d ms | Peers: %d

[ MATCH ]
State: %s | Round: %d
Map: %s

[ LOCAL PLAYER ]
%s""" % [
		fps, frame_ms, draw_calls, mem_mb,
		net_mode, peer_id, ping, peer_count,
		match_state, round_num, map_name,
		tank_info
	]

	stats_label.text = text

func _find_local_tank() -> Tank:
	var tree := get_tree()
	if not tree:
		return null

	var net: Node = get_node_or_null("/root/Network")
	var my_id: int = net.get_unique_id() if net else 1
	var tanks := tree.get_nodes_in_group("tanks")
	for node in tanks:
		if node is Tank:
			if node.net_sync and node.net_sync.is_local_owner():
				return node as Tank
			elif node.input and node.input.enabled:
				return node as Tank
			elif node.peer_id == my_id:
				return node as Tank

	if not tanks.is_empty() and tanks[0] is Tank:
		return tanks[0] as Tank

	return null
