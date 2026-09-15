class_name TPSCamera
extends Node3D

## Орбитальная камера от третьего лица (TPS) с пружинным подвесом SpringArm3D.
## Синхронизирована с физическим циклом во избежание джиттера.

@export var target_node: Node3D = null
@export var mouse_sensitivity: float = 0.003
@export var min_pitch_deg: float = -30.0 # наклон вверх (взгляд вниз)
@export var max_pitch_deg: float = 50.0  # наклон вниз (взгляд вверх)
@export var target_offset: Vector3 = Vector3(0.0, 1.8, 0.0)
@export var smooth_speed: float = 22.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0
var pitch: float = 0.0

func _ready() -> void:
	top_level = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if target_node:
		global_position = target_node.global_position + target_offset
		yaw = target_node.global_rotation.y
		rotation.y = yaw

	pitch = deg_to_rad(12.0)
	if spring_arm:
		spring_arm.rotation.x = -pitch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(
			pitch + event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
		rotation.y = yaw
		if spring_arm:
			spring_arm.rotation.x = -pitch

	# Переключение курсора по Esc / ui_cancel
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Захват курсора обратно при клике по окну
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_node):
		return

	var desired_pos := target_node.global_position + target_offset
	var weight := 1.0 - exp(-smooth_speed * delta)
	global_position = global_position.lerp(desired_pos, weight)

func get_camera() -> Camera3D:
	return camera
