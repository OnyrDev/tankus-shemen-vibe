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

class SpreadEffect extends CardEffect:
	## Бонус урона (+70% за стак) задаётся через stat_modifiers карты, здесь — только разброс.
	const SPREAD_DEG_PER_STACK: float = 8.0
	const MAX_SPREAD_DEG: float = 60.0

	## Максимальное отклонение снаряда от линии прицела (в градусах) для заданного числа стаков.
	static func get_max_spread_deg(stacks: int) -> float:
		return minf(SPREAD_DEG_PER_STACK * float(maxi(1, stacks)), MAX_SPREAD_DEG)

	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		var max_angle: float = deg_to_rad(get_max_spread_deg(stacks))
		var angle: float = randf_range(-max_angle, max_angle)
		proj.direction = proj.direction.rotated(Vector3.UP, angle).normalized()
		proj.velocity = proj.direction * proj.speed

class CriticalHitEffect extends CardEffect:
	## 20% фиксированный шанс критического выстрела на 140% урона (+30% к крит-урону за каждый доп. стак).
	## Дебафф +20% к времени перезарядки задаётся через stat_modifiers карты.
	const CRIT_CHANCE: float = 0.20
	const BASE_CRIT_MULT: float = 1.40
	const EXTRA_CRIT_MULT_PER_STACK: float = 0.30

	static func get_crit_chance(_stacks: int = 1) -> float:
		return CRIT_CHANCE

	static func get_crit_damage_multiplier(stacks: int) -> float:
		return BASE_CRIT_MULT + EXTRA_CRIT_MULT_PER_STACK * float(maxi(1, stacks) - 1)

	static func apply_crit_to_projectile(proj: Projectile, stacks: int) -> void:
		if not proj:
			return
		var mult: float = get_crit_damage_multiplier(stacks)
		proj.damage *= mult
		proj.set_meta("is_critical_hit", true)
		proj.set_meta("crit_multiplier", mult)
		proj._apply_color(Color(1.0, 0.20, 0.24))

	func on_projectile_spawned(proj: Projectile, stacks: int) -> void:
		if not proj:
			return
		if randf() < CRIT_CHANCE:
			apply_crit_to_projectile(proj, stacks)

class AirVortexEffect extends CardEffect:
	## При попадании по врагу или на последнем отскоке по препятствию создаёт воздушную воронку на 3с.
	## Базовый радиус 3.0м (+1.0м за каждый дополнительный стак). Засасывает все танки и физические ящики.
	const BASE_RADIUS: float = 3.0
	const EXTRA_RADIUS_PER_STACK: float = 1.0
	const LIFETIME: float = 3.0
	const MAX_HEIGHT_DELTA: float = 3.0
	## Общий множитель силы втягивания (крути его: 0.5 — в 2 раза слабее, 1.0 — норма, 2.0 — в 2 раза сильнее)
	const PULL_STRENGTH: float = 1.3
	const TANK_PULL_SPEED: float = 4.2
	const TANK_PULL_ACCEL: float = 16.0
	const TANK_DIRECT_PULL_SPEED: float = 1.8
	const CRATE_PULL_SPEED: float = 3.8
	const CRATE_PULL_ACCEL: float = 14.0
	const CRATE_DIRECT_PULL_SPEED: float = 1.6

	static var _next_vortex_id: int = 1
	static var _active_vortexes: Dictionary = {}

	class VortexNode extends Node3D:
		var vortex_id: int = 0
		var owner_tank: Tank = null
		var stacks: int = 1
		var radius: float = 2.0
		var lifetime: float = 3.0
		var is_client_visual: bool = false
		var _age: float = 0.0
		var _swirl_root: Node3D = null
		var _inner_ring: MeshInstance3D = null
		var _ring_mat: StandardMaterial3D = null
		var _funnel_mat: StandardMaterial3D = null
		var _light: OmniLight3D = null

		func _ready() -> void:
			add_to_group("air_vortexes")

		func _process(delta: float) -> void:
			if _swirl_root:
				_swirl_root.rotation.y += delta * 11.5
			if _inner_ring:
				_inner_ring.rotation.y -= delta * 18.0

			var time_left: float = maxf(0.0, lifetime - _age)
			var fade: float = clampf(time_left / 0.35, 0.0, 1.0)
			if _ring_mat:
				_ring_mat.albedo_color.a = 0.72 * fade
			if _funnel_mat:
				_funnel_mat.albedo_color.a = 0.34 * fade
			if _light:
				_light.light_energy = 1.6 * fade

		func _physics_process(delta: float) -> void:
			_age += delta
			if not is_client_visual:
				_pull_entities(delta)

			if _age >= lifetime:
				var valid_owner := owner_tank if is_instance_valid(owner_tank) else null
				AirVortexEffect.remove_vortex_by_id(vortex_id)
				if not is_client_visual and valid_owner and valid_owner.net_sync and valid_owner.multiplayer and valid_owner.multiplayer.has_multiplayer_peer() and valid_owner.multiplayer.is_server():
					valid_owner.net_sync.s2c_remove_air_vortex.rpc(vortex_id)

		func _pull_entities(delta: float) -> void:
			var tree := get_tree()
			if not tree:
				return

			# 1. Засасываем вообще все активные танки в радиусе (врагов, союзников и самого стрелка)
			for node in tree.get_nodes_in_group("tanks"):
				var target := node as Tank
				if not target or not is_instance_valid(target) or not target.is_active:
					continue
				if target.health and not target.health.is_alive():
					continue
				if absf(target.global_position.y - global_position.y) > MAX_HEIGHT_DELTA:
					continue

				var to_center := Vector3(global_position.x - target.global_position.x, 0.0, global_position.z - target.global_position.z)
				var flat_dist := to_center.length()
				if flat_dist > radius or flat_dist < 0.08:
					continue

				var pull_dir := to_center / flat_dist
				var kb_res: float = target.stats.knockback_resistance if target.stats else 1.0
				var pull_scale: float = PULL_STRENGTH / maxf(0.4, kb_res)
				var desired_vel := pull_dir * (TANK_PULL_SPEED * pull_scale)
				target.velocity.x = move_toward(target.velocity.x, desired_vel.x, TANK_PULL_ACCEL * pull_scale * delta)
				target.velocity.z = move_toward(target.velocity.z, desired_vel.z, TANK_PULL_ACCEL * pull_scale * delta)

				var step_dist := minf(maxf(0.0, flat_dist - 0.12), TANK_DIRECT_PULL_SPEED * pull_scale * delta)
				if step_dist > 0.0001:
					target.move_and_collide(pull_dir * step_dist)

			# 2. Засасываем физические ящики в радиусе
			for node in tree.get_nodes_in_group("physics_crates"):
				var crate := node as RigidBody3D
				if not crate or not is_instance_valid(crate) or crate.freeze:
					continue
				if absf(crate.global_position.y - global_position.y) > MAX_HEIGHT_DELTA:
					continue

				var to_center := Vector3(global_position.x - crate.global_position.x, 0.0, global_position.z - crate.global_position.z)
				var flat_dist := to_center.length()
				if flat_dist > radius or flat_dist < 0.08:
					continue

				var pull_dir := to_center / flat_dist
				crate.sleeping = false
				var desired_vel := pull_dir * (CRATE_PULL_SPEED * PULL_STRENGTH)
				crate.linear_velocity.x = move_toward(crate.linear_velocity.x, desired_vel.x, CRATE_PULL_ACCEL * PULL_STRENGTH * delta)
				crate.linear_velocity.z = move_toward(crate.linear_velocity.z, desired_vel.z, CRATE_PULL_ACCEL * PULL_STRENGTH * delta)
				crate.apply_central_force(pull_dir * (crate.mass * CRATE_PULL_ACCEL * PULL_STRENGTH))

				var step_dist := minf(maxf(0.0, flat_dist - 0.12), CRATE_DIRECT_PULL_SPEED * PULL_STRENGTH * delta)
				if step_dist > 0.0001:
					crate.move_and_collide(pull_dir * step_dist)

	static func get_vortex_radius(stacks: int) -> float:
		return BASE_RADIUS + EXTRA_RADIUS_PER_STACK * float(maxi(1, stacks) - 1)

	static func create_vortex_node(vortex_id: int, origin: Vector3, stacks: int, spawn_parent: Node, owner_tank: Tank = null, is_client: bool = false) -> VortexNode:
		if not spawn_parent:
			return null
		remove_vortex_by_id(vortex_id)

		var effective_stacks: int = maxi(1, stacks)
		var v_radius: float = get_vortex_radius(effective_stacks)

		var vortex := VortexNode.new()
		vortex.name = "AirVortex_%d" % vortex_id
		vortex.vortex_id = vortex_id
		vortex.owner_tank = owner_tank
		vortex.stacks = effective_stacks
		vortex.radius = v_radius
		vortex.lifetime = LIFETIME
		vortex.is_client_visual = is_client
		vortex.set_meta("vortex_id", vortex_id)
		vortex.set_meta("stacks", effective_stacks)
		vortex.set_meta("radius", v_radius)

		var swirl_root := Node3D.new()
		swirl_root.name = "SwirlVisual"
		vortex.add_child(swirl_root)
		vortex._swirl_root = swirl_root

		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_mat.albedo_color = Color(0.38, 0.88, 1.0, 0.72)
		vortex._ring_mat = ring_mat

		var outer_mesh := MeshInstance3D.new()
		outer_mesh.name = "OuterRing"
		var outer_torus := TorusMesh.new()
		outer_torus.outer_radius = v_radius
		outer_torus.inner_radius = maxf(0.15, v_radius - 0.14)
		outer_torus.rings = 32
		outer_torus.ring_segments = 12
		outer_mesh.mesh = outer_torus
		outer_mesh.material_override = ring_mat
		outer_mesh.position = Vector3(0.0, 0.12, 0.0)
		swirl_root.add_child(outer_mesh)

		var inner_mesh := MeshInstance3D.new()
		inner_mesh.name = "InnerRing"
		var inner_torus := TorusMesh.new()
		inner_torus.outer_radius = maxf(0.35, v_radius * 0.55)
		inner_torus.inner_radius = maxf(0.12, v_radius * 0.55 - 0.12)
		inner_torus.rings = 24
		inner_torus.ring_segments = 10
		inner_mesh.mesh = inner_torus
		inner_mesh.material_override = ring_mat
		inner_mesh.position = Vector3(0.0, 0.38, 0.0)
		swirl_root.add_child(inner_mesh)
		vortex._inner_ring = inner_mesh

		var funnel_mat := StandardMaterial3D.new()
		funnel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		funnel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		funnel_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		funnel_mat.albedo_color = Color(0.55, 0.92, 1.0, 0.34)
		vortex._funnel_mat = funnel_mat

		var funnel_mesh := MeshInstance3D.new()
		funnel_mesh.name = "FunnelMesh"
		var cyl := CylinderMesh.new()
		cyl.top_radius = v_radius * 0.88
		cyl.bottom_radius = 0.22
		cyl.height = 1.35
		cyl.radial_segments = 24
		cyl.cap_top = false
		cyl.cap_bottom = false
		funnel_mesh.mesh = cyl
		funnel_mesh.material_override = funnel_mat
		funnel_mesh.position = Vector3(0.0, 0.68, 0.0)
		swirl_root.add_child(funnel_mesh)

		var light := OmniLight3D.new()
		light.name = "VortexLight"
		light.position = Vector3(0.0, 0.75, 0.0)
		light.light_color = Color(0.38, 0.88, 1.0)
		light.omni_range = v_radius + 1.5
		light.light_energy = 1.6
		vortex.add_child(light)
		vortex._light = light

		spawn_parent.add_child(vortex)
		vortex.global_position = origin

		if vortex.is_inside_tree():
			swirl_root.scale = Vector3.ONE * 0.2
			var pop_tween := vortex.create_tween()
			pop_tween.tween_property(swirl_root, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		_active_vortexes[vortex_id] = vortex
		return vortex

	static func spawn_client_vortex(vortex_id: int, origin: Vector3, stacks: int, context_node: Node) -> VortexNode:
		var spawn_parent := JumpMineEffect._resolve_spawn_parent(context_node)
		return create_vortex_node(vortex_id, origin, stacks, spawn_parent, null, true)

	static func remove_vortex_by_id(vortex_id: int) -> void:
		var vortex: Node3D = _active_vortexes.get(vortex_id, null) as Node3D
		_active_vortexes.erase(vortex_id)
		if is_instance_valid(vortex):
			vortex.remove_from_group("air_vortexes")
			vortex.queue_free()

	static func clear_all(tree: SceneTree) -> void:
		_active_vortexes.clear()
		if not tree:
			return
		for node in tree.get_nodes_in_group("air_vortexes"):
			if is_instance_valid(node):
				node.remove_from_group("air_vortexes")
				node.queue_free()

	func on_projectile_hit(proj: Projectile, target: Node, point: Vector3, _normal: Vector3, stacks: int) -> void:
		if not tank or not is_instance_valid(tank):
			return
		if tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and not tank.multiplayer.is_server():
			return

		var is_enemy_tank: bool = target is Tank and target != tank
		if is_enemy_tank:
			var hit_tank := target as Tank
			if hit_tank.block and hit_tank.block.is_blocking() and hit_tank.build and hit_tank.build.has_card("reflect"):
				return
		else:
			# На препятствиях/стенах воронка появляется только на последнем ударе, когда рикошетов не осталось
			if proj and proj.bounces_left > 0:
				return

		var spawn_parent := JumpMineEffect._resolve_spawn_parent(tank)
		if not spawn_parent:
			return

		var effective_stacks: int = maxi(1, stacks)
		var vortex_id: int = _next_vortex_id
		_next_vortex_id += 1

		var origin := Vector3(point.x, tank.global_position.y, point.z)
		if tank.get_world_3d():
			var space := tank.get_world_3d().direct_space_state
			var ray_start := Vector3(point.x, point.y + 0.6, point.z)
			if _normal.length_squared() > 0.01:
				var flat_norm := Vector3(_normal.x, 0.0, _normal.z)
				if flat_norm.length_squared() > 0.01:
					flat_norm = flat_norm.normalized()
					ray_start.x += flat_norm.x * 0.25
					ray_start.z += flat_norm.z * 0.25
			var ray := PhysicsRayQueryParameters3D.create(ray_start, ray_start + Vector3.DOWN * 12.0, 1)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				origin.y = hit.position.y

		create_vortex_node(vortex_id, origin, effective_stacks, spawn_parent, tank, false)
		if tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
			tank.net_sync.s2c_spawn_air_vortex.rpc(vortex_id, origin, effective_stacks)

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

class WallhackEffect extends CardEffect:
	## При активации щита подсвечивает вражеские танки сквозь стены на BASE_DURATION секунд за стак.
	## Щит срабатывает штатно, а кулдаун блока увеличен на +40% через stat_modifiers.
	const BASE_DURATION: float = 2.0
	const FADE_OUT_TIME: float = 0.25

	class WallhackRevealNode extends Node3D:
		var time_left: float = 2.0
		var _elapsed: float = 0.0
		var _xray_mat: StandardMaterial3D = null
		var _outline_mat: StandardMaterial3D = null

		func _ready() -> void:
			add_to_group("wallhack_reveals")
			_apply_xray_overlay()

		func setup_or_refresh(duration: float) -> void:
			time_left = maxf(time_left, maxf(0.1, duration))
			if is_inside_tree():
				_apply_xray_overlay()

		func _apply_xray_overlay() -> void:
			var target := get_parent() as Tank
			if not is_instance_valid(target) or not target.visuals:
				return

			var base_col: Color = target.team_color if target else Color(1.0, 0.25, 0.2)
			var fill_col: Color = base_col.lightened(0.30)
			var rim_col: Color = base_col.lightened(0.55)

			if not _outline_mat:
				_outline_mat = StandardMaterial3D.new()
				_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
				_outline_mat.grow = true
				_outline_mat.grow_amount = 0.035
				_outline_mat.no_depth_test = true
				_outline_mat.render_priority = 11
			_outline_mat.albedo_color = Color(rim_col.r, rim_col.g, rim_col.b, 0.92)

			if not _xray_mat:
				_xray_mat = StandardMaterial3D.new()
				_xray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_xray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_xray_mat.no_depth_test = true
				_xray_mat.render_priority = 10
				_xray_mat.next_pass = _outline_mat
			_xray_mat.albedo_color = Color(fill_col.r, fill_col.g, fill_col.b, 0.48)

			TankAppearance.set_wallhack_overlay(target.visuals, _xray_mat)

		func clear_overlay() -> void:
			var target := get_parent() as Tank
			if is_instance_valid(target):
				target.set_meta("wallhack_revealed", false)
				if target.visuals:
					TankAppearance.clear_wallhack_overlay(target.visuals, _xray_mat)

		func _exit_tree() -> void:
			clear_overlay()

		func _physics_process(delta: float) -> void:
			var target := get_parent() as Tank
			if not is_instance_valid(target) or not target.is_active or (target.health and not target.health.is_alive()):
				clear_overlay()
				queue_free()
				return

			_elapsed += delta
			time_left -= delta
			if time_left <= 0.0:
				clear_overlay()
				queue_free()
				return

			if _xray_mat and _outline_mat:
				var fade := clampf(time_left / FADE_OUT_TIME, 0.0, 1.0)
				var pulse := 0.42 + 0.14 * sin(_elapsed * PI * 4.5)
				_xray_mat.albedo_color.a = pulse * fade
				_outline_mat.albedo_color.a = 0.92 * fade

	static func get_reveal_duration(stacks: int) -> float:
		return BASE_DURATION * float(maxi(1, stacks))

	static func apply_reveal_to_target(target_tank: Tank, duration: float) -> WallhackRevealNode:
		if not is_instance_valid(target_tank) or not target_tank.is_active:
			return null

		target_tank.set_meta("wallhack_revealed", true)
		var existing := target_tank.get_node_or_null("WallhackReveal") as WallhackRevealNode
		if existing and is_instance_valid(existing):
			if not existing.is_queued_for_deletion():
				existing.setup_or_refresh(duration)
				return existing
			existing.name = "WallhackRevealExpired"

		var reveal_node := WallhackRevealNode.new()
		reveal_node.name = "WallhackReveal"
		reveal_node.time_left = maxf(0.1, duration)
		target_tank.add_child(reveal_node)
		reveal_node.setup_or_refresh(duration)
		return reveal_node

	static func reveal_enemies_for_tank(viewer_tank: Tank, duration: float) -> int:
		if not is_instance_valid(viewer_tank):
			return 0
		var tree := viewer_tank.get_tree()
		if not tree:
			return 0

		var revealed_count: int = 0
		for node in tree.get_nodes_in_group("tanks"):
			var target := node as Tank
			if not target or target == viewer_tank or not target.is_active:
				continue
			if target.health and not target.health.is_alive():
				continue
			if Game and Game.rules and Game.rules.is_team_mode:
				if target.team_id == viewer_tank.team_id:
					continue
			if apply_reveal_to_target(target, duration) != null:
				revealed_count += 1
		return revealed_count

	static func clear_all_reveals(tree: SceneTree) -> void:
		if not tree:
			return
		for node in tree.get_nodes_in_group("wallhack_reveals"):
			if is_instance_valid(node):
				if node.has_method("clear_overlay"):
					node.clear_overlay()
				node.remove_from_group("wallhack_reveals")
				node.queue_free()

	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank or not is_instance_valid(tank):
			return

		var reveal_duration: float = get_reveal_duration(stacks)
		var p_info := Network.get_player_info(tank.peer_id) if Network else null
		var is_bot: bool = p_info != null and p_info.is_bot

		# На локальном владельце (или в синглплеере/песочнице) сразу включаем просвет врагов
		if (tank.net_sync == null or tank.net_sync.is_local_owner()) and not is_bot:
			reveal_enemies_for_tank(tank, reveal_duration)

		# Если блок нажал удаленный клиент — отправляем ему персональный RPC на включение просвета
		if tank.net_sync and not tank.net_sync.is_local_owner() and not is_bot:
			if tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
				if tank.peer_id in tank.multiplayer.get_peers():
					tank.net_sync.s2c_activate_wallhack.rpc_id(tank.peer_id, reveal_duration)

class BurgerTerminalEffect extends CardEffect:
	## При активации щита ставит терминал, который раз в секунду выбрасывает бургер (+10 HP за стак).
	## Базовое время жизни терминала 3с (+1с за каждый дополнительный стак).
	const TERMINAL_SCENE: PackedScene = preload("res://assets/props/terminal/terminal.glb")
	const BURGER_SCENE: PackedScene = preload("res://assets/props/burger/Burger.glb")
	const BASE_TERMINAL_LIFETIME: float = 3.0
	const EXTRA_LIFETIME_PER_STACK: float = 1.0
	const BURGER_INTERVAL: float = 1.0
	const BASE_HEAL: float = 10.0
	const BURGER_LIFETIME: float = 8.0
	const BURGER_PICKUP_RADIUS: float = 1.15
	const BURGER_VISUAL_SCALE: float = 0.35
	const DISPENSE_MIN_DIST: float = 2.8
	const DISPENSE_MAX_DIST: float = 5.2

	static var _next_terminal_id: int = 1
	static var _next_burger_id: int = 1
	static var _active_terminals: Dictionary = {}
	static var _active_burgers: Dictionary = {}

	class TerminalNode extends Node3D:
		var terminal_id: int = 0
		var owner_tank: Tank = null
		var stacks: int = 1
		var lifetime: float = 3.0
		var heal_amount: float = 10.0
		var is_client_visual: bool = false
		var burgers_spawned: int = 0
		var max_burgers: int = 3
		var _age: float = 0.0
		var _spawn_timer: float = 0.0

		func _ready() -> void:
			add_to_group("burger_terminals")

		func _physics_process(delta: float) -> void:
			if is_client_visual:
				_age += delta
				if _age >= lifetime:
					BurgerTerminalEffect.remove_terminal_by_id(terminal_id)
				return

			_age += delta
			_spawn_timer += delta

			while _spawn_timer >= BURGER_INTERVAL and burgers_spawned < max_burgers:
				_spawn_timer -= BURGER_INTERVAL
				burgers_spawned += 1
				_dispense_burger()

			if _age >= lifetime:
				var valid_owner := owner_tank if is_instance_valid(owner_tank) else null
				BurgerTerminalEffect.remove_terminal_by_id(terminal_id)
				if valid_owner and valid_owner.net_sync and valid_owner.multiplayer and valid_owner.multiplayer.has_multiplayer_peer() and valid_owner.multiplayer.is_server():
					valid_owner.net_sync.s2c_remove_burger_terminal.rpc(terminal_id)

		func _dispense_burger() -> void:
			var spawn_parent := get_parent()
			if not spawn_parent:
				return
			var angle: float = float(burgers_spawned - 1) * (TAU / maxf(3.0, float(max_burgers))) + randf_range(-0.25, 0.25)
			var dist: float = randf_range(DISPENSE_MIN_DIST, DISPENSE_MAX_DIST)
			var forward := -global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() < 0.001:
				forward = Vector3.FORWARD
			forward = forward.normalized()
			var offset := forward.rotated(Vector3.UP, angle) * dist
			var from_pos := global_position + Vector3(0.0, 0.85, 0.0)
			var target_pos := global_position + Vector3(offset.x, 0.0, offset.z)
			var valid_owner := owner_tank if is_instance_valid(owner_tank) else null
			BurgerTerminalEffect.spawn_server_burger(from_pos, target_pos, heal_amount, spawn_parent, valid_owner)

	static func get_terminal_lifetime(stacks: int) -> float:
		return BASE_TERMINAL_LIFETIME + EXTRA_LIFETIME_PER_STACK * float(maxi(1, stacks) - 1)

	static func get_burger_heal(stacks: int) -> float:
		return BASE_HEAL * float(maxi(1, stacks))

	static func create_terminal_node(terminal_id: int, origin: Vector3, yaw: float, stacks: int, spawn_parent: Node, owner_tank: Tank = null, is_client: bool = false) -> TerminalNode:
		if not spawn_parent:
			return null
		remove_terminal_by_id(terminal_id)

		var effective_stacks: int = maxi(1, stacks)
		var term := TerminalNode.new()
		term.name = "BurgerTerminal_%d" % terminal_id
		term.terminal_id = terminal_id
		term.owner_tank = owner_tank
		term.stacks = effective_stacks
		term.lifetime = get_terminal_lifetime(effective_stacks)
		term.heal_amount = get_burger_heal(effective_stacks)
		term.max_burgers = int(round(term.lifetime / BURGER_INTERVAL))
		term.is_client_visual = is_client
		term.set_meta("terminal_id", terminal_id)
		term.set_meta("stacks", effective_stacks)

		var visual_holder := Node3D.new()
		visual_holder.name = "TerminalVisual"
		if TERMINAL_SCENE:
			var glb_inst := TERMINAL_SCENE.instantiate()
			if glb_inst:
				# Скрываем студийную подложку Ground_Pavement (8x8м) из GLB
				var pavement := glb_inst.get_node_or_null("Ground_Pavement")
				if pavement:
					pavement.free()
				visual_holder.add_child(glb_inst)
		term.add_child(visual_holder)

		var light := OmniLight3D.new()
		light.name = "TerminalLight"
		light.position = Vector3(0.0, 1.5, 0.45)
		light.light_color = Color(1.0, 0.78, 0.28)
		light.omni_range = 3.2
		light.light_energy = 1.6
		term.add_child(light)

		spawn_parent.add_child(term)
		term.global_position = origin
		term.rotation = Vector3(0.0, yaw, 0.0)

		if term.is_inside_tree():
			visual_holder.scale = Vector3.ONE * 0.2
			var pop_tween := term.create_tween()
			pop_tween.tween_property(visual_holder, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		if SoundManager:
			SoundManager.play_sfx_3d("vkusno_i_tochka", origin, 2.0, 0.0)

		_active_terminals[terminal_id] = term
		return term

	static func create_burger_node(burger_id: int, from_pos: Vector3, target_pos: Vector3, heal_amount: float, spawn_parent: Node) -> Area3D:
		if not spawn_parent:
			return null
		remove_burger_by_id(burger_id)

		var burger := Area3D.new()
		burger.name = "BurgerPickup_%d" % burger_id
		burger.collision_layer = 0
		burger.collision_mask = 2 # Слой 2: Tank
		burger.monitorable = false
		burger.monitoring = true
		burger.set_meta("burger_id", burger_id)
		burger.set_meta("heal_amount", heal_amount)
		burger.set_meta("target_pos", target_pos)
		burger.add_to_group("burger_pickups")

		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = BURGER_PICKUP_RADIUS
		shape.shape = sphere
		shape.position = Vector3(0.0, 0.45, 0.0)
		burger.add_child(shape)

		var visual_holder := Node3D.new()
		visual_holder.name = "BurgerVisual"
		visual_holder.scale = Vector3.ONE * BURGER_VISUAL_SCALE
		if BURGER_SCENE:
			var glb_inst := BURGER_SCENE.instantiate()
			if glb_inst:
				visual_holder.add_child(glb_inst)
		burger.add_child(visual_holder)

		var light := OmniLight3D.new()
		light.name = "BurgerLight"
		light.position = Vector3(0.0, 0.55, 0.0)
		light.light_color = Color(0.35, 1.0, 0.45)
		light.omni_range = 2.0
		light.light_energy = 1.3
		burger.add_child(light)

		GroundTelegraph3D._ensure_textures()
		var zone_decal := Decal.new()
		zone_decal.name = "BurgerZoneDecal"
		zone_decal.cull_mask = 1
		zone_decal.size = Vector3(BURGER_PICKUP_RADIUS * 2.0, 2.2, BURGER_PICKUP_RADIUS * 2.0)
		zone_decal.upper_fade = 0.15
		zone_decal.lower_fade = 0.22
		zone_decal.normal_fade = 0.55
		zone_decal.texture_albedo = GroundTelegraph3D._drop_albedo_tex
		zone_decal.texture_emission = GroundTelegraph3D._drop_emission_tex
		zone_decal.modulate = Color(0.32, 1.0, 0.46, 0.65)
		zone_decal.emission_energy = 1.25
		burger.add_child(zone_decal)

		spawn_parent.add_child(burger)
		burger.global_position = target_pos

		# Заметный 0.30-секундный маркер точки приземления вылетающего по дуге бургера
		GroundTelegraph3D.spawn_timed(
			spawn_parent,
			target_pos,
			BURGER_PICKUP_RADIUS,
			0.30,
			GroundTelegraph3D.Preset.HEAL,
			true
		)

		if burger.is_inside_tree():
			visual_holder.position = from_pos - target_pos
			var arc_tween := burger.create_tween()
			arc_tween.tween_property(visual_holder, "position", Vector3(0.0, 0.08, 0.0), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		_active_burgers[burger_id] = burger
		return burger

	static func spawn_server_burger(from_pos: Vector3, target_pos: Vector3, heal_amount: float, spawn_parent: Node, owner_tank: Tank = null) -> Area3D:
		var burger_id: int = _next_burger_id
		_next_burger_id += 1
		var burger := create_burger_node(burger_id, from_pos, target_pos, heal_amount, spawn_parent)
		if not burger:
			return null

		if owner_tank and owner_tank.net_sync and owner_tank.multiplayer and owner_tank.multiplayer.has_multiplayer_peer() and owner_tank.multiplayer.is_server():
			owner_tank.net_sync.s2c_spawn_burger_pickup.rpc(burger_id, from_pos, target_pos, heal_amount)

		var try_consume := func(body: Node3D) -> void:
			if not is_instance_valid(burger) or burger.get_meta("consumed", false):
				return
			if body is Tank and body.is_active and body.health and body.health.is_alive():
				burger.set_meta("consumed", true)
				body.health.heal(heal_amount)
				remove_burger_by_id(burger_id)
				if is_instance_valid(owner_tank) and owner_tank.net_sync and owner_tank.multiplayer and owner_tank.multiplayer.has_multiplayer_peer() and owner_tank.multiplayer.is_server():
					owner_tank.net_sync.s2c_remove_burger_pickup.rpc(burger_id)

		burger.body_entered.connect(try_consume)

		var tree := burger.get_tree()
		if tree:
			for node in tree.get_nodes_in_group("tanks"):
				if node is Tank and node.is_active and node.health and node.health.is_alive():
					if node.global_position.distance_to(target_pos) <= BURGER_PICKUP_RADIUS:
						try_consume.call(node)
						break

			tree.create_timer(BURGER_LIFETIME).timeout.connect(func() -> void:
				if is_instance_valid(burger) and not burger.get_meta("consumed", false):
					burger.set_meta("consumed", true)
					remove_burger_by_id(burger_id)
					if is_instance_valid(owner_tank) and owner_tank.net_sync and owner_tank.multiplayer and owner_tank.multiplayer.has_multiplayer_peer() and owner_tank.multiplayer.is_server():
						owner_tank.net_sync.s2c_remove_burger_pickup.rpc(burger_id)
			)

		return burger

	static func spawn_client_terminal(terminal_id: int, origin: Vector3, yaw: float, stacks: int, context_node: Node) -> TerminalNode:
		var spawn_parent := JumpMineEffect._resolve_spawn_parent(context_node)
		return create_terminal_node(terminal_id, origin, yaw, stacks, spawn_parent, null, true)

	static func spawn_client_burger(burger_id: int, from_pos: Vector3, target_pos: Vector3, heal_amount: float, context_node: Node) -> Area3D:
		var spawn_parent := JumpMineEffect._resolve_spawn_parent(context_node)
		return create_burger_node(burger_id, from_pos, target_pos, heal_amount, spawn_parent)

	static func remove_terminal_by_id(terminal_id: int) -> void:
		var term: Node3D = _active_terminals.get(terminal_id, null) as Node3D
		_active_terminals.erase(terminal_id)
		if is_instance_valid(term):
			term.remove_from_group("burger_terminals")
			term.queue_free()

	static func remove_burger_by_id(burger_id: int) -> void:
		var burger: Area3D = _active_burgers.get(burger_id, null) as Area3D
		_active_burgers.erase(burger_id)
		if is_instance_valid(burger):
			burger.remove_from_group("burger_pickups")
			burger.queue_free()

	static func clear_all(tree: SceneTree) -> void:
		_active_terminals.clear()
		_active_burgers.clear()
		if not tree:
			return
		for node in tree.get_nodes_in_group("burger_terminals"):
			if is_instance_valid(node):
				node.remove_from_group("burger_terminals")
				node.queue_free()
		for node in tree.get_nodes_in_group("burger_pickups"):
			if is_instance_valid(node):
				node.remove_from_group("burger_pickups")
				node.queue_free()
		GroundTelegraph3D.clear_all(tree)

	func on_block_started(_duration: float, stacks: int) -> void:
		if not tank or not is_instance_valid(tank):
			return
		if tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and not tank.multiplayer.is_server():
			return

		var spawn_parent := JumpMineEffect._resolve_spawn_parent(tank)
		if not spawn_parent:
			return

		var effective_stacks: int = maxi(1, stacks)
		var terminal_id: int = _next_terminal_id
		_next_terminal_id += 1

		var origin: Vector3 = tank.global_position
		if tank.get_world_3d():
			var space := tank.get_world_3d().direct_space_state
			var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.8, origin + Vector3.DOWN * 12.0, 1)
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				origin.y = hit.position.y

		var yaw: float = tank.rotation.y
		create_terminal_node(terminal_id, origin, yaw, effective_stacks, spawn_parent, tank, false)

		if tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server():
			tank.net_sync.s2c_spawn_burger_terminal.rpc(terminal_id, origin, yaw, effective_stacks)


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
						node.health.take_damage(slam_damage, tank, tank.global_position)

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
		if mine and context_node is Tank:
			mine.set_meta("owner_peer_id", (context_node as Tank).peer_id)
			mine.set_meta("owner_team_id", (context_node as Tank).team_id)
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
		if mine:
			mine.set_meta("owner_peer_id", tank.peer_id)
			mine.set_meta("owner_team_id", tank.team_id)

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
					var det_origin := mine.global_position if is_instance_valid(mine) else origin
					body.health.take_damage(mine_damage, valid_creator, det_origin)
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

class FeatherFallEffect extends CardEffect:
	## Бонус высоты прыжка (+25% за стак) задаётся через stat_modifiers карты.
	## При движении вниз (velocity.y <= 0) снижает гравитацию и ограничивает максимальную скорость падения.
	const FALL_GRAVITY_MULT_PER_STACK: float = 0.38
	const MIN_FALL_GRAVITY_MULT: float = 0.08
	const BASE_MAX_FALL_SPEED: float = 3.2
	const FALL_SPEED_DECAY_PER_STACK: float = 0.68
	const MIN_MAX_FALL_SPEED: float = 0.8

	static func get_fall_gravity_multiplier(stacks: int) -> float:
		if stacks <= 0:
			return 1.0
		return maxf(MIN_FALL_GRAVITY_MULT, pow(FALL_GRAVITY_MULT_PER_STACK, float(stacks)))

	static func get_max_fall_speed(stacks: int) -> float:
		if stacks <= 0:
			return 999.0
		return maxf(MIN_MAX_FALL_SPEED, BASE_MAX_FALL_SPEED * pow(FALL_SPEED_DECAY_PER_STACK, float(stacks - 1)))

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
			var applied := target.health.take_damage(ram_damage, tank, tank.global_position)
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

class FireflyEffect extends CardEffect:
	## Едущий танк оставляет огненный след шириной с танк и длиной не более двух танков.
	## Сегмент горит LIFETIME секунд (не зависит от стаков); длина следа растёт со стаками; враг, вставший в огонь, загорается (DoT как у Poison).
	## Логика и урон — только на сервере, клиенты получают визуал сегментов по RPC.
	const TRAIL_WIDTH: float = 2.0
	const TANK_LENGTH: float = 3.3
	const MAX_TRAIL_TANKS: float = 2.0
	const EXTRA_TRAIL_TANKS_PER_STACK: float = 2.0
	const LIFETIME: float = 2.0
	const FADE_TIME: float = 0.3
	const SEGMENT_LENGTH: float = 0.75
	const TELEPORT_BREAK_DIST: float = 4.0
	const TARGET_RADIUS: float = 0.75
	const MAX_HEIGHT_DELTA: float = 1.6
	static var _next_segment_id: int = 1
	static var _trail_nodes: Dictionary = {}
	static var _flame_texture: Texture2D = null

	var _segments: Array[Dictionary] = []
	var _last_point: Vector3 = Vector3.INF

	class BurnDoTNode extends Node3D:
		const TICK_INTERVAL: float = 0.5
		const TOTAL_TICKS: int = 6
		const DAMAGE_PER_STACK: float = 4.0

		var stacks: int = 1
		var ticks_left: int = TOTAL_TICKS
		var attacker: Node = null
		var _tick_timer: float = 0.0
		var _light: OmniLight3D = null

		func _ready() -> void:
			_light = OmniLight3D.new()
			_light.name = "BurnLight"
			_light.position = Vector3(0.0, 0.8, 0.0)
			_light.light_color = Color(1.0, 0.45, 0.1)
			_light.omni_range = 2.6
			_light.light_energy = 1.8
			add_child(_light)

			var flames := CPUParticles3D.new()
			flames.name = "BurnFlames"
			flames.amount = 14
			flames.lifetime = 0.6
			flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			flames.emission_sphere_radius = 0.6
			flames.direction = Vector3.UP
			flames.spread = 15.0
			flames.gravity = Vector3(0.0, 2.5, 0.0)
			flames.initial_velocity_min = 0.5
			flames.initial_velocity_max = 1.4
			flames.scale_amount_min = 0.7
			flames.scale_amount_max = 1.3
			flames.position = Vector3(0.0, 0.6, 0.0)
			flames.mesh = FireflyEffect.create_flame_quad()
			flames.color_ramp = FireflyEffect.create_flame_gradient()
			add_child(flames)

		func setup_or_refresh(new_stacks: int, new_attacker: Node) -> void:
			stacks = maxi(stacks, maxi(1, new_stacks))
			ticks_left = TOTAL_TICKS
			if is_instance_valid(new_attacker):
				attacker = new_attacker

		func _physics_process(delta: float) -> void:
			var target := get_parent() as Tank
			if not is_instance_valid(target) or not target.is_active or not target.health or not target.health.is_alive():
				queue_free()
				return

			_tick_timer += delta
			if _light:
				_light.light_energy = 1.4 + 0.6 * sin(_tick_timer * PI * 5.0)

			while _tick_timer >= TICK_INTERVAL and ticks_left > 0:
				_tick_timer -= TICK_INTERVAL
				trigger_tick()

		func trigger_tick() -> void:
			var target := get_parent() as Tank
			if not is_instance_valid(target) or not target.is_active or not target.health:
				queue_free()
				return

			ticks_left -= 1
			var valid_attacker: Node = attacker if is_instance_valid(attacker) else null
			var dot_damage: float = DAMAGE_PER_STACK * float(maxi(1, stacks))
			var applied := target.health.take_damage(dot_damage, valid_attacker, Vector3.INF)
			if applied and valid_attacker is Tank and (valid_attacker as Tank).events:
				(valid_attacker as Tank).events.emit_damage_dealt(dot_damage, target)

			if ticks_left <= 0:
				queue_free()

	static func get_trail_width(scale_mult: float) -> float:
		return TRAIL_WIDTH * scale_mult

	## Максимальная длина следа: 2 длины танка на 1 стаке, +2 длины танка за каждый следующий стак.
	static func get_max_trail_length(scale_mult: float, stacks: int = 1) -> float:
		var tanks_long: float = MAX_TRAIL_TANKS + EXTRA_TRAIL_TANKS_PER_STACK * float(maxi(1, stacks) - 1)
		return TANK_LENGTH * tanks_long * scale_mult

	static func create_flame_gradient() -> Gradient:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		grad.colors = PackedColorArray([
			Color(1.0, 0.85, 0.25, 0.9),
			Color(1.0, 0.38, 0.05, 0.7),
			Color(0.4, 0.05, 0.0, 0.0)
		])
		return grad

	static func create_flame_quad() -> QuadMesh:
		if not _flame_texture:
			var soft := Gradient.new()
			soft.offsets = PackedFloat32Array([0.0, 1.0])
			soft.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
			var tex := GradientTexture2D.new()
			tex.gradient = soft
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(1.0, 0.5)
			tex.width = 64
			tex.height = 64
			_flame_texture = tex

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _flame_texture

		var quad := QuadMesh.new()
		quad.size = Vector2(0.6, 0.6)
		quad.material = mat
		return quad

	static func apply_burn(target: Tank, stacks: int, attacker: Node) -> void:
		if not is_instance_valid(target) or not target.is_active:
			return
		var existing := target.get_node_or_null("BurnEffect") as BurnDoTNode
		if existing and is_instance_valid(existing) and not existing.is_queued_for_deletion():
			existing.setup_or_refresh(stacks, attacker)
			return

		var burn_node := BurnDoTNode.new()
		burn_node.name = "BurnEffect"
		burn_node.setup_or_refresh(stacks, attacker)
		target.add_child(burn_node)

	static func remove_segment_by_id(seg_id: int) -> void:
		var node: Node3D = _trail_nodes.get(seg_id, null) as Node3D
		_trail_nodes.erase(seg_id)
		if is_instance_valid(node):
			node.remove_from_group("fire_trail_segments")
			node.queue_free()

	static func clear_all_trails(tree: SceneTree) -> void:
		_trail_nodes.clear()
		if not tree:
			return
		for node in tree.get_nodes_in_group("fire_trail_segments"):
			if is_instance_valid(node):
				node.remove_from_group("fire_trail_segments")
				node.queue_free()

	static func create_segment_node(seg_id: int, a: Vector3, b: Vector3, width: float, parent: Node) -> Node3D:
		if not parent:
			return null
		remove_segment_by_id(seg_id)

		var flat_dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var seg_len: float = maxf(0.1, flat_dir.length())

		var node := Node3D.new()
		node.name = "FireTrailSegment_%d" % seg_id
		node.set_meta("segment_id", seg_id)
		node.add_to_group("fire_trail_segments")
		parent.add_child(node)
		node.global_position = (a + b) * 0.5 + Vector3(0.0, 0.06, 0.0)
		if flat_dir.length_squared() > 0.0001:
			node.rotation.y = atan2(-flat_dir.x, -flat_dir.z)

		# Раскалённое пятно на земле
		var glow := MeshInstance3D.new()
		glow.name = "FireGlow"
		var box := BoxMesh.new()
		box.size = Vector3(width, 0.04, seg_len + 0.1)
		glow.mesh = box
		var glow_mat := StandardMaterial3D.new()
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow_mat.albedo_color = Color(1.0, 0.42, 0.08, 0.55)
		glow.material_override = glow_mat
		node.add_child(glow)

		# Язычки пламени
		var flames := CPUParticles3D.new()
		flames.name = "FireFlames"
		flames.amount = 10
		flames.lifetime = 0.7
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		flames.emission_box_extents = Vector3(width * 0.5, 0.02, seg_len * 0.5)
		flames.direction = Vector3.UP
		flames.spread = 12.0
		flames.gravity = Vector3(0.0, 2.5, 0.0)
		flames.initial_velocity_min = 0.6
		flames.initial_velocity_max = 1.6
		flames.scale_amount_min = 0.8
		flames.scale_amount_max = 1.4
		flames.mesh = create_flame_quad()
		flames.color_ramp = create_flame_gradient()
		node.add_child(flames)

		# Свет только на каждом третьем сегменте, чтобы не плодить OmniLight3D
		var light: OmniLight3D = null
		if seg_id % 3 == 0:
			light = OmniLight3D.new()
			light.name = "FireLight"
			light.position = Vector3(0.0, 0.6, 0.0)
			light.light_color = Color(1.0, 0.5, 0.12)
			light.omni_range = width * 1.8
			light.light_energy = 1.4
			node.add_child(light)

		# Самоуничтожение через LIFETIME (на клиентах без отдельного RPC)
		var tween := node.create_tween()
		tween.tween_interval(maxf(0.0, LIFETIME - FADE_TIME))
		tween.tween_callback(func() -> void:
			flames.emitting = false
		)
		tween.tween_property(glow_mat, "albedo_color:a", 0.0, FADE_TIME)
		if light:
			tween.parallel().tween_property(light, "light_energy", 0.0, FADE_TIME)
		tween.tween_callback(func() -> void:
			remove_segment_by_id(seg_id)
		)

		_trail_nodes[seg_id] = node
		return node

	static func spawn_client_segment(seg_id: int, a: Vector3, b: Vector3, width: float, context_node: Node) -> Node3D:
		var parent := JumpMineEffect._resolve_spawn_parent(context_node)
		return create_segment_node(seg_id, a, b, width, parent)

	static func _distance_to_segment_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
		var p2 := Vector2(p.x, p.z)
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var ab := b2 - a2
		var len_sq := ab.length_squared()
		if len_sq < 0.0001:
			return p2.distance_to(a2)
		var t := clampf((p2 - a2).dot(ab) / len_sq, 0.0, 1.0)
		return p2.distance_to(a2 + ab * t)

	func is_point_in_fire(point: Vector3, target_radius: float = TARGET_RADIUS) -> bool:
		for seg in _segments:
			var a: Vector3 = seg["a"]
			var b: Vector3 = seg["b"]
			if absf(point.y - a.y) > MAX_HEIGHT_DELTA:
				continue
			if _distance_to_segment_xz(point, a, b) <= float(seg["width"]) * 0.5 + target_radius:
				return true
		return false

	func get_segment_count() -> int:
		return _segments.size()

	func get_total_trail_length() -> float:
		var total: float = 0.0
		for seg in _segments:
			total += Vector2((seg["b"] as Vector3).x - (seg["a"] as Vector3).x, (seg["b"] as Vector3).z - (seg["a"] as Vector3).z).length()
		return total

	func _remove_segment_at(index: int, notify_clients: bool) -> void:
		var seg: Dictionary = _segments[index]
		_segments.remove_at(index)
		var seg_id: int = seg["id"]
		remove_segment_by_id(seg_id)
		if notify_clients and _is_network_server():
			tank.net_sync.s2c_remove_fire_segment.rpc(seg_id)

	func _is_network_server() -> bool:
		return tank and tank.net_sync and tank.multiplayer and tank.multiplayer.has_multiplayer_peer() and tank.multiplayer.is_server()

	func _age_segments(delta: float) -> void:
		var i := _segments.size() - 1
		while i >= 0:
			var seg: Dictionary = _segments[i]
			seg["age"] = float(seg["age"]) + delta
			var node: Node3D = _trail_nodes.get(int(seg["id"]), null) as Node3D
			# Сегмент умирает по таймеру либо если его визуал уничтожен (сброс раунда)
			if float(seg["age"]) >= LIFETIME or not is_instance_valid(node):
				_remove_segment_at(i, false)
			i -= 1

	func _drop_trail(scale_mult: float, stacks: int) -> void:
		var forward := -tank.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			return
		forward = forward.normalized()
		var rear := tank.global_position - forward * (TANK_LENGTH * 0.5 * scale_mult)

		if not _last_point.is_finite() or not tank.is_on_floor():
			_last_point = rear
			return

		var flat_dist := Vector2(rear.x - _last_point.x, rear.z - _last_point.z).length()
		if flat_dist > TELEPORT_BREAK_DIST * scale_mult:
			_last_point = rear # телепорт / респавн — след обрывается
			return
		if flat_dist < SEGMENT_LENGTH * scale_mult:
			return

		var a := Vector3(_last_point.x, tank.global_position.y, _last_point.z)
		var b := Vector3(rear.x, tank.global_position.y, rear.z)
		if add_segment(a, b, scale_mult, stacks):
			_last_point = rear

	## Создаёт сегмент следа между точками a и b, рассылает его клиентам
	## и обрезает самые старые сегменты, если след длиннее двух танков.
	func add_segment(a: Vector3, b: Vector3, scale_mult: float = 1.0, stacks: int = 1) -> bool:
		var parent := JumpMineEffect._resolve_spawn_parent(tank)
		if not parent:
			return false

		var width := get_trail_width(scale_mult)
		var seg_id := _next_segment_id
		_next_segment_id += 1
		if not create_segment_node(seg_id, a, b, width, parent):
			return false

		_segments.append({"id": seg_id, "a": a, "b": b, "width": width, "age": 0.0})

		if _is_network_server():
			tank.net_sync.s2c_spawn_fire_segment.rpc(seg_id, a, b, width)

		# Ограничение общей длины следа: самые старые сегменты гаснут первыми
		var max_len := get_max_trail_length(scale_mult, stacks)
		while _segments.size() > 1 and get_total_trail_length() > max_len:
			_remove_segment_at(0, true)
		return true

	func _ignite_enemies(stacks: int) -> void:
		if _segments.is_empty():
			return
		var tree := tank.get_tree()
		if not tree:
			return
		for node in tree.get_nodes_in_group("tanks"):
			var target := node as Tank
			if not target or target == tank or not target.is_active:
				continue
			if not target.health or not target.health.is_alive():
				continue
			if Game and Game.rules and Game.rules.is_team_mode and not Game.rules.friendly_fire:
				if target.team_id == tank.team_id:
					continue
			var target_scale: float = target.stats.tank_scale if target.stats else 1.0
			if is_point_in_fire(target.global_position, TARGET_RADIUS * target_scale):
				apply_burn(target, stacks, tank)

	func on_physics_process(delta: float, stacks: int) -> void:
		if not tank or not is_instance_valid(tank):
			return
		var scale_mult: float = tank.stats.tank_scale if tank.stats else 1.0
		_age_segments(delta)
		if tank.is_active:
			_drop_trail(scale_mult, stacks)
		_ignite_enemies(stacks)

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

	# --- SHOT CARDS (22) ---
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

	_register("spread", "Разброс", "Снаряды летят с разбросом (±8° за стак), но урон +70%. Стаки увеличивают и разброс, и урон.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.70}, SpreadEffect)
	_register("air_vortex", "Air Vortex", "При попадании создает воронку (радиус 3м, +1м за стак) на 3с, засасывающую все танки и ящики. +20% к урону, +30% пауза между выстрелами, +10% скорость перезарядки.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.20, "fire_interval_mult": 1.30, "reload_time_mult": 0.90}, AirVortexEffect)
	_register("accuracy", "Accuracy", "+40% к урону, +50% к скорости полета снарядов, +70% к времени перезарядки, -40% к скорости движения.", CardDefinition.Category.SHOT, false, 99, {"damage_mult": 1.40, "proj_speed_mult": 1.50, "reload_time_mult": 1.70, "move_speed_mult": 0.60})
	_register("critical_hit", "Critical Hit", "20% шанс нанести 140% урона (+30% к крит-урону за стак, шанс не меняется). +20% к времени перезарядки.", CardDefinition.Category.SHOT, false, 99, {"reload_time_mult": 1.20}, CriticalHitEffect)

	# --- BLOCK CARDS (10) ---
	_register("quick_guard", "Quick Guard", "-25% кулдаун защитного блока.", CardDefinition.Category.BLOCK, false, 99, {"block_cooldown_mult": 0.75})
	_register("long_block", "Long Block", "+50% длительность окна щита, +15% кулдаун.", CardDefinition.Category.BLOCK, false, 99, {"block_duration_mult": 1.50, "block_cooldown_mult": 1.15})
	_register("blink", "Blink", "Телепортация на 5м по направлению прицела при активации щита.", CardDefinition.Category.BLOCK, false, 99, {}, BlinkEffect)
	_register("shockwave", "Shockwave", "Щит испускает ударную волну, отталкивающую врагов.", CardDefinition.Category.BLOCK, false, 99, {}, ShockwaveEffect)
	_register("reload_block", "Reload Block", "Успешный блок сокращает текущее время перезарядки на 1с.", CardDefinition.Category.BLOCK, false, 99, {}, ReloadBlockEffect)
	_register("ammo_shield", "Ammo Shield", "Успешный блок восстанавливает +1 снаряд в обойму.", CardDefinition.Category.BLOCK, false, 99, {}, AmmoShieldEffect)
	_register("counter_shot", "Counter Shot", "Успешный блок автоматически выпускает ответный снаряд.", CardDefinition.Category.BLOCK, false, 99, {}, CounterShotEffect)
	_register("reflect", "Reflect", "Заблокированный снаряд отражается обратно во врага со сменой владельца.", CardDefinition.Category.BLOCK, true, 1, {})
	_register("wallhack", "Wallhack", "При активации щита противники просвечиваются сквозь стены на 2с (+2с за стак). +40% кулдаун блока.", CardDefinition.Category.BLOCK, false, 99, {"block_cooldown_mult": 1.40}, WallhackEffect)
	_register("burger_terminal", "Burger Terminal", "При активации щита ставит терминал на 3с (+1с за стак). Раз в секунду терминал кидает бургер на +10 HP (+10 HP за стак). +40% кулдаун блока.", CardDefinition.Category.BLOCK, false, 99, {"block_cooldown_mult": 1.40}, BurgerTerminalEffect)

	# --- JUMP CARDS (6) ---
	_register("high_jump", "High Jump", "+40% высота прыжка танка.", CardDefinition.Category.JUMP, false, 99, {"jump_velocity_mult": 1.40})
	_register("ground_slam", "Ground Slam", "Приземление с высоты вызывает ударную волну на 18 урона в радиусе 4.5м.", CardDefinition.Category.JUMP, false, 99, {}, GroundSlamEffect)
	_register("jump_mine", "Jump Mine", "При прыжке на земле остается мина с таймером 8 секунд.", CardDefinition.Category.JUMP, false, 99, {}, JumpMineEffect)
	_register("death_from_above", "Death From Above", "+40% урона снарядам, выпущенным в прыжке.", CardDefinition.Category.JUMP, false, 99, {}, DeathFromAboveEffect)
	_register("double_jump", "Double Jump", "Разрешает второй прыжок прямо в воздухе.", CardDefinition.Category.JUMP, true, 1, {})
	_register("feather_fall", "Feather Fall", "+25% к высоте прыжка. При падении танк плавно планирует вниз; каждый стак усиливает замедление падения и высоту прыжка.", CardDefinition.Category.JUMP, false, 99, {"jump_velocity_mult": 1.25}, FeatherFallEffect)

	# --- GENERAL CARDS (13) ---
	_register("tankier", "Tankier", "+40 максимального здоровья танка.", CardDefinition.Category.GENERAL, false, 99, {"hp_flat": 40.0})
	_register("huge", "Huge", "+50% максимального здоровья танка.", CardDefinition.Category.GENERAL, false, 99, {"hp_mult": 1.50})
	_register("lightweight", "Lightweight", "+30% к скорости танка, снижена масса.", CardDefinition.Category.GENERAL, false, 99, {"move_speed_mult": 1.30, "knockback_resistance_mult": 0.7})
	_register("heavyweight", "Heavyweight", "+75% устойчивость к отталкиванию, +30% максимального HP, -12% скорости.", CardDefinition.Category.GENERAL, false, 99, {"knockback_resistance_mult": 1.75, "hp_mult": 1.30, "move_speed_mult": 0.88})
	_register("adrenaline", "Adrenaline", "+50% к скорости перемещения, когда HP падает ниже 35%.", CardDefinition.Category.GENERAL, false, 99, {}, AdrenalineEffect)
	_register("glass_cannon", "Glass Cannon", "-40% максимального HP, +75% урона.", CardDefinition.Category.GENERAL, false, 99, {"hp_mult": 0.60, "damage_mult": 1.75})
	_register("regeneration", "Regeneration", "Восстановление 6 HP/сек после 3 секунд без получения урона.", CardDefinition.Category.GENERAL, false, 99, {}, RegenerationEffect)
	_register("vampire", "Vampire", "Лечение на 25% от нанесенного по врагам урона.", CardDefinition.Category.GENERAL, false, 99, {}, VampireEffect)
	_register("road_rage", "Road Rage", "Таран вражеского танка на скорости наносит урон.", CardDefinition.Category.GENERAL, false, 99, {}, RoadRageEffect)
	_register("tiny_tank", "Tiny Tank", "Танк меньше (-30%) и быстрее (+25%), но теряет 25 HP.", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 0.70, "move_speed_mult": 1.25, "hp_flat": -25.0})
	_register("big_tank", "Big Tank", "Танк крупнее (+40%) и прочнее (+60 HP), но медленнее (-15%).", CardDefinition.Category.GENERAL, false, 99, {"scale_mult": 1.40, "hp_flat": 60.0, "move_speed_mult": 0.85})
	_register("firefly", "Firefly", "Едущий танк оставляет огненный след (шириной с танк, до 2 танков в длину, горит 2 сек). Враг в огне горит и получает урон как от яда. Каждый стак усиливает урон горения и удлиняет след на 2 танка.", CardDefinition.Category.GENERAL, false, 99, {}, FireflyEffect)
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
