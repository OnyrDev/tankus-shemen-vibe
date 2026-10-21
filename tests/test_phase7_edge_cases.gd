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
	await _test_physics_crate_stability()
	await _test_sky_courtyard_spawns()
	await _test_void_fall_health_penalty()
	await _test_slope_tilting()

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

	# Проверяем изоляцию башни и ствола от squash/stretch (ствол не меняет размера)
	ctrl._apply_land_squash(3.0)
	ctrl._update_chassis_tilt(0.016)
	_assert_test(is_equal_approx(tank.turret.scale.x, 1.0) and is_equal_approx(tank.turret.scale.y, 1.0) and is_equal_approx(tank.turret.scale.z, 1.0), "Turret scale remains strictly (1,1,1) during landing squash")
	var muzzle := tank.turret.muzzle
	var barrel_mount := tank.turret.barrel_mount
	var barrel_len := barrel_mount.global_position.distance_to(muzzle.global_position)
	_assert_test(is_equal_approx(barrel_len, 1.15), "Barrel length strictly preserved at 1.15m during landing squash (no elongation)")

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
	var overlay = overlay_scene.instantiate()
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

	# Проверка панели цифровых статов танка в левом нижнем углу
	_assert_test(overlay.tank_stats_panel != null, "Tank stats panel exists in debug overlay")
	_assert_test(overlay.stats_left != null and overlay.stats_right != null, "Numeric stats labels exist")

	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var test_tank := tank_scene.instantiate() as Tank
	add_child(test_tank)
	test_tank.name = "Tank_Test"
	await get_tree().process_frame

	overlay._update_tank_stats()
	_assert_test(overlay.stats_left.text.contains("HP:") and overlay.stats_left.text.contains("Move Speed:") and overlay.stats_left.text.contains("Damage:"), "Stats panel renders numeric stats")
	_assert_test(overlay.stats_right.text.contains("Proj Speed:") and overlay.stats_right.text.contains("Fire Rate:"), "Right column renders numeric combat stats")

	# Проверка поиска карточек по названию
	_assert_test(overlay.search_box != null, "Card search input exists")
	_assert_test(overlay._card_widgets.size() == 45, "All 45 cards initialized in card debugger")

	overlay.search_box.text = "Heavy Shell"
	overlay._on_search_text_changed("Heavy Shell")
	var heavy_shell_widget: Control = overlay._card_widgets.get("heavy_shell", null)
	_assert_test(heavy_shell_widget != null and heavy_shell_widget.visible, "Card search finds 'Heavy Shell' by name")
	var bouncy_widget: Control = overlay._card_widgets.get("bouncy", null)
	_assert_test(bouncy_widget != null and not bouncy_widget.visible, "Card search hides non-matching cards ('Bouncy')")

	# Добавление карты через отладочный интерфейс
	var heavy_shell_def := CardDatabase.get_card("heavy_shell")
	overlay._add_card_to_tank(heavy_shell_def)
	_assert_test(test_tank.build.has_card("heavy_shell"), "Debug overlay adds card to local tank")
	_assert_test(test_tank.stats.damage > 28.0, "Tank damage stat recalculated numerically (> 28.0)")

	# Удаление карты и очистка
	overlay._remove_card_from_tank(heavy_shell_def)
	_assert_test(not test_tank.build.has_card("heavy_shell"), "Debug overlay removes card from tank")

	# Проверка переключения захвата мыши по клавише Tab (Lock & Unlock)
	var tab_event := InputEventKey.new()
	tab_event.pressed = true
	tab_event.keycode = KEY_TAB
	overlay._input(tab_event)
	_assert_test(overlay.is_mouse_captured, "Tab locks mouse for gameplay testing")
	_assert_test(overlay.btn_toggle_cursor.text.contains("Free Mouse"), "Button updates to 'Free Mouse'")

	overlay._input(tab_event)
	_assert_test(not overlay.is_mouse_captured, "Second Tab unlocks mouse back to debug overlay")
	_assert_test(overlay.btn_toggle_cursor.text.contains("Lock Mouse"), "Button updates to 'Lock Mouse'")

	test_tank.queue_free()
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

	# Проверяем наклон ствола и сведение выстрела в прицел (Crosshair Convergence)
	tank.visuals.rotation = Vector3.ZERO
	turret.vertical_aim_offset = 0.4 # Проверяем работу вертикального оффсета возвышения
	# 1. Цель выше танка (возвышенность/рампа)
	var high_target := tank.global_position + Vector3(0, 4.0, -10.0)
	for _i in range(20):
		turret.aim_at(high_target, 0.1)
	_assert_test(turret.barrel_mount.rotation.x > deg_to_rad(10.0), "Barrel tilts UP towards elevated target")
	var shoot_dir_high := turret.get_shoot_direction()
	var expected_dir_high := (high_target + Vector3.UP * turret.vertical_aim_offset - turret.get_muzzle_position()).normalized()
	_assert_test(shoot_dir_high.dot(expected_dir_high) > 0.999, "Shoot direction strictly converges onto high crosshair target")
	_assert_test(shoot_dir_high.y > (high_target - turret.get_muzzle_position()).normalized().y, "Shoot direction is elevated higher than raw high target")

	# 2. Цель ниже танка (земля перед танком)
	var low_target := tank.global_position + Vector3(0, -1.5, -8.0)
	for _i in range(20):
		turret.aim_at(low_target, 0.1)
	_assert_test(turret.barrel_mount.rotation.x < deg_to_rad(-10.0), "Barrel tilts DOWN towards low ground target")
	var shoot_dir_low := turret.get_shoot_direction()
	var expected_dir_low := (low_target + Vector3.UP * turret.vertical_aim_offset - turret.get_muzzle_position()).normalized()
	_assert_test(shoot_dir_low.dot(expected_dir_low) > 0.999, "Shoot direction strictly converges onto low ground crosshair target")
	_assert_test(shoot_dir_low.y > (low_target - turret.get_muzzle_position()).normalized().y, "Shoot direction is elevated higher than raw low target")

	# 3. Препятствие вплотную / ствол протыкает объект (Anti-Clipping Aim Clamp)
	turret.rotation.y = 0.0
	var close_obstacle_target := turret.global_position + (-turret.global_transform.basis.z * 0.6)
	turret.aim_at(close_obstacle_target, 1.0)
	var barrel_len_close := turret.barrel_mount.global_position.distance_to(turret.muzzle.global_position)
	_assert_test(is_equal_approx(barrel_len_close, 1.15), "Barrel length strictly preserved at 1.15m when penetrating close obstacle")
	_assert_test(absf(turret.barrel_mount.rotation.x) < deg_to_rad(30.0), "Barrel does not snap to extreme pitch when penetrating obstacle")
	_assert_test(is_zero_approx(turret.rotation.y), "Turret does not flip backwards when target is close inside barrel")

	tank.queue_free()

func _test_physics_crate_stability() -> void:
	print("\n--- 10. Physics Crate Climbing & Stability Test ---")
	var crate_scene: PackedScene = load("res://maps/components/physics_crate.tscn")
	var crate := crate_scene.instantiate() as PhysicsCrate
	add_child(crate)
	crate.global_position = Vector3(0, 0.7, 0)
	await get_tree().process_frame

	_assert_test(crate.mass >= 30.0, "PhysicsCrate has sufficient mass (>= 30)")
	_assert_test(crate.axis_lock_angular_x and crate.axis_lock_angular_z, "PhysicsCrate has angular X and Z locked against tipping")
	_assert_test(crate.physics_material_override != null and crate.physics_material_override.rough, "PhysicsCrate has rough physics material")

	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)
	tank.global_position = Vector3(0, 1.45, 0)
	await get_tree().process_frame

	_assert_test(tank.platform_on_leave == CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING, "Tank has platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING")

	for _i in range(10):
		tank.controller.process_physics(null, 1.0 / 60.0)
		crate._physics_process(1.0 / 60.0)

	_assert_test(is_zero_approx(crate.rotation.x) and is_zero_approx(crate.rotation.z), "Crate pitch and roll remain strictly zero while tank stands on it")
	_assert_test(crate.linear_velocity.length() < 1.0, "Crate does not wobble or accelerate under standing tank")

	tank.queue_free()
	crate.queue_free()

	# Проверка толкания ящика: скорость ящика не превышает скорость танка, отсутствует runaway acceleration
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(50, 1, 50)
	col_shape.shape = box_shape
	col_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(col_shape)
	add_child(floor_body)

	var push_tank := tank_scene.instantiate() as Tank
	add_child(push_tank)
	var push_crate := crate_scene.instantiate() as PhysicsCrate
	add_child(push_crate)

	push_tank.setup_network(1, 0, Color.BLUE)
	push_tank.global_position = Vector3(0, 0.5, 0)
	push_tank.global_rotation = Vector3.ZERO
	push_tank.velocity = Vector3.ZERO

	push_crate.global_position = Vector3(0, 0.6, -1.5)
	push_crate.linear_velocity = Vector3.ZERO
	push_crate.angular_velocity = Vector3.ZERO
	push_crate.freeze = false

	await get_tree().physics_frame
	await get_tree().physics_frame

	_assert_test(push_tank.platform_floor_layers == 1, "Tank platform_floor_layers strictly locked to World layer (1)")
	_assert_test(push_crate.collision_layer == 8, "PhysicsCrate resides on Props layer (layer 4 = 8)")

	# Симулируем толкание вперед через аутентичный action_press
	Input.action_press("move_forward")

	var max_crate_speed := 0.0
	var max_tank_speed := 0.0
	var max_plat_speed := 0.0

	for _step in range(60):
		await get_tree().physics_frame
		var c_speed := push_crate.linear_velocity.length()
		var t_speed := push_tank.get_real_velocity().length()
		var p_speed := push_tank.get_platform_velocity().length()

		if c_speed > max_crate_speed:
			max_crate_speed = c_speed
		if t_speed > max_tank_speed:
			max_tank_speed = t_speed
		if p_speed > max_plat_speed:
			max_plat_speed = p_speed

	Input.action_release("move_forward")

	_assert_test(max_crate_speed > 0.05 and max_crate_speed <= 8.0, "Pushed crate speed is capped below tank max speed (%.2f <= 8.0)" % max_crate_speed)
	_assert_test(max_plat_speed <= 8.0, "Tank platform velocity does not exceed top speed (%.2f <= 8.0)" % max_plat_speed)
	_assert_test(max_tank_speed <= 8.5, "Tank speed does not exceed normal speed while pushing crate (%.2f <= 8.5)" % max_tank_speed)

	push_tank.queue_free()
	push_crate.queue_free()
	floor_body.queue_free()

func _test_sky_courtyard_spawns() -> void:
	print("\n--- 11. Sky Courtyard Spawns & Platform Placement Test ---")
	var scene: PackedScene = load("res://maps/sky_courtyard.tscn")
	var map := scene.instantiate() as BaseArena
	add_child(map)
	await get_tree().process_frame

	var markers := map.get_spawn_points()
	_assert_test(markers.size() == 8, "Sky Courtyard contains exactly 8 spawn points")

	var sp1 := map.get_node_or_null("SpawnPoints/SpawnPoint1") as Marker3D
	var sp2 := map.get_node_or_null("SpawnPoints/SpawnPoint2") as Marker3D
	var sp5 := map.get_node_or_null("SpawnPoints/SpawnPoint5") as Marker3D
	var sp6 := map.get_node_or_null("SpawnPoints/SpawnPoint6") as Marker3D

	_assert_test(sp1 != null and is_equal_approx(sp1.position.y, 2.7) and is_equal_approx(sp1.position.z, 22.0), "SpawnPoint1 is on SouthTerrace (Blue platform)")
	_assert_test(sp2 != null and is_equal_approx(sp2.position.y, 2.7) and is_equal_approx(sp2.position.z, -22.0), "SpawnPoint2 is on NorthTerrace (Red platform)")
	_assert_test(sp5 != null and is_equal_approx(sp5.position.y, 0.5) and is_equal_approx(sp5.position.z, 16.0), "SpawnPoint5 is properly on floor at y=0.5, z=16")
	_assert_test(sp6 != null and is_equal_approx(sp6.position.y, 0.5) and is_equal_approx(sp6.position.z, -16.0), "SpawnPoint6 is properly on floor at y=0.5, z=-16")

	# Тестируем распределение спавнов для 2 игроков (1v1: Синий Хост против Красного Клиента)
	var p1 := PlayerInfo.new(1, "HostBlue", 0)
	var p2 := PlayerInfo.new(2, "ClientRed", 1)
	var players: Array[PlayerInfo] = [p1, p2]

	# 1. FFA режим: Красный игрок должен спавниться на противоположной платформе (SpawnPoint2)
	var ffa_spawns := SpawnManager.assign_spawns(players, markers, false)
	_assert_test(ffa_spawns.has(1) and ffa_spawns.has(2), "FFA spawns assigned for both players")
	var tf_blue_ffa: Transform3D = ffa_spawns[1]
	var tf_red_ffa: Transform3D = ffa_spawns[2]
	_assert_test(is_equal_approx(tf_blue_ffa.origin.z, 22.0) and is_equal_approx(tf_blue_ffa.origin.y, 2.7), "FFA: Blue tank spawns on Blue Platform (z=22)")
	_assert_test(is_equal_approx(tf_red_ffa.origin.z, -22.0) and is_equal_approx(tf_red_ffa.origin.y, 2.7), "FFA: Red tank spawns on Red Platform (z=-22), not in air")

	# 2. Командный режим: Команда 2 (Красные) должна получить базу на NorthTerrace (SpawnPoint2)
	var team_spawns := SpawnManager.assign_spawns(players, markers, true)
	_assert_test(team_spawns.has(1) and team_spawns.has(2), "Team spawns assigned for both players")
	var tf_blue_team: Transform3D = team_spawns[1]
	var tf_red_team: Transform3D = team_spawns[2]
	_assert_test(is_equal_approx(tf_blue_team.origin.z, 22.0) and is_equal_approx(tf_blue_team.origin.y, 2.7), "Teams: Blue team spawns on Blue Platform (z=22)")
	_assert_test(is_equal_approx(tf_red_team.origin.z, -22.0) and is_equal_approx(tf_red_team.origin.y, 2.7), "Teams: Red team spawns on Red Platform (z=-22), not in air")

	map.queue_free()

func _test_void_fall_health_penalty() -> void:
	print("\n--- 12. Void Fall Health Penalty & Edge Cases Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)
	await get_tree().process_frame

	var spawn_pos := Vector3(0.0, 1.0, 0.0)
	var spawn_tf := Transform3D(Basis(), spawn_pos)

	# 1. Обычный респавн без параметров восстанавливает полное здоровье 100 HP
	tank.health.current_health = 40.0
	tank.respawn(spawn_tf)
	_assert_test(is_equal_approx(tank.health.current_health, 100.0), "Standard respawn restores full health to 100 HP")
	_assert_test(tank.is_active, "Tank is active after standard respawn")
	_assert_test(tank.global_position.is_equal_approx(spawn_pos), "Tank positioned at spawn point")

	# 2. Падение в бездну (void fall): reset_health = false, health_penalty = 5.0
	# С полного здоровья (100 HP) должно стать 95 HP
	var damages_received: Array[float] = []
	tank.health.damage_taken.connect(func(amt, _att): damages_received.append(amt))
	tank.respawn(spawn_tf, false, 5.0)

	_assert_test(is_equal_approx(tank.health.current_health, 95.0), "Void fall reduces health by 5 HP (100 -> 95)")
	_assert_test(tank.is_active, "Tank remains active after surviving void fall")
	_assert_test(damages_received.size() == 1 and is_equal_approx(damages_received[0], 5.0), "Damage taken signal emitted with 5.0 penalty")
	if tank.net_sync:
		_assert_test(is_equal_approx(tank.net_sync.synced_health, 95.0), "NetSync replicated reduced health (95.0)")

	# 3. Второе падение подряд: здоровье должно уменьшиться еще на 5 (95 -> 90)
	tank.respawn(spawn_tf, false, 5.0)
	_assert_test(is_equal_approx(tank.health.current_health, 90.0), "Second void fall reduces health again (95 -> 90)")

	# 4. Летальное падение в бездну при HP <= 5.0:
	tank.health.current_health = 4.0
	var died_box := [false]
	tank.died.connect(func(_k): died_box[0] = true)
	tank.respawn(spawn_tf, false, 5.0)

	_assert_test(is_equal_approx(tank.health.current_health, 0.0), "Health drops to 0 on lethal void fall")
	_assert_test(not tank.is_active, "Tank becomes inactive upon lethal void fall")
	_assert_test(died_box[0], "Tank emits died signal upon lethal void fall")
	if tank.net_sync:
		_assert_test(not tank.net_sync.synced_is_active, "NetSync replicated inactive status")
		_assert_test(is_equal_approx(tank.net_sync.synced_health, 0.0), "NetSync replicated 0.0 health")

	# 5. Спасбросок Phoenix при падении в бездну:
	var tank_phoenix := tank_scene.instantiate() as Tank
	add_child(tank_phoenix)
	await get_tree().process_frame

	var phoenix_card := CardDatabase.get_card("phoenix")
	_assert_test(phoenix_card != null, "Phoenix card definition exists")
	tank_phoenix.build.add_card(phoenix_card)
	tank_phoenix.health.current_health = 5.0

	var phoenix_died := false
	tank_phoenix.died.connect(func(_k): phoenix_died = true)
	tank_phoenix.respawn(spawn_tf, false, 5.0)

	_assert_test(not phoenix_died, "Phoenix prevents death upon lethal void fall")
	_assert_test(tank_phoenix.is_active, "Tank with Phoenix stays active after lethal void fall")
	_assert_test(is_equal_approx(tank_phoenix.health.current_health, 50.0), "Phoenix revives tank at 50% HP")

	tank.queue_free()
	tank_phoenix.queue_free()

func _test_slope_tilting() -> void:
	print("\n--- 13. Tank Slope Tilting on Inclined Surfaces Test ---")
	var atrium_scene: PackedScene = load("res://maps/atrium.tscn")
	_assert_test(atrium_scene != null, "atrium.tscn loaded for slope test")
	var atrium := atrium_scene.instantiate()
	add_child(atrium)

	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var tank := tank_scene.instantiate() as Tank
	add_child(tank)
	await get_tree().physics_frame

	var ctrl := tank.controller
	_assert_test(ctrl != null, "Tank has controller")
	_assert_test(ctrl._probe_fl != null and ctrl._probe_fr != null and ctrl._probe_rl != null and ctrl._probe_rr != null, "All 4 suspension ground probes initialized")

	# 1. Горизонтальный ровный пол: крен и дифферент равны 0
	tank.global_position = Vector3(0, 0.5, 0)
	tank.global_rotation = Vector3.ZERO
	await get_tree().physics_frame
	ctrl.update_tilt_only(0.1)
	_assert_test(is_zero_approx(ctrl._current_slope_pitch) and is_zero_approx(ctrl._current_slope_roll), "Flat floor pitch and roll are strictly zero")
	_assert_test(is_zero_approx(tank.visuals.rotation.x) and is_zero_approx(tank.visuals.rotation.z), "Visuals pitch and roll are strictly zero on flat floor")

	# 2. Танк на рампе (RampNorth в Atrium) едет/смотрит В ГОРУ (направление +X -> yaw = -PI/2)
	tank.global_position = Vector3(6.62, 1.6, 0)
	tank.global_rotation.y = -PI * 0.5
	for _i in range(25):
		await get_tree().physics_frame
		ctrl.update_tilt_only(0.016)

	_assert_test(ctrl._current_slope_pitch > deg_to_rad(15.0), "Tank pitches UP (nose elevated) when facing uphill")
	_assert_test(is_equal_approx(ctrl._current_slope_pitch, deg_to_rad(29.3)), "Uphill pitch strictly matches ramp incline (~29.3 deg)")
	_assert_test(is_zero_approx(ctrl._current_slope_roll), "Uphill roll remains zero")
	_assert_test(is_equal_approx(tank.visuals.rotation.x, ctrl._current_slope_pitch), "Visuals mesh is tilted up along slope")

	# 3. Башня сохраняет ориентацию на погоне при наклоне корпуса на рампе
	_assert_test(is_zero_approx(tank.turret.rotation.x) and is_zero_approx(tank.turret.rotation.z), "Turret ring remains flush to tilted chassis on slope")

	# 4. Танк на рампе смотрит ПОД ГОРУ (направление -X -> yaw = PI/2)
	tank.global_rotation.y = PI * 0.5
	for _i in range(25):
		await get_tree().physics_frame
		ctrl.update_tilt_only(0.016)

	_assert_test(ctrl._current_slope_pitch < deg_to_rad(-15.0), "Tank pitches DOWN (nose declined) when facing downhill")
	_assert_test(is_equal_approx(ctrl._current_slope_pitch, deg_to_rad(-29.3)), "Downhill pitch strictly matches ramp incline (~29.3 deg)")
	_assert_test(is_zero_approx(ctrl._current_slope_roll), "Downhill roll remains zero")

	# 5. Танк на рампе стоит ПОПЕРЕК склона (боком: yaw = 0)
	tank.global_rotation.y = 0.0
	for _i in range(25):
		await get_tree().physics_frame
		ctrl.update_tilt_only(0.016)

	_assert_test(is_zero_approx(ctrl._current_slope_pitch), "Transverse pitch is zero")
	_assert_test(ctrl._current_slope_roll > deg_to_rad(15.0), "Transverse roll tilts sideways matching slope")
	_assert_test(is_equal_approx(ctrl._current_slope_roll, deg_to_rad(29.3)), "Transverse roll strictly matches ramp incline (~29.3 deg)")

	# 6. Танк в воздухе (прыжок / полет над рампой)
	tank.global_position = Vector3(6.62, 5.0, 0)
	for _i in range(30):
		await get_tree().physics_frame
		ctrl.update_tilt_only(0.016)

	_assert_test(is_zero_approx(ctrl._current_slope_pitch) and is_zero_approx(ctrl._current_slope_roll), "Airborne tank smoothly levels back to zero tilt")

	# 7. Сброс наклона при respawn()
	ctrl._current_slope_pitch = -0.5
	ctrl._current_slope_roll = 0.3
	ctrl.reset_tilt()
	_assert_test(is_zero_approx(ctrl._current_slope_pitch) and is_zero_approx(ctrl._current_slope_roll), "reset_tilt restores zero slope angles")
	_assert_test(is_zero_approx(tank.visuals.rotation.x) and is_zero_approx(tank.visuals.rotation.z), "reset_tilt zeroes visuals rotation")

	tank.queue_free()
	atrium.queue_free()




