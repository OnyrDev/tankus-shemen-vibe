extends Node3D

var failures := 0
var checks := 0
var player: Tank
var camera: Camera3D
const PROJECTILE := preload("res://projectile/projectile.tscn")

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[FAIL] " + label)
	else:
		print("[PASS] " + label)

func _make_tank() -> Tank:
	var tank := (load("res://tank/tank.tscn") as PackedScene).instantiate() as Tank
	add_child(tank)
	tank.set_physics_process(false)
	tank.net_sync.set_physics_process(false)
	tank.net_sync.set_process(false)
	tank.input.enabled = false
	tank.input.set_physics_process(false)
	return tank

func _run() -> void:
	SoundManager._streams.clear()
	player = _make_tank()
	camera = Camera3D.new()
	add_child(camera)
	camera.make_current()
	for map_name in MatchRules.MAP_SCENES:
		await _check_map(map_name)
	await _check_radio_details()
	await _check_tank_armor()
	await _check_embedded_muzzle()
	await _check_grazing_prediction()
	await _check_despawned_shooter()
	print("Aim collision: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _check_map(map_name: String) -> void:
	player.position = Vector3(500, 500, 500)
	var arena := (load(MatchRules.MAP_SCENES[map_name]) as PackedScene).instantiate() as BaseArena
	add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var uncovered := 0
	var target: MeshInstance3D = null
	for node in arena.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or not mesh.is_visible_in_tree():
			continue
		var parent := mesh.get_parent()
		var authored := false
		while parent != arena:
			if parent is CollisionObject3D:
				authored = true
				break
			parent = parent.get_parent()
		if not authored and not mesh.has_node("ShotSurface"):
			uncovered += 1
		var size := mesh.get_aabb().size * mesh.global_basis.get_scale().abs()
		if target == null and size.y > 0.25 and size.length() < 40.0:
			target = mesh
	_check(uncovered == 0, map_name + ": visible scenery has shot collision")
	_check(target != null, map_name + ": physical aim target available")
	if target:
		var faces := target.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a := target.to_global(faces[index])
			var b := target.to_global(faces[index + 1])
			var c := target.to_global(faces[index + 2])
			var normal := (c - a).cross(b - a).normalized()
			if normal.length_squared() < 0.5:
				continue
			var point := (a + b + c) / 3.0
			await _check_aim_and_shot(point + normal * 2.0, point - normal * 2.0, map_name)
			break
	arena.queue_free()
	await get_tree().process_frame

func _check_aim_and_shot(from: Vector3, to: Vector3, label: String) -> void:
	var direction := (to - from).normalized()
	player.global_position = from - direction * 4.0 - Vector3.UP
	player.hitboxes.update_hitboxes()
	camera.global_position = from
	camera.look_at(to, Vector3.FORWARD if absf(direction.y) > 0.95 else Vector3.UP)
	await get_tree().physics_frame
	player.input._update_aim_raycast()
	if player.input.aim_collider == null or player.input.aim_point.distance_to(from) >= from.distance_to(to):
		print("Aim diagnostic %s: from=%s to=%s actual=%s visible=%s ray=%s" % [label, from, to, player.input.aim_point, player.input.aim_collider != null, camera.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)])
	_check(player.input.aim_collider != null and player.input.aim_point.distance_to(from) < from.distance_to(to), label + ": crosshair converges on the surface")
	var projectile := PROJECTILE.instantiate() as Projectile
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.setup(player, from, direction)
	var hits: Array[Object] = []
	projectile.hit_object.connect(func(collider: Object, _point: Vector3, _normal: Vector3): hits.append(collider))
	projectile.speed = 180.0
	projectile.velocity = direction * projectile.speed
	projectile._physics_process(1.0 / 20.0)
	if hits.is_empty() or not projectile._is_destroyed:
		print("Shot diagnostic %s: from=%s to=%s final=%s hits=%s destroyed=%s" % [label, from, to, projectile.global_position, hits, projectile._is_destroyed])
	_check(not hits.is_empty() and projectile._is_destroyed, label + ": fast projectile stops at the surface")
	if not projectile.is_queued_for_deletion():
		projectile.queue_free()
	await get_tree().process_frame

func _check_radio_details() -> void:
	var arena := (load("res://maps/radio_station.tscn") as PackedScene).instantiate() as BaseArena
	add_child(arena)
	await get_tree().physics_frame
	await _check_aim_and_shot(Vector3(-18, 4.1, -20), Vector3(-18, 4.1, -27), "Radio relay panel from screenshot")
	await _check_aim_and_shot(Vector3(-18, 2.0, -20), Vector3(-18, 2.0, -27), "Thin radio mast")
	player.position = Vector3(-18, 0, -20)
	camera.position = Vector3(-18, 3, -17)
	camera.look_at(Vector3(-18, 4.1, -24))
	await get_tree().physics_frame
	player.input._update_aim_raycast()
	player.turret.aim_at(player.input.aim_point, 1.0)
	var prediction := player.weapon.get_predicted_impact()
	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	hud.bind_to_tank(player)
	player.input.set_process(false)
	player.input.enabled = true
	hud._process(0.0)
	_check(hud.impact_marker.visible and not prediction.is_empty(), "Impact ring is visible for an aimed surface")
	if not prediction.is_empty():
		_check(hud._impact_screen_position.distance_to(camera.unproject_position(prediction.position)) < 0.1, "Impact ring projects the muzzle hit onto the HUD")
	player.input.enabled = false
	hud._process(0.0)
	_check(not hud.impact_marker.visible, "Impact ring hides when aiming input is disabled")
	hud.queue_free()
	player.input.set_process(true)
	var shells: Array[Projectile] = []
	player.weapon.shot_fired.connect(func(shell: Projectile):
		shell.set_physics_process(false)
		shells.append(shell), CONNECT_ONE_SHOT)
	player.weapon._spawn_projectile()
	var impacts: Array[Object] = []
	if not shells.is_empty():
		var shell := shells[0]
		shell.hit_object.connect(func(body: Object, _point: Vector3, _normal: Vector3): impacts.append(body))
		for step in range(60):
			if shell._is_destroyed:
				break
			shell._physics_process(1.0 / 60.0)
		shell.queue_free()
	if not impacts.has(arena.get_node("TechnicalDetails/RelayPanel3/PanelMesh/ShotSurface")):
		print("Weapon diagnostic: aim=%s muzzle=%s direction=%s impacts=%s" % [player.input.aim_point, player.turret.get_muzzle_position(), player.turret.get_shoot_direction(), impacts])
		for impact in impacts:
			if impact is Node:
				print("Weapon impact: ", impact.get_path())
	_check(impacts.has(arena.get_node("TechnicalDetails/RelayPanel3/PanelMesh/ShotSurface")), "Actual weapon converges from the muzzle onto the aimed radio panel")
	_check(not prediction.is_empty() and impacts.has(prediction.collider), "Predicted impact matches the actual weapon hit")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(-18, 4.1, -20), Vector3(-18, 4.1, -27), 1)
	_check(get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "New detail surfaces preserve tank movement collision")
	player.position = Vector3(500, 500, 500)
	var projectile := PROJECTILE.instantiate() as Projectile
	projectile.bounces_left = 1
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.setup(null, Vector3(-18, 4.1, -22), Vector3.FORWARD)
	projectile._physics_process(0.15)
	_check(projectile.bounces_done == 1 and projectile.velocity.z > 0 and not projectile._is_destroyed, "Detail surfaces support ricochet cards")
	projectile.queue_free()
	arena.queue_free()
	await get_tree().process_frame

func _check_tank_armor() -> void:
	var target := _make_tank()
	target.position = Vector3.ZERO
	for factor in [0.6, 1.0, 2.0]:
		target.visuals.scale = Vector3.ONE * factor
		target.visuals.rotation.z = 0.1
		target.turret.rotation.y = PI * 0.5
		target.turret.barrel_mount.rotation.x = 0.25
		target.hitboxes.update_hitboxes()
		await get_tree().physics_frame
		await get_tree().physics_frame
		for path in ["TurretMount/TurretMesh", "TurretMount/BarrelMount/BarrelMesh", "LeftTrack"]:
			var mesh := target.visuals.get_node(path) as MeshInstance3D
			var point := mesh.to_global(mesh.get_aabb().get_center())
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 4, point - Vector3.UP * 0.1, ShotGeometry.TANK_LAYER)
			ray.exclude = player.get_shot_collision_rids()
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			_check(not hit.is_empty() and hit.collider == target.hitboxes, "Armor follows %s at scale %.1f" % [path, factor])
	target.visuals.scale = Vector3.ONE
	target.visuals.rotation = Vector3.ZERO
	target.turret.rotation = Vector3.ZERO
	target.turret.barrel_mount.rotation = Vector3.ZERO
	target.hitboxes.update_hitboxes()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var faces := target.turret_mesh.mesh.get_faces()
	var point := Vector3.ZERO
	var normal := Vector3.RIGHT
	for index in range(0, faces.size(), 3):
		var a := target.turret_mesh.to_global(faces[index])
		var b := target.turret_mesh.to_global(faces[index + 1])
		var c := target.turret_mesh.to_global(faces[index + 2])
		var center := (a + b + c) / 3.0
		var outward := (c - a).cross(b - a).normalized()
		if center.y > point.y and absf(outward.y) < 0.5:
			point = center
			normal = outward
	player.position = point + normal * 6.0 - Vector3.UP
	camera.global_position = point + normal * 4.0
	camera.look_at(point)
	await get_tree().physics_frame
	player.input._update_aim_raycast()
	if player.input.aim_collider == null:
		print("Turret aim diagnostic: point=%s actual=%s ray=%s" % [point, player.input.aim_point, camera.project_ray_normal(get_viewport().get_visible_rect().size * 0.5)])
	_check(player.input.aim_collider != null and player.input.aim_point.distance_to(point) < 1.5, "Aim detects the turret above the movement capsule")
	var projectile := PROJECTILE.instantiate() as Projectile
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.setup(player, point + normal * 3.0, -normal)
	projectile.piercing_count = 1
	var hp := target.health.current_health
	for step in range(15):
		projectile._physics_process(1.0 / 60.0)
	_check(is_equal_approx(target.health.current_health, hp - projectile.damage), "Turret hit deals damage once with piercing")
	_check(not projectile._is_destroyed and projectile.piercing_count == 0, "Piercing excludes the target capsule and armor")
	projectile._reflect_projectile(target, Vector3.RIGHT)
	_check(projectile.get_collision_exceptions().has(target.hitboxes), "Reflected shell excludes the reflecting tank armor")
	projectile.queue_free()
	target.is_active = false
	target.hitboxes.update_hitboxes()
	_check(target.hitboxes.collision_layer == 0, "Inactive tanks have no armor collision")
	target.is_active = true
	target.hitboxes.update_hitboxes()
	_check(target.hitboxes.collision_layer == ShotGeometry.TANK_LAYER, "Respawn restores armor collision")
	target.queue_free()
	await get_tree().process_frame

func _check_embedded_muzzle() -> void:
	player.position = Vector3.ZERO
	player.visuals.rotation = Vector3.ZERO
	player.turret.rotation = Vector3.ZERO
	player.turret.barrel_mount.rotation = Vector3.ZERO
	var muzzle := player.turret.get_muzzle_position()
	var barrier := StaticBody3D.new()
	barrier.collision_layer = ShotGeometry.SURFACE_LAYER
	barrier.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.1)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	barrier.add_child(collision)
	add_child(barrier)
	barrier.position = muzzle + Vector3.BACK * 0.3
	await get_tree().physics_frame
	await get_tree().physics_frame
	var prediction := player.weapon.get_predicted_impact()
	_check(not prediction.is_empty() and prediction.collider == barrier, "Impact prediction detects cover between breech and muzzle")
	var hits: Array[Object] = []
	player.weapon.shot_fired.connect(func(shell: Projectile):
		shell.hit_object.connect(func(body: Object, _point: Vector3, _normal: Vector3): hits.append(body)))
	player.weapon._spawn_projectile()
	_check(hits.has(barrier), "A muzzle inside cover cannot fire through it")
	barrier.queue_free()
	await get_tree().process_frame

func _check_grazing_prediction() -> void:
	player.position = Vector3.ZERO
	player.visuals.rotation = Vector3.ZERO
	player.turret.rotation = Vector3.ZERO
	player.turret.barrel_mount.rotation = Vector3.ZERO
	var aim := Vector3(0, 10, -100)
	player.turret.aim_at(aim, 1.0)
	var origin := player.turret.get_muzzle_position()
	var direction := player.turret.get_shoot_direction()
	camera.position = Vector3(0, 2.4, 5)
	camera.look_at(aim)
	player.input.set_process(false)
	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	hud.bind_to_tank(player)
	for edge in [Vector3.UP, Vector3.RIGHT]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var box := BoxShape3D.new()
		box.size = Vector3(4, 2, 0.25)
		var collision := CollisionShape3D.new()
		collision.shape = box
		wall.add_child(collision)
		add_child(wall)
		var half_extent := box.size.y * 0.5 if edge == Vector3.UP else box.size.x * 0.5
		wall.position = origin + direction * 4.0 - edge * (half_extent + 0.1)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var center_ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * 20, ShotGeometry.COLLISION_MASK)
		center_ray.exclude = player.get_shot_collision_rids()
		_check(get_world_3d().direct_space_state.intersect_ray(center_ray).is_empty(), "Grazing %s: center ray clears the wall" % edge)
		var prediction := player.weapon.get_predicted_impact()
		_check(not prediction.is_empty() and prediction.collider == wall, "Grazing %s: prediction detects shell radius hitting the wall" % edge)
		player.input.enabled = true
		hud._process(0.0)
		_check(hud.impact_marker.visible, "Grazing %s: red impact circle stays visible" % edge)
		player.input.enabled = false
		var projectile := PROJECTILE.instantiate() as Projectile
		add_child(projectile)
		projectile.set_physics_process(false)
		projectile.setup(player, origin, direction)
		var hits: Array[Object] = []
		var points: Array[Vector3] = []
		projectile.hit_object.connect(func(body: Object, point: Vector3, _normal: Vector3):
			hits.append(body)
			points.append(point))
		for step in range(30):
			if projectile._is_destroyed:
				break
			projectile._physics_process(1.0 / 60.0)
		_check(hits.has(wall), "Grazing %s: actual shell hits the wall" % edge)
		_check(not prediction.is_empty() and not points.is_empty() and prediction.position.distance_to(points[0]) < 0.05, "Grazing %s: marker matches actual contact point" % edge)
		projectile.queue_free()
		wall.queue_free()
		await get_tree().process_frame
	hud.queue_free()
	player.input.set_process(true)
	await get_tree().process_frame

func _check_despawned_shooter() -> void:
	var shooter := _make_tank()
	shooter.position = Vector3(100, 100, 100)
	var projectile := PROJECTILE.instantiate() as Projectile
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.setup(shooter, shooter.position + Vector3.FORWARD * 3.0, Vector3.FORWARD)
	shooter.queue_free()
	await get_tree().process_frame
	var start := projectile.global_position
	projectile._physics_process(1.0 / 60.0)
	_check(projectile.global_position.distance_to(start) > 0.1 and not projectile._is_destroyed, "Shots keep flying after their shooter despawns")
	projectile.queue_free()
	await get_tree().process_frame
