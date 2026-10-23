extends Node3D

## Render the real gameplay camera and an overview, then exit. Use without
## --headless, e.g. godot --path . tools/preview_radio_station.tscn
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	call_deferred("_preview")

func _preview() -> void:
	Game.rules.selected_map = "radio_station"
	Game.is_solo_practice = true
	var sandbox := (load("res://maps/test_sandbox.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(sandbox)
	for frame in range(12):
		await get_tree().physics_frame
	sandbox.tank.position = Vector3(-15, 0.5, 7)
	sandbox.tank.rotation = Vector3(0, -0.95, 0)
	sandbox.dummy_tank.position = Vector3(15, 0.5, -5)
	sandbox.camera.setup_target(sandbox.tank)
	sandbox.camera.pitch = deg_to_rad(10)
	sandbox.camera.spring_arm.rotation.x = -sandbox.camera.pitch
	for frame in range(35):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var output := "res://docs/concepts/radio-station/color-variants/"
	var image := get_viewport().get_texture().get_image()
	image.save_png(output + "godot-gameplay.png")
	for child in sandbox.get_children():
		if child is CanvasLayer:
			child.hide()
	get_tree().root.get_node("DebugOverlay").hide()
	var overview := Camera3D.new()
	sandbox.add_child(overview)
	overview.position = Vector3(50, 47, 60)
	overview.look_at(Vector3(0, 2, 0))
	overview.fov = 50
	overview.make_current()
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "godot-overview.png")
	print("Saved real engine screenshots to " + output)
	get_tree().quit()
