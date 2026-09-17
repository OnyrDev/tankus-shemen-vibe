class_name TankOverheadManager
extends CanvasLayer

## Менеджер World-Space индикаторов танков.
## Отслеживает появление танков в контейнере и инстанциирует для них плашки OverheadUI.

@export var tanks_container: Node3D = null
var _overhead_scene: PackedScene = preload("res://tank/tank_overhead_ui.tscn")
var _tank_ui_map: Dictionary = {} # Tank -> TankOverheadUI

func _ready() -> void:
	layer = 5 # Поверх 3D мира, но под HUD и меню
	process_mode = Node.PROCESS_MODE_ALWAYS

	if tanks_container:
		setup_container(tanks_container)

func setup_container(container: Node3D) -> void:
	tanks_container = container
	if not tanks_container.child_entered_tree.is_connected(_on_child_entered):
		tanks_container.child_entered_tree.connect(_on_child_entered)
	if not tanks_container.child_exiting_tree.is_connected(_on_child_exiting):
		tanks_container.child_exiting_tree.connect(_on_child_exiting)

	# Привязываем уже существующие танки
	for child in tanks_container.get_children():
		if child is Tank:
			_create_overhead_for_tank(child)

func _on_child_entered(node: Node) -> void:
	if node is Tank:
		await get_tree().process_frame
		if is_instance_valid(node) and node.is_inside_tree():
			_create_overhead_for_tank(node as Tank)

func _on_child_exiting(node: Node) -> void:
	if node is Tank and _tank_ui_map.has(node):
		var ui: Control = _tank_ui_map[node]
		if is_instance_valid(ui):
			ui.queue_free()
		_tank_ui_map.erase(node)

func _create_overhead_for_tank(tank: Tank) -> void:
	if _tank_ui_map.has(tank) and is_instance_valid(_tank_ui_map[tank]):
		return

	var overhead: TankOverheadUI = _overhead_scene.instantiate() as TankOverheadUI
	add_child(overhead)
	overhead.bind_tank(tank)
	_tank_ui_map[tank] = overhead
