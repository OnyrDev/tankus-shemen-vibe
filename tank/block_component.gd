class_name BlockComponent
extends Node

## Компонент защитного блока (щита) танка TANKUS.
## Обеспечивает кратковременное окно неуязвимости (0.35с) с кулдауном (3.0с).
## Поглощает и уничтожает снаряды, эмитит successful_block для карточной системы.

signal block_started(duration: float)
signal block_ended()
signal cooldown_progress(current: float, total: float)
signal cooldown_finished()
signal successful_block(blocked_projectile: Node)

@export var block_duration: float = 0.35
@export var cooldown: float = 3.0

var _is_blocking: bool = false
var _is_on_cooldown: bool = false
var _block_timer: float = 0.0
var _cooldown_timer: float = 0.0

var _tank: Tank = null
var _shield_mesh: MeshInstance3D = null
var _shield_tween: Tween = null

func _ready() -> void:
	_tank = get_parent() as Tank
	if _tank:
		_shield_mesh = _tank.get_node_or_null("Visuals/ShieldMesh") as MeshInstance3D
		if _shield_mesh:
			_shield_mesh.visible = false

func _physics_process(delta: float) -> void:
	if _is_blocking:
		_block_timer -= delta
		if _block_timer <= 0.0:
			_end_block()

	if _is_on_cooldown:
		_cooldown_timer -= delta
		var elapsed := cooldown - _cooldown_timer
		cooldown_progress.emit(elapsed, cooldown)

		if _cooldown_timer <= 0.0:
			_is_on_cooldown = false
			_cooldown_timer = 0.0
			cooldown_finished.emit()

func can_block() -> bool:
	if _tank and not _tank.is_active:
		return false
	if _is_blocking or _is_on_cooldown:
		return false
	return true

func is_ready() -> bool:
	return can_block()

func is_blocking() -> bool:

	return _is_blocking and (_tank == null or _tank.is_active)

func is_on_cooldown() -> bool:
	return _is_on_cooldown

func get_cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_timer)

func get_cooldown_ratio() -> float:
	if not _is_on_cooldown or cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / cooldown, 0.0, 1.0)

func activate_block() -> bool:
	if not can_block():
		return false

	_is_blocking = true
	_is_on_cooldown = true
	_block_timer = block_duration
	_cooldown_timer = cooldown

	_show_shield()
	block_started.emit(block_duration)
	if _tank and _tank.events:
		_tank.events.emit_block_started(block_duration)
	return true

func absorb_projectile(projectile: Node) -> void:
	if not is_blocking():
		return

	successful_block.emit(projectile)
	if _tank and _tank.events:
		_tank.events.emit_successful_block(projectile)

	_pulse_shield()

	if is_instance_valid(projectile):
		projectile.queue_free()

func _show_shield() -> void:
	if not _shield_mesh:
		return

	_shield_mesh.visible = true
	if _shield_tween and _shield_tween.is_valid():
		_shield_tween.kill()

	_shield_mesh.scale = Vector3(0.5, 0.5, 0.5)
	_shield_tween = create_tween()
	_shield_tween.tween_property(_shield_mesh, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _end_block() -> void:
	_is_blocking = false
	_block_timer = 0.0

	if _shield_mesh:
		if _shield_tween and _shield_tween.is_valid():
			_shield_tween.kill()
		_shield_tween = create_tween()
		_shield_tween.tween_property(_shield_mesh, "scale", Vector3(0.1, 0.1, 0.1), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_shield_tween.tween_callback(func(): _shield_mesh.visible = false)

	block_ended.emit()

func _pulse_shield() -> void:
	if not _shield_mesh:
		return

	var pulse_tween := create_tween()
	pulse_tween.tween_property(_shield_mesh, "scale", Vector3(1.25, 1.25, 1.25), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pulse_tween.tween_property(_shield_mesh, "scale", Vector3.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func reset() -> void:
	_is_blocking = false
	_is_on_cooldown = false
	_block_timer = 0.0
	_cooldown_timer = 0.0
	if _shield_mesh:
		_shield_mesh.visible = false
		_shield_mesh.scale = Vector3.ONE
	cooldown_finished.emit()
