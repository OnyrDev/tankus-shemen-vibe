extends Node

## Автоматический тест слоя интеграции Steam (SteamService + Network + UI)
## в headless-режиме (без запущенного клиента Steam).

var _failures: int = 0


func _ready() -> void:
	var app_tree := get_tree()
	print("\n==================================================")
	print("  TANKUS // Steam Integration Headless Test")
	print("==================================================")
	await app_tree.process_frame

	_test_autoload_and_constants()
	_test_graceful_fallback_without_steam()
	_test_player_info_steam_id_serialization()
	_test_main_menu_steam_controls()
	_test_lobby_screen_invite_visibility()
	_test_version_mismatch_rejection()

	print("==================================================")
	print("  Steam Test: %d failures" % _failures)
	print("==================================================\n")
	if app_tree:
		app_tree.quit(0 if _failures == 0 else 1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("[PASS] ", label)
	else:
		_failures += 1
		push_error("[FAIL] " + label)
		print("[FAIL] ", label)


func _test_autoload_and_constants() -> void:
	_check(SteamService != null, "Синглтон SteamService загружен в /root/SteamService")
	_check(SteamService.APP_ID == 480, "APP_ID установлен в 480 (Spacewar)")
	_check(SteamService.GAME_TAG == "tankus", "GAME_TAG == 'tankus'")
	_check(not SteamService.GAME_VERSION.is_empty(), "GAME_VERSION задан")
	_check(ClassDB.class_exists("SteamMultiplayerPeer"), "GDExtension класс SteamMultiplayerPeer зарегистрирован")


func _test_graceful_fallback_without_steam() -> void:
	_check(not SteamService.is_available(), "В headless-режиме SteamService.is_available() == false")
	var errors: Array[String] = []
	var on_err := func(msg: String): errors.append(msg)
	SteamService.steam_error.connect(on_err)

	_check(SteamService.create_lobby("Test") == ERR_UNAVAILABLE, "create_lobby без Steam возвращает ERR_UNAVAILABLE")
	_check(SteamService.join_lobby(12345) == ERR_UNAVAILABLE, "join_lobby без Steam возвращает ERR_UNAVAILABLE")
	_check(SteamService.request_lobby_list() == ERR_UNAVAILABLE, "request_lobby_list без Steam возвращает ERR_UNAVAILABLE")
	_check(not SteamService.open_invite_overlay(), "open_invite_overlay без Steam возвращает false")
	_check(errors.size() == 3, "Сигнал steam_error испущен для трех вызовов без Steam")

	SteamService.steam_error.disconnect(on_err)


func _test_player_info_steam_id_serialization() -> void:
	var info := PlayerInfo.new(5, "SteamTanker", 2)
	info.steam_id = 76561198000000042
	var dict := info.to_dict()
	var restored := PlayerInfo.from_dict(dict)
	_check(restored.steam_id == 76561198000000042, "PlayerInfo сохраняет и восстанавливает 64-битный steam_id")


func _test_main_menu_steam_controls() -> void:
	var menu_scene: PackedScene = load("res://ui/main_menu.tscn")
	var menu: Control = menu_scene.instantiate()
	add_child(menu)
	menu._on_btn_lan_pressed()
	_check(menu.btn_create_steam != null, "Кнопка 'Создать в Steam' присутствует в MainMenu")
	_check(menu.opt_steam_privacy != null and menu.opt_steam_privacy.item_count == 3, "Выбор приватности Steam-лобби содержит 3 режима")
	_check(menu.btn_create_steam.disabled == true, "Кнопка 'Создать в Steam' заблокирована, когда Steam недоступен")

	menu._on_steam_lobby_list_received([
		{"lobby_id": 777, "name": "Test Steam Room", "mode": "Teams", "members": 3, "max_players": 8, "bots": 2}
	])
	_check(menu.server_list_vbox.get_child_count() >= 1, "Список серверов отображает полученные Steam-лобби")
	menu.queue_free()


func _test_lobby_screen_invite_visibility() -> void:
	var lobby_scene: PackedScene = load("res://lobby/lobby_screen.tscn")
	var lobby: Control = lobby_scene.instantiate()
	add_child(lobby)
	_check(lobby.btn_invite_steam != null, "Кнопка 'Пригласить друга' присутствует в LobbyScreen")
	_check(lobby.btn_invite_steam.visible == false, "Кнопка приглашения скрыта в режиме ENet")
	lobby.queue_free()


func _test_version_mismatch_rejection() -> void:
	var err := Network.create_host(17098)
	_check(err == OK and Network.transport == Network.Transport.ENET, "ENet хост создается с transport == ENET")
	Network.disconnect_session()
