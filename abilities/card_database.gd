class_name CardDatabase
extends Object

## Каталог всех 42 способностей TANKUS по спецификации ROUNDS.
## Предоставляет доступ к базе карт и генератор предложений драфта 1 из 5.

# --- Специализированные эффекты способностей (Inner Classes) ---

class RicochetPowerEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.ricochet_power_stacks = stacks
		if proj.bounces_left < 1:
			proj.bounces_left = 1

class PoisonEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.is_poison = true
		proj.poison_stacks = stacks
		proj._apply_color(Color(0.28, 0.98, 0.32))

class ExplosiveShellEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.is_explosive = true
		proj.explosion_radius = 2.5 + (stacks - 1) * 0.8

class KnockoutEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.knockout_force = 12.0 * stacks

class PiercingEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.piercing_count = stacks

class HomingEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.homing_strength = 0.6 * stacks

class LastRoundEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, _stacks: int) -> void:
		if tank and tank.weapon and tank.weapon.current_ammo == 0:
			proj.damage *= 2.0 # Последний снаряд наносит двойной урон

class FirstRoundEffect extends CardEffect:
	var _is_first_round: bool = true

	func on_reload_completed(_stacks: int) -> void:
		_is_first_round = true

	func on_projectile_spawned(proj: Projectile, _stacks: int) -> void:
		if _is_first_round:
			_is_first_round = false
			proj.damage *= 1.6
			proj.speed *= 1.3
			proj.velocity = proj.direction * proj.speed

class RecoilEffect extends CardEffect:
	func on_shot(stacks: int) -> void:
		if tank and tank.turret:
			var push_dir := -tank.turret.get_shoot_direction()
			push_dir.y = 0.2
			tank.velocity += push_dir.normalized() * (9.0 * stacks)

class SniperShellEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		proj.sniper_bonus_rate = 0.10 * stacks

class ShotgunEffect extends CardEffect:
	func on_shot(_stacks: int) -> void:
		# Дополнительные 3 снаряда с разбросом (в мультиплеере спавнятся в Projectiles для MultiplayerSpawner)
		if not tank or not tank.weapon:
			return

		var base_pos := tank.global_position + Vector3.UP * 0.9 - tank.global_transform.basis.z * 1.5
		var base_dir := -tank.global_transform.basis.z
		if tank.turret:
			base_pos = tank.turret.get_muzzle_position()
			base_dir = tank.turret.get_shoot_direction()

		var angles: Array[float] = [-0.14, 0.08, 0.16]
		var shot_dmg := (tank.stats.damage if tank.stats else 28.0) * 0.45

		for angle in angles:
			var rot_dir := base_dir.rotated(Vector3.UP, angle).normalized()
			tank.weapon.spawn_custom_projectile(base_pos, rot_dir, shot_dmg)

class BlinkEffect extends CardEffect:
	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank or not tank.turret:
			return

		var aim_dir := tank.turret.get_shoot_direction()
		aim_dir.y = 0.0
		if aim_dir.length_squared() < 0.01:
			return
		aim_dir = aim_dir.normalized()

		var dist := 5.0 * stacks
		var space := tank.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			tank.global_position + Vector3.UP * 0.5,
			tank.global_position + Vector3.UP * 0.5 + aim_dir * dist,
			1 # стены
		)
		var hit := space.intersect_ray(query)
		var target_pos: Vector3
		if hit:
			target_pos = hit.position - aim_dir * 0.8
		else:
			target_pos = tank.global_position + aim_dir * dist

		tank.global_position = target_pos
		if tank.net_sync:
			tank.net_sync.reset_movement_prediction()

class ShockwaveEffect extends CardEffect:
	static func get_shockwave_radius(stacks: int) -> float:
		return 5.0 + float(maxi(1, stacks)) * 1.5

	static func spawn_shockwave_vfx(parent_node: Node, origin: Vector3, radius: float, color: Color = Color(0.2, 0.85, 1.0)) -> Node3D:
		if not parent_node:
			return null

		var wave := Node3D.new()
		wave.name = "BlockShockwaveWave"
		wave.set_meta("shockwave_radius", radius)
		parent_node.add_child(wave)
		wave.global_position = origin + Vector3(0.0, 0.45, 0.0)

		# 1. Быстро расширяющийся энергетический полупрозрачный тор (ударный фронт)
		var ring_mesh := MeshInstance3D.new()
		ring_mesh.name = "ShockwaveRing"
		var torus := TorusMesh.new()
		torus.outer_radius = 1.0
		torus.inner_radius = 0.82
		torus.rings = 32
		torus.ring_segments = 16
		ring_mesh.mesh = torus
		ring_mesh.scale = Vector3(0.2, 0.3, 0.2)

		var ring_mat := StandardMaterial3D.new()
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
		ring_mesh.material_override = ring_mat
		wave.add_child(ring_mesh)

		# 2. Сферический купол отталкивающего силового поля (pulse dome)
		var dome_mesh := MeshInstance3D.new()
		dome_mesh.name = "ShockwaveDome"
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 1.4
		sphere.radial_segments = 24
		sphere.rings = 12
		dome_mesh.mesh = sphere
		dome_mesh.scale = Vector3(0.2, 0.2, 0.2)

		var dome_mat := StandardMaterial3D.new()
		dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		dome_mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		dome_mesh.material_override = dome_mat
		wave.add_child(dome_mesh)

		# 3. Энергетическая вспышка света
		var light := OmniLight3D.new()
		light.name = "ShockwaveLight"
		light.light_color = color
		light.omni_range = radius * 1.3
		light.light_energy = 3.2
		wave.add_child(light)

		if SoundManager:
			SoundManager.play_sfx_3d("block", origin, 1.25)
		if Game:
			Game.shake_camera(clampf(0.18 + 0.03 * (radius / 5.0), 0.18, 0.38))

		var tween := wave.create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring_mesh, "scale", Vector3(radius, 0.4, radius), 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(dome_mesh, "scale", Vector3(radius * 0.9, radius * 0.5, radius * 0.9), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(dome_mat, "albedo_color:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(light, "light_energy", 0.0, 0.25)

		var tree := wave.get_tree()
		if tree:
			tree.create_timer(0.32).timeout.connect(func() -> void:
				if is_instance_valid(wave):
					wave.queue_free()
			)

		return wave

	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank:
			return

		var tree := tank.get_tree()
		if not tree:
			return

		var radius: float = get_shockwave_radius(stacks)
		var spawn_parent: Node = tank.get_parent() if tank.get_parent() else tree.current_scene
		if spawn_parent:
			var wave_col: Color = tank.team_color.lightened(0.35) if tank else Color(0.2, 0.85, 1.0)
			spawn_shockwave_vfx(spawn_parent, tank.global_position, radius, wave_col)

		if tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
			tank.net_sync.s2c_spawn_block_shockwave_vfx.rpc(tank.global_position, radius)

		for node in tree.get_nodes_in_group("tanks"):
			var target_tank := node as Tank
			if target_tank and target_tank != tank and target_tank.is_active:
				var to_target: Vector3 = target_tank.global_position - tank.global_position
				var dist: float = to_target.length()
				if dist <= radius and dist > 0.1:
					var force: float = (1.0 - dist / radius) * (18.0 * stacks)
					var push_dir: Vector3 = to_target.normalized()
					push_dir.y = 0.35
					target_tank.velocity += push_dir.normalized() * force

class ReloadBlockEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, stacks: int) -> void:
		if tank and tank.weapon and tank.weapon.is_reloading():
			# Сокращаем оставшееся время перезарядки
			tank.weapon._reload_timer += 1.0 * stacks

class AmmoShieldEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, stacks: int) -> void:
		if tank and tank.weapon:
			tank.weapon.current_ammo = mini(tank.weapon.magazine_size, tank.weapon.current_ammo + (1 * stacks))
			tank.weapon.ammo_changed.emit(tank.weapon.current_ammo, tank.weapon.magazine_size)

class CounterShotEffect extends CardEffect:
	func on_successful_block(_blocked_proj: Node, _stacks: int) -> void:
		if tank and tank.weapon:
			# Мгновенный выстрел без расхода обоймы (в мультиплеере спавнится в Projectiles для MultiplayerSpawner)
			var base_pos := tank.global_position + Vector3.UP * 0.9 - tank.global_transform.basis.z * 1.5
			var base_dir := -tank.global_transform.basis.z
			if tank.turret:
				base_pos = tank.turret.get_muzzle_position()
				base_dir = tank.turret.get_shoot_direction()
			tank.weapon.spawn_custom_projectile(base_pos, base_dir)


class GroundSlamEffect extends CardEffect:
	const BASE_RADIUS: float = 4.5
	const MIN_FALL_DIST: float = 1.2

	static func get_slam_radius(stacks: int) -> float:
		return BASE_RADIUS * float(maxi(1, stacks))

	static func spawn_shockwave_vfx(parent_node: Node, origin: Vector3, radius: float, color: Color = Color(1.0, 0.65, 0.15)) -> Node3D:
		if not parent_node:
			return null

		var wave := Node3D.new()
		wave.name = "GroundSlamWave"
		wave.set_meta("slam_radius", radius)
		parent_node.add_child(wave)
		wave.global_position = origin + Vector3(0.0, 0.08, 0.0)

		# Расширяющееся кольцо ударной волны по границе радиуса
		var ring_mesh := MeshInstance3D.new()
		ring_mesh.name = "ShockwaveRing"
		var torus := TorusMesh.new()
		torus.outer_radius = 1.0
		torus.inner_radius = 0.85
		torus.rings = 32
		torus.ring_segments = 16
		ring_mesh.mesh = torus
		ring_mesh.scale = Vector3(0.15, 1.0, 0.15)

		var ring_mat := StandardMaterial3D.new()
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.72, 0.2, 0.95)
		ring_mesh.material_override = ring_mat
		wave.add_child(ring_mesh)

		# Внутренний диск зоны поражения на земле
		var disc_mesh := MeshInstance3D.new()
		disc_mesh.name = "GroundDisc"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 0.03
		cylinder.radial_segments = 32
		disc_mesh.mesh = cylinder
		disc_mesh.scale = Vector3(0.15, 1.0, 0.15)

		var disc_mat := StandardMaterial3D.new()
		disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc_mat.albedo_color = Color(color.r, color.g, color.b, 0.42)
		disc_mesh.material_override = disc_mat
		wave.add_child(disc_mesh)

		# Вспышка света от удара о землю
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.65, 0.2)
		light.omni_range = radius * 1.25
		light.light_energy = 3.5
		wave.add_child(light)

		SoundManager.play_sfx_3d("explosion", origin)
		Game.shake_camera(clampf(0.20 + 0.05 * (radius / BASE_RADIUS), 0.20, 0.45))

		var tween := wave.create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring_mesh, "scale", Vector3(radius, 1.0, radius), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(disc_mesh, "scale", Vector3(radius, 1.0, radius), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(disc_mat, "albedo_color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(light, "light_energy", 0.0, 0.30)

		var tree := wave.get_tree()
		if tree:
			tree.create_timer(0.4).timeout.connect(func() -> void:
				if is_instance_valid(wave):
					wave.queue_free()
			)

		return wave

	func on_land(fall_dist: float, stacks: int) -> void:
		if not tank or fall_dist < MIN_FALL_DIST:
			return
		if not is_instance_valid(tank):
			return

		var radius: float = get_slam_radius(stacks)
		var slam_damage: float = 18.0 * float(maxi(1, stacks))
		var tree := tank.get_tree()
		if not tree:
			return

		var spawn_parent: Node = tank.get_parent() if tank.get_parent() else tree.current_scene
		if spawn_parent:
			spawn_shockwave_vfx(spawn_parent, tank.global_position, radius, tank.team_color)

		if tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
			tank.net_sync.s2c_spawn_ground_slam_vfx.rpc(tank.global_position, radius)

		for node in tree.get_nodes_in_group("tanks"):
			if node is Tank and is_instance_valid(tank) and node != tank and node.is_active:
				if tank.global_position.distance_to(node.global_position) <= radius:
					if node.health:
						node.health.take_damage(slam_damage, tank)

class JumpMineEffect extends CardEffect:
	const EXPLOSION_SCENE: PackedScene = preload("res://vfx/explosion_vfx.tscn")
	const MINE_MESH: ArrayMesh = preload("res://assets/props/jump_mine/jump_mine_mesh.res")
	const TRIGGER_RADIUS: float = 1.2
	const SCALE_PER_STACK: float = 0.35
	const LIFETIME: float = 8.0
	static var _next_mine_id: int = 1
	static var _active_mines: Dictionary = {}

	static func get_mine_scale(stacks: int) -> float:
		return 1.0 + float(maxi(1, stacks) - 1) * SCALE_PER_STACK

	static func get_trigger_radius(stacks: int) -> float:
		return TRIGGER_RADIUS * get_mine_scale(stacks)

	static func _resolve_spawn_parent(node: Node) -> Node:
		if not node:
			return null
		var tree := node.get_tree()
		var parent := node.get_parent()
		if parent and parent.name != "SpawnedTanks":
			return parent
		if tree and tree.current_scene:
			return tree.current_scene
		return parent

	static func create_mine_node(mine_id: int, origin: Vector3, spawn_parent: Node, stacks: int = 1) -> Area3D:
		var effective_stacks: int = maxi(1, stacks)
		var scale_mult: float = get_mine_scale(effective_stacks)
		var trigger_radius: float = get_trigger_radius(effective_stacks)

		var mine := Area3D.new()
		mine.name = "JumpMine_%d" % mine_id
		mine.collision_layer = 0
		mine.collision_mask = 2 # Слой 2: Tank
		mine.monitorable = false
		mine.monitoring = true
		mine.set_meta("mine_id", mine_id)
		mine.set_meta("stacks", effective_stacks)
		mine.set_meta("mine_scale", scale_mult)
		mine.add_to_group("jump_mines")

		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = trigger_radius
		shape.shape = sphere
		mine.add_child(shape)

		var mesh := MeshInstance3D.new()
		mesh.name = "JumpMineVisual"
		mesh.mesh = MINE_MESH
		mesh.scale = Vector3.ONE * scale_mult

		var dome_mat: StandardMaterial3D = null
		if MINE_MESH:
			for s in range(MINE_MESH.get_surface_count()):
				var base_mat := MINE_MESH.surface_get_material(s) as StandardMaterial3D
				if base_mat and (base_mat.resource_name.contains("Hazard optics") or s == 4):
					dome_mat = base_mat.duplicate() as StandardMaterial3D
					mesh.set_surface_override_material(s, dome_mat)
					break
		mine.add_child(mesh)

		var beacon_light := OmniLight3D.new()
		beacon_light.name = "BeaconLight"
		beacon_light.position = Vector3(0.0, 0.26 * scale_mult, 0.0)
		beacon_light.light_color = Color(1.0, 0.16, 0.08)
		beacon_light.omni_range = 1.8 * scale_mult
		beacon_light.light_energy = 1.4
		mine.add_child(beacon_light)

		if spawn_parent:
			spawn_parent.add_child(mine)
			mine.global_position = origin
			if mine.is_inside_tree():
				var target_scale := Vector3.ONE * scale_mult
				mesh.scale = target_scale * 0.2
				var pop_tween := mine.create_tween()
				pop_tween.tween_property(mesh, "scale", target_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

				var pulse_tween := mine.create_tween().set_loops(16)
				pulse_tween.tween_callback(func() -> void:
					if dome_mat:
						dome_mat.emission_energy_multiplier = 3.6
					if is_instance_valid(beacon_light):
						beacon_light.light_energy = 2.4
				)
				pulse_tween.tween_interval(0.25)
				pulse_tween.tween_callback(func() -> void:
					if dome_mat:
						dome_mat.emission_energy_multiplier = 1.0
					if is_instance_valid(beacon_light):
						beacon_light.light_energy = 0.5
				)
				pulse_tween.tween_interval(0.25)

		_active_mines[mine_id] = mine
		return mine

	static func spawn_explosion(spawn_parent: Node, origin: Vector3, scale_mult: float = 1.0) -> void:
		if spawn_parent and EXPLOSION_SCENE:
			var boom := EXPLOSION_SCENE.instantiate() as ExplosionVFX
			if boom:
				spawn_parent.add_child(boom)
				boom.global_position = origin + Vector3.UP * 0.2
				boom.setup(0.9 * scale_mult, Color(1.0, 0.35, 0.1))
		if SoundManager:
			SoundManager.play_sfx_3d("explosion", origin, 1.5)
		if Game:
			Game.shake_camera(clampf(0.25 * scale_mult, 0.25, 0.50))

	static func spawn_client_mine(mine_id: int, origin: Vector3, context_node: Node, stacks: int = 1) -> Area3D:
		var spawn_parent := _resolve_spawn_parent(context_node)
		if not spawn_parent:
			return null
		if _active_mines.has(mine_id) and is_instance_valid(_active_mines[mine_id]):
			_active_mines[mine_id].queue_free()
		var resolved_stacks: int = maxi(1, stacks)
		if context_node is Tank and (context_node as Tank).build:
			resolved_stacks = maxi(resolved_stacks, (context_node as Tank).build.get_stacks("jump_mine"))
		var mine := create_mine_node(mine_id, origin, spawn_parent, resolved_stacks)
		var tree := mine.get_tree()
		if tree:
			tree.create_timer(LIFETIME + 0.5).timeout.connect(func() -> void:
				remove_mine_by_id(mine_id, false, context_node)
			)
		return mine

	static func remove_mine_by_id(mine_id: int, exploded: bool, context_node: Node = null) -> void:
		var mine: Area3D = _active_mines.get(mine_id, null) as Area3D
		_active_mines.erase(mine_id)
		var pos := Vector3.ZERO
		var parent: Node = null
		var scale_mult: float = 1.0
		if is_instance_valid(mine):
			pos = mine.global_position
			parent = mine.get_parent()
			scale_mult = float(mine.get_meta("mine_scale", 1.0))
			mine.remove_from_group("jump_mines")
			mine.queue_free()
		if exploded:
			if not parent and context_node:
				parent = _resolve_spawn_parent(context_node)
			if parent:
				spawn_explosion(parent, pos, scale_mult)

	static func clear_all_mines(tree: SceneTree) -> void:
		_active_mines.clear()
		if not tree:
			return
		for node in tree.get_nodes_in_group("jump_mines"):
			if is_instance_valid(node):
				node.remove_from_group("jump_mines")
				node.queue_free()

	func on_jump(stacks: int) -> void:
		if not tank or not is_instance_valid(tank):
			return
		if tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and not tank.multiplayer.is_server():
			return

		var spawn_parent := _resolve_spawn_parent(tank)
		if not spawn_parent:
			return

		var effective_stacks: int = maxi(1, stacks)
		var mine_id: int = _next_mine_id
		_next_mine_id += 1
		var origin: Vector3 = tank.global_position
		var mine := create_mine_node(mine_id, origin, spawn_parent, effective_stacks)

		if tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
			tank.net_sync.s2c_spawn_jump_mine.rpc(mine_id, origin, effective_stacks)

		var mine_damage := 25.0 * float(effective_stacks)
		var creator := tank

		var try_detonate := func(body: Node3D) -> void:
			if not is_instance_valid(mine) or mine.get_meta("detonated", false):
				return
			var valid_creator := creator if is_instance_valid(creator) else null
			if body is Tank and body != valid_creator and body.is_active:
				if Game.rules.is_team_mode and not Game.rules.friendly_fire and valid_creator:
					if body.team_id == valid_creator.team_id:
						return
				mine.set_meta("detonated", true)
				if body.health:
					body.health.take_damage(mine_damage, valid_creator)
				remove_mine_by_id(mine_id, true, valid_creator)
				if valid_creator and valid_creator.net_sync and valid_creator.multiplayer and valid_creator.multiplayer.has_multiplayer_peer() and valid_creator.multiplayer.is_server():
					valid_creator.net_sync.s2c_detonate_jump_mine.rpc(mine_id, true)

		mine.body_entered.connect(try_detonate)

		# Проверяем танки, которые уже находятся прямо в радиусе мины в момент прыжка
		var trigger_radius := get_trigger_radius(effective_stacks)
		var tree := mine.get_tree()
		if tree:
			for node in tree.get_nodes_in_group("tanks"):
				if node is Tank and node != creator and node.is_active:
					if node.global_position.distance_to(origin) <= trigger_radius:
						try_detonate.call(node)
						break

			# Авто-удаление через 8с
			var timer := tree.create_timer(LIFETIME)
			timer.timeout.connect(func() -> void:
				if is_instance_valid(mine) and not mine.get_meta("detonated", false):
					mine.set_meta("detonated", true)
					remove_mine_by_id(mine_id, false, creator if is_instance_valid(creator) else null)
					if is_instance_valid(creator) and creator.net_sync and creator.multiplayer and creator.multiplayer.has_multiplayer_peer() and creator.multiplayer.is_server():
						creator.net_sync.s2c_detonate_jump_mine.rpc(mine_id, false)
			)

class DeathFromAboveEffect extends CardEffect:
	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		if tank and not tank.is_on_floor():
			proj.damage *= (1.0 + 0.40 * stacks)

class RegenerationEffect extends CardEffect:
	var _time_since_last_damage: float = 0.0

	func on_damage_taken(_amount: float, _attacker: Node, _stacks: int) -> void:
		_time_since_last_damage = 0.0

	func on_physics_process(delta: float, stacks: int) -> void:
		_time_since_last_damage += delta
		if _time_since_last_damage >= 3.0:
			if tank and tank.health and tank.is_active:
				tank.health.heal(6.0 * stacks * delta)

class VampireEffect extends CardEffect:
	func on_damage_dealt(amount: float, _target: Node, stacks: int) -> void:
		if tank and tank.health and tank.is_active:
			var heal_amount := amount * (0.25 * stacks)
			tank.health.heal(heal_amount)

class AdrenalineEffect extends CardEffect:
	func on_physics_process(_delta: float, stacks: int) -> void:
		if tank and tank.health and tank.controller:
			var hp_ratio := tank.health.get_health_ratio()
			if hp_ratio < 0.35:
				tank.controller.speed_multiplier = 1.0 + (0.50 * stacks)
			else:
				tank.controller.speed_multiplier = 1.0

class RoadRageEffect extends CardEffect:
	const MIN_RAM_SPEED: float = 4.0
	const MIN_OWN_FORWARD_SPEED: float = 2.5
	const DAMAGE_PER_SPEED: float = 2.5
	const HIT_COOLDOWN: float = 0.45

	var _hit_cooldowns: Dictionary = {}

	func _tick_cooldowns(delta: float) -> void:
		if _hit_cooldowns.is_empty():
			return
		var expired: Array = []
		for target_id in _hit_cooldowns:
			var rem: float = float(_hit_cooldowns[target_id]) - delta
			if rem <= 0.0:
				expired.append(target_id)
			else:
				_hit_cooldowns[target_id] = rem
		for target_id in expired:
			_hit_cooldowns.erase(target_id)

	func try_ram_target(target: Tank, impact_dir: Vector3, stacks: int) -> bool:
		if not tank or not is_instance_valid(tank) or not tank.is_active:
			return false
		if not target or not is_instance_valid(target) or target == tank or not target.is_active:
			return false

		var target_id := target.get_instance_id()
		if _hit_cooldowns.has(target_id):
			return false

		var attacker_vel: Vector3 = tank.velocity
		if tank.controller and tank.controller.pre_slide_velocity.length_squared() > attacker_vel.length_squared():
			attacker_vel = tank.controller.pre_slide_velocity

		var target_vel: Vector3 = target.velocity
		if target.controller and target.controller.pre_slide_velocity.length_squared() > target_vel.length_squared():
			target_vel = target.controller.pre_slide_velocity

		var flat_dir := Vector3(impact_dir.x, 0.0, impact_dir.z)
		if flat_dir.length_squared() < 0.001:
			flat_dir = Vector3(target.global_position.x - tank.global_position.x, 0.0, target.global_position.z - tank.global_position.z)
		if flat_dir.length_squared() < 0.001:
			return false
		var dir_to_target := flat_dir.normalized()

		# Таранящий танк должен сам двигаться в сторону цели (стоящий танк не наносит урон, если в него въехали)
		var own_forward_speed := Vector3(attacker_vel.x, 0.0, attacker_vel.z).dot(dir_to_target)
		if own_forward_speed < MIN_OWN_FORWARD_SPEED:
			return false

		var rel_vel := attacker_vel - target_vel
		var closing_speed := maxf(own_forward_speed, Vector3(rel_vel.x, 0.0, rel_vel.z).dot(dir_to_target))
		if closing_speed < MIN_RAM_SPEED:
			return false

		_hit_cooldowns[target_id] = HIT_COOLDOWN
		var effective_stacks: int = maxi(1, stacks)
		var ram_damage: float = closing_speed * DAMAGE_PER_SPEED * float(effective_stacks)

		if target.health:
			var applied := target.health.take_damage(ram_damage, tank)
			if applied and tank.events:
				tank.events.emit_damage_dealt(ram_damage, target)

		# Физический импульс расталкивания, чтобы танки не залипали друг в друге
		var kb_res: float = target.stats.knockback_resistance if target.stats else 1.0
		var push_force: float = clampf(closing_speed * (1.1 + 0.35 * float(effective_stacks - 1)), 6.0, 18.0) / maxf(0.1, kb_res)
		var push_vec := dir_to_target * push_force
		push_vec.y = 2.0
		target.velocity += push_vec
		tank.velocity = tank.velocity * 0.35 - dir_to_target * 2.5

		if SoundManager:
			SoundManager.play_sfx_3d("hit", (tank.global_position + target.global_position) * 0.5)
		if Game:
			Game.shake_camera(0.22)

		return true

	func on_physics_process(delta: float, stacks: int) -> void:
		_tick_cooldowns(delta)
		if not tank or not tank.is_active:
			return

		for i in range(tank.get_slide_collision_count()):
			var col := tank.get_slide_collision(i)
			var target := col.get_collider() as Tank
			if target and target != tank and target.is_active:
				var n := col.get_normal()
				# Исключаем вертикальные контакты (прыжок сверху на крышу)
				if absf(n.y) > 0.65:
					continue
				try_ram_target(target, -n, stacks)

class PhoenixEffect extends CardEffect:
	var _used_this_round: bool = false

	func on_death(_killer: Node, _stacks: int) -> bool:
		if _used_this_round:
			return false

		_used_this_round = true
		if tank and tank.health:
			# Отменяем гибель
			tank.health.current_health = tank.health.max_health * 0.5
			tank.health.health_changed.emit(tank.health.current_health, tank.health.max_health)
			if tank.block:
				tank.block.activate_block()
			return true

		return false

# --- Реестр всех карт ---

static var _cards_cache: Dictionary = {}

static func get_all_cards() -> Array[CardDefinition]:
	if _cards_cache.is_empty():
		_init_cards()

	var list: Array[CardDefinition] = []
	for k in _cards_cache:
		list.append(_cards_cache[k])
	return list

static func get_card(id: String) -> CardDefinition:
	if _cards_cache.is_empty():
		_init_cards()
	return _cards_cache.get(id, null)

static func generate_draft_offer(player_build: TankBuild, count: int = 5) -> Array[CardDefinition]:
	if _cards_cache.is_empty():
		_init_cards()

	var pool: Array[CardDefinition] = []
	for cid in _cards_cache:
		var card: CardDefinition = _cards_cache[cid]

		# Пропускаем unique карты, которые уже есть у игрока
		if card.unique and player_build and player_build.has_card(cid):
			continue

		# Пропускаем карты, достигшие max_stacks
		if player_build and player_build.get_stacks(cid) >= card.max_stacks:
			continue

		pool.append(card)

	pool.shuffle()
	var offer: Array[CardDefinition] = []
	var selected_count := mini(count, pool.size())
	for i in range(selected_count):
		offer.append(pool[i])

	return offer

static func _init_cards() -> void:
	_cards_cache.clear()

	# --- SHOT CARDS (18) ---
	_register("heavy_shell", "Heavy Shell", "+45% урона снарядов, -20% скорости полета.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.45, "proj_speed_mult": 0.8})
	_register("rapid_fire", "Rapid Fire", "-40% интервал между выстрелами, -15% урона.", CardDefinition.Category.SHOT, false, 99, {"fire_interval_mult": 0.60, "damage_mult": 0.85})
	_register("fastball", "Fastball", "+50% скорости полета снарядов.", CardDefinition.Category.SHOT, false, 99, {"proj_speed_mult": 1.50})
	_register("big_magazine", "Big Magazine", "+1 снаряд в магазин, +15% к времени перезарядки.", CardDefinition.Category.SHOT, false, 99, {"magazine_flat": 1, "reload_time_mult": 1.15})
	_register("quick_reload", "Quick Reload", "-30% к времени перезарядки.", CardDefinition.Category.SHOT, false, 99, {"reload_time_mult": 0.70})
	_register("bouncy", "Bouncy", "+1 дополнительный рикошет снаряда от препятствий.", CardDefinition.Category.SHOT, false, 99, {"bounces_flat": 1})
	_register("ricochet_power", "Ricochet Power", "+1 рикошет. Каждый рикошет увеличивает урон на +25% и скорость на +15%.", CardDefinition.Category.SHOT, false, 99, {"bounces_flat": 1}, RicochetPowerEffect)
	_register("poison", "Poison", "Снаряды отравляют цель DoT-уроном на 3 секунды.", CardDefinition.Category.SHOT, false, 99, {}, PoisonEffect)
	_register("explosive_shell", "Explosive Shell", "Снаряды взрываются при столкновении, нанося AoE урон.", CardDefinition.Category.SHOT, false, 99, {}, ExplosiveShellEffect)
	_register("big_shot", "Big Shot", "Снаряды крупнее (+80%) и мощнее (+30%), но летят медленнее (-25%).", CardDefinition.Category.SHOT, false, 99, {"proj_size_mult": 1.8, "damage_mult": 1.30, "proj_speed_mult": 0.75})
	_register("knockout", "Knockout", "Мощный импульс отталкивания при попадании снаряда.", CardDefinition.Category.SHOT, false, 99, {}, KnockoutEffect)
	_register("piercing", "Piercing", "Снаряд пробивает +1 вражеский танк насквозь.", CardDefinition.Category.SHOT, false, 99, {}, PiercingEffect)
	_register("homing", "Homing", "Снаряды плавно подруливают к ближайшим врагам.", CardDefinition.Category.SHOT, false, 99, {}, HomingEffect)
	_register("last_round", "Last Round", "Последний снаряд в обойме наносит +100% урона.", CardDefinition.Category.SHOT, false, 99, {}, LastRoundEffect)
	_register("first_round", "First Round", "Первый выстрел после перезарядки: +60% урона, +30% скорости.", CardDefinition.Category.SHOT, false, 99, {}, FirstRoundEffect)
	_register("recoil", "Recoil", "Выстрел толкает танк назад (Rocket Jump / мобильность), +15% урона.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.15}, RecoilEffect)
	_register("sniper_shell", "Sniper Shell", "+10% урона за каждые 5 метров дистанции полета снаряда.", CardDefinition.Category.SHOT, false, 99, {}, SniperShellEffect)
	_register("shotgun", "Shotgun", "Выстрел веером из 4 дробин с разбросом.", CardDefinition.Category.SHOT, true, 1, {}, ShotgunEffect)

	# --- BLOCK CARDS (8) ---
	_register("quick_guard", "Quick Guard", "-25% кулдаун защитного блока.", CardDefinition.Category.BLOCK, false, 99, {"block_cooldown_mult": 0.75})
	_register("long_block", "Long Block", "+50% длительность окна щита, +15% кулдаун.", CardDefinition.Category.BLOCK, false, 99, {"block_duration_mult": 1.50, "block_cooldown_mult": 1.15})
	_register("blink", "Blink", "Телепортация на 5м по направлению прицела при активации щита.", CardDefinition.Category.BLOCK, false, 99, {}, BlinkEffect)
	_register("shockwave", "Shockwave", "Щит испускает ударную волну, отталкивающую врагов.", CardDefinition.Category.BLOCK, false, 99, {}, ShockwaveEffect)
	_register("reload_block", "Reload Block", "Успешный блок сокращает текущее время перезарядки на 1с.", CardDefinition.Category.BLOCK, false, 99, {}, ReloadBlockEffect)
	_register("ammo_shield", "Ammo Shield", "Успешный блок восстанавливает +1 снаряд в обойму.", CardDefinition.Category.BLOCK, false, 99, {}, AmmoShieldEffect)
	_register("counter_shot", "Counter Shot", "Успешный блок автоматически выпускает ответный снаряд.", CardDefinition.Category.BLOCK, false, 99, {}, CounterShotEffect)
	_register("reflect", "Reflect", "Заблокированный снаряд отражается обратно во врага со сменой владельца.", CardDefinition.Category.BLOCK, true, 1, {})

	# --- JUMP CARDS (5) ---
	_register("high_jump", "High Jump", "+40% высота прыжка танка.", CardDefinition.Category.JUMP, false, 99, {"jump_velocity_mult": 1.40})
	_register("ground_slam", "Ground Slam", "Приземление с высоты вызывает ударную волну на 18 урона в радиусе 4.5м.", CardDefinition.Category.JUMP, false, 99, {}, GroundSlamEffect)
	_register("jump_mine", "Jump Mine", "При прыжке на земле остается мина с таймером 8 секунд.", CardDefinition.Category.JUMP, false, 99, {}, JumpMineEffect)
	_register("death_from_above", "Death From Above", "+40% урона снарядам, выпущенным в прыжке.", CardDefinition.Category.JUMP, false, 99, {}, DeathFromAboveEffect)
	_register("double_jump", "Double Jump", "Разрешает второй прыжок прямо в воздухе.", CardDefinition.Category.JUMP, true, 1, {})

	# --- GENERAL CARDS (11) ---
	_register("tankier", "Tankier", "+40 максимального здоровья танка.", CardDefinition.Category.GENERAL, false, 99, {"hp_flat": 40.0})
	_register("lightweight", "Lightweight", "+30% к скорости танка, снижена масса.", CardDefinition.Category.GENERAL, false, 99, {"move_speed_mult": 1.30, "knockback_resistance_mult": 0.7})
	_register("heavyweight", "Heavyweight", "+75% устойчивость к отталкиванию, +30% максимального HP, -12% скорости.", CardDefinition.Category.GENERAL, false, 99, {"knockback_resistance_mult": 1.75, "hp_mult": 1.30, "move_speed_mult": 0.88})
	_register("adrenaline", "Adrenaline", "+50% к скорости перемещения, когда HP падает ниже 35%.", CardDefinition.Category.GENERAL, false, 99, {}, AdrenalineEffect)
	_register("glass_cannon", "Glass Cannon", "-40% максимального HP, +75% урона.", CardDefinition.Category.GENERAL, false, 99, {"hp_mult": 0.60, "damage_mult": 1.75})
	_register("regeneration", "Regeneration", "Восстановление 6 HP/сек после 3 секунд без получения урона.", CardDefinition.Category.GENERAL, false, 99, {}, RegenerationEffect)
	_register("vampire", "Vampire", "Лечение на 25% от нанесенного по врагам урона.", CardDefinition.Category.GENERAL, false, 99, {}, VampireEffect)
	_register("road_rage", "Road Rage", "Таран вражеского танка на скорости наносит урон.", CardDefinition.Category.GENERAL, false, 99, {}, RoadRageEffect)
	_register("tiny_tank", "Tiny Tank", "Танк меньше (-30%) и быстрее (+25%), но теряет 25 HP.", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 0.70, "move_speed_mult": 1.25, "hp_flat": -25.0})
	_register("big_tank", "Big Tank", "Танк крупнее (+40%) и прочнее (+60 HP), но медленнее (-15%).", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 1.40, "hp_flat": 60.0, "move_speed_mult": 0.85})
	_register("phoenix", "Phoenix", "Один раз за раунд смертельный урон отменяется, танк оживает с 50% HP.", CardDefinition.Category.GENERAL, true, 1, {}, PhoenixEffect)

static func _register(
	id: String,
	display_name: String,
	description: String,
	category: CardDefinition.Category,
	unique: bool = false,
	max_stacks: int = 99,
	stat_modifiers: Dictionary = {},
	effect_script: Script = null
) -> void:
	var def := CardDefinition.new()
	def.id = id
	def.display_name = display_name
	def.description = description
	def.category = category
	def.unique = unique
	def.max_stacks = max_stacks
	def.stat_modifiers = stat_modifiers
	def.effect_script = effect_script
	_cards_cache[id] = def
