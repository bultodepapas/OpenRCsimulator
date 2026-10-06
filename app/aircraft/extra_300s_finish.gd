# Procedural finish for the Extra 300S .60 (EX-10a). Parameters live in the generated extra_300s_appearance.gd.
# The builder writes model-space coordinates into UV/UV2, so every pattern is defined in metres or chord
# fractions: no texture, no seams between panels, and the same look on moving surfaces. Never reads TIME.
#   wing (part 0):            UV = (|span| m, chord fraction), UV2.x = local chord m
#   horizontal tail (part 1): UV = (span m, z from the elevator hinge m)
#   fuselage (part 2):        UV = (height y m, z m)
#   vertical tail (part 3):   UV = (height y m, z from the rudder hinge m)
#   moving wing surface (4):  plain red, both faces
extends RefCounted

const Appearance := preload("res://aircraft/extra_300s_appearance.gd")
const A: Dictionary = Appearance.DATA
const WING := 0
const HORIZONTAL_TAIL := 1
const FUSELAGE := 2
const VERTICAL_TAIL := 3
const AILERON := 4

const SHADER_CODE := """
shader_type spatial;
uniform int part;
uniform vec3 red : source_color;
uniform vec3 white : source_color;
uniform vec3 blue : source_color;
uniform vec3 pinstripe : source_color;
uniform float roughness_value;
uniform vec2 wing_band;
uniform float pin_m;
uniform vec3 wing_star_span;
uniform float wing_star_r;
uniform float wing_period;
uniform float wing_le_red;
uniform vec2 stab_band;
uniform float stab_star_span;
uniform float stab_star_r;
uniform float stab_period;
uniform vec4 side_line; // z0, y0, z1, y1 of the side band centre line
uniform float side_half;
uniform vec2 cowl_panel;
uniform float cowl_star_y;
uniform float cowl_rear_z;
uniform vec3 cowl_star_z;
uniform float cowl_star_r;
uniform float fus_pin_m;
uniform vec2 fin_band;
varying vec3 object_normal;

void vertex() {
	object_normal = NORMAL;
}

// Five-point star signed distance (Inigo Quilez), one point toward +y.
float star(vec2 p, float r) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = 0.45 * r * vec2(-k1.y, k1.x) - vec2(0.0, r);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, 1.0);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// Antialiased coverage of the region d < 0.
float inside(float d) {
	float w = max(fwidth(d), 1e-6);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

// Band of half-width hw around 0 with pinstripes of width pw on its edges, over a base colour.
vec3 band(vec3 base, float d, float hw, float pw) {
	vec3 c = mix(base, white, inside(abs(d) - hw));
	return mix(c, pinstripe, inside(abs(abs(d) - hw) - pw * 0.5));
}

vec3 stripes(float s, float period, vec3 a, vec3 b) {
	float phase = fract(s / period) - 0.5;
	return mix(b, a, inside(abs(phase) * period - period * 0.25));
}

void fragment() {
	vec3 c = red;
	float up = object_normal.y;
	if (part == 0 && abs(up) > 0.3) {
		float chord = UV2.x;
		if (up > 0.0) {
			float mid = 0.5 * (wing_band.x + wing_band.y);
			float d = (UV.y - mid) * chord;
			c = band(red, d, 0.5 * (wing_band.y - wing_band.x) * chord, pin_m);
			for (int i = 0; i < 3; i++) {
				c = mix(c, red, inside(star(vec2(UV.x - wing_star_span[i], -d), wing_star_r)));
			}
		} else {
			c = stripes(UV.x, wing_period, blue, white);
			c = mix(c, red, inside(UV.y - wing_le_red));
		}
	} else if (part == 1 && abs(up) > 0.3 && UV.y < 0.0) {
		if (up > 0.0) {
			float d = UV.y - 0.5 * (stab_band.x + stab_band.y);
			c = band(red, d, 0.5 * (stab_band.y - stab_band.x), pin_m);
			c = mix(c, red, inside(star(vec2(abs(UV.x) - stab_star_span, -d), stab_star_r)));
		} else {
			c = stripes(UV.x, stab_period, red, white);
		}
	} else if (part == 2 && abs(object_normal.x) > 0.55) {
		float centre = mix(side_line.y, side_line.w, clamp((UV.y - side_line.x) / (side_line.z - side_line.x), 0.0, 1.0));
		if (UV.y < cowl_rear_z) {
			float mid = 0.5 * (cowl_panel.x + cowl_panel.y);
			c = band(red, UV.x - mid, 0.5 * (cowl_panel.y - cowl_panel.x), fus_pin_m);
			for (int i = 0; i < 3; i++) {
				c = mix(c, red, inside(star(vec2(UV.y - cowl_star_z[i], UV.x - cowl_star_y), cowl_star_r)));
			}
		} else {
			c = band(red, UV.x - centre, side_half, fus_pin_m);
		}
	} else if (part == 3 && abs(object_normal.x) > 0.3) {
		float d = UV.x - 0.5 * (fin_band.x + fin_band.y);
		c = band(red, d, 0.5 * (fin_band.y - fin_band.x), pin_m);
	}
	ALBEDO = c;
	ROUGHNESS = roughness_value;
}
"""

static var _shader: Shader
static var _materials := {}


## One shared, immutable material per part.
static func material(part: int, cowl_rear_z := 0.0) -> ShaderMaterial:
	if _materials.has(part):
		return _materials[part]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	var colors: Dictionary = A.colors
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("red", Color(colors.red))
	m.set_shader_parameter("white", Color(colors.white))
	m.set_shader_parameter("blue", Color(colors.blue))
	m.set_shader_parameter("pinstripe", Color(colors.pinstripe))
	m.set_shader_parameter("roughness_value", A.roughness)
	m.set_shader_parameter("wing_band", _vec2(A.wing_top.band_chord_fraction))
	m.set_shader_parameter("pin_m", A.wing_top.pinstripe_m)
	m.set_shader_parameter("wing_star_span", _vec3(A.wing_top.star_span_m))
	m.set_shader_parameter("wing_star_r", A.wing_top.star_radius_m)
	m.set_shader_parameter("wing_period", A.wing_bottom.stripe_period_m)
	m.set_shader_parameter("wing_le_red", A.wing_bottom.leading_edge_red_chord_fraction)
	m.set_shader_parameter("stab_band", _vec2(A.stab_top.band_from_hinge_m))
	m.set_shader_parameter("stab_star_span", A.stab_top.star_span_m)
	m.set_shader_parameter("stab_star_r", A.stab_top.star_radius_m)
	m.set_shader_parameter("stab_period", A.stab_bottom.stripe_period_m)
	var line: Array = A.fuselage.side_band_center_y_m
	m.set_shader_parameter("side_line", Vector4(line[0][0], line[0][1], line[1][0], line[1][1]))
	m.set_shader_parameter("side_half", A.fuselage.side_band_half_height_m)
	m.set_shader_parameter("cowl_panel", _vec2(A.fuselage.cowl_panel_y_m))
	m.set_shader_parameter("cowl_star_y", A.fuselage.cowl_star_y_m)
	m.set_shader_parameter("cowl_rear_z", cowl_rear_z)
	m.set_shader_parameter("cowl_star_z", _vec3(A.fuselage.cowl_star_z_m))
	m.set_shader_parameter("cowl_star_r", A.fuselage.cowl_star_radius_m)
	m.set_shader_parameter("fus_pin_m", A.fuselage.pinstripe_m)
	m.set_shader_parameter("fin_band", _vec2(A.vertical_tail.band_height_m))
	_materials[part] = m
	return m


static func _vec2(v: Array) -> Vector2:
	return Vector2(v[0], v[1])


static func _vec3(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])
