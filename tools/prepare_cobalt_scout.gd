extends SceneTree

## Run after importing the GLB: godot --headless --path . --script tools/prepare_cobalt_scout.gd
const SOURCE := "res://assets/tanks/cobalt_scout/CobaltScout_game.glb"
const MODEL_SCALE := 0.44
const GROUND_OFFSET := 0.02618 # Lowest track vertex is -0.0595 in the source.

func _initialize() -> void:
	call_deferred("_prepare")

func _prepare() -> void:
	var source := (load(SOURCE) as PackedScene).instantiate()
	load("res://tools/prepare_track_animation.gd").new().generate(source)
	var model := Node3D.new()
	model.name = "Visuals"
	model.set_script(load("res://tank/tank_appearance.gd"))
	var hull := _part(source, "Hull", "ChassisMesh", model, model)
	hull.position.y = GROUND_OFFSET
	for side in ["L", "R"]:
		var track := _part(source, "Track_" + side, "LeftTrack" if side == "L" else "RightTrack", model, model)
		track.position.y = GROUND_OFFSET
		for index in range(1, 4):
			var wheel_name := "Wheel_%s_%d" % [side, index]
			var original := source.find_child(wheel_name, true, false) as MeshInstance3D
			var wheel := MeshInstance3D.new()
			wheel.name = wheel_name
			wheel.mesh = original.mesh
			track.add_child(wheel)
			wheel.owner = model
			wheel.transform = original.transform
	var turret := Node3D.new()
	turret.name = "TurretMount"
	model.add_child(turret)
	turret.owner = model
	turret.position = Vector3(0, 1.57 * MODEL_SCALE + GROUND_OFFSET, 0.05 * MODEL_SCALE)
	_part(source, "Turret", "TurretMesh", turret, model)
	var barrel := Node3D.new()
	barrel.name = "BarrelMount"
	turret.add_child(barrel)
	barrel.owner = model
	# The exported Gun_Pitch pivot is displaced from the gun geometry.
	# Recenter it at the actual breech before connecting gameplay pitch/recoil.
	barrel.position = Vector3(0, 0.68 * MODEL_SCALE, -0.93 * MODEL_SCALE)
	_part(source, "Gun", "BarrelMesh", barrel, model)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	barrel.add_child(muzzle)
	muzzle.owner = model
	muzzle.position.z = -2.17 * MODEL_SCALE
	var packed := PackedScene.new()
	assert(packed.pack(model) == OK)
	assert(ResourceSaver.save(packed, "res://tank/tank_visuals.tscn") == OK)
	model.free()
	source.free()
	quit()

func _part(source: Node, source_name: String, part_name: String, parent: Node, owner_node: Node) -> MeshInstance3D:
	var original := source.find_child(source_name, true, false) as MeshInstance3D
	assert(original != null, "Missing model part: " + source_name)
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = original.mesh
	parent.add_child(part)
	part.owner = owner_node
	# The GLB faces +Z; gameplay and the cameras use -Z.
	part.rotation.y = PI
	part.scale = Vector3.ONE * MODEL_SCALE
	return part
