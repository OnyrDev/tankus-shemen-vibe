class_name ThreatIndicatorHUD
extends Control

## Экранный радар угроз и урона вокруг центрального прицела (TPS 3D Readability).
## Слой 1 (Damage Hit Arcs): багровые дуги направления полученного удара/взрыва, привязанные к мировой точке
##   (при довороте камеры на звук выстрела дуга плавно приводит прицел точно на стрелка).
## Слой 2 (Incoming Threat Chevrons): проактивные шевроны вне центрального обзора для летящих в танк
##   вражеских снарядов (включая 1 рикошет), падающих врагов с Ground Slam и близких мин в слепой зоне,
##   с визуальным акцентом под тайминг [E] Block (0.35с).

const DAMAGE_ARC_RADIUS: float = 92.0
const CHEVRON_RING_RADIUS: float = 114.0
const DAMAGE_ARC_DURATION: float = 0.85
const DAMAGE_MERGE_ANGLE_RAD: float = deg_to_rad(22.0)

const CENTRAL_CONE_HALF_ANGLE_RAD: float = deg_to_rad(36.0)
const PROJ_MAX_ETA: float = 1.05
const PROJ_DANGER_RADIUS_BASE: float = 3.8
const BLOCK_URGENT_ETA: float = 0.44
const CHEVRON_CLUSTER_ANGLE_RAD: float = deg_to_rad(20.0)
const MAX_VISIBLE_CHEVRONS: int = 4
const MINE_WARN_RADIUS: float = 5.0

var _bound_tank: Tank = null
var _damage_arcs: Array[Dictionary] = []     # {world_origin: Vector3, amount: float, age: float, duration: float}
var _active_threats: Array[Dictionary] = []  # {angle: float, eta: float, urgent: bool, kind: int}
var _pulse_clock: float = 0.0

enum ThreatKind {
	PROJECTILE,
	GROUND_SLAM,
	MINE,
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func bind_to_tank(tank: Tank) -> void:
	_bound_tank = tank
	clear_indicators()

func clear_indicators() -> void:
	_damage_arcs.clear()
	_active_threats.clear()
	queue_redraw()

func register_damage_from(world_origin: Vector3, amount: float) -> void:
	if not world_origin.is_finite() or amount <= 0.01:
		return

	var viewer_pos := _get_viewer_position()
	var cam_basis := _get_camera_basis()
	var new_angle := compute_azimuth_angle(viewer_pos, cam_basis, world_origin)

	# Склеиваем близкие по углу попадания (очередь или дробь Shotgun), усиливая дугу
	for entry in _damage_arcs:
		var existing_origin: Vector3 = entry["world_origin"]
		var existing_angle := compute_azimuth_angle(viewer_pos, cam_basis, existing_origin)
		if absf( angle_difference(existing_angle, new_angle) ) <= DAMAGE_MERGE_ANGLE_RAD:
			entry["world_origin"] = world_origin
			entry["amount"] = minf(120.0, float(entry["amount"]) + amount * 0.65)
			entry["age"] = 0.0
			queue_redraw()
			return

	_damage_arcs.append({
		"world_origin": world_origin,
		"amount": clampf(amount, 4.0, 120.0),
		"age": 0.0,
		"duration": DAMAGE_ARC_DURATION,
	})
	if _damage_arcs.size() > 6:
		_damage_arcs.pop_front()
	queue_redraw()

func get_damage_arc_count() -> int:
	return _damage_arcs.size()

func get_active_threats() -> Array[Dictionary]:
	return _active_threats

func _process(delta: float) -> void:
	_pulse_clock += delta
	var had_visuals := (not _damage_arcs.is_empty()) or (not _active_threats.is_empty())

	_tick_damage_arcs(delta)
	_scan_incoming_threats()

	if had_visuals or not _damage_arcs.is_empty() or not _active_threats.is_empty():
		queue_redraw()

func _tick_damage_arcs(delta: float) -> void:
	var i := _damage_arcs.size() - 1
	while i >= 0:
		var entry: Dictionary = _damage_arcs[i]
		entry["age"] = float(entry["age"]) + delta
		if float(entry["age"]) >= float(entry["duration"]):
			_damage_arcs.remove_at(i)
		i -= 1

func _scan_incoming_threats() -> void:
	_active_threats.clear()
	var tank := _resolve_observed_tank()
	if not tank or not tank.is_active or (tank.health and not tank.health.is_alive()):
		return

	var tree := get_tree()
	if not tree:
		return

	var cam := _get_active_camera()
	var cam_basis := _get_camera_basis_from(cam, tank)
	var tank_center := tank.global_position + Vector3(0.0, 0.55, 0.0)
	var tank_scale := tank.stats.tank_scale if tank.stats else 1.0
	var danger_radius := PROJ_DANGER_RADIUS_BASE * maxf(0.85, tank_scale)

	var candidates: Array[Dictionary] = []

	# 1. Летящие вражеские снаряды вне центрального обзора (включая 1 отскок от ближайшей стены)
	var space: PhysicsDirectSpaceState3D = tank.get_world_3d().direct_space_state if tank.get_world_3d() else null
	for node in tree.get_nodes_in_group("projectiles"):
		var proj := node as Projectile
		if not proj or not is_instance_valid(proj) or proj._is_destroyed:
			continue
		if not is_projectile_hostile(proj, tank):
			continue

		var eval := evaluate_projectile_threat_with_bounce(
			proj.global_position,
			proj.velocity,
			proj.bounces_left,
			tank_center,
			danger_radius,
			PROJ_MAX_ETA,
			space
		)
		if not bool(eval.get("is_threat", false)):
			continue

		var origin: Vector3 = eval["threat_origin"]
		var angle := compute_azimuth_angle(tank_center, cam_basis, origin)
		if not _is_outside_central_view(origin, angle, cam):
			continue

		var eta := float(eval["eta"])
		candidates.append({
			"angle": angle,
			"eta": eta,
			"urgent": eta <= BLOCK_URGENT_ETA,
			"kind": ThreatKind.PROJECTILE,
		})

	# 2. Воздушные вражеские танки с Ground Slam, падающие рядом со слепой зоной
	for node in tree.get_nodes_in_group("tanks"):
		var enemy := node as Tank
		if not enemy or enemy == tank or not enemy.is_active:
			continue
		if not TankAppearance.is_tank_enemy(enemy, tank):
			continue
		var air_tel := enemy.get_node_or_null("TankAirTelegraph") as TankAirTelegraph
		if not air_tel or not air_tel.is_slam_airborne():
			continue

		var slam_pos := air_tel.get_ground_landing_point()
		var slam_r := air_tel.get_current_slam_radius()
		var horiz_dist := Vector2(slam_pos.x - tank_center.x, slam_pos.z - tank_center.z).length()
		if horiz_dist > slam_r + 2.2:
			continue

		var slam_angle := compute_azimuth_angle(tank_center, cam_basis, slam_pos)
		if not _is_outside_central_view(enemy.global_position, slam_angle, cam):
			continue

		var slam_eta := clampf(air_tel.get_estimated_landing_eta(), 0.05, 1.2)
		candidates.append({
			"angle": slam_angle,
			"eta": slam_eta,
			"urgent": slam_eta <= BLOCK_URGENT_ETA and horiz_dist <= slam_r + 0.6,
			"kind": ThreatKind.GROUND_SLAM,
		})

	# 3. Вражеские прыжковые мины (JumpMine) вплотную со спины/фланга
	for node in tree.get_nodes_in_group("jump_mines"):
		var mine := node as Area3D
		if not mine or not is_instance_valid(mine):
			continue
		if mine.has_meta("detonated") and bool(mine.get_meta("detonated")):
			continue
		if not _is_mine_hostile(mine, tank):
			continue

		var dist_to_mine := mine.global_position.distance_to(tank.global_position)
		if dist_to_mine > MINE_WARN_RADIUS:
			continue

		var mine_angle := compute_azimuth_angle(tank_center, cam_basis, mine.global_position)
		if not _is_outside_central_view(mine.global_position, mine_angle, cam):
			continue

		# Предупреждаем остро, если мина совсем рядом или танк пятится прямо на неё
		var to_mine := (mine.global_position - tank.global_position)
		var closing := tank.velocity.dot(to_mine.normalized()) if to_mine.length_squared() > 0.001 else 0.0
		if dist_to_mine > 3.2 and closing < 0.8:
			continue
		var mine_eta := clampf((dist_to_mine - 1.2) / maxf(2.5, closing), 0.18, 0.95)
		candidates.append({
			"angle": mine_angle,
			"eta": mine_eta,
			"urgent": dist_to_mine <= 2.8 or mine_eta <= BLOCK_URGENT_ETA,
			"kind": ThreatKind.MINE,
		})

	_active_threats = cluster_and_prioritize_threats(candidates)

static func is_projectile_hostile(proj: Projectile, viewer_tank: Tank) -> bool:
	if not proj or not viewer_tank:
		return false
	if proj.shooter == viewer_tank:
		return false
	if proj.shooter_peer_id >= 0 and proj.shooter_peer_id == viewer_tank.peer_id:
		return false
	if Game and Game.rules and Game.rules.is_team_mode and not Game.rules.friendly_fire:
		if proj.team_id >= 0 and proj.team_id == viewer_tank.team_id:
			return false
	elif proj.shooter_peer_id < 0 and proj.team_id >= 0 and proj.team_id == viewer_tank.team_id:
		return false
	return true

static func _is_mine_hostile(mine: Area3D, viewer_tank: Tank) -> bool:
	var owner_peer: int = int(mine.get_meta("owner_peer_id")) if mine.has_meta("owner_peer_id") else -1
	var owner_team: int = int(mine.get_meta("owner_team_id")) if mine.has_meta("owner_team_id") else -1
	if owner_peer >= 0 and owner_peer == viewer_tank.peer_id:
		return false
	if Game and Game.rules and Game.rules.is_team_mode and not Game.rules.friendly_fire:
		if owner_team >= 0 and owner_team == viewer_tank.team_id:
			return false
	return true

## Горизонтальный азимут цели относительно взгляда камеры:
## 0 = строго по прицелу (верх кольца), +PI/2 = справа, -PI/2 = слева, ±PI = строго за спиной.
static func compute_azimuth_angle(viewer_pos: Vector3, cam_basis: Basis, target_pos: Vector3) -> float:
	var delta := target_pos - viewer_pos
	var dir_xz := Vector2(delta.x, delta.z)
	if dir_xz.length_squared() < 0.0001:
		return PI

	dir_xz = dir_xz.normalized()
	var fwd3 := -cam_basis.z
	var fwd_xz := Vector2(fwd3.x, fwd3.z)
	if fwd_xz.length_squared() < 0.0001:
		var up3 := -cam_basis.y
		fwd_xz = Vector2(up3.x, up3.z)
	if fwd_xz.length_squared() < 0.0001:
		fwd_xz = Vector2(0.0, -1.0)
	fwd_xz = fwd_xz.normalized()

	var right3 := cam_basis.x
	var right_xz := Vector2(right3.x, right3.z)
	if right_xz.length_squared() < 0.0001:
		right_xz = Vector2(-fwd_xz.y, fwd_xz.x)
	else:
		right_xz = right_xz.normalized()

	return atan2(dir_xz.dot(right_xz), dir_xz.dot(fwd_xz))

static func evaluate_projectile_threat(
	proj_pos: Vector3,
	proj_vel: Vector3,
	tank_pos: Vector3,
	danger_radius: float,
	max_eta: float = PROJ_MAX_ETA
) -> Dictionary:
	var speed_sq := proj_vel.length_squared()
	if speed_sq < 0.25:
		return {"is_threat": false}

	var rel := proj_pos - tank_pos
	var t_closest := -rel.dot(proj_vel) / speed_sq
	if t_closest < -0.04 or t_closest > max_eta:
		return {"is_threat": false}

	var t_eval := maxf(0.0, t_closest)
	var closest_pt := proj_pos + proj_vel * t_eval
	if absf(closest_pt.y - tank_pos.y) > 2.6:
		return {"is_threat": false}

	var closest_dist := closest_pt.distance_to(tank_pos)
	if closest_dist > danger_radius:
		return {"is_threat": false}

	return {
		"is_threat": true,
		"eta": t_eval,
		"closest_dist": closest_dist,
		"threat_origin": proj_pos,
	}

static func evaluate_projectile_threat_with_bounce(
	proj_pos: Vector3,
	proj_vel: Vector3,
	bounces_left: int,
	tank_pos: Vector3,
	danger_radius: float,
	max_eta: float,
	space: PhysicsDirectSpaceState3D = null
) -> Dictionary:
	var direct := evaluate_projectile_threat(proj_pos, proj_vel, tank_pos, danger_radius, max_eta)
	if bool(direct.get("is_threat", false)):
		# Убедимся, что между снарядом и точкой сближения нет глухой стены (если нет рикошета)
		if space and bounces_left <= 0:
			var closest_pt := proj_pos + proj_vel * float(direct["eta"])
			if proj_pos.distance_squared_to(closest_pt) > 0.04:
				var wall_q := PhysicsRayQueryParameters3D.create(proj_pos, closest_pt, 1)
				if not space.intersect_ray(wall_q).is_empty():
					return {"is_threat": false}
		return direct

	if bounces_left <= 0 or not space:
		return {"is_threat": false}

	var speed := proj_vel.length()
	if speed < 0.5:
		return {"is_threat": false}

	var max_wall_dist := minf(10.5, speed * max_eta)
	var ray_to := proj_pos + (proj_vel / speed) * max_wall_dist
	var query := PhysicsRayQueryParameters3D.create(proj_pos, ray_to, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"is_threat": false}

	var hit_pos: Vector3 = hit.position
	var hit_norm: Vector3 = (hit.normal as Vector3).normalized()
	if hit_norm.length_squared() < 0.01:
		return {"is_threat": false}

	var t_to_wall := proj_pos.distance_to(hit_pos) / speed
	var rem_eta := max_eta - t_to_wall
	if rem_eta <= 0.05:
		return {"is_threat": false}

	var bounced_vel := proj_vel.bounce(hit_norm)
	var after_bounce := evaluate_projectile_threat(
		hit_pos + hit_norm * 0.2,
		bounced_vel,
		tank_pos,
		danger_radius * 0.92,
		rem_eta
	)
	if not bool(after_bounce.get("is_threat", false)):
		return {"is_threat": false}

	return {
		"is_threat": true,
		"eta": t_to_wall + float(after_bounce["eta"]),
		"closest_dist": float(after_bounce["closest_dist"]),
		"threat_origin": hit_pos,
	}

static func cluster_and_prioritize_threats(candidates: Array[Dictionary]) -> Array[Dictionary]:
	if candidates.is_empty():
		return []

	# Сортируем по срочности (меньше ETA — выше приоритет)
	var sorted := candidates.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["eta"]) < float(b["eta"])
	)

	var clustered: Array[Dictionary] = []
	for item in sorted:
		var ang := float(item["angle"])
		var merged := false
		for existing in clustered:
			if absf(angle_difference(float(existing["angle"]), ang)) <= CHEVRON_CLUSTER_ANGLE_RAD:
				if bool(item["urgent"]):
					existing["urgent"] = true
				merged = true
				break
		if not merged:
			clustered.append(item.duplicate())
			if clustered.size() >= MAX_VISIBLE_CHEVRONS:
				break

	return clustered

func _is_outside_central_view(world_pos: Vector3, azimuth: float, cam: Camera3D) -> bool:
	if absf(azimuth) > CENTRAL_CONE_HALF_ANGLE_RAD:
		return true
	if not cam:
		return false
	if cam.is_position_behind(world_pos):
		return true
	var vp_rect := get_viewport_rect()
	if vp_rect.size.x <= 1.0 or vp_rect.size.y <= 1.0:
		return false
	var screen_pt := cam.unproject_position(world_pos)
	var safe_margin_x := vp_rect.size.x * 0.18
	var safe_margin_y := vp_rect.size.y * 0.18
	var central_box := Rect2(
		safe_margin_x,
		safe_margin_y,
		vp_rect.size.x - safe_margin_x * 2.0,
		vp_rect.size.y - safe_margin_y * 2.0
	)
	return not central_box.has_point(screen_pt)

func _resolve_observed_tank() -> Tank:
	if is_instance_valid(_bound_tank) and _bound_tank.is_active:
		return _bound_tank
	if get_tree():
		var viewer := TankAppearance.resolve_viewer_tank(get_tree())
		if viewer:
			return viewer
	return _bound_tank if is_instance_valid(_bound_tank) else null

func _get_active_camera() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp else null

func _get_viewer_position() -> Vector3:
	var t := _resolve_observed_tank()
	if t:
		return t.global_position + Vector3(0.0, 0.55, 0.0)
	var cam := _get_active_camera()
	return cam.global_position if cam else Vector3.ZERO

func _get_camera_basis() -> Basis:
	return _get_camera_basis_from(_get_active_camera(), _resolve_observed_tank())

func _get_camera_basis_from(cam: Camera3D, fallback_tank: Tank) -> Basis:
	if cam:
		return cam.global_transform.basis
	if fallback_tank:
		return fallback_tank.global_transform.basis
	return Basis.IDENTITY

func _draw() -> void:
	if _damage_arcs.is_empty() and _active_threats.is_empty():
		return

	var center := size * 0.5
	var viewer_pos := _get_viewer_position()
	var cam_basis := _get_camera_basis()

	# 1. Отрисовка дуг полученного урона (Damage Hit Arcs)
	for entry in _damage_arcs:
		var age := float(entry["age"])
		var dur := maxf(0.05, float(entry["duration"]))
		var life_t := clampf(age / dur, 0.0, 1.0)
		var alpha := pow(1.0 - life_t, 1.45)
		if alpha <= 0.01:
			continue

		var dmg := float(entry["amount"])
		var weight := clampf(dmg / 55.0, 0.25, 1.0)
		var half_span := lerpf(deg_to_rad(16.0), deg_to_rad(31.0), weight)
		var pop_offset := (1.0 - clampf(age / 0.12, 0.0, 1.0)) * 5.0
		var arc_r := DAMAGE_ARC_RADIUS + pop_offset

		var az := compute_azimuth_angle(viewer_pos, cam_basis, entry["world_origin"] as Vector3)
		# В экранных координатах Control: -PI/2 — это верх (12 часов), +PI/2 — низ (6 часов)
		var screen_angle := az - PI * 0.5

		# Контрастная тёмная подложка под дугой
		draw_arc(
			center,
			arc_r,
			screen_angle - half_span * 1.06,
			screen_angle + half_span * 1.06,
			28,
			Color(0.03, 0.015, 0.02, 0.62 * alpha),
			11.0,
			true
		)
		# Основное алое тело дуги
		draw_arc(
			center,
			arc_r,
			screen_angle - half_span,
			screen_angle + half_span,
			28,
			Color(0.98, 0.16, 0.14, 0.92 * alpha),
			6.5,
			true
		)
		# Яркое внутреннее ядро и остриё в центр удара
		draw_arc(
			center,
			arc_r - 1.5,
			screen_angle - half_span * 0.55,
			screen_angle + half_span * 0.55,
			18,
			Color(1.0, 0.62, 0.52, 0.88 * alpha),
			2.6,
			true
		)

		var dir_vec := Vector2(cos(screen_angle), sin(screen_angle))
		var perp_vec := Vector2(-dir_vec.y, dir_vec.x)
		var tip := center + dir_vec * (arc_r + 11.5)
		var base_l := center + dir_vec * (arc_r + 2.5) - perp_vec * 6.5
		var base_r := center + dir_vec * (arc_r + 2.5) + perp_vec * 6.5
		draw_colored_polygon(
			PackedVector2Array([base_l, tip, base_r]),
			Color(1.0, 0.22, 0.16, 0.95 * alpha)
		)

	# 2. Отрисовка проактивных шевронов угроз (Incoming Threat Chevrons)
	for threat in _active_threats:
		var az := float(threat["angle"])
		var eta := float(threat["eta"])
		var urgent := bool(threat["urgent"])
		var kind := int(threat["kind"])
		var screen_angle := az - PI * 0.5

		var pulse := 0.5 + 0.5 * sin(_pulse_clock * TAU * (8.5 if urgent else 3.5))
		var rad := CHEVRON_RING_RADIUS + (pulse * 3.5 if urgent else 0.0)
		var scale_f := lerpf(1.22, 0.92, clampf(eta / PROJ_MAX_ETA, 0.0, 1.0))

		var col: Color
		if urgent:
			col = Color(1.0, 0.26, 0.10, 0.98).lerp(Color(1.0, 0.68, 0.22, 1.0), pulse * 0.45)
		elif kind == ThreatKind.GROUND_SLAM:
			col = Color(1.0, 0.48, 0.14, 0.92)
		else:
			col = Color(1.0, 0.78, 0.20, 0.88)

		_draw_chevron(center, screen_angle, rad, 11.0 * scale_f, 9.5 * scale_f, col)
		if urgent:
			# Второй внутренний шеврон — сигнал нажать [E] Block прямо сейчас!
			_draw_chevron(center, screen_angle, rad - 8.5, 8.5 * scale_f, 7.0 * scale_f, Color(1.0, 0.86, 0.58, 0.94))

func _draw_chevron(
	center: Vector2,
	screen_angle: float,
	ring_r: float,
	half_width: float,
	depth: float,
	fill_col: Color
) -> void:
	var dir := Vector2(cos(screen_angle), sin(screen_angle))
	var perp := Vector2(-dir.y, dir.x)

	var tip := center + dir * (ring_r + depth)
	var wing_l := center + dir * ring_r - perp * half_width
	var wing_r := center + dir * ring_r + perp * half_width
	var notch := center + dir * (ring_r + depth * 0.36)

	var pts := PackedVector2Array([wing_l, tip, wing_r, notch])
	var shadow_col := Color(0.03, 0.03, 0.05, fill_col.a * 0.82)

	draw_polyline(
		PackedVector2Array([wing_l, tip, wing_r, notch, wing_l]),
		shadow_col,
		3.6,
		true
	)
	draw_colored_polygon(pts, fill_col)
