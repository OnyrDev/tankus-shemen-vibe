class_name DebugOverlayClass
extends CanvasLayer

## Оверлей отладки (Debug Overlay), вызываемый по клавише F3.
## Отображает FPS, время кадра, сетевую статистику, состояние FSM матча
## и параметры локального танка (позиция, скорость, HP, карты).

@onready var panel: PanelContainer = $PanelContainer
@onready var stats_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsLabel

var _update_timer: float = 0.0

func _ready() -> void:
	visible = false
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible
			if visible:
				_update_debug_text()

func _process(delta: float) -> void:
	if not visible:
		return

	_update_timer += delta
	if _update_timer >= 0.1: # Обновление 10 раз в секунду для читаемости
		_update_timer = 0.0
		_update_debug_text()

func _update_debug_text() -> void:
	if not stats_label:
		return

	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(1.0, float(fps))
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)

	# Сетевой статус
	var net_mode := "STANDALONE"
	var peer_id := 1
	var ping := 0
	var peer_count := 1

	if Network:
		peer_id = Network.get_unique_id()
		if Network.is_multiplayer_active():
			net_mode = "HOST" if Network.is_server() else "CLIENT"
			ping = Network.get_ping_ms()
			peer_count = Network.players.size()
		else:
			net_mode = "STANDALONE"

	# Состояние матча
	var match_state := Game.match_state if Game else "UNKNOWN"
	var round_num := Game.current_round if Game else 0
	var map_name := Game.rules.selected_map if Game and Game.rules else "None"

	# Локальный танк
	var tank_info := "Tank: Not Spawned"
	var local_tank := _find_local_tank()
	if local_tank and is_instance_valid(local_tank):
		var pos := local_tank.global_position
		var vel := local_tank.velocity.length()
		var hp := local_tank.health.current_health if local_tank.health else 0.0
		var max_hp := local_tank.health.max_health if local_tank.health else 0.0
		var ammo := local_tank.weapon.current_ammo if local_tank.weapon else 0
		var max_ammo := local_tank.weapon.magazine_size if local_tank.weapon else 0

		var cards_str := "None"
		if local_tank.build and not local_tank.build.cards.is_empty():
			var card_names: Array[String] = []
			for c in local_tank.build.cards:
				var count: int = local_tank.build.cards[c]
				card_names.append("%s x%d" % [c, count])
			cards_str = ", ".join(card_names)

		tank_info = "Pos: (%.1f, %.1f, %.1f) | Vel: %.1f m/s\nHP: %.0f/%.0f | Ammo: %d/%d\nCards: %s" % [
			pos.x, pos.y, pos.z, vel, hp, max_hp, ammo, max_ammo, cards_str
		]

	var text := """[ PERFORMANCE ]
FPS: %d (%.2f ms)
Draw Calls: %d | Mem: %.1f MB

[ NETWORK ]
Mode: %s | Peer ID: %d
Ping: %d ms | Peers: %d

[ MATCH ]
State: %s | Round: %d
Map: %s

[ LOCAL PLAYER ]
%s""" % [
		fps, frame_ms, draw_calls, mem_mb,
		net_mode, peer_id, ping, peer_count,
		match_state, round_num, map_name,
		tank_info
	]

	stats_label.text = text

func _find_local_tank() -> Tank:
	var tree := get_tree()
	if not tree:
		return null

	var my_id: int = Network.get_unique_id() if Network else 1
	var tanks := tree.get_nodes_in_group("tanks")
	for node in tanks:
		if node is Tank:
			if node.net_sync and node.net_sync.is_local_owner():
				return node as Tank
			elif node.peer_id == my_id:
				return node as Tank

	if not tanks.is_empty() and tanks[0] is Tank:
		return tanks[0] as Tank

	return null
