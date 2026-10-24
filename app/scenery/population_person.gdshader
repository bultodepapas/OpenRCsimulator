shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://scenery/vertex_color_linear.gdshaderinc"

global uniform float sim_clock;
global uniform vec3 wind_vec;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float normal_strength = 1.0;
uniform float roughness_value = 0.85;
uniform bool fabric = false;
uniform bool skin = false;
uniform float shirt_start = 0.90;
// SC-HUM-02 merged pose: one atlas material; UV2.x is the shading class (0 skin, 1 fabric, 2 plain,
// 3 eyes, 4 flat) and UV2.y the roughness, replacing the per-part fabric/skin/roughness uniforms.
uniform bool merged = false;
// SC-HUM-07 faces: warm backlight on skin, wet eyes and the alpha cut that keeps thin brows and hair.
uniform vec3 skin_backlight = vec3(0.42, 0.20, 0.14);
uniform float alpha_cut = 0.3;
uniform float eye_specular = 0.6;
uniform float eye_roughness = 0.18;
// SC-HUM-03 head aim: Population.head_rig() supplies the neck pivot and weight band per pose;
// PeopleGaze writes yaw to INSTANCE_CUSTOM.w (yaw / PI) and pitch to COLOR.a (0.5 + pitch / PI).
uniform bool head_enabled = false;
uniform vec3 head_pivot = vec3(0.0, 1.55, 0.0);
uniform vec2 head_band = vec2(1.47, 1.56);
uniform vec2 head_radius = vec2(0.13, 0.18);
varying float shirt_weight;
varying vec3 shirt_tint;
varying float skin_tone;
// SC-HUM-08 cloth flutter: metres of hem travel per m/s of wind, capped; zero wind leaves geometry exact.
const float FLUTTER_PER_MPS = 0.0015;
const float FLUTTER_MAX_MPS = 8.0;

void vertex() {
	// Sub-centimeter breathing/weight shift, feet anchored. Integer cycles make the
	// 1024 s simulation-clock wrap seamless; pause and replay never use wall time.
	float phase = INSTANCE_CUSTOM.x * 6.28318530718;
	float motion = INSTANCE_CUSTOM.y;
	float upper = smoothstep(0.65, 1.5, VERTEX.y);
	shirt_weight = smoothstep(shirt_start, shirt_start + 0.12, VERTEX.y);
	shirt_tint = vertex_color_to_linear(COLOR.rgb);
	skin_tone = INSTANCE_CUSTOM.z;
	float head_w = 0.0;
	if (head_enabled && (INSTANCE_CUSTOM.w != 0.0 || COLOR.a != 0.5)) {
		head_w = smoothstep(head_band.x, head_band.y, VERTEX.y)
			* (1.0 - smoothstep(head_radius.x, head_radius.y, length(VERTEX.xz - head_pivot.xz)));
	}
	// Untouched vertices (rest heads, w = 0) keep their exact geometry.
	if (head_w > 0.0) {
		// Rotate each vertex by angle × weight (a position mix() would shrink the neck), pitch about
		// local X then yaw about Y; the faces look along local -Z. Normals follow the same rotation.
		// Population.head_rotate() is the CPU mirror used by tests.
		float w = head_w;
		float yaw = INSTANCE_CUSTOM.w * PI * w;
		float pitch = (COLOR.a - 0.5) * PI * w;
		float cp = cos(pitch);
		float sp = sin(pitch);
		float cy = cos(yaw);
		float sy = sin(yaw);
		mat3 rotation = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy))
			* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cp, sp), vec3(0.0, -sp, cp));
		VERTEX = head_pivot + rotation * (VERTEX - head_pivot);
		NORMAL = rotation * NORMAL;
		TANGENT = rotation * TANGENT;
		BINORMAL = rotation * BINORMAL;
	}
	// SC-HUM-08: shirt hems and loose shirt fronts move with the field wind; shoulders and collars stay
	// pinned (weight falls to zero towards the chest). The flutter uses whole cycles of the 1024 s clock.
	bool tinted = merged ? (floor(UV2.x + 0.5) == 1.0) : fabric;
	if (tinted && dot(wind_vec, wind_vec) > 0.0) {
		float hem = shirt_weight * (1.0 - smoothstep(shirt_start + 0.10, shirt_start + 0.40, VERTEX.y));
		// People are placed by rotation × uniform scale, so the inverse is the scaled transpose.
		mat3 model = mat3(MODEL_MATRIX);
		vec3 local_wind = transpose(model) * wind_vec / dot(model[0], model[0]);
		local_wind *= FLUTTER_PER_MPS * min(1.0, FLUTTER_MAX_MPS / max(length(local_wind), 0.0001));
		float gust = 0.65 + 0.35 * sin(sim_clock * (6.28318530718 * 2304.0 / 1024.0) + phase + VERTEX.y * 9.0);
		VERTEX += local_wind * hem * gust;
	}
	VERTEX.x += sin(sim_clock * (6.28318530718 * 43.0 / 1024.0) + phase) * 0.004 * upper * motion;
	VERTEX.z += sin(sim_clock * (6.28318530718 * 171.0 / 1024.0) + phase) * 0.002 * upper * motion;
}

void fragment() {
	vec4 texel = has_texture ? texture(base_texture, UV) : vec4(1.0);
	ALBEDO = base_color.rgb * texel.rgb;
	float shading = merged ? floor(UV2.x + 0.5) : -1.0;
	if (fabric || shading == 1.0) {
		float detail = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = mix(ALBEDO, detail * shirt_tint * 2.2, shirt_weight);
	}
	if (skin || shading == 0.0) {
		// LU-21's single skin was darkened per person; merged outfits carry their own skins (SC-HUM-07),
		// so they vary only slightly. Compatibility has no subsurface scattering: a warm backlight term
		// lifts the shadowed side and the terminator of skin (ears, nose, fingers) instead (plan §5.4).
		ALBEDO *= merged ? mix(vec3(1.04), vec3(0.92, 0.89, 0.86), skin_tone) : mix(vec3(1.0), vec3(0.58, 0.42, 0.32), skin_tone);
		BACKLIGHT = ALBEDO * skin_backlight;
	}
	ALPHA = base_color.a * texel.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = merged ? UV2.y : roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.22;
	if (shading == 3.0 && eye_roughness >= 0.0) {
		// Eyes: a small wet highlight keeps them alive instead of reading as dark holes.
		ROUGHNESS = eye_roughness;
		SPECULAR = eye_specular;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
