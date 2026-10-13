// Adapted from Boujie Water Shader by Zach Bernal and contributors (MIT).
// Source: assets/landscape/lake/water-source/boujie_water.gdshader
// Commit: 25f3c2da458e0a4f65bdb5903dc068b050930c06
//
// Finite freshwater surface for Godot 4.7.2 Compatibility/OpenGL. The basin
// renderer supplies UV2.x as signed nearest-shore distance in metres and a
// horizontal mesh at the mean water level. Water geometry uses only the shared
// lake-physics analytic height; no Gerstner or horizontal vertex displacement.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float sim_clock;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 shallow_color : source_color = vec4(0.20, 0.43, 0.40, 1.0);
uniform vec4 deep_color : source_color = vec4(0.025, 0.115, 0.15, 1.0);
uniform vec4 foam_color : source_color = vec4(0.70, 0.82, 0.78, 1.0);
uniform float absorption_per_m : hint_range(0.05, 2.0) = 0.46;
uniform float deep_reference_depth_m : hint_range(1.0, 12.0) = 5.0;
uniform float refraction_strength : hint_range(0.0, 0.025) = 0.006;
uniform float shore_fade_m : hint_range(0.1, 12.0) = 5.5;
uniform float shore_foam_start_m : hint_range(0.0, 1.0) = 0.02;
uniform float shore_foam_end_m : hint_range(0.1, 2.0) = 0.48;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.22;
uniform float water_specular : hint_range(0.0, 1.0) = 0.76;

// x amplitude (m), y wavelength (m), z period (s), w heading (rad);
// phase is parallel in wave_phase_rad. These come from the same wave config
// and positive-up function as lake physics. Authored periods are 1024/N s so
// ShaderClock's [0, 1024) wrap remains phase-continuous.
uniform int wave_count = 0;
uniform vec4 wave_params[2];
uniform float wave_phase_rad[2];

// The existing atmosphere owns sky, directional light, haze, and time-of-day.
// This shader mirrors the ground shader's haze uniforms for its custom FOG.
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform vec3 lobe_lin = vec3(0.0);
uniform vec3 lobe_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe_k = 8.0;
uniform float lobe_height = 1.5708;
uniform float beta = 0.00017;

varying vec2 world_ne;
varying float shore_distance_m;
varying vec3 world_position;

vec2 shore_fade_data(float distance_m) {
	if (distance_m <= 0.0) {
		return vec2(0.0);
	}
	if (distance_m >= shore_fade_m) {
		return vec2(1.0, 0.0);
	}
	float t = distance_m / shore_fade_m;
	return vec2(t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t) / shore_fade_m);
}


// Return the unfaded wave height and its exact north/east derivatives. This
// is the core physics sum: amp*sin(k·(north,east) - frequency*time + phase).
float wave_height_raw(vec2 north_east, out vec2 gradient_ne) {
	float height = 0.0;
	gradient_ne = vec2(0.0);
	for (int i = 0; i < 2; i++) {
		if (i >= wave_count) {
			break;
		}
		vec4 wave = wave_params[i];
		float amplitude = wave.x;
		float wavelength = max(wave.y, 0.001);
		float period = max(wave.z, 0.001);
		vec2 direction_ne = vec2(cos(wave.w), sin(wave.w));
		float wave_number = TAU / wavelength;
		float phase = wave_number * dot(direction_ne, north_east)
			- TAU * sim_clock / period + wave_phase_rad[i];
		float sine = sin(phase);
		float cosine = cos(phase);
		height += amplitude * sine;
		gradient_ne += amplitude * wave_number * cosine * direction_ne;
	}
	return height;
}


vec3 lobe_term(vec3 direction_to_camera) {
	float horizontal_length = max(length(direction_to_camera.xz), 1e-4);
	float azimuth_weight = max(dot(direction_to_camera.xz / horizontal_length,
		normalize(lobe_dir.xz + vec2(1e-6, 0.0))), 0.0);
	return lobe_lin * pow(azimuth_weight, lobe_k)
		* exp(-max(asin(clamp(direction_to_camera.y, -1.0, 1.0)), 0.0) / lobe_height);
}


void vertex() {
	vec3 mean_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_ne = vec2(-mean_world_position.z, mean_world_position.x);
	shore_distance_m = UV2.x;
	vec2 ignored_gradient;
	float raw_height = wave_height_raw(world_ne, ignored_gradient);
	VERTEX.y += raw_height * shore_fade_data(shore_distance_m).x;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


float view_depth_at(vec2 screen_uv, mat4 inverse_projection) {
	float raw_depth = textureLod(depth_texture, screen_uv, 0.0).r;
	// Compatibility is OpenGL: depth texture [0,1] maps to NDC Z [-1,1].
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth * 2.0 - 1.0);
	vec4 view_position = inverse_projection * vec4(ndc, 1.0);
	return -view_position.z / max(view_position.w, 1e-6);
}


vec2 shore_distance_gradient_ne(vec2 north_east, float distance_m) {
	// Recover the distance-field gradient from screen derivatives. UV2.x is a
	// linearly interpolated nearest-shore distance on the water mesh.
	vec2 north_east_dx = dFdx(north_east);
	vec2 north_east_dy = dFdy(north_east);
	float distance_dx = dFdx(distance_m);
	float distance_dy = dFdy(distance_m);
	float determinant = north_east_dx.x * north_east_dy.y - north_east_dy.x * north_east_dx.y;
	if (abs(determinant) < 1e-8) {
		return vec2(0.0);
	}
	return vec2(
		(distance_dx * north_east_dy.y - distance_dy * north_east_dx.y) / determinant,
		(north_east_dx.x * distance_dy - north_east_dy.x * distance_dx) / determinant
	);
}


void fragment() {
	vec2 raw_gradient_ne;
	float raw_height = wave_height_raw(world_ne, raw_gradient_ne);
	vec2 shore_fade = shore_fade_data(shore_distance_m);
	vec2 shore_gradient_ne = shore_distance_gradient_ne(world_ne, shore_distance_m);
	vec2 gradient_ne = shore_fade.x * raw_gradient_ne + raw_height * shore_fade.y * shore_gradient_ne;
	vec3 wave_normal_world = normalize(vec3(-gradient_ne.y, 1.0, gradient_ne.x));
	vec3 wave_normal_view = normalize(mat3(VIEW_MATRIX) * wave_normal_world);
	NORMAL = wave_normal_view;

	float surface_depth_view = -VERTEX.z;
	float scene_depth_view = view_depth_at(SCREEN_UV, INV_PROJECTION_MATRIX);
	float water_depth_m = clamp(scene_depth_view - surface_depth_view, 0.0, 12.0);
	float depth_fraction = clamp(water_depth_m / deep_reference_depth_m, 0.0, 1.0);
	float absorption = 1.0 - exp(-water_depth_m * absorption_per_m);
	vec3 depth_tint = mix(shallow_color.rgb, deep_color.rgb, depth_fraction);

	vec2 refracted_uv = SCREEN_UV + wave_normal_view.xy * refraction_strength
		* clamp(water_depth_m / 1.2, 0.0, 1.0);
	refracted_uv = clamp(refracted_uv, vec2(0.001), vec2(0.999));
	if (view_depth_at(refracted_uv, INV_PROJECTION_MATRIX) + 0.015 < surface_depth_view) {
		refracted_uv = SCREEN_UV;
	}
	vec3 scene_color = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	vec3 transmitted_color = mix(scene_color, depth_tint, absorption);

	float fresnel = pow(1.0 - clamp(dot(normalize(wave_normal_view), normalize(VIEW)), 0.0, 1.0), 5.0);
	float transmission = 1.0 - 0.76 * fresnel;
	ALBEDO = mix(depth_tint, transmitted_color, transmission);
	METALLIC = 0.0;
	ROUGHNESS = water_roughness;
	SPECULAR = water_specular;
	ALPHA = 1.0;

	float shore_band = 1.0 - smoothstep(shore_foam_start_m, shore_foam_end_m, max(shore_distance_m, 0.0));
	float crest_weight = smoothstep(-0.015, 0.045, raw_height * shore_fade.x);
	float foam_amount = shore_band * (0.025 + 0.055 * crest_weight);
	ALBEDO = mix(ALBEDO, foam_color.rgb, foam_amount);

	vec3 to_fragment = world_position - CAMERA_POSITION_WORLD;
	float camera_distance = length(to_fragment);
	vec3 view_ray = to_fragment / max(camera_distance, 1e-3);
	vec3 haze = haze_lin + sun_lin * pow(max(dot(view_ray, sun_dir), 0.0), 8.0) * sun_scatter
		+ lobe_term(view_ray);
	FOG = vec4(haze, 1.0 - exp(-beta * camera_distance));
}
