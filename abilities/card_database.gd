class_name CardDatabase
extends Object

## Каталог всех 45 способностей TANKUS по спецификации ROUNDS.
## Предоставляет доступ к базе карт и генератор предложений драфта 1 из 5.

# --- Специализированные эффекты способностей (Inner Classes) ---

class RicochetPowerEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.ricochet_power_stacks = stacks

class PoisonEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.is_poison = true
		proj.poison_stacks = stacks

class ExplosiveShellEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.is_explosive = true
		proj.explosion_radius = 2.5 + (stacks - 1) * 0.8

class KnockoutEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.knockout_force = 12.0 * stacks

class PiercingEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.piercing_count = stacks

class HomingEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.homing_strength = 0.6 * stacks

class LastRoundEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, _stacks: int) -> void:
		if tank and tank.weapon and tank.weapon.current_ammo == 0:
			proj.damage *= 2.0 # Последний снаряд наносит двойной урон

class FirstRoundEffect extends CardEffect:
	var _is_first_round: bool = true

	func on_reload_completed(_stacks: int) -> void:
		_is_first_round = true

	func on_projectile_spawned(proj: Projectile, _stacks: int) -> void:
		if _is_first_round:
			_is_first_round = false
			proj.damage *= 1.6
			proj.speed *= 1.3
			proj.velocity = proj.direction * proj.speed

class RecoilEffect extends CardEffect:
	func on_shot(stacks: int) -> void:
		if tank and tank.turret:
			var push_dir := -tank.turret.get_shoot_direction()
			push_dir.y = 0.2
			tank.velocity += push_dir.normalized() * (9.0 * stacks)

class SniperShellEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.sniper_bonus_rate = 0.10 * stacks

class ShotgunEffect extends CardEffect:
	func on_shot(_stacks: int) -> void:
		# Дополнительные 3 снаряда с разбросом
		if not tank or not tank.weapon or not tank.weapon.projectile_scene or not tank.turret:
			return

		var base_pos := tank.turret.get_muzzle_position()
		var base_dir := tank.turret.get_shoot_direction()
		var angles: Array[float] = [-0.14, 0.08, 0.16]

		for angle in angles:
			var rot_dir := base_dir.rotated(Vector3.UP, angle).normalized()
			var proj := tank.weapon.projectile_scene.instantiate() as Projectile
			if proj:
				var spawn_parent: Node = tank.get_tree().current_scene if (tank.get_tree() and tank.get_tree().current_scene) else tank.get_parent()
				if spawn_parent:
					spawn_parent.add_child(proj)
					proj.damage = (tank.stats.damage if tank.stats else 28.0) * 0.45
					proj.setup(tank, base_pos, rot_dir, tank.team_color)

class BlinkEffect extends CardEffect:
	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank or not tank.turret:
			return

		var aim_dir := tank.turret.get_shoot_direction()
		aim_dir.y = 0.0
		if aim_dir.length_squared() < 0.01:
			return
		aim_dir = aim_dir.normalized()

		var dist := 5.0 * stacks
		var space := tank.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			tank.global_position + Vector3.UP * 0.5,
			tank.global_position + Vector3.UP * 0.5 + aim_dir * dist,
			1 # стены
		)
		var hit := space.intersect_ray(query)
		var target_pos: Vector3
		if hit:
			target_pos = hit.position - aim_dir * 0.8
		else:
			target_pos = tank.global_position + aim_dir * dist

		tank.global_position = target_pos

class ShockwaveEffect extends CardEffect:
	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank:
			return

		var tree := tank.get_tree()
		if not tree:
			return

		var radius: float = 5.0 + stacks * 1.5
		for node in tree.get_nodes_in_group("tanks"):
			var target_tank := node as Tank
			if target_tank and target_tank != tank and target_tank.is_active:
				var to_target: Vector3 = target_tank.global_position - tank.global_position
				var dist: float = to_target.length()
				if dist <= radius and dist > 0.1:
					var force: float = (1.0 - dist / radius) * (18.0 * stacks)
					var push_dir: Vector3 = to_target.normalized()
					push_dir.y = 0.35
					target_tank.velocity += push_dir.normalized() * force

class ReloadBlockEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, stacks: int) -> void:
		if tank and tank.weapon and tank.weapon.is_reloading():
			# Сокращаем оставшееся время перезарядки
			tank.weapon._reload_timer += 1.0 * stacks

class AmmoShieldEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, stacks: int) -> void:
		if tank and tank.weapon:
			tank.weapon.current_ammo = mini(tank.weapon.magazine_size, tank.weapon.current_ammo + (1 * stacks))
			tank.weapon.ammo_changed.emit(tank.weapon.current_ammo, tank.weapon.magazine_size)

class CounterShotEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, _stacks: int) -> void:
		if tank and tank.weapon and tank.turret:
			# Мгновенный выстрел без расхода обоймы
			var base_pos := tank.turret.get_muzzle_position()
			var base_dir := tank.turret.get_shoot_direction()
			var proj := tank.weapon.projectile_scene.instantiate() as Projectile
			if proj:
				var parent: Node = tank.get_tree().current_scene if (tank.get_tree() and tank.get_tree().current_scene) else tank.get_parent()
				if parent:
					parent.add_child(proj)
					proj.setup(tank, base_pos, base_dir, tank.team_color)

class PerfectGuardEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, _stacks: int) -> void:
		if tank and tank.block:
			# Если попадание в первые 25% окна блока (0.35 * 0.25 = ~0.09с)
			var elapsed := tank.block.block_duration - tank.block._block_timer
			if elapsed <= tank.block.block_duration * 0.25:
				tank.block._cooldown_timer = 0.0
				tank.block._is_on_cooldown = false
				tank.block.cooldown_finished.emit()

class GroundSlamEffect extends CardEffect:
	func on_land(fall_dist: float, stacks: int) -> void:
		if not tank or fall_dist < 2.0:
			return

		var radius := 4.5 * stacks
		var slam_damage := 18.0 * stacks
		var tree := tank.get_tree()
		if not tree:
			return

		for node in tree.get_nodes_in_group("tanks"):
			if node is Tank and node != tank and node.is_active:
				if tank.global_position.distance_to(node.global_position) <= radius:
					if node.health:
						node.health.take_damage(slam_damage, tank)

class JumpMineEffect extends CardEffect:
	func on_jump(stacks: int) -> void:
		if not tank:
			return

		# Оставляем мину на месте отрыва
		var mine := Area3D.new()
		mine.name = "JumpMine"
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.2
		shape.shape = sphere
		mine.add_child(shape)

		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.35
		cylinder.bottom_radius = 0.4
		cylinder.height = 0.15
		mesh.mesh = cylinder

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.2, 0.1)
		mesh.material_override = mat
		mine.add_child(mesh)

		var spawn_parent := tank.get_parent()
		if spawn_parent:
			spawn_parent.add_child(mine)
			mine.global_position = tank.global_position

		var mine_damage := 25.0 * stacks
		var creator := tank
		mine.body_entered.connect(func(body: Node3D):
			if body is Tank and body != creator and body.is_active:
				if body.health:
					body.health.take_damage(mine_damage, creator)
				mine.queue_free()
		)

		# Авто-удаление через 8с
		var timer := mine.get_tree().create_timer(8.0)
		timer.timeout.connect(func():
			if is_instance_valid(mine):
				mine.queue_free()
		)

class DeathFromAboveEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		if tank and not tank.is_on_floor():
			proj.damage *= (1.0 + 0.40 * stacks)

class RegenerationEffect extends CardEffect:
	var _time_since_last_damage: float = 0.0

	func on_damage_taken(_amount: float, _attacker: Node, _stacks: int) -> void:
		_time_since_last_damage = 0.0

	func on_physics_process(delta: float, stacks: int) -> void:
		_time_since_last_damage += delta
		if _time_since_last_damage >= 3.0:
			if tank and tank.health and tank.is_active:
				tank.health.heal(6.0 * stacks * delta)

class VampireEffect extends CardEffect:
	func on_damage_dealt(amount: float, _target: Node, stacks: int) -> void:
		if tank and tank.health and tank.is_active:
			var heal_amount := amount * (0.25 * stacks)
			tank.health.heal(heal_amount)

class AdrenalineEffect extends CardEffect:
	func on_physics_process(_delta: float, stacks: int) -> void:
		if tank and tank.health and tank.controller:
			var hp_ratio := tank.health.get_health_ratio()
			if hp_ratio < 0.35:
				tank.controller.speed_multiplier = 1.0 + (0.50 * stacks)
			else:
				tank.controller.speed_multiplier = 1.0

class RoadRageEffect extends CardEffect:
	func on_physics_process(_delta: float, stacks: int) -> void:
		if not tank:
			return

		for i in range(tank.get_slide_collision_count()):
			var col := tank.get_slide_collision(i)
			var target := col.get_collider() as Tank
			if target and target != tank and target.is_active:
				var rel_vel: Vector3 = tank.velocity - target.velocity
				var speed: float = rel_vel.length()
				if speed >= 4.0:
					var ram_damage: float = speed * 2.5 * stacks
					target.health.take_damage(ram_damage, tank)

class PhoenixEffect extends CardEffect:
	var _used_this_round: bool = false

	func on_death(_killer: Node, _stacks: int) -> bool:
		if _used_this_round:
			return false

		_used_this_round = true
		if tank and tank.health:
			# Отменяем гибель
			tank.health.current_health = tank.health.max_health * 0.5
			tank.health.health_changed.emit(tank.health.current_health, tank.health.max_health)
			if tank.block:
				tank.block.activate_block()
			return true

		return false

# --- Реестр всех карт ---

static var _cards_cache: Dictionary = {}

static func get_all_cards() -> Array[CardDefinition]:
	if _cards_cache.is_empty():
		_init_cards()

	var list: Array[CardDefinition] = []
	for k in _cards_cache:
		list.append(_cards_cache[k])
	return list

static func get_card(id: String) -> CardDefinition:
	if _cards_cache.is_empty():
		_init_cards()
	return _cards_cache.get(id, null)

static func generate_draft_offer(player_build: TankBuild, count: int = 5) -> Array[CardDefinition]:
	if _cards_cache.is_empty():
		_init_cards()

	var pool: Array[CardDefinition] = []
	for cid in _cards_cache:
		var card: CardDefinition = _cards_cache[cid]

		# Пропускаем unique карты, которые уже есть у игрока
		if card.unique and player_build and player_build.has_card(cid):
			continue

		# Пропускаем карты, достигшие max_stacks
		if player_build and player_build.get_stacks(cid) >= card.max_stacks:
			continue

		pool.append(card)

	pool.shuffle()
	var offer: Array[CardDefinition] = []
	var selected_count := mini(count, pool.size())
	for i in range(selected_count):
		offer.append(pool[i])

	return offer

static func _init_cards() -> void:
	_cards_cache.clear()

	# --- SHOT CARDS (18) ---
	_register("heavy_shell", "Heavy Shell", "+45% урона снарядов, -20% скорости полета.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.45, "proj_speed_mult": 0.8})
	_register("rapid_fire", "Rapid Fire", "-40% интервал между выстрелами, -15% урона.", CardDefinition.Category.SHOT, false, 99, {"fire_interval_mult": 0.60, "damage_mult": 0.85})
	_register("fastball", "Fastball", "+50% скорости полета снарядов.", CardDefinition.Category.SHOT, false, 99, {"proj_speed_mult": 1.50})
	_register("big_magazine", "Big Magazine", "+1 снаряд в магазин, +15% к времени перезарядки.", CardDefinition.Category.SHOT, false, 99, {"magazine_flat": 1, "reload_time_mult": 1.15})
	_register("quick_reload", "Quick Reload", "-30% к времени перезарядки.", CardDefinition.Category.SHOT, false, 99, {"reload_time_mult": 0.70})
	_register("bouncy", "Bouncy", "+1 дополнительный рикошет снаряда от препятствий.", CardDefinition.Category.SHOT, false, 99, {"bounces_flat": 1})
	_register("ricochet_power", "Ricochet Power", "Каждый рикошет увеличивает урон на +25% и скорость на +15%.", CardDefinition.Category.SHOT, false, 99, {}, RicochetPowerEffect)
	_register("poison", "Poison", "Снаряды отравляют цель DoT-уроном на 3 секунды.", CardDefinition.Category.SHOT, false, 99, {}, PoisonEffect)
	_register("explosive_shell", "Explosive Shell", "Снаряды взрываются при столкновении, нанося AoE урон.", CardDefinition.Category.SHOT, false, 99, {}, ExplosiveShellEffect)
	_register("big_shot", "Big Shot", "Снаряды крупнее (+80%) и мощнее (+30%), но летят медленнее (-25%).", CardDefinition.Category.SHOT, false, 99, {"proj_size_mult": 1.8, "damage_mult": 1.30, "proj_speed_mult": 0.75})
	_register("knockout", "Knockout", "Мощный импульс отталкивания при попадании снаряда.", CardDefinition.Category.SHOT, false, 99, {}, KnockoutEffect)
	_register("piercing", "Piercing", "Снаряд пробивает +1 вражеский танк насквозь.", CardDefinition.Category.SHOT, false, 99, {}, PiercingEffect)
	_register("homing", "Homing", "Снаряды плавно подруливают к ближайшим врагам.", CardDefinition.Category.SHOT, false, 99, {}, HomingEffect)
	_register("last_round", "Last Round", "Последний снаряд в обойме наносит +100% урона.", CardDefinition.Category.SHOT, false, 99, {}, LastRoundEffect)
	_register("first_round", "First Round", "Первый выстрел после перезарядки: +60% урона, +30% скорости.", CardDefinition.Category.SHOT, false, 99, {}, FirstRoundEffect)
	_register("recoil", "Recoil", "Выстрел толкает танк назад (Rocket Jump / мобильность), +15% урона.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.15}, RecoilEffect)
	_register("sniper_shell", "Sniper Shell", "+10% урона за каждые 5 метров дистанции полета снаряда.", CardDefinition.Category.SHOT, false, 99, {}, SniperShellEffect)
	_register("shotgun", "Shotgun", "Выстрел веером из 4 дробин с разбросом.", CardDefinition.Category.SHOT, true, 1, {}, ShotgunEffect)

	# --- BLOCK CARDS (9) ---
	_register("quick_guard", "Quick Guard", "-25% кулдаун защитного блока.", CardDefinition.Category.BLOCK, false, 99, {"block_cooldown_mult": 0.75})
	_register("long_block", "Long Block", "+50% длительность окна щита, +15% кулдаун.", CardDefinition.Category.BLOCK, false, 99, {"block_duration_mult": 1.50, "block_cooldown_mult": 1.15})
	_register("blink", "Blink", "Телепортация на 5м по направлению прицела при активации щита.", CardDefinition.Category.BLOCK, false, 99, {}, BlinkEffect)
	_register("shockwave", "Shockwave", "Щит испускает ударную волну, отталкивающую врагов.", CardDefinition.Category.BLOCK, false, 99, {}, ShockwaveEffect)
	_register("reload_block", "Reload Block", "Успешный блок сокращает текущее время перезарядки на 1с.", CardDefinition.Category.BLOCK, false, 99, {}, ReloadBlockEffect)
	_register("ammo_shield", "Ammo Shield", "Успешный блок восстанавливает +1 снаряд в обойму.", CardDefinition.Category.BLOCK, false, 99, {}, AmmoShieldEffect)
	_register("counter_shot", "Counter Shot", "Успешный блок автоматически выпускает ответный снаряд.", CardDefinition.Category.BLOCK, false, 99, {}, CounterShotEffect)
	_register("reflect", "Reflect", "Заблокированный снаряд отражается обратно во врага со сменой владельца.", CardDefinition.Category.BLOCK, true, 1, {})
	_register("perfect_guard", "Perfect Guard", "Блок в первые 25% окна щита сбрасывает кулдаун.", CardDefinition.Category.BLOCK, true, 1, {}, PerfectGuardEffect)

	# --- JUMP CARDS (6) ---
	_register("high_jump", "High Jump", "+40% высота прыжка танка.", CardDefinition.Category.JUMP, false, 99, {"jump_velocity_mult": 1.40})
	_register("air_control", "Air Control", "+100% маневренность и управление движением в воздухе.", CardDefinition.Category.JUMP, false, 99, {"air_control_mult": 2.0})
	_register("ground_slam", "Ground Slam", "Приземление с высоты вызывает ударную волну урона.", CardDefinition.Category.JUMP, false, 99, {}, GroundSlamEffect)
	_register("jump_mine", "Jump Mine", "При прыжке на земле остается мина с таймером 8 секунд.", CardDefinition.Category.JUMP, false, 99, {}, JumpMineEffect)
	_register("death_from_above", "Death From Above", "+40% урона снарядам, выпущенным в прыжке.", CardDefinition.Category.JUMP, false, 99, {}, DeathFromAboveEffect)
	_register("double_jump", "Double Jump", "Разрешает второй прыжок прямо в воздухе.", CardDefinition.Category.JUMP, true, 1, {})

	# --- GENERAL CARDS (12) ---
	_register("tankier", "Tankier", "+40 максимального здоровья танка.", CardDefinition.Category.GENERAL, false, 99, {"hp_flat": 40.0})
	_register("lightweight", "Lightweight", "+30% к скорости танка, снижена масса.", CardDefinition.Category.GENERAL, false, 99, {"move_speed_mult": 1.30, "knockback_resistance_mult": 0.7})
	_register("heavyweight", "Heavyweight", "+100% устойчивость к отталкиванию, -12% скорости.", CardDefinition.Category.GENERAL, false, 99, {"knockback_resistance_mult": 2.0, "move_speed_mult": 0.88})
	_register("adrenaline", "Adrenaline", "+50% к скорости перемещения, когда HP падает ниже 35%.", CardDefinition.Category.GENERAL, false, 99, {}, AdrenalineEffect)
	_register("glass_cannon", "Glass Cannon", "-40% максимального HP, +75% урона.", CardDefinition.Category.GENERAL, false, 99, {"hp_mult": 0.60, "damage_mult": 1.75})
	_register("regeneration", "Regeneration", "Восстановление 6 HP/сек после 3 секунд без получения урона.", CardDefinition.Category.GENERAL, false, 99, {}, RegenerationEffect)
	_register("vampire", "Vampire", "Лечение на 25% от нанесенного по врагам урона.", CardDefinition.Category.GENERAL, false, 99, {}, VampireEffect)
	_register("road_rage", "Road Rage", "Таран вражеского танка на скорости наносит урон.", CardDefinition.Category.GENERAL, false, 99, {}, RoadRageEffect)
	_register("tiny_tank", "Tiny Tank", "Танк меньше (-30%) и быстрее (+25%), но теряет 25 HP.", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 0.70, "move_speed_mult": 1.25, "hp_flat": -25.0})
	_register("big_tank", "Big Tank", "Танк крупнее (+40%) и прочнее (+60 HP), но медленнее (-15%).", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 1.40, "hp_flat": 60.0, "move_speed_mult": 0.85})
	_register("comeback", "Comeback", "Баффы скорости и кулдаунов в тяжелой ситуации.", CardDefinition.Category.GENERAL, false, 99, {"move_speed_mult": 1.20, "block_cooldown_mult": 0.80})
	_register("phoenix", "Phoenix", "Один раз за раунд смертельный урон отменяется, танк оживает с 50% HP.", CardDefinition.Category.GENERAL, true, 1, {}, PhoenixEffect)

static func _register(
	id: String,
	display_name: String,
	description: String,
	category: CardDefinition.Category,
	unique: bool = false,
	max_stacks: int = 99,
	stat_modifiers: Dictionary = {},
	effect_script: Script = null
) -> void:
	var def := CardDefinition.new()
	def.id = id
	def.display_name = display_name
	def.description = description
	def.category = category
	def.unique = unique
	def.max_stacks = max_stacks
	def.stat_modifiers = stat_modifiers
	def.effect_script = effect_script
	_cards_cache[id] = def
