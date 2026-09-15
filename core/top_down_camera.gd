class_name TopDownCamera
extends Camera3D

## Высокая Top-Down камера с мягким следованием за танком и look-ahead в сторону прицела.
## Не вращается вместе с корпусом танка.

@export var target_node: Node3D = null
@export var height: float = 16.0
@export var distance_back: float = 9.5
@export var pitch_angle_deg: float = -60.0
@export var smooth_speed: float = 8.5
@export var max_lookahead: float = 3.5
@export var lookahead_weight: float = 0.35

func _ready() -> void:
	top_level = true
	fov = 55.0
	rotation_degrees = Vector3(pitch_angle_deg, 0.0, 0.0)

	if target_node:
		var start_pos := target_node.global_position + Vector3(0.0, height, distance_back)
		global_position = start_pos

func _process(delta: float) -> void:
	if not is_instance_valid(target_node):
		return

	var target_base_pos := target_node.global_position

	# Look-ahead в сторону точки прицеливания (если у цели есть компонент input)
	var lookahead_offset := Vector3.ZERO
	if "input" in target_node and target_node.input and target_node.input.is_aim_valid:
		var to_aim: Vector3 = target_node.input.aim_point - target_base_pos
		to_aim.y = 0.0
		lookahead_offset = to_aim.limit_length(max_lookahead) * lookahead_weight

	var desired_position := target_base_pos + lookahead_offset + Vector3(0.0, height, distance_back)

	# Плавное экспоненциальное сглаживание следования без рывков
	var weight := 1.0 - exp(-smooth_speed * delta)
	global_position = global_position.lerp(desired_position, weight)
