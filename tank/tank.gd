class_name Tank
extends CharacterBody3D

## Главный класс сущности танка TANKUS.
## Объединяет компоненты ввода, физического контроллера, наведения башни,
## вооружения, защитного блока, здоровья, карточного билда и событий.

signal fell_into_void()

@export var peer_id: int = 1
@export var team_id: int = 0
@export var team_color: Color = Color(0.18, 0.55, 0.95):
	set(val):
		team_color = val
		_apply_team_color()

@onready var input: TankInput = get_node_or_null("TankInput")
@onready var controller: TankController = get_node_or_null("TankController")
@onready var turret: Turret = get_node_or_null("Visuals/TurretMount")
@onready var visuals: Node3D = get_node_or_null("Visuals")

@onready var weapon: WeaponComponent = get_node_or_null("WeaponComponent")
@onready var block: BlockComponent = get_node_or_null("BlockComponent")
@onready var health: HealthComponent = get_node_or_null("HealthComponent")

@onready var stats: TankStats = get_node_or_null("TankStats")
@onready var build: TankBuild = get_node_or_null("TankBuild")
@onready var events: TankEvents = get_node_or_null("TankEvents")

@onready var chassis_mesh: MeshInstance3D = get_node_or_null("Visuals/ChassisMesh")
@onready var turret_mesh: MeshInstance3D = get_node_or_null("Visuals/TurretMount/TurretMesh")
@onready var shield_mesh: MeshInstance3D = get_node_or_null("Visuals/ShieldMesh")

var spawn_point: Transform3D = Transform3D.IDENTITY
var is_active: bool = true

func _ready() -> void:
	add_to_group("tanks")
	spawn_point = global_transform
	_apply_team_color()

	if stats and build:
		stats.recalculate(build.cards, CardDatabase)

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	if controller:
		controller.process_physics(input, delta)

	if turret and input and input.is_aim_valid:
		turret.aim_at(input.aim_point, delta)

	_process_combat_input()

func _process_combat_input() -> void:
	if not input:
		return

	if input.consume_block():
		if block:
			block.activate_block()

	if input.consume_reload():
		if weapon:
			weapon.start_reload()

	if input.consume_fire() or input.is_fire_held():
		if weapon:
			weapon.try_fire()

func respawn(new_transform: Transform3D = spawn_point) -> void:
	global_transform = new_transform
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	is_active = true

	if visuals:
		visuals.visible = true

	if turret:
		turret.rotation = Vector3.ZERO

	if health:
		health.reset()

	if weapon:
		weapon.reset()

	if block:
		block.reset()

	if stats and build:
		stats.recalculate(build.cards, CardDatabase)

	_apply_team_color()

func set_team_color(p_color: Color) -> void:
	team_color = p_color

func _apply_team_color() -> void:
	var team_mat := StandardMaterial3D.new()
	team_mat.albedo_color = team_color
	team_mat.roughness = 0.35
	team_mat.metallic = 0.1

	if chassis_mesh:
		chassis_mesh.material_override = team_mat
	if turret_mesh:
		turret_mesh.material_override = team_mat
