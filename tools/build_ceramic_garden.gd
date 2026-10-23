extends SceneTree

## Rebuilds an editable, fully baked scene. No runtime generation or randomness.
## Schematic coordinates are metres: x 0..56, z 0..48, centred in world space.
const OUTPUT := "res://maps/ceramic_garden.tscn"
const ORIGIN := Vector3(-28, 0, -24)
var arena: Node3D
var architecture: Node3D
var decoration: Node3D
var mats: Dictionary = {}
var mesh_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	rng.seed = 73126
	arena = Node3D.new()
	arena.name = "CeramicGarden"
	arena.set_script(load("res://maps/base_arena.gd"))
	arena.set("arena_name", "Керамический сад — Терракота")
	_materials()
	architecture = _group("Architecture", arena)
	decoration = _group("GardenDecor", arena)
	_environment()
	_floor()
	_terrace("NorthwestTerrace", Rect2(8, 8, 14, 12))
	_terrace("SoutheastTerrace", Rect2(34, 28, 14, 12))
	_ramp("NorthwestSouthRamp", Vector2(11, 28), Vector2(11, 20), 6.0)
	_ramp("NorthwestEastRamp", Vector2(30, 11), Vector2(22, 11), 6.0)
	_ramp("SoutheastWestRamp", Vector2(26, 37), Vector2(34, 37), 6.0)
	_ramp("SoutheastNorthRamp", Vector2(45, 20), Vector2(45, 28), 6.0)
	_bowl()
	_covers()
	_borders()
	_scenery()
	_spawns_and_fall_volume()
	var packed := PackedScene.new()
	var error := packed.pack(arena)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	if error != OK:
		push_error("Cannot save Ceramic Garden: %s" % error_string(error))
	arena.free()
	print("Ceramic Garden built: " + OUTPUT)
	quit(0 if error == OK else 1)

func _material(key: String, color: Color, roughness: float = 0.8) -> void:
	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	material.roughness = roughness
	mats[key] = material

func _materials() -> void:
	_material("Terracotta", Color("ce805c"))
	_material("Ivory", Color("f2dfb8"), 0.55)
	_material("Turquoise", Color("329a99"), 0.28)
	_material("Ochre", Color("dfb65a"), 0.4)
	_material("Soil", Color("69513c"))
	_material("Leaf", Color("53864a"))
	_material("LeafLight", Color("7b9c51"))
	_material("Cypress", Color("426e49"))
	_material("Trunk", Color("836345"))
	_material("Sea", Color("468ba5"), 0.32)
	_material("DistantRock", Color("8da6ab"))
	var tiles := ShaderMaterial.new()
	tiles.resource_name = "Warm limestone ceramic tiles"
	tiles.shader = load("res://maps/materials/garden_tiles.gdshader")
	tiles.set_shader_parameter("stone", Color("e4d0b3"))
	tiles.set_shader_parameter("grout", Color("b7a58c"))
	mats["Tiles"] = tiles

func _add(node: Node, parent: Node, label: String) -> void:
	node.name = label
	parent.add_child(node, true)
	node.owner = arena

func _group(label: String, parent: Node) -> Node3D:
	var group := Node3D.new()
	_add(group, parent, label)
	return group

func _pos(x: float, y: float, z: float) -> Vector3:
	return ORIGIN + Vector3(x, y, z)

func _mesh(parent: Node3D, label: String, mesh: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	_add(instance, parent, label)
	return instance

func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise front faces. Explicit outward normals keep ceramic
	# flat facets lit correctly without expensive two-sided materials.
	var normal := (b - a).cross(c - a).normalized()
	for vertex in [a, c, b]:
		st.set_normal(normal)
		st.add_vertex(vertex)

func _beveled_box(size: Vector3) -> ArrayMesh:
	var key := str(size)
	if mesh_cache.has(key):
		return mesh_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bevel := minf(0.10, minf(size.y, minf(size.x, size.z)) * 0.22)
	var rings: Array[PackedVector3Array] = []
	for ring in range(4):
		var inset := bevel if ring == 0 or ring == 3 else 0.0
		var half_x := size.x * 0.5 - inset
		var half_z := size.z * 0.5 - inset
		var y: float = [-size.y * 0.5, -size.y * 0.5 + bevel, size.y * 0.5 - bevel, size.y * 0.5][ring]
		var corner := minf(0.16, minf(half_x, half_z) * 0.3)
		rings.append(PackedVector3Array([
			Vector3(-half_x + corner, y, -half_z), Vector3(half_x - corner, y, -half_z),
			Vector3(half_x, y, -half_z + corner), Vector3(half_x, y, half_z - corner),
			Vector3(half_x - corner, y, half_z), Vector3(-half_x + corner, y, half_z),
			Vector3(-half_x, y, half_z - corner), Vector3(-half_x, y, -half_z + corner)]))
	for r in range(3):
		for i in range(8):
			var j := (i + 1) % 8
			_triangle(st, rings[r][i], rings[r + 1][i], rings[r + 1][j])
			_triangle(st, rings[r][i], rings[r + 1][j], rings[r][j])
	for i in range(1, 7):
		_triangle(st, rings[3][0], rings[3][i + 1], rings[3][i])
		_triangle(st, rings[0][0], rings[0][i], rings[0][i + 1])
	var result := st.commit()
	mesh_cache[key] = result
	return result

func _box(parent: Node3D, label: String, center: Vector3, size: Vector3, material: String, solid: bool = false) -> Node3D:
	var node: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		node = body
	else:
		node = Node3D.new()
	node.position = center
	_add(node, parent, label)
	_mesh(node, "CeramicMesh", _beveled_box(size), Vector3.ZERO, mats[material])
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		_collision(node, shape)
	return node

func _collision(parent: Node3D, shape: Shape3D) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_add(collision, parent, "Collision")

func _lathe(profile: Array[Vector2], segments: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var angle := TAU * float(i) / segments
		var next := TAU * float(i + 1) / segments
		for j in range(profile.size() - 1):
			var lower := profile[j]
			var upper := profile[j + 1]
			var a := Vector3(cos(angle) * lower.x, lower.y, sin(angle) * lower.x)
			var b := Vector3(cos(angle) * upper.x, upper.y, sin(angle) * upper.x)
			var c := Vector3(cos(next) * upper.x, upper.y, sin(next) * upper.x)
			var d := Vector3(cos(next) * lower.x, lower.y, sin(next) * lower.x)
			_triangle(st, a, b, c)
			_triangle(st, a, c, d)
	return st.commit()

func _cylinder(parent: Node3D, label: String, position: Vector3, radius: float, height: float, material: String, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 12
	return _mesh(parent, label, mesh, position, mats[material])

func _environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("438bc8")
	sky_material.sky_horizon_color = Color("c1e0e8")
	sky_material.ground_horizon_color = Color("c1e0e8")
	sky_material.ground_bottom_color = Color("7ba7b1")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d2e4ed")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 1.3
	var world := WorldEnvironment.new()
	world.environment = env
	_add(world, arena, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.10
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	_add(sun, arena, "AfternoonSun")

func _floor() -> void:
	_box(architecture, "Foundation", _pos(28, -0.75, 24), Vector3(57, 1.3, 49), "Terracotta", true)
	_box(architecture, "CourtyardTiles", _pos(28, -0.10, 24), Vector3(56, 0.20, 48), "Tiles", true)
	# Thin inlaid strips sit flush enough not to change driving or projectile hits.
	for x in [2.0, 24.0, 32.0, 54.0]:
		_box(decoration, "TurquoiseFloorInlay", _pos(x, 0.004, 24), Vector3(0.18, 0.008, 44), "Turquoise")
	for z in [2.0, 18.0, 30.0, 46.0]:
		_box(decoration, "TurquoiseFloorInlay", _pos(28, 0.005, z), Vector3(52, 0.008, 0.18), "Turquoise")

func _terrace(label: String, rect: Rect2) -> void:
	var group := _group(label, architecture)
	var center := rect.get_center()
	_box(group, "TerracottaRetainingWall", _pos(center.x, 1.4, center.y), Vector3(rect.size.x, 2.8, rect.size.y), "Terracotta", true)
	_box(group, "GlazedFrieze", _pos(center.x, 2.7, center.y), Vector3(rect.size.x + 0.03, 0.22, rect.size.y + 0.03), "Turquoise")
	_box(group, "IvoryCoping", _pos(center.x, 2.9, center.y), Vector3(rect.size.x + 0.1, 0.2, rect.size.y + 0.1), "Tiles", true)
	_planter(label + "RearPlanter", Rect2(rect.position + Vector2(3, 2), Vector2(5, 2)), 3.0, false)

func _ramp(label: String, low: Vector2, high: Vector2, width: float) -> void:
	var body := StaticBody3D.new()
	_add(body, architecture, label)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("garden_ramps", true)
	var direction := (high - low).normalized()
	var side := Vector2(-direction.y, direction.x) * width * 0.5
	var a := _pos(low.x - side.x, 0, low.y - side.y)
	var b := _pos(low.x + side.x, 0, low.y + side.y)
	var c := _pos(high.x + side.x, 0, high.y + side.y)
	var d := _pos(high.x - side.x, 0, high.y - side.y)
	var e := d + Vector3.UP * 3.0
	var f := c + Vector3.UP * 3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[a, b, f], [a, f, e], [a, e, d], [b, c, f], [d, e, f], [d, f, c], [a, d, c], [a, c, b]]:
		_triangle(st, face[0], face[1], face[2])
	var mesh := st.commit()
	_mesh(body, "TiledRamp", mesh, Vector3.ZERO, mats["Tiles"])
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, e, f])
	_collision(body, shape)
	# Flush glazed edge lanes, with no rail at the foot or top to snag tracks.
	var middle := (low + high) * 0.5
	for sign_value in [-1.0, 1.0]:
		var offset: Vector2 = side.normalized() * (width * 0.5 - 0.25) * sign_value
		var strip := _box(decoration, label + "EdgeInlay", _pos(middle.x + offset.x, 1.51, middle.y + offset.y), Vector3(0.20, 0.015, sqrt(low.distance_squared_to(high) + 9.0)), "Turquoise")
		strip.rotation.y = atan2(direction.x, direction.y)
		strip.rotation.x = -atan2(3.0, low.distance_to(high))

func _bowl() -> void:
	var group := _group("CentralCeramicBowl", architecture)
	_box(group, "SolidPedestal", _pos(28, 0.45, 24), Vector3(5.4, 0.9, 5.4), "Ivory", true)
	_box(group, "TurquoisePedestalBand", _pos(28, 0.82, 24), Vector3(5.45, 0.20, 5.45), "Turquoise")
	_box(group, "PedestalCap", _pos(28, 0.98, 24), Vector3(5.6, 0.16, 5.6), "Ivory", true)
	var mesh := _lathe([Vector2(0, 0), Vector2(1.25, 0), Vector2(1.35, 0.2), Vector2(1.9, 0.45), Vector2(2.55, 0.95), Vector2(3.0, 1.55), Vector2(3.02, 1.66), Vector2(2.8, 1.66), Vector2(2.72, 1.48), Vector2(2.3, 0.96), Vector2(1.6, 0.55), Vector2(0, 0.4)], 64)
	var bowl := StaticBody3D.new()
	bowl.position = _pos(28, 1.06, 24)
	bowl.collision_layer = 1
	bowl.collision_mask = 0
	_add(bowl, group, "HollowBowl")
	_mesh(bowl, "IvoryGlazedBowl", mesh, Vector3.ZERO, mats["Ivory"])
	_collision(bowl, mesh.create_trimesh_shape())
	var rim := _lathe([Vector2(2.97, 1.52), Vector2(3.035, 1.61), Vector2(3.035, 1.69), Vector2(2.78, 1.69), Vector2(2.78, 1.61)], 64)
	_mesh(bowl, "TurquoiseRim", rim, Vector3.ZERO, mats["Turquoise"])

func _planter(label: String, rect: Rect2, base_y: float = 0.0, tall: bool = false) -> void:
	var group := _group(label, decoration)
	var center := rect.get_center()
	var h := 1.5
	_box(group, "TerracottaPlanter", _pos(center.x, base_y + h * 0.5, center.y), Vector3(rect.size.x, h, rect.size.y), "Terracotta", true)
	_box(group, "GlazedBand", _pos(center.x, base_y + h - 0.22, center.y), Vector3(rect.size.x + 0.04, 0.25, rect.size.y + 0.04), "Turquoise")
	_box(group, "IvoryLip", _pos(center.x, base_y + h + 0.02, center.y), Vector3(rect.size.x + 0.16, 0.14, rect.size.y + 0.16), "Ivory")
	_box(group, "Soil", _pos(center.x, base_y + h + 0.10, center.y), Vector3(rect.size.x - 0.3, 0.03, rect.size.y - 0.3), "Soil")
	for x in range(maxi(1, int(rect.size.x / 1.2))):
		for z in range(maxi(1, int(rect.size.y / 1.2))):
			var p := _pos(rect.position.x + 0.6 + x * 1.2, base_y + 1.8, rect.position.y + 0.6 + z * 1.2)
			_shrub(group, p, 0.65)
	if tall:
		_cypress(group, _pos(center.x, base_y + h, center.y), 3.0)

func _shrub(parent: Node3D, pos: Vector3, radius: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 1.45
	mesh.radial_segments = 8
	mesh.rings = 4
	var instance := _mesh(parent, "LowPolyFoliage", mesh, pos + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), mats["Leaf" if rng.randf() > 0.4 else "LeafLight"])
	instance.rotation.y = rng.randf_range(0, TAU)

func _cypress(parent: Node3D, pos: Vector3, height: float) -> void:
	_cylinder(parent, "CypressTrunk", pos + Vector3(0, height * 0.2, 0), 0.13, height * 0.4, "Trunk")
	for level in range(3):
		var fraction := float(level) / 3.0
		_cylinder(parent, "CypressCrown", pos + Vector3(0, height * (0.42 + fraction * 0.55), 0), 0.65 * (1.0 - fraction * 0.5), height * 0.5, "Cypress", 0.09)

func _covers() -> void:
	var rectangles: Array[Rect2] = [Rect2(3, 7, 3, 6), Rect2(16, 3, 7, 2), Rect2(34, 3, 7, 2), Rect2(47, 8, 6, 3), Rect2(4, 34, 5, 3), Rect2(13, 42, 7, 2), Rect2(33, 43, 7, 2), Rect2(50, 33, 3, 7), Rect2(17, 30, 4, 2), Rect2(35, 16, 4, 2)]
	for i in range(rectangles.size()):
		_planter("CoverPlanter%02d" % i, rectangles[i])

func _borders() -> void:
	for z in [-0.3, 48.3]:
		_box(architecture, "PerimeterWall", _pos(28, 0.6, z), Vector3(57, 1.2, 0.6), "Terracotta", true)
		_box(decoration, "IvoryWallCoping", _pos(28, 1.24, z), Vector3(57.1, 0.16, 0.8), "Ivory")
	for x in [-0.3, 56.3]:
		_box(architecture, "PerimeterWall", _pos(x, 0.6, 24), Vector3(0.6, 1.2, 48), "Terracotta", true)
		_box(decoration, "IvoryWallCoping", _pos(x, 1.24, 24), Vector3(0.8, 0.16, 48), "Ivory")
	for p in [Vector2(0, 0), Vector2(56, 0), Vector2(0, 48), Vector2(56, 48), Vector2(12, 0), Vector2(44, 48), Vector2(56, 12), Vector2(0, 36)]:
		var group := _group("PerimeterPot", decoration)
		var pot := _lathe([Vector2(0, 0), Vector2(0.55, 0), Vector2(0.8, 0.15), Vector2(0.95, 1.15), Vector2(1, 1.3), Vector2(0.83, 1.3), Vector2(0.75, 0.35), Vector2(0, 0.3)], 24)
		_mesh(group, "CeramicPot", pot, _pos(p.x, 1.3, p.y), mats["Ivory"])
		_cypress(group, _pos(p.x, 2.2, p.y), 4.0)

func _scenery() -> void:
	var scenery := _group("CoastalBackdrop", arena)
	_box(scenery, "SeaHorizon", Vector3(0, -5, 0), Vector3(1600, 0.1, 1600), "Sea")
	# Distant silhouettes have no collision and are outside the playable court.
	for i in range(18):
		var angle := float(i) * TAU / 18.0
		var distance := rng.randf_range(180, 280)
		var p := Vector3(cos(angle) * distance, -4, sin(angle) * distance)
		var radius := rng.randf_range(14, 30)
		var height := rng.randf_range(15, 32)
		_island(scenery, p, radius, height)

func _island(parent: Node3D, pos: Vector3, radius: float, height: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for level in range(3):
		var ring := PackedVector3Array()
		for i in range(12):
			var angle := TAU * float(i) / 12
			var r: float = radius * [1.0, 0.62, 0.18][level] * rng.randf_range(0.75, 1.2)
			var y: float = height * [0.0, 0.42, 0.83][level] * rng.randf_range(0.75, 1.2)
			ring.append(Vector3(cos(angle) * r, y, sin(angle) * r))
		rings.append(ring)
	for level in range(2):
		for i in range(12):
			var j := (i + 1) % 12
			_triangle(st, rings[level][i], rings[level + 1][i], rings[level + 1][j])
			_triangle(st, rings[level][i], rings[level + 1][j], rings[level][j])
	for i in range(12):
		_triangle(st, rings[2][i], Vector3(0, height, 0), rings[2][(i + 1) % 12])
	_mesh(parent, "DistantIsland", st.commit(), pos, mats["DistantRock"])

func _spawns_and_fall_volume() -> void:
	var container := _group("SpawnPoints", arena)
	# Order starts south, facing the plaza: practice begins looking into the map.
	var points: Array[Vector2] = [Vector2(28, 44), Vector2(28, 4), Vector2(4, 24), Vector2(52, 24), Vector2(4, 44), Vector2(52, 4), Vector2(4, 4), Vector2(52, 44)]
	for i in range(points.size()):
		var marker := Marker3D.new()
		marker.position = _pos(points[i].x, 0.5, points[i].y)
		marker.rotation.y = atan2(-marker.position.x, -marker.position.z) + PI
		_add(marker, container, "Spawn%02d" % (i + 1))
	var volume := Area3D.new()
	volume.position.y = -8.0
	volume.collision_layer = 0
	volume.collision_mask = 2
	_add(volume, arena, "KillVolume")
	var shape := BoxShape3D.new()
	shape.size = Vector3(180, 8, 180)
	_collision(volume, shape)
