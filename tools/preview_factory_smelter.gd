extends Node3D

## Рендерит скриншоты реального движка Godot (gameplay и overview) для карты Factory Smelter.
## Запуск: godot --path . res://tools/preview_factory_smelter.tscn
func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	call_deferred("_preview")

func _preview() -> void:
	Game.rules.selected_map = "factory_smelter"
	Game.is_solo_practice = true
	var sandbox := (load("res://maps/test_sandbox.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(sandbox)
	for frame in range(12):
		await get_tree().physics_frame
	
	sandbox.tank.position = Vector3(0.0, 0.5, -12.5)
	sandbox.tank.rotation = Vector3(0, deg_to_rad(135), 0)
	if sandbox.dummy_tank:
		sandbox.dummy_tank.position = Vector3(4.0, 2.0, -10.0)
	
	sandbox.camera.setup_target(sandbox.tank)
	sandbox.camera.pitch = deg_to_rad(18)
	sandbox.camera.spring_arm.rotation.x = -sandbox.camera.pitch
	sandbox.camera.spring_arm.rotation.y = deg_to_rad(-40)
	for frame in range(35):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	
	var output := "res://docs/concepts/factory/"
	var image := get_viewport().get_texture().get_image()
	image.save_png(output + "godot-gameplay.png")
	
	for child in sandbox.get_children():
		if child is CanvasLayer:
			child.hide()
	var debug_overlay := get_tree().root.get_node_or_null("DebugOverlay")
	if debug_overlay:
		debug_overlay.hide()
	
	var overview := Camera3D.new()
	sandbox.add_child(overview)
	overview.position = Vector3(40, 38, 48)
	overview.look_at(Vector3(4.0, 1.0, 0.0))
	overview.fov = 48
	overview.make_current()
	for frame in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "godot-overview.png")
	print("Saved real engine screenshots to " + output)
	get_tree().quit()
