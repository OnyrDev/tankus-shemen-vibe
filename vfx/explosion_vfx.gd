class_name ExplosionVFX
extends Node3D

## Мультяшный многослойный визуальный эффект взрыва.
## Включает расширяющуюся огненную сферу, кольцо ударной волны,
## разлетающиеся искры и яркую световую вспышку OmniLight3D.

@onready var fireball: MeshInstance3D = $Fireball
@onready var shockwave: MeshInstance3D = $Shockwave
@onready var light: OmniLight3D = $OmniLight3D
@onready var sparks: GPUParticles3D = $Sparks

func setup(scale_factor: float = 1.0, custom_color: Color = Color(1.0, 0.55, 0.15)) -> void:
	scale = Vector3.ONE * scale_factor

	if fireball and fireball.material_override:
		var mat := fireball.material_override.duplicate() as StandardMaterial3D
		mat.albedo_color = custom_color
		fireball.material_override = mat

	if light:
		light.light_color = custom_color
		light.omni_range = 7.0 * scale_factor

func _ready() -> void:
	if sparks:
		sparks.emitting = true

	var tween := create_tween().set_parallel(true)

	if fireball:
		fireball.scale = Vector3(0.2, 0.2, 0.2)
		var fire_mat := fireball.material_override as StandardMaterial3D
		if fire_mat:
			fire_mat.albedo_color.a = 0.95
			tween.tween_property(fireball, "scale", Vector3(1.8, 1.8, 1.8), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(fire_mat, "albedo_color:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if shockwave:
		shockwave.scale = Vector3(0.1, 0.1, 0.1)
		var wave_mat := shockwave.material_override as StandardMaterial3D
		if wave_mat:
			wave_mat.albedo_color.a = 0.9
			tween.tween_property(shockwave, "scale", Vector3(2.6, 0.2, 2.6), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(wave_mat, "albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	if light:
		light.light_energy = 4.5
		tween.tween_property(light, "light_energy", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Автоматическое удаление после завершения всех эффектов
	var cleanup_timer := get_tree().create_timer(0.5)
	cleanup_timer.timeout.connect(queue_free)
