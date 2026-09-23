class_name BaseArena
extends Node3D

## Базовый класс для 3D арен TANKUS.
## Предоставляет интерфейс получения точек спавна, окружения и обработки падения в пропасть.

signal tank_fell(tank: Tank)

@export var arena_name: String = "Arena"
@export var spawn_points_container: Node3D = null
@export var kill_volume: Area3D = null

func _ready() -> void:
	if not spawn_points_container:
		spawn_points_container = get_node_or_null("SpawnPoints")
	if not kill_volume:
		kill_volume = get_node_or_null("KillVolume")

	if kill_volume and not kill_volume.body_entered.is_connected(_on_kill_volume_body_entered):
		kill_volume.body_entered.connect(_on_kill_volume_body_entered)

func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	if spawn_points_container:
		for child in spawn_points_container.get_children():
			if child is Marker3D:
				points.append(child)
	return points

func get_spawn_transform(index: int) -> Transform3D:
	var pts := get_spawn_points()
	if pts.is_empty():
		return global_transform
	return pts[index % pts.size()].global_transform

func _on_kill_volume_body_entered(body: Node3D) -> void:
	if body is Tank:
		tank_fell.emit(body as Tank)
