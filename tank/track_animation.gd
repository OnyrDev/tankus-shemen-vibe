extends Node3D

## Cosmetic animation from actual chassis motion, including interpolated remote tanks.
## Distances are measured in world space, then converted to the source model's units.
const LEFT_MESH := preload("res://assets/tanks/cobalt_scout/track_l_animated.res")
const RIGHT_MESH := preload("res://assets/tanks/cobalt_scout/track_r_animated.res")
const BELT_SHADER := preload("res://tank/track_belt.gdshader")
const LOOP_LENGTH := 4.0 * 1.02 + TAU * 0.73

var _tank: Tank
var _tracks: Array[MeshInstance3D] = []
var _materials: Array[Array] = []
var _wheels: Array[Array] = []
var belt_distances: Array[float] = [0.0, 0.0]
var _last_position := Vector3.ZERO
var _last_yaw := 0.0

func _ready() -> void:
	process_priority = 50 # Sample after remote-tank interpolation.
	var visuals := get_parent() as Node3D
	_tank = visuals.get_parent() as Tank
	for side in range(2):
		var track := visuals.get_node("LeftTrack" if side == 0 else "RightTrack") as MeshInstance3D
		track.mesh = LEFT_MESH if side == 0 else RIGHT_MESH
		track.custom_aabb = track.mesh.get_aabb().grow(0.04)
		_tracks.append(track)
		var materials: Array = []
		for surface in range(track.mesh.get_surface_count()):
			var original := track.mesh.surface_get_material(surface) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = BELT_SHADER
			material.set_shader_parameter("base_color", original.albedo_color)
			material.set_shader_parameter("metalness", original.metallic)
			material.set_shader_parameter("surface_roughness", original.roughness)
			track.set_surface_override_material(surface, material)
			materials.append(material)
		_materials.append(materials)
		var wheels: Array = []
		for child in track.get_children():
			if child is MeshInstance3D and child.name.begins_with("Wheel_"):
				wheels.append({"node": child, "rest_basis": child.basis, "radius": child.get_aabb().size.y * 0.5, "angle": 0.0})
		_wheels.append(wheels)
	if _tank:
		_last_position = _tank.global_position
		_last_yaw = _tank.rotation.y
	else:
		set_process(false) # Showroom models keep their stationary pose.

func _process(delta: float) -> void:
	if not is_instance_valid(_tank):
		return
	var displacement := _tank.global_position - _last_position
	var yaw_delta := wrapf(_tank.rotation.y - _last_yaw, -PI, PI)
	var mid_yaw := _last_yaw + yaw_delta * 0.5
	_last_position = _tank.global_position
	_last_yaw = _tank.rotation.y
	if not _tank.is_active or _tank.is_frozen or not _tank.visuals.is_visible_in_tree():
		return
	# Respawns and network corrections must not spin the tracks through a teleport.
	if displacement.length() > 3.0 or absf(yaw_delta) > PI * 0.75:
		return
	if _tank.is_on_floor():
		displacement -= _tank.get_platform_velocity() * delta
	var forward := Vector3(-sin(mid_yaw), 0.0, -cos(mid_yaw))
	advance_motion(displacement.dot(forward), yaw_delta)

func advance_motion(forward_distance: float, yaw_delta: float) -> void:
	for side in range(_tracks.size()):
		var track := _tracks[side]
		# Imported L/R names are mirrored by the model's 180-degree orientation.
		# Use actual lateral positions rather than assuming which named side is left.
		var source_x := -1.33 if side == 0 else 1.33
		var lateral_offset := 0.0
		if _tank:
			lateral_offset = _tank.to_local(track.to_global(Vector3(source_x, 0.75, 0.0))).x
		var travel := forward_distance + yaw_delta * lateral_offset
		if absf(travel) < 0.000001:
			continue
		var model_scale := track.global_basis.z.length()
		var source_distance := travel / maxf(model_scale, 0.001)
		belt_distances[side] = fposmod(belt_distances[side] + source_distance, LOOP_LENGTH)
		for material: ShaderMaterial in _materials[side]:
			material.set_shader_parameter("belt_distance", belt_distances[side])
		for wheel: Dictionary in _wheels[side]:
			wheel.angle = fposmod(wheel.angle + source_distance / wheel.radius, TAU)
			wheel.node.basis = Basis(Vector3.RIGHT, wheel.angle) * wheel.rest_basis
