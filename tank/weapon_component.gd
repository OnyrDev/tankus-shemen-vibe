class_name WeaponComponent
extends Node

## Компонент вооружения танка TANKUS.
## Управляет магазином на 4 снаряда, таймингом стрельбы (0.55с),
## перезарядкой (1.8с), отдачей ствола и спавном снарядов.

signal ammo_changed(current: int, max_ammo: int)
signal reload_started(duration: float)
signal reload_progress(current: float, total: float)
signal reload_completed()
signal shot_fired(projectile: Projectile)

@export var magazine_size: int = 4
@export var current_ammo: int = 4
@export var fire_interval: float = 0.55
@export var reload_time: float = 1.8
@export var projectile_scene: PackedScene = preload("res://projectile/projectile.tscn")

var _fire_cooldown: float = 0.0
var _is_reloading: bool = false
var _reload_timer: float = 0.0

var _tank: Tank = null
var _turret: Turret = null
var _barrel_mount: Node3D = null
var _barrel_initial_pos: Vector3 = Vector3.ZERO
var _recoil_tween: Tween = null

func _ready() -> void:
	_tank = get_parent() as Tank
	current_ammo = magazine_size

	if _tank:
		_turret = _tank.get_node_or_null("Visuals/TurretMount") as Turret
		if _turret:
			_barrel_mount = _turret.get_node_or_null("BarrelMount") as Node3D
			if _barrel_mount:
				_barrel_initial_pos = _barrel_mount.position

func _physics_process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	if _is_reloading:
		_reload_timer += delta
		reload_progress.emit(_reload_timer, reload_time)

		if _reload_timer >= reload_time:
			_complete_reload()

func can_fire() -> bool:
	if _tank and not _tank.is_active:
		return false
	if _is_reloading:
		return false
	if _fire_cooldown > 0.0:
		return false
	if current_ammo <= 0:
		return false
	return true

func is_reloading() -> bool:
	return _is_reloading

func get_reload_ratio() -> float:
	if not _is_reloading or reload_time <= 0.0:
		return 0.0
	return clampf(_reload_timer / reload_time, 0.0, 1.0)

func try_fire() -> bool:
	if _tank and not _tank.is_active:
		return false

	if current_ammo <= 0 and not _is_reloading:
		start_reload()
		return false

	if not can_fire():
		return false

	_fire()
	return true

func _fire() -> void:
	current_ammo -= 1
	_fire_cooldown = fire_interval
	ammo_changed.emit(current_ammo, magazine_size)

	if _tank and _tank.events:
		_tank.events.emit_shot()

	_spawn_projectile()
	_play_recoil()
	_spawn_muzzle_flash()

	if current_ammo <= 0:
		start_reload()

func get_projectile_spawn_parent() -> Node:
	var current_scn: Node = get_tree().current_scene if get_tree() else null
	if current_scn and current_scn.has_node("Projectiles"):
		return current_scn.get_node("Projectiles")
	elif current_scn:
		return current_scn
	elif _tank and _tank.get_parent():
		return _tank.get_parent()
	elif get_tree() and get_tree().root:
		return get_tree().root
	return null

func spawn_custom_projectile(origin: Vector3, shoot_dir: Vector3, damage_override: float = -1.0) -> Projectile:
	if not projectile_scene:
		return null

	var proj := projectile_scene.instantiate() as Projectile
	if not proj:
		return null

	if _tank and _tank.stats:
		proj.damage = damage_override if damage_override >= 0.0 else _tank.stats.damage
		proj.speed = _tank.stats.projectile_speed
		proj.bounces_left = _tank.stats.projectile_bounces
		proj.size_mult = _tank.stats.projectile_size
	elif damage_override >= 0.0:
		proj.damage = damage_override

	var spawn_parent := get_projectile_spawn_parent()
	if spawn_parent:
		spawn_parent.add_child(proj, true)
	else:
		add_child(proj, true)

	var team_col: Color = _tank.team_color if _tank else Color.YELLOW
	proj.setup(_tank, origin, shoot_dir, team_col)

	if _tank and _tank.events:
		_tank.events.emit_projectile_spawned(proj)

	shot_fired.emit(proj)
	return proj

func _spawn_projectile() -> void:
	var muzzle_pos: Vector3
	var shoot_dir: Vector3

	if _turret:
		muzzle_pos = _turret.get_muzzle_position()
		shoot_dir = _turret.get_shoot_direction()
	elif _tank:
		muzzle_pos = _tank.global_position + Vector3.UP * 0.9 - _tank.global_transform.basis.z * 1.5
		shoot_dir = -_tank.global_transform.basis.z
	else:
		return

	spawn_custom_projectile(muzzle_pos, shoot_dir)

func _play_recoil() -> void:
	if not _barrel_mount:
		return

	if _recoil_tween and _recoil_tween.is_valid():
		_recoil_tween.kill()

	_recoil_tween = create_tween()
	var kickback_pos := _barrel_initial_pos + Vector3(0, 0, 0.22)
	_recoil_tween.tween_property(_barrel_mount, "position", kickback_pos, 0.04).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(_barrel_mount, "position", _barrel_initial_pos, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _spawn_muzzle_flash() -> void:
	if not _turret:
		return

	var muzzle_pos := _turret.get_muzzle_position()
	var flash := Node3D.new()

	var sphere_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	sphere_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.4, 0.9)
	sphere_mesh.material_override = mat

	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.85, 0.3)
	omni.light_energy = 2.5
	omni.omni_range = 4.0

	flash.add_child(sphere_mesh)
	flash.add_child(omni)

	var spawn_parent: Node = null
	if get_tree() and get_tree().current_scene:
		spawn_parent = get_tree().current_scene
	elif _tank and _tank.get_parent():
		spawn_parent = _tank.get_parent()
	elif get_tree() and get_tree().root:
		spawn_parent = get_tree().root

	if spawn_parent:
		spawn_parent.add_child(flash)
		flash.global_position = muzzle_pos
	else:
		add_child(flash)

	var tween := flash.create_tween()
	tween.tween_property(sphere_mesh, "scale", Vector3.ZERO, 0.1).from(Vector3(1.2, 1.2, 1.2))
	tween.parallel().tween_property(omni, "light_energy", 0.0, 0.1)
	tween.tween_callback(flash.queue_free)

func start_reload() -> void:
	if _is_reloading or current_ammo >= magazine_size:
		return

	_is_reloading = true
	_reload_timer = 0.0
	reload_started.emit(reload_time)
	if _tank and _tank.events:
		_tank.events.emit_reload_started(reload_time)

func _complete_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0
	current_ammo = magazine_size
	ammo_changed.emit(current_ammo, magazine_size)
	reload_completed.emit()
	if _tank and _tank.events:
		_tank.events.emit_reload_completed()

func reset() -> void:
	_is_reloading = false
	_reload_timer = 0.0
	_fire_cooldown = 0.0
	current_ammo = magazine_size
	ammo_changed.emit(current_ammo, magazine_size)
