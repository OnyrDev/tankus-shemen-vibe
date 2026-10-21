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
@export var slope_alignment_speed: float = 14.0
@export var max_slope_angle_deg: float = 55.0

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
var _current_slope_pitch: float = 0.0
var _current_slope_roll: float = 0.0
var _current_visual_scale: Vector3 = Vector3.ONE

# 4 лучевых зонда подвески для прецизионного отслеживания рельефа
var _probe_fl: RayCast3D = null
var _probe_fr: RayCast3D = null
var _probe_rl: RayCast3D = null
var _probe_rr: RayCast3D = null

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
		_tank_body.floor_max_angle = deg_to_rad(max_slope_angle_deg)
		_tank_body.floor_snap_length = 0.4
		_tank_body.floor_constant_speed = true
		_tank_body.floor_stop_on_slope = false
		_tank_body.floor_block_on_wall = false
		_tank_body.platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
		_setup_ground_probes()

func _setup_ground_probes() -> void:
	if not _tank_body:
		return
	_probe_fl = _tank_body.get_node_or_null("GroundProbeFL") as RayCast3D
	_probe_fr = _tank_body.get_node_or_null("GroundProbeFR") as RayCast3D
	_probe_rl = _tank_body.get_node_or_null("GroundProbeRL") as RayCast3D
	_probe_rr = _tank_body.get_node_or_null("GroundProbeRR") as RayCast3D

	# Резервное программное создание, если нод нет в дереве сцены
	if not _probe_fl:
		_probe_fl = _create_probe_deferred("GroundProbeFL", Vector3(-0.68, 0.45, -0.75))
	if not _probe_fr:
		_probe_fr = _create_probe_deferred("GroundProbeFR", Vector3(0.68, 0.45, -0.75))
	if not _probe_rl:
		_probe_rl = _create_probe_deferred("GroundProbeRL", Vector3(-0.68, 0.45, 0.75))
	if not _probe_rr:
		_probe_rr = _create_probe_deferred("GroundProbeRR", Vector3(0.68, 0.45, 0.75))

	if _probe_fl: _probe_fl.add_exception(_tank_body)
	if _probe_fr: _probe_fr.add_exception(_tank_body)
	if _probe_rl: _probe_rl.add_exception(_tank_body)
	if _probe_rr: _probe_rr.add_exception(_tank_body)

func _create_probe_deferred(probe_name: String, local_pos: Vector3) -> RayCast3D:
	var existing := _tank_body.get_node_or_null(probe_name) as RayCast3D
	if existing:
		return existing
	var probe := RayCast3D.new()
	probe.name = probe_name
	probe.position = local_pos
	probe.target_position = Vector3(0.0, -1.8, 0.0)
	probe.collision_mask = 1 # Слой 1: World
	probe.hit_from_inside = true
	probe.add_exception(_tank_body)
	_tank_body.add_child.call_deferred(probe)
	return probe

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

	# Передача импульса в физические тела (маятники, ящики) при таране и толкании
	for i in range(_tank_body.get_slide_collision_count()):
		var col := _tank_body.get_slide_collision(i)
		var rbody := col.get_collider() as RigidBody3D
		if rbody and not rbody.freeze:
			var col_norm := col.get_normal()
			# Исключаем вертикальные контакты/опоры (когда танк стоит или едет сверху на ящике)
			if col_norm.y > 0.4:
				continue
			var push_dir := -col_norm
			push_dir.y = 0.0
			if push_dir.length_squared() > 0.01:
				var push_norm := push_dir.normalized()
				# Толкаем только если вектор ввода/движения танка направлен в сторону препятствия
				var is_pushing := move_dir.dot(push_norm) > 0.1
				if not is_pushing:
					continue

				# Текущая скорость физического тела вдоль направления толкания
				var current_body_speed := rbody.linear_velocity.dot(push_norm)
				# Ограничиваем максимальную скорость толкания скоростью самого танка
				var max_push_speed := effective_speed * 0.85
				var speed_deficit := max_push_speed - current_body_speed

				if speed_deficit > 0.0:
					# Дозированный импульс для легкого и плавного выравнивания скорости ящика со скоростью танка
					var push_impulse_mag := minf(speed_deficit * rbody.mass * (delta * 14.0), effective_speed * 3.5)
					rbody.apply_central_impulse(push_norm * push_impulse_mag)
				elif current_body_speed > max_push_speed + 0.5:
					# Предотвращаем бесконечный разгон: мягко гасим избыточную скорость, если ящик обогнал танк
					var excess := current_body_speed - max_push_speed
					var damp_impulse := minf(excess * rbody.mass * (delta * 6.0), effective_speed * 2.0)
					rbody.apply_central_impulse(-push_norm * damp_impulse)

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

	# 1. Наклон корпуса по рельефу (склоны, рампы, горы)
	_update_slope_tilt(delta)

	# 2. Динамический наклон подвески от ускорения/торможения
	var current_vel := _tank_body.velocity
	var accel_world := (current_vel - _prev_velocity) / maxf(delta, 0.001)
	_prev_velocity = current_vel

	# Проекция ускорения в локальный базис танка
	var local_accel := _tank_body.global_transform.basis.inverse() * accel_world

	# Наклон корпуса:
	# Торможение (local_accel.z > 0) -> клевок носом (pitch вниз > 0)
	# Разгон вперед (local_accel.z < 0) -> подъем носа (pitch вверх < 0)
	var target_pitch := clampf(-local_accel.z * 0.0035, -0.12, 0.12)
	# Боковой крен при заносе/повороте
	var target_roll := clampf(local_accel.x * 0.0025, -0.08, 0.08)

	_current_tilt_pitch = lerpf(_current_tilt_pitch, target_pitch, 14.0 * delta)
	_current_tilt_roll = lerpf(_current_tilt_roll, target_roll, 14.0 * delta)

	_tank_body.visuals.rotation.x = _current_slope_pitch + _current_tilt_pitch
	_tank_body.visuals.rotation.z = _current_slope_roll + _current_tilt_roll

	# Базовый визуальный масштаб всего танка (от карт/статов) строго изотропен
	var base_tank_scale := _tank_body.stats.tank_scale if (_tank_body and _tank_body.stats) else 1.0
	_tank_body.visuals.scale = Vector3.ONE * base_tank_scale

	# Плавное возвращение формы подвески после squash / stretch
	_current_visual_scale = _current_visual_scale.lerp(Vector3.ONE, 10.0 * delta)

	# Применяем squash / stretch ТОЛЬКО к элементам шасси (корпус и гусеницы),
	# чтобы ствол и башня оставались жесткими и никогда не деформировались при прыжках/ударах
	if _tank_body.chassis_mesh:
		_tank_body.chassis_mesh.scale = _current_visual_scale
	if _tank_body.left_track:
		_tank_body.left_track.scale = _current_visual_scale
	if _tank_body.right_track:
		_tank_body.right_track.scale = _current_visual_scale

	# Башня следует по вертикали за сжатием подвески, сохраняя строгий единичный масштаб
	if _tank_body.turret:
		_tank_body.turret.scale = Vector3.ONE
		_tank_body.turret.position.y = 0.72 + 0.45 * (_current_visual_scale.y - 1.0)
		if _tank_body.turret.barrel_mount:
			_tank_body.turret.barrel_mount.scale = Vector3.ONE

func _compute_ground_normal() -> Vector3:
	if not _tank_body:
		return Vector3.UP

	var on_floor := _tank_body.is_on_floor()

	# Когда танк в воздухе (прыжок / падение), ориентация возвращается в горизонталь
	if not on_floor:
		return Vector3.UP

	var min_cos := cos(deg_to_rad(max_slope_angle_deg))

	# 1. Считываем показания 4 лучевых зондов по углам гусениц
	if _probe_fl and _probe_fr and _probe_rl and _probe_rr:
		_probe_fl.force_raycast_update()
		_probe_fr.force_raycast_update()
		_probe_rl.force_raycast_update()
		_probe_rr.force_raycast_update()

		if _probe_fl.is_colliding() and _probe_fr.is_colliding() and _probe_rl.is_colliding() and _probe_rr.is_colliding():
			var fl := _tank_body.to_local(_probe_fl.get_collision_point())
			var fr := _tank_body.to_local(_probe_fr.get_collision_point())
			var rl := _tank_body.to_local(_probe_rl.get_collision_point())
			var rr := _tank_body.to_local(_probe_rr.get_collision_point())

			var v_long := ((fl - rl) + (fr - rr)) * 0.5
			var v_lat := ((fr - fl) + (rr - rl)) * 0.5
			var local_norm := v_lat.cross(v_long).normalized()

			if local_norm.y >= min_cos:
				return local_norm

	# 2. Резервный расчет через физическую нормаль пола CharacterBody3D
	var floor_norm := _tank_body.get_floor_normal()
	if floor_norm.length_squared() > 0.01:
		var local_norm := _tank_body.global_transform.basis.inverse() * floor_norm
		if local_norm.y >= min_cos:
			return local_norm.normalized()

	return Vector3.UP

func _update_slope_tilt(delta: float) -> void:
	var ground_norm := _compute_ground_normal()
	var target_slope_pitch := atan2(ground_norm.z, ground_norm.y)
	var target_slope_roll := -atan2(ground_norm.x, ground_norm.y)

	var align_factor := clampf(slope_alignment_speed * delta, 0.0, 1.0)
	_current_slope_pitch = lerp_angle(_current_slope_pitch, target_slope_pitch, align_factor)
	_current_slope_roll = lerp_angle(_current_slope_roll, target_slope_roll, align_factor)

func update_tilt_only(delta: float) -> void:
	if not _tank_body or not _tank_body.visuals:
		return

	_update_slope_tilt(delta)

	# Затухание динамических колебаний подвески
	_current_tilt_pitch = lerpf(_current_tilt_pitch, 0.0, 14.0 * delta)
	_current_tilt_roll = lerpf(_current_tilt_roll, 0.0, 14.0 * delta)

	_tank_body.visuals.rotation.x = _current_slope_pitch + _current_tilt_pitch
	_tank_body.visuals.rotation.z = _current_slope_roll + _current_tilt_roll

	var base_tank_scale := _tank_body.stats.tank_scale if (_tank_body and _tank_body.stats) else 1.0
	_tank_body.visuals.scale = Vector3.ONE * base_tank_scale

	_current_visual_scale = _current_visual_scale.lerp(Vector3.ONE, 10.0 * delta)

	if _tank_body.chassis_mesh:
		_tank_body.chassis_mesh.scale = _current_visual_scale
	if _tank_body.left_track:
		_tank_body.left_track.scale = _current_visual_scale
	if _tank_body.right_track:
		_tank_body.right_track.scale = _current_visual_scale

	if _tank_body.turret:
		_tank_body.turret.scale = Vector3.ONE
		_tank_body.turret.position.y = 0.72 + 0.45 * (_current_visual_scale.y - 1.0)
		if _tank_body.turret.barrel_mount:
			_tank_body.turret.barrel_mount.scale = Vector3.ONE

func reset_tilt() -> void:
	_current_slope_pitch = 0.0
	_current_slope_roll = 0.0
	_current_tilt_pitch = 0.0
	_current_tilt_roll = 0.0
	_prev_velocity = Vector3.ZERO
	if _tank_body and _tank_body.visuals:
		_tank_body.visuals.rotation.x = 0.0
		_tank_body.visuals.rotation.z = 0.0
