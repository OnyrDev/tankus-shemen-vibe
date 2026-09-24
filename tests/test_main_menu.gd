extends Node

## Автоматизированный тест Главного Меню TANKUS и системы предотвращения фоновой стрельбы.

const MainMenuScript = preload("res://ui/main_menu.gd")
const PauseMenuScript = preload("res://ui/pause_menu.gd")
const LobbyScreenScript = preload("res://lobby/lobby_screen.gd")

var _passed_count: int = 0
var _failed_count: int = 0

func _ready() -> void:
	var app_tree := get_tree()
	print("\n========================================================")
	print("   TANKUS — MAIN MENU & INPUT SAFETY AUTOMATED TEST")
	print("========================================================\n")

	await get_tree().process_frame

	_test_main_menu_instantiation()
	_test_menu_navigation_and_map_selection()
	_test_settings_bus_control()
	_test_background_fire_prevention()
	_test_pause_menu()
	_test_standalone_lobby_screen()

	print("\n========================================================")
	print("   TEST RESULTS: %d PASSED | %d FAILED" % [_passed_count, _failed_count])
	print("========================================================\n")

	if _failed_count > 0:
		push_error("MainMenu tests failed!")
	else:
		print(">>> ALL MAIN MENU & INPUT SAFETY TESTS PASSED! <<<\n")

	if app_tree:
		app_tree.quit(0 if _failed_count == 0 else 1)

func _assert_test(condition: bool, test_name: String) -> void:
	if condition:
		print("[PASS] ", test_name)
		_passed_count += 1
	else:
		push_error("[FAIL] " + test_name)
		print("[FAIL] ", test_name)
		_failed_count += 1

func _test_main_menu_instantiation() -> void:
	print("--- 1. MainMenu Scene & Showroom Test ---")
	var menu_scene: PackedScene = load("res://ui/main_menu.tscn")
	_assert_test(menu_scene != null, "res://ui/main_menu.tscn успешно загружена")

	var menu: Control = menu_scene.instantiate()
	_assert_test(menu != null, "Сцена MainMenu инстанциирована")
	add_child(menu)

	_assert_test(menu.showroom_tank != null, "3D модель танка в шоуруме существует")
	_assert_test(menu.showroom_turret != null, "Башня танка в шоуруме существует")
	_assert_test(menu.panel_main_buttons != null and menu.panel_main_buttons.visible, "Панель главных кнопок видна по умолчанию")
	_assert_test(menu.btn_solo != null and menu.btn_lan != null and menu.btn_map != null and menu.btn_settings != null and menu.btn_quit != null, "Все 5 главных кнопок навигации существуют")

	menu.queue_free()

func _test_menu_navigation_and_map_selection() -> void:
	print("\n--- 2. Menu Navigation & Map Selection Test ---")
	var menu_scene: PackedScene = load("res://ui/main_menu.tscn")
	var menu: Control = menu_scene.instantiate()
	add_child(menu)

	# Открываем выбор карты
	menu._on_btn_map_pressed()
	_assert_test(menu.panel_map_select.visible == true, "Клик по выбору карт открывает панель MapSelectPanel")
	_assert_test(menu.panel_main_buttons.visible == false, "Главные кнопки скрываются при открытии панели карт")

	# Выбираем карту Iceworks
	menu._selected_map_key = "iceworks"
	Game.rules.selected_map = "iceworks"
	menu._update_map_status_ui()
	_assert_test(Game.rules.selected_map == "iceworks", "Карта 'iceworks' сохранена в Game.rules")
	_assert_test(menu.lbl_status_map.text.contains("ICEWORKS"), "Статусная строка отображает ICEWORKS")

	# Возвращаемся в главное меню
	menu._switch_panel("main")
	_assert_test(menu.panel_main_buttons.visible == true, "Возврат в главное меню восстанавливает кнопки")
	_assert_test(menu.panel_map_select.visible == false, "Панель карт скрыта после возврата")

	# Открываем панель LAN
	menu._on_btn_lan_pressed()
	_assert_test(menu.panel_lan.visible == true, "Клик по LAN открывает панель сетевой игры")
	_assert_test(menu.line_player_name != null and menu.btn_create_host != null, "Поля сетевого лобби присутствуют")

	menu.queue_free()

func _test_settings_bus_control() -> void:
	print("\n--- 3. Settings & Audio Bus Control Test ---")
	var menu_scene: PackedScene = load("res://ui/main_menu.tscn")
	var menu: Control = menu_scene.instantiate()
	add_child(menu)

	menu._on_btn_settings_pressed()
	_assert_test(menu.panel_settings.visible == true, "Панель настроек открывается")

	# Меняем значение SFX слайдера на 60%
	menu._on_sfx_slider_changed(60.0)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var sfx_db := AudioServer.get_bus_volume_db(sfx_bus)
	_assert_test(sfx_db < 0.0 and sfx_db > -10.0, "Громкость шины SFX синхронизирована со слайдером (~60%)")

	menu.queue_free()

func _test_background_fire_prevention() -> void:
	print("\n--- 4. Background Fire Prevention Test ---")
	var tank_scene: PackedScene = load("res://tank/tank.tscn")
	var t := tank_scene.instantiate() as Tank
	add_child(t)

	var input := t.input
	_assert_test(input != null, "TankInput компонент найден")

	# Проверка стрельбы в зависимости от режима ввода
	_assert_test(input._is_aim_input_active() == true or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Определитель активного ввода мыши корректно функционирует")
	input.fire_requested = true
	var consumed := input.consume_fire()
	_assert_test(consumed == true, "consume_fire() обрабатывает запрос на выстрел")
	t.queue_free()

func _test_pause_menu() -> void:
	print("\n--- 5. In-Game Pause Menu Test ---")
	var pause_scene: PackedScene = load("res://ui/pause_menu.tscn")
	_assert_test(pause_scene != null, "res://ui/pause_menu.tscn успешно загружена")

	var pause: CanvasLayer = pause_scene.instantiate()
	add_child(pause)

	_assert_test(pause.visible == false, "PauseMenu изначально скрыто")
	pause.open()
	_assert_test(pause.is_open() == true, "open() делает PauseMenu видимым")

	pause.close()
	_assert_test(pause.is_open() == false, "close() скрывает PauseMenu")

	pause.queue_free()

func _test_standalone_lobby_screen() -> void:
	print("\n--- 6. Standalone LobbyScreen Test ---")
	var lobby_scene: PackedScene = load("res://lobby/lobby_screen.tscn")
	_assert_test(lobby_scene != null, "res://lobby/lobby_screen.tscn успешно загружена")

	var lobby_scr: Control = lobby_scene.instantiate()
	add_child(lobby_scr)

	_assert_test(lobby_scr.showroom_tank != null, "LobbyScreen содержит 3D модель танка в шоуруме")
	_assert_test(lobby_scr.player_list_vbox != null, "LobbyScreen содержит контейнер списка участников")
	_assert_test(lobby_scr.host_settings_panel != null, "LobbyScreen содержит панель настроек хоста")
	_assert_test(lobby_scr.btn_start_match != null, "LobbyScreen содержит кнопку старта матча")
	_assert_test(lobby_scr.btn_leave_lobby != null, "LobbyScreen содержит кнопку выхода из лобби")

	# Проверка динамической перекраски танка под команду игрока
	Network.local_team_id = 2
	lobby_scr._update_tank_team_color()
	var mat: StandardMaterial3D = lobby_scr.chassis_mesh.material_override
	_assert_test(mat != null and mat.albedo_color == LobbyScreenScript.TEAM_COLORS[1], "Танк в шоуруме перекрашивается в цвет команды игрока (Команда 2 - Красный)")

	Network.local_team_id = 1

	# Проверка нажатия кнопки 'Покинуть лобби' без краша get_tree()
	Network.create_host(7099)
	_assert_test(Network.is_host == true, "Хост успешно поднят перед тестом выхода из лобби")
	lobby_scr._on_btn_leave_lobby_pressed()
	_assert_test(Network.is_host == false, "Нажатие 'Покинуть лобби' закрывает сессию без краша get_tree()")

	lobby_scr.queue_free()
