class_name Turret
extends Node3D

## Контроллер башни и ствола танка.
## Обеспечивает независимый доворот башни на 3D точку прицеливания с ограничением скорости
## и наклон ствола под рельеф (рампы, возвышенности).

@export var rotation_speed: float = 20.0 # рад/сек
@export var pitch_speed: float = 16.0 # рад/сек
@export var min_pitch_deg: float = -25.0 # наклон вниз
@export var max_pitch_deg: float = 45.0 # наклон вверх

@onready var barrel_mount: Node3D = get_node_or_null("BarrelMount")
@onready var muzzle: Marker3D = get_node_or_null("BarrelMount/Muzzle")

var _current_target: Vector3 = Vector3.ZERO
var _has_target: bool = false

func aim_at(target_point: Vector3, delta: float) -> void:
	_current_target = target_point
	_has_target = true

	var to_target := target_point - global_position
	var flat_dir := Vector3(to_target.x, 0.0, to_target.z)

	if flat_dir.length_squared() > 0.01:
		flat_dir = flat_dir.normalized()
		# В Godot forward = (0, 0, -1), поэтому угол yaw = atan2(-x, -z)
		var target_yaw := atan2(-flat_dir.x, -flat_dir.z)
		var current_yaw := global_rotation.y
		var diff_yaw := wrapf(target_yaw - current_yaw, -PI, PI)
		var step_yaw := signf(diff_yaw) * minf(absf(diff_yaw), rotation_speed * delta)
		global_rotation.y += step_yaw

	if barrel_mount:
		var dist_h := Vector2(to_target.x, to_target.z).length()
		if dist_h > 0.01:
			var target_pitch := clampf(
				atan2(to_target.y, dist_h),
				deg_to_rad(min_pitch_deg),
				deg_to_rad(max_pitch_deg)
			)
			# Положительный pitch поднимает ствол (вращение вокруг локальной оси X)
			var current_pitch := barrel_mount.rotation.x
			var diff_pitch := target_pitch - current_pitch
			var step_pitch := signf(diff_pitch) * minf(absf(diff_pitch), pitch_speed * delta)
			barrel_mount.rotation.x += step_pitch

func get_muzzle_transform() -> Transform3D:
	if muzzle:
		return muzzle.global_transform
	return global_transform

func get_muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position

func get_shoot_direction() -> Vector3:
	if _has_target:
		var dir := (_current_target - get_muzzle_position()).normalized()
		if dir.length_squared() > 0.001:
			return dir

	if muzzle:
		return -muzzle.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()
