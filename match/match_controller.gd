class_name MatchController
extends Node

## Контроллер матча и раундов TANKUS (Server-Authoritative).
## Управляет полным жизненным циклом матча по правилам ROUNDS:
## PREPARE -> DRAFT (все в раунде 1 / проигравшие в раундах 2+) ->
## COUNTDOWN (3..2..1) -> PLAYING (1 жизнь) -> ROUND_END -> MATCH_END.

signal match_started()
signal round_started(round_number: int)
signal round_ended(winner_peer_or_team: int, is_team: bool)
signal match_ended(winner_peer_or_team: int, is_team: bool)
signal rematch_started()
signal returned_to_lobby()

enum State {
	IDLE,
	PREPARE,
	DRAFT,
	COUNTDOWN,
	PLAYING,
	ROUND_END,
	MATCH_END
}

var current_state: State = State.IDLE
var current_round: int = 0
var last_round_winner_id: int = -1 # peer_id (FFA) или team_id (Teams), -1 = Draw

@export var spawned_tanks_container: Node3D = null
@export var spawn_points_container: Node3D = null
@export var camera: TPSCamera = null
@export var hud: HUD = null
@export var card_draft: CardDraft = null
@export var lobby: Lobby = null


# UI ноды оверлеев
var _ui_layer: CanvasLayer = null
var _lbl_countdown: Label = null
var _pnl_round_end: PanelContainer = null
var _lbl_round_end_title: Label = null
var _lbl_round_end_sub: Label = null
var _pnl_waiting_draft: PanelContainer = null
var _pnl_spectator: PanelContainer = null
var _lbl_spectator_name: Label = null
var _pnl_match_end: PanelContainer = null
var _lbl_match_end_winner: Label = null
var _lbl_match_end_scores: Label = null
var _btn_rematch: Button = null
var _btn_lobby: Button = null

# Серверное отслеживание драфта
var _pending_draft_peers: Array[int] = []
var _countdown_timer: float = 0.0
var _countdown_value: int = 3
var _round_check_timer: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui_overlays()
	Game.match_state_changed.connect(_on_game_state_changed)

func _is_server() -> bool:
	return Network.is_server()

func _get_unique_id() -> int:
	return Network.get_unique_id()

# --- Создание процедурного интерфейса оверлеев матча ---

func _create_ui_overlays() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MatchUILayer"
	_ui_layer.layer = 15
	add_child(_ui_layer)

	# 1. Оверлей обратного отсчета (COUNTDOWN)
	_lbl_countdown = Label.new()
	_lbl_countdown.name = "CountdownLabel"
	_lbl_countdown.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_lbl_countdown.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lbl_countdown.grow_vertical = Control.GROW_DIRECTION_BOTH
	_lbl_countdown.add_theme_font_size_override("font_size", 96)
	_lbl_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_countdown.visible = false
	_ui_layer.add_child(_lbl_countdown)

	# 2. Оверлей конца раунда (ROUND_END)
	_pnl_round_end = PanelContainer.new()
	_pnl_round_end.name = "RoundEndPanel"
	_pnl_round_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pnl_round_end.offset_left = -300
	_pnl_round_end.offset_right = 300
	_pnl_round_end.offset_top = -100
	_pnl_round_end.offset_bottom = 100
	_pnl_round_end.visible = false
	var re_style := StyleBoxFlat.new()
	re_style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	re_style.corner_radius_top_left = 12
	re_style.corner_radius_top_right = 12
	re_style.corner_radius_bottom_right = 12
	re_style.corner_radius_bottom_left = 12
	re_style.border_width_left = 3
	re_style.border_width_top = 3
	re_style.border_width_right = 3
	re_style.border_width_bottom = 3
	re_style.border_color = Color(0.95, 0.75, 0.2)
	_pnl_round_end.add_theme_stylebox_override("panel", re_style)

	var re_vbox := VBoxContainer.new()
	re_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_pnl_round_end.add_child(re_vbox)

	_lbl_round_end_title = Label.new()
	_lbl_round_end_title.add_theme_font_size_override("font_size", 28)
	_lbl_round_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	re_vbox.add_child(_lbl_round_end_title)

	_lbl_round_end_sub = Label.new()
	_lbl_round_end_sub.add_theme_font_size_override("font_size", 16)
	_lbl_round_end_sub.modulate = Color(0.75, 0.8, 0.85)
	_lbl_round_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	re_vbox.add_child(_lbl_round_end_sub)
	_ui_layer.add_child(_pnl_round_end)

	# 3. Ожидание драфта проигравшими (для победителей)
	_pnl_waiting_draft = PanelContainer.new()
	_pnl_waiting_draft.name = "WaitingDraftPanel"
	_pnl_waiting_draft.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_pnl_waiting_draft.offset_left = 300
	_pnl_waiting_draft.offset_right = -300
	_pnl_waiting_draft.offset_top = 30
	_pnl_waiting_draft.offset_bottom = 90
	_pnl_waiting_draft.visible = false
	var wd_style := StyleBoxFlat.new()
	wd_style.bg_color = Color(0.1, 0.12, 0.16, 0.9)
	wd_style.corner_radius_top_left = 8
	wd_style.corner_radius_top_right = 8
	wd_style.corner_radius_bottom_right = 8
	wd_style.corner_radius_bottom_left = 8
	_pnl_waiting_draft.add_theme_stylebox_override("panel", wd_style)

	var wd_lbl := Label.new()
	wd_lbl.text = "Вы победили в раунде!\nОжидание выбора способностей проигравшими соперниками..."
	wd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wd_lbl.add_theme_font_size_override("font_size", 15)
	_pnl_waiting_draft.add_child(wd_lbl)
	_ui_layer.add_child(_pnl_waiting_draft)

	# 4. Панель спектатора (SPECTATOR)
	_pnl_spectator = PanelContainer.new()
	_pnl_spectator.name = "SpectatorPanel"
	_pnl_spectator.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_pnl_spectator.offset_left = 320
	_pnl_spectator.offset_right = -320
	_pnl_spectator.offset_bottom = -20
	_pnl_spectator.offset_top = -80
	_pnl_spectator.visible = false
	var spec_style := StyleBoxFlat.new()
	spec_style.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	spec_style.corner_radius_top_left = 8
	spec_style.corner_radius_top_right = 8
	spec_style.corner_radius_bottom_right = 8
	spec_style.corner_radius_bottom_left = 8
	_pnl_spectator.add_theme_stylebox_override("panel", spec_style)

	var spec_vbox := VBoxContainer.new()
	spec_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_pnl_spectator.add_child(spec_vbox)

	_lbl_spectator_name = Label.new()
	_lbl_spectator_name.text = "ВЫ ПОГИБЛИ. НАБЛЮДЕНИЕ ЗА: ..."
	_lbl_spectator_name.modulate = Color(0.95, 0.35, 0.35)
	_lbl_spectator_name.add_theme_font_size_override("font_size", 16)
	_lbl_spectator_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_vbox.add_child(_lbl_spectator_name)

	var spec_hint := Label.new()
	spec_hint.text = "[ЛКМ / ПКМ] Следующий / Предыдущий игрок"
	spec_hint.modulate = Color(0.7, 0.75, 0.8)
	spec_hint.add_theme_font_size_override("font_size", 12)
	spec_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_vbox.add_child(spec_hint)
	_ui_layer.add_child(_pnl_spectator)

	# 5. Оверлей победы в матче (MATCH_END)
	_pnl_match_end = PanelContainer.new()
	_pnl_match_end.name = "MatchEndPanel"
	_pnl_match_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pnl_match_end.offset_left = -340
	_pnl_match_end.offset_right = 340
	_pnl_match_end.offset_top = -200
	_pnl_match_end.offset_bottom = 200
	_pnl_match_end.visible = false
	var me_style := StyleBoxFlat.new()
	me_style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	me_style.border_width_left = 3
	me_style.border_width_top = 3
	me_style.border_width_right = 3
	me_style.border_width_bottom = 3
	me_style.border_color = Color(1.0, 0.85, 0.2)
	me_style.corner_radius_top_left = 16
	me_style.corner_radius_top_right = 16
	me_style.corner_radius_bottom_right = 16
	me_style.corner_radius_bottom_left = 16
	me_style.content_margin_left = 24
	me_style.content_margin_right = 24
	me_style.content_margin_top = 20
	me_style.content_margin_bottom = 20
	_pnl_match_end.add_theme_stylebox_override("panel", me_style)

	var me_vbox := VBoxContainer.new()
	me_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	me_vbox.add_theme_constant_override("separation", 14)
	_pnl_match_end.add_child(me_vbox)

	var me_cup := Label.new()
	me_cup.text = "🏆 МАТЧ ЗАВЕРШЁН 🏆"
	me_cup.add_theme_font_size_override("font_size", 24)
	me_cup.modulate = Color(1.0, 0.85, 0.2)
	me_cup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me_vbox.add_child(me_cup)

	_lbl_match_end_winner = Label.new()
	_lbl_match_end_winner.add_theme_font_size_override("font_size", 22)
	_lbl_match_end_winner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me_vbox.add_child(_lbl_match_end_winner)

	_lbl_match_end_scores = Label.new()
	_lbl_match_end_scores.add_theme_font_size_override("font_size", 14)
	_lbl_match_end_scores.modulate = Color(0.8, 0.85, 0.9)
	_lbl_match_end_scores.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	me_vbox.add_child(_lbl_match_end_scores)

	var me_btn_hbox := HBoxContainer.new()
	me_btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	me_btn_hbox.add_theme_constant_override("separation", 16)
	me_vbox.add_child(me_btn_hbox)

	_btn_rematch = Button.new()
	_btn_rematch.text = "РЕВАНШ"
	_btn_rematch.custom_minimum_size = Vector2(140, 42)
	_btn_rematch.pressed.connect(_on_btn_rematch_pressed)
	me_btn_hbox.add_child(_btn_rematch)

	_btn_lobby = Button.new()
	_btn_lobby.text = "В ЛОББИ"
	_btn_lobby.custom_minimum_size = Vector2(140, 42)
	_btn_lobby.pressed.connect(_on_btn_lobby_pressed)
	me_btn_hbox.add_child(_btn_lobby)

	_ui_layer.add_child(_pnl_match_end)

# --- Управление матчем (Хост/Сервер) ---

func start_new_match() -> void:
	if not _is_server():
		return

	current_round = 0
	last_round_winner_id = -1
	_pending_draft_peers.clear()

	# Сбрасываем очки побед у всех игроков
	for p in Network.get_all_players():
		if p is PlayerInfo:
			p.round_wins = 0
			p.is_alive = true
	Network._sync_all_players.rpc(Network._get_players_data_array())

	s2c_match_started.rpc(Game.rules.to_dict())

	# Переход к подготовке первого раунда
	_server_prepare_round()

func _server_prepare_round() -> void:
	if not _is_server():
		return

	current_round += 1
	current_state = State.PREPARE
	Game.set_match_state("PREPARE")

	# Помечаем всех игроков живыми
	for p in Network.get_all_players():
		if p is PlayerInfo:
			p.is_alive = true
	Network._sync_all_players.rpc(Network._get_players_data_array())

	# Возвращаем ВСЕ танки на спавн-позиции до начала драфта
	_server_reset_and_place_tanks()

	# В 1-м раунде ВСЕ игроки драфтят первую карту
	if current_round == 1:
		_server_start_draft_phase(true)
	else:
		# Во 2+ раундах драфтят только проигравшие
		_server_start_draft_phase(false)

func _server_start_draft_phase(all_draft: bool) -> void:
	current_state = State.DRAFT
	Game.set_match_state("DRAFT")

	_pending_draft_peers.clear()
	var all_players := Network.get_all_players()

	for p in all_players:
		if not (p is PlayerInfo):
			continue

		var should_draft := false
		if all_draft:
			should_draft = true
		else:
			# Проигравшие драфтят
			if Game.rules.is_team_mode:
				should_draft = (p.team_id != last_round_winner_id)
			else:
				should_draft = (p.peer_id != last_round_winner_id)

		if should_draft:
			_pending_draft_peers.append(p.peer_id)

	# Если по какой-то причине драфтовать некому (например 1 игрок в соло-тесте), сразу переходим к отсчету
	if _pending_draft_peers.is_empty():
		_server_start_countdown()
		return

	s2c_start_draft.rpc(_pending_draft_peers)

	# Серверный предохранитель по таймауту драфта (22 сек)
	get_tree().create_timer(Game.rules.draft_timeout_sec + 2.0).timeout.connect(func():
		if current_state == State.DRAFT:
			_server_force_finish_draft()
	)

func _server_force_finish_draft() -> void:
	if current_state != State.DRAFT:
		return
	_pending_draft_peers.clear()
	s2c_close_all_drafts.rpc()
	_server_start_countdown()

@rpc("any_peer", "reliable")
func c2s_report_draft_chosen(card_id: String) -> void:
	if not _is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_pending_draft_peers.erase(sender_id)

	# Если все драфтующие сделали выбор, запускаем раунд
	if _pending_draft_peers.is_empty() and current_state == State.DRAFT:
		s2c_close_all_drafts.rpc()
		_server_start_countdown()

func _server_start_countdown() -> void:
	current_state = State.COUNTDOWN
	Game.set_match_state("COUNTDOWN")

	# Спавним/расставляем и сбрасываем танки перед раундом
	_server_reset_and_place_tanks()

	_countdown_value = 3
	_countdown_timer = 0.0
	s2c_countdown_tick.rpc(_countdown_value)

func _server_reset_and_place_tanks() -> void:
	if not spawned_tanks_container:
		return

	# Очищаем снаряды, оставшиеся с предыдущего раунда
	var scn := get_tree().current_scene
	if scn and scn.has_node("Projectiles"):
		var p_node := scn.get_node("Projectiles")
		for p in p_node.get_children():
			p.queue_free()

	if multiplayer.has_multiplayer_peer():
		s2c_reset_and_place_tanks.rpc()
	else:
		s2c_reset_and_place_tanks()

func _server_start_combat() -> void:
	current_state = State.PLAYING
	Game.set_match_state("PLAYING")

	var tanks := _get_all_tanks()
	for t in tanks:
		t.is_active = true
		t.is_frozen = false

	s2c_combat_started.rpc(current_round)

func _set_all_tanks_frozen(frozen: bool) -> void:
	for t in _get_all_tanks():
		t.is_frozen = frozen

func _process(delta: float) -> void:
	if not _is_server():
		return

	if current_state == State.COUNTDOWN:
		_countdown_timer += delta
		if _countdown_timer >= 1.0:
			_countdown_timer = 0.0
			_countdown_value -= 1
			s2c_countdown_tick.rpc(_countdown_value)
			if _countdown_value <= 0:
				_server_start_combat()

	elif current_state == State.PLAYING:
		_round_check_timer += delta
		if _round_check_timer >= 0.25:
			_round_check_timer = 0.0
			_server_check_round_end_condition()

func _server_check_round_end_condition() -> void:
	if current_state != State.PLAYING:
		return

	var alive_tanks := _get_alive_tanks()
	var total_tanks := _get_all_tanks()

	if total_tanks.is_empty():
		return

	# Для теста в одиночку: если игрок погиб, раунд завершен
	if total_tanks.size() == 1:
		if alive_tanks.is_empty():
			_server_end_round(-1)
		return

	if Game.rules.is_team_mode:
		var alive_teams: Dictionary = {}
		for t in alive_tanks:
			alive_teams[t.team_id] = true

		if alive_teams.size() <= 1:
			var winning_team := -1
			if alive_teams.size() == 1:
				winning_team = alive_teams.keys()[0]
			_server_end_round(winning_team)
	else:
		# FFA: ждем пока останется 1 или 0
		if alive_tanks.size() <= 1:
			var winner_peer := -1
			if alive_tanks.size() == 1:
				winner_peer = alive_tanks[0].peer_id
			_server_end_round(winner_peer)

func _server_end_round(winner_id: int) -> void:
	current_state = State.ROUND_END
	Game.set_match_state("ROUND_END")
	last_round_winner_id = winner_id

	# Начисляем очко победителю
	if winner_id != -1:
		if Game.rules.is_team_mode:
			for p in Network.get_all_players():
				if p is PlayerInfo and p.team_id == winner_id:
					p.round_wins += 1
		else:
			var winner_info := Network.get_player_info(winner_id)
			if winner_info:
				winner_info.round_wins += 1

	Network._sync_all_players.rpc(Network._get_players_data_array())

	# Проверяем победу в матче
	var match_winner_id := _server_check_match_winner()
	if match_winner_id != -1:
		_server_end_match(match_winner_id)
	else:
		s2c_round_ended.rpc(winner_id, Game.rules.is_team_mode, current_round)
		# Через 3.5 секунды переходим к драфту/следующему раунду
		get_tree().create_timer(3.5).timeout.connect(func():
			if current_state == State.ROUND_END:
				_server_prepare_round()
		)

func _server_check_match_winner() -> int:
	var target := Game.rules.target_round_wins
	if Game.rules.is_team_mode:
		var team_wins: Dictionary = {}
		for p in Network.get_all_players():
			if p is PlayerInfo:
				team_wins[p.team_id] = max(team_wins.get(p.team_id, 0), p.round_wins)
		for t_id in team_wins.keys():
			if team_wins[t_id] >= target:
				return t_id
	else:
		for p in Network.get_all_players():
			if p is PlayerInfo and p.round_wins >= target:
				return p.peer_id
	return -1

func _server_end_match(winner_id: int) -> void:
	current_state = State.MATCH_END
	Game.set_match_state("MATCH_END")
	s2c_match_ended.rpc(winner_id, Game.rules.is_team_mode)

# --- Вспомогательные функции получения танков и спавнов ---

func _get_all_tanks() -> Array[Tank]:
	var list: Array[Tank] = []
	if spawned_tanks_container:
		for child in spawned_tanks_container.get_children():
			if child is Tank:
				list.append(child)
	return list

func _get_alive_tanks() -> Array[Tank]:
	var list: Array[Tank] = []
	for t in _get_all_tanks():
		if t.is_active and t.health and t.health.current_health > 0:
			list.append(t)
	return list

func _get_spawn_transform_for_slot(slot: int) -> Transform3D:
	if spawn_points_container and spawn_points_container.get_child_count() > 0:
		var cnt := spawn_points_container.get_child_count()
		var marker := spawn_points_container.get_child(slot % cnt) as Marker3D
		if marker:
			return marker.global_transform
	return Transform3D.IDENTITY

func _get_spawn_transform_for_tank(tank: Tank, index: int) -> Transform3D:
	if tank.spawn_point != Transform3D.IDENTITY:
		return tank.spawn_point
	return _get_spawn_transform_for_slot(index)

# --- Клиентские RPC обработчики событий ---

@rpc("authority", "reliable", "call_local")
func s2c_reset_and_place_tanks() -> void:
	_stop_spectating()
	if _pnl_round_end:
		_pnl_round_end.visible = false

	var tanks := _get_all_tanks()
	for i in range(tanks.size()):
		var t := tanks[i]
		var spawn_tf := _get_spawn_transform_for_tank(t, i)
		t.respawn(spawn_tf)
		t.is_frozen = true

@rpc("authority", "reliable", "call_local")
func s2c_match_started(rules_dict: Dictionary) -> void:
	Game.rules.load_dict(rules_dict)
	if lobby:
		lobby.close_lobby()
	match_started.emit()
	_hide_all_overlays()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

@rpc("authority", "reliable", "call_local")
func s2c_start_draft(eligible_peer_ids: Array) -> void:
	current_state = State.DRAFT
	Game.set_match_state("DRAFT")
	_set_all_tanks_frozen(true)
	if lobby:
		lobby.close_lobby()
	_hide_all_overlays()

	var my_id := _get_unique_id()
	if eligible_peer_ids.has(my_id):
		# Локальный игрок драфтит
		var my_tank := _get_local_tank()
		if card_draft and my_tank:
			card_draft.open_draft(my_tank)
			if not card_draft.card_selected.is_connected(_on_card_draft_selected):
				card_draft.card_selected.connect(_on_card_draft_selected, CONNECT_ONE_SHOT)
	else:
		# Локальный игрок победил и ожидает
		if _pnl_waiting_draft:
			_pnl_waiting_draft.visible = true

@rpc("authority", "reliable", "call_local")
func s2c_close_all_drafts() -> void:
	if card_draft and card_draft.visible:
		card_draft.close_draft()
	if _pnl_waiting_draft:
		_pnl_waiting_draft.visible = false

func _on_card_draft_selected(card_def: CardDefinition) -> void:
	if _is_server():
		_pending_draft_peers.erase(_get_unique_id())
		if _pending_draft_peers.is_empty() and current_state == State.DRAFT:
			s2c_close_all_drafts.rpc()
			_server_start_countdown()
	else:
		c2s_report_draft_chosen.rpc_id(1, card_def.id)

@rpc("authority", "unreliable", "call_local")
func s2c_countdown_tick(value: int) -> void:
	current_state = State.COUNTDOWN
	Game.set_match_state("COUNTDOWN")
	_set_all_tanks_frozen(true)
	if card_draft:
		card_draft.close_draft()
	if _pnl_waiting_draft:
		_pnl_waiting_draft.visible = false
	if _pnl_round_end:
		_pnl_round_end.visible = false

	_stop_spectating()

	if _lbl_countdown:
		_lbl_countdown.visible = true
		if value > 0:
			_lbl_countdown.text = str(value)
			_lbl_countdown.modulate = Color(1.0, 0.9, 0.2)
		else:
			_lbl_countdown.text = "БОЙ!"
			_lbl_countdown.modulate = Color(0.3, 0.95, 0.35)

@rpc("authority", "reliable", "call_local")
func s2c_combat_started(round_num: int) -> void:
	current_state = State.PLAYING
	Game.set_match_state("PLAYING")
	_set_all_tanks_frozen(false)
	current_round = round_num
	round_started.emit(round_num)

	if _lbl_countdown:
		var tw := create_tween()
		tw.tween_property(_lbl_countdown, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func(): _lbl_countdown.visible = false)

	_stop_spectating()

@rpc("authority", "reliable", "call_local")
func s2c_round_ended(winner_id: int, is_team: bool, round_num: int) -> void:
	current_state = State.ROUND_END
	Game.set_match_state("ROUND_END")
	_set_all_tanks_frozen(true)
	round_ended.emit(winner_id, is_team)

	_stop_spectating()

	if _pnl_round_end and _lbl_round_end_title and _lbl_round_end_sub:
		_pnl_round_end.visible = true
		if winner_id == -1:
			_lbl_round_end_title.text = "РАУНД %d: НИЧЬЯ!" % round_num
			_lbl_round_end_title.modulate = Color(0.8, 0.8, 0.8)
			_lbl_round_end_sub.text = "Все танки были уничтожены"
		else:
			if is_team:
				_lbl_round_end_title.text = "ПОБЕДА КОМАНДЫ %d!" % winner_id
				_lbl_round_end_title.modulate = Color(0.3, 0.8, 1.0)
			else:
				var winner_name := "Player %d" % winner_id
				var info := Network.get_player_info(winner_id)
				if info:
					winner_name = info.player_name
				_lbl_round_end_title.text = "РАУНД %d ВЗЯЛ: %s" % [round_num, winner_name]
				_lbl_round_end_title.modulate = Color(1.0, 0.85, 0.2)

			_lbl_round_end_sub.text = "Проигравшие готовятся к драфту карт..."

@rpc("authority", "reliable", "call_local")
func s2c_match_ended(winner_id: int, is_team: bool) -> void:
	current_state = State.MATCH_END
	Game.set_match_state("MATCH_END")
	_set_all_tanks_frozen(true)
	match_ended.emit(winner_id, is_team)

	_stop_spectating()
	if _pnl_round_end:
		_pnl_round_end.visible = false
	if _pnl_waiting_draft:
		_pnl_waiting_draft.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _pnl_match_end and _lbl_match_end_winner and _lbl_match_end_scores:
		_pnl_match_end.visible = true

		if is_team:
			_lbl_match_end_winner.text = "ПОБЕДИТЕЛЬ МАТЧА: КОМАНДА %d!" % winner_id
			_lbl_match_end_winner.modulate = Color(0.3, 0.8, 1.0)
		else:
			var w_name := "Player %d" % winner_id
			var info := Network.get_player_info(winner_id)
			if info:
				w_name = info.player_name
			_lbl_match_end_winner.text = "ЧЕМПИОН АРЕНЫ: %s!" % w_name
			_lbl_match_end_winner.modulate = Color(1.0, 0.85, 0.2)

		# Список очков всех участников
		var score_text := "ИТОГОВЫЙ СЧЁТ ПОБЕД:\n"
		for p in Network.get_all_players():
			if p is PlayerInfo:
				score_text += "• %s: %d побед\n" % [p.player_name, p.round_wins]
		_lbl_match_end_scores.text = score_text

		if _btn_rematch:
			_btn_rematch.visible = Network.is_host or not Network.is_multiplayer_active()

# --- Режим наблюдателя (Spectator) ---

func on_local_tank_died() -> void:
	if current_state != State.PLAYING:
		return

	var alive := _get_alive_tanks()
	var my_tank := _get_local_tank()
	alive.erase(my_tank)

	if alive.is_empty():
		return

	if camera:
		var targets: Array[Node3D] = []
		for t in alive:
			targets.append(t)
		camera.start_spectating(targets)
		if not camera.spectate_target_changed.is_connected(_on_spectate_target_changed):
			camera.spectate_target_changed.connect(_on_spectate_target_changed)
		_on_spectate_target_changed(camera.target_node)


	if _pnl_spectator:
		_pnl_spectator.visible = true

func _on_spectate_target_changed(target: Node3D) -> void:
	if not _lbl_spectator_name or not target:
		return
	var t_name := target.name
	if target is Tank:
		var p_info := Network.get_player_info(target.peer_id)
		if p_info:
			t_name = p_info.player_name
	_lbl_spectator_name.text = "ВЫ ПОГИБЛИ. НАБЛЮДЕНИЕ ЗА: %s" % t_name

func _stop_spectating() -> void:
	if camera and camera.is_spectating:
		var my_tank := _get_local_tank()
		camera.stop_spectating(my_tank)
	if _pnl_spectator:
		_pnl_spectator.visible = false

func _get_local_tank() -> Tank:
	var my_id := _get_unique_id()
	if spawned_tanks_container:
		var t_name := "Tank_%d" % my_id
		var t := spawned_tanks_container.get_node_or_null(t_name) as Tank
		if t:
			return t
	return null

func _hide_all_overlays() -> void:
	if _lbl_countdown:
		_lbl_countdown.visible = false
	if _pnl_round_end:
		_pnl_round_end.visible = false
	if _pnl_waiting_draft:
		_pnl_waiting_draft.visible = false
	if _pnl_spectator:
		_pnl_spectator.visible = false
	if _pnl_match_end:
		_pnl_match_end.visible = false

func _on_game_state_changed(new_state: String) -> void:
	pass

# --- Обработчики кнопок реванша и лобби ---

func _on_btn_rematch_pressed() -> void:
	if _is_server():
		_pnl_match_end.visible = false
		start_new_match()
		rematch_started.emit()

func _on_btn_lobby_pressed() -> void:
	_pnl_match_end.visible = false
	current_state = State.IDLE
	Game.reset_match()
	returned_to_lobby.emit()
