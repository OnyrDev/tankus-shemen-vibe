extends Node3D

## Регрессионный тест для арены «Завод — Плавильня» (Factory Smelter).
## Проверяет спавны, проходимость моста-эстакады, работу конвейеров,
## сброс танка в топку печи (KillVolume) и интеграцию в меню и сетевые лобби.

const LavaHazardScript = preload("res://maps/components/lava_hazard.gd")
const PhysicsCrateScript = preload("res://maps/components/physics_crate.gd")

var failures := 0
var arena: BaseArena
var tank: Tank

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _run() -> void:
	if SoundManager:
		SoundManager._streams.clear()
	
	var arena_scene := load("res://maps/factory_smelter.tscn") as PackedScene
	arena = arena_scene.instantiate() as BaseArena
	add_child(arena)
	await get_tree().physics_frame
	
	# 1. Спавны
	var spawns := arena.get_spawn_points()
	_check(spawns.size() == 8, "Восемь валидных точек спавна")
	
	var space := get_world_3d().direct_space_state
	for pt in spawns:
		var ray := PhysicsRayQueryParameters3D.create(pt.global_position + Vector3.UP * 3, pt.global_position - Vector3.UP * 2, 1)
		var hit := space.intersect_ray(ray)
		_check(not hit.is_empty() and absf(hit.position.y) < 0.1, pt.name + " стоит над чистым полом")
		
		var shape := CylinderShape3D.new()
		shape.radius = 1.5
		shape.height = 2.0
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = pt.global_position + Vector3.UP
		query.collision_mask = 1
		_check(space.intersect_shape(query).is_empty(), pt.name + " имеет зазор под максимальный танк")
	
	# 2. Конвейеры и Манипуляторы
	var conveyors_node := arena.get_node_or_null("Conveyors")
	_check(conveyors_node != null and conveyors_node.get_child_count() >= 3, "Все 3 промышленные конвейерные линии присутствуют")
	var gear_conv := arena.get_node_or_null("Conveyors/GearOverpassConveyor") as Path3D
	_check(gear_conv != null and gear_conv.curve != null and gear_conv.curve.point_count >= 8, "Главный конвейер с шестерёнками плавно огибает карту и заходит на мост")
	
	var sw_chute := arena.get_node_or_null("Conveyors/SWScrapChute") as Path3D
	var ne_chute := arena.get_node_or_null("Conveyors/NEScrapChute") as Path3D
	_check(sw_chute != null and sw_chute.curve != null and sw_chute.curve.point_count == 4, "Юго-западный конвейер сброса имеет плавный угол 90° в печь (4 контрольные точки)")
	_check(ne_chute != null and ne_chute.curve != null and ne_chute.curve.point_count == 4, "Северо-восточный конвейер сброса имеет плавный угол 90° в печь (4 контрольные точки)")
	
	var inserters_node := arena.get_node_or_null("Inserters")
	_check(inserters_node != null and inserters_node.get_child_count() >= 5, "5 анимированных манипуляторов Factorio на западном складе")
	
	# 3. Физический прогон танка по мосту-эстакаде над печью (scale 1.0 и 2.0)
	tank = (load("res://tank/tank.tscn") as PackedScene).instantiate() as Tank
	add_child(tank)
	tank.set_physics_process(false)
	tank.net_sync.set_physics_process(false)
	tank.net_sync.set_process(false)
	tank.input.enabled = false
	tank.input.set_physics_process(false)
	
	for scale_val in [1.0, 2.0]:
		tank.get_node("CollisionShape3D").scale = Vector3.ONE * scale_val
		await _drive_bridge_test(scale_val)
	
	# 3b. Проезд танка через поворот конвейера с запада на мост
	tank.get_node("CollisionShape3D").scale = Vector3.ONE
	await _drive_west_turn_test()
	
	# 4. Проверка смертоносной зоны лавы (LavaHazardZone) и сброса в топку печи
	var lava := arena.get_node_or_null("Architecture/CentralFurnacePit/LavaHazardZone") as Area3D
	_check(lava != null, "Зона смертоносной лавы LavaHazardZone найдена в шахте печи")
	
	var tank_burned := [false]
	var fell := [false]
	if lava:
		lava.connect("tank_incinerated", func(_t: Tank): tank_burned[0] = true)
	arena.tank_fell.connect(func(_b: Tank): fell[0] = true)
	
	# Позиционируем танк внутри зоны поражения лавы (Y = -2.5)
	tank.position = Vector3(4.0, -2.5, 0.0)
	for _frame in range(10):
		await get_tree().physics_frame
	
	_check(tank_burned[0], "Падение в лаву активирует сигнал tank_incinerated")
	_check(fell[0], "Падение в раскалённую печь активирует сигнал tank_fell")
	_check(not tank.health.is_alive() and not tank.is_active, "Танк мгновенно уничтожен лавой (health <= 0, is_active = false)")
	
	# Проверка утилизации и респавна ящика в лаве
	var crate := arena.get_node_or_null("DynamicProps/FactoryCrate_01") as RigidBody3D
	_check(crate != null, "Физический ящик с металлоломом найден на конвейере")
	if crate and lava:
		var initial_crate_pos := crate.global_position
		var crate_burned := [false]
		lava.connect("crate_incinerated", func(_c: Node): crate_burned[0] = true)
		crate.global_position = Vector3(4.0, -2.5, 0.0)
		for _frame in range(10):
			await get_tree().physics_frame
		_check(crate_burned[0], "Сброс ящика в лаву активирует сигнал crate_incinerated")
		_check(crate.global_position.distance_to(initial_crate_pos) < 0.5, "Ящик после лавы телепортируется на старт конвейера")
	
	tank.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	
	# 5. Проверка интеграции в каталог меню, песочницу и лобби
	await _check_integration()
	
	print("Factory Smelter Tests completed: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)

func _drive_bridge_test(scale_val: float) -> void:
	# Заезд на мост с севера (X=4.0, Z=-17), проезд над печью на юг (Z=+17)
	tank.position = Vector3(4.0, 0.2, -17.0)
	tank.velocity = Vector3.ZERO
	tank.input.move_direction_world = Vector3(0, 0, 1) # Движение на юг
	
	var reached_high_deck := false
	var crossed_south := false
	
	for _frame in range(280):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
		if tank.position.y >= 3.2 and absf(tank.position.z) < 5.0:
			reached_high_deck = true
		if tank.position.z >= 15.0 and tank.position.y <= 0.4 * scale_val + 0.2:
			crossed_south = true
			break
	
	_check(reached_high_deck, "Танк scale=%.1f успешно поднялся на мост-эстакаду над печью" % scale_val)
	_check(crossed_south, "Танк scale=%.1f успешно пересёк мост над печью и съехал на южный пол" % scale_val)

func _drive_west_turn_test() -> void:
	# Ставим танк на северный конвейер перед поворотом: X = -3.0, Z = -17.2
	tank.position = Vector3(-3.0, 0.2, -17.2)
	tank.velocity = Vector3.ZERO
	tank.input.move_direction_world = Vector3.ZERO
	
	var turned_onto_bridge := false
	for _frame in range(220):
		await get_tree().physics_frame
		tank.controller.process_physics(tank.input, 1.0 / 60.0)
		# Проверяем, что конвейер плавно повернул танк в створ моста (X близко к 4.0, Z южнее -14.0, въезд на рампу)
		if absf(tank.position.x - 4.0) < 1.6 and tank.position.z > -13.5 and tank.position.y > 0.4:
			turned_onto_bridge = true
			break
	_check(turned_onto_bridge, "Танк плавно проходит поворот с запада и въезжает на мост")

func _check_integration() -> void:
	_check(MainMenu.MAP_INFO.has("factory_smelter"), "Карта присутствует в каталоге MainMenu.MAP_INFO")
	
	var practice := (load("res://maps/factory_smelter_practice.tscn") as PackedScene).instantiate() as TestSandbox
	add_child(practice)
	await get_tree().physics_frame
	_check(practice.current_arena != null and Game.rules.selected_map == "factory_smelter", "F6 соло-практика успешно загружает Factory Smelter")
	_check(practice.match_controller.spawn_points_container == practice.current_arena.spawn_points_container, "MatchController подключен к точкам спавна арены")
	
	var map_idx := Lobby.MAP_NAMES.find("factory_smelter")
	_check(map_idx >= 0 and practice.lobby.opt_map.item_count > map_idx, "Внутриигровое лобби содержит карту в списке")
	practice.queue_free()
	await get_tree().process_frame
	
	var screen := (load("res://lobby/lobby_screen.tscn") as PackedScene).instantiate() as LobbyScreen
	add_child(screen)
	map_idx = LobbyScreen.MAP_NAMES.find("factory_smelter")
	_check(map_idx >= 0 and screen.opt_map.item_count > map_idx, "LAN-лобби содержит карту в списке")
	screen.queue_free()
	await get_tree().process_frame
