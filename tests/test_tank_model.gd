extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures += 1
		push_error(label)

func _run() -> void:
	var scene := load("res://tank/tank.tscn") as PackedScene
	var tank := scene.instantiate() as Tank
	var other := scene.instantiate() as Tank
	get_tree().root.add_child(tank)
	get_tree().root.add_child(other)
	tank.is_frozen = true
	other.is_frozen = true
	_check(tank.chassis_mesh.mesh is ArrayMesh, "Imported hull replaces primitive geometry")
	_check(tank.visuals.find_children("Wheel_*", "MeshInstance3D", true, false).size() == 6, "All six wheels are present")
	_check(is_equal_approx(tank.left_track.position.y + tank.left_track.get_aabb().position.y * tank.left_track.scale.y, 0.0), "Tracks sit on the ground")
	_check(tank.turret.barrel_mount.position.y > 0.0, "Gun pitch pivot sits above turret ring")
	var muzzle := tank.turret.get_muzzle_position()
	var gun := tank.turret.barrel_mount.get_node("BarrelMesh") as MeshInstance3D
	var gun_tip := gun.to_global(Vector3(0, 0, gun.get_aabb().end.z))
	_check(muzzle.z < 0.0 and muzzle.distance_to(gun_tip) < 0.02, "Muzzle matches the visible barrel tip and faces forward")
	var material := tank.chassis_mesh.mesh.surface_get_material(2)
	tank.set_team_color(Color.RED)
	other.set_team_color(Color.GREEN)
	_check((tank.chassis_mesh.get_surface_override_material(1) as StandardMaterial3D).albedo_color == Color.RED, "Armor receives team color")
	_check((other.chassis_mesh.get_surface_override_material(1) as StandardMaterial3D).albedo_color == Color.GREEN, "Team materials are independent between tanks")
	_check(tank.chassis_mesh.get_active_material(2) == material, "Gunmetal keeps the original material")
	var rest_scale := tank.chassis_mesh.scale
	var rest_height := tank.turret.position.y
	tank.controller._update_chassis_tilt(0.016)
	_check(tank.chassis_mesh.scale.is_equal_approx(rest_scale), "Suspension preserves imported model scale")
	_check(is_equal_approx(tank.turret.position.y, rest_height), "Suspension preserves turret mounting height")
	tank.controller.update_tilt_only(0.016)
	_check(tank.chassis_mesh.scale.is_equal_approx(rest_scale) and tank.left_track.scale.is_equal_approx(rest_scale) and tank.right_track.scale.is_equal_approx(rest_scale), "Frozen slope alignment preserves model scale")
	_check(is_equal_approx(tank.turret.position.y, rest_height), "Frozen slope alignment preserves turret mounting height")
	tank.turret.aim_at(Vector3(8, 3, -8), 0.2)
	_check(tank.turret.rotation.y < 0 and tank.turret.barrel_mount.rotation.x > 0, "Turret yaw and gun elevation follow aiming")
	tank.health._play_hit_flash()
	_check(gun.material_override != null, "Damage flash covers the imported gun")
	await tank.health._hit_flash_tween.finished
	_check(gun.material_override == null and tank.chassis_mesh.get_active_material(2) == material, "Damage flash restores detailed materials")
	tank.free()
	other.free()
	print("Tank model checks: %d failed" % failures)
	get_tree().quit(1 if failures else 0)
