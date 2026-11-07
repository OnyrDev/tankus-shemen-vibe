shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.035, 0.045, 0.068, 1.0);
uniform float near_width_m : hint_range(0.002, 0.08) = 0.015;
uniform float far_width_m : hint_range(0.01, 0.20) = 0.064;
uniform float near_dist : hint_range(1.0, 20.0) = 5.0;
uniform float far_dist : hint_range(10.0, 100.0) = 44.0;

void vertex() {
	// Если в COLOR запечена сглаженная нормаль по склеенным вершинам (COLOR.a < 0.75),
	// выдавливаем по ней, чтобы контур не рвался на жёстких 90-градусных гранях брони.
	vec3 smooth_n = (COLOR.a < 0.75) ? normalize(COLOR.rgb * 2.0 - 1.0) : normalize(NORMAL);

	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_pos = INV_VIEW_MATRIX[3].xyz;
	float cam_dist = distance(world_pos, cam_pos);

	float dist_factor = clamp((cam_dist - near_dist) / max(0.001, far_dist - near_dist), 0.0, 1.0);
	float world_thickness = mix(near_width_m, far_width_m, dist_factor);

	// Компенсация масштаба меша (0.44 у CobaltScout + карты масштаба Tiny/Titan)
	float model_scale = max(0.001, length(MODEL_MATRIX[0].xyz));
	VERTEX += smooth_n * (world_thickness / model_scale);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}

