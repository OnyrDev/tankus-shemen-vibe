extends Node3D

## Физические и интеграционные тесты карты Dust I (de_dust).
var failures := 0
var arena: BaseArena
var tank: Tank

const ORIGIN := Vector3(-73.0, 0.0, -45.0)

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	SoundManager._streams.clear()
	arena = (load("res://maps/de_dust.tscn") as PackedScene).instantiate() as BaseArena
	add_child(arena)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(arena.get_spawn_points().size() == 8, "Eight usable spawn markers on Dust I")
	_check(get_tree().get_nodes_in_group("de_dust_ramps").size() == 9, "Nine smooth tank ramp colliders")
	_check(arena.kill_volume != null and arena.kill_volume.collision_mask == 2, "Fall volume detects tanks")

	var space := get_world_3d().direct_space_state
	for point in arena.get_spawn_points():
		var ray := PhysicsRayQueryParameters3D.create(point.global_position + Vector3.UP * 3.0, point.global_position - Vector3.UP * 3.0, 1)
		var hit := space.intersect_ray(ray)
		_check(not hit.is_empty() and hit.normal.y > 0.7, point.name + " sits above clear walkable floor")

		var shape := CylinderShape3D.new()
		shape.radius = 1.5
		shape.height = 2.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = point.global_position + Vector3.UP * 1.1
		query.collision_mask = 1
		_check(space.intersect_shape(query).is_empty(), point.name + " clears a maximum-size tank")

	# Проверяем, что двойные ворота (Double Doors на X=83.2, Z=28.6) распахнуты и проём свободен:
	var gate_start := ORIGIN + Vector3(83.2, 4.6, 22.0)
	var gate_end := ORIGIN + Vector3(83.2, 4.6, 35.0)
	var gate_ray := PhysicsRayQueryParameters3D.create(gate_start, gate_end, 1)
	_check(space.intersect_ray(gate_ray).is_empty(), "Double doors gateway is open and clear for tanks")

	tank = (load("res://tank/tank.tscn") as PackedScene).instantiate() as Tank
	add_child(tank)
	tank.set_physics_process(false)
	tank.net_sync.set_physics_process(false)
	tank.net_sync.set_process(false)
	tank.input.enabled = false
	tank.input.set_physics_process(false)

	for scale_value in [1.0, 2.0]:
		tank.get_node("CollisionShape3D").scale = Vector3.ONE * scale_value
		await _drive_path(Vector2(14.35, 10.5), Vector2(14.35, 25.0), 0.5, 3.0, scale_value, "WestStairs uphill")
		await _drive_path(Vector2(83.2, 22.0), Vector2(83.2, 35.0), 3.8, 3.0, scale_value, "DoubleDoors passage")

	var fell := [false]
	arena.tank_fell.connect(func(_body: Tank) -> void: fell[0] = true)
	tank.position = Vector3(0.0, -9.5, 0.0)
	for frame in range(4):
		await get_tree().physics_frame
	_check(fell[0], "Fall volume emits tank_fell signal")

	tank.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	await _check_integration()
	print("Dust I: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _drive_path(from2: Vector2, to2: Vector2, start_y: float, min_end_y: float, scale_value: float, label: String) -> void:
	var dir2 := (to2 - from2).normalized()
	var direction := Vector3(dir2.x, 0.0, dir2.y)
	tank.position = ORIGIN + Vector3(from2.x, start_y + 1.0, from2.y)
	tank.velocity = Vector3.ZERO
	tank.input.move_direction_world = Vector3.ZERO
	for frame in range(30):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
	tank.input.move_direction_world = direction
	var target_world := ORIGIN + Vector3(to2.x, min_end_y, to2.y)
	var arrived := false
	for frame in range(180):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
		var horiz_dist := Vector2(tank.position.x - target_world.x, tank.position.z - target_world.z).length()
		if horiz_dist < 2.2 and tank.position.y >= min_end_y:
			arrived = true
			break
	_check(arrived, "%s scale %.1f reaches target (pos=%s)" % [label, scale_value, str(tank.position - ORIGIN)])

func _check_integration() -> void:
	_check(MainMenu.MAP_INFO.has("de_dust"), "Dust I appears in main menu catalogue")
	_check(MatchRules.MAP_SCENES.has("de_dust"), "Dust I participates in map rotation")
	var practice := (load("res://maps/de_dust_practice.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(practice)
	await get_tree().physics_frame
	_check(practice.current_arena != null and Game.rules.selected_map == "de_dust", "Practice entry loads Dust I")
	_check(practice.match_controller.spawn_points_container == practice.current_arena.spawn_points_container, "Match controller uses Dust I spawns")
	practice.queue_free()
	await get_tree().process_frame
