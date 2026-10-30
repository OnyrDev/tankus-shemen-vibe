shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform vec4 belt_color : source_color = vec4(0.20, 0.23, 0.28, 1.0);
uniform vec4 slat_color : source_color = vec4(0.13, 0.15, 0.19, 1.0);
uniform vec4 chevron_color : source_color = vec4(0.96, 0.72, 0.18, 1.0); // Factorio bright yellow
uniform vec4 hazard_dark : source_color = vec4(0.10, 0.11, 0.13, 1.0);
uniform float speed : hint_range(-20.0, 20.0) = 6.0;
uniform float chevron_scale : hint_range(0.1, 5.0) = 1.2;
uniform bool show_gears = false;
uniform bool is_hazard_stripes = true;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	// Animate V along conveyor path
	float anim_v = v_uv.y - TIME * speed * 0.35;
	float u = v_uv.x;
	
	// Base industrial steel belt color
	vec3 col = belt_color.rgb;
	
	// Segmented metal slats (distinct grooved steel plates every 0.4m)
	float slat_phase = fract(anim_v * 2.5);
	float slat_groove = smoothstep(0.85, 0.95, slat_phase) + (1.0 - smoothstep(0.0, 0.05, slat_phase));
	col = mix(col, slat_color.rgb, clamp(slat_groove, 0.0, 1.0) * 0.75);
	
	// Metallic roller line down the center division (two lanes like in Factorio)
	float center_line = smoothstep(0.485, 0.50, u) * (1.0 - smoothstep(0.50, 0.515, u));
	col = mix(col, slat_color.rgb * 0.6, center_line * 0.8);
	
	// Side borders / guide rails (outer 15% on left and right)
	float side_left = 1.0 - smoothstep(0.12, 0.15, u);
	float side_right = smoothstep(0.85, 0.88, u);
	float is_border = clamp(side_left + side_right, 0.0, 1.0);
	
	// Yellow/Black Hazard diagonal stripes on borders
	float stripe_diag = fract((u * 3.5 + anim_v * 1.5) * 2.0);
	float stripe_mask = step(0.5, stripe_diag);
	vec3 border_stripe = mix(hazard_dark.rgb, chevron_color.rgb, stripe_mask);
	
	// Bold center chevron arrows pointing in the direction of movement
	float dist_center = abs(u - 0.5);
	float center_mask = 1.0 - smoothstep(0.22, 0.35, dist_center);
	
	// Arrow shape: V-offset creates arrow tip at center pointing forward
	float chevron_phase = fract(anim_v * chevron_scale + dist_center * 1.8);
	float chevron_arrow = smoothstep(0.35, 0.44, chevron_phase) * (1.0 - smoothstep(0.56, 0.65, chevron_phase));
	
	// Apply chevron arrows
	float arrow_intensity = chevron_arrow * center_mask;
	col = mix(col, chevron_color.rgb, arrow_intensity);
	
	// Optional gear stamp icon along the belt
	if (show_gears) {
		float gear_v = fract(anim_v * 0.4);
		vec2 gear_pos = vec2((u - 0.5) * 2.8, (gear_v - 0.5) * 2.8);
		float r = length(gear_pos);
		float angle = atan(gear_pos.y, gear_pos.x);
		float cogs = sin(angle * 8.0) * 0.08;
		float gear_shape = (1.0 - smoothstep(0.32 + cogs, 0.36 + cogs, r)) * smoothstep(0.10, 0.13, r);
		col = mix(col, vec3(0.85, 0.88, 0.94), gear_shape * 0.9);
	}
	
	// Apply side border hazard markings
	if (is_hazard_stripes) {
		col = mix(col, border_stripe, is_border);
	} else {
		col = mix(col, hazard_dark.rgb, is_border);
	}
	
	ALBEDO = col;
	// Subtle glow on the yellow arrows and hazard stripes so they pop in any lighting
	EMISSION = chevron_color.rgb * arrow_intensity * 0.6 + border_stripe * is_border * 0.2;
	METALLIC = 0.5;
	ROUGHNESS = 0.5;
}
