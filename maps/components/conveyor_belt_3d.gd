@tool
class_name ConveyorBelt3D
extends Path3D

## Интерактивный процедурный 3D-конвейер TANKUS на базе Path3D.
## Автоматически генерирует визуальную геометрию полотна и цепочку физических тел
## с постоянной линейной скоростью (constant_linear_velocity) вдоль изгиба кривой.

@export var belt_width: float = 3.2:
	set(val):
		belt_width = maxf(0.5, val)
		_request_rebuild()

@export var speed: float = 6.0:
	set(val):
		speed = val
		_request_rebuild()

@export var reverse_direction: bool = false:
	set(val):
		reverse_direction = val
		_request_rebuild()

@export var segment_length: float = 1.6:
	set(val):
		segment_length = maxf(0.5, val)
		_request_rebuild()

@export var thickness: float = 0.25:
	set(val):
		thickness = maxf(0.05, val)
		_request_rebuild()

@export var show_gears: bool = false:
	set(val):
		show_gears = val
		_update_material()

@export var is_hazard: bool = true:
	set(val):
		is_hazard = val
		_update_material()

const BELT_SHADER := preload("res://maps/materials/conveyor_belt.gdshader")

var _mesh_instance: MeshInstance3D = null
var _collisions_container: Node3D = null
var _material: ShaderMaterial = null
var _is_rebuilding: bool = false

func _ready() -> void:
	if not curve:
		curve = Curve3D.new()
		curve.add_point(Vector3(0, 0, 0))
		curve.add_point(Vector3(0, 0, -10))
	
	if not curve.changed.is_connected(_on_curve_changed):
		curve.changed.connect(_on_curve_changed)
	
	_setup_nodes()
	rebuild()

func _setup_nodes() -> void:
	_mesh_instance = get_node_or_null("BeltMesh") as MeshInstance3D
	if not _mesh_instance:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "BeltMesh"
		add_child(_mesh_instance)
	
	_collisions_container = get_node_or_null("Collisions") as Node3D
	if not _collisions_container:
		_collisions_container = Node3D.new()
		_collisions_container.name = "Collisions"
		add_child(_collisions_container)
	
	if not _material:
		_material = ShaderMaterial.new()
		_material.shader = BELT_SHADER
		_update_material()
	_mesh_instance.material_override = _material

func _update_material() -> void:
	if not _material:
		return
	var effective_speed := -speed if reverse_direction else speed
	_material.set_shader_parameter("speed", effective_speed)
	_material.set_shader_parameter("show_gears", show_gears)
	_material.set_shader_parameter("is_hazard_stripes", is_hazard)

func _on_curve_changed() -> void:
	_request_rebuild()

func _request_rebuild() -> void:
	if _is_rebuilding:
		return
	_is_rebuilding = true
	call_deferred("_do_rebuild")

func _do_rebuild() -> void:
	_is_rebuilding = false
	if not is_inside_tree() or not curve:
		return
	_setup_nodes()
	rebuild()

func rebuild() -> void:
	if not curve or curve.point_count < 2:
		return
	_setup_nodes()
	_update_material()
	_build_mesh()
	_build_collisions()

func _build_mesh() -> void:
	var total_len := curve.get_baked_length()
	if total_len < 0.1:
		return
	
	var steps := maxi(2, int(ceil(total_len / segment_length)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _material:
		st.set_material(_material)
	
	var half_w := belt_width * 0.5
	var half_h := thickness * 0.5
	
	for i in range(steps):
		var d0 := (float(i) / float(steps)) * total_len
		var d1 := (float(i + 1) / float(steps)) * total_len
		
		var p0 := curve.sample_baked(d0)
		var p1 := curve.sample_baked(d1)
		
		var t0 := _get_tangent(d0, total_len)
		var t1 := _get_tangent(d1, total_len)
		
		var b0 := t0.cross(Vector3.UP).normalized() * half_w
		var b1 := t1.cross(Vector3.UP).normalized() * half_w
		
		# Top surface quad vertices
		var top_l0 := p0 - b0 + Vector3.UP * half_h
		var top_r0 := p0 + b0 + Vector3.UP * half_h
		var top_l1 := p1 - b1 + Vector3.UP * half_h
		var top_r1 := p1 + b1 + Vector3.UP * half_h
		
		var normal := Vector3.UP
		
		# Top surface quad vertices (Clockwise winding for Godot front-face)
		st.set_normal(normal)
		st.set_uv(Vector2(0.0, d0))
		st.add_vertex(top_l0)
		
		st.set_normal(normal)
		st.set_uv(Vector2(0.0, d1))
		st.add_vertex(top_l1)
		
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, d1))
		st.add_vertex(top_r1)
		
		st.set_normal(normal)
		st.set_uv(Vector2(0.0, d0))
		st.add_vertex(top_l0)
		
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, d1))
		st.add_vertex(top_r1)
		
		st.set_normal(normal)
		st.set_uv(Vector2(1.0, d0))
		st.add_vertex(top_r0)
		
		# Side casing skirt (left)
		var bot_l0 := p0 - b0 - Vector3.UP * half_h
		var bot_l1 := p1 - b1 - Vector3.UP * half_h
		var norm_l := -b0.normalized()
		
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.0, d0))
		st.add_vertex(top_l0)
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.0, d1))
		st.add_vertex(top_l1)
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.1, d1))
		st.add_vertex(bot_l1)
		
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.0, d0))
		st.add_vertex(top_l0)
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.1, d1))
		st.add_vertex(bot_l1)
		st.set_normal(norm_l)
		st.set_uv(Vector2(0.1, d0))
		st.add_vertex(bot_l0)
		
		# Side casing skirt (right)
		var bot_r0 := p0 + b0 - Vector3.UP * half_h
		var bot_r1 := p1 + b1 - Vector3.UP * half_h
		var norm_r := b0.normalized()
		
		st.set_normal(norm_r)
		st.set_uv(Vector2(1.0, d0))
		st.add_vertex(top_r0)
		st.set_normal(norm_r)
		st.set_uv(Vector2(0.9, d1))
		st.add_vertex(bot_r1)
		st.set_normal(norm_r)
		st.set_uv(Vector2(1.0, d1))
		st.add_vertex(top_r1)
		
		st.set_normal(norm_r)
		st.set_uv(Vector2(1.0, d0))
		st.add_vertex(top_r0)
		st.set_normal(norm_r)
		st.set_uv(Vector2(0.9, d0))
		st.add_vertex(bot_r0)
		st.set_normal(norm_r)
		st.set_uv(Vector2(0.9, d1))
		st.add_vertex(bot_r1)
	
	_mesh_instance.mesh = st.commit()

func _build_collisions() -> void:
	if not _collisions_container:
		return
	
	# Clear previous segment collision bodies
	for child in _collisions_container.get_children():
		child.free()
	
	var total_len := curve.get_baked_length()
	if total_len < 0.1:
		return
	
	var steps := maxi(1, int(ceil(total_len / segment_length)))
	var effective_speed := -speed if reverse_direction else speed
	
	for i in range(steps):
		var d0 := (float(i) / float(steps)) * total_len
		var d1 := (float(i + 1) / float(steps)) * total_len
		var p0 := curve.sample_baked(d0)
		var p1 := curve.sample_baked(d1)
		
		var delta_vec := p1 - p0
		var seg_len := delta_vec.length()
		if seg_len < 0.01:
			continue
		
		var tangent := delta_vec.normalized()
		var center := (p0 + p1) * 0.5
		
		var body := StaticBody3D.new()
		body.name = "Segment_%02d" % i
		body.collision_layer = 1
		body.collision_mask = 0
		body.constant_linear_velocity = tangent * effective_speed
		
		var shape := BoxShape3D.new()
		shape.size = Vector3(belt_width, thickness, seg_len)
		
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		
		_collisions_container.add_child(body)
		
		# Align body position and orientation
		if absf(tangent.dot(Vector3.UP)) < 0.99:
			body.look_at_from_position(center, center + tangent, Vector3.UP)
		else:
			body.position = center

func _get_tangent(dist: float, total_len: float) -> Vector3:
	var delta := 0.2
	var p_curr := curve.sample_baked(dist)
	if dist + delta <= total_len:
		var p_next := curve.sample_baked(dist + delta)
		var diff := p_next - p_curr
		if diff.length_squared() > 0.0001:
			return diff.normalized()
	if dist - delta >= 0.0:
		var p_prev := curve.sample_baked(dist - delta)
		var diff := p_curr - p_prev
		if diff.length_squared() > 0.0001:
			return diff.normalized()
	return Vector3.FORWARD
