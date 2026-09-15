class_name TestSandbox
extends Node3D

## Скрипт тестовой песочницы Phase 3 (Карточная система, Рикошет, Бой).

@onready var tank: Tank = $Tank
@onready var dummy_tank: Tank = get_node_or_null("DummyTank")
@onready var camera: TPSCamera = $TPSCamera
@onready var spawn_marker: Marker3D = $SpawnPoint
@onready var dummy_spawn_marker: Marker3D = get_node_or_null("DummySpawnPoint")
@onready var kill_volume: Area3D = $KillVolume
@onready var hud: HUD = get_node_or_null("HUD")
@onready var card_draft: CardDraft = get_node_or_null("CardDraft")

func _ready() -> void:
	if kill_volume:
		kill_volume.body_entered.connect(_on_kill_volume_body_entered)

	if tank and camera:
		camera.target_node = tank

	if spawn_marker and tank:
		tank.spawn_point = spawn_marker.global_transform
		tank.global_transform = spawn_marker.global_transform

	if dummy_tank:
		dummy_tank.team_id = 1
		dummy_tank.set_team_color(Color(0.95, 0.25, 0.25))
		if dummy_tank.input:
			dummy_tank.input.enabled = false
		if dummy_spawn_marker:
			dummy_tank.spawn_point = dummy_spawn_marker.global_transform
			dummy_tank.global_transform = dummy_spawn_marker.global_transform

	if hud and tank:
		hud.bind_to_tank(tank)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_BACKSPACE:
			_respawn_all()
		elif event.keycode == KEY_TAB:
			if card_draft and tank:
				if card_draft.visible:
					card_draft.close_draft()
				else:
					card_draft.open_draft(tank)

func _on_kill_volume_body_entered(body: Node3D) -> void:
	if body is Tank:
		body.fell_into_void.emit()
		if body == tank:
			_respawn_tank()
		elif body == dummy_tank and dummy_spawn_marker:
			dummy_tank.respawn(dummy_spawn_marker.global_transform)

func _respawn_tank() -> void:
	if tank and spawn_marker:
		tank.respawn(spawn_marker.global_transform)
		if camera:
			camera.global_position = spawn_marker.global_position + camera.target_offset

func _respawn_all() -> void:
	_respawn_tank()
	if dummy_tank and dummy_spawn_marker:
		dummy_tank.respawn(dummy_spawn_marker.global_transform)
