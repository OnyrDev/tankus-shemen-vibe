class_name TankAirTelegraph
extends Node3D

## Трекер воздушного положения танка для проекции 3D-маркера приземления и зоны Ground Slam.
## Работает единообразно в соло, на сервере и для интерполируемых удалённых танков на клиентах
## (определяет высоту над рельефом по лучу маски 1 и пику траектории прыжка без лишнего трафика).

const AIRBORNE_HEIGHT_THRESHOLD: float = 0.42
const RAY_UP_OFFSET: float = 0.55
const RAY_DOWN_LENGTH: float = 34.0
const DEFAULT_GRAVITY: float = 18.0

var _tank: Tank = null
var _telegraph: GroundTelegraph3D = null

var _is_airborne: bool = false
var _is_slam_threat: bool = false
var _has_ground_hit: bool = false
var _ground_point: Vector3 = Vector3.ZERO
var _height_above_ground: float = 0.0
var _air_peak_y: float = 0.0
var _current_slam_radius: float = 0.0
var _prev_tank_y: float = 0.0
var _estimated_vel_y: float = 0.0
var _has_prev_y: bool = false

func _ready() -> void:
	_tank = get_parent() as Tank
	_telegraph = GroundTelegraph3D.create_tracked(self, 0.95, GroundTelegraph3D.Preset.NEUTRAL_DROP)
	if _telegraph:
		_telegraph.top_level = true
	if _tank:
		_prev_tank_y = _tank.global_position.y
		_air_peak_y = _tank.global_position.y
		_has_prev_y = true

func _process(delta: float) -> void:
	evaluate_state(delta)

## Вычисляет текущее воздушное состояние и обновляет проекционный Decal-телеграф.
## Выделено в публичный метод для детерминированного вызова из автотестов.
func evaluate_state(delta: float) -> void:
	if not is_instance_valid(_tank) or not _telegraph:
		return

	var cur_y := _tank.global_position.y
	if _has_prev_y and delta > 0.0001:
		var inst_vy := (cur_y - _prev_tank_y) / delta
		_estimated_vel_y = lerpf(_estimated_vel_y, inst_vy, clampf(16.0 * delta, 0.0, 1.0))
	_prev_tank_y = cur_y
	_has_prev_y = true

	if not _tank.is_active or not _tank.visible or (_tank.health and not _tank.health.is_alive()):
		_reset_grounded(cur_y)
		return

	if not is_inside_tree() or not get_world_3d():
		_reset_grounded(cur_y)
		return

	var space := get_world_3d().direct_space_state
	var from_pos := _tank.global_position + Vector3(0.0, RAY_UP_OFFSET, 0.0)
	var to_pos := _tank.global_position - Vector3(0.0, RAY_DOWN_LENGTH, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1)
	var hit := space.intersect_ray(ray)

	if hit.is_empty():
		# Над пропастью: пол не найден, но продолжаем помнить верхнюю точку прыжка
		_has_ground_hit = false
		_is_slam_threat = false
		_air_peak_y = maxf(_air_peak_y, cur_y)
		_telegraph.update_tracked(Vector3.ZERO, 1.0, 0.0, false, GroundTelegraph3D.Preset.NEUTRAL_DROP)
		return

	_has_ground_hit = true
	_ground_point = hit.position
	_height_above_ground = cur_y - _ground_point.y

	var locally_grounded := false
	if (_tank.net_sync == null or _tank.net_sync.is_local_owner()) and _tank.is_on_floor() and _height_above_ground < 0.6:
		locally_grounded = true

	if locally_grounded or _height_above_ground < AIRBORNE_HEIGHT_THRESHOLD:
		_reset_grounded(cur_y)
		return

	if not _is_airborne:
		_is_airborne = true
		_air_peak_y = cur_y
	else:
		_air_peak_y = maxf(_air_peak_y, cur_y)

	var potential_fall_dist := _air_peak_y - _ground_point.y
	var slam_stacks := _tank.build.get_stacks("ground_slam") if _tank.build else 0

	if slam_stacks > 0 and potential_fall_dist >= CardDatabase.GroundSlamEffect.MIN_FALL_DIST:
		_is_slam_threat = true
		_current_slam_radius = CardDatabase.GroundSlamEffect.get_slam_radius(slam_stacks)
		var viewer := TankAppearance.resolve_viewer_tank(get_tree())
		var is_enemy := TankAppearance.is_tank_enemy(_tank, viewer) if viewer else (_tank.peer_id != 1)
		var slam_preset := GroundTelegraph3D.Preset.DANGER if is_enemy else GroundTelegraph3D.Preset.ALLY_SLAM
		var span := maxf(CardDatabase.GroundSlamEffect.MIN_FALL_DIST, potential_fall_dist)
		var prog := clampf(1.0 - (_height_above_ground / span), 0.14, 1.0)
		_telegraph.update_tracked(_ground_point, _current_slam_radius, prog, true, slam_preset)
	else:
		_is_slam_threat = false
		_current_slam_radius = 0.0
		var t_scale := _tank.stats.tank_scale if _tank.stats else 1.0
		var drop_radius := 0.95 * t_scale
		var drop_span := maxf(1.6, potential_fall_dist)
		var drop_prog := clampf(1.0 - (_height_above_ground / drop_span), 0.25, 0.96)
		_telegraph.update_tracked(_ground_point, drop_radius, drop_prog, true, GroundTelegraph3D.Preset.NEUTRAL_DROP)

func reset_tracking() -> void:
	var y_now := _tank.global_position.y if is_instance_valid(_tank) else 0.0
	_estimated_vel_y = 0.0
	_prev_tank_y = y_now
	_reset_grounded(y_now)

func is_slam_airborne() -> bool:
	return _is_airborne and _is_slam_threat and _has_ground_hit

func get_ground_landing_point() -> Vector3:
	return _ground_point

func get_current_slam_radius() -> float:
	return _current_slam_radius

func get_estimated_landing_eta() -> float:
	if not _is_airborne or not _has_ground_hit or _height_above_ground <= 0.01:
		return 99.0
	var grav := _tank.controller.gravity if (_tank and _tank.controller) else DEFAULT_GRAVITY
	if _tank and _tank.build:
		var ff_stacks := _tank.build.get_stacks("feather_fall")
		if ff_stacks > 0 and _estimated_vel_y <= 0.0:
			var max_fall := CardDatabase.FeatherFallEffect.get_max_fall_speed(ff_stacks)
			return _height_above_ground / maxf(0.5, maxf(-_estimated_vel_y, max_fall * 0.8))
	# Решаем 0.5 * g * t^2 - vy * t - h = 0 (при vy < 0 падение вниз ускоряется)
	var vy := _estimated_vel_y
	if is_instance_valid(_tank) and (_tank.net_sync == null or _tank.net_sync.is_local_owner()):
		vy = _tank.velocity.y
	var disc := vy * vy + 2.0 * grav * _height_above_ground
	if disc < 0.0:
		return 1.0
	return maxf(0.05, (vy + sqrt(disc)) / maxf(0.1, grav))

func get_telegraph() -> GroundTelegraph3D:
	return _telegraph

func _reset_grounded(cur_y: float) -> void:
	_is_airborne = false
	_is_slam_threat = false
	_has_ground_hit = false
	_height_above_ground = 0.0
	_current_slam_radius = 0.0
	_air_peak_y = cur_y
	if _telegraph:
		_telegraph.update_tracked(Vector3.ZERO, 1.0, 0.0, false, GroundTelegraph3D.Preset.NEUTRAL_DROP)

