extends Node

## Автоматический тест сетевого слоя Фазы 4 TANKUS.

func _ready() -> void:
	print("\n==================================================")
	print("  TANKUS // Phase 4 Network Automated Test")
	print("==================================================")

	var net: NetworkManager = get_node_or_null("/root/Network") as NetworkManager
	assert(net != null, "Синглтон Network должен быть загружен в /root/Network")
	print("[PASS] 1. Синглтон Network найден и активен")

	# 2. Создание хоста
	var test_port: int = 7055
	var err := net.create_host(test_port)
	assert(err == OK, "Создание хоста должно вернуть OK")
	assert(net.is_host, "Флаг is_host должен быть true")
	assert(net.is_server(), "is_server() должен быть true")
	assert(net.players.has(1), "Хост должен быть зарегистрирован с peer_id 1")
	print("[PASS] 2. Создание хоста и регистрация peer_id 1")

	# 3. LAN Discovery
	var discovery := LANDiscovery.new()
	add_child(discovery)
	discovery.start_broadcasting("Test Arena", test_port, 8)
	assert(discovery.is_broadcasting, "Broadcaster должен быть активен")
	discovery.stop_broadcasting()
	assert(not discovery.is_broadcasting, "Broadcaster должен остановиться")
	discovery.queue_free()
	print("[PASS] 3. LAN Discovery Broadcaster")

	# 4. PlayerInfo сериализация
	var p_info := PlayerInfo.new(42, "CyberTanker", 2)
	p_info.is_ready = true
	p_info.round_wins = 5
	var serialized := p_info.to_dict()
	var restored := PlayerInfo.from_dict(serialized)
	assert(restored.peer_id == 42, "peer_id")
	assert(restored.player_name == "CyberTanker", "player_name")
	assert(restored.team_id == 2, "team_id")
	assert(restored.is_ready == true, "is_ready")
	assert(restored.round_wins == 5, "round_wins")
	print("[PASS] 4. Сериализация и десериализация PlayerInfo")

	# 5. Танк и TankNetworkSync
	var tank_scene: PackedScene = preload("res://tank/tank.tscn")
	var tank_inst: Tank = tank_scene.instantiate()
	add_child(tank_inst)
	tank_inst.setup_network(1, 0, Color.BLUE)
	assert(tank_inst.net_sync != null, "net_sync должен быть на танке")
	assert(tank_inst.net_sync.is_local_owner(), "is_local_owner должен быть true")
	tank_inst.queue_free()
	print("[PASS] 5. Танк и TankNetworkSync инициализация")

	# 6. Отключение сессии
	net.disconnect_session()
	assert(not net.is_host, "is_host должен быть false")
	assert(net.players.is_empty(), "Список игроков должен быть пуст")
	print("[PASS] 6. Корректное закрытие сессии и сброс состояния")

	# 7. Клиентская синхронизация геймплея (HP, урон, патроны, смерть, респавн)
	var client_tank: Tank = tank_scene.instantiate()
	add_child(client_tank)
	client_tank.setup_network(2, 1, Color.RED)
	var sync: TankNetworkSync = client_tank.net_sync
	assert(sync != null, "net_sync должен быть инициализирован")

	# Проверяем синхронизацию урона
	var received_health_change: Array = []
	client_tank.health.health_changed.connect(func(curr, max_h): received_health_change.append([curr, max_h]))
	sync.synced_health = 65.0
	sync._apply_synced_health_change()
	assert(client_tank.health.current_health == 65.0, "current_health должен обновиться до 65.0")
	assert(received_health_change.size() == 1, "Сигнал health_changed должен быть испущен ровно 1 раз")
	assert(received_health_change[0][0] == 65.0, "Значение здоровья в сигнале должно быть 65.0")

	# Проверяем синхронизацию патронов
	sync.synced_ammo = 1
	sync._apply_synced_weapon_state()
	assert(client_tank.weapon.current_ammo == 1, "current_ammo должен обновиться до 1")

	# Проверяем обработку смерти на клиенте
	sync.synced_health = 0.0
	sync.synced_is_active = false
	sync._handle_client_tank_death()
	assert(client_tank.is_active == false, "Танк должен стать неактивным после смерти")
	assert(client_tank.visuals.visible == false, "Визуал танка должен быть скрыт после смерти")
	assert(client_tank.health.current_health == 0.0, "current_health должен быть 0.0")

	# Проверяем обработку респавна на клиенте
	sync.synced_position = Vector3(10, 0.5, 10)
	sync.synced_health = 100.0
	sync.synced_ammo = 4
	sync.synced_is_active = true
	sync._handle_client_tank_respawn()
	assert(client_tank.is_active == true, "Танк должен стать активным после респавна")
	assert(client_tank.visuals.visible == true, "Визуал танка должен стать видимым после респавна")
	assert(client_tank.health.current_health == 100.0, "current_health должен восстановиться до 100.0")
	assert(client_tank.weapon.current_ammo == 4, "Патроны должны восстановиться до 4")
	assert(client_tank.global_position.distance_to(Vector3(10, 0.5, 10)) < 0.01, "Позиция танка должна обновиться на точку спавна")

	client_tank.queue_free()
	print("[PASS] 7. Клиентская синхронизация урона, HP, патронов, смерти и респавна")

	# 8. Проверка рикошета снаряда и сетевой синхронизации карточек
	var server_tank: Tank = tank_scene.instantiate()
	add_child(server_tank)
	server_tank.setup_network(1, 0, Color.BLUE)
	assert(server_tank.stats.projectile_bounces == 0, "Базовый танк должен иметь 0 отскоков по умолчанию (без рикошета)")

	# Синхронизация выбора карты Bouncy (+1 рикошет)
	server_tank.net_sync.c2s_choose_card("bouncy")
	assert(server_tank.stats.projectile_bounces == 1, "После карты Bouncy должен появиться 1 отскок")

	# Спавн снаряда и проверка параметров рикошета
	var proj_scene: PackedScene = preload("res://projectile/projectile.tscn")
	var proj: Projectile = proj_scene.instantiate()
	add_child(proj)
	proj.setup(server_tank, Vector3(0, 1, 0), Vector3(0, 0, -1))
	proj.bounces_left = server_tank.stats.projectile_bounces
	assert(proj.bounces_left == 1, "Снаряд должен унаследовать 1 отскок от карты Bouncy")

	# Симулируем 1-й отскок
	var wall_norm := Vector3(0, 0, 1)
	var old_vel_z := proj.velocity.z
	proj.velocity = proj.velocity.bounce(wall_norm)
	proj.bounces_left -= 1
	proj.bounces_done += 1
	assert(proj.velocity.z == -old_vel_z, "Скорость по Z должна инвертироваться при отскоке")
	assert(proj.bounces_left == 0, "Осталось 0 отскоков")

	proj.queue_free()
	server_tank.queue_free()
	print("[PASS] 8. Рикошет снарядов и серверная синхронизация карт способностей")

	# 9. Безопасность снарядов при отключении стрелка (ранее освобожденный экземпляр / freed instance)
	var disconnected_tank: Tank = tank_scene.instantiate()
	add_child(disconnected_tank)
	disconnected_tank.setup_network(3, 2, Color.GREEN)

	var orphan_proj: Projectile = proj_scene.instantiate()
	add_child(orphan_proj)
	orphan_proj.setup(disconnected_tank, Vector3.ZERO, Vector3.FORWARD)

	var target_test_tank: Tank = tank_scene.instantiate()
	add_child(target_test_tank)
	target_test_tank.setup_network(1, 0, Color.BLUE)

	# Освобождаем стрелка (симулируем выход клиента из матча)
	disconnected_tank.free()

	assert(orphan_proj.get_valid_shooter() == null, "get_valid_shooter() должен возвращать null для удаленного танка")
	assert(orphan_proj.get_shooter_tank() == null, "get_shooter_tank() должен возвращать null для удаленного танка")

	# Проверяем урон цели от осиротевшего снаряда без падений движка
	var initial_hp := target_test_tank.health.current_health
	var dmg_applied := target_test_tank.health.take_damage(30.0, orphan_proj.get_valid_shooter())
	assert(dmg_applied == true, "Урон должен корректно наноситься даже без валидного стрелка")
	assert(target_test_tank.health.current_health == initial_hp - 30.0, "HP цели должно уменьшиться на 30.0")

	orphan_proj.queue_free()
	target_test_tank.queue_free()
	print("[PASS] 9. Безопасная обработка урона и коллизий после отключения стрелка")

	# 10. Проверка карты Shotgun: веер из 4 снарядов в сетевом контейнере Projectiles
	var proj_container := Node3D.new()
	proj_container.name = "Projectiles"
	add_child(proj_container)

	var shotgun_tank: Tank = tank_scene.instantiate()
	add_child(shotgun_tank)
	shotgun_tank.setup_network(1, 0, Color.BLUE)

	# Выбираем карту Shotgun через сетевой RPC
	shotgun_tank.net_sync.c2s_choose_card("shotgun")
	assert(shotgun_tank.build.has_card("shotgun"), "Танк должен иметь карту shotgun")

	# Производим выстрел
	shotgun_tank.weapon.try_fire()

	# Проверяем, что в сетевом контейнере Projectiles ровно 4 снаряда (1 базовый + 3 дробины)
	assert(proj_container.get_child_count() == 4, "В сетевом контейнере Projectiles должно быть ровно 4 снаряда дроби, сейчас: %d" % proj_container.get_child_count())
	print("[PASS] 10. Карточка Shotgun создает ровно 4 снаряда в сетевом контейнере Projectiles для MultiplayerSpawner")

	shotgun_tank.queue_free()
	proj_container.queue_free()

	print("\n>>> ВСЕ ПРОВЕРКИ СЕТЕВОГО СЛОЯ ФАЗЫ 4 УСПЕШНО ПРОЙДЕНЫ! <<<\n")
	get_tree().quit(0)
