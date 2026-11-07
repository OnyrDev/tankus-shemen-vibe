shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 rim_color : source_color = vec4(1.0, 0.35, 0.28, 1.0);
uniform float rim_power : hint_range(1.0, 8.0) = 3.2;
uniform float rim_strength : hint_range(0.0, 2.5) = 0.70;

void fragment() {
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, rim_power);

	// Мягкий акцент на верхнюю и боковую полусферу, чтобы силуэт читался в глубоких тенях
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float hemi = mix(0.65, 1.18, clamp(world_n.y * 0.5 + 0.5, 0.0, 1.0));

	float intensity = fresnel * rim_strength * hemi;
	ALBEDO = rim_color.rgb * intensity;
	ALPHA = clamp(intensity, 0.0, 1.0);
}

