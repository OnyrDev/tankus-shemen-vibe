class_name Pendulum
extends Node3D

## Интерактивный физический маятник TANKUS с серверно-авторитетной репликацией.
## На сервере/хосте: подвешен на HingeJoint3D, рассчитывается физика колебаний и реакция на выстрелы/таран.
## На клиенте: кинематическое тело bob, синхронизирующееся с хостом без рассинхронизации.

@export var initial_swing_impulse: float = 0.0
@export var swing_direction: Vector3 = Vector3.FORWARD
@export var sync_rate_hz: float = 30.0

@onready var bob: RigidBody3D = get_node_or_null("Bob")
@onready var hinge: HingeJoint3D = get_node_or_null("HingeJoint3D")

var synced_bob_position: Vector3 = Vector3.ZERO
var synced_bob_rotation: Vector3 = Vector3.ZERO

var _initial_bob_transform: Transform3D = Transform3D.IDENTITY
var _synchronizer: MultiplayerSynchronizer = null

func _is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

func _is_multiplayer() -> bool:
	return multiplayer.has_multiplayer_peer() and Network.is_multiplayer_active()

func _ready() -> void:
	add_to_group("pendulums")
	if bob:
		_initial_bob_transform = bob.transform
		synced_bob_position = bob.global_position
		synced_bob_rotation = bob.rotation

	_setup_network_sync()
	_update_simulation_mode()

	if bob and initial_swing_impulse > 0.0 and _is_server():
		bob.apply_central_impulse(swing_direction.normalized() * initial_swing_impulse)

func _setup_network_sync() -> void:
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "PendulumNetSync"
	_synchronizer.replication_interval = 1.0 / sync_rate_hz
	_synchronizer.delta_interval = 0.0

	var config := SceneReplicationConfig.new()
	_add_replicated_property(config, NodePath(".:synced_bob_position"), true)
	_add_replicated_property(config, NodePath(".:synced_bob_rotation"), true)

	_synchronizer.replication_config = config
	_synchronizer.set_multiplayer_authority(1)
	add_child(_synchronizer)

func _add_replicated_property(config: SceneReplicationConfig, prop_path: NodePath, always_sync: bool) -> void:
	config.add_property(prop_path)
	config.property_set_spawn(prop_path, true)
	if always_sync:
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	else:
		config.property_set_replication_mode(prop_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

func _update_simulation_mode() -> void:
	if not bob:
		return

	if not _is_multiplayer():
		bob.freeze = false
		return

	if _is_server():
		bob.freeze = false
	else:
		bob.freeze = true
		bob.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _physics_process(delta: float) -> void:
	if not bob:
		return

	if not _is_multiplayer():
		return

	if _is_server():
		synced_bob_position = bob.global_position
		synced_bob_rotation = bob.rotation
	else:
		var dist_sq := bob.global_position.distance_squared_to(synced_bob_position)
		if dist_sq > 9.0:
			bob.global_position = synced_bob_position
			bob.rotation = synced_bob_rotation
			return

		var lerp_t := minf(1.0, delta * 25.0)
		bob.global_position = bob.global_position.lerp(synced_bob_position, lerp_t)
		var current_q := Quaternion.from_euler(bob.rotation)
		var target_q := Quaternion.from_euler(synced_bob_rotation)
		bob.rotation = current_q.slerp(target_q, lerp_t).get_euler()

func reset_to_start() -> void:
	if not bob:
		return

	if _is_server():
		bob.transform = _initial_bob_transform
		bob.linear_velocity = Vector3.ZERO
		bob.angular_velocity = Vector3.ZERO
		synced_bob_position = bob.global_position
		synced_bob_rotation = bob.rotation
		if initial_swing_impulse > 0.0:
			bob.apply_central_impulse(swing_direction.normalized() * initial_swing_impulse)
	else:
		bob.transform = _initial_bob_transform

