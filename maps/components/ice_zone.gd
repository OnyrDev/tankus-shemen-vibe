class_name IceZone
extends Area3D

## Интерактивная зона ледяной поверхности TANKUS.
## При въезде танка снижает трение (ускорение и торможение), заставляя танк дрифтовать по инерции.

var _tanks_inside: Array[Tank] = []

func _ready() -> void:
	# Слой танков — 2
	collision_layer = 0
	collision_mask = 2

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body is Tank:
		var t := body as Tank
		if not _tanks_inside.has(t):
			_tanks_inside.append(t)
		t.set_on_ice(true)

func _on_body_exited(body: Node3D) -> void:
	if body is Tank:
		var t := body as Tank
		_tanks_inside.erase(t)
		t.set_on_ice(false)

func _exit_tree() -> void:
	for t in _tanks_inside:
		if is_instance_valid(t):
			t.set_on_ice(false)
	_tanks_inside.clear()
