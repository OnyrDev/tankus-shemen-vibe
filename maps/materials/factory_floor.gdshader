shader_type spatial;
render_mode diffuse_burley;

uniform vec4 plate_color : source_color = vec4(0.24, 0.27, 0.33, 1.0);
uniform vec4 seam_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform float plate_size = 4.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	
	// Large modular plate grid
	vec2 grid = p / plate_size;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	vec2 edge = min(f, 1.0 - f);
	float aa = max(fwidth(grid.x), fwidth(grid.y));
	float seam = 1.0 - smoothstep(0.012, 0.012 + aa, min(edge.x, edge.y));
	
	// Cell brightness variation
	float variation = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	
	// Diamond tread micro-relief (industrial non-slip floor)
	vec2 tread_uv = fract(p * 5.0) - 0.5;
	float d1 = abs(tread_uv.x + tread_uv.y);
	float d2 = abs(tread_uv.x - tread_uv.y);
	float diamond = smoothstep(0.25, 0.20, min(d1, d2));
	
	vec3 col = plate_color.rgb * (0.92 + variation * 0.14);
	col += vec3(diamond * 0.08); // tread highlight
	col = mix(col, seam_color.rgb, seam * 0.9);
	
	ALBEDO = col;
	METALLIC = 0.52;
	ROUGHNESS = 0.62;
}
