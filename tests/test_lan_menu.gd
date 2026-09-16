extends Node

func _ready() -> void:
	print("--- TEST LAN MENU STARTUP ---")
	var sandbox_scene: PackedScene = preload("res://maps/test_sandbox.tscn")
	var sandbox = sandbox_scene.instantiate()
	add_child(sandbox)

	var lan_menu: LANMenu = sandbox.get_node("LANMenu")
	print("LANMenu exists: ", lan_menu != null)
	assert(lan_menu.visible == true, "LANMenu должно быть видимым при старте")
	assert(lan_menu.panel_main.visible == true, "Главное меню сетевой игры должно быть видимым при старте")
	assert(lan_menu.panel_lobby.visible == false, "Панель лобби должна быть скрыта при старте")
	assert(Network.is_multiplayer_active() == false, "Сетевая игра не должна считаться активной при старте")
	print("[PASS] Проверка 1: При старте игры открывается меню TANKUS — СЕТЕВАЯ ИГРА (LAN)")

	# Симулируем нажатие "Создать LAN сервер" на свободном тестовом порту
	lan_menu.line_direct_port.text = "7088"
	lan_menu._on_create_host_pressed()
	print("Network.is_host: ", Network.is_host)
	print("Network.is_multiplayer_active(): ", Network.is_multiplayer_active())
	print("Network players count: ", Network.players.size())
	print("player_list_container child count: ", lan_menu.player_list_container.get_child_count())
	assert(Network.is_host == true, "Network.is_host должен быть true")
	assert(Network.is_multiplayer_active() == true, "Network.is_multiplayer_active() должен быть true")
	assert(lan_menu.panel_main.visible == false, "Главное меню должно скрыться после создания сервера")
	assert(lan_menu.panel_lobby.visible == true, "Панель лобби должна стать видимой")
	assert(lan_menu.btn_start_game.visible == true, "Кнопка старта игры должна быть видна хосту")
	assert(lan_menu.player_list_container.get_child_count() == 1, "В лобби должен отображаться ровно 1 игрок (хост)")
	print("[PASS] Проверка 2: Создание сервера переключает экран на лобби с хостом в списке")

	# Симулируем выход из лобби обратно в меню
	lan_menu._on_disconnect_pressed()
	assert(Network.is_host == false, "Network.is_host должен сброситься")
	assert(Network.is_multiplayer_active() == false, "Мультиплеер должен быть деактивирован")
	assert(lan_menu.panel_main.visible == true, "После выхода из лобби снова должно быть видно главное меню")
	assert(lan_menu.panel_lobby.visible == false, "Панель лобби должна скрыться")
	print("[PASS] Проверка 3: Выход из лобби возвращает в главное меню сетевой игры")

	print("\n>>> ТЕСТЫ LAN МЕНЮ УСПЕШНО ПРОЙДЕНЫ! <<<\n")
	get_tree().quit(0)
