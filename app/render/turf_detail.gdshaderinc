// L9e: two explicit-gradient samples of packed linear turf data (ours, MIT).
// Decorrelation retains world orientation: rotating UVs would also require rotating slopes.
// Slopes are averaged before normalization; unresolved blades return to the old flat material.
uniform sampler2D turf_detail : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float turf_detail_strength : hint_range(0.0, 1.0) = 0.0;

vec3 turf_sample(vec2 p, vec2 gx, vec2 gy) {
	vec2 uv = p * 0.5; // Generated tile spans 2 m; dimensions are artistic estimates.
	float k = vnoise(p * 0.37 + 83.0) * 8.0;
	float index = floor(k);
	vec3 a = textureGrad(turf_detail, uv + hash22(vec2(index, 71.0)), gx * 0.5, gy * 0.5).rgb;
	vec3 b = textureGrad(turf_detail, uv + hash22(vec2(index + 1.0, 71.0)), gx * 0.5, gy * 0.5).rgb;
	return mix(a, b, smoothstep(0.2, 0.8, fract(k)));
}

float turf_weight(vec2 gx, vec2 gy, float distance_m) {
	// Use the major footprint at grazing angles; MSAA does not filter shader detail.
	float footprint = max(length(gx), length(gy));
	return clamp(turf_detail_strength, 0.0, 1.0)
		* (1.0 - smoothstep(0.015, 0.08, footprint))
		* (1.0 - smoothstep(60.0, 110.0, distance_m));
}
