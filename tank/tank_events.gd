class_name TankEvents
extends Node

## Диспетчер событий танка TANKUS.
## Центральная событийная шина для всех триггеров карт, способностей и синергий.

signal shot()
signal projectile_spawned(projectile: Projectile)
signal projectile_hit(projectile: Projectile, target: Node, point: Vector3, normal: Vector3)
signal projectile_bounce(projectile: Projectile, normal: Vector3, bounce_num: int)
signal reload_started(duration: float)
signal reload_completed()
signal block_started(duration: float)
signal successful_block(blocked_projectile: Node)
signal jumped()
signal landed(fall_distance: float)
signal damage_taken(amount: float, attacker: Node)
signal damage_dealt(amount: float, target: Node)
signal killed(victim: Node)
signal death_prevented()

var _tank: Tank = null

func _ready() -> void:
	_tank = get_parent() as Tank

func emit_shot() -> void:
	shot.emit()
	if _tank and _tank.build:
		_tank.build.notify_shot()

func emit_projectile_spawned(proj: Projectile) -> void:
	projectile_spawned.emit(proj)
	if _tank and _tank.build:
		_tank.build.notify_projectile_spawned(proj)

func emit_projectile_hit(proj: Projectile, target: Node, point: Vector3, normal: Vector3) -> void:
	projectile_hit.emit(proj, target, point, normal)
	if _tank and _tank.build:
		_tank.build.notify_projectile_hit(proj, target, point, normal)

func emit_projectile_bounce(proj: Projectile, normal: Vector3, bounce_num: int) -> void:
	projectile_bounce.emit(proj, normal, bounce_num)
	if _tank and _tank.build:
		_tank.build.notify_projectile_bounce(proj, normal, bounce_num)

func emit_reload_started(duration: float) -> void:
	reload_started.emit(duration)
	if _tank and _tank.build:
		_tank.build.notify_reload_started(duration)

func emit_reload_completed() -> void:
	reload_completed.emit()
	if _tank and _tank.build:
		_tank.build.notify_reload_completed()

func emit_block_started(duration: float) -> void:
	block_started.emit(duration)
	if _tank and _tank.build:
		_tank.build.notify_block_started(duration)

func emit_successful_block(blocked_proj: Node) -> void:
	successful_block.emit(blocked_proj)
	if _tank and _tank.build:
		_tank.build.notify_successful_block(blocked_proj)

func emit_jump() -> void:
	jumped.emit()
	if _tank and _tank.build:
		_tank.build.notify_jump()

func emit_land(fall_distance: float) -> void:
	landed.emit(fall_distance)
	if _tank and _tank.build:
		_tank.build.notify_land(fall_distance)

func emit_damage_taken(amount: float, attacker: Node) -> void:
	damage_taken.emit(amount, attacker)
	if _tank and _tank.build:
		_tank.build.notify_damage_taken(amount, attacker)

func emit_damage_dealt(amount: float, target: Node) -> void:
	damage_dealt.emit(amount, target)
	if _tank and _tank.build:
		_tank.build.notify_damage_dealt(amount, target)

func emit_kill(victim: Node) -> void:
	killed.emit(victim)
	if _tank and _tank.build:
		_tank.build.notify_kill(victim)

func check_prevent_death(killer: Node) -> bool:
	if _tank and _tank.build:
		var prevented := _tank.build.notify_death(killer)
		if prevented:
			death_prevented.emit()
			return true
	return false
