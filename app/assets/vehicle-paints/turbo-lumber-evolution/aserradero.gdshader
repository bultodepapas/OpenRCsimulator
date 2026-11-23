shader_type spatial;

uniform int part;
uniform mat3 rest_basis;
uniform vec3 rest_origin;
uniform float grow_amount;
uniform bool detail_enabled;
uniform sampler2D wood_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D stamp : filter_linear_mipmap_anisotropic, repeat_disable;

varying vec3 rest_position;
varying vec3 rest_normal;

const int MAPLE = 0;
const int WALNUT = 1;
const int CHERRY = 2;
const int MAHOGANY = 3;

void vertex() {
	// The neutral projection stays attached when a hinge moves.
	rest_position = rest_basis * VERTEX + rest_origin;
	rest_normal = rest_basis * NORMAL;
	VERTEX += NORMAL * grow_amount;
}

float inside(float d) {
	return clamp(0.5 - d / max(fwidth(d), 0.000001), 0.0, 1.0);
}

float band(float x, float a, float b) {
	return inside(max(a - x, x - b));
}

vec3 grain(vec2 p, int species) {
	// Mirror each board into the next one. Eight edge texels in the baked atlas
	// keep the footprint away from the neighbouring species at a distance.
	vec2 uv = 1.0 - abs(mod(p, 2.0) - 1.0);
	vec2 cell = vec2(float(species % 2), float(species / 2));
	return texture(wood_atlas, (cell + (vec2(8.5) + 495.0 * uv) / 512.0) * 0.5).rgb;
}

float billet_joint(float across, float width) {
	return inside(abs(fract(across / width + 0.5) - 0.5) * width - 0.00055);
}

vec3 end_grain(vec2 p, vec2 center, int species) {
	vec2 offset = p - center;
	float r = length(offset) + 0.0016 * sin(offset.x * 104.0) * sin(offset.y * 96.0);
	float fine = 0.76 + 0.24 * smoothstep(-0.92, -0.31, sin(r * 925.0 + 0.1 * sin(r * 181.0)));
	return grain(p * 8.0 + vec2(0.21, 0.44), species) * fine;
}

vec3 dowel(vec3 c, vec2 p, float radius) {
	float d = length(p);
	vec3 plug = end_grain(p * 1.4, vec2(-0.0015, 0.002), WALNUT) * 1.22;
	c *= 1.0 - 0.34 * inside(d - radius - 0.0006);
	return mix(c, plug, inside(d - radius));
}

vec3 wing(vec3 p, vec3 n) {
	float span = abs(p.x);
	float sweep = span + 0.42 * (p.z - 0.075);
	vec2 uv = vec2(span * 1.23, p.z * 3.25 + p.y * 1.7);
	vec3 light = grain(uv, MAPLE);
	vec3 dark = grain(uv + vec2(0.04, 0.31), WALNUT);
	if (n.y < -0.16) {
		float beams = max(band(sweep, 0.18, 0.29), band(sweep, 0.405, 0.53));
		vec3 c = mix(light, dark, beams);
		c = mix(c, grain(uv, CHERRY), inside(0.592 - sweep));
		return c * (1.0 - 0.20 * billet_joint(p.z + 0.003, 0.039));
	}
	vec3 c = mix(light, grain(uv, CHERRY), inside(0.482 - sweep));
	c = mix(c, dark, max(band(sweep, 0.471, 0.502), inside(p.z - 0.021)));
	c = mix(c, light, max(band(sweep, 0.507, 0.515), band(sweep, 0.528, 0.532)));
	c = mix(c, grain(uv + vec2(0.21, 0.0), MAHOGANY), inside(0.702 - sweep));
	c *= 1.0 - 0.28 * billet_joint(p.z - 0.019, 0.043);
	if (n.y > 0.35 && span > 0.110 && span < 0.700) {
		float along = (fract((span - 0.018) / 0.108) - 0.5) * 0.108;
		c = dowel(c, vec2(along, p.z - 0.120), 0.0040);
	}
	return c;
}

vec3 fuselage(vec3 p, vec3 n) {
	float side = abs(p.x);
	float plank = p.y + 0.029 * clamp((p.z - 0.02) / 0.56, 0.0, 1.0);
	vec2 uv = vec2(p.z * 1.24, (p.y + side * 0.85) * 4.2 + 0.52);
	vec3 walnut = grain(uv, WALNUT) * 1.18;
	vec3 maple = grain(uv + vec2(0.28, 0.0), MAPLE);
	vec3 c = mix(walnut, grain(uv, CHERRY), inside(0.032 - plank));
	c = mix(c, maple, max(band(plank, -0.066, -0.053), band(plank, 0.027, 0.031)));
	// Curved laminations on the cowling meet the growth rings at the nose.
	float scarf = p.z - 0.23 * p.y;
	if (p.z < -0.135) {
		float layers = band(plank, -0.054, -0.037) + band(plank, -0.019, 0.005);
		vec3 cowl = mix(grain(uv, MAHOGANY), maple, clamp(layers, 0.0, 1.0));
		float end_face = smoothstep(0.42, 0.79, -n.z) * inside(p.z + 0.201);
		cowl = mix(cowl, end_grain(p.xy, vec2(-0.016, 0.005), MAPLE), end_face);
		c = mix(c, cowl, inside(scarf + 0.158));
	}
	c *= 1.0 - 0.26 * billet_joint(plank + 0.021, 0.034);
	if (abs(n.x) > 0.50 && p.z > 0.222 && p.z < 0.546) {
		float u = (p.z - 0.231) / 0.307;
		if (n.x > 0.0) {
			u = 1.0 - u;
		}
		vec2 uv_stamp = vec2(u, (0.025 - p.y) / 0.092);
		float panel = band(uv_stamp.x, 0.022, 0.978) * band(uv_stamp.y, 0.055, 0.935);
		float coverage = panel * smoothstep(0.50, 0.71, abs(n.x));
		float mark = texture(stamp, clamp(uv_stamp, vec2(0.0), vec2(1.0))).r;
		c = mix(c, maple * 0.78 * (1.0 - 0.78 * mark), coverage);
	}
	return c;
}

vec3 tail(vec3 p, bool upright) {
	vec2 uv = upright ? vec2(p.y * 4.1, p.z * 4.5) : vec2(abs(p.x) * 2.8, p.z * 5.0);
	float cut = upright ? p.y + 0.42 * (p.z - 0.65) : abs(p.x) + 0.34 * (p.z - 0.69);
	float beyond = upright ? 0.095 : 0.170;
	vec3 maple = grain(uv, MAPLE);
	vec3 c = mix(maple, grain(uv, MAHOGANY), inside(beyond - cut));
	c = mix(c, grain(uv, WALNUT), band(cut, beyond - 0.014, beyond + 0.019));
	c = mix(c, maple, band(cut, beyond + 0.025, beyond + 0.029));
	return c * (1.0 - 0.26 * billet_joint(upright ? p.z : p.z + p.x * 0.002, 0.037));
}

void fragment() {
	vec3 p = rest_position;
	vec3 n = normalize(rest_normal);
	vec3 c;
	float finish = 0.38;
	if (part == 0) {
		c = wing(p, n);
	} else if (part == 1) {
		c = fuselage(p, n);
	} else if (part == 2 || part == 3) {
		c = tail(p, part == 3);
	} else if (part == 4) { // Smoked veneer over the canopied section.
		float rib = max(band(p.z, 0.038, 0.045), band(p.z, 0.151, 0.157));
		vec2 uv = vec2(p.z * 2.4, (abs(p.x) + p.y) * 5.0);
		c = mix(grain(uv, WALNUT) * 0.73, grain(uv, MAPLE), rib);
		finish = 0.30;
	} else if (part == 5) { // Cut hardwood struts.
		vec2 uv = vec2(-p.y * 5.4, p.x * 7.0 + p.z * 4.0);
		c = mix(grain(uv, CHERRY), grain(uv, MAPLE), band(p.z, 0.015, 0.022));
	} else { // Wooden wheels, with dark rims and exposed end grain.
		float broadside = smoothstep(0.37, 0.77, abs(n.x));
		bool tailwheel = p.z > 0.58;
		vec2 center = tailwheel ? vec2(-0.112, 0.759) : vec2(-0.198, 0.008);
		vec2 wheel = p.yz - center;
		float hub = inside(length(wheel) - (tailwheel ? 0.008 : 0.036));
		c = mix(grain(p.yz * 10.0, WALNUT) * 0.79, end_grain(p.yz, center, MAPLE), broadside * hub);
		c = dowel(c, wheel, tailwheel ? 0.0025 : 0.008);
		finish = 0.53;
	}
	ALBEDO = c;
	METALLIC = 0.0;
	SPECULAR = 0.28;
	float grain_luminance = dot(c, vec3(0.2126, 0.7152, 0.0722));
	ROUGHNESS = finish + (detail_enabled ? 0.12 * (0.30 - grain_luminance) : 0.0);
}
