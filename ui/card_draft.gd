class_name CardDraft
extends CanvasLayer

## Экран выбора способностей (Card Draft) в стиле ROUNDS.
## Показывает 5 карт, поддерживает клик и клавиши 1-5, таймер 20 секунд с автовыбором.

signal card_selected(card_def: CardDefinition)

@onready var background: ColorRect = $Background
@onready var title_label: Label = $VBox/Header/Title
@onready var timer_label: Label = $VBox/Header/TimerLabel
@onready var cards_container: HBoxContainer = $VBox/CardsContainer

var _current_offer: Array[CardDefinition] = []
var _target_tank: Tank = null
var _time_left: float = 20.0
var _is_draft_active: bool = false
var _card_panels: Array[Control] = []

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if not _is_draft_active:
		return

	_time_left = maxf(0.0, _time_left - delta)
	if timer_label:
		timer_label.text = "TIME: %ds" % int(ceil(_time_left))

	if _time_left <= 0.0:
		_auto_select_card()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_draft_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_by_index(0)
			KEY_2:
				_select_by_index(1)
			KEY_3:
				_select_by_index(2)
			KEY_4:
				_select_by_index(3)
			KEY_5:
				_select_by_index(4)

func open_draft(tank: Tank, custom_offer: Array[CardDefinition] = []) -> void:
	_target_tank = tank
	_time_left = 20.0
	_is_draft_active = true
	visible = true

	if custom_offer.is_empty():
		var build: TankBuild = tank.build if tank else null
		_current_offer = CardDatabase.generate_draft_offer(build, 5)
	else:
		_current_offer = custom_offer

	_render_cards()

	# Освобождаем мышь для клика
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_draft() -> void:
	_is_draft_active = false
	visible = false
	_current_offer.clear()
	# Возвращаем захват мыши для TPS управления
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _render_cards() -> void:
	for child in cards_container.get_children():
		cards_container.remove_child(child)
		child.queue_free()
	_card_panels.clear()

	for i in range(_current_offer.size()):
		var card_def := _current_offer[i]
		var card_panel := _create_card_widget(card_def, i)
		cards_container.add_child(card_panel)
		_card_panels.append(card_panel)

func _create_card_widget(card: CardDefinition, index: int) -> Control:
	var root_btn := Button.new()
	root_btn.custom_minimum_size = Vector2(200, 310)
	root_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = card.get_category_color()
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 12
	style.content_margin_top = 14
	style.content_margin_right = 12
	style.content_margin_bottom = 14
	root_btn.add_theme_stylebox_override("normal", style)
	root_btn.add_theme_stylebox_override("hover", style)
	root_btn.add_theme_stylebox_override("pressed", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	root_btn.add_child(vbox)

	# Заголовок с номером
	var header := HBoxContainer.new()
	var num_label := Label.new()
	num_label.text = "[%d]" % (index + 1)
	num_label.modulate = Color(0.7, 0.75, 0.8)
	header.add_child(num_label)

	var badge := Label.new()
	badge.text = " %s " % card.get_category_name()
	badge.modulate = card.get_category_color()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(badge)
	vbox.add_child(header)

	# Название
	var name_label := Label.new()
	name_label.text = card.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Разделитель
	var sep := HSeparator.new()
	sep.modulate = card.get_category_color() * 0.7
	vbox.add_child(sep)

	# Описание
	var desc_label := Label.new()
	desc_label.text = card.description
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_label)

	# Текущие стаки (если уже есть)
	if _target_tank and _target_tank.build and _target_tank.build.has_card(card.id):
		var stacks_label := Label.new()
		stacks_label.text = "In build: x%d" % _target_tank.build.get_stacks(card.id)
		stacks_label.modulate = Color(0.3, 0.9, 0.5)
		stacks_label.add_theme_font_size_override("font_size", 12)
		stacks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stacks_label)

	# Клик по кнопке
	root_btn.pressed.connect(func():
		_select_by_index(index)
	)

	return root_btn

func _select_by_index(idx: int) -> void:
	if not _is_draft_active or idx < 0 or idx >= _current_offer.size():
		return

	var chosen_card := _current_offer[idx]

	if _target_tank and _target_tank.build:
		_target_tank.build.add_card(chosen_card)

		# Синхронизация билда карт при игре по сети
		if multiplayer.has_multiplayer_peer() and _target_tank.net_sync:
			if not multiplayer.is_server():
				_target_tank.net_sync.c2s_choose_card.rpc_id(1, chosen_card.id)
			else:
				if _target_tank.stats:
					_target_tank.net_sync.synced_tank_scale = _target_tank.stats.tank_scale
				_target_tank.net_sync.s2c_card_added.rpc(chosen_card.id)


	card_selected.emit(chosen_card)
	close_draft()

func _auto_select_card() -> void:
	if not _current_offer.is_empty():
		_select_by_index(0)
	else:
		close_draft()
