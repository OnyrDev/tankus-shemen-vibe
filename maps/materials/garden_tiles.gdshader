shader_type spatial;
render_mode diffuse_burley;

uniform vec4 stone : source_color = vec4(0.89, 0.79, 0.63, 1.0);
uniform vec4 grout : source_color = vec4(0.69, 0.61, 0.48, 1.0);
uniform float tile_size = 1.8;
uniform float joint_width = 0.012;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_position.xz / tile_size;
	uv.x += mod(floor(uv.y), 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 edge = min(fract(uv), 1.0 - fract(uv));
	float nearest = min(edge.x, edge.y);
	float aa = max(fwidth(uv.x), fwidth(uv.y));
	float joint = 1.0 - smoothstep(joint_width, joint_width + aa, nearest);
	float variation = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float grain = sin(world_position.x * 12.0 + sin(world_position.z * 7.0)) * 0.007;
	ALBEDO = mix(stone.rgb * (0.95 + variation * 0.09) + grain, grout.rgb, joint * 0.65);
	ROUGHNESS = 0.75;
}
