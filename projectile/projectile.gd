class_name Projectile
extends CharacterBody3D

## Базовый физический снаряд TANKUS.
## Движется прямолинейно через move_and_collide, обрабатывает попадания в стены и танки,
## учитывает щит (BlockComponent) и наносит урон (HealthComponent).

signal hit_object(collider: Object, point: Vector3, normal: Vector3)

@export var speed: float = 24.0
@export var damage: float = 28.0
@export var lifetime: float = 3.0

var shooter: Node = null
var team_id: int = -1
var direction: Vector3 = Vector3.FORWARD

@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var light: OmniLight3D = get_node_or_null("OmniLight3D")
@onready var particles: GPUParticles3D = get_node_or_null("GPUParticles3D")

var _time_alive: float = 0.0
var _is_destroyed: bool = false

func _ready() -> void:
	# Исключаем стрелка из коллизий снаряда
	if shooter is CollisionObject3D:
		add_collision_exception_with(shooter as CollisionObject3D)

	velocity = direction.normalized() * speed

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

	var collision := move_and_collide(velocity * delta)
	if collision:
		_handle_collision(collision)

func _handle_collision(collision: KinematicCollision3D) -> void:
	var collider := collision.get_collider()
	var col_point := collision.get_position()
	var col_normal := collision.get_normal()

	hit_object.emit(collider, col_point, col_normal)

	if collider != null:
		# 1. Проверяем блокирование щитом
		var block_comp: BlockComponent = null
		if collider.has_node("BlockComponent"):
			block_comp = collider.get_node("BlockComponent") as BlockComponent
		elif collider is Tank and (collider as Tank).block:
			block_comp = (collider as Tank).block

		if block_comp and block_comp.is_blocking():
			block_comp.absorb_projectile(self)
			_destroy()
			return

		# 2. Проверяем нанесение урона
		var health_comp: HealthComponent = null
		if collider.has_node("HealthComponent"):
			health_comp = collider.get_node("HealthComponent") as HealthComponent
		elif collider is Tank and (collider as Tank).health:
			health_comp = (collider as Tank).health

		if health_comp:
			health_comp.take_damage(damage, shooter)
		elif collider.has_method("take_damage"):
			collider.take_damage(damage, shooter)

	_spawn_impact_vfx(col_point, col_normal)
	_destroy()

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
