extends RefCounted

## Tag each rigid tread with its initial distance around the capsule-shaped belt.
## UV2.y distinguishes moving links from the continuous rubber backing.
const RADIUS := 0.73
const HALF_LENGTH := 1.02
const CENTER_Y := 0.75
const LINK_COUNT := 36
const LOOP_LENGTH := 4.0 * HALF_LENGTH + TAU * RADIUS

func generate(source: Node) -> void:
	for side in ["L", "R"]:
		var source_mesh := (source.find_child("Track_" + side, true, false) as MeshInstance3D).mesh
		var tagged := ArrayMesh.new()
		var link_groups := 0
		for surface in range(source_mesh.get_surface_count()):
			var arrays := source_mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var parents: Array[int] = []
			var positions := {}
			for vertex in vertices:
				var key := vertex.snapped(Vector3.ONE * 0.0001)
				if not positions.has(key):
					positions[key] = parents.size()
					parents.append(parents.size())
			var vertex_ids: Array[int] = []
			for vertex in vertices:
				vertex_ids.append(positions[vertex.snapped(Vector3.ONE * 0.0001)])
			for i in range(0, indices.size(), 3):
				var root := _find(parents, vertex_ids[indices[i]])
				parents[_find(parents, vertex_ids[indices[i + 1]])] = root
				parents[_find(parents, vertex_ids[indices[i + 2]])] = root
			var groups := {}
			for i in vertices.size():
				var root := _find(parents, vertex_ids[i])
				if not groups.has(root):
					groups[root] = []
				groups[root].append(i)
			var uv2 := PackedVector2Array()
			uv2.resize(vertices.size())
			for group: Array in groups.values():
				var bounds := AABB(vertices[group[0]], Vector3.ZERO)
				for index: int in group:
					bounds = bounds.expand(vertices[index])
				if bounds.size.y > 1.0 and bounds.size.z > 3.0:
					continue # Continuous backing stays still.
				var distance := _distance_at(bounds.get_center())
				# All 36 links share an exact spacing; rubber pads and metal shoes
				# must receive the same phase to remain attached at curved ends.
				var step := LOOP_LENGTH / LINK_COUNT
				distance = fposmod(2.0 * HALF_LENGTH + round((distance - 2.0 * HALF_LENGTH) / step) * step, LOOP_LENGTH)
				for index: int in group:
					uv2[index] = Vector2(distance, 1.0)
				link_groups += 1
			arrays[Mesh.ARRAY_TEX_UV2] = uv2
			tagged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			tagged.surface_set_material(surface, source_mesh.surface_get_material(surface))
		assert(link_groups == LINK_COUNT * 2, "Expected 36 metal shoes and 36 rubber pads")
		assert(ResourceSaver.save(tagged, "res://assets/tanks/cobalt_scout/track_%s_animated.res" % side.to_lower(), ResourceSaver.FLAG_COMPRESS) == OK)

func _find(parents: Array[int], id: int) -> int:
	while parents[id] != id:
		parents[id] = parents[parents[id]]
		id = parents[id]
	return id

func _distance_at(point: Vector3) -> float:
	if point.z > HALF_LENGTH:
		return 2.0 * HALF_LENGTH + RADIUS * atan2(point.z - HALF_LENGTH, point.y - CENTER_Y)
	if point.z < -HALF_LENGTH:
		var angle := fposmod(atan2(point.z + HALF_LENGTH, point.y - CENTER_Y), TAU)
		return 4.0 * HALF_LENGTH + PI * RADIUS + RADIUS * (angle - PI)
	if point.y >= CENTER_Y:
		return point.z + HALF_LENGTH
	return 2.0 * HALF_LENGTH + PI * RADIUS + HALF_LENGTH - point.z
