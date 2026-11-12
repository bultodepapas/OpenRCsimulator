// DR-32 gate number plate: a rounded plate with a white rim, sized by its instance scale (a QuadMesh scaled to the
// plate in the plate MultiMesh), so the rim and corners keep their size on every plate.
shader_type spatial;
render_mode cull_back;

uniform vec4 plate_color : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 rim_color : source_color = vec4(0.93, 0.93, 0.93, 1.0);
uniform float rim_m = 0.014;
uniform float corner_m = 0.035;

varying vec2 plate_size;

void vertex() {
	plate_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

void fragment() {
	vec2 p = (UV - 0.5) * plate_size;
	vec2 q = abs(p) - (0.5 * plate_size - corner_m);
	// Rounded-rectangle distance, negative inside.
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_m;
	// Derivative before the discard (undefined after it on GLSL ES).
	float fw = max(fwidth(d), 1.0e-5);
	if (d > 0.0) {
		discard;
	}
	float rim = smoothstep(-rim_m - fw, -rim_m, d);
	ALBEDO = mix(plate_color.rgb, rim_color.rgb, rim);
	ROUGHNESS = mix(0.6, 0.4, rim);
}
