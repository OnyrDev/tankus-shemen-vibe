class_name PhysicsPillar
extends RigidBody3D

## Тяжелый интерактивный физический пилон-монолит для TANKUS.
## Обладает высокой массой и трением: устойчив к одиночным выстрелам,
## но сдвигается при таране танком или плотном обстреле.
## Оснащен серверно-авторитетной сетевой репликацией (без десинхронизации).

@export var sync_rate_hz: float = 30.0
@export var lock_yaw_rotation: bool = true

var synced_position: Vector3 = Vector3.ZERO
var synced_rotation: Vector3 = Vector3.ZERO
var synced_linear_velocity: Vector3 = Vector3.ZERO

var _initial_transform: Transform3D = Transform3D.IDENTITY
var _synchronizer: MultiplayerSynchronizer = null
var _needs_teleport_reset: bool = false

func _is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

func _is_multiplayer() -> bool:
	return multiplayer.has_multiplayer_peer() and Network.is_multiplayer_active()

func _ready() -> void:
	add_to_group("physics_pillars")
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	if lock_yaw_rotation:
		axis_lock_angular_y = true

	_initial_transform = global_transform
	synced_position = global_position
	synced_rotation = rotation

	_setup_network_sync()
	_update_simulation_mode()

func _setup_network_sync() -> void:
	_synchronizer = MultiplayerSynchronizer.new()
	_synchronizer.name = "PillarNetSync"
	_synchronizer.replication_interval = 1.0 / sync_rate_hz
	_synchronizer.delta_interval = 0.0

	var config := SceneReplicationConfig.new()
	_add_replicated_property(config, NodePath(".:synced_position"), true)
	_add_replicated_property(config, NodePath(".:synced_rotation"), true)
	_add_replicated_property(config, NodePath(".:synced_linear_velocity"), false)

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
	if not _is_multiplayer():
		freeze = false
		return

	if _is_server():
		freeze = false
	else:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _physics_process(delta: float) -> void:
	if not _is_multiplayer():
		if global_position.y < -25.0:
			reset_to_start()
		return

	if _is_server():
		_server_process(delta)
	else:
		_client_process(delta)

func _server_process(_delta: float) -> void:
	if global_position.y < -25.0:
		reset_to_start()
		return

	synced_position = global_position
	synced_rotation = rotation
	synced_linear_velocity = linear_velocity

func _client_process(delta: float) -> void:
	var dist_sq := global_position.distance_squared_to(synced_position)
	if dist_sq > 16.0 or _needs_teleport_reset:
		global_position = synced_position
		rotation = synced_rotation
		_needs_teleport_reset = false
		return

	var lerp_t := minf(1.0, delta * 25.0)
	global_position = global_position.lerp(synced_position, lerp_t)

	var current_q := Quaternion.from_euler(rotation)
	var target_q := Quaternion.from_euler(synced_rotation)
	rotation = current_q.slerp(target_q, lerp_t).get_euler()

func reset_to_start() -> void:
	_needs_teleport_reset = true
	if _is_server():
		global_transform = _initial_transform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		synced_position = _initial_transform.origin
		synced_rotation = _initial_transform.basis.get_euler()
		synced_linear_velocity = Vector3.ZERO
	else:
		global_transform = _initial_transform

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _needs_teleport_reset and _is_server():
		state.transform = _initial_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_needs_teleport_reset = false
