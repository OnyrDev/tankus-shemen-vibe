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
	print("Projectile visual checks: %d failed" % failures)
	get_tree().quit(1 if failures else 0)
