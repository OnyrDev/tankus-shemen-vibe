class_name TankController
extends Node

## Контроллер физического перемещения танка.
## Реализует аркадное движение, заезд на рампы, прыжки, ограниченный air-control
## и стабильный разворот корпуса за вектором движения без вибрации.

@export var move_speed: float = 8.0
@export var acceleration: float = 22.0
@export var braking: float = 26.0
@export var air_control_factor: float = 0.45
@export var jump_velocity: float = 8.5
@export var gravity: float = 18.0
@export var body_turn_speed: float = 12.0

var _tank_body: CharacterBody3D = null
var _is_jumping: bool = false
var _coyote_timer: float = 0.0
const COYOTE_TIME: float = 0.12

func _ready() -> void:
	_tank_body = get_parent() as CharacterBody3D
	if _tank_body:
		_tank_body.floor_max_angle = deg_to_rad(48.0)
		_tank_body.floor_snap_length = 0.35
		_tank_body.floor_constant_speed = true
		_tank_body.floor_stop_on_slope = true
		_tank_body.floor_block_on_wall = true

func process_physics(input: TankInput, delta: float) -> void:
	if not _tank_body:
		return

	var on_floor := _tank_body.is_on_floor()
	if on_floor:
		_coyote_timer = COYOTE_TIME
		_is_jumping = false
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	var can_jump := (on_floor or _coyote_timer > 0.0) and not _is_jumping
	if can_jump and input and input.consume_jump():
		_tank_body.velocity.y = jump_velocity
		_is_jumping = true
		_coyote_timer = 0.0
	elif not on_floor:
		_tank_body.velocity.y -= gravity * delta
	else:
		# Находясь на полу, сбрасываем остаточную вертикальную скорость во избежание микро-колебаний
		_tank_body.velocity.y = 0.0

	# Горизонтальное движение
	var move_dir: Vector3 = input.move_direction_world if input else Vector3.ZERO
	var current_accel: float = acceleration if on_floor else (acceleration * air_control_factor)
	var current_brake: float = braking if on_floor else (braking * air_control_factor)

	if move_dir.length_squared() > 0.01:
		var target_vel: Vector3 = move_dir * move_speed
		_tank_body.velocity.x = move_toward(_tank_body.velocity.x, target_vel.x, current_accel * delta)
		_tank_body.velocity.z = move_toward(_tank_body.velocity.z, target_vel.z, current_accel * delta)
	else:
		_tank_body.velocity.x = move_toward(_tank_body.velocity.x, 0.0, current_brake * delta)
		_tank_body.velocity.z = move_toward(_tank_body.velocity.z, 0.0, current_brake * delta)

	# Плавная ориентация корпуса по фактическому направлению движения
	var flat_vel := Vector3(_tank_body.velocity.x, 0.0, _tank_body.velocity.z)
	if flat_vel.length_squared() > 0.35:
		var vel_dir := flat_vel.normalized()
		var target_yaw := atan2(-vel_dir.x, -vel_dir.z)
		var current_yaw := _tank_body.rotation.y
		var diff := wrapf(target_yaw - current_yaw, -PI, PI)
		if absf(diff) > 0.005:
			var step := signf(diff) * minf(absf(diff), body_turn_speed * delta)
			_tank_body.rotation.y += step

	if _is_jumping:
		_tank_body.floor_snap_length = 0.0
	else:
		_tank_body.floor_snap_length = 0.35

	_tank_body.move_and_slide()
