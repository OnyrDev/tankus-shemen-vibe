extends SceneTree

## Импортирует и адаптирует оригинальную геометрию CS 1.6 de_dust
## (res://assets/props/counter_strike_de_dust_1_map.glb) в полноценную
## танковую арену TANKUS (res://maps/de_dust.tscn).
## Запускается через: godot --headless --path . --script tools/build_de_dust.gd

const SOURCE_GLB := "res://assets/props/counter_strike_de_dust_1_map.glb"
const OUTPUT := "res://maps/de_dust.tscn"
const ORIGIN := Vector3(-73.0, 0.0, -45.0)

const STAIR_MESH_NAMES: Array[String] = [
	"Stairs_standardSurface12_0",
	"pCube57_standardSurface12_0",
	"pCube58_standardSurface12_0",
	"pCube59_standardSurface12_0",
	"pCube63_standardSurface12_0",
	"pCube90_standardSurface12_0",
	"pCube92_standardSurface12_0",
	"pCube93_standardSurface12_0",
	"pCube131_standardSurface12_0",
	"pCube154_standardSurface12_0",
	"pCube157_standardSurface12_0",
	"pCube165_standardSurface12_0"
]

const FLOOR_MESH_NAMES: Array[String] = [
	"base_standardSurface12_0",
	"pCube8_standardSurface12_0",
	"pCube24_standardSurface12_0",
	"pCube25_standardSurface12_0",
	"pCube26_standardSurface12_0",
	"pCube34_standardSurface12_0",
	"pCube56_standardSurface12_0",
	"pCube62_standardSurface12_0",
	"Cube19_standardSurface12_0",
	"pCube102_standardSurface12_0",
	"pCube132_standardSurface12_0",
	"pCube153_standardSurface12_0",
	"pCube155_standardSurface12_0",
	"pCube159_standardSurface12_0",
	"pCube160_standardSurface12_0"
]

var arena: Node3D
var floors_group: Node3D
var walls_group: Node3D
var arches_group: Node3D
var crates_group: Node3D
var ramps_group: Node3D
var backdrop_group: Node3D
var mats: Dictionary = {}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var source_packed := load(SOURCE_GLB) as PackedScene
	if not source_packed:
		push_error("Cannot load source GLB: " + SOURCE_GLB)
		quit(1)
		return

	arena = Node3D.new()
	arena.name = "DeDust"
	arena.set_script(load("res://maps/base_arena.gd"))
	arena.set("arena_name", "Dust I — Песчаный рубеж")

	_materials()
	floors_group = _group("FloorsAndTerrain", arena)
	walls_group = _group("WallsAndBuildings", arena)
	arches_group = _group("ArchesAndPillars", arena)
	crates_group = _group("CratesAndCover", arena)
	ramps_group = _group("TankRamps", arena)
	backdrop_group = _group("DesertBackdrop", arena)

	_environment()
	_import_and_adapt_glb(source_packed)
	_build_tank_ramps()
	_build_desert_backdrop()
	_spawns_and_kill_volume()

	var packed := PackedScene.new()
	var error := packed.pack(arena)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	if error != OK:
		push_error("Cannot save Dust I arena: " + error_string(error))
		arena.free()
		quit(1)
		return

	arena.free()
	print("Dust I arena built successfully: " + OUTPUT)
	quit(0)

func _mat(key: String, color: Color, roughness: float = 0.82, metallic: float = 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	mats[key] = m

func _materials() -> void:
	var lower_sand := ShaderMaterial.new()
	lower_sand.resource_name = "Dust Lower Sandstone Paving"
	lower_sand.shader = load("res://maps/materials/dust_sandstone.gdshader")
	lower_sand.set_shader_parameter("stone", Color("d4b689"))
	lower_sand.set_shader_parameter("grout", Color("9e8156"))
	lower_sand.set_shader_parameter("tile_size", 2.6)
	mats["LowerFloor"] = lower_sand

	var upper_sand := ShaderMaterial.new()
	upper_sand.resource_name = "Dust Courtyard Sandstone"
	upper_sand.shader = load("res://maps/materials/dust_sandstone.gdshader")
	upper_sand.set_shader_parameter("stone", Color("e2c89d"))
	upper_sand.set_shader_parameter("grout", Color("b39568"))
	upper_sand.set_shader_parameter("tile_size", 2.2)
	mats["UpperFloor"] = upper_sand

	_mat("AdobeWall", Color("d7b98e"), 0.85)
	_mat("SandstoneArch", Color("c49764"), 0.78)
	_mat("DarkPillar", Color("b08354"), 0.82)
	_mat("StepStone", Color("cca574"), 0.80)
	_mat("MilitaryCrate", Color("6b7450"), 0.70, 0.08)
	_mat("SupplyCrate", Color("ba874d"), 0.74, 0.04)
	_mat("CedarDoor", Color("5c3b23"), 0.78, 0.05)
	_mat("DesertHorizon", Color("d9be93"), 0.95)
	_mat("DesertMesa", Color("bf986b"), 0.92)

func _add(node: Node, parent: Node, label: String) -> void:
	node.name = label
	parent.add_child(node, true)
	node.owner = arena

func _group(label: String, parent: Node) -> Node3D:
	var g := Node3D.new()
	_add(g, parent, label)
	return g

func _pos(x: float, y: float, z: float) -> Vector3:
	return ORIGIN + Vector3(x, y, z)

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3b78b8")
	sky_mat.sky_horizon_color = Color("ebd5b3")
	sky_mat.ground_horizon_color = Color("dec299")
	sky_mat.ground_bottom_color = Color("9c7c54")

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f0dcc0")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.25

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(world_env, arena, "WorldEnvironment")

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_add(sun, arena, "DirectionalLight3D")

func _import_and_adapt_glb(source_packed: PackedScene) -> void:
	var src_root := source_packed.instantiate() as Node3D
	get_root().add_child(src_root)
	var src_meshes: Array[MeshInstance3D] = []
	_collect_meshes(src_root, src_meshes)

	for i in range(src_meshes.size()):
		var m := src_meshes[i]
		if not m.mesh or m.mesh.get_surface_count() == 0:
			continue

		var mname := String(m.name)
		var extra_xf := Transform3D.IDENTITY

		# Адаптация двойных ворот (Double Doors на выходе к Bombsite A / Mid):
		# Распахиваем обе створки вокруг их внешних петель, чтобы танки (включая 2x размер)
		# свободно проезжали через культовый проём, сохраняя сами ворота в кадре.
		if mname == "pCube127_standardSurface12_0":
			var hinge_l := Vector3(79.04, 0.0, 28.10)
			extra_xf = Transform3D().translated(hinge_l) * Transform3D(Basis(Vector3.UP, deg_to_rad(-75.0)), Vector3.ZERO) * Transform3D().translated(-hinge_l)
		elif mname == "pCube128_standardSurface12_0":
			var hinge_r := Vector3(87.38, 0.0, 29.20)
			extra_xf = Transform3D().translated(hinge_r) * Transform3D(Basis(Vector3.UP, deg_to_rad(75.0)), Vector3.ZERO) * Transform3D().translated(-hinge_r)

		var world_xf := Transform3D(Basis.IDENTITY, ORIGIN) * extra_xf * m.global_transform
		var baked_info := _bake_transformed_mesh(m.mesh, world_xf)
		var baked_mesh: ArrayMesh = baked_info["mesh"]
		var center: Vector3 = baked_info["center"]
		var size: Vector3 = baked_info["size"]
		var vcount: int = baked_info["vertex_count"]

		var role := _classify_mesh(mname, size, vcount)
		var parent_group: Node3D = walls_group
		var mat_key := "AdobeWall"
		var build_trimesh_collider := true

		match role:
			"lower_floor":
				parent_group = floors_group
				mat_key = "LowerFloor"
			"upper_floor":
				parent_group = floors_group
				mat_key = "UpperFloor"
			"stairs":
				parent_group = ramps_group
				mat_key = "StepStone"
				# Для ступенчатых лестниц визуал оставляем оригинальным,
				# а физическую коллизию заменяем гладкими пандусами в _build_tank_ramps().
				build_trimesh_collider = false
			"door":
				parent_group = arches_group
				mat_key = "CedarDoor"
			"pillar":
				parent_group = arches_group
				mat_key = "DarkPillar"
			"arch":
				parent_group = arches_group
				mat_key = "SandstoneArch"
			"military_crate":
				parent_group = crates_group
				mat_key = "MilitaryCrate"
			"supply_crate":
				parent_group = crates_group
				mat_key = "SupplyCrate"
			_:
				parent_group = walls_group
				mat_key = "AdobeWall"

		var clean_label := mname.replace("_standardSurface12_0", "")
		if build_trimesh_collider:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.position = center
			_add(body, parent_group, clean_label)

			var mi := MeshInstance3D.new()
			mi.mesh = baked_mesh
			mi.material_override = mats[mat_key]
			_add(mi, body, "Mesh")

			var col := CollisionShape3D.new()
			col.shape = baked_mesh.create_trimesh_shape()
			_add(col, body, "CollisionShape3D")
		else:
			var holder := Node3D.new()
			holder.position = center
			_add(holder, parent_group, clean_label)

			var mi := MeshInstance3D.new()
			mi.mesh = baked_mesh
			mi.material_override = mats[mat_key]
			_add(mi, holder, "Mesh")

	get_root().remove_child(src_root)
	src_root.free()

func _classify_mesh(mname: String, size: Vector3, vcount: int) -> String:
	if mname == "base_standardSurface12_0" or mname == "pCube26_standardSurface12_0" or mname == "Cube19_standardSurface12_0":
		return "lower_floor"
	if mname in FLOOR_MESH_NAMES:
		return "upper_floor"
	if mname in STAIR_MESH_NAMES:
		return "stairs"
	if mname in ["pCube127_standardSurface12_0", "pCube128_standardSurface12_0"]:
		return "door"
	if (size.x < 0.35 or size.z < 0.35) and size.y > 3.0 and vcount == 24:
		return "door"
	if vcount == 24 and size.x < 3.8 and size.z < 3.8 and size.y < 2.8:
		if size.y >= 1.9:
			return "military_crate"
		return "supply_crate"
	if vcount == 40 and size.y >= 6.0 and size.x < 10.5 and size.z < 10.5:
		return "pillar"
	if mname.begins_with("polySurface"):
		return "arch"
	return "wall"

func _bake_transformed_mesh(src_mesh: Mesh, world_xf: Transform3D) -> Dictionary:
	var arrays := src_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var vmin := Vector3(INF, INF, INF)
	var vmax := Vector3(-INF, -INF, -INF)
	var w_verts := PackedVector3Array()
	w_verts.resize(verts.size())

	for i in range(verts.size()):
		var wv := world_xf * verts[i]
		w_verts[i] = wv
		vmin = vmin.min(wv)
		vmax = vmax.max(wv)

	var center := (vmin + vmax) * 0.5
	var size := vmax - vmin
	for i in range(w_verts.size()):
		w_verts[i] -= center

	var normal_basis := world_xf.basis.inverse().transposed()
	var w_norms := PackedVector3Array()
	if norms.size() == verts.size():
		w_norms.resize(norms.size())
		for i in range(norms.size()):
			w_norms[i] = (normal_basis * norms[i]).normalized()

	var flip_winding := world_xf.basis.determinant() < 0.0
	var out_indices := PackedInt32Array()
	if indices.size() > 0:
		out_indices.resize(indices.size())
		for i in range(0, indices.size(), 3):
			out_indices[i] = indices[i]
			if flip_winding:
				out_indices[i + 1] = indices[i + 2]
				out_indices[i + 2] = indices[i + 1]
			else:
				out_indices[i + 1] = indices[i + 1]
				out_indices[i + 2] = indices[i + 2]

	var new_arrays := []
	new_arrays.resize(Mesh.ARRAY_MAX)
	new_arrays[Mesh.ARRAY_VERTEX] = w_verts
	if w_norms.size() > 0:
		new_arrays[Mesh.ARRAY_NORMAL] = w_norms
	if uvs.size() == verts.size():
		new_arrays[Mesh.ARRAY_TEX_UV] = uvs
	if out_indices.size() > 0:
		new_arrays[Mesh.ARRAY_INDEX] = out_indices

	var out_mesh := ArrayMesh.new()
	out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
	return {
		"mesh": out_mesh,
		"center": center,
		"size": size,
		"vertex_count": verts.size()
	}

func _build_tank_ramps() -> void:
	# Гладкие физические пандусы поверх всех 9 ступенчатых лестниц карты:
	# позволяют танкам (1x и 2x) плавно заезжать на все террасы и в коридоры.
	_add_ramp_collider("WestStairsRamp", Vector2(14.35, 12.50), Vector2(14.35, 22.78), 7.80, 0.01, 3.29)
	_add_ramp_collider("BombsiteBStepRamp", Vector2(-4.40, 51.45), Vector2(-6.58, 51.45), 5.15, 3.27, 4.01)
	_add_ramp_collider("SouthAlleyStepRamp", Vector2(14.00, 89.50), Vector2(14.00, 91.67), 3.78, 2.45, 3.27)
	_add_ramp_collider("THallsWestStepRamp", Vector2(39.10, 51.32), Vector2(41.35, 51.32), 5.84, 3.27, 3.78)
	_add_ramp_collider("THallsSouthStepRamp", Vector2(60.25, 76.10), Vector2(60.25, 73.93), 3.80, 3.27, 3.78)
	_add_ramp_collider("THallsNorthStepRamp", Vector2(65.90, 8.60), Vector2(65.90, 10.80), 4.40, 3.27, 3.78)
	_add_ramp_collider("BombsiteAStepRamp", Vector2(68.63, -0.80), Vector2(68.63, -3.02), 3.40, 3.27, 3.78)
	_add_ramp_collider("BridgeStepRamp", Vector2(93.92, 70.80), Vector2(93.92, 73.03), 10.95, 3.27, 3.78)
	_add_ramp_collider("TSpawnStepRamp", Vector2(139.80, 72.20), Vector2(142.20, 72.20), 6.33, 3.27, 4.16)

func _add_ramp_collider(label: String, low: Vector2, high: Vector2, width: float, y_low: float, y_high: float) -> void:
	var dir2 := (high - low).normalized()
	var side2 := Vector2(dir2.y, -dir2.x) * (width * 0.5)
	var a := _pos(low.x - side2.x, y_low, low.y - side2.y)
	var b := _pos(low.x + side2.x, y_low, low.y + side2.y)
	var c := _pos(high.x + side2.x, y_high, high.y + side2.y)
	var d := _pos(high.x - side2.x, y_high, high.y - side2.y)
	var e := _pos(high.x + side2.x, y_low, high.y + side2.y)
	var f := _pos(high.x - side2.x, y_low, high.y - side2.y)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("de_dust_ramps", true)
	_add(body, ramps_group, label)

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, e, f])
	var col := CollisionShape3D.new()
	col.shape = shape
	_add(col, body, "CollisionShape3D")

func _build_desert_backdrop() -> void:
	var horizon_mesh := BoxMesh.new()
	horizon_mesh.size = Vector3(1600.0, 0.2, 1600.0)
	var horizon := MeshInstance3D.new()
	horizon.mesh = horizon_mesh
	horizon.material_override = mats["DesertHorizon"]
	horizon.position = Vector3(0.0, -0.12, 0.0)
	_add(horizon, backdrop_group, "DesertHorizon")

	var rng := RandomNumberGenerator.new()
	rng.seed = 16016
	for i in range(16):
		var angle := float(i) * TAU / 16.0
		var dist := rng.randf_range(190.0, 290.0)
		var mesa_mesh := CylinderMesh.new()
		mesa_mesh.bottom_radius = rng.randf_range(22.0, 42.0)
		mesa_mesh.top_radius = mesa_mesh.bottom_radius * rng.randf_range(0.55, 0.78)
		mesa_mesh.height = rng.randf_range(16.0, 34.0)
		mesa_mesh.radial_segments = 10
		var mesa := MeshInstance3D.new()
		mesa.mesh = mesa_mesh
		mesa.material_override = mats["DesertMesa"]
		mesa.position = Vector3(cos(angle) * dist, -4.0 + mesa_mesh.height * 0.5, sin(angle) * dist)
		mesa.rotation.y = rng.randf_range(0.0, TAU)
		_add(mesa, backdrop_group, "DesertMesa%02d" % (i + 1))

func _spawns_and_kill_volume() -> void:
	var container := _group("SpawnPoints", arena)
	# 8 просторных точек спавна в ключевых зонах de_dust (координаты в схеме GLB -> _pos):
	var raw_spawns: Array[Dictionary] = [
		{"pos": Vector3(84.0, 3.8, 44.0), "look": Vector3(84.0, 3.8, 20.0)},   # 1. Mid Plaza (перед воротами на A)
		{"pos": Vector3(84.0, 3.8, 12.0), "look": Vector3(84.0, 3.8, 36.0)},   # 2. Front Courtyard (выход на A)
		{"pos": Vector3(82.0, 3.8, -18.0), "look": Vector3(82.0, 3.8, 10.0)},  # 3. CT Spawn / Bombsite A
		{"pos": Vector3(4.0, 3.8, 54.0), "look": Vector3(24.0, 3.8, 34.0)},    # 4. Bombsite B Courtyard
		{"pos": Vector3(72.0, 0.5, 84.0), "look": Vector3(40.0, 0.5, 84.0)},   # 5. Lower Underpass Plaza
		{"pos": Vector3(26.0, 3.8, 96.0), "look": Vector3(26.0, 3.8, 70.0)},   # 6. South-West Courtyard
		{"pos": Vector3(148.0, 5.3, 56.0), "look": Vector3(120.0, 3.8, 56.0)}, # 7. T-Spawn Courtyard
		{"pos": Vector3(116.0, 3.8, 46.0), "look": Vector3(84.0, 3.8, 46.0)}   # 8. East Mid Approach
	]

	for i in range(raw_spawns.size()):
		var item: Dictionary = raw_spawns[i]
		var p: Vector3 = _pos(item["pos"].x, item["pos"].y, item["pos"].z)
		var target: Vector3 = _pos(item["look"].x, item["look"].y, item["look"].z)
		var dir := (target - p).normalized()
		var marker := Marker3D.new()
		marker.position = p
		marker.rotation.y = atan2(-dir.x, -dir.z)
		_add(marker, container, "Spawn%02d" % (i + 1))

	var volume := Area3D.new()
	volume.position = Vector3(0.0, -10.0, 0.0)
	volume.collision_layer = 0
	volume.collision_mask = 2
	_add(volume, arena, "KillVolume")

	var kshape := BoxShape3D.new()
	kshape.size = Vector3(280.0, 8.0, 240.0)
	var kcol := CollisionShape3D.new()
	kcol.shape = kshape
	_add(kcol, volume, "CollisionShape3D")

func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)
