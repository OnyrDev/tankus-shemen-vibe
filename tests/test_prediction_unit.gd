extends Node3D

var _failures: int = 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	add_child(floor_body)
	floor_body.position.y = -0.5
	var tank := preload("res://tank/tank.tscn").instantiate() as Tank
	add_child(tank)
	tank.input.enabled = false
	var sync := tank.net_sync
	sync.set_physics_process(false)
	sync.set_process(false)
	for i in range(12):
		await get_tree().physics_frame
		tank.controller.process_movement(Vector3.ZERO, false, 1.0 / 60.0, false, true)

	# Протокол принимает только конечные горизонтальные направления и корректные типы.
	var command := sync._decode_input_command([1, 0, Vector3(30, 50, 0), Vector3.ZERO, 3])
	_check(command.move == Vector3.RIGHT, "Server clamps direction and removes vertical movement")
	_check(command.jump and command.aim_valid, "Compact packet preserves action flags")
	for malformed in [null, [], {}, [1, 0, Vector3.INF, Vector3.ZERO, 0],
		[1, 0, Vector3.ZERO, Vector3.ZERO, 128], [-1, 0, Vector3.ZERO, Vector3.ZERO, 0],
		[1, 0, "invalid", Vector3.ZERO, 0]]:
		_check(sync._decode_input_command(malformed).is_empty(), "Malformed input rejected")

	# Восстановление прыжка/поверхности должно быть полноценным.
	tank.controller._can_double_jump = true
	tank.controller._coyote_timer = 0.08
	tank.controller.set_on_ice(true)
	var state := tank.controller.capture_movement_state()
	tank.controller.reset_movement_state()
	tank.controller.restore_movement_state(state)
	_check(tank.controller._can_double_jump, "Double jump restored")
	_check(is_equal_approx(tank.controller._coyote_timer, 0.08), "Coyote timer restored")
	_check(tank.controller.is_on_ice, "Ice state restored")
	tank.controller.set_on_ice(false)

	# Повторяем неподтверждённые команды от исправленной сервером позиции.
	var base_position := tank.position
	var base_velocity := tank.velocity
	var base_state := tank.controller.capture_movement_state()
	sync._prediction_ready = true
	sync._motion_epoch = 1
	sync._pending_inputs.append({"command": {"seq": 1}, "position": base_position, "velocity": base_velocity})
	for seq in range(2, 8):
		tank.controller.process_movement(Vector3.RIGHT, false, 1.0 / 60.0, false, true)
		sync._pending_inputs.append({"command": {"seq": seq, "move": Vector3.RIGHT, "jump": false},
			"position": tank.position, "velocity": tank.velocity})
	var predicted_end := tank.position
	var snapshot := {"id": 10, "epoch": 1, "ack": 1,
		"position": base_position + Vector3(0, 0, -0.5), "yaw": 0.0,
		"velocity": base_velocity, "movement": base_state}
	sync._reconcile_movement(snapshot)
	_check(tank.position.distance_to(predicted_end + Vector3(0, 0, -0.5)) < 0.015, "Correction replays remaining movement")
	_check(sync.get_pending_input_count() == 6, "Only acknowledged input is removed")
	var corrected_position := tank.position
	var older := snapshot.duplicate(true)
	older.id = 9
	older.position += Vector3(100, 0, 0)
	sync._reconcile_movement(older)
	_check(tank.position == corrected_position, "Out of order snapshot ignored")
	older.id = 11
	older.epoch = 0
	sync._reconcile_movement(older)
	_check(tank.position == corrected_position, "Snapshot from previous life ignored")

	# Принудительная смена эпохи убирает старые команды и визуальную коррекцию.
	snapshot.id = 12
	snapshot.epoch = 2
	snapshot.position = Vector3(-10, 0, 0)
	sync._reconcile_movement(snapshot)
	_check(tank.position == snapshot.position, "New epoch teleports to authoritative position")
	_check(sync.get_pending_input_count() == 0, "New epoch clears pending inputs")
	_check(sync._visual_offset == Vector3.ZERO, "Teleport is not visually interpolated through walls")
	var events := [0]
	tank.events.jumped.connect(func(): events[0] += 1)
	base_state.on_floor = true
	base_state.jumping = false
	tank.controller.restore_movement_state(base_state)
	tank.controller.process_movement(Vector3.ZERO, true, 1.0 / 60.0, false, true)
	_check(events[0] == 0, "Replay does not trigger jump abilities")
	_check(tank.velocity.y > 0.0, "Replay still simulates jump")
	tank.queue_free()
	await get_tree().process_frame
	print("PREDICTION UNIT: %d failures" % _failures)
	get_tree().quit(1 if _failures else 0)
