class_name HealthComponent
extends Node

## Компонент очков прочности (HP) танка TANKUS.
## Обрабатывает получение урона, проверку активного блока,
## визуальный Hit Flash при попадании и смерть танка.

signal health_changed(current: float, max_health: float)
signal damage_taken(amount: float, attacker: Node)
signal healed(amount: float)
signal died(killer: Node)

@export var max_health: float = 100.0
@export var current_health: float = 100.0

var _tank: Tank = null
var _hit_flash_tween: Tween = null
var _original_materials: Dictionary = {}

func _ready() -> void:
	_tank = get_parent() as Tank
	current_health = max_health

func take_damage(amount: float, attacker: Node = null) -> bool:
	if current_health <= 0.0:
		return false

	if _tank and not _tank.is_active:
		return false

	# Проверяем активный блок
	if _tank and _tank.block and _tank.block.is_blocking():
		return false

	var actual_damage := minf(current_health, amount)
	current_health = maxf(0.0, current_health - amount)

	damage_taken.emit(actual_damage, attacker)
	health_changed.emit(current_health, max_health)

	if _tank and _tank.events:
		_tank.events.emit_damage_taken(actual_damage, attacker)

	_play_hit_flash()

	if current_health <= 0.0:
		# Проверяем карточный спасбросок (Phoenix)
		if _tank and _tank.events and _tank.events.check_prevent_death(attacker):
			return true

		if attacker is Tank and (attacker as Tank).events:
			(attacker as Tank).events.emit_kill(_tank)

		_die(attacker)

	return true

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return

	var actual_heal := minf(max_health - current_health, amount)
	current_health = minf(max_health, current_health + amount)

	if actual_heal > 0.0:
		healed.emit(actual_heal)
		health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0

func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)

func _play_hit_flash() -> void:
	if not _tank or not _tank.visuals:
		return

	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()

	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

	var meshes: Array[MeshInstance3D] = []
	if _tank.chassis_mesh:
		meshes.append(_tank.chassis_mesh)
	if _tank.turret_mesh:
		meshes.append(_tank.turret_mesh)

	for mesh in meshes:
		mesh.material_override = flash_mat

	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_interval(0.08)
	_hit_flash_tween.tween_callback(func():
		if _tank:
			_tank._apply_team_color()
	)

func _die(killer: Node) -> void:
	if _tank:
		_tank.is_active = false
		_tank.velocity = Vector3.ZERO

	_spawn_death_explosion()

	if _tank and _tank.visuals:
		_tank.visuals.visible = false

	died.emit(killer)

func _spawn_death_explosion() -> void:
	if not _tank:
		return

	var explosion_pos := _tank.global_position + Vector3.UP * 0.5
	var explosion := Node3D.new()

	# Вспышка взрыва
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.2
	sphere.height = 2.4
	flash.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	flash.material_override = mat

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.1)
	light.light_energy = 5.0
	light.omni_range = 8.0

	explosion.add_child(flash)
	explosion.add_child(light)

	var spawn_parent: Node = null
	if get_tree() and get_tree().current_scene:
		spawn_parent = get_tree().current_scene
	elif _tank.get_parent():
		spawn_parent = _tank.get_parent()
	elif get_tree() and get_tree().root:
		spawn_parent = get_tree().root

	if spawn_parent:
		spawn_parent.add_child(explosion)
		explosion.global_position = explosion_pos
	else:
		_tank.add_child(explosion)

	var tween := explosion.create_tween()
	tween.tween_property(flash, "scale", Vector3(2.0, 2.0, 2.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.25)
	tween.tween_callback(explosion.queue_free)

func reset() -> void:
	current_health = max_health
	if _tank and _tank.visuals:
		_tank.visuals.visible = true
	health_changed.emit(current_health, max_health)
