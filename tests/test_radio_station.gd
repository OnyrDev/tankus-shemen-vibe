extends Node3D

## Physical regression checks for the authored map, including large tank builds.
var failures := 0
var arena: BaseArena
var tank: Tank

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	# Fast fixed-FPS physics tests do not exercise the real-time audio mixer.
	# Avoid accumulating landing playbacks while simulating hundreds of frames.
	SoundManager._streams.clear()
	arena = (load("res://maps/radio_station.tscn") as PackedScene).instantiate() as BaseArena
	add_child(arena)
	await get_tree().physics_frame
	_check(arena.get_spawn_points().size() == 8, "Eight usable spawn markers")
	_check(get_tree().get_nodes_in_group("radio_ramps").size() == 2, "Two offset service terrace ramps")
	_check(arena.kill_volume != null and arena.kill_volume.collision_mask == 2, "Fall volume detects tanks")
	var space := get_world_3d().direct_space_state
	for point in arena.get_spawn_points():
		var ray := PhysicsRayQueryParameters3D.create(point.global_position + Vector3.UP * 3, point.global_position - Vector3.UP * 2, 1)
		var hit := space.intersect_ray(ray)
		_check(not hit.is_empty() and absf(hit.position.y) < 0.05, point.name + " sits above clear courtyard floor")
		var shape := CylinderShape3D.new()
		shape.radius = 1.5
		shape.height = 2.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = point.global_position + Vector3.UP
		query.collision_mask = 1
		_check(space.intersect_shape(query).is_empty(), point.name + " clears a maximum-size tank")
	tank = (load("res://tank/tank.tscn") as PackedScene).instantiate() as Tank
	add_child(tank)
	tank.set_physics_process(false)
	tank.net_sync.set_physics_process(false)
	tank.net_sync.set_process(false)
	tank.input.enabled = false
	tank.input.set_physics_process(false)
	var ramps: Array[Array] = [
		[Vector2(16, 16), Vector2(24, 16)], [Vector2(44, 32), Vector2(36, 32)]]
	for scale_value in [1.0, 2.0]:
		tank.get_node("CollisionShape3D").scale = Vector3.ONE * scale_value
		for index in range(ramps.size()):
			await _drive_ramp(ramps[index][0], ramps[index][1], index, scale_value, true)
			await _drive_ramp(ramps[index][0], ramps[index][1], index, scale_value, false)
	for scale_value in [1.0, 2.0]:
		tank.get_node("CollisionShape3D").scale = Vector3.ONE * scale_value
		await _drive_lane(Vector2(21,10), Vector2(39,10), 0.0, "North bypass", scale_value)
		await _drive_lane(Vector2(39,38), Vector2(21,38), 0.0, "South bypass", scale_value)
		await _drive_lane(Vector2(26,14.5), Vector2(26,33.5), 3.0, "West antenna aisle", scale_value)
		await _drive_lane(Vector2(34,33.5), Vector2(34,14.5), 3.0, "East antenna aisle", scale_value)
	# The low antenna base is solid cover above the service terrace.
	var bowl_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-8, 4.3, 0.5), Vector3(8, 4.3, 0.5), 1))
	_check(not bowl_hit.is_empty(), "Central antenna equipment blocks weapon-height shots")
	var fell := [false]
	arena.tank_fell.connect(func(_body: Tank): fell[0] = true)
	tank.position = Vector3(65, -6, 0)
	for frame in range(4):
		await get_tree().physics_frame
	_check(fell[0], "Fall volume emits the existing arena signal")
	tank.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	await _check_integration()
	print("Radio Station: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _check_integration() -> void:
	_check(MainMenu.MAP_INFO.has("radio_station"), "Map appears in main menu catalogue")
	var practice := (load("res://maps/radio_station_practice.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(practice)
	await get_tree().physics_frame
	_check(practice.current_arena != null and Game.rules.selected_map == "radio_station", "F6 practice entry loads Radio Station")
	_check(practice.match_controller.spawn_points_container == practice.current_arena.spawn_points_container, "Match controller uses the new arena spawns")
	var map_index := Lobby.MAP_NAMES.find("radio_station")
	_check(map_index >= 0 and practice.lobby.opt_map.item_count > map_index, "In-game lobby offers the new map")
	practice.queue_free()
	await get_tree().process_frame
	var screen := (load("res://lobby/lobby_screen.tscn") as PackedScene).instantiate() as LobbyScreen
	add_child(screen)
	map_index = LobbyScreen.MAP_NAMES.find("radio_station")
	_check(map_index >= 0 and screen.opt_map.item_count > map_index, "Standalone LAN lobby offers the new map")
	screen.queue_free()
	await get_tree().process_frame

func _drive_ramp(low: Vector2, high: Vector2, index: int, scale_value: float, uphill: bool) -> void:
	var dir2 := (high - low).normalized()
	var direction := Vector3(dir2.x, 0, dir2.y)
	var start2 := low - dir2 * 2.0 if uphill else high + dir2 * 2.0
	tank.position = Vector3(start2.x - 30, 1.5 if uphill else 4.5, start2.y - 24)
	tank.velocity = Vector3.ZERO
	tank.input.move_direction_world = Vector3.ZERO
	for frame in range(35):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
	var start := tank.position
	tank.input.move_direction_world = direction if uphill else -direction
	var arrived := false
	for frame in range(180):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
		var distance := (tank.position - start).dot(direction if uphill else -direction)
		if distance > 11.0:
			arrived = true
			break
	_check(arrived and (tank.position.y > 2.8 if uphill else tank.position.y < 1.2), "Ramp %d %s, tank scale %.1f" % [index + 1, "up" if uphill else "down", scale_value])


func _drive_lane(from: Vector2, to: Vector2, floor_y: float, label: String, scale_value: float) -> void:
	tank.position = Vector3(from.x - 30, floor_y + 1.5, from.y - 24)
	tank.velocity = Vector3.ZERO
	tank.input.move_direction_world = Vector3.ZERO
	for frame in range(35):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
	var dir := (to-from).normalized()
	tank.input.move_direction_world = Vector3(dir.x, 0, dir.y)
	var target := Vector3(to.x-30, floor_y, to.y-24)
	var arrived := false
	for frame in range(240):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
		if Vector2(tank.position.x-target.x, tank.position.z-target.z).length() < 0.5:
			arrived = true
			break
	_check(arrived and absf(tank.position.y-floor_y) < 1.0, "%s stays accessible at scale %.1f" % [label,scale_value])
