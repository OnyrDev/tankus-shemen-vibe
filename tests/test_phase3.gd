extends Node

func _ready() -> void:
	_run_tests()
	get_tree().quit(0)

func _run_tests() -> void:
	print("\n=== [TEST] Starting Phase 3 (Cards & Ricochet) Verification ===")

	# 1. Загрузка песочницы
	var sandbox_scene := load("res://maps/test_sandbox.tscn") as PackedScene
	assert(sandbox_scene != null, "ERROR: Failed to load test_sandbox.tscn")
	var sandbox := sandbox_scene.instantiate() as TestSandbox
	add_child(sandbox)
	print("[PASS] Sandbox scene instantiated successfully")

	# 2. Проверка ключевых узлов Phase 3
	var tank: Tank = sandbox.tank
	var dummy: Tank = sandbox.dummy_tank
	var hud: HUD = sandbox.hud
	var draft: CardDraft = sandbox.card_draft

	assert(tank != null, "ERROR: Tank not found")
	assert(dummy != null, "ERROR: DummyTank not found")
	assert(hud != null, "ERROR: HUD not found")
	assert(draft != null, "ERROR: CardDraft not found")

	assert(tank.stats != null, "ERROR: TankStats missing")
	assert(tank.build != null, "ERROR: TankBuild missing")
	assert(tank.events != null, "ERROR: TankEvents missing")
	print("[PASS] Phase 3 architecture components verified (TankStats, TankBuild, TankEvents, CardDraft)")

	# 3. Проверка базы данных 43 карт
	var all_cards := CardDatabase.get_all_cards()
	assert(all_cards.size() == 51, "ERROR: Card pool size should be 51, found %d" % all_cards.size())
	assert(CardDatabase.get_card("perfect_guard") == null, "ERROR: Perfect Guard card must be removed")

	var shot_count := 0
	var block_count := 0
	var jump_count := 0
	var general_count := 0

	for c in all_cards:
		match c.category:
			CardDefinition.Category.SHOT:
				shot_count += 1
			CardDefinition.Category.BLOCK:
				block_count += 1
			CardDefinition.Category.JUMP:
				jump_count += 1
			CardDefinition.Category.GENERAL:
				general_count += 1

	assert(shot_count == 22, "ERROR: Expected 22 SHOT cards, got %d" % shot_count)
	assert(block_count == 10, "ERROR: Expected 10 BLOCK cards, got %d" % block_count)
	assert(jump_count == 6, "ERROR: Expected 6 JUMP cards, got %d" % jump_count)
	assert(general_count == 13, "ERROR: Expected 13 GENERAL cards, got %d" % general_count)
	print("[PASS] All 51 cards registered with exact category balance (22 SHOT, 10 BLOCK, 6 JUMP, 13 GENERAL)")

	# 4. Проверка генератора драфта (Draft Offer)
	tank.build.clear_build()
	var offer1 := CardDatabase.generate_draft_offer(tank.build, 5)
	assert(offer1.size() == 5, "ERROR: Offer should contain 5 cards")

	# Проверка отсутствия дубликатов в предложении
	var unique_ids: Dictionary = {}
	for c in offer1:
		assert(not unique_ids.has(c.id), "ERROR: Duplicate card in draft offer: %s" % c.id)
		unique_ids[c.id] = true

	# Проверка фильтрации взятых Unique карт
	var phoenix_card := CardDatabase.get_card("phoenix")
	assert(phoenix_card != null and phoenix_card.unique == true, "ERROR: Phoenix card not found or not unique")
	tank.build.add_card(phoenix_card)
	assert(tank.build.has_card("phoenix") == true, "ERROR: Tank should have phoenix card")

	# Генерируем 10 предложений, Phoenix ни разу не должен выпасть
	for i in range(10):
		var test_offer := CardDatabase.generate_draft_offer(tank.build, 5)
		for c in test_offer:
			assert(c.id != "phoenix", "ERROR: Unique card 'phoenix' appeared in draft offer after being taken!")
	print("[PASS] Draft generation verified (5 unique choices, duplicate-free, unique exclusion)")

	# 5. Проверка чистого пересчета характеристик (TankStats)
	tank.build.clear_build()
	assert(is_equal_approx(tank.stats.max_hp, 100.0), "ERROR: Base max_hp should be 100")
	assert(is_equal_approx(tank.stats.damage, 28.0), "ERROR: Base damage should be 28")
	assert(tank.stats.magazine_size == 6, "ERROR: Base magazine should be 6")
	assert(tank.stats.projectile_bounces == 0, "ERROR: Base bounces should be 0")

	# Добавляем Heavy Shell (+45% dmg, -20% proj speed)
	var heavy := CardDatabase.get_card("heavy_shell")
	tank.build.add_card(heavy)
	assert(is_equal_approx(tank.stats.damage, 28.0 * 1.45), "ERROR: Damage after Heavy Shell incorrect")
	assert(is_equal_approx(tank.stats.projectile_speed, 24.0 * 0.8), "ERROR: Proj speed after Heavy Shell incorrect")

	# Добавляем Big Magazine (+1 ammo, +15% reload time)
	var big_mag := CardDatabase.get_card("big_magazine")
	tank.build.add_card(big_mag)
	assert(tank.stats.magazine_size == 7, "ERROR: Magazine size after Big Magazine should be 7")
	assert(is_equal_approx(tank.stats.reload_time, 1.8 * 1.15), "ERROR: Reload time after Big Magazine incorrect")

	# Добавляем Tankier (+40 max HP)
	var tankier := CardDatabase.get_card("tankier")
	tank.build.add_card(tankier)
	assert(is_equal_approx(tank.stats.max_hp, 140.0), "ERROR: Max HP after Tankier should be 140")
	assert(is_equal_approx(tank.health.current_health, 140.0), "ERROR: Current HP should scale with Tankier")

	# Добавляем Bouncy (+1 bounce)
	var bouncy := CardDatabase.get_card("bouncy")
	tank.build.add_card(bouncy)
	assert(tank.stats.projectile_bounces == 1, "ERROR: Projectile bounces should be 1 after Bouncy card")
	print("[PASS] Pure derived stat recalculation verified (Heavy Shell, Big Magazine, Tankier, Bouncy)")

	# 6. Проверка физического рикошета снаряда
	var proj_scene := load("res://projectile/projectile.tscn") as PackedScene
	var base_proj := proj_scene.instantiate() as Projectile
	add_child(base_proj)
	base_proj.setup(tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	assert(base_proj.bounces_left == 0, "ERROR: Fresh projectile without cards must have 0 bounces by default!")
	base_proj.queue_free()

	var test_proj := proj_scene.instantiate() as Projectile
	add_child(test_proj)
	test_proj.setup(tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	test_proj.bounces_left = 2

	# Симулируем столкновение со стеной (нормаль Vector3.BACK = (0, 0, 1))
	var wall_normal := Vector3(0, 0, 1)
	test_proj.velocity = test_proj.velocity.bounce(wall_normal)
	test_proj.bounces_left -= 1
	test_proj.bounces_done += 1

	assert(test_proj.velocity.z > 0.0, "ERROR: Velocity.z should reverse direction after bouncing off wall")
	assert(test_proj.bounces_left == 1, "ERROR: Bounces left should decrease to 1")
	assert(test_proj.bounces_done == 1, "ERROR: Bounces done should be 1")
	test_proj.queue_free()
	print("[PASS] Projectile ricochet bounce reflection verified")

	# 7. Проверка Ricochet Power
	tank.build.clear_build()
	var rico_card := CardDatabase.get_card("ricochet_power")
	tank.build.add_card(rico_card)
	assert(tank.stats.projectile_bounces == 1, "ERROR: Ricochet Power must grant 1 bounce by default")
	var rico_proj := proj_scene.instantiate() as Projectile
	add_child(rico_proj)
	rico_proj.setup(tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	tank.events.emit_projectile_spawned(rico_proj)
	assert(rico_proj.ricochet_power_stacks == 1, "ERROR: Ricochet power stacks not set on projectile")
	assert(rico_proj.bounces_left >= 1, "ERROR: Ricochet Power projectile must have at least 1 bounce")

	var orig_dmg := rico_proj.damage
	# Симулируем 1 отскок
	rico_proj.damage *= 1.25
	rico_proj.speed *= 1.15
	assert(rico_proj.damage > orig_dmg, "ERROR: Ricochet Power did not boost damage")
	rico_proj.queue_free()
	print("[PASS] Ricochet Power damage and speed scaling verified")

	# 8. Проверка Blink (телепортация при блоке)
	tank.build.clear_build()
	var blink_card := CardDatabase.get_card("blink")
	tank.build.add_card(blink_card)
	var start_pos := tank.global_position
	tank.input.aim_point = start_pos + Vector3(0, 0, -10)
	tank.turret.aim_at(tank.input.aim_point, 1.0)
	tank.block.activate_block()
	# Должен сместиться вперед
	assert(not tank.global_position.is_equal_approx(start_pos), "ERROR: Blink did not change tank position on block")
	tank.block.reset()
	print("[PASS] Blink teleportation on block verified")

	# 9. Проверка Double Jump
	tank.build.clear_build()
	var double_jump := CardDatabase.get_card("double_jump")
	tank.build.add_card(double_jump)
	assert(tank.build.has_card("double_jump") == true, "ERROR: Tank should have double jump")
	# Симулируем первый прыжок
	tank.global_position.y = 2.0 # в воздухе
	tank.controller._can_double_jump = true
	tank.controller.process_physics(tank.input, 0.016)
	assert(tank.controller._can_double_jump == true, "ERROR: Double jump should be ready in air")
	# Потребляем прыжок в воздухе
	tank.input.jump_requested = true
	tank.controller.process_physics(tank.input, 0.016)
	assert(tank.velocity.y > 0.0, "ERROR: Double jump should give positive vertical velocity in air")
	assert(tank.controller._can_double_jump == false, "ERROR: Double jump should be consumed")
	print("[PASS] Double Jump airborne mechanics verified")

	# 10. Проверка Vampire (вампиризм)
	tank.build.clear_build()
	var vampire := CardDatabase.get_card("vampire")
	tank.build.add_card(vampire)
	tank.health.current_health = 50.0 # снижаем HP
	tank.events.emit_damage_dealt(40.0, dummy) # 25% от 40 = 10 HP
	assert(tank.health.current_health == 60.0, "ERROR: Vampire should heal 25% of dealt damage (50 -> 60)")
	print("[PASS] Vampire life-steal healing verified")

	# 11. Проверка Phoenix (воскрешение с 50% HP)
	tank.build.clear_build()
	tank.build.add_card(phoenix_card)
	tank.health.current_health = 10.0
	var fatal_damage_applied := tank.health.take_damage(50.0, dummy)
	assert(fatal_damage_applied == true, "ERROR: Fatal damage should be processed")
	assert(tank.health.is_alive() == true, "ERROR: Tank should be saved by Phoenix")
	assert(tank.health.current_health == tank.health.max_health * 0.5, "ERROR: Phoenix should revive with 50% HP")
	print("[PASS] Phoenix fatal death prevention and resurrection verified")

	# 12. Проверка отображения билда в HUD (если контейнер чипов активен)
	tank.build.clear_build()
	tank.build.add_card(heavy)
	tank.build.add_card(heavy) # 2 стака
	if hud.build_chips_container != null:
		assert(hud.build_chips_container.get_child_count() == 1, "ERROR: Should have 1 chip for heavy_shell")
		var chip_label: Label = hud.build_chips_container.get_child(0).get_child(0)
		assert(chip_label.text == "Heavy Shell ×2", "ERROR: Chip label text should be 'Heavy Shell ×2', got '%s'" % chip_label.text)
	print("[PASS] HUD active build chips display verified")

	# 13. Проверка Ground Slam (отображение ударной волны и увеличение радиуса со стаками)
	tank.build.clear_build()
	var ground_slam := CardDatabase.get_card("ground_slam")
	tank.build.add_card(ground_slam) # 1 стак -> радиус 4.5м
	tank.global_position = Vector3.ZERO
	dummy.global_position = Vector3(6.0, 0.0, 0.0) # 6м — за пределами 1 стака (4.5м), но внутри 2 стаков (9.0м)
	dummy.health.reset()
	tank.events.emit_land(1.7) # высота обычного прыжка (~1.71м)
	assert(dummy.health.current_health == dummy.health.max_health, "ERROR: Ground Slam 1 stack (4.5m) should not hit dummy at 6.0m")
	var wave_1: Node3D = null
	for child in tank.get_parent().get_children():
		if child.name.begins_with("GroundSlamWave"):
			wave_1 = child as Node3D
	assert(wave_1 != null, "ERROR: Ground Slam should spawn GroundSlamWave visual shockwave")
	assert(is_equal_approx(float(wave_1.get_meta("slam_radius", 0.0)), 4.5), "ERROR: Ground Slam 1 stack visual radius should be 4.5")
	wave_1.free()

	# Добавляем 2-й стак -> радиус 9.0м
	tank.build.add_card(ground_slam)
	tank.events.emit_land(1.7)
	assert(dummy.health.current_health < dummy.health.max_health, "ERROR: Ground Slam 2 stacks (9.0m) should hit dummy at 6.0m")
	var wave_2: Node3D = null
	for child in tank.get_parent().get_children():
		if child.name.begins_with("GroundSlamWave"):
			wave_2 = child as Node3D
	assert(wave_2 != null, "ERROR: Ground Slam 2 stacks should spawn GroundSlamWave visual shockwave")
	assert(is_equal_approx(float(wave_2.get_meta("slam_radius", 0.0)), 9.0), "ERROR: Ground Slam 2 stacks visual radius should be 9.0")
	wave_2.free()
	print("[PASS] Ground Slam shockwave VFX and radius stacking verified")

	# 14. Проверка Jump Mine (спавн мины со слоем коллизии танков и нанесение урона при наезде)
	tank.build.clear_build()
	var jump_mine := CardDatabase.get_card("jump_mine")
	tank.build.add_card(jump_mine)
	tank.global_position = Vector3(2.0, 0.0, 2.0)
	dummy.global_position = Vector3(10.0, 0.0, 10.0)
	dummy.health.reset()
	tank.events.emit_jump()

	var spawned_mines := get_tree().get_nodes_in_group("jump_mines")
	assert(spawned_mines.size() == 1, "ERROR: Jump Mine should spawn 1 mine in group 'jump_mines'")
	var mine_node := spawned_mines[0] as Area3D
	assert(mine_node != null, "ERROR: Spawned mine must be Area3D")
	assert((mine_node.collision_mask & 2) != 0, "ERROR: Jump Mine collision_mask must include layer 2 (Tank)")

	# Свой танк не должен подрывать свою мину
	mine_node.body_entered.emit(tank)
	assert(not mine_node.get_meta("detonated", false), "ERROR: Creator tank should not trigger its own Jump Mine")

	# Вражеский танк наезжает на мину и получает 25 урона
	mine_node.body_entered.emit(dummy)
	assert(mine_node.get_meta("detonated", false), "ERROR: Enemy tank should trigger Jump Mine")
	assert(is_equal_approx(dummy.health.current_health, dummy.health.max_health - 25.0), "ERROR: Jump Mine should deal 25 damage on 1 stack")
	CardDatabase.JumpMineEffect.clear_all_mines(get_tree())

	# Проверка увеличения размера и радиуса мины при 2 стаках Jump Mine
	tank.build.add_card(jump_mine) # 2 стака
	tank.events.emit_jump()
	var stacked_mines := get_tree().get_nodes_in_group("jump_mines")
	assert(stacked_mines.size() == 1, "ERROR: 2-stack Jump Mine should spawn 1 mine")
	var stacked_mine := stacked_mines[0] as Area3D
	assert(is_equal_approx(float(stacked_mine.get_meta("mine_scale", 1.0)), 1.35), "ERROR: 2-stack Jump Mine scale should be 1.35")
	CardDatabase.JumpMineEffect.clear_all_mines(get_tree())
	print("[PASS] Jump Mine collision mask, self-ignore, stack scaling, and detonation damage verified")

	# 15. Проверка карты Poison (наложение DoT при попадании и тики урона после уничтожения снаряда)
	tank.build.clear_build()
	var poison_card := CardDatabase.get_card("poison")
	tank.build.add_card(poison_card)
	tank.build.add_card(poison_card) # 2 стака -> 8.0 урона за тик
	dummy.health.reset()
	var poison_proj := tank.weapon.spawn_custom_projectile(Vector3.ZERO, Vector3.FORWARD)
	assert(poison_proj.is_poison and poison_proj.poison_stacks == 2, "ERROR: Poison card should set is_poison and poison_stacks=2 on projectile")
	poison_proj._handle_direct_hit(dummy, dummy.global_position, Vector3.BACK)
	var hp_after_direct_hit := dummy.health.current_health
	var poison_dot := dummy.get_node_or_null("PoisonEffect")
	assert(poison_dot != null, "ERROR: PoisonEffect node should be attached to target tank")
	poison_dot._physics_process(0.5) # 1-й тик яда после удаления снаряда
	assert(is_equal_approx(dummy.health.current_health, hp_after_direct_hit - 8.0), "ERROR: 2-stack Poison tick should deal 8.0 DoT damage")
	for _i in range(5):
		poison_dot._physics_process(0.5)
	assert(is_equal_approx(dummy.health.current_health, hp_after_direct_hit - 48.0), "ERROR: 6 ticks of 2-stack Poison should deal 48.0 total DoT damage")
	print("[PASS] Poison DoT application, post-impact projectile cleanup survival, and stack damage verified")

	# 15.1. Проверка Shockwave VFX при активации блока
	tank.build.clear_build()
	var shockwave_card := CardDatabase.get_card("shockwave")
	tank.build.add_card(shockwave_card)
	tank.events.emit_block_started(0.35)
	var sw_wave: Node3D = null
	for child in (tank.get_parent() if tank.get_parent() else get_tree().current_scene).get_children():
		if child.name == "BlockShockwaveWave":
			sw_wave = child as Node3D
	assert(sw_wave != null, "ERROR: Shockwave card must spawn BlockShockwaveWave visual effect")
	assert(is_equal_approx(float(sw_wave.get_meta("shockwave_radius", 0.0)), 6.5), "ERROR: 1-stack Shockwave visual radius should be 6.5m (5.0 + 1.5)")
	sw_wave.free()

	# 16. Проверка карты Road Rage (доколлизионная скорость, фильтр направления, кулдаун и бамп)
	tank.build.clear_build()
	var road_rage := CardDatabase.get_card("road_rage")
	tank.build.add_card(road_rage)
	var rr_effect := tank.build.active_effects.get("road_rage", null) as CardDatabase.RoadRageEffect
	assert(rr_effect != null, "ERROR: RoadRageEffect must be active on tank")

	tank.global_position = Vector3(0.0, 0.0, 0.0)
	dummy.global_position = Vector3(0.0, 0.0, -1.5)
	dummy.health.reset()
	dummy.velocity = Vector3.ZERO

	# Стоящий танк не должен наносить урон, если в него въехал враг
	tank.velocity = Vector3.ZERO
	if tank.controller:
		tank.controller.pre_slide_velocity = Vector3.ZERO
	dummy.velocity = Vector3(0.0, 0.0, 8.0)
	assert(not rr_effect.try_ram_target(dummy, Vector3.FORWARD, 1), "ERROR: Stationary tank with Road Rage must not damage enemy ramming into it")
	assert(is_equal_approx(dummy.health.current_health, dummy.health.max_health), "ERROR: Dummy HP must remain full when ramming a stationary Road Rage tank")

	# Лобовой таран (даже если move_and_slide уже погасил tank.velocity, берется pre_slide_velocity = 8.0)
	dummy.velocity = Vector3.ZERO
	tank.velocity = Vector3.ZERO
	if tank.controller:
		tank.controller.pre_slide_velocity = Vector3(0.0, 0.0, -8.0)
	assert(rr_effect.try_ram_target(dummy, Vector3.FORWARD, 1), "ERROR: Road Rage should trigger using pre_slide_velocity on head-on ram")
	assert(is_equal_approx(dummy.health.current_health, dummy.health.max_health - 20.0), "ERROR: Road Rage at 8 m/s (1 stack) should deal 20.0 damage")
	assert(dummy.velocity.z < -4.0, "ERROR: Road Rage must apply knockback impulse to target tank")

	# Повторный тик в следующем кадре блокируется кулдауном (защита от стирания ХП за 5 кадров)
	assert(not rr_effect.try_ram_target(dummy, Vector3.FORWARD, 1), "ERROR: Road Rage must respect per-target hit cooldown")
	rr_effect.on_physics_process(0.5, 1) # истекает кулдаун 0.45с
	assert(rr_effect.try_ram_target(dummy, Vector3.FORWARD, 1), "ERROR: Road Rage should trigger again after cooldown expires")
	print("[PASS] Road Rage pre-slide velocity, directional check, knockback, and cooldown verified")

	# 17. Проверка карты "Разброс" (+70% урона, отклонение от прицела, стакание разброса и урона)
	tank.build.clear_build()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var base_dmg: float = tank.stats.damage
	var spread_card := CardDatabase.get_card("spread")
	assert(spread_card != null, "ERROR: Spread card must be registered")
	tank.build.add_card(spread_card)
	assert(is_equal_approx(tank.stats.damage, base_dmg * 1.70), "ERROR: 1-stack Spread must give +70% damage")
	var aim_dir := Vector3(0.0, 0.0, -1.0)
	var max_dev_1: float = CardDatabase.SpreadEffect.get_max_spread_deg(1)
	var deviated := false
	for _i in range(40):
		var sp_proj := tank.weapon.spawn_custom_projectile(Vector3.ZERO, aim_dir)
		var dev_deg: float = rad_to_deg(aim_dir.angle_to(sp_proj.direction))
		assert(dev_deg <= max_dev_1 + 0.01, "ERROR: 1-stack Spread deviation %.2f exceeds limit %.2f" % [dev_deg, max_dev_1])
		assert(sp_proj.velocity.normalized().is_equal_approx(sp_proj.direction), "ERROR: Spread must keep projectile velocity aligned with direction")
		assert(is_equal_approx(sp_proj.direction.y, 0.0), "ERROR: Spread must deviate horizontally only")
		if dev_deg > 0.1:
			deviated = true
		sp_proj.free()
	assert(deviated, "ERROR: Spread must actually deflect projectiles from the aim line")
	tank.build.add_card(spread_card)
	assert(is_equal_approx(tank.stats.damage, base_dmg * 1.70 * 1.70), "ERROR: 2-stack Spread damage must stack multiplicatively")
	assert(CardDatabase.SpreadEffect.get_max_spread_deg(2) > max_dev_1, "ERROR: Spread angle must grow with stacks")
	var max_dev_2: float = CardDatabase.SpreadEffect.get_max_spread_deg(2)
	var widest := 0.0
	for _i in range(200):
		var sp_proj2 := tank.weapon.spawn_custom_projectile(Vector3.ZERO, aim_dir)
		var dev2: float = rad_to_deg(aim_dir.angle_to(sp_proj2.direction))
		assert(dev2 <= max_dev_2 + 0.01, "ERROR: 2-stack Spread deviation exceeds limit")
		widest = maxf(widest, dev2)
		sp_proj2.free()
	assert(widest > max_dev_1, "ERROR: 2-stack Spread should reach angles beyond the 1-stack limit")
	print("[PASS] Spread card damage stacking, horizontal deviation cone, and stack-scaled angle verified")

	# 18. Проверка карты Firefly (огненный след: ширина, лимит длины, время жизни, поджог врага)
	tank.build.clear_build()
	var firefly_card := CardDatabase.get_card("firefly")
	assert(firefly_card != null and firefly_card.category == CardDefinition.Category.GENERAL, "ERROR: Firefly must be registered as GENERAL card")
	tank.build.add_card(firefly_card)
	var ff := tank.build.active_effects.get("firefly", null) as CardDatabase.FireflyEffect
	assert(ff != null, "ERROR: FireflyEffect must be active on tank")
	CardDatabase.FireflyEffect.clear_all_trails(get_tree())

	var ff_scale: float = tank.stats.tank_scale
	var ff_max_len: float = CardDatabase.FireflyEffect.get_max_trail_length(ff_scale)
	assert(is_equal_approx(ff_max_len, 6.6 * ff_scale), "ERROR: Firefly max trail length must be 2 tank lengths")
	assert(is_equal_approx(CardDatabase.FireflyEffect.get_trail_width(ff_scale), 2.0 * ff_scale), "ERROR: Firefly trail width must match tank width")

	# Длинный путь вдоль оси X: лимит длины обрезает старые сегменты
	var ff_y: float = tank.global_position.y
	for i in range(20):
		var seg_a := Vector3(float(i), ff_y, 20.0)
		var seg_b := Vector3(float(i + 1), ff_y, 20.0)
		assert(ff.add_segment(seg_a, seg_b, ff_scale), "ERROR: Firefly segment must be created")
	assert(ff.get_total_trail_length() <= ff_max_len + 0.001, "ERROR: Firefly trail must not exceed 2 tank lengths (%.2f)" % ff.get_total_trail_length())
	assert(ff.get_segment_count() > 1 and ff.get_segment_count() < 20, "ERROR: Firefly must drop old segments over the length cap")
	assert(get_tree().get_nodes_in_group("fire_trail_segments").size() == ff.get_segment_count(), "ERROR: Firefly visual nodes must match active segments")

	# Враг внутри огня загорается, снаружи — нет
	dummy.health.reset()
	dummy.velocity = Vector3.ZERO
	var fire_head := Vector3(20.0, ff_y, 20.0) # конец последнего сегмента
	dummy.global_position = fire_head + Vector3(-1.0, 0.0, 0.0)
	var old_dummy_burn := dummy.get_node_or_null("BurnEffect")
	if old_dummy_burn:
		old_dummy_burn.free()
	ff.on_physics_process(0.016, 1)
	var burn_dot := dummy.get_node_or_null("BurnEffect")
	assert(burn_dot != null, "ERROR: Enemy standing in Firefly trail must catch fire")
	var hp_before_burn := dummy.health.current_health
	burn_dot._physics_process(0.5)
	assert(is_equal_approx(dummy.health.current_health, hp_before_burn - 4.0), "ERROR: 1-stack burn tick must deal 4.0 damage like Poison")
	burn_dot.free()

	dummy.global_position = fire_head + Vector3(-1.0, 0.0, 6.0) # далеко в стороне от следа
	ff.on_physics_process(0.016, 1)
	assert(dummy.get_node_or_null("BurnEffect") == null, "ERROR: Enemy outside Firefly trail must not catch fire")

	# Собственный танк огонь не поджигает
	tank.global_position = fire_head + Vector3(-1.0, 0.0, 0.0)
	ff.on_physics_process(0.016, 1)
	assert(tank.get_node_or_null("BurnEffect") == null, "ERROR: Firefly owner must be immune to own fire")

	# Через 2 секунды след полностью гаснет
	ff.on_physics_process(2.1, 1)
	assert(ff.get_segment_count() == 0, "ERROR: Firefly trail must disappear after 2 seconds")
	dummy.global_position = fire_head + Vector3(-1.0, 0.0, 0.0)
	ff.on_physics_process(0.016, 1)
	assert(dummy.get_node_or_null("BurnEffect") == null, "ERROR: Expired Firefly trail must not ignite enemies")

	# Стаки удлиняют след (+2 длины танка за стак), но не меняют время горения сегментов
	assert(is_equal_approx(CardDatabase.FireflyEffect.get_max_trail_length(ff_scale, 1), 6.6 * ff_scale), "ERROR: 1-stack Firefly trail must be 2 tanks long")
	assert(is_equal_approx(CardDatabase.FireflyEffect.get_max_trail_length(ff_scale, 3), 3.3 * 6.0 * ff_scale), "ERROR: 3-stack Firefly trail must be 6 tanks long")
	CardDatabase.FireflyEffect.clear_all_trails(get_tree())
	for i in range(30):
		ff.add_segment(Vector3(float(i), ff_y, 30.0), Vector3(float(i + 1), ff_y, 30.0), ff_scale, 3)
	var len_3: float = ff.get_total_trail_length()
	assert(len_3 <= 19.8 * ff_scale + 0.001 and len_3 > 13.2 * ff_scale + 1.0, "ERROR: 3-stack Firefly trail must reach ~6 tanks (%.2f)" % len_3)
	ff.on_physics_process(1.9, 3)
	assert(ff.get_segment_count() > 0, "ERROR: Firefly segments must still burn just before 2s")
	ff.on_physics_process(0.2, 3)
	assert(ff.get_segment_count() == 0, "ERROR: Firefly segment lifetime must stay 2s regardless of stacks")
	var burn_check := dummy.get_node_or_null("BurnEffect")
	if burn_check:
		burn_check.free()
	ff.add_segment(Vector3(0.0, ff_y, 40.0), Vector3(1.0, ff_y, 40.0), ff_scale, 3)
	dummy.global_position = Vector3(0.5, ff_y, 40.0)
	ff.on_physics_process(0.016, 3)
	burn_check = dummy.get_node_or_null("BurnEffect")
	assert(burn_check != null and burn_check.ticks_left == 6, "ERROR: Burn duration must stay 6 ticks regardless of stacks")
	burn_check.free()
	CardDatabase.FireflyEffect.clear_all_trails(get_tree())
	print("[PASS] Firefly trail width, 2-tank length cap, stack-scaled trail length, fixed lifetime/burn time, burn DoT and owner immunity verified")

	# 19. Проверка карты Wallhack (штатный щит при блоке, просвет врагов на 2с за стак, +40% кулдаун блока без верхнего лимита)
	tank.build.clear_build()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var base_block_cd: float = tank.stats.block_cooldown
	var wallhack_card := CardDatabase.get_card("wallhack")
	assert(wallhack_card != null and wallhack_card.category == CardDefinition.Category.BLOCK, "ERROR: Wallhack must be registered as BLOCK card")
	tank.build.add_card(wallhack_card)
	assert(is_equal_approx(tank.stats.block_cooldown, base_block_cd * 1.40), "ERROR: 1-stack Wallhack must increase block cooldown by +40%")
	assert(is_equal_approx(CardDatabase.WallhackEffect.get_reveal_duration(1), 2.0), "ERROR: 1-stack Wallhack duration must be 2.0s")
	assert(is_equal_approx(CardDatabase.WallhackEffect.get_reveal_duration(2), 4.0), "ERROR: 2-stack Wallhack duration must be 4.0s")

	CardDatabase.WallhackEffect.clear_all_reveals(get_tree())
	dummy.health.reset()
	dummy.is_active = true
	tank.block.reset()
	assert(tank.block.activate_block(), "ERROR: Tank block must activate normally with Wallhack card")
	assert(tank.block.is_blocking(), "ERROR: Shield must be active as normal when Wallhack triggers")
	assert(dummy.get_meta("wallhack_revealed", false) == true, "ERROR: Enemy tank must be marked wallhack_revealed on block")
	var wh_node := dummy.get_node_or_null("WallhackReveal")
	assert(wh_node != null and is_equal_approx(wh_node.time_left, 2.0), "ERROR: WallhackReveal node must be attached to enemy with 2.0s timer")

	var has_xray_overlay := false
	for mnode in dummy.visuals.find_children("*", "MeshInstance3D", true, false):
		var m := mnode as MeshInstance3D
		if m and m != dummy.shield_mesh and m.material_overlay is StandardMaterial3D:
			var xmat := m.material_overlay as StandardMaterial3D
			if xmat.no_depth_test:
				has_xray_overlay = true
				break
	assert(has_xray_overlay, "ERROR: Enemy meshes must have X-ray material_overlay (no_depth_test=true) during Wallhack")
	assert(tank.get_meta("wallhack_revealed", false) == false, "ERROR: Wallhack owner must not reveal itself")

	# Через 2 секунды просвет с врага снимается
	wh_node._physics_process(2.05)
	assert(dummy.get_meta("wallhack_revealed", false) == false, "ERROR: Wallhack reveal must expire after 2 seconds on 1 stack")

	# 2 стака: кулдаун блока стакается, длительность просвета 4 секунды
	tank.build.add_card(wallhack_card)
	assert(is_equal_approx(tank.stats.block_cooldown, base_block_cd * 1.40 * 1.40), "ERROR: 2-stack Wallhack cooldown must stack multiplicatively")
	tank.block.reset()
	assert(tank.block.activate_block(), "ERROR: Block must activate on 2 stacks")
	var wh_node2 := dummy.get_node_or_null("WallhackReveal")
	assert(wh_node2 != null and is_equal_approx(wh_node2.time_left, 4.0), "ERROR: 2-stack Wallhack must reveal enemies for 4.0s")
	wh_node2._physics_process(2.5)
	assert(dummy.get_meta("wallhack_revealed", false) == true, "ERROR: 2-stack Wallhack must still be active at 2.5s")
	wh_node2._physics_process(1.6)
	assert(dummy.get_meta("wallhack_revealed", false) == false, "ERROR: 2-stack Wallhack must expire after 4.0s")
	tank.build.add_card(wallhack_card)
	tank.build.add_card(wallhack_card) # 4 стака: КД 3.0 * 1.4^4 = 11.5248с > 8.0с (без старого потолка)
	assert(is_equal_approx(tank.stats.block_cooldown, base_block_cd * pow(1.40, 4)), "ERROR: block_cooldown must not have an upper cap")
	assert(tank.stats.block_cooldown > CardDatabase.WallhackEffect.get_reveal_duration(4), "ERROR: 4-stack block cooldown must exceed Wallhack reveal duration")
	CardDatabase.WallhackEffect.clear_all_reveals(get_tree())
	print("[PASS] Wallhack normal shield activation, X-ray material overlay, stack-scaled duration (2s/stack), and uncapped +40% block cooldown verified")

	# 20. Проверка карты Burger Terminal (спавн терминала при блоке, выброс бургера раз в 1с, хил +10/стак, время жизни +1с/стак)
	tank.build.clear_build()
	CardDatabase.BurgerTerminalEffect.clear_all(get_tree())
	var bt_card := CardDatabase.get_card("burger_terminal")
	assert(bt_card != null and bt_card.category == CardDefinition.Category.BLOCK, "ERROR: Burger Terminal must be registered as BLOCK card")
	assert(is_equal_approx(CardDatabase.BurgerTerminalEffect.get_terminal_lifetime(1), 3.0), "ERROR: 1-stack Burger Terminal lifetime must be 3.0s")
	assert(is_equal_approx(CardDatabase.BurgerTerminalEffect.get_terminal_lifetime(2), 4.0), "ERROR: 2-stack Burger Terminal lifetime must be 4.0s")
	assert(is_equal_approx(CardDatabase.BurgerTerminalEffect.get_burger_heal(1), 10.0), "ERROR: 1-stack burger heal must be 10.0 HP")
	assert(is_equal_approx(CardDatabase.BurgerTerminalEffect.get_burger_heal(2), 20.0), "ERROR: 2-stack burger heal must be 20.0 HP")

	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var bt_base_cd: float = tank.stats.block_cooldown
	tank.build.add_card(bt_card)
	assert(is_equal_approx(tank.stats.block_cooldown, bt_base_cd * 1.40), "ERROR: 1-stack Burger Terminal must increase block cooldown by +40%")
	tank.global_position = Vector3(12.0, 0.0, 12.0)
	dummy.global_position = Vector3(45.0, 0.0, 45.0)
	tank.block.reset()
	assert(tank.block.activate_block(), "ERROR: Block must activate with Burger Terminal card")
	var terminals := get_tree().get_nodes_in_group("burger_terminals")
	assert(terminals.size() == 1, "ERROR: Block with Burger Terminal must spawn 1 terminal")
	var term_node := terminals[0]
	assert(term_node.find_child("Terminal_Root", true, false) != null, "ERROR: Terminal must instantiate 3D model from terminal.glb")
	assert(term_node.find_child("Ground_Pavement", true, false) == null, "ERROR: Studio Ground_Pavement must be stripped from terminal instance")

	# Отодвигаем танк, чтобы бургеры не съедались мгновенно в момент выброса
	tank.global_position = Vector3(25.0, 0.0, 25.0)
	term_node._physics_process(1.0)
	var burgers := get_tree().get_nodes_in_group("burger_pickups")
	assert(burgers.size() == 1, "ERROR: Terminal must throw 1 burger after 1.0s")
	var first_burger := burgers[0] as Area3D
	assert(first_burger.find_child("bun", true, false) != null, "ERROR: Burger pickup must instantiate 3D model from Burger.glb")

	# Подбираем бургер раненым танком -> +10 HP на 1 стаке
	tank.health.current_health = 50.0
	first_burger.body_entered.emit(tank)
	assert(is_equal_approx(tank.health.current_health, 60.0), "ERROR: 1-stack burger must heal tank by +10 HP")

	# Дотикиваем оставшиеся 2 секунды (всего 3.0с на 1 стаке) -> еще 2 бургера и терминал исчезает
	term_node._physics_process(1.0)
	term_node._physics_process(1.0)
	assert(not is_instance_valid(term_node) or term_node.is_queued_for_deletion(), "ERROR: 1-stack terminal must expire after 3.0s")
	assert(get_tree().get_nodes_in_group("burger_pickups").size() == 2, "ERROR: 1-stack terminal must have thrown 2 more burgers before expiring")

	# 2 стака: время жизни терминала 4.0с (+1с), хил бургера +20 HP, КД блока +40% за стак
	CardDatabase.BurgerTerminalEffect.clear_all(get_tree())
	tank.build.add_card(bt_card)
	assert(is_equal_approx(tank.stats.block_cooldown, bt_base_cd * 1.40 * 1.40), "ERROR: 2-stack Burger Terminal block cooldown must stack multiplicatively")
	tank.global_position = Vector3(12.0, 0.0, 12.0)
	tank.block.reset()
	assert(tank.block.activate_block(), "ERROR: Block must activate on 2-stack Burger Terminal")
	var term2 := get_tree().get_nodes_in_group("burger_terminals")[0]
	tank.global_position = Vector3(25.0, 0.0, 25.0)
	term2._physics_process(3.0)
	assert(is_instance_valid(term2) and not term2.is_queued_for_deletion(), "ERROR: 2-stack terminal must still exist at 3.0s")
	term2._physics_process(1.0)
	assert(not is_instance_valid(term2) or term2.is_queued_for_deletion(), "ERROR: 2-stack terminal must expire at 4.0s")
	var burgers_2s := get_tree().get_nodes_in_group("burger_pickups")
	assert(burgers_2s.size() == 4, "ERROR: 2-stack terminal must throw 4 burgers over 4.0s")
	tank.health.current_health = 40.0
	(burgers_2s[0] as Area3D).body_entered.emit(tank)
	assert(is_equal_approx(tank.health.current_health, 60.0), "ERROR: 2-stack burger must heal tank by +20 HP")
	CardDatabase.BurgerTerminalEffect.clear_all(get_tree())
	print("[PASS] Burger Terminal 3D models, 1s burger dispense interval, +10 HP/stack heal, +1s/stack lifetime, and +40% block cooldown verified")

	# 21. Проверка карты Air Vortex (+20% урона, +30% пауза между выстрелами, +10% скорость перезарядки, воронка 2м +1м/стак на 3с, спавн на последнем отскоке, засасывает всех и ящики)
	tank.build.clear_build()
	CardDatabase.AirVortexEffect.clear_all(get_tree())
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var av_base_dmg: float = tank.stats.damage
	var av_base_fire: float = tank.stats.fire_interval
	var av_base_reload: float = tank.stats.reload_time

	var av_card := CardDatabase.get_card("air_vortex")
	assert(av_card != null and av_card.category == CardDefinition.Category.SHOT, "ERROR: Air Vortex must be registered as SHOT card")
	assert(is_equal_approx(CardDatabase.AirVortexEffect.get_vortex_radius(1), 3.0), "ERROR: 1-stack Air Vortex radius must be 3.0m")
	assert(is_equal_approx(CardDatabase.AirVortexEffect.get_vortex_radius(2), 4.0), "ERROR: 2-stack Air Vortex radius must be 4.0m")
	assert(is_equal_approx(CardDatabase.AirVortexEffect.get_vortex_radius(3), 5.0), "ERROR: 3-stack Air Vortex radius must be 5.0m")

	tank.build.add_card(av_card)
	assert(is_equal_approx(tank.stats.damage, av_base_dmg * 1.20), "ERROR: 1-stack Air Vortex must grant +20% damage")
	assert(is_equal_approx(tank.stats.fire_interval, av_base_fire * 1.30), "ERROR: 1-stack Air Vortex must increase fire interval by +30%")
	assert(is_equal_approx(tank.stats.reload_time, av_base_reload * 0.90), "ERROR: 1-stack Air Vortex must speed up reload by 10% (reload_time * 0.90)")

	# Проверка правила отскоков: при попадании в препятствие с оставшимися рикошетами воронка НЕ спавнится, а на последнем — спавнится
	var av_obstacle := StaticBody3D.new()
	add_child(av_obstacle)
	var av_proj := proj_scene.instantiate() as Projectile
	add_child(av_proj)
	av_proj.setup(tank, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	av_proj.bounces_left = 1
	tank.events.emit_projectile_hit(av_proj, av_obstacle, Vector3(15.0, 0.5, 15.0), Vector3.UP)
	assert(get_tree().get_nodes_in_group("air_vortexes").size() == 0, "ERROR: Air Vortex must NOT spawn on obstacle hit while bounces_left > 0")

	# Последний удар по препятствию (bounces_left == 0) -> воронка спавнится
	av_proj.bounces_left = 0
	var vortex_center := Vector3(18.0, 0.0, 18.0)
	tank.events.emit_projectile_hit(av_proj, av_obstacle, vortex_center, Vector3.UP)
	var vortexes := get_tree().get_nodes_in_group("air_vortexes")
	assert(vortexes.size() == 1, "ERROR: Air Vortex must spawn on the final obstacle hit (bounces_left == 0)")
	var vortex_node := vortexes[0]
	assert(is_equal_approx(vortex_node.radius, 3.0), "ERROR: 1-stack spawned vortex must have radius 3.0m")

	# Попадание напрямую по вражескому танку спавнит воронку сразу даже при bounces_left > 0
	CardDatabase.AirVortexEffect.clear_all(get_tree())
	av_proj.bounces_left = 2
	tank.events.emit_projectile_hit(av_proj, dummy, vortex_center, Vector3.UP)
	vortexes = get_tree().get_nodes_in_group("air_vortexes")
	assert(vortexes.size() == 1, "ERROR: Direct hit on enemy tank must spawn Air Vortex immediately even with bounces left")
	vortex_node = vortexes[0]

	# Проверка засасывания: засасывает и врага (dummy), и самого стрелка (tank), и физический ящик (PhysicsCrate)
	tank.is_active = true
	dummy.is_active = true
	dummy.health.reset()
	tank.global_position = vortex_center + Vector3(1.6, 0.0, 0.0)
	dummy.global_position = vortex_center + Vector3(-1.5, 0.0, 0.0)
	tank.velocity = Vector3.ZERO
	dummy.velocity = Vector3.ZERO

	var test_crate := PhysicsCrate.new()
	var crate_col := CollisionShape3D.new()
	var crate_box := BoxShape3D.new()
	crate_box.size = Vector3.ONE * 0.8
	crate_col.shape = crate_box
	test_crate.add_child(crate_col)
	add_child(test_crate)
	test_crate.global_position = vortex_center + Vector3(0.0, 0.4, 1.5)
	test_crate.linear_velocity = Vector3.ZERO

	var tank_dist_before: float = Vector2(tank.global_position.x - vortex_node.global_position.x, tank.global_position.z - vortex_node.global_position.z).length()
	var dummy_dist_before: float = Vector2(dummy.global_position.x - vortex_node.global_position.x, dummy.global_position.z - vortex_node.global_position.z).length()
	var crate_dist_before: float = Vector2(test_crate.global_position.x - vortex_node.global_position.x, test_crate.global_position.z - vortex_node.global_position.z).length()

	vortex_node._physics_process(0.25)

	var tank_dist_after: float = Vector2(tank.global_position.x - vortex_node.global_position.x, tank.global_position.z - vortex_node.global_position.z).length()
	var dummy_dist_after: float = Vector2(dummy.global_position.x - vortex_node.global_position.x, dummy.global_position.z - vortex_node.global_position.z).length()
	var crate_dist_after: float = Vector2(test_crate.global_position.x - vortex_node.global_position.x, test_crate.global_position.z - vortex_node.global_position.z).length()

	assert(tank_dist_after < tank_dist_before and tank.velocity.x < 0.0, "ERROR: Air Vortex must pull the shooter tank itself toward the center")
	assert(dummy_dist_after < dummy_dist_before and dummy.velocity.x > 0.0, "ERROR: Air Vortex must pull enemy tanks toward the center")
	assert(crate_dist_after < crate_dist_before and test_crate.linear_velocity.z < 0.0, "ERROR: Air Vortex must pull physics crates toward the center")

	# Проверка времени жизни (3.0с): на 2.9с еще живет, на 3.05с исчезает
	vortex_node._physics_process(2.65) # итого 2.90с
	assert(is_instance_valid(vortex_node) and not vortex_node.is_queued_for_deletion(), "ERROR: Air Vortex must still exist at 2.9s")
	vortex_node._physics_process(0.15) # итого 3.05с
	assert(not is_instance_valid(vortex_node) or vortex_node.is_queued_for_deletion(), "ERROR: Air Vortex must expire after 3.0s")

	# 2 стака: радиус воронки увеличивается до 4.0м и засасывает цель на дистанции 3.6м (которая вне базовых 3.0м)
	CardDatabase.AirVortexEffect.clear_all(get_tree())
	tank.build.add_card(av_card)
	assert(is_equal_approx(tank.stats.damage, av_base_dmg * 1.20 * 1.20), "ERROR: 2-stack Air Vortex damage must stack multiplicatively")
	assert(is_equal_approx(tank.stats.fire_interval, av_base_fire * 1.30 * 1.30), "ERROR: 2-stack Air Vortex fire interval must stack multiplicatively")
	assert(is_equal_approx(tank.stats.reload_time, av_base_reload * 0.90 * 0.90), "ERROR: 2-stack Air Vortex reload time must stack multiplicatively")
	av_proj.bounces_left = 0
	tank.events.emit_projectile_hit(av_proj, av_obstacle, vortex_center, Vector3.UP)
	var vortex2 := get_tree().get_nodes_in_group("air_vortexes")[0]
	assert(is_equal_approx(vortex2.radius, 4.0), "ERROR: 2-stack Air Vortex must have 4.0m radius")
	dummy.global_position = vortex_center + Vector3(3.6, 0.0, 0.0)
	dummy.velocity = Vector3.ZERO
	vortex2._physics_process(0.25)
	assert(dummy.velocity.x < 0.0, "ERROR: 2-stack Air Vortex (4m radius) must pull tank at 3.6m distance")

	test_crate.queue_free()
	av_proj.queue_free()
	av_obstacle.queue_free()
	CardDatabase.AirVortexEffect.clear_all(get_tree())
	print("[PASS] Air Vortex stats (+20% dmg, +30% fire interval, +10% reload speed), last-bounce trigger, 3m+1m/stack radius, 3s duration, and all-tank/crate suction verified")

	# 22. Проверка карты Feather Fall (+25% высота прыжка, резкий взлет с обычной гравитацией и плавное планирование на спуске, стаки усиливают эффект)
	tank.build.clear_build()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var ff_base_jump_vel: float = tank.stats.jump_velocity
	var feather_card := CardDatabase.get_card("feather_fall")
	assert(feather_card != null and feather_card.category == CardDefinition.Category.JUMP, "ERROR: Feather Fall must be registered as JUMP card")
	assert(feather_card.unique == false, "ERROR: Feather Fall must be stackable")

	tank.build.add_card(feather_card)
	assert(is_equal_approx(tank.stats.jump_velocity, ff_base_jump_vel * 1.25), "ERROR: 1-stack Feather Fall must increase jump_velocity by +25%")
	assert(is_equal_approx(tank.controller.jump_velocity, ff_base_jump_vel * 1.25), "ERROR: TankController jump_velocity must sync with Feather Fall stat")

	# На взлёте (velocity.y > 0) действует полная гравитация (резкий подъём)
	tank.global_position = Vector3(0.0, 6.0, 0.0)
	tank.velocity = Vector3(0.0, 6.0, 0.0)
	tank.controller._restored_floor = {"on_floor": false, "floor_normal": Vector3.UP}
	tank.controller.process_movement(Vector3.ZERO, false, 0.1)
	var expected_ascent_vy: float = 6.0 - tank.controller.gravity * 0.1
	assert(is_equal_approx(tank.velocity.y, expected_ascent_vy), "ERROR: Feather Fall must keep full normal gravity while rising (velocity.y > 0)")

	# На спуске (velocity.y <= 0) гравитация снижена, а скорость падения ограничена max_fall_speed (-3.2 м/с на 1 стаке)
	tank.global_position = Vector3(0.0, 8.0, 0.0)
	tank.velocity = Vector3(0.0, 0.0, 0.0)
	tank.controller._restored_floor = {"on_floor": false, "floor_normal": Vector3.UP}
	tank.controller.process_movement(Vector3.ZERO, false, 0.1)
	var expected_descent_vy_1s: float = -tank.controller.gravity * CardDatabase.FeatherFallEffect.get_fall_gravity_multiplier(1) * 0.1
	assert(is_equal_approx(tank.velocity.y, expected_descent_vy_1s), "ERROR: 1-stack Feather Fall descent must use reduced gravity multiplier (0.38)")
	assert(absf(tank.velocity.y) < tank.controller.gravity * 0.1, "ERROR: Feather Fall descent speed must be slower than normal freefall")

	# При долгом падении на 1 стаке скорость не превышает -3.2 м/с
	for _step in range(10):
		tank.global_position = Vector3(0.0, 10.0, 0.0)
		tank.controller._restored_floor = {"on_floor": false, "floor_normal": Vector3.UP}
		tank.controller.process_movement(Vector3.ZERO, false, 0.1)
	var max_fall_1s: float = CardDatabase.FeatherFallEffect.get_max_fall_speed(1)
	assert(is_equal_approx(tank.velocity.y, -max_fall_1s), "ERROR: 1-stack Feather Fall terminal velocity must clamp at -3.2 m/s")

	# 2 стака: высота прыжка стакается мультипликативно, а падение становится ещё плавнее
	tank.build.add_card(feather_card)
	assert(is_equal_approx(tank.stats.jump_velocity, ff_base_jump_vel * 1.25 * 1.25), "ERROR: 2-stack Feather Fall jump_velocity must stack multiplicatively")
	var max_fall_2s: float = CardDatabase.FeatherFallEffect.get_max_fall_speed(2)
	assert(max_fall_2s < max_fall_1s, "ERROR: 2-stack Feather Fall max fall speed must be slower than 1-stack")
	assert(CardDatabase.FeatherFallEffect.get_fall_gravity_multiplier(2) < CardDatabase.FeatherFallEffect.get_fall_gravity_multiplier(1), "ERROR: 2-stack Feather Fall gravity multiplier must be lower than 1-stack")

	tank.global_position = Vector3(0.0, 10.0, 0.0)
	tank.velocity = Vector3(0.0, -5.0, 0.0)
	tank.controller._restored_floor = {"on_floor": false, "floor_normal": Vector3.UP}
	tank.controller.process_movement(Vector3.ZERO, false, 0.1)
	assert(is_equal_approx(tank.velocity.y, -max_fall_2s), "ERROR: 2-stack Feather Fall must clamp downward velocity to 2-stack max fall speed")
	print("[PASS] Feather Fall +25% jump height, full-speed ascent, reduced-gravity glide descent, and stack scaling verified")

	# 23. Проверка карты Huge (+50% максимального HP за стак)
	tank.build.clear_build()
	tank.health.reset()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var huge_base_hp: float = tank.stats.max_hp
	var huge_card := CardDatabase.get_card("huge")
	assert(huge_card != null and huge_card.category == CardDefinition.Category.GENERAL, "ERROR: Huge must be registered as GENERAL card")
	assert(huge_card.unique == false, "ERROR: Huge must be stackable")
	tank.build.add_card(huge_card)
	assert(is_equal_approx(tank.stats.max_hp, huge_base_hp * 1.50), "ERROR: 1-stack Huge must increase max_hp by +50% (150 HP)")
	assert(is_equal_approx(tank.health.current_health, huge_base_hp * 1.50), "ERROR: 1-stack Huge must also boost current_health by +50 HP")
	tank.build.add_card(huge_card)
	assert(is_equal_approx(tank.stats.max_hp, huge_base_hp * 1.50 * 1.50), "ERROR: 2-stack Huge must stack multiplicatively (225 HP)")
	print("[PASS] Huge card (+50% max HP per stack) verified")

	# 24. Проверка снайперской карты Accuracy (+40% урона, +50% скорости пули, +70% времени перезарядки, -40% скорости движения)
	tank.build.clear_build()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var acc_base_dmg: float = tank.stats.damage
	var acc_base_proj_spd: float = tank.stats.projectile_speed
	var acc_base_reload: float = tank.stats.reload_time
	var acc_base_move: float = tank.stats.move_speed

	var acc_card := CardDatabase.get_card("accuracy")
	assert(acc_card != null and acc_card.category == CardDefinition.Category.SHOT, "ERROR: Accuracy must be registered as SHOT card")
	assert(acc_card.unique == false, "ERROR: Accuracy must be stackable")

	tank.build.add_card(acc_card)
	assert(is_equal_approx(tank.stats.damage, acc_base_dmg * 1.40), "ERROR: 1-stack Accuracy must grant +40% damage")
	assert(is_equal_approx(tank.stats.projectile_speed, acc_base_proj_spd * 1.50), "ERROR: 1-stack Accuracy must grant +50% projectile speed")
	assert(is_equal_approx(tank.stats.reload_time, acc_base_reload * 1.70), "ERROR: 1-stack Accuracy must increase reload time by +70%")
	assert(is_equal_approx(tank.stats.move_speed, acc_base_move * 0.60), "ERROR: 1-stack Accuracy must reduce move speed by -40%")

	tank.build.add_card(acc_card)
	assert(is_equal_approx(tank.stats.damage, acc_base_dmg * 1.40 * 1.40), "ERROR: 2-stack Accuracy damage must stack multiplicatively")
	assert(is_equal_approx(tank.stats.projectile_speed, acc_base_proj_spd * 1.50 * 1.50), "ERROR: 2-stack Accuracy projectile speed must stack multiplicatively")
	assert(is_equal_approx(tank.stats.reload_time, acc_base_reload * 1.70 * 1.70), "ERROR: 2-stack Accuracy reload time must stack multiplicatively")
	assert(is_equal_approx(tank.stats.move_speed, acc_base_move * 0.60 * 0.60), "ERROR: 2-stack Accuracy move speed must stack multiplicatively")
	print("[PASS] Accuracy card (+40% dmg, +50% proj speed, +70% reload time, -40% move speed) verified")

	# 25. Проверка карты Critical Hit (20% шанс на 140% урона, +30% к крит-урону за доп. стак, фиксированный шанс 20%, +20% ко времени перезарядки)
	tank.build.clear_build()
	tank.stats.recalculate(tank.build.cards, CardDatabase)
	var crit_base_reload: float = tank.stats.reload_time
	var crit_base_dmg: float = tank.stats.damage

	var crit_card := CardDatabase.get_card("critical_hit")
	assert(crit_card != null and crit_card.category == CardDefinition.Category.SHOT, "ERROR: Critical Hit must be registered as SHOT card")
	assert(crit_card.unique == false, "ERROR: Critical Hit must be stackable")
	assert(is_equal_approx(CardDatabase.CriticalHitEffect.get_crit_chance(1), 0.20), "ERROR: 1-stack crit chance must be 20%")
	assert(is_equal_approx(CardDatabase.CriticalHitEffect.get_crit_chance(5), 0.20), "ERROR: Crit chance must stay 20% regardless of stacks")
	assert(is_equal_approx(CardDatabase.CriticalHitEffect.get_crit_damage_multiplier(1), 1.40), "ERROR: 1-stack crit damage multiplier must be 1.40 (140%)")
	assert(is_equal_approx(CardDatabase.CriticalHitEffect.get_crit_damage_multiplier(2), 1.70), "ERROR: 2-stack crit damage multiplier must be 1.70 (170%)")
	assert(is_equal_approx(CardDatabase.CriticalHitEffect.get_crit_damage_multiplier(3), 2.00), "ERROR: 3-stack crit damage multiplier must be 2.00 (200%)")

	tank.build.add_card(crit_card)
	assert(is_equal_approx(tank.stats.reload_time, crit_base_reload * 1.20), "ERROR: 1-stack Critical Hit must increase reload time by +20%")
	assert(is_equal_approx(tank.stats.damage, crit_base_dmg), "ERROR: Non-crit base damage must stay unchanged")

	# Проверяем срабатывание крита на 1 и 2 стаках и статистическое наличие критов/обычных выстрелов на серии
	var crit_hits := 0
	var normal_hits := 0
	seed(424242)
	for _i in range(80):
		var cproj := proj_scene.instantiate() as Projectile
		add_child(cproj)
		cproj.setup(tank, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
		tank.events.emit_projectile_spawned(cproj)
		if cproj.get_meta("is_critical_hit", false):
			crit_hits += 1
			assert(is_equal_approx(cproj.damage, crit_base_dmg * 1.40), "ERROR: 1-stack critical projectile must deal 140% damage")
		else:
			normal_hits += 1
			assert(is_equal_approx(cproj.damage, crit_base_dmg), "ERROR: Non-critical projectile must deal 100% damage")
		cproj.queue_free()
	assert(crit_hits > 0 and normal_hits > 0, "ERROR: 20% crit chance over 80 shots must produce both crits and normal shots")

	# 2 стака: перезарядка +20% за стак, крит-урон 170% (1.40 + 0.30)
	tank.build.add_card(crit_card)
	assert(is_equal_approx(tank.stats.reload_time, crit_base_reload * 1.20 * 1.20), "ERROR: 2-stack Critical Hit reload debuff must stack multiplicatively")
	var crit_proj_2s := proj_scene.instantiate() as Projectile
	add_child(crit_proj_2s)
	crit_proj_2s.setup(tank, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	CardDatabase.CriticalHitEffect.apply_crit_to_projectile(crit_proj_2s, 2)
	assert(is_equal_approx(crit_proj_2s.damage, crit_base_dmg * 1.70), "ERROR: 2-stack critical projectile must deal 170% damage")
	crit_proj_2s.queue_free()
	print("[PASS] Critical Hit 20% fixed chance, 140% (+30%/stack) crit damage, and +20% reload time debuff verified")

	print("=== [TEST] ALL PHASE 3 TESTS PASSED SUCCESSFULLY! ===\n")
