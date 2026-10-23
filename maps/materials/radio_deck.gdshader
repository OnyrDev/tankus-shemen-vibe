shader_type spatial;
render_mode diffuse_burley;

uniform vec4 plate : source_color = vec4(0.23, 0.25, 0.31, 1.0);
uniform vec4 seam : source_color = vec4(0.08, 0.10, 0.14, 1.0);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz / vec2(3.0, 2.4);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 d = min(f, 1.0 - f);
	float aa = max(fwidth(p.x), fwidth(p.y));
	float joint = 1.0 - smoothstep(0.008, 0.008 + aa, min(d.x, d.y));
	float variation = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 bolt = abs(f - 0.5) - vec2(0.45, 0.44);
	float rivet = 1.0 - smoothstep(0.012, 0.012 + aa, length(bolt));
	ALBEDO = mix(plate.rgb * (0.95 + variation * 0.10), seam.rgb, joint * 0.9);
	ALBEDO = mix(ALBEDO, vec3(0.4), rivet * 0.65);
	METALLIC = 0.42;
	ROUGHNESS = 0.64;
}
