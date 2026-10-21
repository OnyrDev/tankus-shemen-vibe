class_name ShieldPulseVFX
extends Node3D

## Энергетический импульс при успешном блокировании снаряда щитом.

@onready var pulse_mesh: MeshInstance3D = $PulseMesh

func setup(color: Color = Color(0.2, 0.85, 1.0)) -> void:
	if pulse_mesh and pulse_mesh.material_override:
		var mat := pulse_mesh.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		pulse_mesh.material_override = mat

func _ready() -> void:
	if pulse_mesh:
		var mat := pulse_mesh.material_override as StandardMaterial3D
		var tween := create_tween().set_parallel(true)
		pulse_mesh.scale = Vector3(0.5, 0.5, 0.5)
		tween.tween_property(pulse_mesh, "scale", Vector3(1.8, 1.8, 1.8), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if mat:
			mat.albedo_color.a = 0.85
			tween.tween_property(mat, "albedo_color:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var cleanup := get_tree().create_timer(0.25)
	cleanup.timeout.connect(queue_free)
