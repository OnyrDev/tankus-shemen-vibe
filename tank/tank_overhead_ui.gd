class_name TankOverheadUI
extends Control

## World-Space оверхед-индикатор над танком.
## Проецирует информацию о здоровье, боезапасе и готовности щита в 2D пространство экрана.
## Оснащен физической Raycast-проверкой прямой видимости:
## плашка скрывается, если танк заслонен стеной или находится позади камеры.

@onready var container: VBoxContainer = $VBox
@onready var lbl_player_name: Label = $VBox/LblName
@onready var health_bar: ProgressBar = $VBox/HealthBar
@onready var ammo_hbox: HBoxContainer = $VBox/HBoxStatus/AmmoPills
@onready var lbl_reload: Label = $VBox/HBoxStatus/LblReload
@onready var shield_indicator: Panel = $VBox/HBoxStatus/ShieldIndicator

var target_tank: Tank = null
var overhead_mount: Marker3D = null

const COLOR_AMMO_FULL := Color(1.0, 0.85, 0.2)
const COLOR_AMMO_EMPTY := Color(0.25, 0.25, 0.28, 0.6)

var _ammo_pills: Array[ColorRect] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_setup_ammo_pills(4)
	if shield_indicator:
		shield_indicator.visible = false

func bind_tank(tank: Tank) -> void:
	target_tank = tank
	if not target_tank:
		return

	overhead_mount = target_tank.get_node_or_null("OverheadMount") as Marker3D

	# Подключаем сигналы танка
	if target_tank.health:
		target_tank.health.health_changed.connect(_on_health_changed)
		_on_health_changed(target_tank.health.current_health, target_tank.health.max_health)

	if target_tank.weapon:
		target_tank.weapon.ammo_changed.connect(_on_ammo_changed)
		target_tank.weapon.reload_started.connect(func(_d): _on_reload_state(true))
		target_tank.weapon.reload_completed.connect(func(): _on_reload_state(false))
		_setup_ammo_pills(target_tank.weapon.magazine_size)
		_on_ammo_changed(target_tank.weapon.current_ammo, target_tank.weapon.magazine_size)

	if target_tank.block:
		target_tank.block.block_started.connect(func(_d): _update_shield_state())
		target_tank.block.block_ended.connect(_update_shield_state)
		target_tank.block.cooldown_finished.connect(_update_shield_state)
		_update_shield_state()

	_update_player_info()

func _setup_ammo_pills(count: int) -> void:
	if not ammo_hbox:
		return

	for child in ammo_hbox.get_children():
		ammo_hbox.remove_child(child)
		child.queue_free()
	_ammo_pills.clear()

	for i in range(count):
		var pill := ColorRect.new()
		pill.custom_minimum_size = Vector2(8, 12)
		pill.color = COLOR_AMMO_FULL
		ammo_hbox.add_child(pill)
		_ammo_pills.append(pill)

func _process(_delta: float) -> void:
	if not is_instance_valid(target_tank) or not target_tank.is_inside_tree():
		queue_free()
		return

	# Локальный танк скрываем — у него есть полный экранный HUD
	var my_id := Network.get_unique_id()
	if target_tank.peer_id == my_id:
		visible = false
		return

	# Если танк погиб или отключен
	if not target_tank.is_active or (target_tank.health and target_tank.health.current_health <= 0.0):
		visible = false
		return

	var cam := get_viewport().get_camera_3d()
	if not cam:
		visible = false
		return

	var world_pos := target_tank.global_position + Vector3(0, 1.4, 0)
	if overhead_mount:
		world_pos = overhead_mount.global_position

	# Проверка: находится ли точка позади камеры
	if cam.is_position_behind(world_pos):
		visible = false
		return

	var cam_dist := cam.global_position.distance_to(world_pos)
	if cam_dist > 55.0: # Предел видимости оверхеда
		visible = false
		return

	# Raycast-проверка прямой видимости через стены
	var space := target_tank.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, world_pos)
	query.collision_mask = 1 # Стены и геометрия уровня (слой 1)
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		# Между камерой и танком стена
		visible = false
		return

	# Танк виден — проецируем на экран
	visible = true
	var screen_pos := cam.unproject_position(world_pos)
	position = screen_pos - size * 0.5

	# Мягкое масштабирование от дистанции
	var scale_factor := clampf(1.0 - (cam_dist - 8.0) / 60.0, 0.7, 1.0)
	scale = Vector2(scale_factor, scale_factor)

	_update_player_info()
	_update_shield_state()


func _update_player_info() -> void:
	if not target_tank:
		return

	var p_info := Network.get_player_info(target_tank.peer_id)
	if lbl_player_name:
		if p_info:
			lbl_player_name.text = p_info.player_name
		else:
			lbl_player_name.text = "Tank %d" % target_tank.peer_id
		lbl_player_name.modulate = target_tank.team_color

func _on_health_changed(curr: float, max_h: float) -> void:
	if health_bar:
		health_bar.max_value = max_h
		health_bar.value = curr
		var ratio := curr / max_h if max_h > 0 else 0.0
		var style := health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if style:
			style.bg_color = Color(0.95, 0.25, 0.2).lerp(Color(0.2, 0.85, 0.35), ratio)

func _on_ammo_changed(curr: int, _max_a: int) -> void:
	for i in range(_ammo_pills.size()):
		if i < curr:
			_ammo_pills[i].color = COLOR_AMMO_FULL
		else:
			_ammo_pills[i].color = COLOR_AMMO_EMPTY

func _on_reload_state(reloading: bool) -> void:
	if lbl_reload:
		lbl_reload.visible = reloading
	if ammo_hbox:
		ammo_hbox.visible = not reloading

func _update_shield_state() -> void:
	if not shield_indicator:
		return
	var has_block: bool = false
	if target_tank and is_instance_valid(target_tank) and target_tank.block:
		has_block = target_tank.block.can_block()
	shield_indicator.visible = has_block
