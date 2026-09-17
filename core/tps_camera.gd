class_name TPSCamera
extends Node3D

## Орбитальная камера от третьего лица (TPS) с пружинным подвесом SpringArm3D.
## Синхронизирована с физическим циклом во избежание джиттера.

signal spectate_target_changed(target_node: Node3D)

@export var target_node: Node3D = null
@export var mouse_sensitivity: float = 0.003
@export var min_pitch_deg: float = -30.0 # наклон вверх (взгляд вниз)
@export var max_pitch_deg: float = 50.0  # наклон вниз (взгляд вверх)
@export var target_offset: Vector3 = Vector3(0.0, 1.8, 0.0)
@export var smooth_speed: float = 22.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var yaw: float = 0.0
var pitch: float = 0.0

var is_spectating: bool = false
var _spectate_targets: Array[Node3D] = []
var _spectate_index: int = 0


func _ready() -> void:
	top_level = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if target_node:
		global_position = target_node.global_position + target_offset
		yaw = target_node.global_rotation.y
		rotation.y = yaw

	pitch = deg_to_rad(12.0)
	if spring_arm:
		spring_arm.rotation.x = -pitch

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(
			pitch + event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)
		rotation.y = yaw
		if spring_arm:
			spring_arm.rotation.x = -pitch

	# Переключение курсора по Esc / ui_cancel
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Захват курсора обратно при клике по окну или переключение спектатора
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif is_spectating:
			if event.button_index == MOUSE_BUTTON_LEFT:
				spectate_next()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				spectate_prev()

func start_spectating(candidates: Array[Node3D]) -> void:
	_spectate_targets.clear()
	for c in candidates:
		if is_instance_valid(c) and c.is_inside_tree():
			_spectate_targets.append(c)

	if _spectate_targets.is_empty():
		return

	is_spectating = true
	_spectate_index = 0
	_apply_spectate_target()

func stop_spectating(original_target: Node3D) -> void:
	is_spectating = false
	_spectate_targets.clear()
	if is_instance_valid(original_target):
		target_node = original_target

func spectate_next() -> void:
	if _spectate_targets.is_empty():
		return
	_filter_valid_spectate_targets()
	if _spectate_targets.is_empty():
		return
	_spectate_index = (_spectate_index + 1) % _spectate_targets.size()
	_apply_spectate_target()

func spectate_prev() -> void:
	if _spectate_targets.is_empty():
		return
	_filter_valid_spectate_targets()
	if _spectate_targets.is_empty():
		return
	_spectate_index = (_spectate_index - 1 + _spectate_targets.size()) % _spectate_targets.size()
	_apply_spectate_target()

func _apply_spectate_target() -> void:
	if _spectate_index >= 0 and _spectate_index < _spectate_targets.size():
		target_node = _spectate_targets[_spectate_index]
		spectate_target_changed.emit(target_node)

func _filter_valid_spectate_targets() -> void:
	var valid: Array[Node3D] = []
	for t in _spectate_targets:
		if is_instance_valid(t) and t.is_inside_tree():
			if t is Tank and not t.is_active:
				continue
			valid.append(t)
	_spectate_targets = valid
	if _spectate_targets.is_empty():
		target_node = null
	else:
		_spectate_index = clampi(_spectate_index, 0, _spectate_targets.size() - 1)

func _physics_process(delta: float) -> void:
	if is_spectating:
		_filter_valid_spectate_targets()

	if not is_instance_valid(target_node):
		return

	var desired_pos := target_node.global_position + target_offset
	var weight := 1.0 - exp(-smooth_speed * delta)
	global_position = global_position.lerp(desired_pos, weight)

func get_camera() -> Camera3D:
	return camera
