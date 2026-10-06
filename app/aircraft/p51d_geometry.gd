# Generated from assets/aircraft/p51d-mustang-120/geometry.json; edit source.json and run build_geometry.py.
# Visual geometry only. Every group has provenance in DATA.evidence.
extends RefCounted

const DATA := {
	"id": "p51d-mustang-120-v1",
	"kit": "PLACEHOLDER: giant-scale P-51D for a 120 cc gasoline engine",
	"units": "m",
	"axes": {
		"nose": "-Z",
		"right": "+X",
		"up": "+Y"
	},
	"datum": "Symmetry plane; z = 0 at the wing leading edge on the centreline; y = 0 on the thrust line (spinner axis). Physics CG is set in the data file.",
	"scale": {
		"full_size_span": 11.286,
		"model_span": 2.508,
		"factor": 0.222222,
		"nominal": "1/4.50"
	},
	"engine_class": "120 cc class gasoline twin-cylinder (DA-120 / DLE-120 class)",
	"wing": {
		"span": 2.508,
		"root_chord": 0.5867,
		"tip_chord": 0.2822,
		"le_z_root": 0.0,
		"le_z_tip": 0.0761,
		"chord_plane_y": -0.0667,
		"dihedral_deg": 5.0,
		"incidence_deg": 1.0,
		"washout_deg": 0.0,
		"root_thickness_ratio": 0.151,
		"tip_thickness_ratio": 0.114,
		"camber_ratio": 0.015,
		"aileron_inner": 0.7222,
		"aileron_outer": 1.2222,
		"aileron_chord_fraction": 0.21,
		"flap_inner": 0.1111,
		"flap_outer": 0.7111,
		"flap_chord_fraction": 0.21,
		"hinge_gap": 0.003,
		"section": [
			[
				0.0,
				0.0
			],
			[
				0.0125,
				0.12
			],
			[
				0.025,
				0.165
			],
			[
				0.05,
				0.225
			],
			[
				0.1,
				0.305
			],
			[
				0.2,
				0.405
			],
			[
				0.3,
				0.465
			],
			[
				0.4,
				0.5
			],
			[
				0.5,
				0.49
			],
			[
				0.6,
				0.44
			],
			[
				0.7,
				0.35
			],
			[
				0.8,
				0.235
			],
			[
				0.9,
				0.115
			],
			[
				0.95,
				0.06
			],
			[
				1.0,
				0.005
			]
		],
		"reference": {
			"trapezoid_area": 1.0896,
			"s_over_b": 0.4344,
			"mac": 0.4522,
			"mac_le_z": 0.0336,
			"mac_span_station": 0.5538,
			"cg_fraction_of_mac": 0.25
		}
	},
	"fuselage_stations": [
		[
			-0.3444,
			0.0767,
			0.0767,
			-0.0767,
			2.0,
			2.0
		],
		[
			-0.2889,
			0.0889,
			0.0933,
			-0.0933,
			2.2,
			2.0
		],
		[
			-0.2222,
			0.0956,
			0.1044,
			-0.1044,
			2.3,
			2.0
		],
		[
			-0.1333,
			0.0978,
			0.1111,
			-0.1111,
			2.4,
			2.0
		],
		[
			-0.0444,
			0.0978,
			0.1156,
			-0.1156,
			2.4,
			2.0
		],
		[
			0.0,
			0.0978,
			0.1178,
			-0.1178,
			2.4,
			2.0
		],
		[
			0.0889,
			0.0978,
			0.12,
			-0.1222,
			2.4,
			2.0
		],
		[
			0.1667,
			0.0978,
			0.1244,
			-0.1244,
			2.4,
			2.0
		],
		[
			0.2667,
			0.0978,
			0.1267,
			-0.1267,
			2.4,
			2.0
		],
		[
			0.3778,
			0.0956,
			0.1289,
			-0.1267,
			2.4,
			2.0
		],
		[
			0.4333,
			0.0956,
			0.1289,
			-0.1267,
			2.4,
			2.0
		],
		[
			0.5333,
			0.0933,
			0.1244,
			-0.1244,
			2.3,
			2.0
		],
		[
			0.6444,
			0.0889,
			0.1156,
			-0.1222,
			2.3,
			2.0
		],
		[
			0.7778,
			0.08,
			0.1,
			-0.1111,
			2.2,
			2.0
		],
		[
			0.9333,
			0.0667,
			0.08,
			-0.0956,
			2.2,
			2.0
		],
		[
			1.1111,
			0.0489,
			0.0578,
			-0.0667,
			2.1,
			2.0
		],
		[
			1.2667,
			0.0333,
			0.0378,
			-0.0378,
			2.0,
			2.0
		],
		[
			1.4667,
			0.02,
			0.02,
			-0.02,
			2.0,
			2.0
		],
		[
			1.5444,
			0.0089,
			0.0111,
			-0.0067,
			2.0,
			2.0
		]
	],
	"scoop_stations": [
		[
			0.4556,
			0.0667,
			-0.2111
		],
		[
			0.5556,
			0.0733,
			-0.24
		],
		[
			0.6667,
			0.0733,
			-0.2489
		],
		[
			0.7778,
			0.0667,
			-0.2333
		],
		[
			0.8667,
			0.0533,
			-0.1889
		],
		[
			0.9667,
			0.0356,
			-0.1333
		]
	],
	"carb_intake": {
		"z0": -0.3222,
		"z1": -0.0889,
		"half_width": 0.0333,
		"height": 0.0222
	},
	"spinner": {
		"tip_z": -0.5222,
		"back_z": -0.3444,
		"radius": 0.0767
	},
	"firewall_z": 0.1667,
	"cowl_rear_z": 0.3778,
	"canopy": {
		"top": [
			[
				0.4333,
				0.1289
			],
			[
				0.4889,
				0.1911
			],
			[
				0.5444,
				0.2178
			],
			[
				0.6111,
				0.2267
			],
			[
				0.6778,
				0.2156
			],
			[
				0.7444,
				0.1822
			],
			[
				0.8111,
				0.1156
			]
		],
		"frame_z": 0.5222,
		"halfwidth_fraction": 0.95
	},
	"tail": {
		"stab_y": 0.0222,
		"stab_root_le_z": 1.3333,
		"stab_tip_le_z": 1.4111,
		"stab_half_span": 0.4478,
		"stab_root_chord": 0.2778,
		"stab_tip_chord": 0.1556,
		"elevator_hinge_fraction": 0.65,
		"stab_thickness": 0.0217,
		"stab_incidence_deg": 0.0,
		"fin_root_le_z": 1.3111,
		"dorsal_start_z": 1.1778,
		"fin_top_y": 0.4333,
		"fin_top_le_z": 1.5,
		"fin_top_chord": 0.1222,
		"rudder_hinge_z": 1.5444,
		"rudder_te_bottom": [
			1.6556,
			-0.0111
		],
		"fin_thickness": 0.0176,
		"hinge_gap": 0.003
	},
	"gear": {
		"main_axle": [
			0.0222,
			-0.3667
		],
		"main_wheel_diameter": 0.1524,
		"main_wheel_width": 0.0489,
		"track": 0.8022,
		"strut_radius": 0.0122,
		"tail_axle": [
			1.4333,
			-0.1111
		],
		"tail_wheel_diameter": 0.0707
	},
	"propeller": {
		"diameter": 0.7112,
		"pitch": 0.254,
		"blades": 4,
		"z": -0.3889,
		"hub_radius": 0.0383,
		"scale_diameter": 0.7564,
		"blade": {
			"chord_fraction_of_radius": [
				[
					0.2,
					0.14
				],
				[
					0.35,
					0.17
				],
				[
					0.55,
					0.18
				],
				[
					0.75,
					0.17
				],
				[
					0.9,
					0.13
				],
				[
					1.0,
					0.04
				]
			],
			"thickness_fraction_of_chord": [
				[
					0.2,
					0.18
				],
				[
					0.5,
					0.1
				],
				[
					1.0,
					0.06
				]
			]
		}
	},
	"pilot": {
		"cap_top": [
			0.6044,
			0.2067
		],
		"cap_brim_front": [
			0.5689,
			0.1867
		],
		"nose_front": [
			0.5733,
			0.1689
		],
		"head_back": [
			0.6311,
			0.1778
		],
		"chin": [
			0.5822,
			0.1511
		],
		"shoulder_front": [
			0.5667,
			0.1333
		],
		"shoulder_back": [
			0.6556,
			0.1289
		],
		"head_half_width": 0.0222,
		"shoulder_half_width": 0.0533
	},
	"evidence": {
		"full_size.overall": {
			"kind": "estimated",
			"source": "published P-51D specifications (span 37 ft 0.3 in, length 32 ft 3 in, wing area 235 sq ft, stab span 13 ft 2.5 in, track 11 ft 10 in, propeller 11 ft 2 in, 27 in / 12.5 in wheels); URLs in docs/research/p51-resources.json once verified",
			"limits": "Sections, station lines, scoop and canopy proportions are read by eye from public three-view drawings, not measured on a calibrated plan."
		},
		"full_size.wing": {
			"kind": "estimated",
			"source": "root chord 104 in, tip chord 50 in, AR 5.86, dihedral 5 deg, NAA 45-100 section 15.1 % root / 11.4 % tip; quarter chord assumed unswept (LE sweep 3.5 deg)",
			"limits": "Incidence +1 deg and zero washout are assumptions to confirm."
		},
		"section": {
			"kind": "estimated",
			"source": "generic laminar thickness distribution (max at 40 % chord) with 1.5 % parabolic camber; the true NAA 45-100 ordinates are not reproduced",
			"limits": "Visual and first-estimate aero only."
		},
		"kit": {
			"kind": "estimated",
			"source": "placeholder until the research report selects the reference kit",
			"limits": "Span, mass, propeller and throws are provisional."
		},
		"scaling": {
			"kind": "derived",
			"source": "assets/aircraft/p51d-mustang-120/build_geometry.py: every full-size length x kit.span / full_size.span",
			"method": "factor 0.22222 (1/4.50)"
		},
		"propeller": {
			"kind": "estimated",
			"source": "kit propeller size (not the scaled 11 ft 2 in Hamilton Standard, recorded as scale_diameter); paddle-blade planform by eye; pitch for the twist only",
			"limits": "visual stand-in"
		}
	}
}
