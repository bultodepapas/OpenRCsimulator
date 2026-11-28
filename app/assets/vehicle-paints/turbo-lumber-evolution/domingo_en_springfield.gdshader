shader_type spatial;

uniform int part;
uniform mat3 rest_basis;
uniform vec3 rest_origin;
uniform float grow_amount;
uniform bool detail_enabled;

uniform vec3 sunshine : source_color = vec3(1.00, 0.81, 0.12);
uniform vec3 sky_blue : source_color = vec3(0.24, 0.68, 0.96);
uniform vec3 frosting : source_color = vec3(0.98, 0.34, 0.66);
uniform vec3 cream : source_color = vec3(1.00, 0.99, 0.91);
uniform vec3 ink : source_color = vec3(0.15, 0.10, 0.22);
uniform vec3 violet : source_color = vec3(0.48, 0.30, 0.66);
uniform vec3 biscuit : source_color = vec3(0.92, 0.57, 0.29);

varying vec3 paint_position;
varying vec3 paint_normal;

void vertex() {
	paint_position = rest_basis * VERTEX + rest_origin;
	paint_normal = rest_basis * NORMAL;
	VERTEX += NORMAL * grow_amount;
}

float inside(float edge) {
	return clamp(0.5 - edge / max(fwidth(edge), 1e-6), 0.0, 1.0);
}

vec3 drawing(vec3 background, vec3 fill, float edge, float outline) {
	vec3 outlined = mix(background, ink, inside(edge - outline));
	return mix(outlined, fill, inside(edge));
}

float round_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + radius;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec3 cloud(vec3 background, vec2 p) {
	float d = round_box(p, vec2(0.079, 0.023), 0.022);
	d = min(d, length(p - vec2(-0.043, 0.010)) - 0.025);
	d = min(d, length(p - vec2(-0.007, 0.020)) - 0.036);
	d = min(d, length(p - vec2(0.037, 0.016)) - 0.027);
	vec3 fill = mix(mix(cream, sky_blue, 0.22), cream, smoothstep(-0.026, -0.009, p.y));
	return drawing(background, fill, d, 0.0028);
}

vec3 sprinkle(vec3 background, vec3 sugar, vec2 p, vec2 axis) {
	vec2 center = axis * clamp(dot(p, axis), -0.074, 0.074);
	return mix(background, sugar, inside(length(p - center) - 0.030));
}

vec3 donut(vec3 background, vec2 p) {
	float radius = length(p);
	float ring = max(radius - 1.0, 0.286 - radius);
	vec3 pastry = drawing(background, biscuit, ring, 0.061);
	float a = atan(p.y, p.x);
	float icing = max(radius - (0.84 + 0.045 * sin(7.0 * a + 0.7) + 0.027 * sin(11.0 * a)), 0.36 - radius);
	vec3 icing_color = mix(frosting, cream, 0.21 * smoothstep(-0.1, 0.9, p.y));
	vec3 glazed = drawing(pastry, icing_color, icing, 0.025);
	glazed = sprinkle(glazed, sunshine, p - vec2(-0.37, 0.52), vec2(0.8, 0.6));
	glazed = sprinkle(glazed, cream, p - vec2(0.10, 0.65), vec2(0.2, 0.98));
	glazed = sprinkle(glazed, sky_blue, p - vec2(0.51, 0.38), vec2(0.8, -0.6));
	glazed = sprinkle(glazed, cream, p - vec2(0.61, -0.16), vec2(0.6, 0.8));
	glazed = sprinkle(glazed, sunshine, p - vec2(0.33, -0.55), vec2(0.2, -0.98));
	if (detail_enabled) {
		glazed = sprinkle(glazed, sky_blue, p - vec2(-0.16, -0.62), vec2(0.98, -0.2));
		glazed = sprinkle(glazed, cream, p - vec2(-0.61, -0.22), vec2(0.8, 0.6));
	}
	return sprinkle(glazed, sky_blue, p - vec2(-0.61, 0.15), vec2(0.6, -0.8));
}

vec3 wing(vec3 p, vec3 n) {
	float span = abs(p.x);
	float sweep = span + 0.41 * (p.z - 0.103);
	vec3 c;
	if (n.y < -0.13) {
		c = drawing(sunshine, violet, 0.572 - sweep, 0.0034);
		c = drawing(c, frosting, 0.677 - sweep, 0.0033);
		if (p.x < 0.0) {
			return donut(c, (vec2(span, 0.217 - p.z) - vec2(0.391, 0.106)) / 0.073);
		}
		return cloud(c, (vec2(span, 0.217 - p.z) - vec2(0.363, 0.101)) * 0.91);
	}
	c = drawing(sky_blue, sunshine, p.z - (0.037 + 0.038 * span), 0.0034);
	c = drawing(c, violet, 0.610 - sweep, 0.0034);
	c = drawing(c, frosting, 0.662 - sweep, 0.0034);
	if (p.x > 0.0) {
		c = cloud(c, vec2(span - 0.225, 0.133 - p.z));
		return donut(c, vec2(span - 0.456, 0.121 - p.z) / 0.064);
	}
	c = cloud(c, vec2(span - 0.185, 0.143 - p.z) * 1.30);
	return cloud(c, vec2(span - 0.442, 0.127 - p.z) * 0.94);
}

vec3 fuselage(vec3 p) {
	float sweep = p.y + 0.044 * p.z;
	vec3 c = drawing(sunshine, violet, sweep + 0.053, 0.0027);
	return drawing(c, frosting, p.z + 0.152 - p.y * 0.36, 0.0031);
}

vec3 tail(vec2 p, float tip) {
	float diag = p.x + 0.57 * (p.y - 0.676);
	vec3 c = drawing(sunshine, sky_blue, tip - 0.065 - diag, 0.0031);
	c = drawing(c, frosting, tip - diag, 0.0028);
	return c;
}

vec3 trim(vec3 p, vec3 n) {
	if (part == 4) {
		float angle = p.z + 0.81 * p.y;
		vec3 c = drawing(violet, sky_blue, angle - 0.157, 0.0034);
		float glint = max(0.042 - angle, angle - 0.054);
		return mix(c, cream, 0.82 * inside(glint));
	}
	if (part == 5) {
		return drawing(violet, sunshine, p.z - 0.014 + 0.37 * p.y, 0.0027);
	}
	bool tailwheel = p.z > 0.58;
	vec2 center = tailwheel ? vec2(-0.112, 0.759) : vec2(-0.198, 0.008);
	float radius = length(p.yz - center);
	vec3 c = drawing(ink, frosting, radius - (tailwheel ? 0.009 : 0.038), 0.0017);
	vec3 hub = drawing(c, sunshine, radius - (tailwheel ? 0.003 : 0.014), 0.0015);
	return mix(ink, hub, smoothstep(0.42, 0.77, abs(n.x)));
}

void fragment() {
	vec3 p = paint_position;
	vec3 n = normalize(paint_normal);
	vec3 c;
	if (part == 0) {
		c = wing(p, n);
	} else if (part == 1) {
		c = fuselage(p);
	} else if (part == 2) {
		c = tail(vec2(abs(p.x), p.z), 0.236);
	} else if (part == 3) {
		c = tail(p.yz, 0.111);
	} else {
		c = trim(p, n);
	}
	ALBEDO = c;
	// Keep the flat colours readable with normal aircraft lighting.
	EMISSION = c * 0.045;
	ROUGHNESS = part == 4 ? 0.26 : 0.66;
	SPECULAR = part == 4 ? 0.31 : 0.19;
}
