class_name CardEffect
extends RefCounted

## Базовый класс для кастомных эффектов карт способностей.
## Способности подписываются на хуки жизненного цикла танка и снарядов.

var card_id: String = ""
var tank: Tank = null

func setup(p_tank: Tank, p_card_id: String) -> void:
	tank = p_tank
	card_id = p_card_id

## Вызывается при первичном получении или повышении стака карты
func on_applied(_stacks: int) -> void:
	pass

## Вызывается в момент выстрела танком перед созданием снаряда
func on_shot(_stacks: int) -> void:
	pass

## Вызывается при спавне каждого нового снаряда этим танком
func on_projectile_spawned(_proj: Projectile, _stacks: int) -> void:
	pass

## Вызывается при попадании снаряда во врага или объект
func on_projectile_hit(_proj: Projectile, _target: Node, _point: Vector3, _normal: Vector3, _stacks: int) -> void:
	pass

## Вызывается при каждом рикошете снаряда от стены/препятствия
func on_projectile_bounce(_proj: Projectile, _normal: Vector3, _bounce_num: int, _stacks: int) -> void:
	pass

## Вызывается при старте перезарядки
func on_reload_started(_duration: float, _stacks: int) -> void:
	pass

## Вызывается при завершении перезарядки
func on_reload_completed(_stacks: int) -> void:
	pass

## Вызывается при активации блока (щита)
func on_block_started(_duration: float, _stacks: int) -> void:
	pass

## Вызывается при успешном поглощении снаряда щитом
func on_successful_block(_blocked_proj: Node, _stacks: int) -> void:
	pass

## Вызывается при прыжке танка
func on_jump(_stacks: int) -> void:
	pass

## Вызывается при приземлении танка на землю
func on_land(_fall_distance: float, _stacks: int) -> void:
	pass

## Вызывается при получении танком урона
func on_damage_taken(_amount: float, _attacker: Node, _stacks: int) -> void:
	pass

## Вызывается при нанесении урона вражеской цели
func on_damage_dealt(_amount: float, _target: Node, _stacks: int) -> void:
	pass

## Вызывается при уничтожении вражеского танка
func on_kill(_victim: Node, _stacks: int) -> void:
	pass

## Вызывается при фатальном уроне перед гибелью.
## Если возвращает true — смерть отменяется (например, карта Phoenix).
func on_death(_killer: Node, _stacks: int) -> bool:
	return false

## Вызывается каждый физический кадр для фоновых пассивок (регенерация и т.д.)
func on_physics_process(_delta: float, _stacks: int) -> void:
	pass
