@tool
class_name Inserter3D
extends Node3D

## Манипулятор из Factorio (Inserter) для атмосферного окружения арены.
## Полностью процедурная анимация сочленений и захвата деталей в _process
## без тяжёлых анимационных скелетов.

@export var speed: float = 2.2
@export var cycle_offset: float = 0.0
@export var sweep_angle_deg: float = 150.0
@export var hold_gear: bool = true

const YELLOW_MAT: Color = Color("e5a93b")
const DARK_MAT: Color = Color("23272e")
const STEEL_MAT: Color = Color("7a828e")

var _pivot_base: Node3D
var _lower_arm: Node3D
var _upper_arm: Node3D
var _claw: Node3D
var _gear_item: Node3D
var _time: float = 0.0

func _ready() -> void:
	_time = cycle_offset
	_build_visuals()

func _process(delta: float) -> void:
	_time += delta * speed
	_animate()

func _animate() -> void:
	if not _pivot_base or not _lower_arm or not _upper_arm:
		return
	
	# Smooth oscillating sweep back and forth (Yaw)
	var sweep_rad := deg_to_rad(sweep_angle_deg * 0.5)
	var sine_t := sin(_time)
	var cos_t := cos(_time)
	
	_pivot_base.rotation.y = sine_t * sweep_rad
	
	# Reach down to pick up when near endpoints, lift up in the middle
	var reach_down := absf(sine_t) # 1 at edges, 0 at middle
	_lower_arm.rotation.x = deg_to_rad(lerpf(-15.0, 35.0, reach_down))
	_upper_arm.rotation.x = deg_to_rad(lerpf(30.0, -50.0, reach_down))
	
	if _claw:
		_claw.rotation.x = -_lower_arm.rotation.x - _upper_arm.rotation.x * 0.8
	
	if _gear_item and hold_gear:
		# Visible when carrying from side to side
		_gear_item.visible = (cos_t > -0.2)

func _build_visuals() -> void:
	# Clear old generated nodes if rebuilding
	for child in get_children():
		child.queue_free()
	
	# Base pedestal (Static)
	var base_mesh := CylinderMesh.new()
	base_mesh.bottom_radius = 0.65
	base_mesh.top_radius = 0.55
	base_mesh.height = 0.4
	base_mesh.radial_segments = 12
	var base_inst := MeshInstance3D.new()
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0, 0.2, 0)
	base_inst.material_override = _create_mat(DARK_MAT, 0.8, 0.3)
	add_child(base_inst)
	
	# Rotating Pivot Turret
	_pivot_base = Node3D.new()
	_pivot_base.name = "PivotBase"
	_pivot_base.position = Vector3(0, 0.4, 0)
	add_child(_pivot_base)
	
	var turret_mesh := BoxMesh.new()
	turret_mesh.size = Vector3(0.6, 0.45, 0.6)
	var turret_inst := MeshInstance3D.new()
	turret_inst.mesh = turret_mesh
	turret_inst.position = Vector3(0, 0.22, 0)
	turret_inst.material_override = _create_mat(YELLOW_MAT, 0.4, 0.2)
	_pivot_base.add_child(turret_inst)
	
	# Lower Arm Joint & Beam
	_lower_arm = Node3D.new()
	_lower_arm.name = "LowerArm"
	_lower_arm.position = Vector3(0, 0.4, 0)
	_pivot_base.add_child(_lower_arm)
	
	var lower_beam := BoxMesh.new()
	lower_beam.size = Vector3(0.24, 1.3, 0.26)
	var lower_inst := MeshInstance3D.new()
	lower_inst.mesh = lower_beam
	lower_inst.position = Vector3(0, 0.65, 0)
	lower_inst.material_override = _create_mat(YELLOW_MAT, 0.4, 0.2)
	_lower_arm.add_child(lower_inst)
	
	# Elbow Joint & Upper Arm
	_upper_arm = Node3D.new()
	_upper_arm.name = "UpperArm"
	_upper_arm.position = Vector3(0, 1.3, 0)
	_lower_arm.add_child(_upper_arm)
	
	var elbow_mesh := CylinderMesh.new()
	elbow_mesh.bottom_radius = 0.22
	elbow_mesh.top_radius = 0.22
	elbow_mesh.height = 0.32
	var elbow_inst := MeshInstance3D.new()
	elbow_inst.mesh = elbow_mesh
	elbow_inst.rotation_degrees = Vector3(0, 0, 90)
	elbow_inst.material_override = _create_mat(DARK_MAT, 0.8, 0.4)
	_upper_arm.add_child(elbow_inst)
	
	var upper_beam := BoxMesh.new()
	upper_beam.size = Vector3(0.2, 1.2, 0.2)
	var upper_inst := MeshInstance3D.new()
	upper_inst.mesh = upper_beam
	upper_inst.position = Vector3(0, 0.6, 0)
	upper_inst.material_override = _create_mat(YELLOW_MAT, 0.4, 0.2)
	_upper_arm.add_child(upper_inst)
	
	# Claw Wrist
	_claw = Node3D.new()
	_claw.name = "Claw"
	_claw.position = Vector3(0, 1.2, 0)
	_upper_arm.add_child(_claw)
	
	# Two claw fingers
	for sign_val in [-1.0, 1.0]:
		var finger := BoxMesh.new()
		finger.size = Vector3(0.08, 0.35, 0.12)
		var f_inst := MeshInstance3D.new()
		f_inst.mesh = finger
		f_inst.position = Vector3(sign_val * 0.14, 0.18, 0)
		f_inst.rotation_degrees = Vector3(0, 0, sign_val * -18.0)
		f_inst.material_override = _create_mat(STEEL_MAT, 0.3, 0.8)
		_claw.add_child(f_inst)
	
	# Held Gear Item
	if hold_gear:
		_gear_item = Node3D.new()
		_gear_item.name = "HeldGear"
		_gear_item.position = Vector3(0, 0.32, 0)
		
		var g_mesh := CylinderMesh.new()
		g_mesh.top_radius = 0.26
		g_mesh.bottom_radius = 0.26
		g_mesh.height = 0.08
		g_mesh.radial_segments = 8
		var g_inst := MeshInstance3D.new()
		g_inst.mesh = g_mesh
		g_inst.material_override = _create_mat(Color("b0b8c4"), 0.35, 0.75)
		_gear_item.add_child(g_inst)
		_claw.add_child(_gear_item)

func _create_mat(color: Color, roughness: float = 0.5, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
