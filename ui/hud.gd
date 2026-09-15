class_name HUD
extends CanvasLayer

## Боевой интерфейс игрока TANKUS.
## Отображает очки прочности, обойму, перезарядку, статус щита, прицел и полученные карты билда.

@onready var crosshair: Control = get_node_or_null("Crosshair")
@onready var health_bar: ProgressBar = get_node_or_null("BottomLeft/HealthPanel/HealthContainer/HealthBar")
@onready var health_label: Label = get_node_or_null("BottomLeft/HealthPanel/HealthContainer/HealthLabel")

@onready var ammo_container: HBoxContainer = get_node_or_null("BottomRight/CombatContainer/AmmoBox/VBox/AmmoPills")
@onready var ammo_label: Label = get_node_or_null("BottomRight/CombatContainer/AmmoBox/VBox/AmmoHeader/AmmoLabel")
@onready var reload_bar: ProgressBar = get_node_or_null("BottomRight/CombatContainer/AmmoBox/VBox/ReloadBar")

@onready var shield_status_label: Label = get_node_or_null("BottomRight/CombatContainer/ShieldBox/VBox/ShieldStatusLabel")
@onready var shield_cooldown_bar: ProgressBar = get_node_or_null("BottomRight/CombatContainer/ShieldBox/VBox/ShieldCooldownBar")
@onready var shield_panel: PanelContainer = get_node_or_null("BottomRight/CombatContainer/ShieldBox")

@onready var build_chips_container: HFlowContainer = get_node_or_null("TopLeft/BuildChipsContainer")

var _bound_tank: Tank = null
var _ammo_pills: Array[ColorRect] = []

const COLOR_HEALTH_NORMAL := Color(0.2, 0.85, 0.35)
const COLOR_HEALTH_LOW := Color(0.95, 0.25, 0.2)
const COLOR_AMMO_FULL := Color(1.0, 0.85, 0.2)
const COLOR_AMMO_EMPTY := Color(0.25, 0.25, 0.28, 0.6)
const COLOR_SHIELD_READY := Color(0.2, 0.8, 1.0)
const COLOR_SHIELD_ACTIVE := Color(0.9, 0.95, 1.0)
const COLOR_SHIELD_COOLDOWN := Color(0.4, 0.45, 0.5)

func _ready() -> void:
	_setup_ammo_pills(4)
	if reload_bar:
		reload_bar.visible = false

func bind_to_tank(tank: Tank) -> void:
	if _bound_tank and is_instance_valid(_bound_tank):
		_unbind_tank()

	_bound_tank = tank
	if not _bound_tank:
		return

	if _bound_tank.health:
		_bound_tank.health.health_changed.connect(_on_health_changed)
		_bound_tank.health.died.connect(_on_tank_died)
		_on_health_changed(_bound_tank.health.current_health, _bound_tank.health.max_health)

	if _bound_tank.weapon:
		_bound_tank.weapon.ammo_changed.connect(_on_ammo_changed)
		_bound_tank.weapon.reload_started.connect(_on_reload_started)
		_bound_tank.weapon.reload_progress.connect(_on_reload_progress)
		_bound_tank.weapon.reload_completed.connect(_on_reload_completed)
		_setup_ammo_pills(_bound_tank.weapon.magazine_size)
		_on_ammo_changed(_bound_tank.weapon.current_ammo, _bound_tank.weapon.magazine_size)

	if _bound_tank.block:
		_bound_tank.block.block_started.connect(_on_block_started)
		_bound_tank.block.block_ended.connect(_on_block_ended)
		_bound_tank.block.cooldown_progress.connect(_on_block_cooldown_progress)
		_bound_tank.block.cooldown_finished.connect(_on_block_cooldown_finished)
		_on_block_cooldown_finished()

	if _bound_tank.build:
		_bound_tank.build.build_changed.connect(_update_build_chips)
		_bound_tank.build.card_added.connect(func(_c, _s): _update_build_chips())
		_update_build_chips()

func _unbind_tank() -> void:
	if not _bound_tank or not is_instance_valid(_bound_tank):
		return

	if _bound_tank.health:
		if _bound_tank.health.health_changed.is_connected(_on_health_changed):
			_bound_tank.health.health_changed.disconnect(_on_health_changed)
		if _bound_tank.health.died.is_connected(_on_tank_died):
			_bound_tank.health.died.disconnect(_on_tank_died)

	if _bound_tank.weapon:
		if _bound_tank.weapon.ammo_changed.is_connected(_on_ammo_changed):
			_bound_tank.weapon.ammo_changed.disconnect(_on_ammo_changed)
		if _bound_tank.weapon.reload_started.is_connected(_on_reload_started):
			_bound_tank.weapon.reload_started.disconnect(_on_reload_started)
		if _bound_tank.weapon.reload_progress.is_connected(_on_reload_progress):
			_bound_tank.weapon.reload_progress.disconnect(_on_reload_progress)
		if _bound_tank.weapon.reload_completed.is_connected(_on_reload_completed):
			_bound_tank.weapon.reload_completed.disconnect(_on_reload_completed)

	if _bound_tank.block:
		if _bound_tank.block.block_started.is_connected(_on_block_started):
			_bound_tank.block.block_started.disconnect(_on_block_started)
		if _bound_tank.block.block_ended.is_connected(_on_block_ended):
			_bound_tank.block.block_ended.disconnect(_on_block_ended)
		if _bound_tank.block.cooldown_progress.is_connected(_on_block_cooldown_progress):
			_bound_tank.block.cooldown_progress.disconnect(_on_block_cooldown_progress)
		if _bound_tank.block.cooldown_finished.is_connected(_on_block_cooldown_finished):
			_bound_tank.block.cooldown_finished.disconnect(_on_block_cooldown_finished)

	_bound_tank = null

func _update_build_chips() -> void:
	if not build_chips_container or not _bound_tank or not _bound_tank.build:
		return

	for child in build_chips_container.get_children():
		build_chips_container.remove_child(child)
		child.queue_free()

	for card_id in _bound_tank.build.ordered_cards:
		var stacks: int = _bound_tank.build.get_stacks(card_id)
		var card_def := CardDatabase.get_card(card_id)
		if not card_def:
			continue

		var chip := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = card_def.get_category_color()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		chip.add_theme_stylebox_override("panel", style)

		var lbl := Label.new()
		if stacks > 1:
			lbl.text = "%s ×%d" % [card_def.display_name, stacks]
		else:
			lbl.text = card_def.display_name
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.modulate = card_def.get_category_color()
		chip.add_child(lbl)

		build_chips_container.add_child(chip)

func _setup_ammo_pills(count: int) -> void:
	if not ammo_container:
		return

	for child in ammo_container.get_children():
		ammo_container.remove_child(child)
		child.queue_free()
	_ammo_pills.clear()

	for i in range(count):
		var pill := ColorRect.new()
		pill.custom_minimum_size = Vector2(16, 26)
		pill.color = COLOR_AMMO_FULL
		ammo_container.add_child(pill)
		_ammo_pills.append(pill)

func _on_health_changed(current: float, max_h: float) -> void:
	if health_bar:
		health_bar.max_value = max_h
		health_bar.value = current
		var ratio := current / max_h if max_h > 0 else 0.0
		var health_fill := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if health_fill:
			health_fill.bg_color = COLOR_HEALTH_LOW.lerp(COLOR_HEALTH_NORMAL, ratio)

	if health_label:
		health_label.text = "%d / %d HP" % [int(ceil(current)), int(max_h)]

func _on_tank_died(_killer: Node) -> void:
	if health_label:
		health_label.text = "DESTROYED"

func _on_ammo_changed(current: int, max_a: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [current, max_a]
	for i in range(_ammo_pills.size()):
		if i < current:
			_ammo_pills[i].color = COLOR_AMMO_FULL
		else:
			_ammo_pills[i].color = COLOR_AMMO_EMPTY

func _on_reload_started(duration: float) -> void:
	if reload_bar:
		reload_bar.max_value = duration
		reload_bar.value = 0.0
		reload_bar.visible = true
	if ammo_label:
		ammo_label.text = "RELOAD..."

func _on_reload_progress(curr: float, _total: float) -> void:
	if reload_bar:
		reload_bar.value = curr

func _on_reload_completed() -> void:
	if reload_bar:
		reload_bar.visible = false

func _on_block_started(_duration: float) -> void:
	if shield_status_label:
		shield_status_label.text = "[E] ACTIVE"
		shield_status_label.modulate = COLOR_SHIELD_ACTIVE
	if shield_cooldown_bar:
		shield_cooldown_bar.value = 0.0

func _on_block_ended() -> void:
	if shield_status_label:
		shield_status_label.text = "[E] COOLING"
		shield_status_label.modulate = COLOR_SHIELD_COOLDOWN

func _on_block_cooldown_progress(curr: float, total: float) -> void:
	if shield_cooldown_bar:
		shield_cooldown_bar.max_value = total
		shield_cooldown_bar.value = curr
	if shield_status_label:
		var remaining := maxf(0.0, total - curr)
		shield_status_label.text = "[E] %.1fs" % remaining

func _on_block_cooldown_finished() -> void:
	if shield_status_label:
		shield_status_label.text = "[E] READY"
		shield_status_label.modulate = COLOR_SHIELD_READY
	if shield_cooldown_bar:
		shield_cooldown_bar.max_value = 1.0
		shield_cooldown_bar.value = 1.0
