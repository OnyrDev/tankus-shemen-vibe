class_name TankInput
extends Node

## Компонент сбора ввода для управления танком от 3-го лица (TPS).
## Считывает WASD относительно взгляда камеры, прыжок и пускает луч прицела из центра экрана.

@export var enabled: bool = true
@export_flags_3d_physics var raycast_collision_mask: int = 11 # Слой 1 (мир) + Слой 2 (танки) + Слой 4 (пропсы/ящики)

var move_input: Vector2 = Vector2.ZERO
var move_direction_world: Vector3 = Vector3.ZERO
var jump_requested: bool = false
var fire_requested: bool = false
var reload_requested: bool = false
var block_requested: bool = false

var aim_point: Vector3 = Vector3.ZERO
var aim_normal: Vector3 = Vector3.UP
var is_aim_valid: bool = false

var _crosshair: Node3D = null
var _tank_body: CharacterBody3D = null

func _ready() -> void:
	_tank_body = get_parent() as CharacterBody3D
	_setup_laser_point()

func _setup_laser_point() -> void:
	# Маленькая лазерная точка сведения на поверхностях препятствий
	_crosshair = Node3D.new()
	_crosshair.name = "LaserAimPoint"
	_crosshair.top_level = true

	var dot_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.2, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	dot_inst.mesh = sphere
	dot_inst.material_override = mat

	_crosshair.add_child(dot_inst)
	add_child(_crosshair)

func _exit_tree() -> void:
	if is_instance_valid(_crosshair):
		_crosshair.queue_free()

func _is_aim_input_active() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if not enabled or not _is_aim_input_active():
		if is_instance_valid(_crosshair):
			_crosshair.visible = false
		return

	_update_aim_raycast()

func _physics_process(_delta: float) -> void:
	if not enabled or (_tank_body and _tank_body.is_frozen):
		move_input = Vector2.ZERO
		move_direction_world = Vector3.ZERO
		jump_requested = false
		fire_requested = false
		reload_requested = false
		block_requested = false
		return

	_update_movement_input()
	_update_aim_raycast()

	if Input.is_action_just_pressed("jump"):
		jump_requested = true
	# Стрельба возможна ТОЛЬКО в режиме захваченного прицела (исключает стрельбу при кликах в UI/меню/лобби)
	if _is_aim_input_active() and Input.is_action_pressed("fire"):
		fire_requested = true
	if Input.is_action_just_pressed("reload"):
		reload_requested = true
	if Input.is_action_just_pressed("block"):
		block_requested = true

func consume_jump() -> bool:
	var requested := jump_requested
	jump_requested = false
	return requested

func is_fire_held() -> bool:
	return enabled and (_tank_body == null or not _tank_body.is_frozen) and _is_aim_input_active() and Input.is_action_pressed("fire")

func consume_fire() -> bool:
	if not _is_aim_input_active():
		fire_requested = false
		return false
	var requested := fire_requested
	fire_requested = false
	return requested

func consume_reload() -> bool:
	var requested := reload_requested
	reload_requested = false
	return requested

func consume_block() -> bool:
	var requested := block_requested
	block_requested = false
	return requested

func _update_movement_input() -> void:
	var raw_x := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var raw_y := Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	move_input = Vector2(raw_x, raw_y).limit_length(1.0)

	var camera := get_viewport().get_camera_3d()
	if camera:
		var cam_basis := camera.global_basis
		var cam_right := Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
		var cam_forward := Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
		move_direction_world = (cam_right * move_input.x + cam_forward * move_input.y).limit_length(1.0)
	else:
		move_direction_world = Vector3(move_input.x, 0.0, -move_input.y).limit_length(1.0)

func _update_aim_raycast() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	# В TPS прицеливание идет строго из центра экрана
	var screen_center := get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(screen_center)
	var ray_dir := camera.project_ray_normal(screen_center)

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 300.0, raycast_collision_mask)

	if _tank_body:
		query.exclude = [_tank_body.get_rid()]

	var result := space_state.intersect_ray(query)
	var cam_forward := -camera.global_basis.z.normalized()
	if not result.is_empty():
		var hit_pos: Vector3 = result.position
		var hit_behind_tank := false
		if _tank_body:
			var to_hit: Vector3 = hit_pos - _tank_body.global_position
			if to_hit.dot(cam_forward) < -0.2:
				hit_behind_tank = true

		if not hit_behind_tank:
			var hit_normal: Vector3 = result.normal as Vector3
			var collider: Object = result.get("collider", null)

			# Опция 1: Компенсация параллакса TPS-камеры над полом (Floor-Clearing Horizon Compensation).
			# Камера находится на высоте 2.5-3м и смотрит под наклоном вниз, поэтому при взгляде вдаль
			# луч камеры пересекает плоский пол арены на 15-25 метрах. Если брать чистую точку пола,
			# дуло танка наклоняется вниз и пули бьются о землю задолго до цели.
			# Если луч задел горизонтальный пол (normal.y > 0.7), поднимаем точку цели на уровень танка (~0.7м),
			# чтобы снаряды летели горизонтально сквозь арену на высоте корпусов танков.
			var is_floor: bool = hit_normal.y > 0.7 and not (collider is CharacterBody3D)
			if is_floor:
				# При взгляде в горизонт или вдаль (ray_dir.y >= 0) компенсация максимальна (1.0).
				# При намеренном крутом взгляде прямо под ноги (ray_dir.y <= -0.45) компенсация сходит на нет (0.0).
				var floor_comp := clampf(1.0 - (-minf(0.0, ray_dir.y) / 0.45), 0.0, 1.0)
				hit_pos.y += 0.7 * floor_comp

			aim_point = hit_pos
			aim_normal = hit_normal
			is_aim_valid = true
			if is_instance_valid(_crosshair):
				_crosshair.visible = true
				_crosshair.global_position = aim_point + aim_normal * 0.03
			return

	# Если препятствий нет или они позади танка, целимся вдаль по линии горизонта на рабочей высоте
	var base_y := _tank_body.global_position.y + 0.7 if _tank_body else ray_origin.y
	var horizon_dir := ray_dir
	if horizon_dir.y < 0.0:
		horizon_dir.y = 0.0
		horizon_dir = horizon_dir.normalized()
	aim_point = Vector3(
		(_tank_body.global_position.x if _tank_body else ray_origin.x) + horizon_dir.x * 100.0,
		base_y + maxf(0.0, ray_dir.y) * 100.0,
		(_tank_body.global_position.z if _tank_body else ray_origin.z) + horizon_dir.z * 100.0
	)
	aim_normal = -horizon_dir
	is_aim_valid = true
	if is_instance_valid(_crosshair):
		_crosshair.visible = false
