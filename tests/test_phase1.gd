extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return true
	_tested = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("\n=== [TEST] Starting Phase 1 (TPS) Verification ===")

	# 1. Загрузка песочницы
	var sandbox_scene := load("res://maps/test_sandbox.tscn") as PackedScene
	assert(sandbox_scene != null, "ERROR: Failed to load test_sandbox.tscn")
	var sandbox := sandbox_scene.instantiate()
	root.add_child(sandbox)
	print("[PASS] Sandbox scene instantiated successfully")

	# 2. Проверка ключевых нод
	var tank: Tank = sandbox.get_node_or_null("Tank")
	assert(tank != null, "ERROR: Tank node not found in sandbox")
	var camera: TPSCamera = sandbox.get_node_or_null("TPSCamera")
	assert(camera != null, "ERROR: TPSCamera not found in sandbox")
	assert(camera.get_camera() != null, "ERROR: Inner Camera3D is null")
	var kill_volume: Area3D = sandbox.get_node_or_null("KillVolume")
	assert(kill_volume != null, "ERROR: KillVolume not found in sandbox")
	print("[PASS] All required nodes exist in sandbox (Tank, TPSCamera, KillVolume)")

	# 3. Проверка компонентов танка
	assert(tank.input != null, "ERROR: TankInput is null")
	assert(tank.controller != null, "ERROR: TankController is null")
	assert(tank.turret != null, "ERROR: Turret is null")
	print("[PASS] Tank components verified (Input, Controller, Turret)")

	# 4. Проверка поворота башни
	var initial_yaw := tank.turret.global_rotation.y
	var target_point := tank.global_position + Vector3(10.0, 0.0, 0.0) # строго справа
	tank.turret.aim_at(target_point, 0.5)
	assert(tank.turret.global_rotation.y != initial_yaw, "ERROR: Turret did not rotate towards target")
	print("[PASS] Turret aiming and rotation verified")

	# 5. Проверка физического движения контроллера
	tank.input.move_direction_world = Vector3(0.0, 0.0, -1.0) # вперед
	tank.controller.process_physics(tank.input, 0.1)
	assert(tank.velocity.z < 0.0, "ERROR: Tank velocity.z should be negative when moving forward")
	print("[PASS] Tank forward movement physics verified")

	# 6. Проверка прыжка
	tank.global_position.y = 0.0
	tank.velocity = Vector3.ZERO
	tank.controller._coyote_timer = 0.1
	tank.input.jump_requested = true
	tank.controller.process_physics(tank.input, 0.016)
	assert(tank.velocity.y > 0.0, "ERROR: Tank jump velocity should be positive")
	print("[PASS] Tank jump physics verified")

	# 7. Проверка респавна при падении
	var start_pos := tank.spawn_point.origin
	tank.global_position = Vector3(100.0, -15.0, 100.0) # улетел за пределы
	tank.respawn()
	assert(tank.global_position.is_equal_approx(start_pos), "ERROR: Tank respawn failed to restore position")
	print("[PASS] Tank respawn verified")

	# 8. Проверка цвета команды
	tank.set_team_color(Color.CORAL)
	assert(tank.team_color == Color.CORAL, "ERROR: Team color was not applied")
	print("[PASS] Dynamic team color verified")

	print("=== [TEST] ALL PHASE 1 (TPS) TESTS PASSED SUCCESSFULLY! ===\n")
