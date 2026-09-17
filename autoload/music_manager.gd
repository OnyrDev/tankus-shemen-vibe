class_name MusicManagerClass
extends Node

## Глобальный менеджер музыки TANKUS (Autoload: MusicManager).
## Управляет фоновой музыкой, плавными переходами (Crossfade),
## затуханием (Fade-in / Fade-out) и маршрутизацией в аудиошину "Music".

signal music_started(stream: AudioStream)
signal music_stopped()

@export var default_fade_duration: float = 1.2
@export var autoplay_menu: bool = true
@export var menu_music_path: String = "res://assets/audio/music/menu_theme.ogg"

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _current_tween: Tween = null

var _menu_theme: AudioStream = null
var _target_volume_db: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ensure_music_bus()
	_setup_players()
	_load_menu_theme()

	# Подключаемся к глобальным состояниям игры
	if Game:
		Game.match_state_changed.connect(_on_match_state_changed)

	if autoplay_menu and _menu_theme:
		play_menu_music(default_fade_duration)


func _ensure_music_bus() -> void:
	var bus_idx := AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Music")
		AudioServer.set_bus_send(bus_idx, "Master")


func _setup_players() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.name = "MusicPlayerA"
	_player_a.bus = "Music"
	_player_a.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.name = "MusicPlayerB"
	_player_b.bus = "Music"
	_player_b.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_b)

	_active_player = _player_a


func _load_menu_theme() -> void:
	if ResourceLoader.exists(menu_music_path):
		_menu_theme = load(menu_music_path)
		if _menu_theme is AudioStreamOggVorbis:
			(_menu_theme as AudioStreamOggVorbis).loop = true


## Воспроизведение трека с плавным переходом (crossfade)
func play_music(stream: AudioStream, fade_duration: float = -1.0, from_position: float = 0.0) -> void:
	if stream == null:
		stop_music(fade_duration)
		return

	var duration := default_fade_duration if fade_duration < 0.0 else fade_duration

	# Если уже играет этот же трек
	if _active_player.stream == stream and _active_player.playing:
		if _current_tween and _current_tween.is_valid():
			_current_tween.kill()
		_current_tween = create_tween()
		_current_tween.tween_property(_active_player, "volume_db", _target_volume_db, duration)
		return

	var next_player := _player_b if _active_player == _player_a else _player_a

	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# Готовим новый плеер
	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play(from_position)

	# Кроссфейд
	_current_tween = create_tween().set_parallel(true)
	if _active_player.playing:
		_current_tween.tween_property(_active_player, "volume_db", -80.0, duration)
	_current_tween.tween_property(next_player, "volume_db", _target_volume_db, duration)

	var old_player := _active_player
	_current_tween.chain().tween_callback(func():
		if old_player != next_player:
			old_player.stop()
	)

	_active_player = next_player
	music_started.emit(stream)


## Запуск музыки главного меню
func play_menu_music(fade_duration: float = -1.0) -> void:
	if _menu_theme == null:
		_load_menu_theme()
	if _menu_theme:
		play_music(_menu_theme, fade_duration)


## Остановка воспроизведения с плавным затуханием (fade out)
func stop_music(fade_duration: float = -1.0) -> void:
	var duration := default_fade_duration if fade_duration < 0.0 else fade_duration

	if not _active_player.playing:
		return

	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	_current_tween = create_tween()
	_current_tween.tween_property(_active_player, "volume_db", -80.0, duration)
	_current_tween.tween_callback(func():
		_active_player.stop()
		music_stopped.emit()
	)


func is_playing() -> bool:
	return _active_player != null and _active_player.playing and _active_player.volume_db > -70.0


func get_current_stream() -> AudioStream:
	return _active_player.stream if _active_player else null


## Установка громкости шины "Music" через линейный диапазон 0.0 .. 1.0 (для слайдеров в UI)
func set_music_volume_linear(linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		return

	var clamped := clampf(linear, 0.0, 1.0)
	if clamped <= 0.0001:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped))


func get_music_volume_linear() -> float:
	var bus_idx := AudioServer.get_bus_index("Music")
	if bus_idx == -1:
		return 1.0
	if AudioServer.is_bus_mute(bus_idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus_idx))


## Реакция на смену состояний матча
func _on_match_state_changed(new_state: String) -> void:
	match new_state:
		"COUNTDOWN", "PLAYING":
			# В бою глушим тему меню
			if _active_player.stream == _menu_theme and _active_player.playing:
				stop_music(1.5)
		"LOBBY", "IDLE":
			# В лобби или меню возвращаем тему меню
			play_menu_music(1.5)
