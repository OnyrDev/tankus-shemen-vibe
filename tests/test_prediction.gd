extends Node3D

## Два реальных ENet-пира. Задержка добавляется на клиенте в обоих направлениях.
## Клавиатурный ввод заменяет сценарий; физика и RPC остаются игровыми.
var _tank: Tank
var _server: bool = true
var _port: int = 17110
var _failures: int = 0
var _elapsed: float = -1.0
var _first_motion_ms: float = -1.0
var _start_x: float = 0.0
var _jumped: bool = false
var _double_jumped: bool = false
var _wall_limit: float = 0.0
var _max_y: float = 0.0
var _max_x: float = -1000.0
var _finished: bool = false
var _reset_test: bool = false
var _reset_time: float = 0.0
var _jump_events: int = 0
var _settled_error: float = 0.0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--prediction-test-client":
			_server = false
		if arg.begins_with("--prediction-test-port="):
			_port = arg.get_slice("=", 1).to_int()
	_build_world()
	get_tree().create_timer(25.0).timeout.connect(func(): get_tree().quit(2))
	if _server:
		_check(Network.create_host(_port) == OK, "Host starts")
		Network.peer_connected.connect(func(id): _configure_client.rpc_id(id, id))
	else:
		_check(Network.join_host("127.0.0.1", _port) == OK, "Client starts")

func _build_world() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))
	_add_box(Vector3(4, 2, 0), Vector3(1, 4, 14))

func _add_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.position = pos

func _create_tank(owner_id: int) -> void:
	_tank = preload("res://tank/tank.tscn").instantiate() as Tank
	_tank.name = "ControlledTank"
	_tank.peer_id = owner_id
	_tank.position = Vector3(-8, 0.05, 0)
	add_child(_tank)
	_tank.setup_network(owner_id, 1, Color.BLUE)
	_tank.input.set_physics_process(false)
	_tank.input.set_process(false)
	_tank.build.add_card(CardDatabase.get_card("double_jump"))
	_wall_limit = 3.5 - (_tank.get_node("CollisionShape3D").shape as CapsuleShape3D).radius + 0.03
	_tank.events.jumped.connect(func(): _jump_events += 1)

@rpc("authority", "reliable")
func _configure_client(owner_id: int) -> void:
	_create_tank(owner_id)
	_client_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	_create_tank(multiplayer.get_remote_sender_id())

func _physics_process(delta: float) -> void:
	if _tank == null:
		return
	if _server:
		_check(_tank.position.x <= _wall_limit, "Server respects wall collision")
		return
	if _finished:
		return
	if not _tank.net_sync._prediction_ready:
		return
	if _elapsed < 0.0:
		_elapsed = 0.0
		_start_x = _tank.position.x
	_elapsed += delta
	var t := _elapsed - 0.7 # Даём обеим сторонам стабилизироваться на полу.
	_tank.input.move_direction_world = Vector3.ZERO
	if t >= 0.0 and t < 0.8:
		_tank.input.move_direction_world = Vector3.RIGHT
	elif t >= 1.3 and t < 2.0:
		_tank.input.move_direction_world = Vector3.LEFT
	elif t >= 2.0 and t < 2.5:
		_tank.input.move_direction_world = Vector3.RIGHT
		if not _jumped:
			_tank.input.jump_requested = true
			_jumped = true
		elif t >= 2.25 and not _double_jumped:
			_tank.input.jump_requested = true
			_double_jumped = true
	elif t >= 3.7 and t < 6.7:
		_tank.input.move_direction_world = Vector3.RIGHT
	if t >= 0.0:
		if _first_motion_ms < 0.0 and absf(_tank.position.x - _start_x) > 0.002:
			_first_motion_ms = t * 1000.0
		_max_y = maxf(_max_y, _tank.position.y)
		_max_x = maxf(_max_x, _tank.position.x)
	if t > 7.7 and not _reset_test:
		_check(_first_motion_ms >= 0.0, "Client moves")
		if _tank.net_sync.prediction_enabled:
			_check(_first_motion_ms < 50.0, "Prediction reacts within one physics tick")
		_check(_max_y > 2.8, "Jump and double jump work under latency")
		_check(_max_x <= _wall_limit, "Predicted body does not pass through wall")
		_check(_tank.net_sync.get_pending_input_count() < 90, "Acknowledgments drain input history")
		_check(_jump_events == 0, "Prediction and replay do not trigger gameplay jump events")
		_reset_test = true
		_reset_time = _elapsed
		_request_checkpoint.rpc_id(1)
	if _reset_test and _elapsed - _reset_time < 0.6:
		_tank.input.move_direction_world = Vector3.RIGHT
	if _reset_test and _elapsed - _reset_time > 1.5:
		_check(_tank.position.distance_to(Vector3(-12, 0, 0)) < 0.15, "Respawn discards inputs from previous life")
		_finished = true
		_request_result.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_checkpoint() -> void:
	_checkpoint.rpc_id(multiplayer.get_remote_sender_id(), _tank.position)

@rpc("authority", "reliable")
func _checkpoint(server_position: Vector3) -> void:
	_settled_error = _tank.position.distance_to(server_position)
	_check(_settled_error < 0.15, "Client converges to server after stopping")
	_reset_time = _elapsed
	_request_reset.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_reset() -> void:
	_check(_jump_events == 2, "Server executes each jump once despite redundant packets")
	_tank.respawn(Transform3D(Basis.IDENTITY, Vector3(-12, 0, 0)))
	_tank.is_frozen = true
	await get_tree().create_timer(0.8).timeout
	_check(_tank.position.distance_to(Vector3(-12, 0, 0)) < 0.15, "Frozen tank ignores movement")
	_tank.is_frozen = false

@rpc("any_peer", "reliable")
func _request_result() -> void:
	_result.rpc_id(multiplayer.get_remote_sender_id(), _tank.position, _failures)

@rpc("authority", "reliable")
func _result(server_position: Vector3, server_failures: int) -> void:
	var final_error := _tank.position.distance_to(server_position)
	_check(final_error < 0.15, "Client converges to server after stopping/reset")
	print("PREDICTION_METRICS ", JSON.stringify({
		"prediction": _tank.net_sync.prediction_enabled,
		"simulated_rtt_ms": Network.debug_movement_latency_ms * 2,
		"first_motion_ms": snappedf(_first_motion_ms, 0.1),
		"settled_error_m": snappedf(_settled_error, 0.001),
		"final_error_m": snappedf(final_error, 0.001),
		"max_x": snappedf(_max_x, 0.01),
		"max_y": snappedf(_max_y, 0.01),
		"pending_inputs": _tank.net_sync.get_pending_input_count(),
		"corrections": _tank.net_sync.reconciliation_count,
		"failures": _failures + server_failures
	}))
	_finish.rpc_id(1, _failures + server_failures)
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(1 if _failures + server_failures > 0 else 0)

@rpc("any_peer", "reliable")
func _finish(failures: int) -> void:
	get_tree().quit(1 if failures > 0 else 0)
