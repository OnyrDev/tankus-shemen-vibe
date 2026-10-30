extends SceneTree

## Bakes a static, editable arena from the Radio Station schematic (metres).
const OUTPUT := "res://maps/radio_station.tscn"
const ORIGIN := Vector3(-30, 0, -24)
var arena: Node3D
var architecture: Node3D
var decoration: Node3D
var mats: Dictionary = {}
var mesh_cache: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	rng.seed = 193741
	arena = Node3D.new()
	arena.name = "RadioStation"
	arena.set_script(load("res://maps/base_arena.gd"))
	arena.set("arena_name", "Радиостанция — Малиновая частота")
	_materials()
	architecture = _group("Architecture", arena)
	decoration = _group("TechnicalDetails", arena)
	_environment()
	_floor()
	_platform()
	_ramp("WestAccessRamp", Vector2(16, 16), Vector2(24, 16), 6.0)
	_ramp("EastAccessRamp", Vector2(44, 32), Vector2(36, 32), 6.0)
	_covers()
	_antenna()
	_perimeter()
	_backdrop()
	_spawns()
	var packed := PackedScene.new()
	var error := packed.pack(arena)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	if error != OK:
		push_error("Cannot save Radio Station: " + error_string(error))
	arena.free()
	print("Radio Station built: " + OUTPUT)
	quit(0 if error == OK else 1)

func _materials() -> void:
	_material("Graphite", Color("343d50"), 0.55)
	_material("Raspberry", Color("b62f65"), 0.4)
	_material("Cyan", Color("66cfe3"), 0.35)
	_material("White", Color("e0e6ed"), 0.6)
	_material("Recess", Color("19212c"), 0.8)
	_material("Steel", Color("6b7a8b"), 0.38)
	_material("Rock", Color("7b829f"), 0.95)
	_material("DistantGround", Color("67748c"), 1.0)
	for key in ["Graphite", "Raspberry", "Steel"]:
		(mats[key] as StandardMaterial3D).metallic = 0.45
	var deck := ShaderMaterial.new()
	deck.resource_name = "Segmented graphite deck"
	deck.shader = load("res://maps/materials/radio_deck.gdshader")
	deck.set_shader_parameter("plate", Color("555c6c"))
	deck.set_shader_parameter("seam", Color("1e2633"))
	mats["Deck"] = deck

func _environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4e86c7")
	sky_material.sky_horizon_color = Color("cfdaed")
	sky_material.ground_horizon_color = Color("cfdaed")
	sky_material.ground_bottom_color = Color("747b97")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("cad8ed")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 1.2
	var world := WorldEnvironment.new()
	world.environment = env
	_add(world, arena, "WorldEnvironment")
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -36, 0)
	sun.light_color = Color("fff1e8")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	_add(sun, arena, "Daylight")

func _floor() -> void:
	_box(architecture, "Foundation", _pos(30, -0.75, 24), Vector3(61, 1.3, 49), "Graphite", true)
	_box(architecture, "PanelDeck", _pos(30, -0.1, 24), Vector3(60, 0.2, 48), "Deck", true)
	# Thin paint, not physical obstacles. The two end routes remain wide open.
	for x in [2.0, 22.0, 38.0, 58.0]:
		_box(decoration, "CyanLaneEdge", _pos(x, 0.008, 24), Vector3(0.12, 0.012, 43), "Cyan")
	for z in [3.0, 10.0, 38.0, 45.0]:
		for x in range(12, 49, 4):
			_box(decoration, "BypassPaint", _pos(x, 0.009, z), Vector3(1.5, 0.012, 0.22), "White")

func _platform() -> void:
	var group := _group("CentralServiceTerrace", architecture)
	_box(group, "SolidStructure", _pos(30, 1.4, 24), Vector3(12, 2.8, 22), "Graphite", true)
	_box(group, "UpperDeck", _pos(30, 2.9, 24), Vector3(12, 0.2, 22), "Deck", true)
	for x in [24.02, 35.98]:
		_box(group, "CyanEdge", _pos(x, 2.96, 24), Vector3(0.13, 0.10, 22), "Cyan")
	# Inset raspberry panels stay within the original platform footprint.
	for z in [21.0, 26.5]:
		for x in [23.96, 36.04]:
			_box(group, "MagentaSidePanel", _pos(x, 1.45, z), Vector3(0.06, 2.15, 4.9), "Raspberry")
	for z in [12.96, 35.04]:
		_box(group, "MagentaEndPanel", _pos(30, 1.45, z), Vector3(11.5, 2.15, 0.06), "Raspberry")

func _ramp(label: String, low: Vector2, high: Vector2, width: float) -> void:
	var body := StaticBody3D.new()
	_add(body, architecture, label)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("radio_ramps", true)
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
	_mesh(body, "MetalRamp", st.commit(), Vector3.ZERO, mats["Deck"])
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, e, f])
	_collision(body, shape)
	var middle := (low + high) * 0.5
	for sign_value in [-1.0, 1.0]:
		var offset: Vector2 = side.normalized() * (width * 0.5 - 0.18) * sign_value
		var strip := _box(decoration, label + "CyanEdge", _pos(middle.x + offset.x, 1.515, middle.y + offset.y), Vector3(0.22, 0.018, sqrt(low.distance_squared_to(high) + 9.0)), "Cyan")
		strip.rotation.y = atan2(direction.x, direction.y)
		strip.rotation.x = -atan2(3.0, low.distance_to(high))

func _cabinet(label: String, rect: Rect2, height: float = 1.7, base: float = 0.0) -> void:
	var group := _group(label, architecture)
	var c := rect.get_center()
	_box(group, "SolidEquipment", _pos(c.x, base + height * 0.5, c.y), Vector3(rect.size.x, height, rect.size.y), "Graphite", true)
	for z in [-1.0, 1.0]:
		_box(group, "RaspberryFace", _pos(c.x, base + height * 0.51, c.y + z * (rect.size.y * 0.5 + 0.018)), Vector3(rect.size.x - 0.20, height - 0.2, 0.04), "Raspberry")
		var vent_width := minf(2.6, rect.size.x - 0.7)
		_box(group, "VentRecess", _pos(c.x, base + height * 0.53, c.y + z * (rect.size.y * 0.5 + 0.045)), Vector3(vent_width, height * 0.58, 0.025), "Recess")
		for slat in range(5):
			_box(group, "VentLouvre", _pos(c.x, base + height * 0.30 + slat * height * 0.11, c.y + z * (rect.size.y * 0.5 + 0.063)), Vector3(vent_width - 0.1, 0.055, 0.04), "Steel")
	for x in [-1.0, 1.0]:
		_box(group, "CyanCornerGuard", _pos(c.x + x * (rect.size.x * 0.5 - 0.13), base + height * 0.5, c.y), Vector3(0.16, height - 0.1, rect.size.y + 0.06), "Cyan")
	_box(group, "TopCap", _pos(c.x, base + height - 0.04, c.y), Vector3(rect.size.x + 0.02, 0.09, rect.size.y + 0.06), "Steel")

func _covers() -> void:
	# Exact footprints of the previous Radio Station schematic.
	var covers: Array[Rect2] = [Rect2(7,6,10,3), Rect2(7,9,3,9), Rect2(7,30,3,9), Rect2(10,36,8,3), Rect2(43,6,10,3), Rect2(50,9,3,9), Rect2(50,30,3,9), Rect2(42,36,8,3), Rect2(19,22,3,5), Rect2(38,21,3,5), Rect2(26,5,8,2), Rect2(26,41,8,2)]
	for i in range(covers.size()):
		_cabinet("EquipmentCover%02d" % i, covers[i])
	_cabinet("CentralAntennaBase", Rect2(28,23,4,3), 2.0, 3.0)

func _beam(parent: Node3D, label: String, a: Vector3, b: Vector3, radius: float, material: String) -> void:
	var node := _cylinder(parent, label, (a + b) * 0.5, radius, a.distance_to(b), material)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _antenna() -> void:
	var group := _group("BroadcastAntenna", decoration)
	# Thin lattice is decorative. Solid, visible equipment below is the cover.
	var mast := _pos(31, 5, 25)
	var corners: Array[Vector3] = [Vector3(-0.6,0,-0.6), Vector3(0.6,0,-0.6), Vector3(0.6,0,0.6), Vector3(-0.6,0,0.6)]
	for i in range(4):
		_beam(group, "MastColumn", mast + corners[i], mast + corners[i] + Vector3.UP * 11, 0.075, "Raspberry")
		for level in range(5):
			var a := mast + corners[i] + Vector3.UP * level * 2
			var b := mast + corners[(i+1)%4] + Vector3.UP * (level+1) * 2
			_beam(group, "LatticeBrace", a, b, 0.045, "Raspberry")
			_beam(group, "HorizontalBrace", a, mast + corners[(i+1)%4] + Vector3.UP * level * 2, 0.045, "Steel")
	for x in [-1.05, 1.05]:
		_box(group, "SignalPanel", mast + Vector3(x, 9.2, 0), Vector3(0.42, 2.8, 0.9), "White")
		_box(group, "PanelMount", mast + Vector3(x * 0.65, 8.5, 0), Vector3(0.6, 0.16, 0.3), "Raspberry")
	_beam(group, "LightningRod", mast + Vector3.UP * 11, mast + Vector3.UP * 12.5, 0.035, "Steel")
	# A tilted, genuinely concave dish with ribs and receiver supports.
	var pivot := _group("DishTilt", group)
	pivot.position = _pos(29.8, 9.0, 27.2)
	pivot.rotation_degrees = Vector3(48, -22, 0)
	var face_profile: Array[Vector2] = [Vector2(3.6,1.60), Vector2(2.7,0.94), Vector2(1.8,0.48), Vector2(0.9,0.20), Vector2(0,0.12)]
	var back_profile: Array[Vector2] = [Vector2(0,-0.04), Vector2(0.9,0.06), Vector2(1.8,0.34), Vector2(2.7,0.80), Vector2(3.65,1.5), Vector2(3.6,1.60)]
	var face := _lathe(face_profile, 64)
	var back := _lathe(back_profile, 64)
	_mesh(pivot, "WhiteReflector", face, Vector3.ZERO, mats["White"])
	_mesh(pivot, "RaspberryDishBack", back, Vector3.ZERO, mats["Raspberry"])
	_mesh(pivot, "DishRim", _lathe([Vector2(3.6,1.57), Vector2(3.65,1.64), Vector2(3.55,1.68)], 64), Vector3.ZERO, mats["Raspberry"])
	for i in range(8):
		var a := TAU * i / 8
		_beam(pivot, "RadialRib", Vector3(cos(a)*0.6,0.0,sin(a)*0.6), Vector3(cos(a)*3.55,1.48,sin(a)*3.55), 0.045, "Raspberry")
	for i in range(3):
		var a := TAU * i / 3
		_beam(pivot, "ReceiverArm", Vector3(cos(a)*3.0,1.14,sin(a)*3.0), Vector3(0,3.0,0), 0.065, "Steel")
	_cylinder(pivot, "FeedReceiver", Vector3(0,3.0,0), 0.25, 0.65, "Graphite")
	_cylinder(pivot, "FeedCyanCap", Vector3(0,3.35,0), 0.23, 0.09, "Cyan")
	_box(group, "DishPedestal", _pos(29.8, 5.65, 24), Vector3(1.5, 1.3, 1.5), "Raspberry")
	_beam(group, "DishSupport", _pos(29.8,5.5,24), pivot.position, 0.32, "Steel")

func _perimeter() -> void:
	for z in [-0.3, 48.3]:
		_box(architecture, "PerimeterBarrier", _pos(30, 0.6, z), Vector3(61, 1.2, 0.6), "Graphite", true)
		_box(decoration, "CyanPerimeterCap", _pos(30, 1.24, z), Vector3(61.1, 0.12, 0.7), "Cyan")
	for x in [-0.3, 60.3]:
		_box(architecture, "PerimeterBarrier", _pos(x, 0.6, 24), Vector3(0.6, 1.2, 48), "Graphite", true)
		_box(decoration, "CyanPerimeterCap", _pos(x, 1.24, 24), Vector3(0.7, 0.12, 48), "Cyan")
	for p in [Vector2(0,12), Vector2(60,36), Vector2(12,0), Vector2(48,48)]:
		_box(decoration, "RelayPost", _pos(p.x, 2.5, p.y), Vector3(0.35,5,0.35), "Graphite")
		_box(decoration, "RelayPanel", _pos(p.x, 4.1, p.y), Vector3(0.65,1.6,0.4), "Raspberry")

func _backdrop() -> void:
	var group := _group("DistantMountainBackdrop", arena)
	_box(group, "DistantGround", Vector3(0,-10,0), Vector3(1400,0.1,1400), "DistantGround")
	for i in range(24):
		var angle := TAU * i / 24
		var distance := rng.randf_range(190,310)
		var radius := rng.randf_range(25,48)
		_island(group, Vector3(cos(angle)*distance,-12,sin(angle)*distance), radius, rng.randf_range(22,55))

func _spawns() -> void:
	var container := _group("SpawnPoints", arena)
	var points: Array[Vector2] = [Vector2(21,44), Vector2(39,4), Vector2(4,4), Vector2(56,44), Vector2(39,44), Vector2(21,4), Vector2(56,4), Vector2(4,44)]
	for i in range(points.size()):
		var marker := Marker3D.new()
		marker.position = _pos(points[i].x, 0.5, points[i].y)
		marker.rotation.y = atan2(-marker.position.x, -marker.position.z) + PI
		_add(marker, container, "Spawn%02d" % (i+1))
	var volume := Area3D.new()
	volume.position.y = -8
	volume.collision_layer = 0
	volume.collision_mask = 2
	_add(volume, arena, "KillVolume")
	var shape := BoxShape3D.new()
	shape.size = Vector3(180,8,180)
	_collision(volume, shape)


func _material(key: String, color: Color, roughness: float = 0.8) -> void:
	var material := StandardMaterial3D.new()
	material.resource_name = key
	material.albedo_color = color
	material.roughness = roughness
	mats[key] = material


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
	_mesh(node, "PanelMesh", _beveled_box(size), Vector3.ZERO, mats[material])
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
	_mesh(parent, "MountainRidge", st.commit(), pos, mats["Rock"])
