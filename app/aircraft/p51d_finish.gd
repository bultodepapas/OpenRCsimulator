# Procedural natural-metal finish for the P-51D (P51-V08). Parameters live in the generated p51d_appearance.gd.
# The patterns are drawn from the OBJECT-SPACE position of each skin mesh (a varying written in vertex()), so the
# lofts need no UVs: the fuselage mesh sits in the airplane frame (z stations, y height), the wing skins in their
# dihedral frames (x along the panel, z chord from the root leading edge), the stab in the tail frame (x span) and
# the fin in the fin frame (y height). No textures, never reads TIME.
#   FUSELAGE (0): panel lines at the major stations and every pitch aft of the cowl, two longerons, rivets.
#   WING (1):     rib lines every rib_pitch outboard of rib_from_span, two spar lines at chord fractions.
#   TAIL_H (2):   rib lines every pitch along the span, one spar line.
#   TAIL_V (3):   rib lines every pitch up the fin, one spar line.
#   PLAIN (4):    the same metal, no lines (moving surfaces, doors, fairings).
extends RefCounted

const Appearance := preload("res://aircraft/p51d_appearance.gd")
const A: Dictionary = Appearance.DATA
const FUSELAGE := 0
const WING := 1
const TAIL_H := 2
const TAIL_V := 3
const PLAIN := 4

const SHADER_CODE := """
shader_type spatial;
uniform int part;
uniform vec3 aluminium : source_color;
uniform vec3 aluminium_dark : source_color;
uniform vec3 panel_line : source_color;
uniform vec3 rivet : source_color;
uniform float metallic_value;
uniform vec2 roughness_range;
uniform float tone_variation;
uniform float hash_scale;
uniform float line_width;
uniform float line_darkening;
uniform float rivet_pitch;
uniform float rivet_radius;
uniform float rivet_darkening;
uniform float major_z[8];
uniform int major_count;
uniform float fus_pitch;
uniform float fus_pitch_from;
uniform vec2 longerons;
uniform float rib_pitch;
uniform vec2 spars;
uniform float rib_from;
uniform float half_span;
uniform float root_chord;
uniform float tip_chord;
uniform float le_z_tip;
uniform float cos_dihedral;
uniform float tail_pitch;
uniform float tail_spar;
uniform float stab_root_le;
uniform float stab_root_chord;
uniform float stab_tip_le;
uniform float stab_tip_chord;
uniform float stab_half_span;
uniform float stab_hinge_z;
uniform float fin_chord;
varying vec3 object_pos;

void vertex() {
	object_pos = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Antialiased coverage of |d| < half width.
float line_cov(float d, float hw) {
	float w = max(fwidth(d), 1e-6);
	return clamp(0.5 - (abs(d) - hw) / w, 0.0, 1.0);
}

// Distance to the nearest line of a periodic family (period p) through the origin.
float periodic(float s, float p) {
	float u = s / p - floor(s / p + 0.5);
	return abs(u) * p;
}

// Rivet row: dots of rivet_radius every rivet_pitch along coordinate `along`, at distance `across` from the line.
float rivets(float along, float across) {
	float u = (along / rivet_pitch - floor(along / rivet_pitch + 0.5)) * rivet_pitch;
	float d = length(vec2(u, across)) - rivet_radius;
	float w = max(fwidth(d), 1e-6);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

void fragment() {
	vec3 p = object_pos;
	float line_d = 1e9;   // distance to the nearest panel line
	float row_along = 0.0; // coordinate along that line, for the rivet row
	vec2 cell = vec2(0.0); // panel id for the tone/roughness hash
	if (part == 0) {
		float d = 1e9;
		for (int i = 0; i < major_count; i++) {
			d = min(d, abs(p.z - major_z[i]));
		}
		if (p.z > fus_pitch_from) {
			d = min(d, periodic(p.z - fus_pitch_from, fus_pitch));
		}
		float ang = atan(p.y, abs(p.x) + 1e-6);
		line_d = d;
		row_along = ang * max(length(p.xy), 0.05);
		float dl = min(abs(p.y - longerons.x), abs(p.y - longerons.y));
		if (dl < line_d) { line_d = dl; row_along = p.z; }
		cell = vec2(floor(p.z / fus_pitch), floor(ang / 0.9));
	} else if (part == 1) {
		float span = abs(p.x) * cos_dihedral;
		float t = clamp(span / half_span, 0.0, 1.0);
		float le = mix(0.0, le_z_tip, t);
		float c = mix(root_chord, tip_chord, t);
		float f = (p.z - le) / c;
		float d = 1e9;
		if (span > rib_from) d = periodic(span - rib_from, rib_pitch);
		line_d = d;
		row_along = f * c;
		float ds = min(abs(f - spars.x), abs(f - spars.y)) * c;
		if (ds < line_d) { line_d = ds; row_along = span; }
		cell = vec2(floor((span - rib_from) / rib_pitch), floor(f * 3.0));
	} else if (part == 2) {
		float span = abs(p.x);
		float t = clamp(span / stab_half_span, 0.0, 1.0);
		float le = mix(stab_root_le, stab_tip_le, t) - stab_hinge_z;
		float c = mix(stab_root_chord, stab_tip_chord, t);
		float f = (p.z - le) / c;
		line_d = periodic(span, tail_pitch);
		row_along = f * c;
		float ds = abs(f - tail_spar) * c;
		if (ds < line_d) { line_d = ds; row_along = span; }
		cell = vec2(floor(span / tail_pitch), floor(f * 2.0));
	} else if (part == 3) {
		line_d = periodic(p.y, tail_pitch);
		row_along = p.z;
		float ds = abs(p.z + fin_chord * (1.0 - tail_spar));
		if (ds < line_d) { line_d = ds; row_along = p.y; }
		cell = vec2(floor(p.y / tail_pitch), floor(p.z / fin_chord));
	} else {
		cell = floor(p.xz / hash_scale) + floor(p.y / hash_scale);
	}
	// Plain parts (moving surfaces, doors) are small: one tone, mid roughness, so no blocks show on them.
	float h = part == 4 ? 0.5 : hash12(cell + 17.0);
	float hr = part == 4 ? 0.5 : hash12(cell + 3.7);
	vec3 base = mix(aluminium, aluminium_dark, tone_variation * (h * 2.0 - 1.0) + 0.5 * tone_variation);
	float rough = mix(roughness_range.x, roughness_range.y, hr);
	vec3 c = base;
	if (part != 4) {
		float lines = line_cov(line_d, line_width * 0.5);
		c = mix(c, mix(c, panel_line, line_darkening), lines);
		float r = rivets(row_along, line_d - line_width * 0.5 - rivet_radius * 2.5);
		c = mix(c, mix(c, rivet, rivet_darkening), r * (1.0 - lines));
		rough = mix(rough, 0.6, max(lines, r) * 0.5);
	}
	ALBEDO = c;
	METALLIC = metallic_value;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
"""

static var _shader: Shader
static var _materials := {}


## One shared, immutable material per part. `geometry` is the P-51 geometry DATA (wing and tail numbers).
static func material(part: int, geometry: Dictionary) -> ShaderMaterial:
	if _materials.has(part):
		return _materials[part]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	var colors: Dictionary = A.colors
	m.set_shader_parameter("part", part)
	m.set_shader_parameter("aluminium", Color(colors.aluminium))
	m.set_shader_parameter("aluminium_dark", Color(colors.aluminium_dark))
	m.set_shader_parameter("panel_line", Color(colors.panel_line))
	m.set_shader_parameter("rivet", Color(colors.rivet))
	m.set_shader_parameter("metallic_value", A.metal.metallic)
	m.set_shader_parameter("roughness_range", Vector2(A.metal.roughness_range[0], A.metal.roughness_range[1]))
	m.set_shader_parameter("tone_variation", A.metal.tone_variation)
	m.set_shader_parameter("hash_scale", A.metal.panel_hash_scale_m)
	m.set_shader_parameter("line_width", A.panel_lines.width_m)
	m.set_shader_parameter("line_darkening", A.panel_lines.darkening)
	m.set_shader_parameter("rivet_pitch", A.panel_lines.rivet_pitch_m)
	m.set_shader_parameter("rivet_radius", A.panel_lines.rivet_radius_m)
	m.set_shader_parameter("rivet_darkening", A.panel_lines.rivet_darkening)
	var majors: Array = A.fuselage.major_z_m
	var packed := PackedFloat32Array()
	for i in 8: packed.append(float(majors[i]) if i < majors.size() else 0.0)
	m.set_shader_parameter("major_z", packed)
	m.set_shader_parameter("major_count", majors.size())
	m.set_shader_parameter("fus_pitch", A.fuselage.pitch_m)
	m.set_shader_parameter("fus_pitch_from", A.fuselage.pitch_from_z_m)
	m.set_shader_parameter("longerons", Vector2(A.fuselage.longeron_y_m[0], A.fuselage.longeron_y_m[1]))
	m.set_shader_parameter("rib_pitch", A.wing.rib_pitch_m)
	m.set_shader_parameter("spars", Vector2(A.wing.spar_chord_fractions[0], A.wing.spar_chord_fractions[1]))
	m.set_shader_parameter("rib_from", A.wing.rib_from_span_m)
	var w: Dictionary = geometry.wing
	m.set_shader_parameter("half_span", float(w.span) / 2.0)
	m.set_shader_parameter("root_chord", w.root_chord)
	m.set_shader_parameter("tip_chord", w.tip_chord)
	m.set_shader_parameter("le_z_tip", w.le_z_tip)
	m.set_shader_parameter("cos_dihedral", cos(deg_to_rad(float(w.dihedral_deg))))
	var t: Dictionary = geometry.tail
	m.set_shader_parameter("tail_pitch", A.tail.pitch_m)
	m.set_shader_parameter("tail_spar", A.tail.spar_fraction)
	m.set_shader_parameter("stab_root_le", t.stab_root_le_z)
	m.set_shader_parameter("stab_root_chord", t.stab_root_chord)
	m.set_shader_parameter("stab_tip_le", t.stab_tip_le_z)
	m.set_shader_parameter("stab_tip_chord", t.stab_tip_chord)
	m.set_shader_parameter("stab_half_span", t.stab_half_span)
	m.set_shader_parameter("stab_hinge_z", float(t.stab_root_le_z) + float(t.elevator_hinge_fraction) * float(t.stab_root_chord))
	m.set_shader_parameter("fin_chord", float(t.rudder_hinge_z) - float(t.fin_root_le_z))
	_materials[part] = m
	return m


## Metallic value of a finish material (for checks).
static func metallic_of(mat: Material) -> float:
	if mat is StandardMaterial3D: return (mat as StandardMaterial3D).metallic
	if mat is ShaderMaterial: return float((mat as ShaderMaterial).get_shader_parameter("metallic_value"))
	return 0.0
