extends Node3D

## Рендерит геймплейный ракурс и общий обзор карты Dust I (de_dust).
## Запускать без --headless: godot --path . tools/preview_de_dust.tscn
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	call_deferred("_preview")

func _preview() -> void:
	Game.rules.selected_map = "de_dust"
	Game.is_solo_practice = true
	var sandbox := (load("res://maps/test_sandbox.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(sandbox)
	for frame in range(12):
		await get_tree().physics_frame

	# Ставим наш танк перед распахнутыми двойными воротами на Mid, а мишень — за воротами в сторону A:
	sandbox.tank.position = Vector3(-73.0 + 83.2, 3.8, -45.0 + 40.0)
	sandbox.tank.rotation = Vector3(0.0, 0.0, 0.0)
	sandbox.dummy_tank.position = Vector3(-73.0 + 83.2, 3.8, -45.0 + 18.0)
	sandbox.camera.setup_target(sandbox.tank)
	sandbox.camera.pitch = deg_to_rad(8.0)
	sandbox.camera.spring_arm.rotation.x = -sandbox.camera.pitch

	for frame in range(35):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/concepts/de-dust"))
	var output := "res://docs/concepts/de-dust/"
	get_viewport().get_texture().get_image().save_png(output + "godot-gameplay.png")

	for child in sandbox.get_children():
		if child is CanvasLayer:
			child.hide()
	var dbg := get_tree().root.get_node_or_null("DebugOverlay")
	if dbg:
		dbg.hide()

	var overview := Camera3D.new()
	sandbox.add_child(overview)
	overview.position = Vector3(68.0, 78.0, 88.0)
	overview.look_at(Vector3(0.0, 2.0, 0.0))
	overview.fov = 52.0
	overview.make_current()

	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "godot-overview.png")
	print("Saved Dust I screenshots to " + output)
	get_tree().quit()

