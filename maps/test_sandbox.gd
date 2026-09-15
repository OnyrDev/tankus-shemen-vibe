extends Node3D

## Скрипт тестовой песочницы в режиме от третьего лица (TPS).

@onready var tank: Tank = $Tank
@onready var camera: TPSCamera = $TPSCamera
@onready var spawn_marker: Marker3D = $SpawnPoint
@onready var kill_volume: Area3D = $KillVolume

func _ready() -> void:
	if kill_volume:
		kill_volume.body_entered.connect(_on_kill_volume_body_entered)

	if tank and camera:
		camera.target_node = tank

	if spawn_marker and tank:
		tank.spawn_point = spawn_marker.global_transform
		tank.global_transform = spawn_marker.global_transform

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_BACKSPACE:
			_respawn_tank()

func _on_kill_volume_body_entered(body: Node3D) -> void:
	if body is Tank:
		body.fell_into_void.emit()
		_respawn_tank()

func _respawn_tank() -> void:
	if tank and spawn_marker:
		tank.respawn(spawn_marker.global_transform)
		if camera:
			camera.global_position = spawn_marker.global_position + camera.target_offset
