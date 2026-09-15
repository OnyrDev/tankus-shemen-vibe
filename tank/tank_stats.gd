class_name TankStats
extends Node

## Вычислитель характеристик танка TANKUS.
## Применяет чистый пересчет derived_stats = (base + flat) * multiplier
## без накопления float-погрешностей, с защитными clamp-значениями.

signal stats_changed()

# Базовые константы характеристик
const BASE_MAX_HP := 100.0
const BASE_MOVE_SPEED := 8.0
const BASE_JUMP_VELOCITY := 8.0
const BASE_AIR_CONTROL := 0.3
const BASE_DAMAGE := 28.0
const BASE_PROJECTILE_SPEED := 24.0
const BASE_PROJECTILE_BOUNCES := 0
const BASE_PROJECTILE_SIZE := 1.0
const BASE_FIRE_INTERVAL := 0.55
const BASE_RELOAD_TIME := 1.8
const BASE_MAGAZINE_SIZE := 4
const BASE_BLOCK_DURATION := 0.35
const BASE_BLOCK_COOLDOWN := 3.0
const BASE_SCALE := 1.0
const BASE_KNOCKBACK_RESISTANCE := 1.0

# Актуальные (производные) характеристики
var max_hp: float = BASE_MAX_HP
var move_speed: float = BASE_MOVE_SPEED
var jump_velocity: float = BASE_JUMP_VELOCITY
var air_control: float = BASE_AIR_CONTROL
var damage: float = BASE_DAMAGE
var projectile_speed: float = BASE_PROJECTILE_SPEED
var projectile_bounces: int = BASE_PROJECTILE_BOUNCES
var projectile_size: float = BASE_PROJECTILE_SIZE
var fire_interval: float = BASE_FIRE_INTERVAL
var reload_time: float = BASE_RELOAD_TIME
var magazine_size: int = BASE_MAGAZINE_SIZE
var block_duration: float = BASE_BLOCK_DURATION
var block_cooldown: float = BASE_BLOCK_COOLDOWN
var tank_scale: float = BASE_SCALE
var knockback_resistance: float = BASE_KNOCKBACK_RESISTANCE

var _tank: Tank = null

func _ready() -> void:
	_tank = get_parent() as Tank

func recalculate(cards_with_stacks: Dictionary, card_db: Object = null) -> void:
	var old_max_hp := max_hp

	# Накопители плоских бонусов
	var flat_hp := 0.0
	var flat_move_speed := 0.0
	var flat_jump_vel := 0.0
	var flat_air_ctrl := 0.0
	var flat_damage := 0.0
	var flat_proj_speed := 0.0
	var flat_bounces := 0
	var flat_magazine := 0
	var flat_block_dur := 0.0

	# Множители
	var mult_hp := 1.0
	var mult_move_speed := 1.0
	var mult_jump_vel := 1.0
	var mult_air_ctrl := 1.0
	var mult_damage := 1.0
	var mult_proj_speed := 1.0
	var mult_proj_size := 1.0
	var mult_fire_interval := 1.0
	var mult_reload_time := 1.0
	var mult_block_dur := 1.0
	var mult_block_cd := 1.0
	var mult_scale := 1.0
	var mult_knockback_res := 1.0

	for card_id in cards_with_stacks:
		var stacks: int = cards_with_stacks[card_id]
		if stacks <= 0:
			continue

		var card_def: CardDefinition = null
		if card_db and card_db.has_method("get_card"):
			card_def = card_db.get_card(card_id)

		if not card_def:
			continue

		var mods: Dictionary = card_def.stat_modifiers

		# Flat
		if mods.has("hp_flat"):
			flat_hp += float(mods["hp_flat"]) * stacks
		if mods.has("move_speed_flat"):
			flat_move_speed += float(mods["move_speed_flat"]) * stacks
		if mods.has("jump_velocity_flat"):
			flat_jump_vel += float(mods["jump_velocity_flat"]) * stacks
		if mods.has("air_control_flat"):
			flat_air_ctrl += float(mods["air_control_flat"]) * stacks
		if mods.has("damage_flat"):
			flat_damage += float(mods["damage_flat"]) * stacks
		if mods.has("proj_speed_flat"):
			flat_proj_speed += float(mods["proj_speed_flat"]) * stacks
		if mods.has("bounces_flat"):
			flat_bounces += int(mods["bounces_flat"]) * stacks
		if mods.has("magazine_flat"):
			flat_magazine += int(mods["magazine_flat"]) * stacks
		if mods.has("block_duration_flat"):
			flat_block_dur += float(mods["block_duration_flat"]) * stacks

		# Multipliers (возводятся в степень числа стаков)
		if mods.has("hp_mult"):
			mult_hp *= pow(float(mods["hp_mult"]), stacks)
		if mods.has("move_speed_mult"):
			mult_move_speed *= pow(float(mods["move_speed_mult"]), stacks)
		if mods.has("jump_velocity_mult"):
			mult_jump_vel *= pow(float(mods["jump_velocity_mult"]), stacks)
		if mods.has("air_control_mult"):
			mult_air_ctrl *= pow(float(mods["air_control_mult"]), stacks)
		if mods.has("damage_mult"):
			mult_damage *= pow(float(mods["damage_mult"]), stacks)
		if mods.has("proj_speed_mult"):
			mult_proj_speed *= pow(float(mods["proj_speed_mult"]), stacks)
		if mods.has("proj_size_mult"):
			mult_proj_size *= pow(float(mods["proj_size_mult"]), stacks)
		if mods.has("fire_interval_mult"):
			mult_fire_interval *= pow(float(mods["fire_interval_mult"]), stacks)
		if mods.has("reload_time_mult"):
			mult_reload_time *= pow(float(mods["reload_time_mult"]), stacks)
		if mods.has("block_duration_mult"):
			mult_block_dur *= pow(float(mods["block_duration_mult"]), stacks)
		if mods.has("block_cooldown_mult"):
			mult_block_cd *= pow(float(mods["block_cooldown_mult"]), stacks)
		if mods.has("scale_mult"):
			mult_scale *= pow(float(mods["scale_mult"]), stacks)
		if mods.has("knockback_resistance_mult"):
			mult_knockback_res *= pow(float(mods["knockback_resistance_mult"]), stacks)

	# Итоговый расчет с clamp
	max_hp = maxf(15.0, (BASE_MAX_HP + flat_hp) * mult_hp)
	move_speed = clampf((BASE_MOVE_SPEED + flat_move_speed) * mult_move_speed, 2.0, 24.0)
	jump_velocity = clampf((BASE_JUMP_VELOCITY + flat_jump_vel) * mult_jump_vel, 2.0, 22.0)
	air_control = clampf((BASE_AIR_CONTROL + flat_air_ctrl) * mult_air_ctrl, 0.05, 1.0)
	damage = maxf(5.0, (BASE_DAMAGE + flat_damage) * mult_damage)
	projectile_speed = clampf((BASE_PROJECTILE_SPEED + flat_proj_speed) * mult_proj_speed, 8.0, 70.0)
	projectile_bounces = maxi(0, BASE_PROJECTILE_BOUNCES + flat_bounces)
	projectile_size = clampf(BASE_PROJECTILE_SIZE * mult_proj_size, 0.35, 3.0)
	fire_interval = clampf(BASE_FIRE_INTERVAL * mult_fire_interval, 0.06, 2.5)
	reload_time = clampf(BASE_RELOAD_TIME * mult_reload_time, 0.25, 6.0)
	magazine_size = maxi(1, BASE_MAGAZINE_SIZE + flat_magazine)
	block_duration = clampf((BASE_BLOCK_DURATION + flat_block_dur) * mult_block_dur, 0.15, 1.5)
	block_cooldown = clampf(BASE_BLOCK_COOLDOWN * mult_block_cd, 0.5, 8.0)
	tank_scale = clampf(BASE_SCALE * mult_scale, 0.45, 2.0)
	knockback_resistance = clampf(BASE_KNOCKBACK_RESISTANCE * mult_knockback_res, 0.2, 5.0)

	# Если max_hp изменился, компенсируем текущее здоровье танка
	if _tank and _tank.health:
		var hp_diff := max_hp - old_max_hp
		if hp_diff > 0.0:
			_tank.health.current_health += hp_diff
		else:
			_tank.health.current_health = minf(_tank.health.current_health, max_hp)
		_tank.health.max_health = max_hp
		_tank.health.health_changed.emit(_tank.health.current_health, max_hp)

	_apply_to_tank_components()
	stats_changed.emit()

func _apply_to_tank_components() -> void:
	if not _tank:
		return

	if _tank.controller:
		_tank.controller.move_speed = move_speed
		_tank.controller.jump_velocity = jump_velocity
		_tank.controller.air_control = air_control

	if _tank.weapon:
		_tank.weapon.magazine_size = magazine_size
		_tank.weapon.fire_interval = fire_interval
		_tank.weapon.reload_time = reload_time

	if _tank.block:
		_tank.block.block_duration = block_duration
		_tank.block.cooldown = block_cooldown

	if _tank.visuals:
		_tank.visuals.scale = Vector3.ONE * tank_scale
