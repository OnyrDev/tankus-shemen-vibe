class_name TankController
extends Node

## Контроллер физического перемещения танка TANKUS.
## Реализует аркадное движение, заезд на рампы, прыжки, ограниченный air-control,
## поддержку Double Jump, отслеживание падения для Ground Slam и плавный доворот корпуса.

@export var move_speed: float = 8.0
@export var acceleration: float = 22.0
@export var braking: float = 26.0
@export var air_control: float = 0.45
@export var jump_velocity: float = 8.5
@export var gravity: float = 18.0
@export var body_turn_speed: float = 12.0

var speed_multiplier: float = 1.0

var _tank_body: Tank = null
var _is_jumping: bool = false
var _coyote_timer: float = 0.0
var _can_double_jump: bool = false
var _was_in_air: bool = false
var _peak_y: float = 0.0

const COYOTE_TIME: float = 0.12

func _ready() -> void:
	_tank_body = get_parent() as Tank
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
		if _was_in_air:
			var fall_dist := maxf(0.0, _peak_y - _tank_body.global_position.y)
			if _tank_body.events:
				_tank_body.events.emit_land(fall_dist)
			_was_in_air = false

		_coyote_timer = COYOTE_TIME
		_is_jumping = false
		_peak_y = _tank_body.global_position.y

		# Восстанавливаем double jump при касании земли
		if _tank_body.build and _tank_body.build.has_card("double_jump"):
			_can_double_jump = true
	else:
		_was_in_air = true
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		if _tank_body.global_position.y > _peak_y:
			_peak_y = _tank_body.global_position.y

	# Прыжок
	var wants_jump := input != null and input.consume_jump()
	var can_normal_jump := (on_floor or _coyote_timer > 0.0) and not _is_jumping

	if wants_jump and can_normal_jump:
		_tank_body.velocity.y = jump_velocity
		_is_jumping = true
		_coyote_timer = 0.0
		_peak_y = _tank_body.global_position.y
		if _tank_body.events:
			_tank_body.events.emit_jump()
	elif wants_jump and not on_floor and _can_double_jump:
		# Выполнение Double Jump в воздухе
		_can_double_jump = false
		_tank_body.velocity.y = jump_velocity
		_peak_y = _tank_body.global_position.y
		if _tank_body.events:
			_tank_body.events.emit_jump()
	elif not on_floor:
		_tank_body.velocity.y -= gravity * delta
	else:
		_tank_body.velocity.y = 0.0

	# Горизонтальное перемещение
	var move_dir: Vector3 = input.move_direction_world if input else Vector3.ZERO
	var current_accel: float = acceleration if on_floor else (acceleration * air_control)
	var current_brake: float = braking if on_floor else (braking * air_control)
	var effective_speed := move_speed * speed_multiplier

	if move_dir.length_squared() > 0.01:
		var target_vel: Vector3 = move_dir * effective_speed
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
