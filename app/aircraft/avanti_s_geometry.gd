# Generated, do not edit. Source: assets/aircraft/avanti-s-a200/geometry.json (revision a200-av02-contours-03).
# Regenerate with: python3 assets/aircraft/avanti-s-a200/compile_geometry.py
# Visual preview geometry only (AV-02 estimates, see DATA.evidence); not flyable.
extends RefCounted

const DATA := {
	"schema": "openrc-avanti-visual-study-v1",
	"revision": "a200-av02-contours-03",
	"status": "isolated visual study; not calibrated, not flyable",
	"units": "m",
	"axes": {
		"nose": "-Z",
		"right": "+X",
		"up": "+Y"
	},
	"datum": {
		"z": "Root leading edge beside fuselage projected onto symmetry plane",
		"y": "Estimated wing midplane at root; not measured CG height"
	},
	"nominal": {
		"span_m": 2.0,
		"length_m": 2.22,
		"engine_length_m": 0.241,
		"engine_diameter_m": 0.097,
		"cg_aft_root_le_m": [
			0.24,
			0.25,
			0.26
		]
	},
	"fuselage_stations": [
		[
			-1.05,
			0.001,
			0.001,
			-0.001
		],
		[
			-1.0,
			0.023,
			0.025,
			-0.014
		],
		[
			-0.85,
			0.06,
			0.075,
			-0.041
		],
		[
			-0.65,
			0.095,
			0.13,
			-0.07
		],
		[
			-0.4,
			0.129,
			0.155,
			-0.093
		],
		[
			-0.15,
			0.151,
			0.154,
			-0.11
		],
		[
			0.0,
			0.162,
			0.139,
			-0.12
		],
		[
			0.3,
			0.137,
			0.105,
			-0.11
		],
		[
			0.6,
			0.103,
			0.084,
			-0.09
		],
		[
			0.86,
			0.066,
			0.067,
			-0.064
		],
		[
			1.05,
			0.047,
			0.05,
			-0.048
		],
		[
			1.17,
			0.038,
			0.039,
			-0.039
		]
	],
	"canopy_stations": [
		[
			-0.86,
			0.002,
			0.076,
			0.073
		],
		[
			-0.72,
			0.043,
			0.16,
			0.094
		],
		[
			-0.53,
			0.092,
			0.23,
			0.11
		],
		[
			-0.28,
			0.108,
			0.251,
			0.12
		],
		[
			-0.09,
			0.099,
			0.214,
			0.12
		],
		[
			0.07,
			0.008,
			0.125,
			0.119
		]
	],
	"wing": {
		"stations": [
			[
				0.14,
				0.0,
				0.43,
				0.0
			],
			[
				0.53,
				0.145,
				0.5,
				0.007
			],
			[
				0.9,
				0.278,
				0.54,
				0.0172
			],
			[
				0.95,
				0.296,
				0.535,
				0.0186
			],
			[
				0.985,
				0.309,
				0.53,
				0.0196
			],
			[
				1.0,
				0.325,
				0.523,
				0.02
			]
		],
		"hinge_fraction": 0.69,
		"flap_span": [
			0.18,
			0.53
		],
		"aileron_span": [
			0.55,
			0.95
		],
		"gap_m": 0.004,
		"slab_thickness_m": 0.024,
		"control_thickness_m": 0.01
	},
	"tail": {
		"stations": [
			[
				0.05,
				0.86,
				1.1,
				0.065
			],
			[
				0.35,
				0.98,
				1.14,
				0.07684
			],
			[
				0.4,
				1.003,
				1.131,
				0.07882
			],
			[
				0.43,
				1.02,
				1.104,
				0.08
			]
		],
		"hinge_fraction": 0.67,
		"gap_m": 0.003,
		"slab_thickness_m": 0.014,
		"control_thickness_m": 0.01
	},
	"fin": {
		"outline_yz": [
			[
				0.085,
				0.3
			],
			[
				0.1,
				0.4
			],
			[
				0.125,
				0.51
			],
			[
				0.18,
				0.64
			],
			[
				0.27,
				0.75
			],
			[
				0.38,
				0.835
			],
			[
				0.465,
				0.887
			],
			[
				0.498,
				0.92
			],
			[
				0.51,
				0.96
			],
			[
				0.49,
				1.105
			],
			[
				0.06,
				1.155
			]
		],
		"hinge_bottom_yz": [
			0.065,
			1.017
		],
		"hinge_top_yz": [
			0.5,
			1.035
		],
		"thickness_m": 0.014,
		"leading_outline_count": 9.0
	},
	"installation": {
		"engine_center": [
			0.0,
			-0.005,
			0.54
		],
		"outlet_radius_m": 0.036,
		"intake_stations": [
			[
				-0.09,
				0.026,
				0.007,
				-0.063,
				0.156
			],
			[
				-0.07,
				0.029,
				0.01,
				-0.066,
				0.156
			],
			[
				0.015,
				0.032,
				0.013,
				-0.067,
				0.154
			],
			[
				0.14,
				0.023,
				0.009,
				-0.058,
				0.145
			],
			[
				0.28,
				0.006,
				-0.012,
				-0.038,
				0.13
			]
		],
		"intake_shadow_stations": [
			[
				-0.091,
				0.021,
				0.001,
				-0.057,
				0.156
			],
			[
				-0.089,
				0.021,
				0.001,
				-0.057,
				0.156
			]
		]
	},
	"controls_deg": {
		"flap_cruise": 0.0,
		"flap_takeoff": 20.0,
		"flap_landing": 50.0,
		"aileron_up": 30.0,
		"aileron_down": 25.0,
		"elevator_up": 30.0,
		"elevator_down": 30.0,
		"rudder_each_side": 30.0
	},
	"evidence": {
		"nominal": {
			"kind": "manufacturer_nominal",
			"sources": [
				{
					"path": "references/avanti-s/manuals/avanti-s-200-intro.pdf",
					"url": "https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf",
					"sha256": "c22d198a694eca39f122ce7ce419d55a30bfb73ca60cdc888471b021c4ec8134"
				},
				{
					"path": "references/avanti-s/turbine/jetcat-p100-rx-dimensions.pdf",
					"url": "https://www.jetcat.de/jetcat/produkte/hobby/p100_rx/JetCat%20P100%20RX%20Size.PDF",
					"sha256": "122094da4d679ed03b30b3a16ff0cafbc105e0dbab13e4655ba1aa6703af9cf5"
				}
			]
		},
		"controls_deg": {
			"kind": "manufacturer_nominal",
			"source": {
				"path": "references/avanti-s/manuals/avanti-s-200-intro.pdf",
				"url": "https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf",
				"sha256": "c22d198a694eca39f122ce7ce419d55a30bfb73ca60cdc888471b021c4ec8134"
			},
			"pdf_page": 4.0
		},
		"fuselage_stations": {
			"kind": "estimated_visual_blockout",
			"source": "Official CIMG7310/CIMG7313/CIMG7321 photographs; no metric reconstruction",
			"uncertainty": "Unknown; values are design assumptions, not confidence intervals",
			"refinement": "Visual estimate from unchanged comparison cameras and existing official photos; docs/research/avanti-s-contour-refinement-v3.md. No metric calibration."
		},
		"canopy_stations": {
			"kind": "estimated_visual_blockout",
			"source": "Official CIMG7316 and CIMG7310 photographs",
			"refinement": "Visual estimate from unchanged comparison cameras and existing official photos; docs/research/avanti-s-contour-refinement-v3.md. No metric calibration."
		},
		"wing": {
			"kind": "estimated_visual_blockout",
			"source": "Official CIMG7321 and CIMG7313; endpoints constrained only by nominal span",
			"warning": "Area, chord, sweep, dihedral and thickness are unvalidated; not aerodynamic data",
			"refinement": "Frozen-camera CIMG7321/CIMG7313/CIMG7310 silhouette review; docs/research/avanti-s-contour-refinement.md. Visual estimates, not measured dimensions."
		},
		"tail": {
			"kind": "estimated_visual_blockout",
			"source": "Official CIMG7313; no calibrated scale",
			"refinement": "Frozen-camera CIMG7321/CIMG7313/CIMG7310 silhouette review; docs/research/avanti-s-contour-refinement.md. Visual estimates, not measured dimensions."
		},
		"fin": {
			"kind": "estimated_visual_blockout",
			"source": "Official CIMG7310; no calibrated scale",
			"refinement": "Frozen-camera CIMG7321/CIMG7313/CIMG7310 silhouette review; docs/research/avanti-s-contour-refinement.md. Visual estimates, not measured dimensions."
		},
		"installation": {
			"kind": "estimated_visual_blockout",
			"source": "Assembly steps131-134 for arrangement only; positions and duct radii assumed",
			"refinement": "Frozen-camera CIMG7321/CIMG7313/CIMG7310 silhouette review; docs/research/avanti-s-contour-refinement.md. Visual estimates, not measured dimensions."
		},
		"finish": {
			"kind": "illustrative",
			"source": "White/blue/red groups for inspection; not exact SebArt livery"
		},
		"loft": {
			"kind": "procedural_visual_interpolation",
			"source": "Shape-preserving interpolation through estimated sections; adds no measured dimensions."
		}
	},
	"loft": {
		"longitudinal_subdivisions": 4.0,
		"smooth_normals": true,
		"interpolation": "bounded_monotone_hermite"
	}
}
