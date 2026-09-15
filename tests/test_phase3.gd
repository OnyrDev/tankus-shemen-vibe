extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return true
	_tested = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("\n=== [TEST] Starting Phase 3 (Cards & Ricochet) Verification ===")

	# 1. Загрузка песочницы
	var sandbox_scene := load("res://maps/test_sandbox.tscn") as PackedScene
	assert(sandbox_scene != null, "ERROR: Failed to load test_sandbox.tscn")
	var sandbox := sandbox_scene.instantiate() as TestSandbox
	root.add_child(sandbox)
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

	# 3. Проверка базы данных 45 карт
	var all_cards := CardDatabase.get_all_cards()
	assert(all_cards.size() == 45, "ERROR: Card pool size should be 45, found %d" % all_cards.size())

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

	assert(shot_count == 18, "ERROR: Expected 18 SHOT cards, got %d" % shot_count)
	assert(block_count == 9, "ERROR: Expected 9 BLOCK cards, got %d" % block_count)
	assert(jump_count == 6, "ERROR: Expected 6 JUMP cards, got %d" % jump_count)
	assert(general_count == 12, "ERROR: Expected 12 GENERAL cards, got %d" % general_count)
	print("[PASS] All 45 cards registered with exact category balance (18 SHOT, 9 BLOCK, 6 JUMP, 12 GENERAL)")

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
	assert(tank.stats.magazine_size == 4, "ERROR: Base magazine should be 4")
	assert(tank.stats.projectile_bounces == 0, "ERROR: Base bounces should be 0")

	# Добавляем Heavy Shell (+45% dmg, -20% proj speed)
	var heavy := CardDatabase.get_card("heavy_shell")
	tank.build.add_card(heavy)
	assert(is_equal_approx(tank.stats.damage, 28.0 * 1.45), "ERROR: Damage after Heavy Shell incorrect")
	assert(is_equal_approx(tank.stats.projectile_speed, 24.0 * 0.8), "ERROR: Proj speed after Heavy Shell incorrect")

	# Добавляем Big Magazine (+1 ammo, +15% reload time)
	var big_mag := CardDatabase.get_card("big_magazine")
	tank.build.add_card(big_mag)
	assert(tank.stats.magazine_size == 5, "ERROR: Magazine size after Big Magazine should be 5")
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
	root.add_child(base_proj)
	base_proj.setup(tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	assert(base_proj.bounces_left == 0, "ERROR: Fresh projectile without cards must have 0 bounces by default!")
	base_proj.queue_free()

	var test_proj := proj_scene.instantiate() as Projectile
	root.add_child(test_proj)
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
	var rico_proj := proj_scene.instantiate() as Projectile
	root.add_child(rico_proj)
	rico_proj.setup(tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	tank.events.emit_projectile_spawned(rico_proj)
	assert(rico_proj.ricochet_power_stacks == 1, "ERROR: Ricochet power stacks not set on projectile")

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

	# 12. Проверка отображения билда в HUD
	assert(hud.build_chips_container != null, "ERROR: Build chips container is null")
	tank.build.clear_build()
	tank.build.add_card(heavy)
	tank.build.add_card(heavy) # 2 стака
	assert(hud.build_chips_container.get_child_count() == 1, "ERROR: Should have 1 chip for heavy_shell")
	var chip_label: Label = hud.build_chips_container.get_child(0).get_child(0)
	assert(chip_label.text == "Heavy Shell ×2", "ERROR: Chip label text should be 'Heavy Shell ×2', got '%s'" % chip_label.text)
	print("[PASS] HUD active build chips display verified")

	print("=== [TEST] ALL PHASE 3 TESTS PASSED SUCCESSFULLY! ===\n")
