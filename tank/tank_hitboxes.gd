class_name TankHitboxes
extends AnimatableBody3D

## Armor hitboxes follow the visible hull, tracks, turret and barrel independently
## of the compact capsule used for driving over ramps and around obstacles.
var _tank: Tank
var _meshes: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []

func _ready() -> void:
	_tank = get_parent() as Tank
	collision_mask = 0
	sync_to_physics = false
	process_physics_priority = 100
	if not _tank or not _tank.visuals:
		return
	for node in _tank.visuals.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or mesh.name == "ShieldMesh":
			continue
		var shape := mesh.mesh.create_convex_shape()
		if not shape:
			continue
		var collision := CollisionShape3D.new()
		collision.shape = shape
		add_child(collision)
		_meshes.append(mesh)
		_shapes.append(collision)
	update_hitboxes()

func _physics_process(_delta: float) -> void:
	update_hitboxes()

func update_hitboxes() -> void:
	if not is_instance_valid(_tank):
		return
	collision_layer = ShotGeometry.TANK_LAYER if _tank.is_active and _tank.is_visible_in_tree() else 0
	var inverse := global_transform.affine_inverse()
	for index in range(_meshes.size()):
		_shapes[index].transform = inverse * _meshes[index].global_transform
