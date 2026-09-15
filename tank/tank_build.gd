class_name TankBuild
extends Node

## Компонент билда карт способностей танка TANKUS.
## Управляет коллекцией полученных карт, стаками, активными экземплярами CardEffect
## и трансляцией событий от TankEvents к эффектам.

signal card_added(card_def: CardDefinition, new_stacks: int)
signal build_changed()

var cards: Dictionary = {} # card_id (String) -> stack_count (int)
var ordered_cards: Array[String] = []
var active_effects: Dictionary = {} # card_id (String) -> CardEffect

var _tank: Tank = null

func _ready() -> void:
	_tank = get_parent() as Tank

func _physics_process(delta: float) -> void:
	for card_id in active_effects:
		var effect: CardEffect = active_effects[card_id]
		var stacks: int = cards.get(card_id, 1)
		effect.on_physics_process(delta, stacks)

func add_card(card_def: CardDefinition) -> void:
	if not card_def:
		return

	var cid := card_def.id
	var current_stacks: int = cards.get(cid, 0)

	if card_def.unique and current_stacks > 0:
		return

	if current_stacks >= card_def.max_stacks:
		return

	var new_stacks := current_stacks + 1
	cards[cid] = new_stacks

	if not ordered_cards.has(cid):
		ordered_cards.append(cid)

	# Создаем и регистрируем CardEffect если у карты есть скрипт
	if card_def.effect_script and not active_effects.has(cid):
		var effect_inst: CardEffect = card_def.effect_script.new()
		if effect_inst:
			effect_inst.setup(_tank, cid)
			active_effects[cid] = effect_inst

	if active_effects.has(cid):
		active_effects[cid].on_applied(new_stacks)

	# Пересчитываем характеристики танка
	if _tank and _tank.stats:
		_tank.stats.recalculate(cards, CardDatabase)

	card_added.emit(card_def, new_stacks)
	build_changed.emit()

func has_card(card_id: String) -> bool:
	return cards.has(card_id) and cards[card_id] > 0

func get_stacks(card_id: String) -> int:
	return cards.get(card_id, 0)

func clear_build() -> void:
	cards.clear()
	ordered_cards.clear()
	active_effects.clear()

	if _tank and _tank.stats:
		_tank.stats.recalculate(cards, CardDatabase)

	build_changed.emit()

# --- Трансляторы событий ---

func notify_shot() -> void:
	for cid in active_effects:
		active_effects[cid].on_shot(cards[cid])

func notify_projectile_spawned(proj: Projectile) -> void:
	for cid in active_effects:
		active_effects[cid].on_projectile_spawned(proj, cards[cid])

func notify_projectile_hit(proj: Projectile, target: Node, point: Vector3, normal: Vector3) -> void:
	for cid in active_effects:
		active_effects[cid].on_projectile_hit(proj, target, point, normal, cards[cid])

func notify_projectile_bounce(proj: Projectile, normal: Vector3, bounce_num: int) -> void:
	for cid in active_effects:
		active_effects[cid].on_projectile_bounce(proj, normal, bounce_num, cards[cid])

func notify_reload_started(duration: float) -> void:
	for cid in active_effects:
		active_effects[cid].on_reload_started(duration, cards[cid])

func notify_reload_completed() -> void:
	for cid in active_effects:
		active_effects[cid].on_reload_completed(cards[cid])

func notify_block_started(duration: float) -> void:
	for cid in active_effects:
		active_effects[cid].on_block_started(duration, cards[cid])

func notify_successful_block(blocked_proj: Node) -> void:
	for cid in active_effects:
		active_effects[cid].on_successful_block(blocked_proj, cards[cid])

func notify_jump() -> void:
	for cid in active_effects:
		active_effects[cid].on_jump(cards[cid])

func notify_land(fall_dist: float) -> void:
	for cid in active_effects:
		active_effects[cid].on_land(fall_dist, cards[cid])

func notify_damage_taken(amount: float, attacker: Node) -> void:
	for cid in active_effects:
		active_effects[cid].on_damage_taken(amount, attacker, cards[cid])

func notify_damage_dealt(amount: float, target: Node) -> void:
	for cid in active_effects:
		active_effects[cid].on_damage_dealt(amount, target, cards[cid])

func notify_kill(victim: Node) -> void:
	for cid in active_effects:
		active_effects[cid].on_kill(victim, cards[cid])

func notify_death(killer: Node) -> bool:
	var prevented := false
	for cid in active_effects:
		if active_effects[cid].on_death(killer, cards[cid]):
			prevented = true
	return prevented
