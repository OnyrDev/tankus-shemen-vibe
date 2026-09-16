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

	print("\n>>> ВСЕ ПРОВЕРКИ СЕТЕВОГО СЛОЯ ФАЗЫ 4 УСПЕШНО ПРОЙДЕНЫ! <<<\n")
	get_tree().quit(0)
