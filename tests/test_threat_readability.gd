extends Node

## Комплексный автотест читаемости угроз в 3D (TANKUS):
## 1. ThreatIndicatorHUD (азимут, живой доворот камеры, дуги урона от рикошета/взрыва, подавление DoT,
##    проактивные шевроны снарядов, 1-рикошетный расчёт от стены, кластеризация дроби, Ground Slam и JumpMine).
## 2. GroundTelegraph3D & TankAirTelegraph (Decal cull_mask=1, прыжковый маркер, радиус Ground Slam по стакам,
##    разделение враг/союзник, BurgerTerminal маркер приземления и зоны подбора).
## 3. TankAppearance Silhouettes (сглаженные нормали без разрывов на рёбрах, Fresnel Rim + Outline,
##    профили контраста SELF vs ENEMY, бесконфликтная работа с Hit Flash и Wallhack).

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures += 1
		push_error("FAILED: " + label)

func _run() -> void:
	print("\n=== [TEST] Starting 3D Threat Readability Suite ===")

	var root_3d := Node3D.new()
	root_3d.name = "TestArena3D"
	add_child(root_3d)

	# Статический пол мира на слое 1 (World)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(120.0, 1.0, 120.0)
	floor_col.shape = floor_box
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	root_3d.add_child(floor_body)

	# Боковая стена для проверки 1-рикошетного предупреждения (x = +6.0, нормаль -X)
	var side_wall := StaticBody3D.new()
	side_wall.name = "SideWall"
	side_wall.collision_layer = 1
	side_wall.collision_mask = 0
	var wall_col := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.0, 6.0, 30.0)
	wall_col.shape = wall_box
	side_wall.position = Vector3(6.5, 2.5, 0.0) # левая грань стены ровно на x = +6.0
	side_wall.add_child(wall_col)
	root_3d.add_child(side_wall)

	# Спавним локальный и вражеский танки
	var tank_scene := load("res://tank/tank.tscn") as PackedScene
	var player_tank := tank_scene.instantiate() as Tank
	player_tank.name = "Tank_1"
	player_tank.peer_id = 1
	player_tank.team_id = 0
	player_tank.is_frozen = true

	var enemy_tank := tank_scene.instantiate() as Tank
	enemy_tank.name = "Tank_2"
	enemy_tank.peer_id = 2
	enemy_tank.team_id = 1
	enemy_tank.is_frozen = true

	root_3d.add_child(player_tank)
	root_3d.add_child(enemy_tank)
	player_tank.global_position = Vector3(0.0, 0.0, 0.0)
	enemy_tank.global_position = Vector3(0.0, 0.0, -14.0)
	player_tank.set_team_color(Color(0.18, 0.55, 0.95))
	enemy_tank.set_team_color(Color(0.95, 0.25, 0.25))

	# Камера TPS позади игрока, смотрит вдоль -Z
	var cam := Camera3D.new()
	cam.name = "TestCamera"
	root_3d.add_child(cam)
	cam.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 6.0))
	cam.make_current()

	# Боевой HUD
	var hud_scene := load("res://ui/hud.tscn") as PackedScene
	var hud := hud_scene.instantiate() as HUD
	add_child(hud)
	hud.bind_to_tank(player_tank)

	# Даём физическому серверу зарегистрировать коллайдеры пола и стены
	await get_tree().physics_frame
	await get_tree().physics_frame

	# -------------------------------------------------------------------------
	# ЧАСТЬ 1: Математика азимута, дуги урона, подавление DoT и шевроны угроз
	# -------------------------------------------------------------------------
	var viewer_pt := Vector3(0.0, 0.55, 0.0)
	var basis_fwd := Basis.IDENTITY
	var az_front := ThreatIndicatorHUD.compute_azimuth_angle(viewer_pt, basis_fwd, Vector3(0.0, 0.55, -10.0))
	var az_right := ThreatIndicatorHUD.compute_azimuth_angle(viewer_pt, basis_fwd, Vector3(10.0, 0.55, 0.0))
	var az_left := ThreatIndicatorHUD.compute_azimuth_angle(viewer_pt, basis_fwd, Vector3(-10.0, 0.55, 0.0))
	var az_back := ThreatIndicatorHUD.compute_azimuth_angle(viewer_pt, basis_fwd, Vector3(0.0, 0.55, 10.0))
	_check(
		absf(az_front) < 0.01 and is_equal_approx(az_right, PI * 0.5) and is_equal_approx(az_left, -PI * 0.5) and absf(absf(az_back) - PI) < 0.01,
		"Azimuth math maps ahead=0, right=+PI/2, left=-PI/2, behind=PI"
	)

	var basis_turned_right := Basis(Vector3.UP, -PI * 0.5) # поворот камеры на +X
	var az_reprojected := ThreatIndicatorHUD.compute_azimuth_angle(viewer_pt, basis_turned_right, Vector3(10.0, 0.55, 0.0))
	_check(absf(az_reprojected) < 0.01, "World-anchored threat origin re-projects to 0 rad when camera turns toward it")

	# Снаряд врага спереди (-Z), но прилетевший РИКОШЕТОМ в корму (+Z): дуга обязана указать НАЗАД (+Z)!
	var proj_scene := load("res://projectile/projectile.tscn") as PackedScene
	var rico_proj := proj_scene.instantiate() as Projectile
	root_3d.add_child(rico_proj)
	# Снаряд летит со спины (z = +5 -> 0, direction = (0, 0, -1)), хотя стрелок стоит спереди (z = -14)
	rico_proj.setup(enemy_tank, Vector3(0.0, 0.6, 4.5), Vector3(0.0, 0.0, -1.0))

	var dmg_capture := {"origin": Vector3.ZERO, "has_origin": false}
	var on_dmg := func(_amt: float, _att: Node, has_orig: bool, orig: Vector3) -> void:
		dmg_capture["has_origin"] = has_orig
		dmg_capture["origin"] = orig
	player_tank.health.damage_taken_from.connect(on_dmg)

	rico_proj._handle_direct_hit(player_tank, Vector3(0.0, 0.6, 1.4), Vector3(0.0, 0.0, 1.0))
	var cap_orig := dmg_capture["origin"] as Vector3
	_check(
		bool(dmg_capture["has_origin"]) and cap_orig.z > 2.5 and hud.threat_indicator.get_damage_arc_count() == 1,
		"Ricochet hit in rear armor points Damage Hit Arc behind player (+Z), not toward front shooter (-Z)"
	)
	rico_proj.free()

	# Проверка подавления ненаправленного периодического урона (Poison DoT и Firefly Burn DoT)
	hud.threat_indicator.clear_indicators()
	player_tank.health.reset()
	dmg_capture["has_origin"] = true

	var poison_dot := Projectile.PoisonDoTNode.new()
	poison_dot.name = "PoisonEffect"
	poison_dot.stacks = 1
	poison_dot.attacker = enemy_tank
	player_tank.add_child(poison_dot)
	poison_dot._physics_process(0.5)
	_check(
		not bool(dmg_capture["has_origin"]) and hud.threat_indicator.get_damage_arc_count() == 0,
		"Poison DoT ticks suppress directional Damage Hit Arc (no fake wallhack compass)"
	)
	poison_dot.free()

	dmg_capture["has_origin"] = true
	var burn_dot := CardDatabase.FireflyEffect.BurnDoTNode.new()
	burn_dot.name = "BurnEffect"
	burn_dot.stacks = 1
	burn_dot.attacker = enemy_tank
	player_tank.add_child(burn_dot)
	burn_dot._physics_process(0.5)
	_check(
		not bool(dmg_capture["has_origin"]) and hud.threat_indicator.get_damage_arc_count() == 0,
		"Firefly Burn DoT ticks suppress directional Damage Hit Arc"
	)
	burn_dot.free()
	player_tank.health.damage_taken_from.disconnect(on_dmg)
	player_tank.health.reset()

	# Проверка фильтрации своих и союзных снарядов
	var own_proj := proj_scene.instantiate() as Projectile
	root_3d.add_child(own_proj)
	own_proj.setup(player_tank, Vector3(0.0, 0.6, 7.0), Vector3(0.0, 0.0, -1.0))
	hud.threat_indicator._process(0.016)
	_check(hud.threat_indicator.get_active_threats().is_empty(), "Own projectiles never trigger incoming threat chevrons")
	own_proj.free()

	var prev_team_mode := Game.rules.is_team_mode
	var prev_ff := Game.rules.friendly_fire
	Game.rules.is_team_mode = true
	Game.rules.friendly_fire = false
	var ally_proj := proj_scene.instantiate() as Projectile
	root_3d.add_child(ally_proj)
	ally_proj.shooter_peer_id = 3
	ally_proj.team_id = 0 # та же команда, что у player_tank
	ally_proj.global_position = Vector3(0.0, 0.6, 7.0)
	ally_proj.velocity = Vector3(0.0, 0.0, -24.0)
	hud.threat_indicator._process(0.016)
	_check(hud.threat_indicator.get_active_threats().is_empty(), "Friendly-team projectiles are ignored when friendly_fire is off")
	ally_proj.free()
	Game.rules.is_team_mode = prev_team_mode
	Game.rules.friendly_fire = prev_ff

	# Вражеский снаряд в спину на дистанции тайминга блока (ETA ~0.31s <= 0.44s) -> срочный шеврон!
	var back_proj := proj_scene.instantiate() as Projectile
	root_3d.add_child(back_proj)
	back_proj.setup(enemy_tank, Vector3(0.0, 0.6, 7.5), Vector3(0.0, 0.0, -1.0))
	hud.threat_indicator._process(0.016)
	var threats := hud.threat_indicator.get_active_threats()
	_check(
		threats.size() == 1 and bool(threats[0]["urgent"]) and absf(absf(float(threats[0]["angle"])) - PI) < 0.05,
		"Rear enemy projectile with ETA <= 0.44s spawns an URGENT rear threat chevron for [E] Block"
	)

	# 3 дополнительные дробинки Shotgun с того же направления сливаются в 1 кластер без мусора
	var extra_pellets: Array[Projectile] = []
	for deg_off in [-7.0, 4.0, 9.0]:
		var p := proj_scene.instantiate() as Projectile
		root_3d.add_child(p)
		var dir := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(deg_off))
		p.setup(enemy_tank, Vector3(0.0, 0.6, 8.0), dir)
		extra_pellets.append(p)
	hud.threat_indicator._process(0.016)
	_check(
		hud.threat_indicator.get_active_threats().size() == 1,
		"Shotgun pellet fan from the same flank merges into a single clean threat chevron"
	)
	back_proj.free()
	for p in extra_pellets:
		p.free()

	# 1-рикошетный расчёт от боковой стены x = +6.0
	var space := root_3d.get_world_3d().direct_space_state
	var bank_pos := Vector3(2.0, 0.55, 4.0)
	var bank_vel := Vector3(20.0, 0.0, -10.0) # бьёт в стену (6.0, 0.55, 2.0) и отскакивает (-20, 0, -10) ровно в (0, 0.55, -1.0)!
	var direct_only := ThreatIndicatorHUD.evaluate_projectile_threat(bank_pos, bank_vel, viewer_pt, 3.8, 1.05)
	var with_bounce := ThreatIndicatorHUD.evaluate_projectile_threat_with_bounce(bank_pos, bank_vel, 1, viewer_pt, 3.8, 1.05, space)
	_check(
		not bool(direct_only.get("is_threat", false)) and bool(with_bounce.get("is_threat", false)) and is_equal_approx((with_bounce["threat_origin"] as Vector3).x, 6.0),
		"1-bounce wall ricochet lookahead detects bank shot and anchors chevron to the rebound wall"
	)

	# Близкая вражеская JumpMine за спиной вызывает предупреждающий шеврон MINE
	var test_mine := Area3D.new()
	test_mine.add_to_group("jump_mines")
	test_mine.set_meta("owner_peer_id", 2)
	test_mine.set_meta("owner_team_id", 1)
	root_3d.add_child(test_mine)
	test_mine.global_position = Vector3(0.0, 0.1, 2.3)
	hud.threat_indicator._process(0.016)
	var mine_threats := hud.threat_indicator.get_active_threats()
	_check(
		mine_threats.size() == 1 and int(mine_threats[0]["kind"]) == ThreatIndicatorHUD.ThreatKind.MINE and bool(mine_threats[0]["urgent"]),
		"Close enemy JumpMine in rear blind spot triggers urgent MINE threat chevron"
	)
	test_mine.free()

	# -------------------------------------------------------------------------
	# ЧАСТЬ 2: GroundTelegraph3D, TankAirTelegraph и BurgerTerminal
	# -------------------------------------------------------------------------
	var timed_tel := GroundTelegraph3D.spawn_timed(root_3d, Vector3(4.0, 3.0, -4.0), 3.5, 0.4, GroundTelegraph3D.Preset.DANGER, true)
	_check(
		timed_tel != null and timed_tel.get_outer_decal().cull_mask == 1 and timed_tel.get_fill_decal().cull_mask == 1 and is_equal_approx(timed_tel.global_position.y, 0.0),
		"GroundTelegraph3D snaps to World floor and sets Decal cull_mask=1 (never paints Layer 2 tanks)"
	)
	var initial_fill_x := timed_tel.get_fill_decal().size.x
	timed_tel._process(0.25)
	_check(
		timed_tel.get_fill_decal().size.x > initial_fill_x,
		"GroundTelegraph3D inner timing ring expands smoothly toward outer impact perimeter"
	)
	GroundTelegraph3D.clear_all(get_tree())
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("ground_telegraphs").is_empty(), "GroundTelegraph3D.clear_all removes active timed telegraphs")

	# Проверка TankAirTelegraph на вражеском и своём танке
	enemy_tank.global_position = Vector3(0.0, 0.0, -14.0)
	enemy_tank.air_telegraph.evaluate_state(0.016)
	_check(not enemy_tank.air_telegraph.get_telegraph().visible, "Grounded tank hides air landing telegraph")

	# Обычный прыжок без Ground Slam
	enemy_tank.global_position = Vector3(0.0, 3.2, -14.0)
	enemy_tank.air_telegraph.evaluate_state(0.016)
	var enemy_tel := enemy_tank.air_telegraph.get_telegraph()
	_check(
		enemy_tel.visible and enemy_tel.preset == GroundTelegraph3D.Preset.NEUTRAL_DROP and is_equal_approx(enemy_tel.radius, 0.95),
		"Airborne tank without Ground Slam projects compact NEUTRAL_DROP ground ring"
	)

	# Добавляем 1 и 2 стака Ground Slam врагу и переносим его за спину игрока для проверки связки с HUD
	var slam_card := CardDatabase.get_card("ground_slam")
	enemy_tank.build.add_card(slam_card)
	enemy_tank.global_position = Vector3(0.0, 4.0, 3.2) # за спиной игрока в радиусе поражения 4.5м!
	enemy_tank.air_telegraph.evaluate_state(0.016)
	hud.threat_indicator._process(0.016)
	var slam_threats := hud.threat_indicator.get_active_threats()
	_check(
		enemy_tel.visible and enemy_tel.preset == GroundTelegraph3D.Preset.DANGER and is_equal_approx(enemy_tel.radius, 4.5) and is_equal_approx(enemy_tel.get_outer_decal().size.x, 9.0),
		"1-stack enemy Ground Slam projects DANGER GroundTelegraph3D with exact 4.5m AoE radius"
	)
	_check(
		slam_threats.size() == 1 and int(slam_threats[0]["kind"]) == ThreatIndicatorHUD.ThreatKind.GROUND_SLAM,
		"Airborne enemy Ground Slam behind player simultaneously triggers HUD GROUND_SLAM chevron"
	)

	enemy_tank.build.add_card(slam_card) # 2 стака -> 9.0м
	enemy_tank.air_telegraph.evaluate_state(0.016)
	_check(
		is_equal_approx(enemy_tel.radius, 9.0) and is_equal_approx(enemy_tel.get_outer_decal().size.x, 18.0),
		"2-stack Ground Slam scales GroundTelegraph3D radius to 9.0m"
	)

	# Свой танк с Ground Slam рисует тактический ALLY_SLAM, а не вражеский красный DANGER
	player_tank.build.add_card(slam_card)
	player_tank.global_position = Vector3(0.0, 3.5, 0.0)
	player_tank.air_telegraph.evaluate_state(0.016)
	_check(
		player_tank.air_telegraph.get_telegraph().visible and player_tank.air_telegraph.get_telegraph().preset == GroundTelegraph3D.Preset.ALLY_SLAM,
		"Local/ally Ground Slam uses tactical ALLY_SLAM telegraph preset distinct from enemy DANGER"
	)

	# Возвращаем танки на пол
	player_tank.build.clear_build()
	enemy_tank.build.clear_build()
	player_tank.global_position = Vector3(0.0, 0.0, 0.0)
	enemy_tank.global_position = Vector3(0.0, 0.0, -14.0)
	player_tank.air_telegraph.evaluate_state(0.016)
	enemy_tank.air_telegraph.evaluate_state(0.016)
	_check(
		not enemy_tank.air_telegraph.get_telegraph().visible and not enemy_tank.air_telegraph.is_slam_airborne(),
		"Returning tank to ground automatically hides Ground Slam telegraph"
	)

	# Проверка BurgerTerminal: навесной выброс бургера спавнит HEAL-телеграф + напольную декаль зоны подбора
	var burger_card := CardDatabase.get_card("burger_terminal")
	player_tank.build.add_card(burger_card)
	var bt_eff := player_tank.build.active_effects.get("burger_terminal", null) as CardDatabase.BurgerTerminalEffect
	bt_eff.on_block_started(0.35, 1)
	var terminals := get_tree().get_nodes_in_group("burger_terminals")
	if not terminals.is_empty():
		(terminals[0] as Node)._physics_process(1.05)
	var burgers := get_tree().get_nodes_in_group("burger_pickups")
	var burger_telegraphs := get_tree().get_nodes_in_group("ground_telegraphs")
	var zone_decal: Decal = burgers[0].get_node_or_null("BurgerZoneDecal") as Decal if not burgers.is_empty() else null
	_check(
		burgers.size() == 1 and burger_telegraphs.size() == 1 and zone_decal != null and zone_decal.cull_mask == 1,
		"BurgerTerminal spawns arcing HEAL landing telegraph and persistent Layer-1 pickup Decal"
	)
	CardDatabase.BurgerTerminalEffect.clear_all(get_tree())
	player_tank.build.clear_build()
	await get_tree().process_frame

	# -------------------------------------------------------------------------
	# ЧАСТЬ 3: Контрастные 3D-силуэты (TankAppearance), Hit Flash и Wallhack
	# -------------------------------------------------------------------------
	var p_hull := player_tank.chassis_mesh
	var e_hull := enemy_tank.chassis_mesh
	var e_gun := enemy_tank.turret.barrel_mount.get_node("BarrelMesh") as MeshInstance3D

	var hull_arrays := (e_hull.mesh as ArrayMesh).surface_get_arrays(0)
	var hull_colors: PackedColorArray = hull_arrays[Mesh.ARRAY_COLOR]
	_check(
		not hull_colors.is_empty() and absf(hull_colors[0].a - 0.25) < 0.02,
		"Tank silhouette meshes bake position-welded smooth normals into vertex COLOR (alpha~0.25)"
	)

	var e_rim := e_hull.material_overlay as ShaderMaterial
	var e_outline := e_rim.next_pass as ShaderMaterial if e_rim else null
	_check(
		e_rim != null and e_outline != null and e_gun.material_overlay == e_rim,
		"Hull, turret, and barrel receive Fresnel Rim + Inverted-Hull Outline material_overlay chain"
	)
	_check(
		enemy_tank.shield_mesh.material_overlay == null and enemy_tank.left_track.material_overlay == null and enemy_tank.right_track.material_overlay == null,
		"ShieldMesh and animated tracks are cleanly excluded from hull outline extrusion"
	)

	# Обновляем профиль контраста относительно зрителя (player_tank = SELF, enemy_tank = ENEMY)
	player_tank.set_team_color(Color(0.18, 0.55, 0.95))
	enemy_tank.set_team_color(Color(0.95, 0.25, 0.25))
	var p_rim := p_hull.material_overlay as ShaderMaterial
	e_rim = e_hull.material_overlay as ShaderMaterial
	var self_strength := float(p_rim.get_shader_parameter("rim_strength"))
	var enemy_strength := float(e_rim.get_shader_parameter("rim_strength"))
	_check(
		enemy_strength > self_strength + 0.4,
		"Enemy tank receives stronger Fresnel rim contrast (%.2f) than local player's own tank (%.2f)" % [enemy_strength, self_strength]
	)

	# Проверка совместной работы с Hit Flash и Wallhack без потери контура
	enemy_tank.health._play_hit_flash()
	_check(
		e_hull.material_override != null and e_hull.material_overlay == e_rim,
		"Hit Flash uses material_override while keeping silhouette material_overlay intact"
	)
	await enemy_tank.health._hit_flash_tween.finished
	_check(
		e_hull.material_override == null and e_hull.material_overlay == e_rim,
		"Finishing Hit Flash restores PBR armor materials and keeps silhouette overlay"
	)

	var reveal_node := CardDatabase.WallhackEffect.apply_reveal_to_target(enemy_tank, 5.0)
	var wh_mat := e_hull.material_overlay as StandardMaterial3D
	_check(
		wh_mat != null and wh_mat.no_depth_test == true,
		"Wallhack temporarily promotes no_depth_test X-Ray overlay onto enemy tank"
	)
	if reveal_node and is_instance_valid(reveal_node):
		reveal_node.free()
	_check(
		e_hull.material_overlay == e_rim and (e_hull.material_overlay as ShaderMaterial).next_pass != null,
		"Clearing Wallhack cleanly restores Fresnel Rim + Outline silhouette overlay"
	)

	# Чистая выгрузка тестовой сцены
	hud.free()
	root_3d.free()
	await get_tree().process_frame

	print("=== [TEST] 3D Threat Readability checks finished: %d failed ===\n" % failures)
	get_tree().quit(1 if failures > 0 else 0)
