shader_type spatial;

uniform int part;
uniform mat3 rest_basis;
uniform vec3 rest_origin;
uniform sampler2D decals : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 silver : source_color;
uniform vec3 charcoal : source_color;
uniform vec3 red : source_color;
uniform vec3 green : source_color;

uniform bool detail_enabled;
uniform sampler2D foam_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 foam_scale;
uniform vec3 foam_offset;
uniform float foam_sharpness;
uniform float normal_strength;
uniform float roughness_value;
uniform float metallic_value;
uniform float specular_value;
uniform float grow_amount;

varying vec3 paint_position;
varying vec3 paint_normal;
varying vec3 foam_weights;
varying vec3 foam_position;

void vertex() {
	// Project in the neutral airframe so the graphics move with each surface.
	paint_position = rest_basis * VERTEX + rest_origin;
	paint_normal = normalize(rest_basis * NORMAL);
	if (detail_enabled) {
		vec3 n = abs(NORMAL);
		TANGENT = normalize(vec3(n.y + n.z, 0.0, -n.x));
		BINORMAL = normalize(vec3(0.0, n.x + n.z, -n.y));
		foam_weights = pow(n, vec3(foam_sharpness));
		foam_weights /= max(dot(foam_weights, vec3(1.0)), 0.000001);
		foam_position = (VERTEX * foam_scale + foam_offset) * vec3(1.0, -1.0, 1.0);
	}
	VERTEX += NORMAL * grow_amount;
}

vec4 projected(sampler2D image, vec3 weights, vec3 p) {
	return texture(image, p.xy) * weights.z + texture(image, p.xz) * weights.y
		+ texture(image, p.zy * vec2(-1.0, 1.0)) * weights.x;
}

float inside(float d) {
	return clamp(0.5 - d / max(fwidth(d), 1e-6), 0.0, 1.0);
}

float band(float p, float start, float end) {
	return inside(max(start - p, p - end));
}

vec3 decal(vec3 base, vec2 p, vec2 cell) {
	vec4 ink = texture(decals, (cell + clamp(p, vec2(0.01), vec2(0.99))) * 0.5);
	return mix(base, ink.rgb, ink.a * band(p.x, 0.0, 1.0) * band(p.y, 0.0, 1.0));
}

vec3 wing_paint(vec3 p, vec3 n) {
	float span = abs(p.x);
	float sweep = span + 0.54 * (p.z - 0.075);
	if (n.y < -0.16) {
		vec3 c = mix(charcoal, silver, max(band(sweep, 0.19, 0.33), band(sweep, 0.43, 0.53)));
		c = mix(c, red, band(sweep, 0.53, 0.554));
		return mix(c, red, inside(0.68 - sweep));
	}
	vec3 c = mix(silver, charcoal, inside(0.146 - p.z + 0.026 * span));
	c = mix(c, charcoal, band(sweep, 0.532, 0.588));
	c = mix(c, red, inside(0.588 - sweep));
	c = mix(c, silver, max(band(sweep, 0.605, 0.613), band(sweep, 0.623, 0.631)));
	if (n.y > 0.44) {
		vec2 mark = vec2((span - 0.185) / 0.318, (p.z - 0.024) / 0.112);
		if (p.x < 0.0) {
			mark.x = 1.0 - mark.x;
			c = decal(c, mark, vec2(1.0, 0.0));
		} else {
			c = decal(c, mark, vec2(0.0, 1.0));
		}
	}
	return c;
}

vec3 body_paint(vec3 p, vec3 n) {
	float shoulder = p.z - 0.54 * p.y;
	float sill = p.y + 0.071 + 0.019 * clamp((p.z - 0.18) / 0.40, 0.0, 1.0);
	float aft = inside(0.191 - shoulder);
	vec3 c = mix(silver, charcoal, aft * inside(-sill));
	c = mix(c, charcoal, inside(shoulder + 0.142));
	c = mix(c, red, max(band(shoulder, -0.161, -0.148), aft * band(sill, -0.010, -0.001)));
	float flank = abs(n.x);
	// Three short silver ribs bring the servo's cooling fins onto the lower cheek.
	float fin = p.z + 0.40 * (p.y + 0.053);
	float ribs = max(max(band(p.y, -0.070, -0.065), band(p.y, -0.060, -0.055)), band(p.y, -0.050, -0.045));
	c = mix(c, charcoal, band(fin, -0.132, 0.129) * band(p.y, -0.076, -0.038) * smoothstep(0.4, 0.7, flank));
	c = mix(c, silver * 0.78, band(fin, -0.122, 0.116) * ribs * smoothstep(0.4, 0.7, flank));
	// The left and right flanks face opposite ways in the same body coordinates.
	float u = (p.z - 0.236) / 0.283;
	if (n.x > 0.0) {
		u = 1.0 - u;
	}
	vec2 mark = vec2(u, (0.030 - p.y) / 0.104);
	return mix(c, decal(c, mark, vec2(0.0)), smoothstep(0.51, 0.76, flank));
}

void fragment() {
	vec3 p = paint_position;
	vec3 n = normalize(paint_normal);
	vec3 c;
	if (part == 0) {
		c = wing_paint(p, n);
	} else if (part == 1) {
		c = body_paint(p, n);
	} else if (part == 2) {
		float sweep = abs(p.x) + 0.55 * (p.z - 0.69);
		c = n.y < -0.16 ? charcoal : silver;
		c = mix(c, charcoal, band(sweep, 0.161, 0.195));
		c = mix(c, red, inside(0.195 - sweep));
		c = mix(c, silver, band(sweep, 0.208, 0.219));
	} else {
		float diagonal = p.y + 0.63 * (p.z - 0.71);
		c = mix(silver, charcoal, inside(0.064 - diagonal));
		c = mix(c, red, inside(0.096 - diagonal));
		c = mix(c, silver, band(diagonal, 0.100, 0.109));
		c = mix(c, green, band(p.y, 0.024, 0.032) * band(p.z, 0.697, 0.724));
	}
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	if (detail_enabled) {
		NORMAL_MAP = projected(foam_normal, foam_weights, foam_position).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
		ROUGHNESS *= projected(foam_roughness, foam_weights, foam_position).r;
	}
}
