shader_type spatial;
render_mode cull_disabled;

uniform float belt_distance = 0.0;
uniform vec4 base_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float metalness = 0.0;
uniform float surface_roughness = 0.7;

const float RADIUS = 0.73;
const float HALF_LENGTH = 1.02;
const float LOOP_LENGTH = 4.0 * HALF_LENGTH + 6.28318530718 * RADIUS;

// Returns (height, longitudinal position, rotation about the axle).
vec3 belt_pose(float distance) {
	float s = mod(distance, LOOP_LENGTH);
	float straight = 2.0 * HALF_LENGTH;
	float arc = 3.14159265359 * RADIUS;
	if (s < straight) {
		return vec3(0.75 + RADIUS, -HALF_LENGTH + s, 0.0);
	}
	if (s < straight + arc) {
		float angle = (s - straight) / RADIUS;
		return vec3(0.75 + RADIUS * cos(angle), HALF_LENGTH + RADIUS * sin(angle), angle);
	}
	if (s < 2.0 * straight + arc) {
		return vec3(0.75 - RADIUS, HALF_LENGTH - (s - straight - arc), 3.14159265359);
	}
	float angle = 3.14159265359 + (s - 2.0 * straight - arc) / RADIUS;
	return vec3(0.75 + RADIUS * cos(angle), -HALF_LENGTH + RADIUS * sin(angle), angle);
}

vec3 turn_axle(vec3 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z);
}

void vertex() {
	if (UV2.y > 0.5) {
		vec3 before = belt_pose(UV2.x);
		vec3 after = belt_pose(UV2.x + belt_distance);
		float turn = after.z - before.z;
		vec3 offset = VERTEX - vec3(0.0, before.x, before.y);
		VERTEX = vec3(0.0, after.x, after.y) + turn_axle(offset, turn);
		NORMAL = turn_axle(NORMAL, turn);
		TANGENT = turn_axle(TANGENT, turn);
		BINORMAL = turn_axle(BINORMAL, turn);
	}
}

void fragment() {
	ALBEDO = base_color.rgb;
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
}
