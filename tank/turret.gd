class_name Turret
extends Node3D

## Контроллер башни и ствола танка.
## Обеспечивает независимый доворот башни на 3D точку прицеливания с ограничением скорости
## в локальной плоскости корпуса танка (без крена/завала набок)
## и наклон ствола под рельеф (рампы, возвышенности).

@export var rotation_speed: float = 20.0 # рад/сек
@export var pitch_speed: float = 16.0 # рад/сек
@export var min_pitch_deg: float = -35.0 # наклон вниз
@export var max_pitch_deg: float = 45.0 # наклон вверх

@onready var barrel_mount: Node3D = get_node_or_null("BarrelMount")
@onready var muzzle: Marker3D = get_node_or_null("BarrelMount/Muzzle")

var _current_target: Vector3 = Vector3.ZERO
var _has_target: bool = false

func aim_at(target_point: Vector3, delta: float) -> void:
	_current_target = target_point
	_has_target = true

	# Цель в локальных координатах башни
	var local_target := to_local(target_point)
	var flat_target := Vector2(local_target.x, local_target.z)

	if flat_target.length_squared() > 0.001:
		# В Godot вперед — это -Z, поэтому angle_yaw = atan2(-x, -z)
		var angle_yaw := atan2(-flat_target.x, -flat_target.y)
		var step_yaw := signf(angle_yaw) * minf(absf(angle_yaw), rotation_speed * delta)
		rotation.y += step_yaw

	# Башня всегда сидит строго на погоне корпуса — никакого наклона/крена по X и Z!
	rotation.x = 0.0
	rotation.z = 0.0

	# Наклон ствола (pitch) в локальных координатах башни вокруг локальной оси X ствола
	if barrel_mount:
		# Вектор от шарнира ствола к цели в пространстве башни (где rest pitch = 0)
		var dir_in_turret := to_local(target_point) - barrel_mount.position
		var dist_h := Vector2(dir_in_turret.x, dir_in_turret.z).length()
		if dist_h > 0.01:
			var target_pitch := clampf(
				atan2(dir_in_turret.y, dist_h),
				deg_to_rad(min_pitch_deg),
				deg_to_rad(max_pitch_deg)
			)
			var current_pitch := barrel_mount.rotation.x
			var diff_pitch := target_pitch - current_pitch
			var step_pitch := signf(diff_pitch) * minf(absf(diff_pitch), pitch_speed * delta)
			barrel_mount.rotation.x += step_pitch

		# Ствол поднимается/опускается только по X, никаких поворотов/кренов по Y и Z
		barrel_mount.rotation.y = 0.0
		barrel_mount.rotation.z = 0.0

func get_muzzle_transform() -> Transform3D:
	if muzzle:
		return muzzle.global_transform
	return global_transform

func get_muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position

func get_shoot_direction() -> Vector3:
	if _has_target and muzzle:
		var to_target := _current_target - muzzle.global_position
		if to_target.length_squared() > 0.01:
			var target_dir := to_target.normalized()
			var barrel_dir := -muzzle.global_transform.basis.z.normalized()
			# Сведение снаряда в точку прицела (Crosshair Convergence)
			# Если ствол наведен в сектор цели (до ~45 градусов отклонения при повороте),
			# снаряд вылетает СТРОГО в точку прицела без отклонений по высоте.
			if barrel_dir.dot(target_dir) > 0.7:
				return target_dir
	if muzzle:
		return -muzzle.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()
