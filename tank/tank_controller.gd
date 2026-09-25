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
var is_on_ice: bool = false
@export var ice_acceleration_multiplier: float = 0.35
@export var ice_braking_multiplier: float = 0.08

const DUST_PUFF_SCENE: PackedScene = preload("res://vfx/dust_puff_vfx.tscn")

var _tank_body: Tank = null

# Game feel: динамический наклон подвески (Pitch/Roll) и сжатие (Squash/Stretch)
var _prev_velocity: Vector3 = Vector3.ZERO
var _current_tilt_pitch: float = 0.0
var _current_tilt_roll: float = 0.0
var _current_visual_scale: Vector3 = Vector3.ONE

func set_on_ice(val: bool) -> void:
	is_on_ice = val
var _is_jumping: bool = false
var _coyote_timer: float = 0.0
var _can_double_jump: bool = false
var _was_in_air: bool = false
var _peak_y: float = 0.0

const COYOTE_TIME: float = 0.12

func _ready() -> void:
	_tank_body = get_parent() as Tank
	if _tank_body:
		_tank_body.floor_max_angle = deg_to_rad(55.0)
		_tank_body.floor_snap_length = 0.4
		_tank_body.floor_constant_speed = true
		_tank_body.floor_stop_on_slope = false
		_tank_body.floor_block_on_wall = false

func process_physics(input: TankInput, delta: float) -> void:
	if not _tank_body:
		return

	if _tank_body.is_frozen:
		_tank_body.velocity.x = 0.0
		_tank_body.velocity.z = 0.0
		if not _tank_body.is_on_floor():
			_tank_body.velocity.y -= gravity * delta
			_tank_body.move_and_slide()
		else:
			_tank_body.velocity.y = 0.0
		return

	var on_floor := _tank_body.is_on_floor()

	if on_floor:
		if _was_in_air:
			var fall_dist := maxf(0.0, _peak_y - _tank_body.global_position.y)
			if _tank_body.events:
				_tank_body.events.emit_land(fall_dist)
			if SoundManager and fall_dist > 0.4:
				SoundManager.play_sfx_3d("land", _tank_body.global_position)
			_spawn_land_dust(fall_dist)
			_apply_land_squash(fall_dist)
			if fall_dist > 1.8 and Game:
				Game.shake_camera(0.22)
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
		_apply_jump_stretch()
	elif wants_jump and not on_floor and _can_double_jump:
		# Выполнение Double Jump в воздухе
		_can_double_jump = false
		_tank_body.velocity.y = jump_velocity
		_peak_y = _tank_body.global_position.y
		if _tank_body.events:
			_tank_body.events.emit_jump()
		_apply_jump_stretch()
	elif not on_floor:
		_tank_body.velocity.y -= gravity * delta

	# Перемещение с поддержкой наклонных плоскостей (рамп) и скольжения на льду
	var move_dir: Vector3 = input.move_direction_world if input else Vector3.ZERO
	var current_accel: float = acceleration if on_floor else (acceleration * air_control)
	var current_brake: float = braking if on_floor else (braking * air_control)
	if on_floor and is_on_ice:
		current_accel *= ice_acceleration_multiplier
		current_brake *= ice_braking_multiplier
	var effective_speed := move_speed * speed_multiplier

	if move_dir.length_squared() > 0.01:
		var target_vel: Vector3 = move_dir * effective_speed

		# Если на наклонном полу — проецируем вектор движения на нормаль пола
		if on_floor:
			var floor_norm := _tank_body.get_floor_normal()
			if floor_norm.y > 0.1 and floor_norm.y < 0.999:
				target_vel = target_vel.slide(floor_norm).normalized() * effective_speed

		_tank_body.velocity.x = move_toward(_tank_body.velocity.x, target_vel.x, current_accel * delta)
		_tank_body.velocity.z = move_toward(_tank_body.velocity.z, target_vel.z, current_accel * delta)
		if on_floor and not _is_jumping:
			_tank_body.velocity.y = move_toward(_tank_body.velocity.y, target_vel.y, current_accel * delta)
	else:
		_tank_body.velocity.x = move_toward(_tank_body.velocity.x, 0.0, current_brake * delta)
		_tank_body.velocity.z = move_toward(_tank_body.velocity.z, 0.0, current_brake * delta)
		if on_floor and not _is_jumping:
			_tank_body.velocity.y = move_toward(_tank_body.velocity.y, 0.0, current_brake * delta)

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
		_tank_body.floor_snap_length = 0.4

	_tank_body.move_and_slide()

	_update_chassis_tilt(delta)

	# Передача импульса в физические тела (маятники, ящики) при таране
	for i in range(_tank_body.get_slide_collision_count()):
		var col := _tank_body.get_slide_collision(i)
		var rbody := col.get_collider() as RigidBody3D
		if rbody:
			var push_dir := -col.get_normal()
			push_dir.y = 0.0
			var push_impulse := push_dir.normalized() * (effective_speed * 2.0)
			rbody.apply_impulse(push_impulse, col.get_position() - rbody.global_position)

func _apply_jump_stretch() -> void:
	_current_visual_scale = Vector3(0.92, 1.16, 0.92)

func _apply_land_squash(fall_dist: float) -> void:
	var factor := clampf(fall_dist * 0.05, 0.08, 0.25)
	_current_visual_scale = Vector3(1.0 + factor, 1.0 - factor, 1.0 + factor)

func _spawn_land_dust(fall_dist: float) -> void:
	if not DUST_PUFF_SCENE or not _tank_body:
		return
	var dust := DUST_PUFF_SCENE.instantiate() as DustPuffVFX
	if dust:
		var parent: Node = _tank_body.get_parent() if _tank_body.get_parent() else _tank_body
		parent.add_child(dust)
		dust.global_position = _tank_body.global_position
		dust.setup(clampf(fall_dist / 2.5, 0.8, 1.8))

func _update_chassis_tilt(delta: float) -> void:
	if not _tank_body or not _tank_body.visuals:
		return

	var current_vel := _tank_body.velocity
	var accel_world := (current_vel - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = current_vel

	# Проекция ускорения в локальный базис танка
	var local_accel := _tank_body.global_transform.basis.inverse() * accel_world

	# Наклон корпуса:
	# Торможение (local_accel.z > 0) -> клевок носом (pitch вниз > 0)
	# Разгон вперед (local_accel.z < 0) -> подъем носа (pitch вверх < 0)
	var target_pitch := clampf(local_accel.z * 0.0035, -0.12, 0.12)
	# Боковой крен при заносе/повороте
	var target_roll := clampf(-local_accel.x * 0.0025, -0.08, 0.08)

	_current_tilt_pitch = lerpf(_current_tilt_pitch, target_pitch, 14.0 * delta)
	_current_tilt_roll = lerpf(_current_tilt_roll, target_roll, 14.0 * delta)

	_tank_body.visuals.rotation.x = _current_tilt_pitch
	_tank_body.visuals.rotation.z = _current_tilt_roll

	# Плавное возвращение формы после squash / stretch
	_current_visual_scale = _current_visual_scale.lerp(Vector3.ONE, 10.0 * delta)
	_tank_body.visuals.scale = _current_visual_scale
