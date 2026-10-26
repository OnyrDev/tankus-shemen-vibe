class_name LavaHazardZone
extends Area3D

## Интерактивная зона смертоносной лавы / расплавленного металла TANKUS.
## При попадании танка наносит летальный урон, вызывает взрыв и уничтожает танк.
## При попадании ящиков (PhysicsCrate) сжигает их со взрывом и возвращает на старт конвейера.

signal tank_incinerated(tank: Tank)
signal crate_incinerated(crate: PhysicsCrate)

@export var fatal_damage: float = 99999.0

const EXPLOSION_SCENE: PackedScene = preload("res://vfx/explosion_vfx.tscn")

func _ready() -> void:
	# Слой 0 (зона только детектирует), маска: 2 (танки) + 8 (ящики / RigidBody3D)
	collision_layer = 0
	collision_mask = 2 | 8
	body_entered.connect(_on_body_entered)

func _physics_process(_delta: float) -> void:
	# Дополнительный опрос на случай мгновенного спавна или телепортации тела внутрь лавы
	var bodies := get_overlapping_bodies()
	for b in bodies:
		if b is Tank:
			var t := b as Tank
			if t.is_active and is_instance_valid(t):
				_incinerate_tank(t)
		elif b is PhysicsCrate:
			var c := b as PhysicsCrate
			if is_instance_valid(c):
				_incinerate_crate(c)
		elif b is RigidBody3D:
			var rb := b as RigidBody3D
			if is_instance_valid(rb):
				_incinerate_rigidbody(rb)

func _on_body_entered(body: Node3D) -> void:
	if body is Tank:
		_incinerate_tank(body as Tank)
	elif body is PhysicsCrate:
		_incinerate_crate(body as PhysicsCrate)
	elif body is RigidBody3D:
		_incinerate_rigidbody(body as RigidBody3D)

func _incinerate_tank(tank: Tank) -> void:
	if not is_instance_valid(tank) or not tank.is_inside_tree():
		return
	if not tank.is_active:
		return
	
	# Снимаем щит/блок, если танк пытался защититься от расплавленного металла
	if tank.block:
		tank.block.set("_is_blocking", false)
	
	# Наносим смертельный урон (вызовет взрыв, отключит танк и запустит таймер респавна)
	if tank.health:
		if tank.health.is_alive():
			var damaged := tank.health.take_damage(fatal_damage, null)
			if not damaged or tank.health.is_alive():
				tank.health._die(null)
		else:
			tank.health._die(null)
	else:
		_spawn_lava_explosion(tank.global_position)
		tank.is_active = false
	
	tank_incinerated.emit(tank)
	
	# Уведомляем базовую арену о падении в расплав для совместимости
	var parent_arena := get_tree().current_scene as BaseArena if get_tree() else null
	if not parent_arena:
		var n: Node = get_parent()
		while n:
			if n is BaseArena:
				parent_arena = n as BaseArena
				break
			n = n.get_parent()
	if parent_arena:
		parent_arena.tank_fell.emit(tank)

func _incinerate_crate(crate: PhysicsCrate) -> void:
	if not is_instance_valid(crate) or not crate.is_inside_tree():
		return
	
	var impact_pos := crate.global_position
	_spawn_lava_explosion(impact_pos)
	
	if SoundManager:
		SoundManager.play_sfx_3d("explosion", impact_pos, -2.0)
	
	crate_incinerated.emit(crate)
	crate.reset_to_start()

func _incinerate_rigidbody(rb: RigidBody3D) -> void:
	if not is_instance_valid(rb) or not rb.is_inside_tree():
		return
	_spawn_lava_explosion(rb.global_position)
	if rb.has_method("reset_to_start"):
		rb.call("reset_to_start")
	else:
		rb.queue_free()

func _spawn_lava_explosion(pos: Vector3) -> void:
	if not EXPLOSION_SCENE:
		return
	var vfx := EXPLOSION_SCENE.instantiate() as Node3D
	var parent: Node = get_tree().current_scene if (get_tree() and get_tree().current_scene) else get_parent()
	if parent:
		parent.add_child(vfx)
		vfx.global_position = pos
