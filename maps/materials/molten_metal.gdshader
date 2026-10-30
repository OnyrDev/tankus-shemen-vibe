shader_type spatial;
render_mode diffuse_burley;

uniform vec4 crust_color : source_color = vec4(0.25, 0.08, 0.04, 1.0);
uniform vec4 molten_color : source_color = vec4(1.0, 0.42, 0.05, 1.0);
uniform vec4 core_glow : source_color = vec4(1.0, 0.88, 0.35, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 4.2;
uniform float wave_speed : hint_range(0.1, 5.0) = 1.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Gentle bubbling liquid displacement
	float wave1 = sin(world_pos.x * 1.5 + TIME * wave_speed) * 0.04;
	float wave2 = cos(world_pos.z * 1.8 + TIME * wave_speed * 1.3) * 0.04;
	VERTEX.y += wave1 + wave2;
}

void fragment() {
	vec2 p = world_pos.xz * 0.35;
	
	// Multi-octave cellular / molten flow noise
	float t = TIME * wave_speed * 0.4;
	float n1 = sin(p.x * 3.0 + sin(p.y * 2.5 + t));
	float n2 = cos(p.y * 3.2 + cos(p.x * 2.8 - t * 0.8));
	float heat = (n1 + n2) * 0.5 + 0.5;
	
	// Sharp transitions between cooled slag crust and burning hot molten seams
	float slag_mask = smoothstep(0.42, 0.65, heat);
	float core_mask = smoothstep(0.75, 0.95, heat);
	
	vec3 base = mix(crust_color.rgb, molten_color.rgb, slag_mask);
	base = mix(base, core_glow.rgb, core_mask);
	
	ALBEDO = base;
	EMISSION = mix(molten_color.rgb * 1.5, core_glow.rgb * 3.0, core_mask) * (slag_mask * 0.9 + 0.1) * emission_energy;
	METALLIC = 0.2;
	ROUGHNESS = mix(0.7, 0.15, slag_mask);
}
