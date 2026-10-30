class_name Projectile
extends CharacterBody3D

## Физический снаряд TANKUS с поддержкой рикошетов и карточных модификаторов.
## Обрабатывает отскоки от препятствий, пробивание (Piercing), AoE взрывы (Explosive Shell),
## яд (Poison DoT), самонаведение (Homing) и отражение щитом (Reflect).

signal hit_object(collider: Object, point: Vector3, normal: Vector3)
signal bounced(normal: Vector3, bounce_num: int)

@export var speed: float = 24.0
@export var damage: float = 28.0
@export var lifetime: float = 3.0
@export var bounces_left: int = 0

const HIT_SPARK_SCENE: PackedScene = preload("res://vfx/hit_spark_vfx.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://vfx/explosion_vfx.tscn")

var shooter: Node = null
var team_id: int = -1
var direction: Vector3 = Vector3.FORWARD

# Карточные модификаторы снаряда
var bounces_done: int = 0
var size_mult: float = 1.0
var is_explosive: bool = false
var explosion_radius: float = 2.5
var is_poison: bool = false
var poison_stacks: int = 0
var piercing_count: int = 0
var homing_strength: float = 0.0
var ricochet_power_stacks: int = 0
var sniper_bonus_rate: float = 0.0
var knockout_force: float = 0.0

var distance_traveled: float = 0.0
var _time_alive: float = 0.0
var _is_destroyed: bool = false

const ENERGY_COLOR := Color(0.08, 0.7, 1.0)

var _visual_color: Color = ENERGY_COLOR
var _base_visual_scale: Vector3 = Vector3(0.8, 0.8, 0.8)

@onready var visuals: Node3D = get_node_or_null("Visuals")
@onready var mesh_instance: MeshInstance3D = get_node_or_null("Visuals/Shell")
@onready var tail: MeshInstance3D = get_node_or_null("Visuals/Tail")
@onready var light: OmniLight3D = get_node_or_null("OmniLight3D")
@onready var particles: GPUParticles3D = get_node_or_null("Visuals/GPUParticles3D")
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")

var _net_sync: MultiplayerSynchronizer = null

func _is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

func get_valid_shooter() -> Node:
	if is_instance_valid(shooter):
		return shooter
	return null

func get_shooter_tank() -> Tank:
	if is_instance_valid(shooter) and shooter is Tank:
		return shooter as Tank
	return null

const DEFAULT_TEAM_COLORS: Array[Color] = [
	Color(0.18, 0.55, 0.95), # Синий (Хост)
	Color(0.95, 0.25, 0.25), # Красный
	Color(0.2, 0.85, 0.35),  # Зеленый
	Color(0.95, 0.75, 0.15), # Желтый
	Color(0.75, 0.25, 0.95), # Фиолетовый
	Color(0.15, 0.85, 0.85), # Бирюзовый
	Color(0.95, 0.5, 0.15),  # Оранжевый
	Color(0.85, 0.85, 0.85)  # Белый
]

var _pierced_rids: Array[RID] = []

func _ready() -> void:
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		add_collision_exception_with(shooter as CollisionObject3D)

	velocity = direction.normalized() * speed
	lifetime = maxf(lifetime, 72.0 / maxf(1.0, speed))
	if visuals:
		_base_visual_scale = visuals.scale
	if light and size_mult != 1.0:
		light.omni_range = 1.4 * size_mult

	_apply_color(DEFAULT_TEAM_COLORS[team_id % DEFAULT_TEAM_COLORS.size()] if team_id >= 0 else ENERGY_COLOR)
	_update_visual_direction()

	_setup_network_sync()

func _setup_network_sync() -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	_net_sync = MultiplayerSynchronizer.new()
	_net_sync.name = "ProjNetSync"
	_net_sync.replication_interval = 0.033 # 30 Hz

	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:global_position"))
	config.property_set_spawn(NodePath(".:global_position"), true)
	config.property_set_replication_mode(NodePath(".:global_position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	config.add_property(NodePath(".:velocity"))
	config.property_set_spawn(NodePath(".:velocity"), true)
	config.property_set_replication_mode(NodePath(".:velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	config.add_property(NodePath(".:team_id"))
	config.property_set_spawn(NodePath(".:team_id"), true)
	config.property_set_replication_mode(NodePath(".:team_id"), SceneReplicationConfig.REPLICATION_MODE_NEVER)

	config.add_property(NodePath(".:bounces_left"))
	config.property_set_spawn(NodePath(".:bounces_left"), true)
	config.property_set_replication_mode(NodePath(".:bounces_left"), SceneReplicationConfig.REPLICATION_MODE_NEVER)

	config.add_property(NodePath(".:speed"))
	config.property_set_spawn(NodePath(".:speed"), true)
	config.property_set_replication_mode(NodePath(".:speed"), SceneReplicationConfig.REPLICATION_MODE_NEVER)

	config.add_property(NodePath(".:size_mult"))
	config.property_set_spawn(NodePath(".:size_mult"), true)
	config.property_set_replication_mode(NodePath(".:size_mult"), SceneReplicationConfig.REPLICATION_MODE_NEVER)

	_net_sync.replication_config = config
	_net_sync.set_multiplayer_authority(1)
	add_child(_net_sync)

func setup(p_shooter: Node, p_origin: Vector3, p_direction: Vector3, p_color: Color = ENERGY_COLOR) -> void:
	shooter = p_shooter
	global_position = p_origin
	direction = p_direction.normalized()
	lifetime = maxf(lifetime, 72.0 / maxf(1.0, speed))
	velocity = direction * speed

	if is_instance_valid(shooter) and shooter is Tank:
		team_id = (shooter as Tank).team_id

	if is_node_ready():
		if is_instance_valid(shooter) and shooter is CollisionObject3D:
			add_collision_exception_with(shooter as CollisionObject3D)
		if light and size_mult != 1.0:
			light.omni_range = 1.4 * size_mult
		_apply_color(p_color)
		_update_visual_direction()

func _apply_color(col: Color) -> void:
	_visual_color = col
	for part in [mesh_instance, tail]:
		if not part:
			continue
		var mat := part.material_override as StandardMaterial3D
		if not mat:
			mat = part.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		var alpha := mat.albedo_color.a
		mat.albedo_color = Color(col.r, col.g, col.b, alpha)
		mat.emission = col
		part.material_override = mat

	if particles:
		var trail_material := particles.process_material.duplicate() as ParticleProcessMaterial
		trail_material.color = col.lightened(0.25)
		particles.process_material = trail_material
	if light:
		light.light_color = col

func _process(_delta: float) -> void:
	_update_visual_direction()

func _update_visual_direction() -> void:
	if not visuals or velocity.length_squared() < 0.001:
		return
	var forward := velocity.normalized()
	var up := Vector3.FORWARD if absf(forward.dot(Vector3.UP)) > 0.95 else Vector3.UP
	visuals.look_at(visuals.global_position + forward, up)
	visuals.scale = _base_visual_scale * size_mult

func _physics_process(delta: float) -> void:
	if _is_destroyed:
		return

	_time_alive += delta
	if _time_alive >= lifetime:
		_destroy()
		return

	# Логика самонаведения (Homing)
	if homing_strength > 0.0:
		_process_homing(delta)

	var move_delta := velocity * delta
	distance_traveled += move_delta.length()

	var collision := move_and_collide(move_delta)
	if collision:
		_handle_collision(collision)
	elif size_mult > 1.0 and not _is_destroyed:
		_check_enlarged_tank_hit()

func _process_homing(delta: float) -> void:
	var tree := get_tree()
	if not tree:
		return

	var nearest_enemy: Tank = null
	var min_dist_sq := 250.0 # радиус поиска ~15-16м
	var shooter_tank := get_shooter_tank()

	for node in tree.get_nodes_in_group("tanks"):
		if node is Tank and node != shooter_tank and node.is_active:
			if team_id < 0 or node.team_id != team_id:
				var d_sq := global_position.distance_squared_to(node.global_position)
				if d_sq < min_dist_sq:
					min_dist_sq = d_sq
					nearest_enemy = node

	if nearest_enemy:
		var target_pos := nearest_enemy.global_position + Vector3.UP * 0.4
		var to_enemy := (target_pos - global_position).normalized()
		var steer_rate := clampf(homing_strength * 3.5 * delta, 0.0, 1.0)
		direction = direction.lerp(to_enemy, steer_rate).normalized()
		velocity = direction * speed

func _check_enlarged_tank_hit() -> void:
	var world := get_world_3d()
	if not world:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18 * size_mult
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = global_transform
	query.collision_mask = 2 # Слой 2: только танки (не задевает пол и стены мира)
	var exclude_rids: Array[RID] = [get_rid()]
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		exclude_rids.append((shooter as CollisionObject3D).get_rid())
	for prid in _pierced_rids:
		exclude_rids.append(prid)
	query.exclude = exclude_rids

	var rest_info := world.direct_space_state.get_rest_info(query)
	if not rest_info.is_empty():
		var col_obj := instance_from_id(rest_info["collider_id"])
		if col_obj != null:
			_handle_direct_hit(col_obj, rest_info["point"], rest_info["normal"])

func _handle_collision(collision: KinematicCollision3D) -> void:
	_handle_direct_hit(collision.get_collider(), collision.get_position(), collision.get_normal())

func _handle_direct_hit(collider: Object, col_point: Vector3, col_normal: Vector3) -> void:
	hit_object.emit(collider, col_point, col_normal)

	var target_tank: Tank = null
	if collider is Tank:
		target_tank = collider as Tank
	elif collider != null and collider.get_parent() is Tank:
		target_tank = collider.get_parent() as Tank

	# На клиентах: урон рассчитывает сервер, но от стен снаряд ДОЛЖЕН отскакивать локально,
	# чтобы не залипать в препятствии в ожидании сетевого пакета!
	if not _is_server():
		_spawn_impact_vfx(col_point, col_normal)
		if target_tank == null and bounces_left > 0:
			bounces_left -= 1
			bounces_done += 1
			var bounce_norm := col_normal.normalized() if col_normal.length_squared() > 0.01 else -direction
			velocity = velocity.bounce(bounce_norm)
			direction = velocity.normalized()
			global_position = col_point + bounce_norm * 0.22
			bounced.emit(bounce_norm, bounces_done)
			if SoundManager:
				SoundManager.play_sfx_3d("ricochet", col_point)
		return

	var shooter_tank := get_shooter_tank()
	var valid_shooter := get_valid_shooter()

	# Оповещаем стрелка
	if shooter_tank and shooter_tank.events:
		shooter_tank.events.emit_projectile_hit(self, collider as Node, col_point, col_normal)

	# 1. Попадание в танк
	if target_tank != null and target_tank != shooter_tank:
		if SoundManager:
			SoundManager.play_sfx_3d("hit", col_point)
		# Проверка блокирования
		if target_tank.block and target_tank.block.is_blocking():
			# Проверка Reflect
			if target_tank.build and target_tank.build.has_card("reflect"):
				_reflect_projectile(target_tank, col_normal)
				return

			target_tank.block.absorb_projectile(self)
			_destroy()
			return

		# Нанесение прямого урона
		var final_damage := damage
		if sniper_bonus_rate > 0.0:
			final_damage += damage * (distance_traveled / 5.0) * sniper_bonus_rate

		if target_tank.health:
			var applied := target_tank.health.take_damage(final_damage, valid_shooter)
			if applied and shooter_tank and shooter_tank.events:
				shooter_tank.events.emit_damage_dealt(final_damage, target_tank)

		# Импульс отталкивания (Knockout)
		if knockout_force > 0.0:
			var knock_dir := direction
			knock_dir.y = 0.2
			target_tank.velocity += knock_dir.normalized() * (knockout_force / target_tank.stats.knockback_resistance if target_tank.stats else knockout_force)

		# Наложение яда (Poison DoT)
		if is_poison and poison_stacks > 0:
			_apply_poison_to_target(target_tank, poison_stacks)

		# Взрывной урон (Explosive Shell)
		if is_explosive:
			_trigger_aoe_explosion(col_point, final_damage * 0.5, explosion_radius)

		# Пробивание (Piercing)
		if piercing_count > 0:
			piercing_count -= 1
			add_collision_exception_with(target_tank)
			_pierced_rids.append(target_tank.get_rid())
			_spawn_impact_vfx(col_point, col_normal)
			return # снаряд не уничтожается, летит дальше!

		_spawn_impact_vfx(col_point, col_normal)
		_destroy()
		return

	# Если попали в физическое тело RigidBody3D (маятник или ящик) — передаем импульс
	if collider is RigidBody3D:
		var rbody := collider as RigidBody3D
		var hit_impulse := direction * (damage * 0.4 + knockout_force * 2.0)
		rbody.apply_impulse(hit_impulse, col_point - rbody.global_position)

	# 2. Попадание в стену или статическое препятствие -> РИКОШЕТ
	if bounces_left > 0:
		bounces_left -= 1
		bounces_done += 1

		var bounce_normal := col_normal.normalized() if col_normal.length_squared() > 0.01 else -direction
		velocity = velocity.bounce(bounce_normal)
		direction = velocity.normalized()

		# Выдвигаем снаряд из поверхности по нормали на радиус сферы + запас безопасности,
		# чтобы исключить залипание в коллизии (sticky collision) на следующем тике физики!
		var safe_dist := 0.22
		global_position = col_point + bounce_normal * safe_dist

		# Бонус карты Ricochet Power (+25% урона, +15% скорости за каждый отскок)
		if ricochet_power_stacks > 0:
			damage *= (1.0 + 0.25 * ricochet_power_stacks)
			speed *= (1.0 + 0.15 * ricochet_power_stacks)
			velocity = direction * speed

		if shooter_tank and shooter_tank.events:
			shooter_tank.events.emit_projectile_bounce(self, bounce_normal, bounces_done)

		bounced.emit(bounce_normal, bounces_done)
		_spawn_impact_vfx(col_point, bounce_normal)
		if SoundManager:
			SoundManager.play_sfx_3d("ricochet", col_point)
		return

	# Отскоки закончились: финальный взрыв и удаление
	if is_explosive:
		_trigger_aoe_explosion(col_point, damage * 0.5, explosion_radius)

	_spawn_impact_vfx(col_point, col_normal)
	_destroy()

func _reflect_projectile(reflecting_tank: Tank, normal: Vector3) -> void:
	shooter = reflecting_tank
	team_id = reflecting_tank.team_id
	add_collision_exception_with(reflecting_tank)

	# Разворачиваем снаряд в сторону стрелка
	velocity = velocity.bounce(normal)
	direction = velocity.normalized()
	speed *= 1.25
	damage *= 1.25
	velocity = direction * speed
	_time_alive = 0.0 # сбрасываем время жизни для нового полета

	_apply_color(reflecting_tank.team_color)
	_spawn_impact_vfx(global_position, normal)
	if SoundManager:
		SoundManager.play_sfx_3d("block", global_position)

func _trigger_aoe_explosion(origin: Vector3, splash_damage: float, radius: float) -> void:
	var tree := get_tree()
	if not tree:
		return

	for node in tree.get_nodes_in_group("tanks"):
		if node is Tank and node.is_active:
			var d := origin.distance_to(node.global_position)
			if d <= radius:
				var falloff := 1.0 - (d / radius)
				var aoe_dmg := splash_damage * clampf(falloff, 0.25, 1.0)
				if node.health:
					node.health.take_damage(aoe_dmg, get_valid_shooter())

	if SoundManager:
		SoundManager.play_sfx_3d("explosion", origin)
	if Game:
		Game.shake_camera(0.45)

	var spawn_parent := get_parent()
	if spawn_parent and EXPLOSION_SCENE:
		var boom := EXPLOSION_SCENE.instantiate() as ExplosionVFX
		if boom:
			spawn_parent.add_child(boom)
			boom.global_position = origin
			boom.setup(radius * 0.45)

func _apply_poison_to_target(target: Tank, stacks: int) -> void:
	var poison_node := target.get_node_or_null("PoisonEffect")
	if not poison_node:
		poison_node = Node.new()
		poison_node.name = "PoisonEffect"
		target.add_child(poison_node)

		var timer := Timer.new()
		timer.wait_time = 0.5
		timer.autostart = true
		poison_node.add_child(timer)

		var total_ticks := 6 # 3 секунды DoT
		var current_ticks := 0
		var dot_damage := 4.0 * stacks

		timer.timeout.connect(func():
			current_ticks += 1
			if is_instance_valid(target) and target.health and target.is_active:
				target.health.take_damage(dot_damage, get_valid_shooter())
			if current_ticks >= total_ticks:
				poison_node.queue_free()
		)

func _spawn_impact_vfx(pos: Vector3, normal: Vector3) -> void:
	var spawn_parent := get_parent()
	if not spawn_parent:
		return

	if HIT_SPARK_SCENE:
		var spark := HIT_SPARK_SCENE.instantiate() as HitSparkVFX
		if spark:
			spawn_parent.add_child(spark)
			spark.global_position = pos
			spark.setup(normal, _visual_color.lightened(0.35))

func _destroy() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	queue_free()
