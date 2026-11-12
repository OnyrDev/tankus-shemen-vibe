class_name ShotGeometry
extends RefCounted

## Extra surfaces for aiming and projectiles; tanks keep their movement colliders.
const SURFACE_LAYER: int = 16
const TANK_LAYER: int = 32
const WORLD_MASK: int = 1 | 8 | SURFACE_LAYER
const COLLISION_MASK: int = WORLD_MASK | 2 | TANK_LAYER

static func add_arena_surfaces(arena: Node) -> void:
	_add_surfaces(arena, {})

static func _add_surfaces(node: Node, shapes: Dictionary) -> void:
	# Existing world bodies and interactive props already own their collision shapes.
	# Never turn trigger volumes or their visual effects into solid obstacles.
	if node is CollisionObject3D:
		return
	for child in node.get_children():
		_add_surfaces(child, shapes)
	if not node is MeshInstance3D:
		return
	var instance := node as MeshInstance3D
	if not instance.mesh or not instance.is_visible_in_tree() or instance.has_node("ShotSurface"):
		return
	if not shapes.has(instance.mesh):
		var shape := instance.mesh.create_trimesh_shape()
		if shape:
			shape.backface_collision = true
		shapes[instance.mesh] = shape
	var shape := shapes[instance.mesh] as ConcavePolygonShape3D
	if not shape:
		return
	var body := StaticBody3D.new()
	body.name = "ShotSurface"
	body.collision_layer = SURFACE_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	instance.add_child(body)
