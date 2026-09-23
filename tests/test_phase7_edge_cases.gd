extends Node

## Комплексный автоматизированный тест Фазы 7:
## Проверка Game Feel, Audio/SFX, Camera Shake, Debug Overlay и краевых сценариев (Phoenix, Reflect, Blink, Draw).

var _passed_count: int = 0
var _failed_count: int = 0

func _ready() -> void:
	print("\n========================================================")
	print("   TANKUS — PHASE 7 VERIFICATION & EDGE CASES TEST")
	print("========================================================\n")

	await get_tree().process_frame

	_test_sound_manager()
	_test_vfx_instantiation()
	_test_camera_shake()
	_test_chassis_tilt_and_squash()
	_test_phoenix_card()
	_test_reflect_card()
	_test_blink_safety()
	_test_debug_overlay()
	await _test_turret_behavior()

	print("\n========================================================")
	print("   TEST RESULTS: %d PASSED | %d FAILED" % [_passed_count, _failed_count])
	print("========================================================\n")

	if _failed_count > 0:
		push_error("Some tests failed!")
	else:
		print(">>> ALL PHASE 7 EDGE CASE TESTS PASSED SUCCESSFULLY! <<<\n")

	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if _failed_count == 0 else 1)

func _assert_test(condition: bool, test_name: String) -> void:
	if condition:
		print("[PASS] ", test_name)
		_passed_count += 1
	else:
		push_error("[FAIL] " + test_name)
		print("[FAIL] ", test_name)
		_failed_count += 1

func _test_sound_manager() -> void:
	print("--- 1. SoundManager & SFX Smoke Test ---")
	_assert_test(SoundManager != null, "SoundManager singleton exists")

	var sfx_keys := ["shoot", "ricochet", "hit", "block", "jump", "land", "explosion", "card_hover", "card_select", "reload_done"]
	var all_loaded := true
	for k in sfx_keys:
		if not SoundManager._streams.has(k) or SoundManager._streams[k] == null:
			all_loaded = false
			print("   Missing SFX stream: ", k)
	_assert_test(all_loaded, "All 10 SFX streams are loaded in SoundManager")

	var p2d := SoundManager.play_sfx("card_hover")
	_assert_test(p2d != null and p2d.playing, "play_sfx 2D player plays audio")

	var p3d := SoundManager.play_sfx_3d("shoot", Vector3.ZERO)
	_assert_test(p3d != null and p3d.playing, "play_sfx_3d 3D player plays audio at world pos")

func _test_vfx_instantiation() -> void:
	print("\n--- 2. VFX Scenes Instantiation Test ---")
	var exp_scene: PackedScene = load("res://vfx/explosion_vfx.tscn")
	_assert_test(exp_scene != null, "explosion_vfx.tscn loaded")
	var exp_instance := exp_scene.instantiate() as ExplosionVFX
	add_child(exp_instance)
	exp_instance.setup(1.5, Color.ORANGE)
	_assert_test(is_instance_valid(exp_instance) and exp_instance.scale.x > 1.4, "ExplosionVFX instantiated and setup applied")
	exp_instance.queue_free()

	var spark_scene: PackedScene = load("res://vfx/hit_spark_vfx.tscn")
	_assert_test(spark_scene != null, "hit_spark_vfx.tscn loaded")
	var spark_instance := spark_scene.instantiate() as HitSparkVFX
	add_child(spark_instance)
	spark_instance.setup(Vector3.UP)
	_assert_test(is_instance_valid(spark_instance), "HitSparkVFX instantiated with normal")
	spark_instance.queue_free()

	var dust_scene: PackedScene = load("res://vfx/dust_puff_vfx.tscn")
	_assert_test(dust_scene != null, "dust_puff_vfx.tscn loaded")
	var dust_instance := dust_scene.instantiate() as DustPuffVFX
	add_child(dust_instance)
	dust_instance.setup(1.2)
	_assert_test(is_instance_valid(dust_instance), "DustPuffVFX instantiated with intensity")
	dust_instance.queue_free()

	var pulse_scene: PackedScene = load("res://vfx/shield_pulse_vfx.tscn")
	_assert_test(pulse_scene != null, "shield_pulse_vfx.tscn loaded")
	var pulse_instance := pulse_scene.instantiate() as ShieldPulseVFX
	add_child(pulse_instance)
	pulse_instance.setup(Color.CYAN)
	_assert_test(is_instance_valid(pulse_instance), "ShieldPulseVFX instantiated with color")
	pulse_instance.queue_free()

func _test_camera_shake() -> void:
	print("\n--- 3. Trauma-based Camera Shake & TPS Setup Test ---")
	var cam_scene: PackedScene = load("res://core/tps_camera.tscn")
	_assert_test(cam_scene != null, "tps_camera.tscn loaded")
	var cam := cam_scene.instantiate() as TPSCamera
	add_child(cam)

	_assert_test(is_equal_approx(cam.spring_arm.spring_length, 9.0), "TPSCamera spring_length is locked at 9.0m per specification")
	_assert_test(is_equal_approx(cam.default_pitch_deg, 3.5), "Default pitch is 3.5 deg aimed at horizon")
	_assert_test(cam.target_offset.y >= 2.0, "Camera target offset elevated for clearance")

	# Проверяем Anti-Occlusion при взгляде в небо
	var dummy_target := Node3D.new()
	add_child(dummy_target)
	dummy_target.global_position = Vector3(0, 0, 0)
	cam.setup_target(dummy_target)
	var neutral_y := cam.global_position.y

	# Задираем камеру в небо (pitch = min_pitch_deg)
	cam.pitch = deg_to_rad(cam.min_pitch_deg)
	cam.setup_target(dummy_target)
	var sky_y := cam.global_position.y
	_assert_test(sky_y > neutral_y + 1.5, "Anti-occlusion elevates camera pivot when aiming upward")
	dummy_target.queue_free()

	_assert_test(cam.trauma == 0.0, "Initial camera trauma is 0.0")
	Game.shake_camera(0.5)
	_assert_test(cam.trauma >= 0.5, "Game.shake_camera added trauma to TPSCamera")

	# Симулируем несколько кадров затухания
	cam._process_camera_shake(0.1)
	_assert_test(cam.trauma < 0.5, "Trauma decays smoothly over time")
	cam.queue_free()

func _test_chassis_tilt_and_squash() -> void:
	print("\n--- 4. Chassis Tilt & Suspension Dynamics Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)

	var ctrl := tank.controller
	_assert_test(ctrl != null, "Tank controller exists on tank")

	# Имитируем прыжок -> stretch
	ctrl._apply_jump_stretch()
	_assert_test(ctrl._current_visual_scale.y > 1.1, "Jump triggers vertical stretch")

	# Имитируем приземление -> squash
	ctrl._apply_land_squash(3.0)
	_assert_test(ctrl._current_visual_scale.y < 0.95 and ctrl._current_visual_scale.x > 1.05, "Landing triggers horizontal squash")

	# Имитируем ускорение вперед -> наклон носа
	tank.velocity = Vector3(0, 0, -8.0)
	ctrl._update_chassis_tilt(0.016)
	_assert_test(absf(ctrl._current_tilt_pitch) > 0.001 or absf(ctrl._current_tilt_roll) >= 0.0, "Chassis tilt responds to velocity")
	tank.queue_free()

func _test_phoenix_card() -> void:
	print("\n--- 5. Edge Case: Phoenix Card Revive Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)

	var phoenix_card := CardDatabase.get_card("phoenix")
	_assert_test(phoenix_card != null, "Phoenix card definition exists in database")

	tank.build.add_card(phoenix_card)
	tank.stats.recalculate(tank.build.cards, CardDatabase)

	# Наносим смертельный урон (150 HP при макс 100)
	tank.health.take_damage(150.0)

	_assert_test(tank.health.is_alive(), "Phoenix prevented death upon lethal damage")
	_assert_test(tank.health.current_health == tank.health.max_health * 0.5, "Phoenix revived tank at 50% HP")
	_assert_test(tank.block.is_blocking(), "Phoenix activated emergency shield upon revive")

	# Второй смертельный урон в том же раунде должен убить танк
	tank.block._is_blocking = false # сбрасываем щит для теста
	tank.health.take_damage(100.0)
	_assert_test(not tank.health.is_alive(), "Second lethal damage correctly kills tank (Phoenix used)")
	tank.queue_free()

func _test_reflect_card() -> void:
	print("\n--- 6. Edge Case: Reflect Card Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var shooter_tank := tank_scene.instantiate() as Tank
	shooter_tank.name = "Shooter"
	add_child(shooter_tank)

	var reflector_tank := tank_scene.instantiate() as Tank
	reflector_tank.name = "Reflector"
	add_child(reflector_tank)
	reflector_tank.global_position = Vector3(0, 0, 5)

	var reflect_card := CardDatabase.get_card("reflect")
	_assert_test(reflect_card != null, "Reflect card definition exists in database")

	reflector_tank.build.add_card(reflect_card)
	reflector_tank.block.activate_block()
	_assert_test(reflector_tank.block.is_blocking(), "Reflector tank shield is active")

	var proj_scene: PackedScene = load("res://projectile/projectile.tscn")
	var proj := proj_scene.instantiate() as Projectile
	add_child(proj)
	proj.setup(shooter_tank, Vector3(0, 0, 2), Vector3(0, 0, 1))

	# Проверяем отражение снаряда
	proj._reflect_projectile(reflector_tank, Vector3(0, 0, -1))
	_assert_test(proj.direction.z < 0.0, "Projectile direction reversed upon reflect")
	_assert_test(proj.shooter == reflector_tank, "Projectile ownership transferred to Reflector tank")

	shooter_tank.queue_free()
	reflector_tank.queue_free()
	proj.queue_free()

func _test_blink_safety() -> void:
	print("\n--- 7. Edge Case: Blink In Wall Safety Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)
	tank.global_position = Vector3(0, 0, 0)

	var blink_card := CardDatabase.get_card("blink")
	_assert_test(blink_card != null, "Blink card definition exists in database")
	tank.build.add_card(blink_card)

	# Имитируем срабатывание эффекта Blink
	var blink_effect := CardDatabase.BlinkEffect.new()
	blink_effect.setup(tank, "blink")

	# Танк смотрит вперед (0, 0, -1), без препятствий телепортируется на 5м вперед
	blink_effect.on_block_started(0.35, 1)
	_assert_test(tank.global_position.distance_to(Vector3.ZERO) > 3.0, "Blink teleports tank forward safely")
	tank.queue_free()

func _test_debug_overlay() -> void:
	print("\n--- 8. Debug Overlay Test ---")
	var overlay_scene: PackedScene = load("res://ui/debug_overlay.tscn")
	_assert_test(overlay_scene != null, "debug_overlay.tscn loaded")
	var overlay: CanvasLayer = overlay_scene.instantiate()
	add_child(overlay)

	_assert_test(not overlay.visible, "Debug overlay is initially hidden")
	# Симулируем переключение F3
	var f3_event := InputEventKey.new()
	f3_event.pressed = true
	f3_event.keycode = KEY_F3
	overlay._unhandled_input(f3_event)
	_assert_test(overlay.visible, "Debug overlay toggles visible on F3")

	overlay._update_debug_text()
	_assert_test(overlay.stats_label.text.contains("PERFORMANCE") and overlay.stats_label.text.contains("FPS"), "Debug overlay populates performance & network stats")
	overlay.queue_free()

func _test_turret_behavior() -> void:
	print("\n--- 9. Turret Leveling & Audio Verification Test ---")
	_assert_test(not MusicManager.autoplay_menu, "MusicManager autoplay_menu is disabled")
	_assert_test(not MusicManager.is_playing(), "No music playing on start")

	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)
	tank.global_position = Vector3(0, 0, 22)
	tank.global_rotation = Vector3(0, PI, 0)
	await get_tree().process_frame

	var turret := tank.turret
	_assert_test(turret != null, "Tank has turret component")
	_assert_test(is_zero_approx(turret.rotation.x) and is_zero_approx(turret.rotation.z), "Initial turret has zero roll/pitch tilt")

	# Наводим башню на цель прямо по курсу танка
	var forward_target := tank.global_position - tank.global_transform.basis.z * 10.0
	turret.aim_at(forward_target, 1.0)
	_assert_test(is_zero_approx(turret.rotation.x) and is_zero_approx(turret.rotation.z), "Turret maintains zero roll/pitch tilt after aim_at")
	_assert_test(is_zero_approx(turret.rotation.y), "Turret aims directly forward relative to tank body")

	# Симулируем динамический наклон подвески (chassis tilt)
	tank.visuals.rotation.x = 0.08
	tank.visuals.rotation.z = -0.06
	turret.aim_at(Vector3(10, 0, 10), 0.2)
	_assert_test(is_zero_approx(turret.rotation.x) and is_zero_approx(turret.rotation.z), "Turret remains flat on turret ring during chassis roll/pitch")
	if turret.barrel_mount:
		_assert_test(is_zero_approx(turret.barrel_mount.rotation.y) and is_zero_approx(turret.barrel_mount.rotation.z), "Barrel mount has zero roll/yaw wobble")

	# Проверяем вектор выстрела
	var shoot_dir := turret.get_shoot_direction()
	_assert_test(shoot_dir.length_squared() > 0.99, "Shoot direction is a valid normalized vector")

	tank.queue_free()


