extends Node3D

## Studio Turntable & Reference-Match Renderer for IndustrialCrate (.glb)
## Run: Godot_v4.7.2-stable_win64_console.exe --path . res://tools/preview_industrial_crate.tscn

const GLB_PATH := "res://assets/props/industrial_crate/industrial_crate.glb"
const OUT_DIR := "C:/Users/pavlo/.gemini/antigravity/brain/0f52faf8-4ca4-4e28-a3b3-998c44fb72f7/"

func _ready() -> void:
	for child in get_tree().root.get_children():
		if child != self:
			for sub in child.get_children():
				if sub is CanvasLayer:
					sub.hide()
			if child is CanvasLayer:
				child.hide()
	var debug_overlay := get_tree().root.get_node_or_null("DebugOverlay")
	if debug_overlay:
		debug_overlay.hide()

	get_window().size = Vector2i(1024, 1024)
	call_deferred("_render_studio")

func _render_studio() -> void:
	# 1. Studio Environment (Soft off-white cyclorama matching reference image)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.955, 0.95, 0.945)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.88, 0.90, 0.93)
	sky_mat.sky_horizon_color = Color(0.92, 0.92, 0.92)
	sky_mat.ground_horizon_color = Color(0.80, 0.80, 0.80)
	sky_mat.ground_bottom_color = Color(0.70, 0.70, 0.70)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 0.28
	env.ssao_intensity = 1.8

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# 2. Studio Floor (catches soft contact shadow under the crate)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_mesh
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.96, 0.955, 0.95)
	floor_mat.roughness = 0.95
	floor_mat.metallic = 0.0
	floor_inst.material_override = floor_mat
	floor_inst.position = Vector3(0.0, -0.703, 0.0)
	add_child(floor_inst)

	# 3. Studio 3-Point Lighting using explicit look_at() toward the crate
	var key_light := DirectionalLight3D.new()
	add_child(key_light)
	key_light.position = Vector3(1.6, 4.8, 3.8)
	key_light.look_at(Vector3.ZERO, Vector3.UP)
	key_light.light_energy = 1.15
	key_light.light_color = Color(1.0, 0.99, 0.97)
	key_light.shadow_enabled = true
	key_light.shadow_blur = 2.8
	key_light.shadow_opacity = 0.38

	var fill_light := DirectionalLight3D.new()
	add_child(fill_light)
	fill_light.position = Vector3(4.2, 2.2, 1.2)
	fill_light.look_at(Vector3.ZERO, Vector3.UP)
	fill_light.light_energy = 0.65
	fill_light.light_color = Color(0.95, 0.97, 1.0)
	fill_light.shadow_enabled = false

	var left_fill := DirectionalLight3D.new()
	add_child(left_fill)
	left_fill.position = Vector3(-1.8, 2.5, 4.2)
	left_fill.look_at(Vector3.ZERO, Vector3.UP)
	left_fill.light_energy = 0.50
	left_fill.light_color = Color(0.96, 0.97, 1.0)
	left_fill.shadow_enabled = false

	# 4. Load the generated GLB model via GLTFDocument
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(ProjectSettings.globalize_path(GLB_PATH), gltf_state)
	if err != OK:
		push_error("Failed to load GLB: " + str(err))
		get_tree().quit(1)
		return

	var crate_root := gltf_doc.generate_scene(gltf_state)
	add_child(crate_root)

	# Ensure linear vertex colors from glTF are used accurately
	_enable_vertex_colors(crate_root)

	# 5. Camera matching the exact three-quarter angle of the reference image
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 30.0
	cam.position = Vector3(2.38, 1.82, 2.45)
	cam.look_at(Vector3(0.0, -0.04, 0.0), Vector3.UP)
	cam.make_current()

	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "crate_render_main.png")
	img.save_png(OUT_DIR + "crate_render_v5.png")

	# Second angle: Rear-Opposite three-quarter view
	cam.position = Vector3(-2.42, 1.75, -2.38)
	cam.look_at(Vector3(0.0, -0.04, 0.0), Vector3.UP)
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "crate_render_alt.png")

	print("Studio renders saved to: " + OUT_DIR)
	get_tree().quit(0)

func _enable_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var bmat := mat as BaseMaterial3D
					bmat.vertex_color_use_as_albedo = true
					bmat.vertex_color_is_srgb = false
			ResourceSaver.save(mi.mesh, "res://assets/props/industrial_crate/industrial_crate_mesh.res")
	for c in node.get_children():
		_enable_vertex_colors(c)
