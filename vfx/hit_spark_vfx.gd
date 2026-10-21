class_name HitSparkVFX
extends Node3D

## Визуальный эффект рикошета и искр от столкновения снаряда.
## Направляет искры вдоль нормали столкновения и удаляется по таймеру.

@onready var sparks: GPUParticles3D = $Sparks
@onready var flash: MeshInstance3D = $Flash

func setup(normal: Vector3, color: Color = Color(1.0, 0.85, 0.25)) -> void:
	if normal.length_squared() > 0.01:
		# Ориентируем ось Z по нормали
		var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		look_at(global_position + normal, up)

	if flash and flash.material_override:
		var mat := flash.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		flash.material_override = mat

func _ready() -> void:
	if sparks:
		sparks.emitting = true

	if flash:
		var tween := create_tween()
		flash.scale = Vector3(1.2, 1.2, 1.2)
		tween.tween_property(flash, "scale", Vector3.ZERO, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var cleanup := get_tree().create_timer(0.3)
	cleanup.timeout.connect(queue_free)
