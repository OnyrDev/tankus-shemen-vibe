class_name SettingsManagerClass
extends Node

## Глобальный менеджер настроек TANKUS (Autoload: SettingsManager).
## Обеспечивает персистентность конфигурации (аудио, дисплей, сеть, геймплей)
## через ConfigFile в "user://settings.cfg".
## Автоматически загружает настройки при запуске и сохраняет при изменениях и выходе из игры.

signal settings_changed()
signal setting_changed(section: String, key: String, value: Variant)

const SETTINGS_PATH: String = "user://settings.cfg"

# Дефолтные настройки
const DEFAULT_SFX_VOLUME: float = 0.8
const DEFAULT_UI_VOLUME: float = 0.8
const DEFAULT_MUSIC_VOLUME: float = 0.5
const DEFAULT_FULLSCREEN: bool = false
const DEFAULT_PLAYER_NAME: String = "Player"
const DEFAULT_SELECTED_MAP: String = "sky_courtyard"

var _config: ConfigFile = ConfigFile.new()

# Кэшированные значения в памяти для быстрого доступа
var sfx_volume: float = DEFAULT_SFX_VOLUME
var ui_volume: float = DEFAULT_UI_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var fullscreen: bool = DEFAULT_FULLSCREEN
var player_name: String = DEFAULT_PLAYER_NAME
var selected_map: String = DEFAULT_SELECTED_MAP

var _is_loaded: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()

## Загрузка настроек с диска (user://settings.cfg)
func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		# Файл еще не существует или поврежден — формируем дефолты
		_set_default_values()
		save_settings()
	else:
		sfx_volume = clampf(float(_config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
		ui_volume = clampf(float(_config.get_value("audio", "ui_volume", DEFAULT_UI_VOLUME)), 0.0, 1.0)
		music_volume = clampf(float(_config.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME)), 0.0, 1.0)
		fullscreen = bool(_config.get_value("display", "fullscreen", DEFAULT_FULLSCREEN))
		player_name = str(_config.get_value("network", "player_name", DEFAULT_PLAYER_NAME)).strip_edges()
		if player_name.is_empty():
			player_name = DEFAULT_PLAYER_NAME
		selected_map = str(_config.get_value("gameplay", "selected_map", DEFAULT_SELECTED_MAP))
		if selected_map.is_empty():
			selected_map = DEFAULT_SELECTED_MAP

	_is_loaded = true
	settings_changed.emit()

## Сохранение текущих настроек на диск
func save_settings() -> void:
	_config.set_value("audio", "sfx_volume", sfx_volume)
	_config.set_value("audio", "ui_volume", ui_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("network", "player_name", player_name)
	_config.set_value("gameplay", "selected_map", selected_map)

	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: не удалось сохранить настройки в %s (код ошибки: %d)" % [SETTINGS_PATH, err])

## Применение текущих настроек ко всем системам игры
func apply_settings() -> void:
	# 1. Применение громкостей
	if SoundManager:
		SoundManager.set_sfx_volume_linear(sfx_volume)
		SoundManager.set_ui_volume_linear(ui_volume)
	else:
		_apply_fallback_bus_volume("SFX", sfx_volume)
		_apply_fallback_bus_volume("UI", ui_volume)

	if MusicManager:
		MusicManager.set_music_volume_linear(music_volume)
	else:
		_apply_fallback_bus_volume("Music", music_volume)

	# 2. Применение дисплея (пропускаем в headless тестах)
	if DisplayServer.get_name() != "headless":
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)

	# 3. Применение имени игрока
	if Network:
		Network.local_player_name = player_name

	# 4. Применение выбранной карты
	if Game and Game.rules:
		Game.rules.selected_map = selected_map

func _apply_fallback_bus_volume(bus_name: String, linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		var clamped := clampf(linear, 0.0, 1.0)
		if clamped <= 0.0001:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped))

func _set_default_values() -> void:
	sfx_volume = DEFAULT_SFX_VOLUME
	ui_volume = DEFAULT_UI_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	fullscreen = DEFAULT_FULLSCREEN
	player_name = DEFAULT_PLAYER_NAME
	selected_map = DEFAULT_SELECTED_MAP

# --- Типизированные геттеры и сеттеры с авто-сохранением ---

func set_sfx_volume(val: float, auto_save: bool = true) -> void:
	var clamped := clampf(val, 0.0, 1.0)
	if is_equal_approx(sfx_volume, clamped):
		return
	sfx_volume = clamped
	if SoundManager:
		SoundManager.set_sfx_volume_linear(sfx_volume)
	else:
		_apply_fallback_bus_volume("SFX", sfx_volume)
	setting_changed.emit("audio", "sfx_volume", sfx_volume)
	if auto_save:
		save_settings()

func get_sfx_volume() -> float:
	return sfx_volume

func set_ui_volume(val: float, auto_save: bool = true) -> void:
	var clamped := clampf(val, 0.0, 1.0)
	if is_equal_approx(ui_volume, clamped):
		return
	ui_volume = clamped
	if SoundManager:
		SoundManager.set_ui_volume_linear(ui_volume)
	else:
		_apply_fallback_bus_volume("UI", ui_volume)
	setting_changed.emit("audio", "ui_volume", ui_volume)
	if auto_save:
		save_settings()

func get_ui_volume() -> float:
	return ui_volume

func set_music_volume(val: float, auto_save: bool = true) -> void:
	var clamped := clampf(val, 0.0, 1.0)
	if is_equal_approx(music_volume, clamped):
		return
	music_volume = clamped
	if MusicManager:
		MusicManager.set_music_volume_linear(music_volume)
	else:
		_apply_fallback_bus_volume("Music", music_volume)
	setting_changed.emit("audio", "music_volume", music_volume)
	if auto_save:
		save_settings()

func get_music_volume() -> float:
	return music_volume

func set_fullscreen(val: bool, auto_save: bool = true) -> void:
	if fullscreen == val:
		return
	fullscreen = val
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	setting_changed.emit("display", "fullscreen", fullscreen)
	if auto_save:
		save_settings()

func is_fullscreen() -> bool:
	return fullscreen

func set_player_name(val: String, auto_save: bool = true) -> void:
	var cleaned := val.strip_edges()
	if cleaned.is_empty():
		cleaned = DEFAULT_PLAYER_NAME
	if player_name == cleaned:
		return
	player_name = cleaned
	if Network:
		Network.local_player_name = player_name
	setting_changed.emit("network", "player_name", player_name)
	if auto_save:
		save_settings()

func get_player_name() -> String:
	return player_name

func set_selected_map(val: String, auto_save: bool = true) -> void:
	if val.is_empty() or selected_map == val:
		return
	selected_map = val
	if Game and Game.rules:
		Game.rules.selected_map = selected_map
	setting_changed.emit("gameplay", "selected_map", selected_map)
	if auto_save:
		save_settings()

func get_selected_map() -> String:
	return selected_map

## Универсальный доступ для произвольных параметров
func get_setting(section: String, key: String, default_val: Variant = null) -> Variant:
	return _config.get_value(section, key, default_val)

func set_setting(section: String, key: String, val: Variant, auto_save: bool = true) -> void:
	_config.set_value(section, key, val)
	setting_changed.emit(section, key, val)
	if auto_save:
		save_settings()
