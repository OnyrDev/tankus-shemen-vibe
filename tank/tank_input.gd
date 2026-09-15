class_name TankInput
extends Node

## Компонент сбора ввода для управления танком от 3-го лица (TPS).
## Считывает WASD относительно взгляда камеры, прыжок и пускает луч прицела из центра экрана.

@export var enabled: bool = true
@export_flags_3d_physics var raycast_collision_mask: int = 1

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

func _process(_delta: float) -> void:
	if not enabled:
		if is_instance_valid(_crosshair):
			_crosshair.visible = false
		return

	_update_aim_raycast()

func _physics_process(_delta: float) -> void:
	if not enabled:
		move_input = Vector2.ZERO
		move_direction_world = Vector3.ZERO
		return

	_update_movement_input()

	if Input.is_action_just_pressed("jump"):
		jump_requested = true
	if Input.is_action_pressed("fire"):
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
	return enabled and Input.is_action_pressed("fire")

func consume_fire() -> bool:
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
	if result:
		aim_point = result.position
		aim_normal = result.normal
		is_aim_valid = true
		if is_instance_valid(_crosshair):
			_crosshair.visible = true
			_crosshair.global_position = aim_point + aim_normal * 0.03
	else:
		# Если препятствий нет, целимся вдаль по линии взгляда
		aim_point = ray_origin + ray_dir * 100.0
		aim_normal = -ray_dir
		is_aim_valid = true
		if is_instance_valid(_crosshair):
			_crosshair.visible = false
