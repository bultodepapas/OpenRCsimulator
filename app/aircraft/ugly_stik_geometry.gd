# Generated from assets/aircraft/ugly-stik-60/geometry.json; edit that source.
# Visual geometry only. Every group has provenance in DATA.evidence.
extends RefCounted

const DATA := {
	"id": "jensen-60-nitro-61-v3",
	"units": "m",
	"axes": {
		"nose": "-Z",
		"right": "+X",
		"up": "+Y"
	},
	"datum": "Visual assembly origin near wing quarter chord; NOT a measured CG",
	"engine_class": ".61 nitro",
	"deferred_variants": [
		"mini",
		"giant"
	],
	"wing": {
		"span": 1.524,
		"chord": 0.3048,
		"root_y": 0.051,
		"leading_z": -0.115,
		"dihedral_deg": 2.86,
		"hinge_fraction": 0.88807069,
		"aileron_inner": 0.136515,
		"aileron_outer": 0.762,
		"tip_start": 0.688779,
		"section": [
			[
				0.0,
				0.0
			],
			[
				0.01251841,
				0.01782054
			],
			[
				0.03092784,
				0.0320286
			],
			[
				0.04933726,
				0.04476391
			],
			[
				0.08615611,
				0.06139801
			],
			[
				0.15979381,
				0.07257489
			],
			[
				0.23343152,
				0.076388
			],
			[
				0.30706922,
				0.07578285
			],
			[
				0.41752577,
				0.07119323
			],
			[
				0.52798233,
				0.05923985
			],
			[
				0.63843888,
				0.04728647
			],
			[
				0.74889543,
				0.02944207
			],
			[
				0.82253314,
				0.02073677
			],
			[
				0.87407953,
				0.0147167
			],
			[
				0.88807069,
				0.00825415
			],
			[
				1.0,
				0.0
			],
			[
				0.88807069,
				-0.00794615
			],
			[
				0.82253314,
				-0.01387295
			],
			[
				0.74889543,
				-0.02210432
			],
			[
				0.63843888,
				-0.03297863
			],
			[
				0.52798233,
				-0.04458931
			],
			[
				0.41752577,
				-0.05546361
			],
			[
				0.30706922,
				-0.06412879
			],
			[
				0.23343152,
				-0.06646914
			],
			[
				0.15979381,
				-0.06439124
			],
			[
				0.08615611,
				-0.04979492
			],
			[
				0.04933726,
				-0.03771031
			],
			[
				0.03092784,
				-0.02761793
			],
			[
				0.01251841,
				-0.01678918
			]
		],
		"tip_le_span": 0.699948,
		"hinge_gap": 0.0016,
		"inboard_gap": 0.0015
	},
	"fuselage_stations": [
		[
			-0.291276,
			0.039116,
			0.037926,
			-0.049958
		],
		[
			-0.153862,
			0.048514,
			0.0458,
			-0.051482
		],
		[
			-0.096712,
			0.050292,
			0.038942,
			-0.05199
		],
		[
			0.016318,
			0.05207,
			0.03183,
			-0.052752
		],
		[
			0.192848,
			0.051689,
			0.043514,
			-0.052752
		],
		[
			0.317308,
			0.047752,
			0.035132,
			-0.052498
		],
		[
			0.477328,
			0.0381,
			0.013542,
			-0.05199
		],
		[
			0.600518,
			0.02633,
			-0.002206,
			-0.051482
		],
		[
			0.791018,
			0.008128,
			-0.031162,
			-0.051228
		]
	],
	"tail": {
		"y": -0.04564,
		"hinge_z": 0.801178,
		"span": 0.5588,
		"stab_outline": [
			[
				-0.27305,
				0.0
			],
			[
				-0.2667,
				-0.029972
			],
			[
				-0.254,
				-0.085852
			],
			[
				-0.2413,
				-0.141986
			],
			[
				-0.2159,
				-0.146558
			],
			[
				0.2159,
				-0.146558
			],
			[
				0.2413,
				-0.141986
			],
			[
				0.254,
				-0.085852
			],
			[
				0.2667,
				-0.029972
			],
			[
				0.27305,
				0.0
			]
		],
		"elevator_outline": [
			[
				-0.27305,
				0
			],
			[
				-0.2794,
				0.025908
			],
			[
				-0.2794,
				0.03048
			],
			[
				-0.27305,
				0.03683
			],
			[
				0.27305,
				0.03683
			],
			[
				0.2794,
				0.03048
			],
			[
				0.2794,
				0.025908
			],
			[
				0.27305,
				0
			]
		],
		"fin_outline": [
			[
				0.028956,
				-0.19177
			],
			[
				0.050292,
				-0.19685
			],
			[
				0.065532,
				-0.19812
			],
			[
				0.080772,
				-0.19558
			],
			[
				0.096012,
				-0.1905
			],
			[
				0.111252,
				-0.18288
			],
			[
				0.126492,
				-0.17272
			],
			[
				0.141732,
				-0.16002
			],
			[
				0.156972,
				-0.14478
			],
			[
				0.170942,
				-0.127
			],
			[
				0.182372,
				-0.10922
			],
			[
				0.193802,
				-0.08382
			],
			[
				0.200914,
				-0.05842
			],
			[
				0.206248,
				-0.03302
			],
			[
				0.209296,
				-0.0127
			],
			[
				0.208788,
				0.0
			],
			[
				0.0,
				0.0
			]
		],
		"rudder_outline": [
			[
				0.208788,
				0.0
			],
			[
				0.20574,
				0.02032
			],
			[
				0.198882,
				0.04064
			],
			[
				0.187452,
				0.06096
			],
			[
				0.168402,
				0.0762
			],
			[
				0.146812,
				0.0889
			],
			[
				0.121412,
				0.09906
			],
			[
				0.092202,
				0.10414
			],
			[
				0.083312,
				0.10541
			],
			[
				0.071882,
				0.10414
			],
			[
				0.057912,
				0.10033
			],
			[
				0.040132,
				0.09144
			],
			[
				0.026162,
				0.0762
			],
			[
				0.014732,
				0.05588
			],
			[
				0.005842,
				0.03048
			],
			[
				-0.000508,
				0.0
			]
		],
		"thickness": 0.007,
		"hinge_gap": 0.004,
		"elevator_cutout_half_width": 0.03,
		"fin_thickness": 0.00635,
		"fin_y": -0.031162,
		"rudder_hinge_z": 0.792288,
		"ventral_outline": [
			[
				-0.020828,
				-0.23622
			],
			[
				-0.020066,
				-0.00254
			],
			[
				-0.057658,
				-0.00254
			]
		],
		"ventral_thickness": 0.0047625,
		"elevator_cutout_start": 0.024
	},
	"equipment": {
		"firewall_z": -0.291276,
		"shaft_y": -0.005,
		"prop_z": -0.408276,
		"prop_diameter": 0.3048,
		"main_wheel_diameter": 0.0762,
		"nose_wheel_diameter": 0.06985,
		"wheel_y": -0.22,
		"main_axle_z": 0.1,
		"main_track": 0.36,
		"nose_axle_z": -0.251276
	},
	"evidence": {
		"wing.span": {
			"kind": "manual",
			"source": "signed Jensen oz1253 title block, 60 in",
			"uncertainty_m": null
		},
		"wing.chord": {
			"kind": "estimated",
			"source": "720 in² / 60 in = 12 in representative chord; rectangular visual simplification"
		},
		"wing.section": {
			"kind": "estimated",
			"source": "research/ugly-stik/model-v3/wing-trace.json",
			"method": "Manually traced normalized rib contour of Jensen sheet2; page chord differs from sheet1 so keep installed nominal chord; LE/TE line removed before ordinate normalization. No polar inferred."
		},
		"wing.dihedral_deg": {
			"kind": "estimated",
			"source": "visual angle initially atan(1.5/30); plan tip-rise callout is not a published angle; installed angle awaits calibration"
		},
		"wing.other": {
			"kind": "estimated",
			"source": "research/ugly-stik/model-v3/wing-trace.json",
			"method": "Hinge fraction from section trace; aileron inner and swept tip span fractions from plan-view pixels normalized to 60 in. Tip scallops/rounded corners simplified, incidence remains visual default."
		},
		"fuselage_stations": {
			"kind": "estimated",
			"source": "research/ugly-stik/model-v3/us02-jensen-sheet1-metrology.json; fuselage-adoption.json",
			"method": "F4/F5/F6 measured in source pixels, local scale .254mm/px; front/hidden roof and terminal widths remain estimated. Parent uses y_proxy2595 (1px different from US02 candidate2596); common datum not measured thrustline. Fin-root roof point from parent assembled side trace. No longitudinal fit to old mesh. See per-station adoption record."
		},
		"tail": {
			"kind": "estimated",
			"source": "research/ugly-stik/model-v3/tail-adoption.json; US02 report",
			"method": "Separate assembled-side elevator/rudder hinge stations. Horizontal planform uses current US02 LE3838/TE4560/span1100px per side with swept outer-edge picks and simplified corner/scallop detail. Fin/rudder parent trace from continuous assembled side view, not upper decorative detail. Page scale locally supported; vertical registration uses estimated F1 center. 7mm horizontal thickness is an estimated side-envelope. No aerodynamic area/inertia changed."
		},
		"equipment.wheels": {
			"kind": "manual",
			"source": "Jensen plan 2.75 in nose, selected 3 in main from 3 or 3.25 in callout"
		},
		"equipment.engine": {
			"kind": "estimated",
			"source": "visual .61 single cylinder, provisional envelope informed by O.S. MAX-61FX manual p40; accessories simplified; brand not selected"
		},
		"equipment.other": {
			"kind": "estimated",
			"source": "12in prop and gear placement remain estimated. V2 moves prop and nose axle with F1 by +0.148724m, preserving installation offsets; shaft height and main gear unchanged."
		},
		"decoration": {
			"kind": "estimated",
			"source": "red/cream top and charcoal underside selected for readability; not claimed as a canonical livery"
		},
		"equipment.firewall_z": {
			"kind": "measured",
			"source": "research/d1/jensen_plan_cg.py; signed Jensen oz1253 page1; F1frontx114, LEx808 at100dpi",
			"method": "wing.leading_z - (808-114)/100*0.0254",
			"value_m_from_le": -0.17627600000000002,
			"uncertainty_m": 0.002,
			"scope": "Local scan reading; page scale supported by 12.07in chord vs 12in nominal, not a globally calibrated built-aircraft dimension"
		},
		"wing.hinge_gap": {
			"kind": "estimated",
			"source": "Visual hinge relief sized for traced section half-thickness and existing +/-20 degree control travel; must pass mesh clearance checks. Inboard span relief is 1.5 mm for separate fixed and moving trailing edges."
		},
		"tail.relief": {
			"kind": "estimated",
			"source": "Visual kinematic relief: 4mm hinge separation, central elevator U-notch half-width30mm starting24mm aft of hinge (front bridge retained), fin sheet 1/4in from signed plan; clearance tested at simulator throws (not claimed as Jensen published throws). Horizontal envelope7mm; ventral sheet3/16in from plan, silhouette simplified; rudder hinge differs from elevator by8.89mm."
		},
		"details": {
			"kind": "estimated",
			"source": "Two stylized visible crossing wing retainers and dowels inspired by Jensen mounting instructions (not reproduction of full 12–14 band count); carburetor/exhaust outlet and steerable nose fork simplified. Visual angles supplied externally; no physics from mesh."
		},
		"wing.root_y": {
			"kind": "estimated",
			"source": "US02 side-view LE y~2375 vs estimated thrust proxy2595; .051m adopted and seat checked on actual mesh."
		}
	}
}
