class_name DustPuffVFX
extends Node3D

## Мультяшные клубы пыли при приземлении танка или резком заносе.

@onready var dust_particles: GPUParticles3D = $DustParticles

func setup(intensity: float = 1.0) -> void:
	scale = Vector3.ONE * clampf(intensity, 0.5, 2.5)

func _ready() -> void:
	if dust_particles:
		dust_particles.emitting = true
	var cleanup := get_tree().create_timer(0.55)
	cleanup.timeout.connect(queue_free)
