class_name Pendulum
extends Node3D

## Интерактивный физический маятник TANKUS.
## Подвешен на шарнире HingeJoint3D, раскачивается от выстрелов и толчков танков.

@export var initial_swing_impulse: float = 0.0
@export var swing_direction: Vector3 = Vector3.FORWARD

@onready var bob: RigidBody3D = get_node_or_null("Bob")

func _ready() -> void:
	if bob and initial_swing_impulse > 0.0:
		bob.apply_central_impulse(swing_direction.normalized() * initial_swing_impulse)
