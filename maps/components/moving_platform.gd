class_name MovingPlatform
extends AnimatableBody3D

## Движущаяся тактическая платформа TANKUS.
## Основана на AnimatableBody3D с sync_to_physics для корректного переноса танков без соскальзывания.

@export var travel_offset: Vector3 = Vector3(0, 0, 16.0)
@export var travel_time: float = 4.0
@export var wait_time: float = 1.2
@export var start_delay: float = 0.0

var _start_pos: Vector3 = Vector3.ZERO
var _target_pos: Vector3 = Vector3.ZERO
var _tween: Tween = null

func _ready() -> void:
	sync_to_physics = true
	_start_pos = global_position
	_target_pos = _start_pos + travel_offset

	if start_delay > 0.0:
		get_tree().create_timer(start_delay).timeout.connect(_start_motion)
	else:
		_start_motion()

func _start_motion() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween().set_loops()
	_tween.tween_property(self, "global_position", _target_pos, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(wait_time)
	_tween.tween_property(self, "global_position", _start_pos, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_interval(wait_time)
