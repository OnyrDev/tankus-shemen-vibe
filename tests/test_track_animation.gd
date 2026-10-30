extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print(("[PASS] " if ok else "[FAIL] ") + label)
	if not ok:
		failures += 1

func _make_tank() -> Tank:
	var tank := (load("res://tank/tank.tscn") as PackedScene).instantiate() as Tank
	add_child(tank)
	tank.set_physics_process(false)
	tank.net_sync.set_process(false)
	tank.net_sync.set_physics_process(false)
	tank.input.set_process(false)
	tank.input.set_physics_process(false)
	return tank

func _run() -> void:
	var tank := _make_tank()
	var other := _make_tank()
	var tracks = tank.visuals.get_node("TrackAnimation")
	var other_tracks = other.visuals.get_node("TrackAnimation")
	tracks.set_process(false)
	other_tracks.set_process(false)
	_check(tracks._wheels[0].size() == 3 and tracks._wheels[1].size() == 3, "All six wheels participate in animation")
	tracks.advance_motion(0.22, 0.0)
	_check(is_equal_approx(tracks.belt_distances[0], 0.5) and is_equal_approx(tracks.belt_distances[1], 0.5), "Forward travel drives both belts equally in model units")
	var wheel := tank.left_track.get_node("Wheel_L_1") as Node3D
	_check(not wheel.rotation.is_zero_approx(), "Road wheels rotate about their axle")
	_check(tracks._wheels[0][1].angle > tracks._wheels[0][0].angle, "Smaller middle wheels turn faster for the same belt travel")
	tracks.advance_motion(-0.22, 0.0)
	_check(is_zero_approx(tracks.belt_distances[0]) and is_zero_approx(tracks.belt_distances[1]) and wheel.rotation.is_zero_approx(), "Reverse motion unwinds belt and wheel rotation")
	tracks.advance_motion(0.0, 0.2)
	var left_turn := wrapf(tracks.belt_distances[0], -tracks.LOOP_LENGTH * 0.5, tracks.LOOP_LENGTH * 0.5)
	var right_turn := wrapf(tracks.belt_distances[1], -tracks.LOOP_LENGTH * 0.5, tracks.LOOP_LENGTH * 0.5)
	_check(left_turn * right_turn < 0.0 and is_equal_approx(absf(left_turn), absf(right_turn)), "Turning in place drives the physical sides in opposite directions")
	_check(other_tracks.belt_distances == [0.0, 0.0], "Different tanks have independent belt phases")
	var material := tank.left_track.get_surface_override_material(0) as ShaderMaterial
	_check(material != other.left_track.get_surface_override_material(0), "Shader uniforms are isolated per tank")
	tank.set_team_color(Color.RED)
	_check(tank.left_track.get_surface_override_material(0) == material, "Team recoloring keeps animated track materials")
	tank.health._play_hit_flash()
	await tank.health._hit_flash_tween.finished
	_check(tank.left_track.material_override == null and tank.left_track.get_surface_override_material(0) == material, "Damage flash restores animated belts")
	var previous: Array = tracks.belt_distances.duplicate()
	tank.global_position.z -= 0.1
	tracks._process(0.016)
	_check(tracks.belt_distances != previous, "Position changes animate remote tanks even with zero velocity")
	previous = tracks.belt_distances.duplicate()
	tank.velocity = Vector3.FORWARD * 8
	tracks._process(0.016)
	_check(tracks.belt_distances == previous, "A blocked stationary tank does not spin from velocity alone")
	tank.global_position.x += 0.1
	tracks._process(0.016)
	_check(tracks.belt_distances == previous, "Pure lateral sliding does not roll tracks forward")
	tank.global_position += Vector3(20, 0, 20)
	tracks._process(0.016)
	_check(tracks.belt_distances == previous, "Respawn teleports do not spin the belts")
	tank.is_frozen = true
	tank.global_position.z -= 0.1
	tracks._process(0.016)
	_check(tracks.belt_distances == previous, "Frozen tanks keep their tracks still")
	tank.is_frozen = false
	tank.is_active = false
	tank.global_position.z -= 0.1
	tracks._process(0.016)
	_check(tracks.belt_distances == previous, "Destroyed tanks stop track animation")
	var showroom := (load("res://tank/tank_visuals.tscn") as PackedScene).instantiate() as Node3D
	add_child(showroom)
	_check(not showroom.get_node("TrackAnimation").is_processing(), "Lobby and menu showroom models remain stationary")
	# Verify the tagged mesh keeps its backing still and pairs pads with metal shoes.
	for side in range(2):
		var mesh: Mesh = tracks._tracks[side].mesh
		var backing_vertices := 0
		var phase_sets: Array[Dictionary] = []
		for surface in range(mesh.get_surface_count()):
			var phases := {}
			var uv2: PackedVector2Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV2]
			for tag in uv2:
				if tag.y < 0.5:
					backing_vertices += 1
				else:
					phases[snappedf(tag.x, 0.01)] = true
			phase_sets.append(phases)
		_check(backing_vertices > 0 and phase_sets[0].size() == 36 and phase_sets[1].size() == 36, "Side %d: 36 rigid links move around a stationary backing" % side)
		_check(phase_sets[0] == phase_sets[1], "Side %d: rubber pads and metal shoes share the same phases" % side)
	showroom.free()
	tank.free()
	other.free()
	print("Track animation checks: %d failed" % failures)
	get_tree().quit(1 if failures else 0)
