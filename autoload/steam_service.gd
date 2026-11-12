class_name SteamServiceManager
extends Node

## Опциональный синглтон для интеграции со Steamworks через GodotSteam GDExtension.
## Обращается к Steam только через Engine.get_singleton("Steam"), чтобы проект
## собирался и проходил headless-тесты даже без установленного аддона или запущенного клиента Steam.

signal steam_initialized(steam_id: int, persona_name: String)
signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int, owner_steam_id: int)
signal lobby_list_received(lobbies: Array)
signal lobby_invite_accepted(lobby_id: int)
signal steam_error(message: String)

const APP_ID: int = 480 # Spacewar на время разработки; заменить на свой App ID перед релизом
const GAME_TAG: String = "tankus"
const GAME_VERSION: String = "0.7.0"

const LOBBY_TYPE_PRIVATE: int = 0
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_DISTANCE_WORLDWIDE: int = 3
const LOBBY_COMPARISON_EQUAL: int = 0
const CHAT_ROOM_ENTER_SUCCESS: int = 1

var is_initialized: bool = false
var steam_id: int = 0
var persona_name: String = ""
var current_lobby_id: int = 0
var pending_lobby_name: String = "TANKUS Room"
var pending_connect_lobby_id: int = 0

var _steam: Object = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_warn_if_steam_godot_dll_mismatch()
	_parse_command_line_lobby()
	_try_init_steam()


func _warn_if_steam_godot_dll_mismatch() -> void:
	if Engine.has_singleton("Steam") or OS.get_name() != "Windows":
		return
	var exe_dir := OS.get_executable_path().get_base_dir()
	var editor_dll := exe_dir.path_join("steam_api64.dll")
	var addon_dll := ProjectSettings.globalize_path("res://addons/godotsteam/win64/steam_api64.dll")
	if FileAccess.file_exists(editor_dll) and FileAccess.file_exists(addon_dll):
		var ed_size := FileAccess.get_file_as_bytes(editor_dll).size()
		var ad_size := FileAccess.get_file_as_bytes(addon_dll).size()
		if ed_size != ad_size:
			push_warning("SteamService: Устаревший steam_api64.dll в папке Steam-версии Godot (%s, %d байт vs %d байт в GodotSteam). Замените его файлом из addons/godotsteam/win64/steam_api64.dll и перезапустите редактор." % [editor_dll, ed_size, ad_size])


func _process(_delta: float) -> void:
	if is_initialized and _steam != null:
		_steam.call("run_callbacks")


func is_available() -> bool:
	return is_initialized and _steam != null


func get_steam() -> Object:
	return _steam


func _parse_command_line_lobby() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	for i in range(all_args.size()):
		if all_args[i] == "+connect_lobby" and i + 1 < all_args.size():
			var parsed := all_args[i + 1].to_int()
			if parsed > 0:
				pending_connect_lobby_id = parsed
				break


func _try_init_steam() -> void:
	if "--no-steam" in OS.get_cmdline_args() or "--no-steam" in OS.get_cmdline_user_args():
		return
	if DisplayServer.get_name() == "headless" and "--enable-steam-headless" not in OS.get_cmdline_user_args():
		return
	if not Engine.has_singleton("Steam"):
		return

	_steam = Engine.get_singleton("Steam")
	if _steam == null or not _steam.has_method("steamInitEx"):
		_steam = null
		return

	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))

	var res: Dictionary = _steam.call("steamInitEx", APP_ID, false)
	var status: int = int(res.get("status", -1))
	if status != 0:
		print("SteamService: Steam не инициализирован (status=%d: %s). Доступен режим LAN." % [
			status, str(res.get("verbal", "нет ответа от клиента Steam"))
		])
		_steam = null
		return

	is_initialized = true
	steam_id = int(_steam.call("getSteamID"))
	persona_name = str(_steam.call("getPersonaName")).strip_edges()
	if _steam.has_method("initRelayNetworkAccess"):
		_steam.call("initRelayNetworkAccess")
	if _steam.has_method("allowP2PPacketRelay"):
		_steam.call("allowP2PPacketRelay", true)

	_connect_steam_signals()
	print("SteamService: Инициализирован как '%s' (SteamID: %d, AppID: %d)" % [persona_name, steam_id, APP_ID])
	steam_initialized.emit(steam_id, persona_name)

	if pending_connect_lobby_id > 0:
		var target := pending_connect_lobby_id
		pending_connect_lobby_id = 0
		call_deferred("join_lobby", target)


func _connect_steam_signals() -> void:
	_safe_connect("lobby_created", _on_steam_lobby_created)
	_safe_connect("lobby_joined", _on_steam_lobby_joined)
	_safe_connect("lobby_match_list", _on_steam_lobby_match_list)
	_safe_connect("join_requested", _on_steam_join_requested)


func _safe_connect(sig_name: String, callable: Callable) -> void:
	if _steam != null and _steam.has_signal(sig_name) and not _steam.is_connected(sig_name, callable):
		_steam.connect(sig_name, callable)


func create_lobby(lobby_name: String = "TANKUS Room", lobby_type: int = LOBBY_TYPE_PUBLIC, max_members: int = 8) -> Error:
	if not is_available():
		steam_error.emit("Клиент Steam не запущен или не инициализирован.")
		return ERR_UNAVAILABLE
	leave_lobby()
	pending_lobby_name = lobby_name.strip_edges()
	if pending_lobby_name.is_empty():
		pending_lobby_name = "%s's Room" % (persona_name if not persona_name.is_empty() else "TANKUS")
	_steam.call("createLobby", lobby_type, clampi(max_members, 2, 8))
	return OK


func join_lobby(lobby_id: int) -> Error:
	if not is_available():
		steam_error.emit("Клиент Steam не запущен или не инициализирован.")
		return ERR_UNAVAILABLE
	if lobby_id <= 0:
		steam_error.emit("Некорректный ID лобби Steam.")
		return ERR_INVALID_PARAMETER
	if current_lobby_id != 0 and current_lobby_id != lobby_id:
		leave_lobby()
	_steam.call("joinLobby", lobby_id)
	return OK


func leave_lobby() -> void:
	if current_lobby_id != 0 and is_available():
		_steam.call("leaveLobby", current_lobby_id)
	current_lobby_id = 0


func request_lobby_list() -> Error:
	if not is_available():
		steam_error.emit("Клиент Steam не запущен или не инициализирован.")
		return ERR_UNAVAILABLE
	_steam.call("addRequestLobbyListDistanceFilter", LOBBY_DISTANCE_WORLDWIDE)
	_steam.call("addRequestLobbyListStringFilter", "game", GAME_TAG, LOBBY_COMPARISON_EQUAL)
	_steam.call("addRequestLobbyListStringFilter", "game_version", GAME_VERSION, LOBBY_COMPARISON_EQUAL)
	_steam.call("addRequestLobbyListResultCountFilter", 50)
	_steam.call("requestLobbyList")
	return OK


func update_current_lobby_metadata() -> void:
	if not is_available() or current_lobby_id == 0:
		return
	var owner_id := int(_steam.call("getLobbyOwner", current_lobby_id))
	if owner_id != steam_id:
		return
	_steam.call("setLobbyData", current_lobby_id, "game", GAME_TAG)
	_steam.call("setLobbyData", current_lobby_id, "game_version", GAME_VERSION)
	_steam.call("setLobbyData", current_lobby_id, "name", pending_lobby_name)
	_steam.call("setLobbyData", current_lobby_id, "host_name", persona_name)
	_steam.call("setLobbyData", current_lobby_id, "mode", "Teams" if Game.rules.is_team_mode else "FFA")
	_steam.call("setLobbyData", current_lobby_id, "map", Game.rules.selected_map)
	_steam.call("setLobbyData", current_lobby_id, "bots", str(Game.rules.bot_count))
	_steam.call("setLobbyJoinable", current_lobby_id, not Game.is_in_match)


func is_overlay_enabled() -> bool:
	if not is_available() or not _steam.has_method("isOverlayEnabled"):
		return false
	return bool(_steam.call("isOverlayEnabled"))


func open_invite_overlay() -> bool:
	if not is_available() or current_lobby_id == 0:
		return false
	if not is_overlay_enabled():
		return false
	_steam.call("activateGameOverlayInviteDialog", current_lobby_id)
	return true


func get_online_friends() -> Array:
	var result: Array = []
	if not is_available() or not _steam.has_method("getUserSteamFriends"):
		return result
	var raw_friends: Array = _steam.call("getUserSteamFriends")
	for f in raw_friends:
		if not (f is Dictionary):
			continue
		var fid := int(f.get("id", 0))
		var status := int(f.get("status", 0))
		var fname := str(f.get("name", "")).strip_edges()
		if fid <= 0 or fname.is_empty():
			continue
		result.append({
			"steam_id": fid,
			"name": fname,
			"status": status,
			"is_online": status > 0
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["is_online"]) != bool(b["is_online"]):
			return bool(a["is_online"])
		return str(a["name"]).nocasecmp_to(str(b["name"])) < 0
	)
	return result


func invite_friend_to_current_lobby(friend_steam_id: int) -> bool:
	if not is_available() or current_lobby_id == 0 or friend_steam_id <= 0:
		return false
	return bool(_steam.call("inviteUserToLobby", current_lobby_id, friend_steam_id))


func get_lobby_owner(lobby_id: int = 0) -> int:
	var target := lobby_id if lobby_id > 0 else current_lobby_id
	if not is_available() or target <= 0:
		return 0
	return int(_steam.call("getLobbyOwner", target))


func get_friend_name(target_steam_id: int) -> String:
	if not is_available() or target_steam_id <= 0:
		return ""
	if target_steam_id == steam_id:
		return persona_name
	return str(_steam.call("getFriendPersonaName", target_steam_id)).strip_edges()


func parse_lobby_list(raw_lobbies: Array) -> Array:
	var result: Array = []
	if not is_available():
		return result
	for raw_id in raw_lobbies:
		var lid := int(raw_id)
		if lid <= 0:
			continue
		var tag := str(_steam.call("getLobbyData", lid, "game"))
		var ver := str(_steam.call("getLobbyData", lid, "game_version"))
		if tag != GAME_TAG or ver != GAME_VERSION:
			continue
		var lname := str(_steam.call("getLobbyData", lid, "name")).strip_edges()
		var hname := str(_steam.call("getLobbyData", lid, "host_name")).strip_edges()
		if lname.is_empty():
			lname = "%s's Room" % (hname if not hname.is_empty() else "TANKUS")
		var members := int(_steam.call("getNumLobbyMembers", lid))
		var max_members := int(_steam.call("getLobbyMemberLimit", lid))
		if max_members <= 0:
			max_members = 8
		var bots := int(str(_steam.call("getLobbyData", lid, "bots")).to_int())
		var mode := str(_steam.call("getLobbyData", lid, "mode"))
		result.append({
			"lobby_id": lid,
			"name": lname,
			"host_name": hname,
			"members": members,
			"max_members": max_members,
			"bots": bots,
			"mode": mode if not mode.is_empty() else "FFA"
		})
	return result


# --- Обработчики сигналов GodotSteam ---

func _on_steam_lobby_created(connect_result: int, lobby_id: int) -> void:
	if connect_result != 1 or lobby_id <= 0:
		var msg := "Не удалось создать лобби Steam (код %d)." % connect_result
		push_warning("SteamService: " + msg)
		steam_error.emit(msg)
		return

	current_lobby_id = lobby_id
	update_current_lobby_metadata()
	var err := Network.create_host_steam(lobby_id)
	if err != OK:
		leave_lobby()
		steam_error.emit("Ошибка запуска SteamMultiplayerPeer: %s" % error_string(err))
		return

	lobby_created.emit(lobby_id)


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != CHAT_ROOM_ENTER_SUCCESS or lobby_id <= 0:
		var msg := "Не удалось войти в лобби Steam (код ответа %d)." % response
		push_warning("SteamService: " + msg)
		steam_error.emit(msg)
		return

	current_lobby_id = lobby_id
	var owner_id := get_lobby_owner(lobby_id)
	if owner_id == steam_id:
		# Владелец лобби уже поднял хост в _on_steam_lobby_created
		return

	var ver := str(_steam.call("getLobbyData", lobby_id, "game_version"))
	if not ver.is_empty() and ver != GAME_VERSION:
		leave_lobby()
		steam_error.emit("Версия комнаты (%s) не совпадает с вашей (%s)." % [ver, GAME_VERSION])
		return

	var err := Network.join_host_steam(lobby_id)
	if err != OK:
		leave_lobby()
		steam_error.emit("Не удалось подключиться к хосту Steam: %s" % error_string(err))
		return

	lobby_joined.emit(lobby_id, owner_id)


func _on_steam_lobby_match_list(lobbies: Array) -> void:
	lobby_list_received.emit(parse_lobby_list(lobbies))


func _on_steam_join_requested(lobby_id: int, _friend_steam_id: int) -> void:
	if lobby_id <= 0:
		return
	lobby_invite_accepted.emit(lobby_id)
	if Game.is_in_match:
		Game.return_to_main_menu()
	join_lobby(lobby_id)

