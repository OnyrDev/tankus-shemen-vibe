class_name TankAppearance
extends Node3D

## Shared armor recoloring and high-contrast 3D silhouette manager for playable tanks and lobby showroom.
## Preserves rubber, steel, optics and warning accents from the GLB while coordinating
## Fresnel rim + distance-scaled dark outline with Hit Flash and Wallhack overlays.

enum ViewerRelation {
	SHOWROOM,
	SELF,
	ALLY,
	ENEMY,
}

const OUTLINE_SHADER: Shader = preload("res://tank/tank_silhouette_outline.gdshader")
const FRESNEL_RIM_SHADER: Shader = preload("res://tank/tank_fresnel_rim.gdshader")

const OUTLINE_INK_ENEMY := Color(0.03, 0.038, 0.058, 1.0)
const OUTLINE_INK_DEFAULT := Color(0.04, 0.05, 0.075, 1.0)

static var _smooth_mesh_cache: Dictionary = {} # RID -> ArrayMesh
var _relation_check_timer: float = 0.0
var _cached_relation: int = -1

func _ready() -> void:
	_ensure_smooth_silhouette_meshes(self)
	var tracks := Node3D.new()
	tracks.set_script(preload("res://tank/track_animation.gd"))
	tracks.name = "TrackAnimation"
	add_child(tracks)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		for node in find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh and mesh.material_overlay != null:
				mesh.material_overlay = null

func _process(delta: float) -> void:
	_relation_check_timer += delta
	if _relation_check_timer < 0.2:
		return
	_relation_check_timer = 0.0

	var rel := _resolve_viewer_relation(self)
	if rel != _cached_relation:
		_cached_relation = rel
		var col: Color = get_meta("team_color") if has_meta("team_color") else Color(0.18, 0.55, 0.95)
		_apply_contrast_profile(self, col, rel)

static func is_silhouette_mesh(mesh: MeshInstance3D) -> bool:
	if not mesh or not mesh.mesh:
		return false
	if mesh.name == "ShieldMesh" or mesh.name == "LeftTrack" or mesh.name == "RightTrack":
		return false
	if mesh.name.begins_with("Wheel_"):
		return false
	return true

static func resolve_viewer_tank(tree: SceneTree) -> Tank:
	if not tree:
		return null

	var vp := tree.root
	if vp:
		var cam := vp.get_camera_3d()
		if cam:
			var p1 := cam.get_parent()
			var p2 := p1.get_parent() if p1 else null
			if p2 is TPSCamera and is_instance_valid((p2 as TPSCamera).target_node) and (p2 as TPSCamera).target_node is Tank:
				return (p2 as TPSCamera).target_node as Tank

	var my_peer: int = 1
	if tree.get_multiplayer() and tree.get_multiplayer().has_multiplayer_peer():
		my_peer = tree.get_multiplayer().get_unique_id()

	for node in tree.get_nodes_in_group("tanks"):
		var t := node as Tank
		if not t or not t.is_active:
			continue
		if t.net_sync and t.net_sync.is_local_owner():
			return t
		if t.peer_id == my_peer:
			return t
	return null

static func is_tank_enemy(candidate: Tank, viewer: Tank) -> bool:
	if not is_instance_valid(candidate) or not is_instance_valid(viewer):
		return false
	if candidate == viewer:
		return false
	if Game and Game.rules and Game.rules.is_team_mode:
		return candidate.team_id != viewer.team_id
	if candidate.peer_id != viewer.peer_id:
		return true
	return candidate.team_id != viewer.team_id

static func _resolve_viewer_relation(model: Node3D) -> ViewerRelation:
	if not model:
		return ViewerRelation.SHOWROOM
	var owner_tank := model.get_parent() as Tank
	if not owner_tank:
		return ViewerRelation.SHOWROOM
	var tree := model.get_tree()
	if not tree:
		return ViewerRelation.SHOWROOM
	var viewer := resolve_viewer_tank(tree)
	if not viewer:
		return ViewerRelation.ENEMY
	if owner_tank == viewer:
		return ViewerRelation.SELF
	if is_tank_enemy(owner_tank, viewer):
		return ViewerRelation.ENEMY
	return ViewerRelation.ALLY

static func _compute_vivid_rim_color(base_color: Color, is_enemy: bool) -> Color:
	var h := base_color.h
	var s := clampf(base_color.s * (1.12 if is_enemy else 0.95), 0.15, 1.0)
	if base_color.s < 0.08:
		s = 0.05
	var v := clampf(maxf(base_color.v, 0.82) * (1.15 if is_enemy else 1.05), 0.78, 1.0)
	return Color.from_hsv(h, s, v, 1.0).lightened(0.22 if is_enemy else 0.15)

static func _ensure_silhouette_materials(model: Node3D) -> ShaderMaterial:
	var rim_mat: ShaderMaterial = model.get_meta("silhouette_rim_mat") as ShaderMaterial if model.has_meta("silhouette_rim_mat") else null
	var outline_mat: ShaderMaterial = model.get_meta("silhouette_outline_mat") as ShaderMaterial if model.has_meta("silhouette_outline_mat") else null

	if not outline_mat:
		outline_mat = ShaderMaterial.new()
		outline_mat.shader = OUTLINE_SHADER
		model.set_meta("silhouette_outline_mat", outline_mat)

	if not rim_mat:
		rim_mat = ShaderMaterial.new()
		rim_mat.shader = FRESNEL_RIM_SHADER
		rim_mat.next_pass = outline_mat
		model.set_meta("silhouette_rim_mat", rim_mat)
	elif rim_mat.next_pass != outline_mat:
		rim_mat.next_pass = outline_mat

	return rim_mat

static func _apply_contrast_profile(model: Node3D, color: Color, relation: ViewerRelation) -> void:
	if not model:
		return
	var rim_mat := _ensure_silhouette_materials(model)
	var outline_mat: ShaderMaterial = model.get_meta("silhouette_outline_mat") as ShaderMaterial if model.has_meta("silhouette_outline_mat") else null
	if not rim_mat or not outline_mat:
		return

	match relation:
		ViewerRelation.SELF:
			rim_mat.set_shader_parameter("rim_color", _compute_vivid_rim_color(color, false))
			rim_mat.set_shader_parameter("rim_power", 3.8)
			rim_mat.set_shader_parameter("rim_strength", 0.18)
			outline_mat.set_shader_parameter("outline_color", OUTLINE_INK_DEFAULT)
			outline_mat.set_shader_parameter("near_width_m", 0.011)
			outline_mat.set_shader_parameter("far_width_m", 0.046)
		ViewerRelation.ENEMY:
			rim_mat.set_shader_parameter("rim_color", _compute_vivid_rim_color(color, true))
			rim_mat.set_shader_parameter("rim_power", 2.85)
			rim_mat.set_shader_parameter("rim_strength", 0.82)
			outline_mat.set_shader_parameter("outline_color", OUTLINE_INK_ENEMY)
			outline_mat.set_shader_parameter("near_width_m", 0.016)
			outline_mat.set_shader_parameter("far_width_m", 0.068)
		ViewerRelation.ALLY:
			rim_mat.set_shader_parameter("rim_color", _compute_vivid_rim_color(color, false))
			rim_mat.set_shader_parameter("rim_power", 3.2)
			rim_mat.set_shader_parameter("rim_strength", 0.48)
			outline_mat.set_shader_parameter("outline_color", OUTLINE_INK_DEFAULT)
			outline_mat.set_shader_parameter("near_width_m", 0.014)
			outline_mat.set_shader_parameter("far_width_m", 0.056)
		_:
			rim_mat.set_shader_parameter("rim_color", _compute_vivid_rim_color(color, false))
			rim_mat.set_shader_parameter("rim_power", 3.1)
			rim_mat.set_shader_parameter("rim_strength", 0.44)
			outline_mat.set_shader_parameter("outline_color", OUTLINE_INK_DEFAULT)
			outline_mat.set_shader_parameter("near_width_m", 0.013)
			outline_mat.set_shader_parameter("far_width_m", 0.052)

static func apply_team_color(model: Node3D, color: Color) -> void:
	if not model:
		return

	_ensure_smooth_silhouette_meshes(model)
	model.set_meta("team_color", color)

	var rim_mat := _ensure_silhouette_materials(model)
	var rel := _resolve_viewer_relation(model)
	if model is TankAppearance:
		(model as TankAppearance)._cached_relation = rel
	_apply_contrast_profile(model, color, rel)

	var active_wallhack: Material = model.get_meta("active_wallhack_overlay") as Material if model.has_meta("active_wallhack_overlay") else null
	var has_wallhack := active_wallhack != null and is_instance_valid(active_wallhack)

	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or mesh.name == "ShieldMesh":
			continue
		mesh.material_override = null

		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if not original:
				continue
			var is_enamel := original.resource_name.contains("Cobalt enamel")
			var is_dark_armor := original.resource_name.contains("Deep blue armor")
			if not is_enamel and not is_dark_armor:
				continue
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_color = color.darkened(0.42) if is_dark_armor else color
			material.metallic = 0.28
			material.roughness = 0.44
			material.rim_enabled = true
			material.rim = 0.35
			material.rim_tint = 0.35
			mesh.set_surface_override_material(surface, material)

		if is_silhouette_mesh(mesh):
			mesh.set_meta("base_silhouette_overlay", rim_mat)
			mesh.material_overlay = active_wallhack if has_wallhack else rim_mat
		else:
			if mesh.has_meta("base_silhouette_overlay"):
				mesh.remove_meta("base_silhouette_overlay")
			mesh.material_overlay = active_wallhack if has_wallhack else null

static func set_wallhack_overlay(model: Node3D, xray_mat: Material) -> void:
	if not model or not xray_mat:
		return
	model.set_meta("active_wallhack_overlay", xray_mat)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh and mesh.mesh and mesh.name != "ShieldMesh":
			mesh.material_overlay = xray_mat

static func clear_wallhack_overlay(model: Node3D, expected_xray_mat: Material = null) -> void:
	if not model:
		return
	var current_wh: Material = model.get_meta("active_wallhack_overlay") as Material if model.has_meta("active_wallhack_overlay") else null
	if expected_xray_mat != null and current_wh != null and current_wh != expected_xray_mat:
		return
	if model.has_meta("active_wallhack_overlay"):
		model.remove_meta("active_wallhack_overlay")
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh or not mesh.mesh or mesh.name == "ShieldMesh":
			continue
		if expected_xray_mat == null or mesh.material_overlay == expected_xray_mat:
			var base_overlay: Material = mesh.get_meta("base_silhouette_overlay") as Material if mesh.has_meta("base_silhouette_overlay") else null
			mesh.material_overlay = base_overlay

static func _ensure_smooth_silhouette_meshes(model: Node3D) -> void:
	if not model:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if not is_silhouette_mesh(mesh_inst):
			continue
		var src_mesh := mesh_inst.mesh as ArrayMesh
		if not src_mesh or (src_mesh.has_meta("has_smooth_outline_normals") and bool(src_mesh.get_meta("has_smooth_outline_normals"))):
			continue
		mesh_inst.mesh = _get_or_build_smooth_normal_mesh(src_mesh)

static func _get_or_build_smooth_normal_mesh(src_mesh: ArrayMesh) -> ArrayMesh:
	var key := src_mesh.get_rid()
	if _smooth_mesh_cache.has(key):
		var cached := _smooth_mesh_cache[key] as ArrayMesh
		if is_instance_valid(cached):
			return cached

	var surface_count := src_mesh.get_surface_count()
	if surface_count == 0:
		return src_mesh

	# Склеиваем нормали совпадающих по позиции вершин через все поверхности меша,
	# чтобы контур не расходился ни на острых 90-градусных углах, ни на стыках материалов.
	var normal_accum: Dictionary = {} # Vector3i -> Vector3
	var surface_arrays_list: Array[Array] = []

	for s in range(surface_count):
		var arrays := src_mesh.surface_get_arrays(s)
		surface_arrays_list.append(arrays)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if verts.is_empty() or norms.size() != verts.size():
			continue
		for i in range(verts.size()):
			var v := verts[i]
			var qkey := Vector3i(int(round(v.x * 2000.0)), int(round(v.y * 2000.0)), int(round(v.z * 2000.0)))
			var prev: Vector3 = normal_accum.get(qkey, Vector3.ZERO)
			normal_accum[qkey] = prev + norms[i]

	var new_mesh := ArrayMesh.new()
	new_mesh.resource_name = src_mesh.resource_name

	for s in range(surface_count):
		var arrays: Array = surface_arrays_list[s]
		var prim := src_mesh.surface_get_primitive_type(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if not verts.is_empty() and norms.size() == verts.size():
			var colors := PackedColorArray()
			colors.resize(verts.size())
			for i in range(verts.size()):
				var v := verts[i]
				var qkey := Vector3i(int(round(v.x * 2000.0)), int(round(v.y * 2000.0)), int(round(v.z * 2000.0)))
				var sum_n: Vector3 = normal_accum.get(qkey, norms[i])
				var smooth_n := sum_n.normalized() if sum_n.length_squared() > 0.00001 else norms[i].normalized()
				colors[i] = Color(smooth_n.x * 0.5 + 0.5, smooth_n.y * 0.5 + 0.5, smooth_n.z * 0.5 + 0.5, 0.25)
			arrays[Mesh.ARRAY_COLOR] = colors

		new_mesh.add_surface_from_arrays(prim, arrays)
		var surf_idx := new_mesh.get_surface_count() - 1
		new_mesh.surface_set_name(surf_idx, src_mesh.surface_get_name(s))
		new_mesh.surface_set_material(surf_idx, src_mesh.surface_get_material(s))

	new_mesh.set_meta("has_smooth_outline_normals", true)
	_smooth_mesh_cache[key] = new_mesh
	return new_mesh
