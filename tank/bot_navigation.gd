class_name BotNavigation
extends Node

## Серверный граф проходимых поверхностей. Несколько этажей в одной ячейке
## сохраняются отдельно; связи проверяют опору, уклон и свободный проход.
const CELL_SIZE: float = 2.0
var graph := AStar3D.new()
var is_built: bool = false
var _cells: Dictionary = {}
var _space: PhysicsDirectSpaceState3D
var _clearance := SphereShape3D.new()

func _ready() -> void:
	add_to_group("bot_navigation")
	if not Network.is_server():
		return
	# Коллизии новой арены должны попасть в физический мир.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_inside_tree():
		_build_graph()

func _build_graph() -> void:
	var arena := get_parent() as BaseArena
	if arena == null:
		return
	_space = arena.get_world_3d().direct_space_state
	_clearance.radius = 0.5
	var points := arena.get_spawn_points()
	if points.is_empty():
		return
	var low := points[0].global_position
	var high := low
	for point in points:
		low = low.min(point.global_position)
		high = high.max(point.global_position)
	var min_x := floori((low.x - 10.0) / CELL_SIZE)
	var max_x := ceili((high.x + 10.0) / CELL_SIZE)
	var min_z := floori((low.z - 10.0) / CELL_SIZE)
	var max_z := ceili((high.z + 10.0) / CELL_SIZE)
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var cell := Vector2i(x, z)
			var from := Vector3(x * CELL_SIZE, high.y + 12.0, z * CELL_SIZE)
			var bottom := Vector3(from.x, low.y - 10.0, from.z)
			for layer in range(4):
				var hit := _ray(from, bottom)
				if hit.is_empty():
					break
				var position: Vector3 = hit.position
				if hit.normal.y >= 0.57 and _has_clearance(position):
					var id := graph.get_available_point_id()
					graph.add_point(id, position + Vector3.UP * 0.05)
					if not _cells.has(cell):
						_cells[cell] = []
					_cells[cell].append(id)
				# Продолжаем под настилом, не принимая нижнюю грань пола за поверхность.
				from.y = position.y - 0.15
				if from.y <= bottom.y:
					break
	for cell in _cells:
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var neighbour: Vector2i = cell + offset
			if not _cells.has(neighbour):
				continue
			for first in _cells[cell]:
				for second in _cells[neighbour]:
					var a := graph.get_point_position(first)
					var b := graph.get_point_position(second)
					if _can_connect(a, b):
						graph.connect_points(first, second)
					elif _can_drop(a, b):
						graph.connect_points(first, second, false)
					elif _can_drop(b, a):
						graph.connect_points(second, first, false)
	is_built = true

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.hit_back_faces = false
	return _space.intersect_ray(query)

func _has_clearance(position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.transform.origin = position + Vector3.UP * 0.95
	query.collision_mask = 1
	return _space.intersect_shape(query, 1).is_empty()

func _can_connect(a: Vector3, b: Vector3) -> bool:
	var horizontal := Vector2(a.x - b.x, a.z - b.z).length()
	if absf(a.y - b.y) > horizontal * 1.15:
		return false
	if not _ray(a + Vector3.UP * 0.85, b + Vector3.UP * 0.85).is_empty():
		return false
	var middle := (a + b) * 0.5
	var support := _ray(middle + Vector3.UP * 0.6, middle - Vector3.UP * 1.1)
	return not support.is_empty() and support.normal.y >= 0.57 and _has_clearance(middle)

## С высоких стартовых террас можно безопасно спуститься, но обратная
## связь не создаётся: обычный танк не умеет взбираться на отвесную стену.
func _can_drop(from: Vector3, to: Vector3) -> bool:
	var drop := from.y - to.y
	if drop < 0.9 or drop > 3.0:
		return false
	var over_landing := Vector3(to.x, from.y + 0.85, to.z)
	return _ray(from + Vector3.UP * 0.85, over_landing).is_empty() and _ray(over_landing, to + Vector3.UP * 0.1).is_empty()

func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not is_built or graph.get_point_count() == 0:
		return PackedVector3Array()
	var first := graph.get_closest_point(from)
	var last := graph.get_closest_point(to)
	return graph.get_point_path(first, last, true)

## Ищем достижимую позицию для стрельбы, а не саму позицию врага.
## Это позволяет атаковать танк на террасе, на которую нельзя взобраться.
func find_firing_path(from: Vector3, target: Vector3, preferred_range: float) -> PackedVector3Array:
	if not is_built or graph.get_point_count() == 0:
		return PackedVector3Array()
	var away := Vector3(from.x - target.x, 0, from.z - target.z).normalized()
	if away.length_squared() < 0.1:
		away = Vector3.FORWARD
	var start := graph.get_closest_point(from)
	for extra in [0.0, 6.0, 12.0]:
		for angle in [0.0, 0.7, -0.7, 1.4, -1.4, PI]:
			var candidate: Vector3 = target + away.rotated(Vector3.UP, angle) * (preferred_range + extra)
			candidate.y = from.y
			var end := graph.get_closest_point(candidate)
			var position := graph.get_point_position(end)
			var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.5, target + Vector3.UP * 0.4, 9)
			if not _space.intersect_ray(query).is_empty():
				continue
			var route := graph.get_point_path(start, end, true)
			if not route.is_empty() and route[-1].distance_to(position) < 0.1:
				return route
	return PackedVector3Array()
