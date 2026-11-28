shader_type spatial;
render_mode cull_disabled;

uniform vec4 exterior_color : source_color;
uniform float exterior_roughness = 0.48;
uniform float exterior_metallic = 0.0;
uniform float exterior_clearcoat = 0.25;
uniform float exterior_clearcoat_roughness = 0.28;
uniform vec3 inside_axis;
uniform vec4 panel_bounds;
uniform bool brushed = true;

uniform vec4 liner : source_color = vec4(0.30, 0.42, 0.53, 1.0);
uniform vec4 edge : source_color = vec4(0.12, 0.18, 0.25, 1.0);
uniform vec4 alloy : source_color = vec4(0.62, 0.72, 0.78, 1.0);
uniform vec4 amber : source_color = vec4(0.81, 0.59, 0.32, 1.0);

varying vec3 local_normal;
varying vec2 panel_point;

void vertex() {
	// The mesh-local orientation turns with the retract. Both faces have geometry.
	local_normal = NORMAL;
	panel_point = abs(inside_axis.x) > 0.5 ? VERTEX.zy : VERTEX.xz;
}

void fragment() {
	float inner = smoothstep(0.18, 0.76, dot(normalize(local_normal), inside_axis));
	vec2 uv = (panel_point - panel_bounds.xy) / (panel_bounds.zw - panel_bounds.xy);
	vec2 margin = min(uv, vec2(1.0) - uv);
	float edge_distance = min(margin.x, margin.y);
	float field = smoothstep(0.045, 0.115, edge_distance);
	float gasket = 1.0 - smoothstep(0.008, 0.018, abs(edge_distance - 0.075));
	float bead = 1.0 - smoothstep(0.007, 0.015, abs(edge_distance - 0.103));
	float rib_distance = abs(uv.x - 0.5) - 0.19;
	float ribs = 1.0 - smoothstep(0.024, 0.050, abs(rib_distance));
	ribs *= smoothstep(0.14, 0.22, uv.y) * (1.0 - smoothstep(0.78, 0.86, uv.y)) * field;
	float stamp = 1.0 - smoothstep(0.011, 0.026, abs(uv.y - 0.20 - 0.12 * (uv.x - 0.5)));
	stamp *= (1.0 - smoothstep(0.14, 0.19, abs(uv.x - 0.5))) * field;
	vec3 inside_color = mix(edge.rgb, liner.rgb, field);
	inside_color = mix(inside_color, edge.rgb * 0.72, 0.58 * gasket);
	inside_color = mix(inside_color, alloy.rgb, 0.29 * bead);
	inside_color = mix(inside_color, alloy.rgb, 0.66 * ribs);
	inside_color *= 1.0 - 0.18 * ribs * smoothstep(0.001, 0.031, rib_distance);
	// Fold the pattern coordinates about the centre to place four captive heads.
	vec2 pin = abs(uv - 0.5) - vec2(0.329, 0.332);
	vec2 panel_size = panel_bounds.zw - panel_bounds.xy;
	pin *= panel_size / min(panel_size.x, panel_size.y);
	float pin_distance = length(pin);
	float socket = 1.0 - smoothstep(0.031, 0.043, pin_distance);
	float head = 1.0 - smoothstep(0.020, 0.031, pin_distance);
	float slot = (1.0 - smoothstep(0.004, 0.011, abs(pin.y + 0.65 * pin.x))) * head;
	inside_color = mix(inside_color, edge.rgb * 0.57, socket);
	inside_color = mix(inside_color, alloy.rgb * 0.81, head);
	inside_color = mix(inside_color, edge.rgb, slot);
	if (brushed) {
		float grain = 77.0 * uv.x + 5.0 * uv.y;
		float contrast = 1.0 - smoothstep(0.12, 0.48, fwidth(grain));
		inside_color *= 1.0 + 0.045 * contrast * sin(6.283185 * grain);
	}
	inside_color = mix(inside_color, amber.rgb, 0.87 * stamp);
	ALBEDO = mix(exterior_color.rgb, inside_color, inner);
	METALLIC = mix(exterior_metallic, mix(0.26, 0.56, max(ribs, head)), inner);
	float inner_roughness = mix(0.57, 0.36, max(ribs, bead));
	inner_roughness = mix(inner_roughness, mix(0.75, 0.29, head), socket);
	ROUGHNESS = mix(exterior_roughness, inner_roughness, inner);
	CLEARCOAT = exterior_clearcoat * (1.0 - inner);
	CLEARCOAT_ROUGHNESS = exterior_clearcoat_roughness;
}
