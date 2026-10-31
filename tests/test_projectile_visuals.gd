extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PASS] " + label)
	else:
		failures += 1
		push_error(label)

func _run() -> void:
	var scene := load("res://projectile/projectile.tscn") as PackedScene
	var first := scene.instantiate() as Projectile
	var second := scene.instantiate() as Projectile
	add_child(first)
	add_child(second)
	first.set_physics_process(false)
	second.set_physics_process(false)
	first.setup(null, Vector3.ZERO, Vector3.RIGHT, Color.CYAN)
	second.setup(null, Vector3(0, 2, 0), Vector3.UP, Color.RED)
	_check((-first.visuals.global_basis.z).normalized().is_equal_approx(Vector3.RIGHT), "Shell nose follows horizontal velocity")
	_check((-second.visuals.global_basis.z).normalized().is_equal_approx(Vector3.UP), "Vertical shots have a valid orientation")
	first.velocity = Vector3.BACK * first.speed
	first._update_visual_direction()
	_check((-first.visuals.global_basis.z).normalized().is_equal_approx(Vector3.BACK), "Shell turns after a bounce or reflection")
	_check(first.rotation.is_zero_approx(), "Visual orientation leaves the physics body unchanged")
	var first_mat := first.mesh_instance.material_override as StandardMaterial3D
	var second_mat := second.mesh_instance.material_override as StandardMaterial3D
	_check(first_mat.emission == Color.CYAN and second_mat.emission == Color.RED, "Team shell colors are independent")
	_check(first_mat.albedo_color.a < 0.5, "Energy shell keeps transparency around the white core")
	_check(first.visuals.get_node("Nose").material_override == null, "Metal casing retains its material")
	_check(first.particles.process_material != second.particles.process_material, "Particle tint is isolated per projectile")
	_check((first.particles.process_material as ParticleProcessMaterial).color == Color.CYAN.lightened(0.25), "Trail uses the projectile team color")
	_check(first.particles.lifetime * first.speed < 1.5, "Particle trail stays short at base speed")
	_check(is_equal_approx((first.collision_shape.shape as SphereShape3D).radius, 0.18), "Collision radius remains unchanged")
	_check(first.damage == 28.0 and first.speed == 24.0 and first.bounces_left == 0, "Base combat stats remain unchanged")
	first.free()
	second.free()

	# Проверка Big Shot: визуальный масштаб, дальность полета над полом и уничтожение при прямом попадании в поверхность сверху
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100.0, 1.0, 100.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	var big_proj := scene.instantiate() as Projectile
	big_proj.size_mult = 2.6
	big_proj.speed = 13.5
	add_child(big_proj)
	big_proj.setup(null, Vector3(0.0, 0.35, 0.0), Vector3(0.0, 0.0, -1.0), Color.ORANGE)
	_check(big_proj.visuals.global_basis.get_scale().x > 2.0, "Big Shot preserves enlarged visual scale after look_at")
	_check(big_proj.lifetime >= 5.0, "Big Shot scales lifetime to preserve full flight range")

	for _step in range(180):
		big_proj._physics_process(1.0 / 60.0)
		if big_proj._is_destroyed:
			break

	_check(not big_proj._is_destroyed and big_proj.distance_traveled > 35.0, "Big Shot flies low above floor without premature floor collision")
	big_proj.free()

	var top_hit_proj := scene.instantiate() as Projectile
	add_child(top_hit_proj)
	top_hit_proj.setup(null, Vector3(0.0, 1.5, 0.0), Vector3(0.0, -0.35, -1.0).normalized(), Color.ORANGE)
	for _step in range(60):
		top_hit_proj._physics_process(1.0 / 60.0)
		if top_hit_proj._is_destroyed:
			break

	_check(top_hit_proj._is_destroyed, "Projectile hitting surface from above is destroyed and does not bounce off")
	if is_instance_valid(top_hit_proj):
		top_hit_proj.free()
	floor_body.free()
	print("Projectile visual checks: %d failed" % failures)
	get_tree().quit(1 if failures else 0)
