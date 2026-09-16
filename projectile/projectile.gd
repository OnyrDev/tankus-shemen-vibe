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

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var light: OmniLight3D = get_node_or_null("OmniLight3D")
@onready var particles: GPUParticles3D = get_node_or_null("GPUParticles3D")
@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")

var _net_sync: MultiplayerSynchronizer = null

func _is_server() -> bool:
	return multiplayer.is_server() if multiplayer.has_multiplayer_peer() else true

func _ready() -> void:
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter as CollisionObject3D)

	velocity = direction.normalized() * speed
	if size_mult != 1.0:
		scale = Vector3.ONE * size_mult

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

func setup(p_shooter: Node, p_origin: Vector3, p_direction: Vector3, p_color: Color = Color(1.0, 0.85, 0.2)) -> void:
	shooter = p_shooter
	global_position = p_origin
	direction = p_direction.normalized()
	velocity = direction * speed

	if shooter is Tank:
		team_id = (shooter as Tank).team_id

	if is_node_ready():
		if shooter is CollisionObject3D:
			add_collision_exception_with(shooter as CollisionObject3D)
		_apply_color(p_color)
		if size_mult != 1.0:
			scale = Vector3.ONE * size_mult

func _apply_color(col: Color) -> void:
	if mesh_instance:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mesh_instance.material_override = mat

	if light:
		light.light_color = col

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

func _process_homing(delta: float) -> void:
	var tree := get_tree()
	if not tree:
		return

	var nearest_enemy: Tank = null
	var min_dist_sq := 250.0 # радиус поиска ~15-16м

	for node in tree.get_nodes_in_group("tanks"):
		if node is Tank and node != shooter and node.is_active:
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

func _handle_collision(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	var col_point := collision.get_position()
	var col_normal := collision.get_normal()

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
			global_position = col_point + bounce_norm * (0.22 * size_mult)
			bounced.emit(bounce_norm, bounces_done)
		return

	# Оповещаем стрелка
	if shooter is Tank and (shooter as Tank).events:
		(shooter as Tank).events.emit_projectile_hit(self, collider as Node, col_point, col_normal)

	# 1. Попадание в танк
	if target_tank != null and target_tank != shooter:
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
			var applied := target_tank.health.take_damage(final_damage, shooter)
			if applied and shooter is Tank and (shooter as Tank).events:
				(shooter as Tank).events.emit_damage_dealt(final_damage, target_tank)

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
			_spawn_impact_vfx(col_point, col_normal)
			return # снаряд не уничтожается, летит дальше!

		_spawn_impact_vfx(col_point, col_normal)
		_destroy()
		return

	# 2. Попадание в стену или статическое препятствие -> РИКОШЕТ
	if bounces_left > 0:
		bounces_left -= 1
		bounces_done += 1

		var bounce_normal := col_normal.normalized() if col_normal.length_squared() > 0.01 else -direction
		velocity = velocity.bounce(bounce_normal)
		direction = velocity.normalized()

		# Выдвигаем снаряд из поверхности по нормали на радиус сферы + запас безопасности,
		# чтобы исключить залипание в коллизии (sticky collision) на следующем тике физики!
		var safe_dist := 0.22 * size_mult
		global_position = col_point + bounce_normal * safe_dist

		# Бонус карты Ricochet Power (+25% урона, +15% скорости за каждый отскок)
		if ricochet_power_stacks > 0:
			damage *= (1.0 + 0.25 * ricochet_power_stacks)
			speed *= (1.0 + 0.15 * ricochet_power_stacks)
			velocity = direction * speed

		if shooter is Tank and (shooter as Tank).events:
			(shooter as Tank).events.emit_projectile_bounce(self, bounce_normal, bounces_done)

		bounced.emit(bounce_normal, bounces_done)
		_spawn_impact_vfx(col_point, bounce_normal)
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
	velocity = -velocity.bounce(normal)
	direction = velocity.normalized()
	speed *= 1.25
	damage *= 1.25
	velocity = direction * speed
	_time_alive = 0.0 # сбрасываем время жизни для нового полета

	_apply_color(reflecting_tank.team_color)
	_spawn_impact_vfx(global_position, normal)

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
					node.health.take_damage(aoe_dmg, shooter)

	# Визуальная вспышка AoE взрыва
	var boom := Node3D.new()
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.6
	sphere.height = radius * 1.2
	mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.8)
	mesh.material_override = mat

	boom.add_child(mesh)
	var spawn_parent := get_parent()
	if spawn_parent:
		spawn_parent.add_child(boom)
		boom.global_position = origin

	var tween := boom.create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 1.5, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(boom.queue_free)

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
				target.health.take_damage(dot_damage, shooter)
			if current_ticks >= total_ticks:
				poison_node.queue_free()
		)

func _spawn_impact_vfx(pos: Vector3, _normal: Vector3) -> void:
	var spawn_parent := get_parent()
	if not spawn_parent:
		return

	var impact := Node3D.new()
	var flash_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	flash_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	flash_mesh.material_override = mat

	impact.add_child(flash_mesh)
	spawn_parent.add_child(impact)
	impact.global_position = pos

	var tween := impact.create_tween()
	tween.tween_property(flash_mesh, "scale", Vector3.ZERO, 0.15).from(Vector3(1.5, 1.5, 1.5))
	tween.tween_callback(impact.queue_free)

func _destroy() -> void:
	if _is_destroyed:
		return
	_is_destroyed = true
	queue_free()
