# Generated, do not edit. Source: assets/aircraft/turbo-lumber-evolution/geometry.json (revision r2-d75ae605aa3a).
# Regenerate with: python3 assets/aircraft/turbo-lumber-evolution/compile_geometry.py
# Visual preview geometry of the author's r2 export (see DATA.evidence); not flyable.
extends RefCounted

const DATA := {
	"schema": "openrc-timber-geometry v1",
	"revision": "r2-d75ae605aa3a",
	"catalog_id": "turbo-lumber-evolution",
	"source_alias": "eflite_turbo_timber_evolution",
	"status": "visual preview geometry of the author's r2 export; dimensions measured on the Godot-imported scene, ranges and installation angles estimated by the author; not calibrated, not flyable",
	"generator": "assets/aircraft/turbo-lumber-evolution/build_geometry.py",
	"inputs": {
		"manifest": "assets/aircraft/turbo-lumber-evolution/source-manifest.json",
		"glb_sha256": "d75ae605aa3afdf3f417a0ec535c3bd3126c2a5a4eb7827393727152245c6722",
		"metadata_sha256": "e596b4044ae18547a9bbf7c2f594e1f2d6108ca90d25a1aa4295db6746c7c724",
		"measurements": {
			"generator": "research/timber/tt02/measure_mesh.gd",
			"godot": "4.8-beta1 (official)",
			"format": "openrc-timber-mesh-measurements v1"
		},
		"manual": "assets/aircraft/turbo-lumber-evolution/manual.json",
		"hardware_revision": {
			"value": "EFL105250B / EFL105275B (2024 B revision: 70 A Avian Smart Lite ESC, heavier gear springs)",
			"kind": "manual",
			"source": "TT-00 sources.md, Horizon Hobby product pages; the r1 mesh revision is unconfirmed by its author"
		}
	},
	"units": "m",
	"axes": {
		"nose": "-Z",
		"right": "+X",
		"up": "+Y"
	},
	"datum": {
		"id": "D0",
		"definition": "symmetry plane  x  wing-root leading-edge station  x  CAD thrust-axis height (motor shaft line before down/right thrust)",
		"position": [
			0.0,
			0.0,
			0.0
		],
		"contract_frame": "aircraft contract positions [x_aft, y_right, z_up] = [z_model, x_model, y_model]; the root LE datum of the data file is D0, so AirplaneBuilder.datum() = (0, 0)"
	},
	"scene": {
		"imported_root": "timber",
		"aircraft_node": "TurboTimberEvolution",
		"mesh_nodes": {
			"aileron_left": {
				"parent": "aileron_left_hinge",
				"triangles": 928.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"aileron_right": {
				"parent": "aileron_right_hinge",
				"triangles": 928.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"canopy_glass": {
				"parent": "TurboTimberEvolution",
				"triangles": 1032.0,
				"surfaces": 1.0,
				"materials": [
					"glass"
				],
				"local_identity": true
			},
			"cowl": {
				"parent": "TurboTimberEvolution",
				"triangles": 2310.0,
				"surfaces": 4.0,
				"materials": [
					"white",
					"black",
					"red",
					"metal"
				],
				"local_identity": true
			},
			"elevator": {
				"parent": "elevator_hinge",
				"triangles": 1462.0,
				"surfaces": 3.0,
				"materials": [
					"white",
					"black",
					"red"
				],
				"local_identity": true
			},
			"fin_fixed": {
				"parent": "TurboTimberEvolution",
				"triangles": 2314.0,
				"surfaces": 3.0,
				"materials": [
					"red",
					"black",
					"white"
				],
				"local_identity": true
			},
			"flap_left": {
				"parent": "flap_left_hinge",
				"triangles": 1392.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"flap_right": {
				"parent": "flap_right_hinge",
				"triangles": 1392.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"fuselage_core": {
				"parent": "TurboTimberEvolution",
				"triangles": 4542.0,
				"surfaces": 4.0,
				"materials": [
					"white",
					"red",
					"black",
					"light_red"
				],
				"local_identity": true
			},
			"gear_cables": {
				"parent": "TurboTimberEvolution",
				"triangles": 112.0,
				"surfaces": 1.0,
				"materials": [
					"metal"
				],
				"local_identity": true
			},
			"gear_left_leg": {
				"parent": "gear_left_suspension",
				"triangles": 794.0,
				"surfaces": 2.0,
				"materials": [
					"white",
					"metal"
				],
				"local_identity": true
			},
			"gear_right_leg": {
				"parent": "gear_right_suspension",
				"triangles": 794.0,
				"surfaces": 2.0,
				"materials": [
					"white",
					"metal"
				],
				"local_identity": true
			},
			"propeller_rotor": {
				"parent": "propeller_spin",
				"triangles": 3580.0,
				"surfaces": 2.0,
				"materials": [
					"black",
					"metal"
				],
				"local_identity": true
			},
			"rudder": {
				"parent": "rudder_hinge",
				"triangles": 1244.0,
				"surfaces": 3.0,
				"materials": [
					"white",
					"red",
					"black"
				],
				"local_identity": true
			},
			"stabilizer_fixed": {
				"parent": "TurboTimberEvolution",
				"triangles": 4999.0,
				"surfaces": 3.0,
				"materials": [
					"white",
					"black",
					"red"
				],
				"local_identity": true
			},
			"tailwheel": {
				"parent": "tailwheel_axle",
				"triangles": 816.0,
				"surfaces": 2.0,
				"materials": [
					"foam",
					"light_grey"
				],
				"local_identity": true
			},
			"tailwheel_fork": {
				"parent": "tailwheel_steer",
				"triangles": 238.0,
				"surfaces": 1.0,
				"materials": [
					"metal"
				],
				"local_identity": true
			},
			"wheel_left": {
				"parent": "wheel_left_axle",
				"triangles": 1660.0,
				"surfaces": 2.0,
				"materials": [
					"foam",
					"light_grey"
				],
				"local_identity": true
			},
			"wheel_right": {
				"parent": "wheel_right_axle",
				"triangles": 1660.0,
				"surfaces": 2.0,
				"materials": [
					"foam",
					"light_grey"
				],
				"local_identity": true
			},
			"wing_left_fixed": {
				"parent": "TurboTimberEvolution",
				"triangles": 5197.0,
				"surfaces": 5.0,
				"materials": [
					"white",
					"black",
					"red",
					"dark_grey",
					"light_red"
				],
				"local_identity": true
			},
			"wing_right_fixed": {
				"parent": "TurboTimberEvolution",
				"triangles": 5125.0,
				"surfaces": 5.0,
				"materials": [
					"white",
					"black",
					"red",
					"dark_grey",
					"light_green"
				],
				"local_identity": true
			}
		},
		"materials": {
			"black": {
				"albedo": [
					0.142826,
					0.142826,
					0.151704,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"dark_grey": {
				"albedo": [
					0.2717,
					0.2717,
					0.282779,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"foam": {
				"albedo": [
					0.151704,
					0.151704,
					0.151704,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"glass": {
				"albedo": [
					0.484529,
					0.516881,
					0.546854,
					0.45
				],
				"emission": false,
				"transparency": 4.0,
				"class": "StandardMaterial3D"
			},
			"light_green": {
				"albedo": [
					0.34919,
					0.954687,
					0.484529,
					1.0
				],
				"emission": true,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"light_grey": {
				"albedo": [
					0.701411,
					0.70837,
					0.722027,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"light_red": {
				"albedo": [
					0.954687,
					0.247801,
					0.189748,
					1.0
				],
				"emission": true,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"metal": {
				"albedo": [
					0.906332,
					0.906332,
					0.916274,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"red": {
				"albedo": [
					0.701411,
					0.112075,
					0.086104,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			},
			"white": {
				"albedo": [
					0.930925,
					0.930925,
					0.926075,
					1.0
				],
				"emission": false,
				"transparency": 0.0,
				"class": "StandardMaterial3D"
			}
		},
		"counts": {
			"animation_players": 0.0,
			"cameras": 0.0,
			"lights": 0.0,
			"mesh_instances": 21.0,
			"surfaces": 49.0,
			"triangles": 42519.0
		},
		"compressed_vertex_attributes": false,
		"godot": "4.8-beta1 (official)"
	},
	"dimensions": {
		"span": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): outermost vertices of the wing and control sections, including lenses and brackets"
		},
		"span_skin": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): outermost non-excluded skin vertices of the wing and control sections"
		},
		"length": {
			"value": 1.115461,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): rudder trailing edge minus spinner tip along z (manual: 1.040 m)"
		},
		"height": {
			"value": 0.434,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): fin top minus main-wheel bottom at neutral suspension"
		},
		"bbox": {
			"min": [
				-0.772752,
				-0.256,
				-0.283461
			],
			"max": [
				0.772752,
				0.178,
				0.832
			]
		},
		"forward_extent_vertex": {
			"mesh": "propeller_rotor",
			"surface": 0.0,
			"material": "black",
			"root": [
				0.001116,
				-0.001117,
				-0.283461
			],
			"local": [
				0.041372,
				0.0,
				0.0
			],
			"finding": "the spinner tip of propeller_rotor (author landmark); the extent is measured at the furthest mesh vertex, not from a tilted axis-aligned box"
		},
		"manual_span": {
			"value": 1.555,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (1,555 mm)"
		},
		"manual_length": {
			"value": 1.04,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (1,040 mm); measurement endpoints not stated"
		}
	},
	"landmarks": {
		"left_wingtip": {
			"author": [
				-0.772752,
				0.077909,
				0.186293
			],
			"measured": [
				-0.772752,
				0.077909,
				0.186293
			],
			"compared_axes": [
				0.0
			],
			"difference_mm": 0.0,
			"definition": "outermost vertex of wing_left_fixed (pilot's left)"
		},
		"right_wingtip": {
			"author": [
				0.772752,
				0.077909,
				0.186293
			],
			"measured": [
				0.772752,
				0.077909,
				0.186293
			],
			"compared_axes": [
				0.0
			],
			"difference_mm": 0.0,
			"definition": "outermost vertex of wing_right_fixed"
		},
		"nose_spinner_tip": {
			"author": [
				0.001116,
				-0.001117,
				-0.283461
			],
			"measured": [
				0.001116,
				-0.001117,
				-0.283461
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "foremost vertex of propeller_rotor"
		},
		"tail_rudder_trailing_edge": {
			"author": [
				-0.0,
				0.002,
				0.832
			],
			"measured": [
				0.0,
				0.002,
				0.832
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "aftmost vertex of rudder"
		},
		"wing_root_leading_edge": {
			"author": [
				0.001263,
				0.097386,
				3.2e-05
			],
			"measured": [
				0.001023,
				0.095985,
				0.000164
			],
			"compared_axes": [
				0.0
			],
			"difference_mm": 0.24,
			"definition": "foremost wing vertex within 3 mm of the symmetry plane"
		},
		"left_main_wheel_center": {
			"author": [
				-0.131979,
				-0.198,
				0.008
			],
			"measured": [
				-0.131979,
				-0.198,
				0.008
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "wheel_left_axle origin"
		},
		"right_main_wheel_center": {
			"author": [
				0.131979,
				-0.198,
				0.008
			],
			"measured": [
				0.131979,
				-0.198,
				0.008
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "wheel_right_axle origin"
		},
		"tailwheel_center": {
			"author": [
				0.0,
				-0.112,
				0.759
			],
			"measured": [
				0.0,
				-0.112,
				0.759
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "tailwheel_axle origin"
		},
		"propeller_hub": {
			"author": [
				-0.000327,
				0.000327,
				-0.24214
			],
			"measured": [
				-0.000327,
				0.000327,
				-0.24214
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "propeller_spin origin"
		},
		"datum_D0": {
			"author": [
				0.0,
				0.0,
				-0.0
			],
			"measured": [
				0.0,
				0.0,
				0.0
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": "root node origin"
		},
		"left_main_wheel_contact": {
			"author": [
				-0.132,
				-0.256,
				0.008
			],
			"measured": [
				-0.131979,
				-0.256,
				0.008
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.021,
			"definition": "lowest vertex of wheel_left (neutral, no ground)"
		},
		"right_main_wheel_contact": {
			"author": [
				0.132,
				-0.256,
				0.008
			],
			"measured": [
				0.131979,
				-0.256,
				0.008
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.021,
			"definition": "lowest vertex of wheel_right"
		},
		"tailwheel_contact": {
			"author": [
				-0.000331,
				-0.125999,
				0.759057
			],
			"measured": [
				0.0,
				-0.125999,
				0.759
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.331,
			"definition": "lowest vertex of tailwheel"
		}
	},
	"articulations": {
		"aileron_left_hinge": {
			"node": "aileron_left_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "aileron_left",
			"members": "left aileron + horn",
			"pivot": [
				-0.562017,
				0.116965,
				0.157726
			],
			"axis": [
				0.999391,
				-0.034899,
				0.0
			],
			"rest_translation": [
				-0.562017,
				0.116965,
				0.157726
			],
			"rest_basis": {
				"x": [
					0.999391,
					-0.034899,
					0.0
				],
				"y": [
					0.034899,
					0.999391,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				-0.017452,
				0.999848
			],
			"range_deg": [
				-22.0,
				22.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge down",
			"driven_by": "roll: right stick -> right aileron negative (up), left aileron positive (down); authored differential 0.7 (down travel = 0.7 x up travel)",
			"app_key": "aileron_left",
			"app_sign": -1.0
		},
		"flap_left_hinge": {
			"node": "flap_left_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "flap_left",
			"members": "left flap + horn",
			"pivot": [
				-0.240247,
				0.105729,
				0.157726
			],
			"axis": [
				0.999391,
				-0.034899,
				0.0
			],
			"rest_translation": [
				-0.240247,
				0.105729,
				0.157726
			],
			"rest_basis": {
				"x": [
					0.999391,
					-0.034899,
					0.0
				],
				"y": [
					0.034899,
					0.999391,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				-0.017452,
				0.999848
			],
			"range_deg": [
				0.0,
				40.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge down",
			"driven_by": "flap channel (both flaps equal)",
			"app_key": "flap_left",
			"app_sign": 1.0
		},
		"aileron_right_hinge": {
			"node": "aileron_right_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "aileron_right",
			"members": "right aileron + horn",
			"pivot": [
				0.562017,
				0.116965,
				0.157726
			],
			"axis": [
				0.999391,
				0.034899,
				0.0
			],
			"rest_translation": [
				0.562017,
				0.116965,
				0.157726
			],
			"rest_basis": {
				"x": [
					0.999391,
					0.034899,
					0.0
				],
				"y": [
					-0.034899,
					0.999391,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				0.017452,
				0.999848
			],
			"range_deg": [
				-22.0,
				22.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge down",
			"driven_by": "roll: right stick -> right aileron negative (up), left aileron positive (down); authored differential 0.7 (down travel = 0.7 x up travel)",
			"app_key": "aileron_right",
			"app_sign": -1.0
		},
		"flap_right_hinge": {
			"node": "flap_right_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "flap_right",
			"members": "right flap + horn",
			"pivot": [
				0.240247,
				0.105729,
				0.157726
			],
			"axis": [
				0.999391,
				0.034899,
				0.0
			],
			"rest_translation": [
				0.240247,
				0.105729,
				0.157726
			],
			"rest_basis": {
				"x": [
					0.999391,
					0.034899,
					0.0
				],
				"y": [
					-0.034899,
					0.999391,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				0.017452,
				0.999848
			],
			"range_deg": [
				0.0,
				40.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge down",
			"driven_by": "flap channel (both flaps equal)",
			"app_key": "flap_right",
			"app_sign": 1.0
		},
		"elevator_hinge": {
			"node": "elevator_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "elevator",
			"members": "one-piece elevator (both halves + torsion rod), markings, horn",
			"pivot": [
				0.0,
				-0.032,
				0.704
			],
			"axis": [
				1.0,
				0.0,
				0.0
			],
			"rest_translation": [
				0.0,
				-0.032,
				0.704
			],
			"rest_basis": {
				"x": [
					1.0,
					0.0,
					0.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				0.0,
				1.0
			],
			"range_deg": [
				-22.0,
				22.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge down (nose-down pitch)",
			"driven_by": "pitch: stick back (nose up) -> negative; single one-piece elevator joined by a torsion rod",
			"app_key": "elevator",
			"app_sign": -1.0
		},
		"rudder_hinge": {
			"node": "rudder_hinge",
			"parent": "TurboTimberEvolution",
			"mesh_node": "rudder",
			"members": "rudder + markings + horn",
			"pivot": [
				0.0,
				0.0538,
				0.738
			],
			"axis": [
				0.0,
				1.0,
				0.0
			],
			"rest_translation": [
				0.0,
				0.0538,
				0.738
			],
			"rest_basis": {
				"x": [
					0.0,
					1.0,
					0.0
				],
				"y": [
					0.0,
					0.0,
					1.0
				],
				"z": [
					1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.5,
				0.5,
				0.5,
				0.5
			],
			"range_deg": [
				-30.0,
				30.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "trailing edge to the pilot's right (nose right)",
			"driven_by": "yaw: right pedal -> positive",
			"app_key": "rudder",
			"app_sign": 1.0
		},
		"tailwheel_steer": {
			"node": "tailwheel_steer",
			"parent": "TurboTimberEvolution",
			"mesh_node": "tailwheel_fork",
			"members": "steerable tailwheel wire (coaxial with rudder hinge)",
			"pivot": [
				0.0,
				-0.084092,
				0.738
			],
			"axis": [
				0.0,
				1.0,
				0.0
			],
			"rest_translation": [
				0.0,
				-0.084092,
				0.738
			],
			"rest_basis": {
				"x": [
					0.0,
					1.0,
					0.0
				],
				"y": [
					0.0,
					0.0,
					1.0
				],
				"z": [
					1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.5,
				0.5,
				0.5,
				0.5
			],
			"range_deg": [
				-30.0,
				30.0
			],
			"range_kind": "estimated",
			"range_source": "delivery spec r2 / authored (follows rudder)",
			"positive": "trailing wheel to the pilot's right (follows the rudder)",
			"driven_by": "coupled to rudder_hinge 1:1 (wire tip sits inside the rudder)",
			"app_key": null,
			"app_sign": null,
			"coupling": {
				"follows": "rudder_hinge",
				"ratio": 1.0,
				"note": "tailwheel wire rides in the rudder; coaxial hinge line"
			}
		},
		"tailwheel_axle": {
			"node": "tailwheel_axle",
			"parent": "tailwheel_steer",
			"mesh_node": "tailwheel",
			"members": "tailwheel tire + hub",
			"pivot": [
				0.0,
				-0.112,
				0.759
			],
			"axis": [
				-1.0,
				0.0,
				0.0
			],
			"rest_translation": [
				-0.027908,
				0.021,
				0.0
			],
			"rest_basis": {
				"x": [
					0.0,
					0.0,
					-1.0
				],
				"y": [
					1.0,
					0.0,
					0.0
				],
				"z": [
					0.0,
					-1.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.5,
				0.5,
				-0.5,
				0.5
			],
			"range_deg": null,
			"range_kind": "continuous",
			"range_source": "continuous",
			"positive": "forward rolling",
			"driven_by": "ground contact (rolling without slip, radius 14.0 mm)",
			"app_key": null,
			"app_sign": null,
			"radius": {
				"value": 0.014,
				"unit": "m",
				"kind": "estimated",
				"source": "r2/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
			}
		},
		"propeller_spin": {
			"node": "propeller_spin",
			"parent": "thrust_frame",
			"mesh_node": "propeller_rotor",
			"members": "rotating: 3 blades, spinner, backplate, outrunner bell",
			"pivot": [
				-0.000327,
				0.000327,
				-0.24214
			],
			"axis": [
				0.034878,
				-0.034899,
				-0.998782
			],
			"rest_translation": [
				-0.009372,
				0.0,
				0.0
			],
			"rest_basis": {
				"x": [
					1.0,
					0.0,
					0.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					0.0,
					0.0,
					1.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.0,
				0.0,
				1.0
			],
			"range_deg": null,
			"range_kind": "continuous",
			"range_source": "continuous",
			"positive": "normal tractor rotation: clockwise seen from behind (pilot view)",
			"driven_by": "throttle / motor rpm",
			"app_key": null,
			"app_sign": null
		},
		"gear_left_suspension": {
			"node": "gear_left_suspension",
			"parent": "TurboTimberEvolution",
			"mesh_node": "gear_left_leg",
			"members": "left leg + axle bolt + spacer + wire link",
			"pivot": [
				-0.046,
				-0.090347,
				0.031
			],
			"axis": [
				0.0,
				0.0,
				-1.0
			],
			"rest_translation": [
				-0.046,
				-0.090347,
				0.031
			],
			"rest_basis": {
				"x": [
					0.0,
					0.0,
					-1.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.707107,
				0.0,
				0.707107
			],
			"range_deg": [
				0.0,
				12.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler); cross-wire springs limit it",
			"positive": "leg swings outboard (left)",
			"driven_by": "ground load (suspension); springs: cross cables with tension springs, see metadata",
			"app_key": null,
			"app_sign": null
		},
		"wheel_left_axle": {
			"node": "wheel_left_axle",
			"parent": "gear_left_suspension",
			"mesh_node": "wheel_left",
			"members": "left tire, hub, washer, nut",
			"pivot": [
				-0.131979,
				-0.198,
				0.008
			],
			"axis": [
				-1.0,
				0.0,
				0.0
			],
			"rest_translation": [
				0.023,
				-0.107653,
				-0.085979
			],
			"rest_basis": {
				"x": [
					0.0,
					0.0,
					-1.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				0.707107,
				0.0,
				0.707107
			],
			"range_deg": null,
			"range_kind": "continuous",
			"range_source": "continuous",
			"positive": "forward rolling",
			"driven_by": "ground contact (rolling without slip, radius 58.0 mm)",
			"app_key": null,
			"app_sign": null,
			"radius": {
				"value": 0.058,
				"unit": "m",
				"kind": "estimated",
				"source": "r2/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
			}
		},
		"gear_right_suspension": {
			"node": "gear_right_suspension",
			"parent": "TurboTimberEvolution",
			"mesh_node": "gear_right_leg",
			"members": "right leg + axle bolt + spacer + wire link",
			"pivot": [
				0.046,
				-0.090347,
				0.031
			],
			"axis": [
				0.0,
				0.0,
				1.0
			],
			"rest_translation": [
				0.046,
				-0.090347,
				0.031
			],
			"rest_basis": {
				"x": [
					0.0,
					0.0,
					1.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					-1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				-0.707107,
				0.0,
				0.707107
			],
			"range_deg": [
				0.0,
				12.0
			],
			"range_kind": "estimated",
			"range_source": "authored approximation (no manufacturer manual available to the modeler); cross-wire springs limit it",
			"positive": "leg swings outboard (right)",
			"driven_by": "ground load (suspension); springs: cross cables with tension springs, see metadata",
			"app_key": null,
			"app_sign": null
		},
		"wheel_right_axle": {
			"node": "wheel_right_axle",
			"parent": "gear_right_suspension",
			"mesh_node": "wheel_right",
			"members": "right tire, hub, washer, nut",
			"pivot": [
				0.131979,
				-0.198,
				0.008
			],
			"axis": [
				-1.0,
				0.0,
				0.0
			],
			"rest_translation": [
				-0.023,
				-0.107653,
				-0.085979
			],
			"rest_basis": {
				"x": [
					0.0,
					0.0,
					1.0
				],
				"y": [
					0.0,
					1.0,
					0.0
				],
				"z": [
					-1.0,
					0.0,
					0.0
				]
			},
			"rest_quaternion_xyzw": [
				0.0,
				-0.707107,
				0.0,
				0.707107
			],
			"range_deg": null,
			"range_kind": "continuous",
			"range_source": "continuous",
			"positive": "forward rolling",
			"driven_by": "ground contact (rolling without slip, radius 58.0 mm)",
			"app_key": null,
			"app_sign": null,
			"radius": {
				"value": 0.058,
				"unit": "m",
				"kind": "estimated",
				"source": "r2/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
			}
		}
	},
	"thrust": {
		"node": "thrust_frame",
		"fixed": true,
		"parent": "TurboTimberEvolution",
		"origin": {
			"value": [
				0.0,
				0.0,
				-0.2515
			],
			"unit": "m",
			"kind": "measured",
			"source": "r2/metadata.json (author's CAD export): propeller hub, CAD x = -251.5 mm"
		},
		"direction": {
			"value": [
				0.034878,
				-0.034899,
				-0.998782
			],
			"unit": "1",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): thrust_frame local +X in the root frame"
		},
		"rest_basis": {
			"x": [
				0.034878,
				-0.034899,
				-0.998782
			],
			"y": [
				0.001218,
				0.999391,
				-0.034878
			],
			"z": [
				0.999391,
				0.0,
				0.034899
			]
		},
		"rest_translation": [
			0.0,
			0.0,
			-0.2515
		],
		"rest_quaternion_xyzw": [
			-0.012123,
			0.694553,
			-0.012554,
			0.71923
		],
		"downthrust_deg": {
			"value": 2.0,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json) (author: 2 deg estimated, typical for the type)"
		},
		"right_thrust_deg": {
			"value": 2.0,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json) (author: 2 deg estimated, typical for the type)"
		},
		"spin_node": "propeller_spin",
		"spin_rest_translation": [
			-0.009372,
			0.0,
			0.0
		],
		"rotation_sense": "clockwise seen from behind (normal tractor) = positive about the thrust direction",
		"propeller_radius": {
			"value": 0.14032,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): largest radial distance of a rotor vertex from the thrust axis (author estimate 0.1381 m; manual 11 in = 0.1397 m)"
		},
		"spinner_tip": {
			"value": [
				0.001116,
				-0.001117,
				-0.283461
			],
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): rotor vertex furthest along the thrust axis"
		},
		"rotor_axial_extent": [
			-0.0505,
			0.032
		]
	},
	"wing": {
		"planform": "rectangular, constant chord from the fuselage side to the last aileron station, rounded tips; the model is mirrored about x = 0",
		"span": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): outermost vertices of the wing and control sections, including lenses and brackets"
		},
		"span_skin": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): outermost non-excluded skin vertices of the wing and control sections"
		},
		"le_z": {
			"value": 1.6e-05,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): median leading-edge z of the constant-chord stations (datum D0 is the root LE station)"
		},
		"te_z": {
			"value": 0.21287,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): median trailing-edge z of the flap/aileron stations"
		},
		"chord": {
			"value": 0.212854,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): te_z - le_z, constant over the flap and aileron stations"
		},
		"mac": {
			"value": 0.212854,
			"unit": "m",
			"kind": "derived",
			"source": "rectangular panel: MAC = chord (r2 metadata: 0.213 m from the CAD)"
		},
		"area": {
			"value": 0.327007,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: trapezoid integral of the measured chord over the span, fuselage carry-through at the panel chord, rounded tips from the tip slices (r2 CAD: 0.329 m2)"
		},
		"area_rectangular": {
			"value": 0.328967,
			"unit": "m2",
			"kind": "derived",
			"source": "span x chord, no tip rounding"
		},
		"panel_x": [
			0.06,
			0.69
		],
		"fuselage_half_width_at_wing": {
			"value": 0.0605,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): largest fixed-skin half-width of the fuselage slices between z = 0.06 and 0.16 m"
		},
		"hinge_z": {
			"value": 0.157726,
			"unit": "m",
			"kind": "measured",
			"source": "r2/metadata.json (author's CAD export): aileron and flap pivots share z = 0.157726 m"
		},
		"hinge_fraction": {
			"value": 0.7409,
			"unit": "1",
			"kind": "derived",
			"source": "(hinge_z - le_z) / chord"
		},
		"control_chord_aft_of_hinge": {
			"value": 0.055144,
			"unit": "m",
			"kind": "measured",
			"source": "te_z - hinge_z"
		},
		"control_nose_ahead_of_hinge": {
			"value": 0.00687,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): rounded control-surface nose ahead of the pivot"
		},
		"aileron_x": [
			0.4301,
			0.694449
		],
		"flap_x": [
			0.054329,
			0.426612
		],
		"dihedral_deg": {
			"value": 1.977,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): slope of the leading-edge y over the panel stations (author: 2 deg)"
		},
		"incidence_deg": {
			"value": 2.0,
			"unit": "deg",
			"kind": "estimated",
			"source": "r2/metadata.json (author's CAD export): 2 deg chord incidence built into the export; the measured LE-nose-to-TE line is 1.84-2.49 deg (nose radius above the chord line)"
		},
		"section_y_extent": {
			"value": 0.023581,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): mean vertical extent of the panel sections (thickness plus the incidence tilt of the chord)"
		},
		"thickness_ratio_upper_bound": {
			"value": 0.1108,
			"unit": "1",
			"kind": "derived",
			"source": "section_y_extent / chord; the true t/c is lower because the tilted chord contributes to the extent"
		},
		"stations": [
			[
				0.06,
				1.6e-05,
				0.21287,
				0.099459,
				0.091716
			],
			[
				0.07,
				0.000521,
				0.21287,
				0.101305,
				0.092065
			],
			[
				0.08,
				0.000521,
				0.21287,
				0.101654,
				0.092415
			],
			[
				0.09,
				4.9e-05,
				0.21287,
				0.100617,
				0.092764
			],
			[
				0.1,
				4.1e-05,
				0.21287,
				0.100085,
				0.093113
			],
			[
				0.11,
				4e-05,
				0.21287,
				0.100302,
				0.093462
			],
			[
				0.12,
				4e-05,
				0.21287,
				0.100651,
				0.093812
			],
			[
				0.13,
				3.8e-05,
				0.21287,
				0.101094,
				0.094161
			],
			[
				0.14,
				1.6e-05,
				0.21287,
				0.102094,
				0.09451
			],
			[
				0.15,
				0.000521,
				0.21287,
				0.104098,
				0.094859
			],
			[
				0.16,
				0.000521,
				0.21287,
				0.104448,
				0.095208
			],
			[
				0.17,
				5.2e-05,
				0.21287,
				0.103442,
				0.095558
			],
			[
				0.18,
				6e-06,
				0.21287,
				0.103049,
				0.095907
			],
			[
				0.19,
				6e-06,
				0.21287,
				0.103395,
				0.096256
			],
			[
				0.2,
				6e-06,
				0.21287,
				0.103744,
				0.096605
			],
			[
				0.21,
				1.5e-05,
				0.21287,
				0.104567,
				0.096954
			],
			[
				0.22,
				8e-06,
				0.21287,
				0.104406,
				0.097304
			],
			[
				0.23,
				8e-06,
				0.21287,
				0.104755,
				0.097653
			],
			[
				0.24,
				0.000521,
				0.21287,
				0.107241,
				0.098002
			],
			[
				0.25,
				4.9e-05,
				0.21287,
				0.106196,
				0.098351
			],
			[
				0.26,
				4.1e-05,
				0.21287,
				0.105663,
				0.0987
			],
			[
				0.27,
				4e-05,
				0.21287,
				0.10589,
				0.09905
			],
			[
				0.28,
				4e-05,
				0.21287,
				0.106239,
				0.099399
			],
			[
				0.29,
				3.8e-05,
				0.21287,
				0.10669,
				0.099748
			],
			[
				0.3,
				1.5e-05,
				0.21287,
				0.107661,
				0.100097
			],
			[
				0.31,
				0.000521,
				0.21287,
				0.109686,
				0.100446
			],
			[
				0.32,
				0.000521,
				0.21287,
				0.110035,
				0.100796
			],
			[
				0.33,
				2e-06,
				0.21287,
				0.108482,
				0.101145
			],
			[
				0.34,
				8e-06,
				0.21287,
				0.108596,
				0.101494
			],
			[
				0.35,
				8e-06,
				0.21287,
				0.108946,
				0.101843
			],
			[
				0.36,
				6e-06,
				0.21287,
				0.109646,
				0.102192
			],
			[
				0.37,
				5e-06,
				0.21287,
				0.109858,
				0.102542
			],
			[
				0.38,
				5e-06,
				0.21287,
				0.11007,
				0.102891
			],
			[
				0.39,
				0.000521,
				0.21287,
				0.112479,
				0.10324
			],
			[
				0.4,
				0.000521,
				0.21287,
				0.112829,
				0.103589
			],
			[
				0.41,
				5.2e-05,
				0.21287,
				0.111826,
				0.103939
			],
			[
				0.42,
				1e-05,
				0.21287,
				0.111489,
				0.104288
			],
			[
				0.44,
				6e-06,
				0.21287,
				0.112125,
				0.104986
			],
			[
				0.45,
				1e-05,
				0.21287,
				0.112677,
				0.105335
			],
			[
				0.46,
				3e-06,
				0.21287,
				0.113179,
				0.105685
			],
			[
				0.47,
				8e-06,
				0.21287,
				0.113141,
				0.106034
			],
			[
				0.48,
				0.000521,
				0.21287,
				0.115622,
				0.106383
			],
			[
				0.49,
				4.9e-05,
				0.21287,
				0.114564,
				0.106732
			],
			[
				0.5,
				4.1e-05,
				0.21287,
				0.114031,
				0.107081
			],
			[
				0.51,
				4e-05,
				0.21287,
				0.114271,
				0.107431
			],
			[
				0.52,
				4e-05,
				0.21287,
				0.11462,
				0.10778
			],
			[
				0.53,
				3.7e-05,
				0.21287,
				0.115085,
				0.108129
			],
			[
				0.54,
				1.5e-05,
				0.21287,
				0.116011,
				0.108478
			],
			[
				0.55,
				0.000521,
				0.21287,
				0.118067,
				0.108827
			],
			[
				0.56,
				0.000521,
				0.21287,
				0.118416,
				0.109177
			],
			[
				0.57,
				7.9e-05,
				0.21287,
				0.117491,
				0.109526
			],
			[
				0.58,
				8.2e-05,
				0.21287,
				0.117878,
				0.109875
			],
			[
				0.59,
				8e-06,
				0.21287,
				0.117334,
				0.110224
			],
			[
				0.6,
				6e-06,
				0.21287,
				0.118131,
				0.110573
			],
			[
				0.61,
				6e-06,
				0.21287,
				0.11848,
				0.110923
			],
			[
				0.62,
				6e-06,
				0.21287,
				0.11883,
				0.111272
			],
			[
				0.63,
				6e-06,
				0.21287,
				0.119179,
				0.111621
			],
			[
				0.64,
				6e-06,
				0.21287,
				0.119528,
				0.11197
			],
			[
				0.65,
				6e-06,
				0.21287,
				0.119877,
				0.11232
			],
			[
				0.66,
				6e-06,
				0.21287,
				0.120226,
				0.112669
			],
			[
				0.67,
				6e-06,
				0.21287,
				0.120576,
				0.113018
			],
			[
				0.68,
				7e-06,
				0.21287,
				0.120485,
				0.113367
			],
			[
				0.69,
				8e-06,
				0.21287,
				0.120822,
				0.113716
			],
			[
				0.7,
				-1e-06,
				0.212847,
				0.121261,
				0.113805
			],
			[
				0.71,
				3e-05,
				0.212781,
				0.120937,
				0.113422
			],
			[
				0.72,
				0.000234,
				0.212312,
				0.119428,
				0.11175
			],
			[
				0.73,
				0.000702,
				0.21115,
				0.116376,
				0.108842
			],
			[
				0.74,
				0.001709,
				0.208854,
				0.111984,
				0.104491
			],
			[
				0.75,
				0.003466,
				0.204922,
				0.105163,
				0.098538
			],
			[
				0.76,
				0.006167,
				0.198538,
				0.097229,
				0.090659
			],
			[
				0.77,
				0.010157,
				0.189365,
				0.086904,
				0.08092
			]
		],
		"stations_columns": [
			"x",
			"le_z",
			"te_z",
			"le_y",
			"te_y"
		],
		"tip_stations": [
			[
				0.7,
				-1e-06,
				0.212847
			],
			[
				0.71,
				3e-05,
				0.212781
			],
			[
				0.72,
				0.000234,
				0.212312
			],
			[
				0.73,
				0.000702,
				0.21115
			],
			[
				0.74,
				0.001709,
				0.208854
			],
			[
				0.75,
				0.003466,
				0.204922
			],
			[
				0.76,
				0.006167,
				0.198538
			],
			[
				0.77,
				0.010157,
				0.189365
			]
		]
	},
	"tail": {
		"planform": "one-piece elevator behind a swept-leading-edge stabilizer; linear fits over the clean stations, carry-through at the centreline",
		"span": {
			"value": 0.596,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): elevator mesh x extent (the stabilizer slice disappears between x = 0.29 and 0.30 m)"
		},
		"y": {
			"value": -0.032,
			"unit": "m",
			"kind": "measured",
			"source": "r2/metadata.json (author's CAD export): elevator hinge height"
		},
		"hinge_z": {
			"value": 0.704,
			"unit": "m",
			"kind": "measured",
			"source": "r2/metadata.json (author's CAD export): elevator pivot"
		},
		"le_z_centreline": {
			"value": 0.622938,
			"unit": "m",
			"kind": "derived",
			"source": "linear fit of the stabilizer leading edge extrapolated to x = 0"
		},
		"te_z_centreline": {
			"value": 0.770449,
			"unit": "m",
			"kind": "derived",
			"source": "linear fit of the elevator trailing edge extrapolated to x = 0"
		},
		"root_chord": {
			"value": 0.147511,
			"unit": "m",
			"kind": "derived",
			"source": "centreline chord from the fits"
		},
		"tip_chord": {
			"value": 0.106568,
			"unit": "m",
			"kind": "derived",
			"source": "chord at the elevator tip from the fits"
		},
		"le_sweep_deg": {
			"value": 5.21,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): leading-edge slope"
		},
		"te_sweep_deg": {
			"value": -2.645,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): elevator trailing-edge slope (negative = forward)"
		},
		"area": {
			"value": 0.075715,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: planform between the fitted edges from the centreline to the tip, both sides (CAD v12: 0.0756 m2)"
		},
		"elevator_chord_aft_of_hinge_root": {
			"value": 0.064302,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the trailing edge at x = 0.04 m"
		},
		"elevator_chord_aft_of_hinge_tip": {
			"value": 0.04988,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the trailing edge at x = 0.29 m"
		},
		"section_y_extent": {
			"value": 0.007097,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): mean vertical extent of the stabilizer sections"
		},
		"tail_arm_quarter_chords": {
			"value": 0.606586,
			"unit": "m",
			"kind": "derived",
			"source": "stabilizer centreline quarter chord minus wing quarter chord (CAD v12: 0.612 m)"
		},
		"stations": [
			[
				0.04,
				0.62663,
				0.701803,
				0.768302
			],
			[
				0.05,
				0.627536,
				0.7054,
				0.767878
			],
			[
				0.06,
				0.628439,
				0.7054,
				0.767453
			],
			[
				0.07,
				0.629354,
				0.701823,
				0.767029
			],
			[
				0.08,
				0.630255,
				0.70183,
				0.766604
			],
			[
				0.09,
				0.631163,
				0.701836,
				0.76618
			],
			[
				0.1,
				0.63207,
				0.701843,
				0.765755
			],
			[
				0.11,
				0.632974,
				0.70185,
				0.765331
			],
			[
				0.12,
				0.633883,
				0.701857,
				0.764907
			],
			[
				0.13,
				0.634785,
				0.701863,
				0.764482
			],
			[
				0.14,
				0.635706,
				0.70187,
				0.764058
			],
			[
				0.15,
				0.636598,
				0.701877,
				0.763633
			],
			[
				0.16,
				0.637504,
				0.702327,
				0.763209
			],
			[
				0.17,
				0.63841,
				0.70189,
				0.762784
			],
			[
				0.18,
				0.639316,
				0.701897,
				0.76236
			],
			[
				0.19,
				0.640222,
				0.701904,
				0.761935
			],
			[
				0.2,
				0.641128,
				0.701911,
				0.761511
			],
			[
				0.21,
				0.642034,
				0.701917,
				0.761086
			],
			[
				0.22,
				0.64294,
				0.701924,
				0.760662
			],
			[
				0.23,
				0.643846,
				0.701931,
				0.760237
			],
			[
				0.24,
				0.644752,
				0.701938,
				0.759813
			],
			[
				0.25,
				0.645657,
				0.702327,
				0.759389
			],
			[
				0.26,
				0.646563,
				0.701951,
				0.758964
			],
			[
				0.27,
				0.647469,
				0.701958,
				0.75854
			],
			[
				0.28,
				0.648476,
				0.701999,
				0.75748
			],
			[
				0.29,
				0.649884,
				0.702179,
				0.75388
			]
		],
		"stations_columns": [
			"x",
			"le_z",
			"fixed_te_z",
			"elevator_te_z"
		]
	},
	"fin": {
		"planform": "swept fin with dorsal fillet, straight vertical rudder trailing edge; the rudder extends below the fuselage top to the tailwheel wire",
		"top_y": {
			"value": 0.178,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): highest vertex of the model (rudder/fin tip)"
		},
		"root_y": {
			"value": 0.03,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): first horizontal slice clear of the fuselage"
		},
		"hinge_z": {
			"value": 0.738,
			"unit": "m",
			"kind": "measured",
			"source": "r2/metadata.json (author's CAD export): rudder pivot"
		},
		"rudder_te_z": {
			"value": 0.832,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): aft-most rudder vertex"
		},
		"rudder_y": [
			-0.0704,
			0.178
		],
		"le_sweep_deg": {
			"value": 33.325,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): fin leading-edge slope dz/dy"
		},
		"le_z_at_root": {
			"value": 0.615451,
			"unit": "m",
			"kind": "derived",
			"source": "fitted leading edge at root_y"
		},
		"root_chord": {
			"value": 0.216549,
			"unit": "m",
			"kind": "derived",
			"source": "rudder_te_z - fitted leading edge at root_y"
		},
		"tip_chord": {
			"value": 0.11924,
			"unit": "m",
			"kind": "derived",
			"source": "rudder_te_z - fitted leading edge at top_y"
		},
		"area_above_fuselage": {
			"value": 0.024848,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: trapezoid between root_y and top_y"
		},
		"rudder_chord_aft_of_hinge": {
			"value": 0.094,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the aft-most rudder vertex"
		},
		"rudder_area": {
			"value": 0.02335,
			"unit": "m2",
			"kind": "derived",
			"source": "rudder chord aft of hinge x rudder height"
		},
		"stations": [
			[
				0.03,
				0.61,
				0.735102,
				0.832
			],
			[
				0.04,
				0.623583,
				0.736317,
				0.832
			],
			[
				0.05,
				0.629979,
				0.735305,
				0.832
			],
			[
				0.06,
				0.636374,
				0.735369,
				0.832
			],
			[
				0.07,
				0.642769,
				0.735417,
				0.832
			],
			[
				0.08,
				0.649164,
				0.735464,
				0.832
			],
			[
				0.09,
				0.655559,
				0.735512,
				0.832
			],
			[
				0.1,
				0.661954,
				0.735559,
				0.832
			],
			[
				0.11,
				0.668349,
				0.735606,
				0.832
			],
			[
				0.12,
				0.674745,
				0.735586,
				0.832
			],
			[
				0.13,
				0.68114,
				0.736327,
				0.832
			],
			[
				0.14,
				0.687535,
				0.735377,
				0.832
			],
			[
				0.15,
				0.693931,
				0.735273,
				0.832
			],
			[
				0.16,
				0.700334,
				0.735169,
				0.832
			],
			[
				0.17,
				0.706716,
				0.735065,
				0.832
			]
		],
		"stations_columns": [
			"y",
			"le_z",
			"fixed_te_z",
			"rudder_te_z"
		]
	},
	"fuselage": {
		"stations": [
			[
				-0.22,
				0.041318,
				-0.035958,
				0.023407,
				false,
				false
			],
			[
				-0.2,
				0.049325,
				-0.042476,
				0.027347,
				false,
				false
			],
			[
				-0.18,
				0.069048,
				-0.045976,
				0.029046,
				false,
				false
			],
			[
				-0.16,
				0.069424,
				-0.047291,
				0.028755,
				false,
				false
			],
			[
				-0.14,
				0.068965,
				-0.048096,
				0.027452,
				false,
				false
			],
			[
				-0.12,
				0.052115,
				-0.048879,
				0.025892,
				false,
				false
			],
			[
				-0.1,
				0.051956,
				-0.051408,
				0.024165,
				false,
				false
			],
			[
				-0.08,
				0.052944,
				-0.055229,
				0.022939,
				false,
				false
			],
			[
				-0.06,
				0.055904,
				-0.062727,
				0.022392,
				false,
				false
			],
			[
				-0.04,
				0.057985,
				-0.068594,
				0.035048,
				false,
				false
			],
			[
				-0.02,
				0.058451,
				-0.073373,
				0.057119,
				false,
				false
			],
			[
				0.0,
				0.058917,
				-0.094526,
				0.079189,
				true,
				false
			],
			[
				0.02,
				0.059402,
				-0.094526,
				0.092639,
				true,
				false
			],
			[
				0.04,
				0.059879,
				-0.094526,
				0.092578,
				true,
				false
			],
			[
				0.06,
				0.060273,
				-0.094526,
				0.092518,
				true,
				false
			],
			[
				0.08,
				0.060298,
				-0.087297,
				0.092457,
				true,
				false
			],
			[
				0.1,
				0.06036,
				-0.090312,
				0.092397,
				true,
				false
			],
			[
				0.12,
				0.060465,
				-0.092589,
				0.092336,
				true,
				false
			],
			[
				0.14,
				0.060306,
				-0.094247,
				0.092276,
				true,
				false
			],
			[
				0.16,
				0.060084,
				-0.096244,
				0.092215,
				true,
				false
			],
			[
				0.18,
				0.059677,
				-0.096825,
				0.091998,
				true,
				false
			],
			[
				0.2,
				0.059107,
				-0.097406,
				0.09163,
				true,
				false
			],
			[
				0.22,
				0.058358,
				-0.097685,
				0.082177,
				false,
				false
			],
			[
				0.24,
				0.057177,
				-0.097763,
				0.076179,
				false,
				false
			],
			[
				0.26,
				0.055218,
				-0.09776,
				0.069693,
				false,
				false
			],
			[
				0.28,
				0.052704,
				-0.097028,
				0.058813,
				false,
				false
			],
			[
				0.3,
				0.050191,
				-0.096297,
				0.047932,
				false,
				false
			],
			[
				0.32,
				0.047677,
				-0.095558,
				0.042093,
				false,
				false
			],
			[
				0.34,
				0.045164,
				-0.094813,
				0.039614,
				false,
				false
			],
			[
				0.36,
				0.042651,
				-0.094053,
				0.037161,
				false,
				false
			],
			[
				0.38,
				0.040137,
				-0.093166,
				0.03495,
				false,
				false
			],
			[
				0.4,
				0.037688,
				-0.0933,
				0.032739,
				false,
				false
			],
			[
				0.42,
				0.035412,
				-0.091204,
				0.029917,
				false,
				false
			],
			[
				0.44,
				0.033137,
				-0.090003,
				0.02669,
				false,
				false
			],
			[
				0.46,
				0.030989,
				-0.088778,
				0.023448,
				false,
				false
			],
			[
				0.48,
				0.02907,
				-0.087339,
				0.020077,
				false,
				false
			],
			[
				0.5,
				0.027151,
				-0.085901,
				0.016705,
				false,
				false
			],
			[
				0.52,
				0.025232,
				-0.084488,
				0.013522,
				false,
				false
			],
			[
				0.54,
				0.023549,
				-0.083093,
				0.010463,
				false,
				false
			],
			[
				0.56,
				0.021937,
				-0.081718,
				0.007481,
				false,
				false
			],
			[
				0.58,
				0.020325,
				-0.080521,
				0.004874,
				false,
				false
			],
			[
				0.6,
				0.018713,
				-0.079325,
				0.002283,
				false,
				false
			],
			[
				0.62,
				0.017101,
				-0.078078,
				-0.000288,
				false,
				true
			],
			[
				0.64,
				0.015489,
				-0.076797,
				-0.003523,
				false,
				true
			],
			[
				0.66,
				0.013877,
				-0.075494,
				-0.006057,
				false,
				true
			],
			[
				0.68,
				0.012265,
				-0.073991,
				-0.008591,
				false,
				true
			],
			[
				0.7,
				0.010653,
				-0.078,
				-0.011125,
				false,
				true
			],
			[
				0.72,
				0.00904,
				-0.078,
				-0.01366,
				false,
				true
			],
			[
				0.74,
				0.0065,
				-0.078,
				-0.071,
				false,
				true
			]
		],
		"stations_columns": [
			"z",
			"half_width",
			"y_bottom",
			"y_top",
			"inside_wing_chord",
			"inside_tail"
		],
		"note": "combined fixed-section skin slices (glazing, lenses and grey brackets excluded) limited to |x| <= 0.09 m; stations inside the wing chord include the wing carry-through and stations inside the tail include the fin/stabilizer roots",
		"cowl_front_z": {
			"value": -0.23448,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): foremost vertex of the separate cowl section"
		},
		"aft_end_z": {
			"value": 0.746,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): aft-most skin vertex among the fixed sections, ahead of the moving rudder"
		}
	},
	"landing_gear": {
		"type": "two wire-sprung legs hinged on fuselage pins, crossed cables with tension springs between each leg and the opposite fuselage eyelet",
		"wheel_centres": {
			"main_left": [
				-0.131979,
				-0.198,
				0.008
			],
			"main_right": [
				0.131979,
				-0.198,
				0.008
			],
			"tail": [
				0.0,
				-0.112,
				0.759
			]
		},
		"main_wheel_radius": {
			"value": 0.058016,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): largest radial vertex distance of wheel_left about its axle (author estimate 0.058 m)"
		},
		"tail_wheel_radius": {
			"value": 0.014004,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): largest radial vertex distance of tailwheel about its axle (author estimate 0.014 m)"
		},
		"main_wheel_width": {
			"value": 0.044058,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json)"
		},
		"track": {
			"value": 0.263958,
			"unit": "m",
			"kind": "measured",
			"source": "right minus left axle x (r2 metadata: 0.264 m)"
		},
		"contacts_neutral": {
			"main_left": [
				-0.131979,
				-0.256016,
				0.008
			],
			"main_right": [
				0.131979,
				-0.256016,
				0.008
			],
			"tail": [
				0.0,
				-0.126004,
				0.759
			]
		},
		"contacts_measured_bottom_y": {
			"main_left": -0.256,
			"main_right": -0.256,
			"tail": -0.125999
		},
		"three_point_attitude_deg": {
			"value": 9.822,
			"unit": "deg",
			"kind": "derived",
			"source": "line through the main and tail contact points (r2 metadata: 9.8 deg)"
		},
		"suspension": {
			"pivots": {
				"left": [
					-0.046,
					-0.090347,
					0.031
				],
				"right": [
					0.046,
					-0.090347,
					0.031
				]
			},
			"axes": {
				"left": [
					0.0,
					0.0,
					-1.0
				],
				"right": [
					0.0,
					0.0,
					1.0
				]
			},
			"travel_deg": {
				"value": {
					"value": 12.0,
					"unit": "deg",
					"evidence": "estimated",
					"source": "derived from the parametric CAD v12 (modelo_v12.py) (spring stretch audit)"
				},
				"unit": "deg",
				"kind": "estimated",
				"source": "r2/metadata.json (author's CAD export): suspension travel from the r2 metadata"
			},
			"spring_stiffness": "unknown (author); the simulator's contact stiffness is a model input (TT-07)",
			"cable_endpoints": {
				"der": {
					"fuselage_eyelet": [
						0.022,
						-0.090358,
						0.044
					],
					"anchor_rest": [
						-0.075231,
						-0.167417,
						0.017691
					],
					"rigid_cable_length_m": 0.07082320767062981
				},
				"izq": {
					"fuselage_eyelet": [
						-0.022,
						-0.090358,
						0.03
					],
					"anchor_rest": [
						0.07495,
						-0.167194,
						0.015505
					],
					"rigid_cable_length_m": 0.06855160099103486
				}
			}
		},
		"steering": {
			"pivot": [
				0.0,
				-0.084092,
				0.738
			],
			"axis": [
				0.0,
				1.0,
				0.0
			],
			"range_deg": [
				-30.0,
				30.0
			],
			"positive": "trailing wheel to the pilot's right (follows the rudder)",
			"coupling": {
				"follows": "rudder_hinge",
				"ratio": 1.0,
				"note": "tailwheel wire rides in the rudder; coaxial hinge line"
			}
		},
		"brakes": "none"
	},
	"controls": {
		"convention": "straight-line distance between the neutral and deflected trailing-edge positions, d = 2 r sin(theta / 2), r = perpendicular distance from the hinge axis to the trailing edge at the station",
		"stations": {
			"aileron": "inboard end of the aileron (first clean slice outboard of its inner edge)",
			"elevator": "elevator root beside the fuselage (first clean stabilizer slice)",
			"rudder": "aft-most rudder vertex (the rudder chord is constant)",
			"flap": "inboard end of the flap (first clean slice outboard of the wing root)",
			"kind": "estimated",
			"source": "the manual states millimetres but not the spanwise station; E-flite setup sheets measure at the widest point of the surface next to the fuselage. Angles over the whole span are reported as a range so the assumption stays visible"
		},
		"manual_mm": {
			"aileron": {
				"high": 33.0,
				"low": 25.0
			},
			"elevator": {
				"high": 20.0,
				"low": 15.0
			},
			"rudder": {
				"high": 30.0,
				"low": 20.0
			},
			"flap": {
				"half": 20.0,
				"full": 35.0
			}
		},
		"manual_source": "EFL105250B manual p.14 (quick-start setup): linear trailing-edge travel from neutral, symmetric up/down; the flap settings carry 16 %/30 % down-elevator mixes that are setup values, not geometry",
		"aileron": {
			"r": {
				"value": 0.055681,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the trailing edge at x = 0.44 m"
			},
			"high_deg": {
				"value": 34.475,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 33 mm, r = 0.0557 m"
			},
			"low_deg": {
				"value": 25.946,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 25 mm, r = 0.0557 m"
			},
			"authored_range_deg": 22.0,
			"differential_authored": 0.7,
			"note": "constant chord: the angle does not change along the aileron; the manual gives symmetric up/down travel, the authored 0.7 differential is not applied"
		},
		"elevator": {
			"r": {
				"value": 0.064302,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the trailing edge at x = 0.04 m (root)"
			},
			"high_deg": {
				"value": 17.893,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0643 m"
			},
			"low_deg": {
				"value": 13.396,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 15 mm, r = 0.0643 m"
			},
			"high_deg_at_tip": {
				"value": 23.13,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0499 m"
			},
			"authored_range_deg": 22.0,
			"note": "the tapered elevator gives a larger angle for the same millimetres at the tip; the root station is the assumption"
		},
		"rudder": {
			"r": {
				"value": 0.094,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the aft-most rudder vertex"
			},
			"high_deg": {
				"value": 18.364,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 30 mm, r = 0.0940 m"
			},
			"low_deg": {
				"value": 12.214,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0940 m"
			},
			"authored_range_deg": 30.0
		},
		"flap": {
			"r": {
				"value": 0.055681,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the trailing edge at x = 0.06 m"
			},
			"half_deg": {
				"value": 20.692,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0557 m"
			},
			"full_deg": {
				"value": 36.636,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 35 mm, r = 0.0557 m"
			},
			"authored_range_deg": [
				0.0,
				40.0
			],
			"elevator_mix": "16 % (half) / 30 % (full) down elevator per the manual: a radio setup value, not geometry"
		}
	},
	"manual": {
		"span_m": {
			"value": 1.555,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (1,555 mm)"
		},
		"length_m": {
			"value": 1.04,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (1,040 mm); measurement endpoints not stated"
		},
		"mass_empty_kg": {
			"value": 1.86,
			"unit": "kg",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (1,860 g without battery)"
		},
		"mass_flying_kg": {
			"value": 2.19,
			"unit": "kg",
			"kind": "manual",
			"source": "EFL105250B manual p.3 (2,190 g with the recommended 4S 3,200 mAh pack)"
		},
		"cg_aft_of_root_le_m": {
			"value": 0.06,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.13: 60 +/- 5 mm aft of the wing-root leading edge, slats off"
		},
		"cg_tolerance_m": {
			"value": 0.005,
			"unit": "m",
			"kind": "manual",
			"source": "EFL105250B manual p.13"
		},
		"propeller": {
			"value": "11 x 7.3 three-blade, part EFL5962",
			"diameter_m": 0.2794,
			"pitch_m": 0.18542,
			"blades": 3.0,
			"kind": "manual",
			"source": "EFL105250B manual p.13 and Horizon part EFL5962"
		},
		"motor": {
			"value": "brushless outrunner 800 Kv, 14-pole, SPM-1012",
			"kv": 800.0,
			"kind": "manual",
			"source": "EFL105250B manual p.3"
		},
		"battery": {
			"value": "4S 3,200 mAh 30C recommended (3S-4S, 2,200-5,000 mAh compatible)",
			"kind": "manual",
			"source": "EFL105250B manual p.3"
		},
		"servos": {
			"value": "six 9 g metal-gear servos (2 ailerons, 2 flaps, elevator, rudder)",
			"kind": "manual",
			"source": "EFL105250B manual p.3 equipment table"
		}
	},
	"author_component_stations": {
		"note": "author's class-typical component estimates (1.46 kg total) as stations only; the selected 2.190 kg reference mass is separate and does not create a flight mass budget",
		"components": [
			{
				"name": "ala (2 semialas, flaps, alerones)",
				"mass_kg_author_estimate": 0.2556,
				"z_model": 0.1013
			},
			{
				"name": "fuselaje",
				"mass_kg_author_estimate": 0.29,
				"z_model": 0.2208
			},
			{
				"name": "cola",
				"mass_kg_author_estimate": 0.0613,
				"z_model": 0.7033
			},
			{
				"name": "tren principal",
				"mass_kg_author_estimate": 0.135,
				"z_model": 0.012
			},
			{
				"name": "rueda de cola",
				"mass_kg_author_estimate": 0.012,
				"z_model": 0.7384
			},
			{
				"name": "helice y cono",
				"mass_kg_author_estimate": 0.032,
				"z_model": -0.251
			},
			{
				"name": "motor",
				"mass_kg_author_estimate": 0.16,
				"z_model": -0.2125
			},
			{
				"name": "variador",
				"mass_kg_author_estimate": 0.06,
				"z_model": -0.142
			},
			{
				"name": "receptor",
				"mass_kg_author_estimate": 0.012,
				"z_model": 0.118
			},
			{
				"name": "servos_cola",
				"mass_kg_author_estimate": 0.026,
				"z_model": 0.228
			},
			{
				"name": "servos_ala",
				"mass_kg_author_estimate": 0.036,
				"z_model": 0.1001
			},
			{
				"name": "cableado_luces",
				"mass_kg_author_estimate": 0.04,
				"z_model": 0.058
			},
			{
				"name": "bateria",
				"mass_kg_author_estimate": 0.34,
				"z_model": -0.052
			}
		]
	},
	"discrepancies": {
		"span_mm": {
			"value": -9.496,
			"unit": "mm",
			"kind": "derived",
			"source": "measured span (lenses included) minus the manual span"
		},
		"length_mm": {
			"value": 75.461,
			"unit": "mm",
			"kind": "derived",
			"source": "measured length minus the manual length; the author attributes most of it to the nose/cowl ahead of the wing (r2 request); kept as delivered (decision D4)"
		},
		"area_vs_author_cad_percent": {
			"value": -0.606,
			"unit": "%",
			"kind": "derived",
			"source": "measured planform area against the author's r2 metadata CAD value of 0.329 m2"
		},
		"propeller_radius_mm": {
			"value": 0.0,
			"unit": "mm",
			"kind": "derived",
			"source": "measured blade-tip radius minus half of the author's measured r2 propeller diameter"
		},
		"silhouette_overlay": "pending owner review: r2 side/top previews against the manual three-view (TT-02 evidence lists the files)"
	},
	"evidence": {
		"pivots": {
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json); agree with r2/metadata.json (author's CAD export) within 1e-6 m and 1e-6 in axis components"
		},
		"planform": {
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r2 scene (mesh-measurements.json): plane slices of the white/red/black skin and the control-surface meshes"
		},
		"ranges": {
			"kind": "estimated",
			"source": "r2/metadata.json (author's CAD export): authored approximations, no manual available to the modeller"
		},
		"throws": {
			"kind": "derived",
			"source": "manual millimetres (manual.json) converted at the assumed stations (controls.stations)"
		},
		"installation_angles": {
			"kind": "estimated",
			"source": "r2/metadata.json (author's CAD export): 2 deg incidence, dihedral, down and right thrust typical for the type; the export carries them, so they are measured in the mesh but not validated against the aircraft"
		},
		"length": {
			"kind": "measured",
			"source": "76.6 mm longer than the manual; unresolved (TT-02 discrepancies)"
		}
	}
}
