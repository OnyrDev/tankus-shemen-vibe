extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return true
	_tested = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("\n=== [TEST] Starting Phase 2 (Combat Foundation) Verification ===")

	# 1. Загрузка песочницы
	var sandbox_scene := load("res://maps/test_sandbox.tscn") as PackedScene
	assert(sandbox_scene != null, "ERROR: Failed to load test_sandbox.tscn")
	var sandbox := sandbox_scene.instantiate() as TestSandbox
	root.add_child(sandbox)
	print("[PASS] Sandbox scene instantiated successfully")

	# 2. Проверка ключевых узлов и компонентов игрока и манекена
	var tank: Tank = sandbox.get_node_or_null("Tank")
	var dummy: Tank = sandbox.get_node_or_null("DummyTank")
	var hud: HUD = sandbox.get_node_or_null("HUD")

	assert(tank != null, "ERROR: Player Tank not found")
	assert(dummy != null, "ERROR: DummyTank not found")
	assert(hud != null, "ERROR: HUD not found")

	assert(tank.weapon != null, "ERROR: WeaponComponent missing on Tank")
	assert(tank.block != null, "ERROR: BlockComponent missing on Tank")
	assert(tank.health != null, "ERROR: HealthComponent missing on Tank")
	assert(tank.shield_mesh != null, "ERROR: ShieldMesh missing on Tank")
	print("[PASS] All Phase 2 combat components verified on Tank")

	# 3. Проверка параметров магазина и стрельбы
	assert(tank.weapon.magazine_size == 4, "ERROR: Magazine size should be 4")
	assert(tank.weapon.current_ammo == 4, "ERROR: Initial ammo should be 4")
	assert(tank.weapon.can_fire() == true, "ERROR: Tank should be able to fire initially")

	var shot_capture := {"received": false, "proj": null}
	tank.weapon.shot_fired.connect(func(proj: Projectile):
		shot_capture["received"] = true
		shot_capture["proj"] = proj
	)

	var fired := tank.weapon.try_fire()
	assert(fired == true, "ERROR: try_fire() returned false")
	assert(tank.weapon.current_ammo == 3, "ERROR: Ammo should decrease to 3 after firing")
	assert(shot_capture["received"] == true, "ERROR: shot_fired signal was not emitted")
	var spawned_proj: Projectile = shot_capture["proj"]
	assert(spawned_proj != null, "ERROR: Spawned projectile is null")
	assert(spawned_proj.speed == 24.0, "ERROR: Projectile speed should be 24.0")
	assert(spawned_proj.damage == 28.0, "ERROR: Projectile damage should be 28.0")
	print("[PASS] Weapon firing, ammo decrement, and projectile spawn verified")

	# 4. Проверка скорострельности (Fire Interval = 0.55s)
	var immediate_second_shot := tank.weapon.try_fire()
	assert(immediate_second_shot == false, "ERROR: Second shot should be blocked by fire cooldown")

	# Симулируем прохождение 0.56 секунды
	tank.weapon._physics_process(0.56)
	assert(tank.weapon.can_fire() == true, "ERROR: Weapon should be ready to fire after 0.56s cooldown")
	print("[PASS] Fire rate cooldown (0.55s) verified")

	# 5. Проверка автоматической и ручной перезарядки
	tank.weapon.try_fire() # ammo -> 2
	tank.weapon._physics_process(0.56)
	tank.weapon.try_fire() # ammo -> 1
	tank.weapon._physics_process(0.56)
	tank.weapon.try_fire() # ammo -> 0 (должна начаться перезарядка)

	assert(tank.weapon.current_ammo == 0, "ERROR: Ammo should be 0")
	assert(tank.weapon.is_reloading() == true, "ERROR: Auto-reload should start when ammo hits 0")

	# Симулируем часть перезарядки
	tank.weapon._physics_process(1.0)
	assert(tank.weapon.is_reloading() == true, "ERROR: Should still be reloading after 1.0s")
	assert(tank.weapon.get_reload_ratio() > 0.5, "ERROR: Reload progress ratio incorrect")

	# Симулируем завершение перезарядки (1.8s)
	tank.weapon._physics_process(0.85)
	assert(tank.weapon.is_reloading() == false, "ERROR: Reload should finish after total 1.85s")
	assert(tank.weapon.current_ammo == 4, "ERROR: Ammo should be restored to 4")
	print("[PASS] Empty magazine auto-reload (1.8s) verified")

	# 6. Проверка защитного блока (щита)
	assert(tank.block.can_block() == true, "ERROR: Block should be available")
	var block_activated := tank.block.activate_block()
	assert(block_activated == true, "ERROR: activate_block returned false")
	assert(tank.block.is_blocking() == true, "ERROR: is_blocking() should be true")
	assert(tank.block.is_on_cooldown() == true, "ERROR: is_on_cooldown() should be true")

	# Повторный блок во время действия невозможен
	assert(tank.block.activate_block() == false, "ERROR: Duplicate block activation should fail")

	# Симулируем окончание окна блока (0.35s)
	tank.block._physics_process(0.36)
	assert(tank.block.is_blocking() == false, "ERROR: Block window should end after 0.35s")
	assert(tank.block.is_on_cooldown() == true, "ERROR: Cooldown should still be active")

	# Симулируем прохождение оставшегося кулдауна (2.7s)
	tank.block._physics_process(2.7)
	assert(tank.block.is_on_cooldown() == false, "ERROR: Cooldown should expire after 3.0s")
	assert(tank.block.can_block() == true, "ERROR: Block should be ready again")
	print("[PASS] Block duration (0.35s) and cooldown (3.0s) verified")

	# 7. Проверка поглощения урона и уничтожения снаряда щитом
	dummy.health.reset()
	dummy.block.activate_block()
	assert(dummy.block.is_blocking() == true, "ERROR: Dummy tank should be blocking")

	var block_capture := {"received": false}
	dummy.block.successful_block.connect(func(_p: Node):
		block_capture["received"] = true
	)

	# Создаем тестовый снаряд
	var test_proj_scene := load("res://projectile/projectile.tscn") as PackedScene
	var test_proj := test_proj_scene.instantiate() as Projectile
	root.add_child(test_proj)
	test_proj.setup(tank, dummy.global_position + Vector3(0, 0, 1), Vector3(0, 0, -1))

	# Передаем снаряд на поглощение
	dummy.block.absorb_projectile(test_proj)
	assert(block_capture["received"] == true, "ERROR: successful_block signal was not emitted")
	assert(dummy.health.current_health == 100.0, "ERROR: Dummy tank should not take damage when blocking")
	print("[PASS] Shield projectile absorption and damage negation verified")

	# 8. Проверка нанесения урона незащищенному танку
	dummy.block.reset()
	assert(dummy.block.is_blocking() == false, "ERROR: Dummy should not be blocking after reset")
	var took_damage := dummy.health.take_damage(28.0, tank)
	assert(took_damage == true, "ERROR: take_damage returned false")
	assert(dummy.health.current_health == 72.0, "ERROR: Dummy HP should be 72.0 (100 - 28)")
	print("[PASS] Unprotected projectile damage (28 HP) verified")

	# 9. Проверка гибели танка при 0 HP
	var died_capture := {"received": false}
	dummy.health.died.connect(func(_killer: Node):
		died_capture["received"] = true
	)
	dummy.health.take_damage(72.0, tank)
	assert(dummy.health.current_health == 0.0, "ERROR: Dummy HP should be 0")
	assert(dummy.health.is_alive() == false, "ERROR: is_alive() should be false")
	assert(dummy.is_active == false, "ERROR: Dummy tank is_active should be false when destroyed")
	assert(died_capture["received"] == true, "ERROR: died signal was not emitted")
	print("[PASS] Tank death, active state disabling, and death signal verified")

	# 10. Проверка респавна
	dummy.respawn()
	assert(dummy.is_active == true, "ERROR: Dummy should be active after respawn")
	assert(dummy.health.current_health == 100.0, "ERROR: Dummy HP should be restored to 100")
	assert(dummy.weapon.current_ammo == 4, "ERROR: Dummy ammo should be restored to 4")
	assert(dummy.block.can_block() == true, "ERROR: Dummy block should be ready after respawn")
	print("[PASS] Respawn and component reset verified")

	print("=== [TEST] ALL PHASE 2 TESTS PASSED SUCCESSFULLY! ===\n")
