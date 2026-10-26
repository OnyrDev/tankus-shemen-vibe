extends SceneTree

## Скрипт запекания карты «Завод — Плавильня» (Factory Smelter) в стиле Factorio.
## Запускается через: godot --headless --path . --script tools/build_factory_smelter.gd

const OUTPUT := "res://maps/factory_smelter.tscn"

const ConveyorBelt3DScript = null
const Inserter3DScript = null
const BaseArenaScript = null

var _conveyor_script: GDScript
var _inserter_script: GDScript
var _arena_script: GDScript
var _lava_hazard_script: GDScript
var _crate_mesh: ArrayMesh

var arena: Node3D
var architecture: Node3D
var conveyors_group: Node3D
var inserters_group: Node3D
var props_group: Node3D
var backdrop_group: Node3D
var mats: Dictionary = {}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	_arena_script = load("res://maps/base_arena.gd")
	_conveyor_script = load("res://maps/components/conveyor_belt_3d.gd")
	_inserter_script = load("res://maps/components/inserter_3d.gd")
	_lava_hazard_script = load("res://maps/components/lava_hazard.gd")
	_crate_mesh = load("res://assets/props/industrial_crate/industrial_crate_mesh.res")
	
	arena = Node3D.new()
	arena.name = "FactorySmelter"
	arena.set_script(_arena_script)
	arena.set("arena_name", "Завод — Плавильня")
	
	_materials()
	
	architecture = _group("Architecture", arena)
	conveyors_group = _group("Conveyors", arena)
	inserters_group = _group("Inserters", arena)
	props_group = _group("DynamicProps", arena)
	backdrop_group = _group("Backdrop", arena)
	
	_environment()
	_floor_with_furnace_pit()
	_furnace_interior()
	_bridge_structure()
	_setup_conveyors()
	_setup_inserters_and_warehouse()
	_setup_props()
	_perimeter()
	_backdrop()
	_spawns_and_kill_volume()
	
	var packed := PackedScene.new()
	var error := packed.pack(arena)
	if error == OK:
		error = ResourceSaver.save(packed, OUTPUT)
	if error != OK:
		push_error("Cannot save Factory Smelter: " + error_string(error))
		quit(1)
		return
	
	arena.free()
	print("Factory Smelter built successfully: " + OUTPUT)
	quit(0)

func _materials() -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://maps/materials/factory_floor.gdshader")
	mats["Floor"] = floor_mat
	
	var molten_mat := ShaderMaterial.new()
	molten_mat.shader = load("res://maps/materials/molten_metal.gdshader")
	mats["Molten"] = molten_mat
	
	_mat("SteelDark", Color("242831"), 0.55, 0.45)
	_mat("SteelBeam", Color("3e4450"), 0.45, 0.6)
	_mat("HazardYellow", Color("e5a93b"), 0.35, 0.2)
	_mat("HazardDark", Color("14161a"), 0.7, 0.1)
	_mat("FurnaceBricks", Color("33241e"), 0.85, 0.1)
	_mat("Concrete", Color("4f535b"), 0.9, 0.0)

func _mat(key: String, color: Color, roughness: float, metallic: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	mats[key] = m

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2d3b4d")
	sky_mat.sky_horizon_color = Color("8c7b70")
	sky_mat.ground_horizon_color = Color("8c7b70")
	sky_mat.ground_bottom_color = Color("1e1c1a")
	
	var sky := Sky.new()
	sky.sky_material = sky_mat
	
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c0b3a6")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.3
	env.ssao_intensity = 1.4
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(world_env, arena, "WorldEnvironment")
	
	# Factory skylight sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color("fff2e0")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	_add(sun, arena, "Sunlight")

func _floor_with_furnace_pit() -> void:
	# Main floor is split into 4 sections around the central 14x12m furnace pit [X: -3..11, Z: -6..6]
	# Total arena: 58x40m (X: -29..29, Z: -20..20)
	
	# 1. West Plate (X: -29 to -3, width 26, Z: -20 to 20, depth 40)
	_box(architecture, "FloorWest", Vector3(-16.0, -0.5, 0.0), Vector3(26.0, 1.0, 40.0), "Floor", true)
	
	# 2. East Plate (X: 11 to 29, width 18, Z: -20 to 20, depth 40)
	_box(architecture, "FloorEast", Vector3(20.0, -0.5, 0.0), Vector3(18.0, 1.0, 40.0), "Floor", true)
	
	# 3. North Center Plate (X: -3 to 11, width 14, Z: -20 to -6, depth 14)
	_box(architecture, "FloorNorthCenter", Vector3(4.0, -0.5, -13.0), Vector3(14.0, 1.0, 14.0), "Floor", true)
	
	# 4. South Center Plate (X: -3 to 11, width 14, Z: 6 to 20, depth 14)
	_box(architecture, "FloorSouthCenter", Vector3(4.0, -0.5, 13.0), Vector3(14.0, 1.0, 14.0), "Floor", true)
	
	# Hazard warning borders along the edge of the pit (North, South, East, West)
	_box(architecture, "PitBorderNorth", Vector3(4.0, 0.05, -6.1), Vector3(14.4, 0.1, 0.3), "HazardYellow")
	_box(architecture, "PitBorderSouth", Vector3(4.0, 0.05, 6.1), Vector3(14.4, 0.1, 0.3), "HazardYellow")
	_box(architecture, "PitBorderWest", Vector3(-3.1, 0.05, 0.0), Vector3(0.3, 0.1, 12.4), "HazardYellow")
	_box(architecture, "PitBorderEast", Vector3(11.1, 0.05, 0.0), Vector3(0.3, 0.1, 12.4), "HazardYellow")

func _furnace_interior() -> void:
	var furnace := _group("CentralFurnacePit", architecture)
	
	# Pit retaining walls (Y from 0 to -3.5)
	# North wall
	_box(furnace, "WallNorth", Vector3(4.0, -1.75, -5.9), Vector3(14.0, 3.5, 0.4), "FurnaceBricks", true)
	# South wall
	_box(furnace, "WallSouth", Vector3(4.0, -1.75, 5.9), Vector3(14.0, 3.5, 0.4), "FurnaceBricks", true)
	# West wall
	_box(furnace, "WallWest", Vector3(-2.9, -1.75, 0.0), Vector3(0.4, 3.5, 12.0), "FurnaceBricks", true)
	# East wall
	_box(furnace, "WallEast", Vector3(10.9, -1.75, 0.0), Vector3(0.4, 3.5, 12.0), "FurnaceBricks", true)
	
	# Molten metal surface at Y = -3.2
	_box(furnace, "MoltenMetalSurface", Vector3(4.0, -3.2, 0.0), Vector3(13.6, 0.2, 11.6), "Molten", false)
	
	# Glowing orange light inside the furnace
	var glow := OmniLight3D.new()
	glow.name = "FurnaceGlowLight"
	glow.position = Vector3(4.0, -2.2, 0.0)
	glow.light_color = Color("ff6a14")
	glow.light_energy = 3.8
	glow.omni_range = 24.0
	glow.omni_attenuation = 0.8
	_add(glow, furnace, "FurnaceGlowLight")
	
	# Lethal lava hazard zone (kills tanks & vaporizes crates that drop into molten steel)
	var lava_zone: Area3D = _lava_hazard_script.new()
	lava_zone.set_script(_lava_hazard_script)
	lava_zone.name = "LavaHazardZone"
	lava_zone.position = Vector3(4.0, -2.5, 0.0)
	lava_zone.collision_layer = 0
	lava_zone.collision_mask = 2 | 8
	_add(lava_zone, furnace, "LavaHazardZone")
	
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(13.6, 2.2, 11.6)
	col.shape = box
	_add(col, lava_zone, "LavaCollision")

func _bridge_structure() -> void:
	var bridge := _group("ElevatedBridgeStructure", architecture)
	
	# Ramp North up to +3.4m (from Z = -14.5 to Z = -6.5 at X = 4.0)
	_ramp("NorthApproachRamp", Vector3(4.0, -0.05, -14.5), Vector3(4.0, 3.40, -6.5), 3.4)
	
	# Ramp South down from +3.4m to -0.05m (from Z = 6.5 to Z = 14.5 at X = 4.0)
	_ramp("SouthExitRamp", Vector3(4.0, 3.40, 6.5), Vector3(4.0, -0.05, 14.5), 3.4)
	
	# Overhead bridge deck over the furnace chasm (Z: -6.5 to +6.5, width 3.4, thickness 0.3)
	_box(bridge, "BridgeDeck", Vector3(4.0, 3.25, 0.0), Vector3(3.4, 0.3, 13.0), "SteelDark", true)
	
	# Heavy steel support pillars under the bridge at the pit borders
	for z_pos in [-6.5, 6.5]:
		for x_offset in [-1.5, 1.5]:
			_cylinder(bridge, "BridgePillar", Vector3(4.0 + x_offset, 1.6, z_pos), 0.22, 3.4, "SteelBeam")

func _setup_conveyors() -> void:
	# 1. Main High Gear Supply Highway: Runs from West warehouse inserters, smoothly curves
	# around the North corner, sweeps onto the elevated bridge over the furnace, and exits South.
	var gear_conveyor: Node3D = _conveyor_script.new()
	gear_conveyor.name = "GearOverpassConveyor"
	gear_conveyor.set("curve", Curve3D.new())
	var c1: Curve3D = gear_conveyor.get("curve")
	# P0: Start at south end of west warehouse
	c1.add_point(Vector3(-22.5, 0.05, 17.0), Vector3.ZERO, Vector3(0, 0, -4.0))
	# P1: North end of inserters row
	c1.add_point(Vector3(-22.5, 0.05, -13.0), Vector3(0, 0, 3.0), Vector3(0, 0, -3.0))
	# P2: NW bend from North to East
	c1.add_point(Vector3(-16.0, 0.05, -17.2), Vector3(-3.5, 0, 0), Vector3(3.5, 0, 0))
	# P3: Northern straightaway heading East
	c1.add_point(Vector3(-2.0, 0.05, -17.2), Vector3(-3.0, 0, 0), Vector3(3.0, 0, 0))
	# P4: Smooth sweeping turn onto bridge approach (transition to South)
	c1.add_point(Vector3(4.0, 0.05, -14.5), Vector3(0, 0, -2.5), Vector3(0, 0.875, 2.0))
	# P5: Crest of North approach ramp onto elevated bridge deck
	c1.add_point(Vector3(4.0, 3.55, -6.5), Vector3(0, -0.875, -2.0), Vector3(0, 0, 2.0))
	# P6: South edge of bridge deck over the furnace
	c1.add_point(Vector3(4.0, 3.55, 6.5), Vector3(0, 0, -2.0), Vector3(0, -0.875, 2.0))
	# P7: Foot of South exit ramp
	c1.add_point(Vector3(4.0, 0.05, 14.5), Vector3(0, 0.875, -2.0), Vector3(0, 0, 2.0))
	# P8: Exit arena South
	c1.add_point(Vector3(4.0, 0.05, 20.0), Vector3(0, 0, -2.0), Vector3.ZERO)
	gear_conveyor.set("belt_width", 3.2)
	gear_conveyor.set("speed", 7.0)
	gear_conveyor.set("show_gears", true)
	_add(gear_conveyor, conveyors_group, "GearOverpassConveyor")
	_bake_conveyor(gear_conveyor)
	
	# 2. SW Scrap Chute (feeding furnace from SW into west rim with smooth 90-degree turn)
	var sw_scrap: Node3D = _conveyor_script.new()
	sw_scrap.name = "SWScrapChute"
	sw_scrap.set("curve", Curve3D.new())
	var c3: Curve3D = sw_scrap.get("curve")
	var r_fillet := 3.5
	var k_fillet := 0.55228475 * r_fillet
	c3.add_point(Vector3(-14.0, 0.05, 16.0))
	c3.add_point(Vector3(-14.0, 0.05, 3.5 + r_fillet), Vector3.ZERO, Vector3(0, 0, -k_fillet))
	c3.add_point(Vector3(-14.0 + r_fillet, 0.05, 3.5), Vector3(-k_fillet, 0, 0), Vector3.ZERO)
	c3.add_point(Vector3(-2.8, 0.05, 3.5))
	sw_scrap.set("belt_width", 3.0)
	sw_scrap.set("speed", 5.2)
	sw_scrap.set("is_hazard", true)
	_add(sw_scrap, conveyors_group, "SWScrapChute")
	_bake_conveyor(sw_scrap)
	
	# 3. NE Scrap Chute (feeding furnace from NE into east rim with smooth 90-degree turn)
	var ne_scrap: Node3D = _conveyor_script.new()
	ne_scrap.name = "NEScrapChute"
	ne_scrap.set("curve", Curve3D.new())
	var c4: Curve3D = ne_scrap.get("curve")
	c4.add_point(Vector3(22.0, 0.05, -16.0))
	c4.add_point(Vector3(22.0, 0.05, -3.5 - r_fillet), Vector3.ZERO, Vector3(0, 0, k_fillet))
	c4.add_point(Vector3(22.0 - r_fillet, 0.05, -3.5), Vector3(k_fillet, 0, 0), Vector3.ZERO)
	c4.add_point(Vector3(10.8, 0.05, -3.5))
	ne_scrap.set("belt_width", 3.0)
	ne_scrap.set("speed", 5.2)
	ne_scrap.set("is_hazard", true)
	_add(ne_scrap, conveyors_group, "NEScrapChute")
	_bake_conveyor(ne_scrap)

func _bake_conveyor(conveyor: Node3D) -> void:
	conveyor.call("rebuild")
	var mesh_inst: Node = conveyor.get_node_or_null("BeltMesh")
	if mesh_inst:
		mesh_inst.owner = arena
	var col_cont: Node = conveyor.get_node_or_null("Collisions")
	if col_cont:
		col_cont.owner = arena
		for seg in col_cont.get_children():
			seg.owner = arena
			for c_shape in seg.get_children():
				c_shape.owner = arena

func _setup_inserters_and_warehouse() -> void:
	# 5 Factorio Inserters along the West conveyor
	var z_coords := [-12.0, -5.0, 2.0, 9.0, 15.0]
	for i in range(z_coords.size()):
		var inserter: Node3D = _inserter_script.new()
		inserter.name = "FactorioInserter_%02d" % (i + 1)
		inserter.position = Vector3(-25.2, 0.0, z_coords[i])
		inserter.set("cycle_offset", float(i) * 0.75)
		inserter.set("hold_gear", true)
		_add(inserter, inserters_group, inserter.name)
		
		# Pallet of raw gears next to each inserter
		_box(architecture, "GearPallet_%02d" % i, Vector3(-27.2, 0.25, z_coords[i]), Vector3(1.4, 0.5, 1.4), "SteelDark", true)
		_cylinder(architecture, "RawGear_%02d" % i, Vector3(-27.2, 0.55, z_coords[i]), 0.45, 0.12, "HazardYellow")

func _setup_props() -> void:
	# Solid Cover Barricades & Scrap Piles (replaced with tactical Industrial Crate stacks)
	_crate_cover_stack(props_group, "ScrapDumpSW", Vector3(-15.0, 0.0, 17.0), "scrap_dump")
	_crate_cover_stack(props_group, "ScrapDumpNE", Vector3(23.0, 0.0, -17.0), "scrap_dump")
	
	# Midfield Tactical Industrial Covers (breaking diagonal sightlines)
	_crate_cover_stack(props_group, "TransformerCoverWest", Vector3(-10.0, 0.0, -7.0), "wide")
	_crate_cover_stack(props_group, "TransformerCoverEast", Vector3(16.0, 0.0, 7.0), "wide")
	_crate_cover_stack(props_group, "FilterUnitNorth", Vector3(-4.0, 0.0, -10.0), "cluster")
	_crate_cover_stack(props_group, "FilterUnitSouth", Vector3(12.0, 0.0, 10.0), "cluster")
	
	# Corner deflector guards contouring the smooth 90-degree scrap chute turns
	_box(props_group, "CornerGuardSW_Diag", Vector3(-14.25, 0.45, 3.25), Vector3(3.0, 0.7, 0.25), "HazardYellow", true).rotation = Vector3(0, deg_to_rad(45), 0)
	_box(props_group, "CornerGuardSW_East", Vector3(-11.5, 0.45, 1.85), Vector3(3.2, 0.7, 0.25), "HazardYellow", true)
	_box(props_group, "CornerGuardSW_South", Vector3(-15.65, 0.45, 6.0), Vector3(0.25, 0.7, 3.2), "HazardYellow", true)

	_box(props_group, "CornerGuardNE_Diag", Vector3(22.25, 0.45, -3.25), Vector3(3.0, 0.7, 0.25), "HazardYellow", true).rotation = Vector3(0, deg_to_rad(45), 0)
	_box(props_group, "CornerGuardNE_West", Vector3(19.5, 0.45, -1.85), Vector3(3.2, 0.7, 0.25), "HazardYellow", true)
	_box(props_group, "CornerGuardNE_North", Vector3(23.65, 0.45, -6.0), Vector3(0.25, 0.7, 3.2), "HazardYellow", true)
	
	# Instantiate network-synchronized physical crates on the scrap chutes
	var crate_scene := load("res://maps/components/physics_crate.tscn") as PackedScene
	if crate_scene:
		var crate_positions := [
			Vector3(-14.0, 0.6, 12.0),
			Vector3(-14.0, 0.6, 7.0),
			Vector3(22.0, 0.6, -12.0),
			Vector3(22.0, 0.6, -7.0)
		]
		for i in range(crate_positions.size()):
			var crate := crate_scene.instantiate() as RigidBody3D
			crate.name = "FactoryCrate_%02d" % (i + 1)
			crate.position = crate_positions[i]
			_add(crate, props_group, crate.name)

func _perimeter() -> void:
	# Perimeter walls: 58x40m -> X: [-29, 29], Z: [-20, 20]
	for z_val in [-20.0, 20.0]:
		_box(architecture, "WallNorthSouth", Vector3(0, 0.6, z_val), Vector3(58.6, 1.2, 0.6), "Concrete", true)
		_box(architecture, "CopingNS", Vector3(0, 1.25, z_val), Vector3(58.8, 0.12, 0.8), "HazardYellow")
	for x_val in [-29.0, 29.0]:
		_box(architecture, "WallWestEast", Vector3(x_val, 0.6, 0), Vector3(0.6, 1.2, 40.0), "Concrete", true)
		_box(architecture, "CopingWE", Vector3(x_val, 1.25, 0), Vector3(0.8, 0.12, 40.0), "HazardYellow")

func _backdrop() -> void:
	# Giant factory smokestacks and cooling towers in the distance
	for i in range(6):
		var angle := float(i) * TAU / 6.0 + 0.3
		var dist := 120.0
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		
		# Smokestack tower
		_cylinder(backdrop_group, "Smokestack_%02d" % i, pos + Vector3(0, 25, 0), 4.0, 50.0, "SteelDark", 2.8)
		# Red emission warning band on top
		_cylinder(backdrop_group, "WarningBand_%02d" % i, pos + Vector3(0, 48, 0), 2.9, 2.0, "HazardYellow")

func _spawns_and_kill_volume() -> void:
	var container := _group("SpawnPoints", arena)
	
	# 8 Balanced spawn points: 4 corners + 4 midfield flank positions
	var spawn_coords := [
		Vector3(-18.0, 0.5, -10.0),
		Vector3(18.0, 0.5, -10.0),
		Vector3(-18.0, 0.5, 10.0),
		Vector3(18.0, 0.5, 10.0),
		Vector3(-8.0, 0.5, -14.0),
		Vector3(0.0, 0.5, 14.0),
		Vector3(-10.0, 0.5, 0.0),
		Vector3(18.0, 0.5, 0.0)
	]
	
	for i in range(spawn_coords.size()):
		var marker := Marker3D.new()
		marker.position = spawn_coords[i]
		marker.rotation.y = atan2(-marker.position.x, -marker.position.z)
		_add(marker, container, "Spawn%02d" % (i + 1))
	
	# Kill Volume Area3D inside the molten furnace and below the map
	var kill_vol := Area3D.new()
	kill_vol.name = "KillVolume"
	kill_vol.position = Vector3(4.0, -4.5, 0.0)
	kill_vol.collision_layer = 0
	kill_vol.collision_mask = 2 # Tanks layer
	_add(kill_vol, arena, "KillVolume")
	
	var kill_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180.0, 6.0, 180.0)
	kill_shape.shape = box
	_add(kill_shape, kill_vol, "KillShape")

func _ramp(label: String, start_pt: Vector3, end_pt: Vector3, width: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_add(body, architecture, label)
	
	var delta := end_pt - start_pt
	var dir := Vector2(delta.x, delta.z).normalized()
	var side := Vector2(-dir.y, dir.x) * width * 0.5
	
	var a := start_pt + Vector3(-side.x, 0, -side.y)
	var b := start_pt + Vector3(side.x, 0, side.y)
	var c := end_pt + Vector3(side.x, 0, side.y)
	var d := end_pt + Vector3(-side.x, 0, -side.y)
	
	var thickness := 0.35
	var bot_a := a - Vector3.UP * thickness
	var bot_b := b - Vector3.UP * thickness
	var bot_c := c - Vector3.UP * thickness
	var bot_d := d - Vector3.UP * thickness
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Top surface (CCW normal pointing upward/outward)
	for v in [a, c, b, a, d, c]:
		st.add_vertex(v)
	
	# Left skirt (facing +X / outward)
	for v in [a, bot_a, bot_d, a, bot_d, d]:
		st.add_vertex(v)
		
	# Right skirt (facing -X / outward)
	for v in [b, bot_c, bot_b, b, c, bot_c]:
		st.add_vertex(v)
	
	st.generate_normals()
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mats["SteelBeam"]
	_add(inst, body, "RampMesh")
	
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([a, b, c, d, bot_a, bot_b, bot_c, bot_d])
	var col := CollisionShape3D.new()
	col.shape = shape
	_add(col, body, "Collision")

func _box(parent: Node3D, label: String, pos: Vector3, size: Vector3, mat_key: String, solid: bool = false) -> Node3D:
	var node: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		node = body
	else:
		node = Node3D.new()
	
	node.position = pos
	_add(node, parent, label)
	
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mats[mat_key]
	_add(inst, node, "Mesh")
	
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		_add(col, node, "Collision")
	
	return node

func _cylinder(parent: Node3D, label: String, pos: Vector3, radius: float, height: float, mat_key: String, top_r: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_r < 0.0 else top_r
	mesh.height = height
	mesh.radial_segments = 14
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mats[mat_key]
	inst.position = pos
	_add(inst, parent, label)
	return inst

func _static_crate(parent: Node3D, label: String, pos: Vector3, rot_y_deg: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees.y = rot_y_deg
	_add(body, parent, label)
	
	var inst := MeshInstance3D.new()
	inst.name = "Mesh"
	inst.mesh = _crate_mesh
	_add(inst, body, "Mesh")
	
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.4, 1.4, 1.4)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	_add(col, body, "Collision")
	
	return body

func _crate_cover_stack(parent: Node3D, label: String, pos: Vector3, layout: String) -> Node3D:
	var group := _group(label, parent)
	group.position = pos
	
	match layout:
		"scrap_dump":
			# 2x2 base + 2 offset on top (wide heavy barricade)
			_static_crate(group, "Crate_Base_01", Vector3(-0.68, 0.7, -0.68), 0.0)
			_static_crate(group, "Crate_Base_02", Vector3(0.68, 0.7, -0.66), 4.0)
			_static_crate(group, "Crate_Base_03", Vector3(-0.66, 0.7, 0.68), -3.0)
			_static_crate(group, "Crate_Base_04", Vector3(0.68, 0.7, 0.68), 5.0)
			_static_crate(group, "Crate_Top_01", Vector3(-0.35, 2.1, 0.0), -8.0)
			_static_crate(group, "Crate_Top_02", Vector3(0.35, 2.1, 0.1), 9.0)
		"wide":
			# 2 bottom + 1 top centered (classic 3.0m wide tactical cover)
			_static_crate(group, "Crate_Base_01", Vector3(-0.72, 0.7, 0.0), -2.0)
			_static_crate(group, "Crate_Base_02", Vector3(0.72, 0.7, 0.0), 3.0)
			_static_crate(group, "Crate_Top_01", Vector3(0.0, 2.1, 0.0), 6.0)
		"cluster":
			# 3 bottom (L-shape / triangle) + 1 top (2.5x2.5m compact cover)
			_static_crate(group, "Crate_Base_01", Vector3(-0.65, 0.7, -0.38), 3.0)
			_static_crate(group, "Crate_Base_02", Vector3(0.65, 0.7, -0.38), -4.0)
			_static_crate(group, "Crate_Base_03", Vector3(0.0, 0.7, 0.65), 86.0)
			_static_crate(group, "Crate_Top_01", Vector3(0.0, 2.1, 0.0), -7.0)
	
	return group

func _group(label: String, parent: Node) -> Node3D:
	var g := Node3D.new()
	_add(g, parent, label)
	return g

func _add(node: Node, parent: Node, label: String) -> void:
	node.name = label
	parent.add_child(node, true)
	node.owner = arena
