shader_type spatial;
render_mode diffuse_burley;

uniform vec4 stone : source_color = vec4(0.85, 0.74, 0.57, 1.0);
uniform vec4 grout : source_color = vec4(0.67, 0.56, 0.39, 1.0);
uniform float tile_size = 2.4;
uniform float joint_width = 0.016;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 plane_uv = abs(world_normal.y) > 0.5
		? world_position.xz
		: (abs(world_normal.x) > abs(world_normal.z) ? world_position.zy : world_position.xy);
	vec2 uv = plane_uv / tile_size;
	uv.x += mod(floor(uv.y), 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 edge = min(fract(uv), 1.0 - fract(uv));
	float nearest = min(edge.x, edge.y);
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	float joint = 1.0 - smoothstep(joint_width, joint_width + aa, nearest);
	float variation = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float sand_drift = sin(world_position.x * 0.17 + cos(world_position.z * 0.13)) * 0.035;
	float grain = sin(plane_uv.x * 11.0 + sin(plane_uv.y * 7.5)) * 0.01;
	vec3 base_col = stone.rgb * (0.94 + variation * 0.10 + sand_drift) + grain;
	ALBEDO = mix(base_col, grout.rgb, joint * 0.62);
	ROUGHNESS = 0.84;
}

