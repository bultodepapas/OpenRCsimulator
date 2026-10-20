// LU-28: bounded countryside surface, one shared material for spatial batches.
// UV is measured in metres: (cross-road, along-road). UV2 is (kind, full width m).
// COLOR carries the palette in sRGB. The three photo maps contribute luminance only.
shader_type spatial;
render_mode cull_back;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

// Physical source footprints: Grass001 1.4 m, Dirt 2 m, Aerial Asphalt 01 30 m.
uniform float grass_tile_m = 1.4;
uniform float soil_tile_m = 2.0;
uniform float asphalt_tile_m = 30.0;

// LU-16 shared directional haze. Keep defaults and fragment equations aligned
// with app/render/landscape_upgrade/ridge_haze.gdshader.
uniform vec3 haze_lin = vec3(0.584, 0.768, 0.846);
uniform vec3 sun_dir = vec3(0.0, 0.707, 0.707);
uniform vec3 sun_lin = vec3(3.14159);
uniform float sun_scatter = 0.0;
uniform vec3 lobe_lin = vec3(0.0);
uniform vec3 lobe_dir = vec3(1.0, 0.0, 0.0);
uniform float lobe_k = 8.0;
uniform float lobe_height = 1.5708;
uniform float beta = 0.00017;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Bounded projected offset: keep X/Y coverage at the unbiased render position
	// while separating flat overlays from the 21 km depth buffer at aerial distance.
	vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float offset_m = min(6.0, view_position.z * view_position.z * 0.0000015);
	float priority = UV2.x >= 2.0 ? 1.15 : 1.0;
	view_position.xyz *= max(0.0, 1.0 - offset_m * priority / max(length(view_position.xyz), 0.01));
	POSITION = PROJECTION_MATRIX * view_position;
}

float luminance(vec3 linear_rgb) {
	return dot(linear_rgb, vec3(0.2126, 0.7152, 0.0722));
}

// Keep photographic color from replacing the field palette; use it only as
// restrained, mip-filtered luminance variation.
float photo_value(vec3 linear_rgb) {
	return mix(0.86, 1.14, clamp(luminance(linear_rgb) * 2.0, 0.0, 1.0));
}

// Coverage-filtered periodic stripes fade to their mean coverage below pixel
// resolution, avoiding row and dash flicker as the camera moves away.
float band_integral(float coordinate, float period, float band_width) {
	return floor(coordinate / period) * band_width + clamp(mod(coordinate, period), 0.0, band_width);
}

float periodic_band(float coordinate, float period, float band_width) {
	float span = max(fwidth(coordinate), 1e-4);
	float centre = coordinate + band_width * 0.5;
	return clamp((band_integral(centre + span * 0.5, period, band_width)
		- band_integral(centre - span * 0.5, period, band_width)) / span, 0.0, 1.0);
}

float solid_line(float cross_m, float center_m, float width_m) {
	float span = max(fwidth(cross_m), 1e-4);
	return clamp((min(cross_m + span * 0.5, center_m + width_m * 0.5)
		- max(cross_m - span * 0.5, center_m - width_m * 0.5)) / span, 0.0, 1.0);
}

float symmetric_line(float cross_m, float center_m, float width_m) {
	return clamp(solid_line(cross_m, center_m, width_m)
		+ solid_line(cross_m, -center_m, width_m), 0.0, 1.0);
}

void fragment() {
	float kind = floor(UV2.x + 0.5);
	float full_width_m = max(UV2.y, 0.001);
	float cross_m = UV.x;
	float along_m = UV.y;
	vec3 palette = COLOR.rgb;
	vec3 albedo = palette;
	vec3 paint = vec3(0.62, 0.61, 0.55);

	if (kind < 0.5) {
		vec3 grass = texture(grass_tex, vec2(cross_m, along_m) / max(grass_tile_m, 0.001)).rgb;
		albedo *= photo_value(grass);
		// A second, broad photographic footprint breaks up otherwise uniform fields.
		float broad = texture(grass_tex, (world_pos.xz + vec2(417.0, 783.0)) / 85.0).g;
		albedo *= 0.83 + 0.50 * broad;

		float rows = periodic_band(cross_m, 0.9, 0.10);
		float tram_left = periodic_band(cross_m, 14.0, 0.20);
		float tram_right = periodic_band(cross_m - 0.55, 14.0, 0.20);
		float tramlines = clamp(tram_left + tram_right, 0.0, 1.0);
		albedo *= 1.0 - 0.08 * rows - 0.18 * tramlines;
	} else if (kind < 1.5) {
		vec3 soil = texture(soil_tex, vec2(cross_m, along_m) / max(soil_tile_m, 0.001)).rgb;
		albedo *= photo_value(soil);
		albedo *= 0.86 + 0.42 * texture(soil_tex, world_pos.xz / 48.0).r;
		float furrows = periodic_band(cross_m, 1.4, 0.16);
		albedo *= 1.0 - 0.16 * furrows;
	} else if (kind < 2.5) {
		vec3 asphalt = texture(asphalt_tex,
			vec2(cross_m, along_m) / max(asphalt_tile_m, 0.001)).rgb;
		vec3 road = palette * photo_value(asphalt);
		float median = 1.0 - smoothstep(2.0 - max(fwidth(cross_m), 1e-4),
			2.0 + max(fwidth(cross_m), 1e-4), abs(cross_m));
		vec3 grass = texture(grass_tex, vec2(cross_m, along_m) / max(grass_tile_m, 0.001)).rgb;
		vec3 median_palette = vec3(0.29, 0.34, 0.19);
		albedo = mix(road, median_palette * photo_value(grass), median);

		float half_width = full_width_m * 0.5;
		float shoulder = smoothstep(11.0 - max(fwidth(cross_m), 1e-4),
			11.0 + max(fwidth(cross_m), 1e-4), abs(cross_m));
		albedo *= mix(1.0, 0.91, shoulder);

		float solid = symmetric_line(cross_m, 2.5, 0.14)
			+ symmetric_line(cross_m, min(11.0, half_width), 0.16);
		float dashed = symmetric_line(cross_m, 6.5, 0.14)
			* periodic_band(along_m, 9.0, 3.0);
		albedo = mix(albedo, paint, clamp(solid + dashed, 0.0, 1.0));
	} else if (kind < 3.5) {
		vec3 asphalt = texture(asphalt_tex,
			vec2(cross_m, along_m) / max(asphalt_tile_m, 0.001)).rgb;
		albedo *= photo_value(asphalt);
		float edges = symmetric_line(cross_m, min(2.9, full_width_m * 0.5), 0.13);
		float center = solid_line(cross_m, 0.0, 0.11)
			* periodic_band(along_m, 9.0, 3.0);
		albedo = mix(albedo, paint, clamp(edges + center, 0.0, 1.0));
	} else {
		vec3 soil = texture(soil_tex, vec2(cross_m, along_m) / max(soil_tile_m, 0.001)).rgb;
		albedo *= photo_value(soil);
	}

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	vec3 to_frag = world_pos - CAMERA_POSITION_WORLD;
	float d = length(to_frag);
	vec3 v = to_frag / max(d, 1e-3);
	float h = max(length(v.xz), 1e-4);
	float az = max(dot(v.xz / h, normalize(lobe_dir.xz + vec2(1e-6, 0.0))), 0.0);
	vec3 lobe = lobe_lin * pow(az, lobe_k) * exp(-max(asin(clamp(v.y, -1.0, 1.0)), 0.0) / lobe_height);
	vec3 haze = haze_lin + sun_lin * pow(max(dot(v, sun_dir), 0.0), 8.0) * sun_scatter + lobe;
	FOG = vec4(haze, 1.0 - exp(-beta * d));
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * max(dot(NORMAL, LIGHT), 0.0) * (1.0 / PI) * ATTENUATION;
}
