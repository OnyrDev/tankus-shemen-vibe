class_name GroundTelegraph3D
extends Node3D

## Универсальная 3D-система маркеров приземления и зон угрозы (Decal-based).
## Проецируется строго на геометрии мира (cull_mask = 1: пол, наклонные рампы, ступени, мосты),
## не окрашивая корпуса танков (слой 2). Содержит тёмную контрастную окантовку для светлых карт
## (песок, лёд) и эмиссионное ядро для тёмных зон, а также готовый API под будущие навесные снаряды.

enum Preset {
	DANGER,       ## Вражеский Ground Slam / навесной удар (красно-оранжевая тревога)
	ALLY_SLAM,    ## Свой или союзный Ground Slam (янтарно-голубой тактический)
	NEUTRAL_DROP, ## Обычное приземление танка в прыжке (компактное посадочное кольцо)
	HEAL,         ## Приземление и зона подбора бургера (изумрудно-зелёный)
}

enum Mode {
	TIMED,
	TRACKED,
}

const TEX_SIZE: int = 256
const TIMED_GROUP := "ground_telegraphs"

static var _hazard_albedo_tex: ImageTexture = null
static var _hazard_emission_tex: ImageTexture = null
static var _drop_albedo_tex: ImageTexture = null
static var _drop_emission_tex: ImageTexture = null
static var _fill_albedo_tex: ImageTexture = null
static var _fill_emission_tex: ImageTexture = null

var mode: Mode = Mode.TRACKED
var preset: Preset = Preset.DANGER
var radius: float = 2.0
var progress: float = 0.0
var duration: float = 0.5

var _elapsed: float = 0.0
var _pulse_time: float = 0.0
var _outer_decal: Decal = null
var _fill_decal: Decal = null

func _ready() -> void:
	_ensure_textures()
	_build_decals_if_needed()
	_apply_preset_visuals()
	_refresh_transforms()

func _process(delta: float) -> void:
	_pulse_time += delta
	if mode == Mode.TIMED:
		_elapsed += delta
		var total_dur := maxf(0.05, duration)
		if _elapsed <= total_dur:
			progress = clampf(_elapsed / total_dur, 0.0, 1.0)
			_refresh_transforms()
		elif _elapsed <= total_dur + 0.09:
			var fade := 1.0 - clampf((_elapsed - total_dur) / 0.09, 0.0, 1.0)
			_set_alpha_multiplier(fade)
		else:
			if is_in_group(TIMED_GROUP):
				remove_from_group(TIMED_GROUP)
			queue_free()
	elif visible:
		_refresh_pulse_only()

## Готовый API для навесных/миномётных снарядов и дуговых объектов с известным временем подлёта.
static func spawn_timed(
	parent_node: Node,
	target_world_pos: Vector3,
	p_radius: float,
	p_duration: float,
	p_preset: Preset = Preset.DANGER,
	snap_to_ground: bool = true
) -> GroundTelegraph3D:
	if not parent_node:
		return null

	var telegraph := GroundTelegraph3D.new()
	telegraph.name = "GroundTelegraphTimed"
	telegraph.mode = Mode.TIMED
	telegraph.preset = p_preset
	telegraph.radius = maxf(0.25, p_radius)
	telegraph.duration = maxf(0.05, p_duration)
	telegraph.progress = 0.05
	telegraph.add_to_group(TIMED_GROUP)

	parent_node.add_child(telegraph)
	var final_pos := target_world_pos
	if snap_to_ground:
		final_pos = telegraph._snap_point_to_world_ground(target_world_pos)
	telegraph.global_position = final_pos
	telegraph.global_rotation = Vector3.ZERO
	telegraph._apply_preset_visuals()
	telegraph._refresh_transforms()
	return telegraph

## Создаёт управляемый телеграф для физически движущихся объектов (прыгающие/падающие танки, управляемые снаряды).
static func create_tracked(
	parent_node: Node,
	p_radius: float = 1.0,
	p_preset: Preset = Preset.NEUTRAL_DROP
) -> GroundTelegraph3D:
	if not parent_node:
		return null

	var telegraph := GroundTelegraph3D.new()
	telegraph.name = "GroundTelegraphTracked"
	telegraph.mode = Mode.TRACKED
	telegraph.preset = p_preset
	telegraph.radius = maxf(0.25, p_radius)
	telegraph.progress = 0.0
	telegraph.visible = false
	parent_node.add_child(telegraph)
	return telegraph

## Очищает все автономные (TIMED) телеграфы при перезапуске раунда.
static func clear_all(tree: SceneTree) -> void:
	if not tree:
		return
	for node in tree.get_nodes_in_group(TIMED_GROUP):
		if is_instance_valid(node):
			node.remove_from_group(TIMED_GROUP)
			node.queue_free()

func set_target_position(world_pos: Vector3, snap_to_ground: bool = false) -> void:
	global_position = _snap_point_to_world_ground(world_pos) if snap_to_ground else world_pos
	global_rotation = Vector3.ZERO

func update_tracked(
	ground_world_pos: Vector3,
	p_radius: float,
	p_progress: float,
	show_marker: bool,
	p_preset: Preset
) -> void:
	if not show_marker:
		if visible:
			visible = false
		return

	var preset_changed := (preset != p_preset)
	preset = p_preset
	radius = maxf(0.25, p_radius)
	progress = clampf(p_progress, 0.0, 1.0)

	if not visible:
		visible = true
	global_position = ground_world_pos
	global_rotation = Vector3.ZERO

	_build_decals_if_needed()
	if preset_changed:
		_apply_preset_visuals()
	_refresh_transforms()

func get_outer_decal() -> Decal:
	_build_decals_if_needed()
	return _outer_decal

func get_fill_decal() -> Decal:
	_build_decals_if_needed()
	return _fill_decal

func _snap_point_to_world_ground(origin: Vector3) -> Vector3:
	if not is_inside_tree() or not get_world_3d():
		return origin
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 2.5, origin + Vector3.DOWN * 30.0, 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		return hit.position
	return origin

func _build_decals_if_needed() -> void:
	_ensure_textures()
	if not _outer_decal:
		_outer_decal = Decal.new()
		_outer_decal.name = "OuterDecal"
		_outer_decal.cull_mask = 1 # Строго слой 1 (World) — не рисует поверх танков!
		_outer_decal.upper_fade = 0.15
		_outer_decal.lower_fade = 0.22
		_outer_decal.normal_fade = 0.55
		add_child(_outer_decal)

	if not _fill_decal:
		_fill_decal = Decal.new()
		_fill_decal.name = "FillDecal"
		_fill_decal.cull_mask = 1
		_fill_decal.upper_fade = 0.15
		_fill_decal.lower_fade = 0.22
		_fill_decal.normal_fade = 0.55
		_fill_decal.texture_albedo = _fill_albedo_tex
		_fill_decal.texture_emission = _fill_emission_tex
		add_child(_fill_decal)

func _apply_preset_visuals() -> void:
	_build_decals_if_needed()
	var base_col := _get_preset_color(preset)

	if preset == Preset.NEUTRAL_DROP:
		_outer_decal.texture_albedo = _drop_albedo_tex
		_outer_decal.texture_emission = _drop_emission_tex
		_outer_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.82)
		_outer_decal.emission_energy = 1.35
		_fill_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.55)
		_fill_decal.emission_energy = 1.15
	else:
		_outer_decal.texture_albedo = _hazard_albedo_tex
		_outer_decal.texture_emission = _hazard_emission_tex
		_outer_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.96)
		_outer_decal.emission_energy = 2.6 if preset == Preset.DANGER else 2.0
		_fill_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.85)
		_fill_decal.emission_energy = 2.2 if preset == Preset.DANGER else 1.7

func _refresh_transforms() -> void:
	if not _outer_decal or not _fill_decal:
		return

	var diameter := maxf(0.5, radius * 2.0)
	var proj_depth := clampf(radius * 1.45, 2.2, 8.5)
	_outer_decal.size = Vector3(diameter, proj_depth, diameter)

	var fill_ratio := clampf(lerpf(0.10, 1.0, progress), 0.08, 1.0)
	var fill_diam := maxf(0.15, diameter * fill_ratio)
	_fill_decal.size = Vector3(fill_diam, proj_depth, fill_diam)
	_refresh_pulse_only()

func _refresh_pulse_only() -> void:
	if not _outer_decal or not _fill_decal:
		return
	var urgency := clampf((progress - 0.55) / 0.45, 0.0, 1.0)
	var pulse := 1.0 + urgency * 0.35 * (0.5 + 0.5 * sin(_pulse_time * TAU * 7.0))
	if preset == Preset.DANGER:
		_outer_decal.emission_energy = 2.5 * pulse
		_fill_decal.emission_energy = (1.9 + 1.2 * urgency) * pulse
	elif preset == Preset.ALLY_SLAM or preset == Preset.HEAL:
		_outer_decal.emission_energy = 1.9 * pulse
		_fill_decal.emission_energy = (1.5 + 0.8 * urgency) * pulse

func _set_alpha_multiplier(alpha_mult: float) -> void:
	var base_col := _get_preset_color(preset)
	if _outer_decal:
		_outer_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.95 * alpha_mult)
	if _fill_decal:
		_fill_decal.modulate = Color(base_col.r, base_col.g, base_col.b, 0.85 * alpha_mult)

static func _get_preset_color(p: Preset) -> Color:
	match p:
		Preset.DANGER:
			return Color(1.0, 0.24, 0.12, 1.0)
		Preset.ALLY_SLAM:
			return Color(0.24, 0.88, 1.0, 1.0)
		Preset.HEAL:
			return Color(0.32, 1.0, 0.46, 1.0)
		_:
			return Color(0.86, 0.95, 1.0, 1.0)

static func _ensure_textures() -> void:
	if _hazard_albedo_tex != null:
		return

	var haz_alb := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var haz_emi := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var drop_alb := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var drop_emi := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var fill_alb := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var fill_emi := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)

	var half := float(TEX_SIZE) * 0.5
	var inv_half := 1.0 / half

	for y in range(TEX_SIZE):
		var dy := (float(y) + 0.5 - half) * inv_half
		for x in range(TEX_SIZE):
			var dx := (float(x) + 0.5 - half) * inv_half
			var r := sqrt(dx * dx + dy * dy)
			if r > 1.0:
				continue

			var angle := atan2(dy, dx)

			# --- 1. Текстура боевой зоны угрозы (Outer Hazard Ring + Shadow Border + Ticks) ---
			var outer_shadow := _band_mask(r, 0.875, 0.995, 0.015)
			var outer_core := _band_mask(r, 0.905, 0.968, 0.012)

			# 12 тактических засечек по внутреннему периметру
			var sector := absf(sin(angle * 6.0))
			var tick_band := _band_mask(r, 0.77, 0.86, 0.012) * clampf((sector - 0.82) / 0.12, 0.0, 1.0)
			var inner_wash := (1.0 - smoothstep(0.0, 0.90, r)) * 0.14 + smoothstep(0.65, 0.90, r) * (1.0 - smoothstep(0.90, 0.93, r)) * 0.18

			var bright_mask := clampf(maxf(outer_core, tick_band), 0.0, 1.0)
			var shadow_only := clampf(outer_shadow - bright_mask * 0.85, 0.0, 1.0)
			var haz_a := clampf(maxf(maxf(outer_shadow * 0.84, bright_mask * 0.98), inner_wash), 0.0, 1.0)
			var haz_luma := clampf(bright_mask + inner_wash * 1.6 - shadow_only * 0.85, 0.0, 1.0)

			haz_alb.set_pixel(x, y, Color(haz_luma, haz_luma, haz_luma, haz_a))
			var emi_val := clampf(bright_mask * 0.95 + inner_wash * 0.35, 0.0, 1.0)
			haz_emi.set_pixel(x, y, Color(emi_val, emi_val, emi_val, 1.0))

			# --- 2. Текстура компактного маркера приземления (Neutral Drop Spot) ---
			var drop_shadow := _band_mask(r, 0.74, 0.98, 0.025)
			var drop_ring := _band_mask(r, 0.80, 0.91, 0.02)
			var center_dot := 1.0 - smoothstep(0.10, 0.18, r)
			var drop_bright := clampf(maxf(drop_ring, center_dot * 0.85), 0.0, 1.0)
			var drop_dark := clampf(drop_shadow - drop_bright * 0.85, 0.0, 1.0)
			var drop_a := clampf(maxf(drop_shadow * 0.72, drop_bright * 0.92), 0.0, 1.0)
			var drop_luma := clampf(drop_bright - drop_dark * 0.85, 0.0, 1.0)

			drop_alb.set_pixel(x, y, Color(drop_luma, drop_luma, drop_luma, drop_a))
			drop_emi.set_pixel(x, y, Color(drop_bright * 0.8, drop_bright * 0.8, drop_bright * 0.8, 1.0))

			# --- 3. Внутреннее расширяющееся кольцо тайминга удара (Fill Progress Ring) ---
			var fill_edge := _band_mask(r, 0.88, 0.98, 0.025)
			var fill_disc := (1.0 - smoothstep(0.0, 0.96, r)) * 0.22
			var fill_a := clampf(maxf(fill_edge * 0.90, fill_disc), 0.0, 1.0)
			var fill_luma := clampf(fill_edge + fill_disc * 1.4, 0.0, 1.0)
			fill_alb.set_pixel(x, y, Color(fill_luma, fill_luma, fill_luma, fill_a))
			fill_emi.set_pixel(x, y, Color(fill_luma * 0.9, fill_luma * 0.9, fill_luma * 0.9, 1.0))

	_hazard_albedo_tex = ImageTexture.create_from_image(haz_alb)
	_hazard_emission_tex = ImageTexture.create_from_image(haz_emi)
	_drop_albedo_tex = ImageTexture.create_from_image(drop_alb)
	_drop_emission_tex = ImageTexture.create_from_image(drop_emi)
	_fill_albedo_tex = ImageTexture.create_from_image(fill_alb)
	_fill_emission_tex = ImageTexture.create_from_image(fill_emi)

static func _band_mask(r: float, r_min: float, r_max: float, feather: float) -> float:
	return smoothstep(r_min - feather, r_min + feather, r) * (1.0 - smoothstep(r_max - feather, r_max + feather, r))

