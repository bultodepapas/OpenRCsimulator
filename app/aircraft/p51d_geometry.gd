# Generated from assets/aircraft/p51d-mustang-120/geometry.json; edit source.json and run build_geometry.py.
# Visual geometry only. Every group has provenance in DATA.evidence.
extends RefCounted

const DATA := {
	"id": "p51d-mustang-120-v1",
	"kit": "P-51D Mustang 1/4 scale, 120 cc class (plans/short-kit class: Chad Veich 1/4 plans, Jerry Bates 1/4, FokkeRC 1/4 short kit)",
	"units": "m",
	"axes": {
		"nose": "-Z",
		"right": "+X",
		"up": "+Y"
	},
	"datum": "Symmetry plane; z = 0 at the wing leading edge on the centreline; y = 0 on the thrust line (spinner axis). Physics CG is set in the data file.",
	"scale": {
		"full_size_span": 11.286,
		"model_span": 2.82,
		"factor": 0.249867,
		"nominal": "1/4.00"
	},
	"engine_class": "Desert Aircraft DA-120 (121 cc twin, 11.7 hp, 2.45 kg with ignition) or DLE-120 class",
	"wing": {
		"span": 2.82,
		"root_chord": 0.6596,
		"tip_chord": 0.3173,
		"le_z_root": 0.0,
		"le_z_tip": 0.0856,
		"chord_plane_y": -0.075,
		"dihedral_deg": 5.0,
		"incidence_deg": 1.0,
		"washout_deg": 0.0,
		"root_thickness_ratio": 0.1651,
		"tip_thickness_ratio": 0.1142,
		"camber_ratio": 0.0128,
		"aileron_inner": 0.8121,
		"aileron_outer": 1.3743,
		"aileron_chord_fraction": 0.21,
		"flap_inner": 0.1249,
		"flap_outer": 0.7996,
		"flap_chord_fraction": 0.21,
		"hinge_gap": 0.003,
		"section": [
			[
				0.0,
				0.0
			],
			[
				0.00558,
				0.0865
			],
			[
				0.02221,
				0.1718
			],
			[
				0.04952,
				0.2475
			],
			[
				0.08688,
				0.3184
			],
			[
				0.13347,
				0.3769
			],
			[
				0.18826,
				0.4278
			],
			[
				0.25,
				0.4678
			],
			[
				0.31733,
				0.4945
			],
			[
				0.38874,
				0.5
			],
			[
				0.46264,
				0.4765
			],
			[
				0.53736,
				0.4267
			],
			[
				0.61126,
				0.3622
			],
			[
				0.68267,
				0.2962
			],
			[
				0.75,
				0.2341
			],
			[
				0.81175,
				0.1703
			],
			[
				0.86653,
				0.1065
			],
			[
				0.91312,
				0.0578
			],
			[
				0.95049,
				0.0279
			],
			[
				0.97779,
				0.0116
			],
			[
				1.0,
				0.0
			]
		],
		"reference": {
			"trapezoid_area": 1.3775,
			"s_over_b": 0.4885,
			"mac": 0.5085,
			"mac_le_z": 0.0378,
			"mac_span_station": 0.6227,
			"cg_fraction_of_mac": 0.27
		}
	},
	"fuselage_stations": [
		[
			-0.3873,
			0.0862,
			0.0862,
			-0.0862,
			2.0,
			2.0
		],
		[
			-0.3248,
			0.0999,
			0.1049,
			-0.1049,
			2.2,
			2.0
		],
		[
			-0.2499,
			0.1074,
			0.1174,
			-0.1174,
			2.3,
			2.0
		],
		[
			-0.1499,
			0.1099,
			0.1249,
			-0.1249,
			2.4,
			2.0
		],
		[
			-0.05,
			0.1099,
			0.1299,
			-0.1299,
			2.4,
			2.0
		],
		[
			0.0,
			0.1099,
			0.1324,
			-0.1324,
			2.4,
			2.0
		],
		[
			0.0999,
			0.1099,
			0.1349,
			-0.1374,
			2.4,
			2.0
		],
		[
			0.1874,
			0.1099,
			0.1399,
			-0.1399,
			2.4,
			2.0
		],
		[
			0.2998,
			0.1099,
			0.1424,
			-0.1424,
			2.4,
			2.0
		],
		[
			0.4248,
			0.1074,
			0.1449,
			-0.1424,
			2.4,
			2.0
		],
		[
			0.4872,
			0.1074,
			0.1449,
			-0.1424,
			2.4,
			2.0
		],
		[
			0.5997,
			0.1049,
			0.1399,
			-0.1399,
			2.3,
			2.0
		],
		[
			0.7246,
			0.0999,
			0.1299,
			-0.1374,
			2.3,
			2.0
		],
		[
			0.8745,
			0.09,
			0.1124,
			-0.1249,
			2.2,
			2.0
		],
		[
			1.0494,
			0.075,
			0.09,
			-0.1074,
			2.2,
			2.0
		],
		[
			1.2493,
			0.055,
			0.065,
			-0.075,
			2.1,
			2.0
		],
		[
			1.4242,
			0.0375,
			0.0425,
			-0.0425,
			2.0,
			2.0
		],
		[
			1.6491,
			0.0225,
			0.0225,
			-0.0225,
			2.0,
			2.0
		],
		[
			1.7366,
			0.01,
			0.0125,
			-0.0075,
			2.0,
			2.0
		]
	],
	"scoop_stations": [
		[
			0.5122,
			0.075,
			-0.2374
		],
		[
			0.6247,
			0.0825,
			-0.2699
		],
		[
			0.7496,
			0.0825,
			-0.2799
		],
		[
			0.8745,
			0.075,
			-0.2624
		],
		[
			0.9745,
			0.06,
			-0.2124
		],
		[
			1.0869,
			0.04,
			-0.1499
		]
	],
	"carb_intake": {
		"z0": -0.3623,
		"z1": -0.0999,
		"half_width": 0.0375,
		"height": 0.025
	},
	"spinner": {
		"tip_z": -0.5872,
		"back_z": -0.3873,
		"radius": 0.0862
	},
	"firewall_z": 0.1874,
	"cowl_rear_z": 0.4248,
	"canopy": {
		"top": [
			[
				0.4872,
				0.1449
			],
			[
				0.5497,
				0.2149
			],
			[
				0.6122,
				0.2449
			],
			[
				0.6871,
				0.2549
			],
			[
				0.7621,
				0.2424
			],
			[
				0.8371,
				0.2049
			],
			[
				0.912,
				0.1299
			]
		],
		"frame_z": 0.5872,
		"halfwidth_fraction": 0.95
	},
	"tail": {
		"stab_y": 0.025,
		"stab_root_le_z": 1.4617,
		"stab_tip_le_z": 1.5742,
		"stab_half_span": 0.4985,
		"stab_root_chord": 0.3498,
		"stab_tip_chord": 0.1749,
		"elevator_hinge_fraction": 0.65,
		"stab_thickness": 0.0262,
		"stab_incidence_deg": 0.0,
		"fin_root_le_z": 1.4992,
		"dorsal_start_z": 1.3243,
		"fin_top_y": 0.4048,
		"fin_top_le_z": 1.6991,
		"fin_top_chord": 0.1249,
		"rudder_hinge_z": 1.7366,
		"rudder_te_bottom": [
			1.8615,
			-0.0125
		],
		"fin_thickness": 0.018,
		"hinge_gap": 0.003
	},
	"gear": {
		"main_axle": [
			0.025,
			-0.4123
		],
		"main_wheel_diameter": 0.1714,
		"main_wheel_width": 0.055,
		"track": 0.902,
		"strut_radius": 0.0137,
		"tail_axle": [
			1.6116,
			-0.1249
		],
		"tail_wheel_diameter": 0.0795
	},
	"propeller": {
		"diameter": 0.6604,
		"pitch": 0.3048,
		"blades": 4,
		"z": -0.4373,
		"hub_radius": 0.0431,
		"scale_diameter": 0.8505,
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
			0.6796,
			0.2324
		],
		"cap_brim_front": [
			0.6397,
			0.2099
		],
		"nose_front": [
			0.6447,
			0.1899
		],
		"head_back": [
			0.7096,
			0.1999
		],
		"chin": [
			0.6547,
			0.1699
		],
		"shoulder_front": [
			0.6372,
			0.1499
		],
		"shoulder_back": [
			0.7371,
			0.1449
		],
		"head_half_width": 0.025,
		"shoulder_half_width": 0.06
	},
	"evidence": {
		"full_size.overall": {
			"kind": "estimated",
			"source": "P-51D: span 37 ft 0 in / 11.28 m, length 32 ft 3 in / 9.83 m (warbirdsresourcegroup.org, DCS manual p18); wing area 235 ft2 (WRG) / 233.19 ft2 (DCS); propeller 11 ft 2 in (DCS). URLs and hashes in docs/research/p51-resources.json",
			"limits": "Fuselage sections, station lines, scoop and canopy proportions are read by eye from the public-domain AN 01-60-3 three-view (references/p51-mustang/drawings/), not measured on a calibrated plan. Gear track 11 ft 10 in and 27 in / 12.5 in wheels are unverified."
		},
		"full_size.wing": {
			"kind": "estimated",
			"source": "root/tip chord 104/50 in reproduce 235 ft2 to the centreline (Mason, VT: 101.8/46.4 in, AR 5.876 for 233 ft2: unresolved); dihedral 5 deg along 25 % chord and ~1 deg root incidence (modelflying.co.uk snippet); quarter chord assumed unswept",
			"limits": "Washout 0 is an assumption."
		},
		"full_size.tail": {
			"kind": "borrowed",
			"source": "Mason (Virginia Tech) P-51D configuration study: horizontal 45.4 ft2, span 13.1 ft, chords 4.6/2.3 ft; vertical 14.8 ft2, span 4.7 ft, chords 4.7/1.6 ft (references/p51-mustang/papers/)",
			"limits": "Dorsal fillet and positions along the fuselage are read from the three-view."
		},
		"section": {
			"kind": "borrowed",
			"source": "UIUC p51droot.dat (BL17.5: t/c 16.5 % at 39 %, camber 1.26 %) and p51dtip.dat (BL215: 11.4 % at 46 %, camber 1.30 %)",
			"limits": "The builder uses the root thickness distribution with a parabolic camber line; the true camber line is not reproduced."
		},
		"kit": {
			"kind": "estimated",
			"source": "No commercial ARF exists for 100-150 cc (research 2026-10-06): 1/4-scale plans (Veich: 284.5 cm, 1.36 m2, 18-27 kg; Bates 112 in, 50 lb+; FokkeRC 111 in, Kolm 155 cc). Engine DA-120 (desertaircraft.com, toni-clark.com). CG/throws from the Hangar 9 60cc, CARF and Ziroli manuals (references/p51-mustang/manuals/)",
			"limits": "Exact 1/4 scale assumed; the propeller choice and the throws are estimates."
		},
		"scaling": {
			"kind": "derived",
			"source": "assets/aircraft/p51d-mustang-120/build_geometry.py: every full-size length x kit.span / full_size.span",
			"method": "factor 0.24987 (1/4.00)"
		},
		"propeller": {
			"kind": "estimated",
			"source": "kit propeller size (not the scaled 11 ft 2 in Hamilton Standard, recorded as scale_diameter); paddle-blade planform by eye; pitch for the twist only",
			"limits": "visual stand-in"
		}
	}
}
