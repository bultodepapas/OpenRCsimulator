# Generated from assets/aircraft/extra-300s-60/appearance.json; edit that source.
# Finish parameters only (artistic estimate); drawn by extra_300s_finish.gd.
extends RefCounted

const DATA := {
	"id": "gp-extra-300s-60-red-stars-v1",
	"kind": "estimated",
	"source": "Owner photo references/extra-300/image.png (Great Planes .40 catalogue scheme) for the top and sides; Outerzone oz12489 photo 005 for the blue/white underside. Adapted by eye to the .60 geometry; colours read under unknown light. Original artwork: no logos, registration or photo pixels are copied.",
	"purpose": "Readability first (EX-10a): the upper surface reads red with a white star band, the lower surface blue and white chordwise stripes, so a pilot can tell top from bottom.",
	"colors": {
		"red": "#c4182a",
		"white": "#f3f1ea",
		"blue": "#1f3f9e",
		"pinstripe": "#16285e",
		"glass": "#1c2733"
	},
	"wing_top": {
		"band_chord_fraction": [
			0.2,
			0.6
		],
		"pinstripe_m": 0.006,
		"star_span_m": [
			0.4,
			0.55,
			0.7
		],
		"star_radius_m": 0.045
	},
	"wing_bottom": {
		"stripe_period_m": 0.12,
		"leading_edge_red_chord_fraction": 0.06
	},
	"stab_top": {
		"band_from_hinge_m": [
			-0.07,
			-0.03
		],
		"star_span_m": 0.2,
		"star_radius_m": 0.022
	},
	"stab_bottom": {
		"stripe_period_m": 0.08
	},
	"fuselage": {
		"side_band_center_y_m": [
			[
				-0.14,
				-0.004
			],
			[
				0.81,
				-0.002
			]
		],
		"side_band_half_height_m": 0.011,
		"cowl_panel_y_m": [
			-0.066,
			0.007
		],
		"cowl_star_y_m": -0.03,
		"pinstripe_m": 0.004,
		"cowl_star_z_m": [
			-0.32,
			-0.27,
			-0.22
		],
		"cowl_star_radius_m": 0.016
	},
	"vertical_tail": {
		"band_height_m": [
			0.2,
			0.235
		]
	},
	"roughness": 0.4,
	"fuselage_note": "Side band: straight line in model height (metres) from the cowl joint to the tail post, as in the photo; the cowl carries a lower white panel with three stars.",
	"canopy": {
		"alpha": 0.45,
		"note": "Tinted transparent canopy (EX-10 test): set alpha to 1.0 for the opaque fallback if transparency shows sorting defects."
	},
	"pilot_colors": {
		"skin": "#d9a57e",
		"cap": "#1d2a4a",
		"shirt": "#e6e8ec"
	}
}
