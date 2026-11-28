shader_type spatial;

// The Extra builder supplies painted-surface coordinates in UV and UV2.
uniform int part;
uniform float cowl_rear_z;
uniform vec3 red : source_color; // Existing Workshop paint slot, here the platinum base.
uniform vec3 graphite : source_color;
uniform vec3 blue : source_color;
uniform vec3 cyan : source_color;
uniform sampler2D decals : source_color, filter_linear_mipmap_anisotropic, repeat_disable;

varying vec3 object_normal;
varying float wing_side;

void vertex() {
	object_normal = NORMAL;
	wing_side = VERTEX.x;
}

float inside(float distance_m) {
	return clamp(0.5 - distance_m / max(fwidth(distance_m), 1e-6), 0.0, 1.0);
}

float band(float position, float start, float end) {
	return inside(max(start - position, position - end));
}

vec3 decal(vec3 base, vec2 p, vec2 cell) {
	// Each cell has transparent margins. Clamp the lookup and mask the box so
	// its neighbouring cells cannot wrap onto distant portions of the airframe.
	vec4 ink = texture(decals, (cell + clamp(p, vec2(0.01), vec2(0.99))) * 0.5);
	float coverage = band(p.x, 0.0, 1.0) * band(p.y, 0.0, 1.0);
	return mix(base, ink.rgb, ink.a * coverage);
}

void fragment() {
	vec3 c = red;
	if (part == 0 || part == 4) { // Wing and aileron, with continuous stripes across the hinge.
		float span = UV.x;
		float chord = UV.y;
		if (object_normal.y >= 0.0) {
			float trailing = 0.77 - 0.16 * span;
			float sweep = span + 0.23 * chord;
			c = mix(c, graphite, inside(trailing - chord));
			c = mix(c, cyan, band(chord, trailing - 0.029, trailing));
			c = mix(c, blue, inside(0.68 - sweep));
			c = mix(c, cyan, band(sweep, 0.68, 0.752));
			c = mix(c, graphite, inside(0.875 - sweep));
			c = mix(c, cyan, band(sweep, 0.875, 0.89));
			if (part == 0 && object_normal.y > 0.35) {
				vec2 marking = vec2((span - 0.293) / 0.283, (chord - 0.13) * UV2.x / 0.1415);
				if (wing_side < 0.0) {
					marking.x = 1.0 - marking.x;
					c = decal(c, marking, vec2(0.0, 1.0));
				} else {
					c = decal(c, marking, vec2(1.0, 0.0));
				}
			}
		} else {
			float sweep = span - 0.09 * chord;
			c = graphite;
			c = mix(c, red, max(band(sweep, 0.23, 0.376), band(sweep, 0.49, 0.642)));
			c = mix(c, cyan, max(band(sweep, 0.37, 0.396), band(sweep, 0.636, 0.662)));
			c = mix(c, blue, inside(0.74 - sweep));
		}
	} else if (part == 1) { // Stabiliser and elevator.
		float sweep = abs(UV.x) + 0.38 * UV.y;
		if (object_normal.y >= 0.0) {
			c = mix(c, graphite, inside(0.016 - UV.y));
			c = mix(c, blue, inside(0.205 - sweep));
			c = mix(c, cyan, band(sweep, 0.205, 0.237));
		} else {
			c = mix(graphite, red, band(sweep, 0.075, 0.169));
			c = mix(c, cyan, band(sweep, 0.164, 0.188));
		}
	} else if (part == 2) { // Fuselage, cowl face and canopy frame.
		float z = UV.y;
		float split = UV.x - (0.012 - 0.075 * clamp((z + 0.18) / 0.55, 0.0, 1.0));
		c = mix(graphite, c, inside(-split));
		c = mix(c, blue, band(split, -0.052, 0.014));
		c = mix(c, cyan, band(split, 0.006, 0.014));
		// Dark cowl front and tapered cheek panel.
		float nose = z + 0.19 * UV.x;
		c = mix(c, cyan, inside(nose + 0.271));
		c = mix(c, graphite, inside(nose + 0.298));
		float flank = abs(object_normal.x);
		if (flank > 0.52) {
			float u = (z - 0.355) / 0.304;
			if (object_normal.x > 0.0) {
				u = 1.0 - u;
			}
			vec2 marking = vec2(u, (0.090 - UV.x) / 0.152);
			c = mix(c, decal(c, marking, vec2(0.0, 0.0)), smoothstep(0.52, 0.73, flank));
		}
		c *= mix(1.0, 0.55, inside(abs(z - cowl_rear_z) - 0.00045));
	} else if (part == 3) { // Fin and rudder.
		float sweep = UV.x + 0.65 * UV.y;
		c = mix(c, blue, inside(0.16 - sweep));
		c = mix(c, cyan, band(sweep, 0.158, 0.194));
		c = mix(c, graphite, inside(0.234 - sweep));
		c = mix(c, cyan, band(sweep, 0.234, 0.244));
	} else { // Cooling-opening lips.
		c = mix(graphite, red, 0.06);
	}
	ALBEDO = c;
	ROUGHNESS = 0.38;
}
