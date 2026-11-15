shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// A native CylinderMesh is reshaped into nozzle-local +Z exhaust.
// This is an illustrative art shader, not a combustion or nozzle solver.
uniform float burner_actual : hint_range(0.0, 1.0) = 0.0;
// Bounded phases derived on the CPU from the accepted presentation timestamp.
uniform vec4 animation_phase_rad = vec4(0.0);
uniform float nozzle_radius_m = 0.036;
uniform float max_length_m = 0.42;
uniform float core_layer : hint_range(0.0, 1.0) = 0.0;
uniform float shock_strength : hint_range(0.0, 1.0) = 0.25;
uniform float brightness : hint_range(0.0, 4.0) = 1.0;
uniform float phase = 0.0;
uniform vec4 outer_color : source_color = vec4(1.0, 0.30, 0.06, 1.0);
uniform vec4 core_color : source_color = vec4(0.35, 0.55, 1.0, 1.0);

varying float along;

void vertex() {
	along = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	float amount = clamp(burner_actual, 0.0, 1.0);
	float wave = sin(along * 29.0 - animation_phase_rad.x + phase)
		* sin(UV.x * TAU * 3.0 + animation_phase_rad.y + phase);
	float radius_scale = nozzle_radius_m * mix(1.0, 0.48, core_layer);
	radius_scale *= (0.88 + 0.12 * amount) * (1.0 + 0.065 * wave * along);
	float length_scale = max_length_m * mix(0.22, 1.0, sqrt(amount));
	length_scale *= mix(1.0, 0.82, core_layer);
	VERTEX = vec3(VERTEX.x * radius_scale, VERTEX.z * radius_scale, along * length_scale);
	NORMAL = normalize(vec3(NORMAL.x / radius_scale, NORMAL.z / radius_scale, NORMAL.y / length_scale));
}

void fragment() {
	float amount = clamp(burner_actual, 0.0, 1.0);
	// Smooth procedural breakup: no texture dependency and no frame-random input.
	float stream_a = sin(UV.x * TAU * 4.0 - along * 38.0 + animation_phase_rad.z + phase);
	float stream_b = sin(UV.x * TAU * 7.0 + along * 61.0 - animation_phase_rad.w);
	float breakup = clamp(0.76 + 0.15 * stream_a + 0.09 * stream_b, 0.38, 1.0);
	float tip = 1.0 - smoothstep(0.62, 1.0, along);
	float root_fade = mix(smoothstep(0.0, 0.035, along), 1.0, core_layer);
	float soft_shell = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 0.28);
	soft_shell = mix(soft_shell, 1.0, core_layer);
	// Cells remain fixed relative to the nozzle; only small-scale breakup moves.
	float cells = pow(0.5 + 0.5 * cos(along * TAU * 5.2), 10.0);
	float cell_mask = cells * exp(-along * 2.5) * shock_strength * amount;
	float opacity = amount * tip * root_fade * soft_shell * breakup;
	opacity *= mix(0.46, 0.58, core_layer);
	vec3 color = mix(outer_color.rgb, core_color.rgb, core_layer);
	color = mix(color, vec3(0.95, 0.88, 0.72), cell_mask * 0.65);
	// Values intentionally stay readable without an HDR-only effect.
	ALBEDO = color * brightness * (1.0 + cell_mask * 0.65);
	ALPHA = clamp(opacity, 0.0, 0.85);
}
