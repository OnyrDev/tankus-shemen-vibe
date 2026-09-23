class_name SoundManagerClass
extends Node

## Глобальный менеджер звуковых эффектов TANKUS (Autoload: SoundManager).
## Управляет пулом 2D и 3D аудиоплееров, направляет звуки в шину "SFX",
## обеспечивает микро-рандомизацию pitch_scale и позиционирование в 3D мире.

const POOL_SIZE_2D: int = 12
const POOL_SIZE_3D: int = 16

const SFX_PATHS: Dictionary = {
	"shoot": "res://assets/audio/sfx/sfx_shoot.wav",
	"ricochet": "res://assets/audio/sfx/sfx_ricochet.wav",
	"hit": "res://assets/audio/sfx/sfx_hit.wav",
	"block": "res://assets/audio/sfx/sfx_block.wav",
	"jump": "res://assets/audio/sfx/sfx_jump.wav",
	"land": "res://assets/audio/sfx/sfx_land.wav",
	"explosion": "res://assets/audio/sfx/sfx_explosion.wav",
	"card_hover": "res://assets/audio/sfx/sfx_card_hover.wav",
	"card_select": "res://assets/audio/sfx/sfx_card_select.wav",
	"reload_done": "res://assets/audio/sfx/sfx_reload_done.wav",
}

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []

var _index_2d: int = 0
var _index_3d: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_sfx_bus()
	_load_sound_streams()
	_create_player_pools()

func _ensure_sfx_bus() -> void:
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "SFX")
		AudioServer.set_bus_send(bus_idx, "Master")

func _load_sound_streams() -> void:
	for sfx_name in SFX_PATHS:
		var path: String = SFX_PATHS[sfx_name]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream:
				_streams[sfx_name] = stream
		else:
			push_warning("SoundManager: SFX not found at " + path)

func _create_player_pools() -> void:
	for i in range(POOL_SIZE_2D):
		var p := AudioStreamPlayer.new()
		p.name = "SFX2D_%d" % i
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players_2d.append(p)

	for i in range(POOL_SIZE_3D):
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "SFX3D_%d" % i
		p3.bus = "SFX"
		p3.max_distance = 45.0
		p3.unit_size = 8.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p3)
		_players_3d.append(p3)

## Воспроизведение 2D звука (UI, локальный щелчок, выбор карты)
func play_sfx(sfx_name_or_stream: Variant, volume_db: float = 0.0, pitch_variance: float = 0.05) -> AudioStreamPlayer:
	var stream: AudioStream = _resolve_stream(sfx_name_or_stream)
	if not stream or _players_2d.is_empty():
		return null

	var player := _players_2d[_index_2d]
	_index_2d = (_index_2d + 1) % _players_2d.size()

	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()
	return player

## Воспроизведение пространственного 3D звука (выстрел, взрыв, рикошет, прыжок)
func play_sfx_3d(sfx_name_or_stream: Variant, world_pos: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.06, max_dist: float = 45.0) -> AudioStreamPlayer3D:
	var stream: AudioStream = _resolve_stream(sfx_name_or_stream)
	if not stream or _players_3d.is_empty():
		return null

	var player := _players_3d[_index_3d]
	_index_3d = (_index_3d + 1) % _players_3d.size()

	player.global_position = world_pos
	player.max_distance = max_dist
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	player.play()
	return player

func _resolve_stream(val: Variant) -> AudioStream:
	if val is AudioStream:
		return val as AudioStream
	elif val is String:
		var s_name := val as String
		if _streams.has(s_name):
			return _streams[s_name]
		elif ResourceLoader.exists(s_name):
			return load(s_name) as AudioStream
	return null

## Установка громкости шины SFX (0.0 .. 1.0)
func set_sfx_volume_linear(linear: float) -> void:
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx == -1:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	if clamped <= 0.0001:
		AudioServer.set_bus_mute(bus_idx, true)
	else:
		AudioServer.set_bus_mute(bus_idx, false)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped))

func get_sfx_volume_linear() -> float:
	var bus_idx := AudioServer.get_bus_index("SFX")
	if bus_idx == -1:
		return 1.0
	if AudioServer.is_bus_mute(bus_idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
