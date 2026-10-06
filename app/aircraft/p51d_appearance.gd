# Generated from assets/aircraft/p51d-mustang-120/appearance.json; edit that source.
# Finish parameters only (artistic estimate); drawn by p51d_finish.gd.
extends RefCounted

const DATA := {
	"id": "p51d-mustang-120-natural-metal-v1",
	"kind": "estimated",
	"source": "V08 2026-10-06. Natural-metal P-51D finish read from ground photos of restored airframes and the AN 01-60-3 three-view: bare aluminium with per-panel tone and roughness variation, dark panel lines at the frame stations and ribs, rivet rows along them, olive anti-glare panel, yellow tips and rudder, red spinner (placeholder scheme until V09). Artistic estimate: no photo pixels are copied.",
	"purpose": "V08: the skin should read as riveted aluminium panels, not grey plastic, in the inspector and in flight, with no textures and no TIME in the shader.",
	"colors": {
		"aluminium": "#c9ccd1",
		"aluminium_dark": "#9fa4ab",
		"panel_line": "#5a5f66",
		"rivet": "#7a7f86",
		"olive": "#3f4a2a",
		"yellow": "#e8b900",
		"red": "#b0121a",
		"glass": "#1c2733"
	},
	"metal": {
		"metallic": 0.9,
		"roughness_range": [
			0.24,
			0.36
		],
		"tone_variation": 0.03,
		"panel_hash_scale_m": 0.21
	},
	"panel_lines": {
		"width_m": 0.0015,
		"darkening": 0.35,
		"rivet_pitch_m": 0.018,
		"rivet_radius_m": 0.0009,
		"rivet_darkening": 0.18
	},
	"fuselage": {
		"major_z_m": [
			-0.025,
			0.15,
			0.62,
			0.985,
			1.28
		],
		"pitch_m": 0.145,
		"pitch_from_z_m": 0.15,
		"longeron_y_m": [
			0.0,
			-0.085
		]
	},
	"wing": {
		"rib_pitch_m": 0.095,
		"spar_chord_fractions": [
			0.25,
			0.63
		],
		"rib_from_span_m": 0.26
	},
	"tail": {
		"pitch_m": 0.08,
		"spar_fraction": 0.3
	}
}
