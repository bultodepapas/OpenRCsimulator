shader_type spatial;

uniform int part;
uniform mat3 rest_basis;
uniform vec3 rest_origin;
uniform float grow_amount;
uniform bool detail_enabled;

varying vec3 glass_position;
varying vec3 glass_normal;

// Linear colour and frost density. The leaded joints use the top of the frost range.
const vec4 COBALT = vec4(0.016, 0.090, 0.345, 0.09);
const vec4 AQUA = vec4(0.011, 0.306, 0.273, 0.21);
const vec4 ICE = vec4(0.375, 0.713, 0.677, 0.75);
const vec4 SMOKE = vec4(0.034, 0.047, 0.103, 0.12);
const vec4 AMBER = vec4(0.725, 0.302, 0.032, 0.18);
const vec4 RUBY = vec4(0.529, 0.038, 0.136, 0.15);
const vec4 LEAD = vec4(0.036, 0.047, 0.058, 1.0);

void vertex() {
	glass_position = rest_basis * VERTEX + rest_origin;
	glass_normal = rest_basis * NORMAL;
	VERTEX += NORMAL * grow_amount;
}

float inside(float distance) {
	return clamp(0.5 - distance / max(fwidth(distance), 1e-6), 0.0, 1.0);
}

vec4 pane(vec4 background, vec4 inset, float edge) {
	// A fine bevel catches the light just inside each leaded joint.
	vec4 result = mix(background, inset, inside(edge));
	result.rgb *= 1.0 + 0.24 * inside(abs(edge) - 0.0037);
	return mix(result, LEAD, inside(abs(edge) - 0.00145));
}

vec4 wing(vec3 p, vec3 n) {
	float span = abs(p.x);
	float sweep = span + 0.62 * (p.z - 0.104);
	vec4 result;
	if (n.y < -0.13) {
		// Larger blocks and warm tips separate the underside from the upper face in flight.
		result = pane(COBALT, ICE, max(0.165 - sweep, sweep - 0.298));
		result = pane(result, AQUA, max(0.376 - sweep, sweep - 0.520));
		result = pane(result, AMBER, 0.574 - sweep);
		return pane(result, RUBY, 0.659 - sweep);
	}
	result = pane(AQUA, COBALT, p.z - (0.058 + 0.12 * span));
	float kite = abs(span - 0.300) * 0.25 + abs(p.z - 0.104 + 0.10 * (span - 0.300));
	result = pane(result, ICE, kite - 0.050);
	result = pane(result, SMOKE, 0.183 + 0.014 * span - p.z);
	result = pane(result, AMBER, 0.572 - sweep);
	result = pane(result, RUBY, 0.628 - sweep);
	return pane(result, SMOKE, 0.735 - sweep);
}

vec4 body(vec3 p) {
	float shoulder = p.y + 0.16 * abs(p.x);
	vec4 result = pane(SMOKE, COBALT, 0.034 - shoulder + 0.12 * (p.z - 0.23));
	result = pane(result, AQUA, shoulder + 0.046 + 0.041 * p.z);
	float lozenge = abs(p.z - 0.414) * 0.24 + abs(shoulder + 0.017 + 0.012 * p.z);
	result = pane(result, ICE, lozenge - 0.044);
	result = pane(result, AQUA, lozenge - 0.031);
	float nose = p.z - 0.27 * shoulder;
	result = pane(result, AMBER, nose + 0.116);
	return pane(result, RUBY, nose + 0.156);
}

vec4 tail(vec2 p, float outer) {
	float sweep = p.x + 0.56 * (p.y - 0.679);
	vec4 result = pane(COBALT, AQUA, p.y - 0.678 - 0.17 * p.x);
	result = pane(result, ICE, outer - 0.045 - sweep);
	return pane(result, RUBY, outer - sweep);
}

vec4 trim(vec3 p, vec3 n) {
	if (part == 5) {
		return pane(SMOKE, AMBER, p.z - 0.013 + 0.37 * p.y);
	}
	bool tailwheel = p.z > 0.58;
	vec2 hub = tailwheel ? vec2(-0.112, 0.759) : vec2(-0.198, 0.008);
	float radius = length(p.yz - hub);
	if (abs(n.x) > 0.5) {
		vec4 wheel = pane(SMOKE, AQUA, radius - (tailwheel ? 0.009 : 0.037));
		return pane(wheel, ICE, radius - (tailwheel ? 0.004 : 0.016));
	}
	return SMOKE;
}

void fragment() {
	vec3 p = glass_position;
	vec3 n = normalize(glass_normal);
	vec4 finish;
	if (part == 0) {
		finish = wing(p, n);
	} else if (part == 1) {
		finish = body(p);
	} else if (part == 2) {
		finish = tail(vec2(abs(p.x), p.z), 0.220);
	} else if (part == 3) {
		finish = tail(p.yz, 0.105);
	} else {
		finish = trim(p, n);
	}
	float lead = smoothstep(0.77, 0.96, finish.a);
	float frost = min(finish.a, 0.75);
	vec3 normal = normalize(NORMAL);
	vec3 reflected = mat3(INV_VIEW_MATRIX) * reflect(-VIEW, normal);
	float facing = clamp(dot(normal, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 4.0);
	float ripple = 0.0;
	if (detail_enabled) {
		// Broad rolled-glass waves fade as their wavelength approaches a pixel.
		float phase = dot(p, vec3(77.0, 116.0, 194.0)) + 2.0 * sin(dot(p, vec3(42.0, 18.0, -37.0)));
		ripple = sin(phase) * (1.0 - smoothstep(0.55, 2.4, fwidth(phase))) * (1.0 - lead);
	}
	float horizon = exp2(-abs(reflected.y + 0.06 + ripple * 0.035) * mix(14.0, 5.5, frost));
	float sky = smoothstep(-0.24, 0.64, reflected.y);
	float sheen = (0.09 * horizon + 0.28 * fresnel * sky) * (1.0 - lead) * (1.0 - 0.64 * frost);
	// Tinted depth and a soft reflected horizon sell the glass in Compatibility too.
	ALBEDO = finish.rgb * (0.80 + 0.20 * facing + 0.055 * ripple) + sheen * vec3(0.40, 0.64, 0.85);
	ROUGHNESS = mix(0.075 + 0.57 * frost + 0.026 * ripple, 0.52, lead);
	METALLIC = 0.24 * lead;
	SPECULAR = mix(0.58, 0.26, lead);
	CLEARCOAT = (1.0 - lead) * (1.0 - frost) * 0.78;
	CLEARCOAT_ROUGHNESS = 0.12 + 0.32 * frost;
	BACKLIGHT = finish.rgb * (0.32 - 0.20 * lead);
}
