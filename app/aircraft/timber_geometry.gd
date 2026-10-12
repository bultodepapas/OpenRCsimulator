# Generated, do not edit. Source: assets/aircraft/turbo-lumber-evolution/geometry.json (revision r1-fb7586f19029).
# Regenerate with: python3 assets/aircraft/turbo-lumber-evolution/compile_geometry.py
# Visual preview geometry of the author's r1 export (see DATA.evidence); not flyable.
extends RefCounted

const DATA := {
	"schema": "openrc-timber-geometry v1",
	"revision": "r1-fb7586f19029",
	"catalog_id": "turbo-lumber-evolution",
	"source_alias": "eflite_turbo_timber_evolution",
	"status": "visual preview geometry of the author's r1 export; dimensions measured on the Godot-imported scene, ranges and installation angles estimated by the author; not calibrated, not flyable",
	"generator": "assets/aircraft/turbo-lumber-evolution/build_geometry.py",
	"inputs": {
		"manifest": "assets/aircraft/turbo-lumber-evolution/source-manifest.json",
		"glb_sha256": "fb7586f190295bd3e3aee6b8fbd4c10acf34d3b2288f38baadf170b8f66ae4a5",
		"metadata_sha256": "7e0afb84661c1dfb9eb050ce6d8fc088707ddcd0dbd97928f6420ef0886ca047",
		"measurements": {
			"generator": "research/timber/tt02/measure_mesh.gd",
			"godot": "4.7.2-stable (official)",
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
				"triangles": 1062.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"aileron_right": {
				"parent": "aileron_right_hinge",
				"triangles": 1062.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"airframe": {
				"parent": "TurboTimberEvolution",
				"triangles": 36691.0,
				"surfaces": 9.0,
				"materials": [
					"white",
					"red",
					"black",
					"glass",
					"metal",
					"light_red",
					"light_grey",
					"dark_grey",
					"light_green"
				],
				"local_identity": true
			},
			"elevator": {
				"parent": "elevator_hinge",
				"triangles": 2042.0,
				"surfaces": 4.0,
				"materials": [
					"white",
					"metal",
					"red",
					"black"
				],
				"local_identity": true
			},
			"flap_left": {
				"parent": "flap_left_hinge",
				"triangles": 1050.0,
				"surfaces": 1.0,
				"materials": [
					"white"
				],
				"local_identity": true
			},
			"flap_right": {
				"parent": "flap_right_hinge",
				"triangles": 1050.0,
				"surfaces": 1.0,
				"materials": [
					"white"
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
				"triangles": 1868.0,
				"surfaces": 2.0,
				"materials": [
					"white",
					"metal"
				],
				"local_identity": true
			},
			"gear_right_leg": {
				"parent": "gear_right_suspension",
				"triangles": 1866.0,
				"surfaces": 2.0,
				"materials": [
					"white",
					"metal"
				],
				"local_identity": true
			},
			"propeller_rotor": {
				"parent": "propeller_spin",
				"triangles": 6034.0,
				"surfaces": 2.0,
				"materials": [
					"black",
					"metal"
				],
				"local_identity": true
			},
			"rudder": {
				"parent": "rudder_hinge",
				"triangles": 2546.0,
				"surfaces": 3.0,
				"materials": [
					"white",
					"red",
					"black"
				],
				"local_identity": true
			},
			"tailwheel": {
				"parent": "tailwheel_axle",
				"triangles": 1504.0,
				"surfaces": 2.0,
				"materials": [
					"foam",
					"light_grey"
				],
				"local_identity": true
			},
			"tailwheel_fork": {
				"parent": "tailwheel_steer",
				"triangles": 532.0,
				"surfaces": 1.0,
				"materials": [
					"metal"
				],
				"local_identity": true
			},
			"wheel_left": {
				"parent": "wheel_left_axle",
				"triangles": 3436.0,
				"surfaces": 3.0,
				"materials": [
					"foam",
					"white",
					"metal"
				],
				"local_identity": true
			},
			"wheel_right": {
				"parent": "wheel_right_axle",
				"triangles": 3436.0,
				"surfaces": 3.0,
				"materials": [
					"foam",
					"white",
					"metal"
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
			"mesh_instances": 15.0,
			"surfaces": 36.0,
			"triangles": 64291.0
		},
		"compressed_vertex_attributes": true,
		"godot": "4.7.2-stable (official)"
	},
	"dimensions": {
		"span": {
			"value": 1.547912,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): outermost vertices, nav-light lenses included (manual: 1.555 m)"
		},
		"span_skin": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): outermost white skin vertices (lenses excluded)"
		},
		"length": {
			"value": 1.11656,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): rudder trailing edge minus spinner tip along z (manual: 1.040 m)"
		},
		"height": {
			"value": 0.434,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): fin top minus main-wheel bottom at neutral suspension"
		},
		"bbox": {
			"min": [
				-0.773956,
				-0.256,
				-0.283461
			],
			"max": [
				0.773956,
				0.178,
				0.833099
			]
		},
		"forward_extent_vertex": {
			"mesh": "propeller_rotor",
			"surface": 0.0,
			"material": "black",
			"root": [
				0.001116,
				-0.00112,
				-0.283461
			],
			"local": [
				0.041372,
				-3e-06,
				0.0
			],
			"finding": "the spinner tip of propeller_rotor (author landmark); the -0.2913 m extent reported by the TT-00-R1 probe came from the axis-aligned bounding box of the 2 deg/2 deg tilted rotor, not from a vertex"
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
				-0.773956,
				0.096985,
				0.031077
			],
			"measured": [
				-0.773956,
				0.096984,
				0.028922
			],
			"compared_axes": [
				0.0
			],
			"difference_mm": 0.0,
			"definition": "outermost vertex of the left wing (pilot's left)"
		},
		"right_wingtip": {
			"author": [
				0.773956,
				0.096985,
				0.031077
			],
			"measured": [
				0.773956,
				0.096985,
				0.031077
			],
			"compared_axes": [
				0.0
			],
			"difference_mm": 0.0,
			"definition": "outermost vertex of the right wing (pilot's right)"
		},
		"nose_spinner_tip": {
			"author": [
				0.001116,
				-0.001117,
				-0.283461
			],
			"measured": [
				0.001116,
				-0.00112,
				-0.283461
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.003,
			"definition": "most forward vertex of the spinner (propeller_rotor mesh)"
		},
		"tail_rudder_trailing_edge": {
			"author": [
				-0.0,
				0.027267,
				0.833099
			],
			"measured": [
				0.0,
				0.027266,
				0.833099
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.001,
			"definition": "most aft vertex of the rudder at neutral"
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
			"definition": "axle-pivot origin (wheel center) at neutral suspension"
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
			"definition": "axle-pivot origin (wheel center) at neutral suspension"
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
			"definition": "axle-pivot origin (wheel center) at neutral suspension"
		},
		"propeller_hub": {
			"author": [
				0.0,
				0.0,
				-0.2515
			],
			"measured": [
				0.0,
				0.0,
				-0.2515
			],
			"compared_axes": [
				0.0,
				1.0,
				2.0
			],
			"difference_mm": 0.0,
			"definition": ""
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
			"definition": ""
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
			"range_source": "authored approximation (no manufacturer manual available to the modeler)",
			"positive": "same sense as rudder (wheel trails to the right)",
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
				"source": "r1/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
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
			"positive": "leg swings outboard (compression)",
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
				"source": "r1/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
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
			"positive": "leg swings outboard (compression)",
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
				"source": "r1/metadata.json (author's CAD export): user-supplied photographs of a Turbo Timber Evolution (side, 3/4, top, front, nose, gear close-up)"
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
			"source": "r1/metadata.json (author's CAD export): propeller hub, CAD x = -251.5 mm"
		},
		"direction": {
			"value": [
				0.034878,
				-0.034899,
				-0.998782
			],
			"unit": "1",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): thrust_frame local +X in the root frame"
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
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json) (author: 2 deg estimated, typical for the type)"
		},
		"right_thrust_deg": {
			"value": 2.0,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json) (author: 2 deg estimated, typical for the type)"
		},
		"spin_node": "propeller_spin",
		"spin_rest_translation": [
			-0.009372,
			0.0,
			0.0
		],
		"rotation_sense": "clockwise seen from behind (normal tractor) = positive about the thrust direction",
		"propeller_radius": {
			"value": 0.140321,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): largest radial distance of a rotor vertex from the thrust axis (author estimate 0.1381 m; manual 11 in = 0.1397 m)"
		},
		"spinner_tip": {
			"value": [
				0.001116,
				-0.00112,
				-0.283461
			],
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): rotor vertex furthest along the thrust axis"
		},
		"rotor_axial_extent": [
			-0.0505,
			0.032
		]
	},
	"wing": {
		"planform": "rectangular, constant chord from the fuselage side to the last aileron station, rounded tips; the model is mirrored about x = 0",
		"span": {
			"value": 1.547912,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): outermost vertices, nav-light lenses included (manual: 1.555 m)"
		},
		"span_skin": {
			"value": 1.545504,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): outermost white skin vertices (lenses excluded)"
		},
		"le_z": {
			"value": -0.000665,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): median leading-edge z of the constant-chord stations (datum D0 is the root LE station)"
		},
		"te_z": {
			"value": 0.21287,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): median trailing-edge z of the flap/aileron stations"
		},
		"chord": {
			"value": 0.213535,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): te_z - le_z, constant over the flap and aileron stations"
		},
		"mac": {
			"value": 0.213535,
			"unit": "m",
			"kind": "derived",
			"source": "rectangular panel: MAC = chord (r1 metadata: 0.213 m from the CAD)"
		},
		"area": {
			"value": 0.328223,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: trapezoid integral of the measured chord over the span, fuselage carry-through at the panel chord, rounded tips from the tip slices (r1 CAD: 0.329 m2)"
		},
		"area_rectangular": {
			"value": 0.330533,
			"unit": "m2",
			"kind": "derived",
			"source": "span x chord, no tip rounding"
		},
		"panel_x": [
			0.06,
			0.69
		],
		"fuselage_half_width_at_wing": {
			"value": 0.0611,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): largest airframe-skin half-width of the fuselage slices between z = 0.06 and 0.16 m"
		},
		"hinge_z": {
			"value": 0.157726,
			"unit": "m",
			"kind": "measured",
			"source": "r1/metadata.json (author's CAD export): aileron and flap pivots share z = 0.157726 m"
		},
		"hinge_fraction": {
			"value": 0.7418,
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
			"value": 0.006871,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): rounded control-surface nose ahead of the pivot"
		},
		"aileron_x": [
			0.4301,
			0.694445
		],
		"flap_x": [
			0.054329,
			0.426607
		],
		"dihedral_deg": {
			"value": 1.973,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): slope of the leading-edge y over the panel stations (author: 2 deg)"
		},
		"incidence_deg": {
			"value": 2.0,
			"unit": "deg",
			"kind": "estimated",
			"source": "r1/metadata.json (author's CAD export): 2 deg chord incidence built into the export; the measured LE-nose-to-TE line is 2.00-2.44 deg (nose radius above the chord line)"
		},
		"section_y_extent": {
			"value": 0.02696,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): mean vertical extent of the panel sections (thickness plus the incidence tilt of the chord)"
		},
		"thickness_ratio_upper_bound": {
			"value": 0.1263,
			"unit": "1",
			"kind": "derived",
			"source": "section_y_extent / chord; the true t/c is lower because the tilted chord contributes to the extent"
		},
		"stations": [
			[
				0.06,
				-0.000665,
				0.21287,
				0.1008,
				0.091716
			],
			[
				0.07,
				-0.000665,
				0.21287,
				0.101149,
				0.092065
			],
			[
				0.08,
				-0.000665,
				0.21287,
				0.101498,
				0.092415
			],
			[
				0.09,
				-0.000665,
				0.21287,
				0.101847,
				0.092764
			],
			[
				0.1,
				-0.000665,
				0.21287,
				0.102197,
				0.093113
			],
			[
				0.11,
				-0.000665,
				0.21287,
				0.102546,
				0.093462
			],
			[
				0.12,
				-0.000665,
				0.21287,
				0.102895,
				0.093811
			],
			[
				0.13,
				-0.000665,
				0.21287,
				0.103244,
				0.094161
			],
			[
				0.14,
				-0.000665,
				0.21287,
				0.103593,
				0.09451
			],
			[
				0.15,
				-0.000665,
				0.21287,
				0.103942,
				0.094859
			],
			[
				0.16,
				-0.000665,
				0.21287,
				0.104292,
				0.095208
			],
			[
				0.17,
				-0.000665,
				0.21287,
				0.104641,
				0.095557
			],
			[
				0.18,
				-0.000665,
				0.21287,
				0.10499,
				0.095907
			],
			[
				0.19,
				-0.000665,
				0.21287,
				0.105339,
				0.096256
			],
			[
				0.2,
				-0.000665,
				0.21287,
				0.105688,
				0.096605
			],
			[
				0.21,
				-0.000665,
				0.21287,
				0.106037,
				0.096954
			],
			[
				0.22,
				-0.002066,
				0.21287,
				0.104805,
				0.097303
			],
			[
				0.23,
				-0.002066,
				0.21287,
				0.105154,
				0.097653
			],
			[
				0.24,
				-0.000665,
				0.21287,
				0.107084,
				0.098002
			],
			[
				0.25,
				-0.000665,
				0.21287,
				0.107433,
				0.098351
			],
			[
				0.26,
				-0.000665,
				0.21287,
				0.107782,
				0.0987
			],
			[
				0.27,
				-0.000665,
				0.21287,
				0.108131,
				0.099049
			],
			[
				0.28,
				-0.000665,
				0.21287,
				0.10848,
				0.099399
			],
			[
				0.29,
				-0.000665,
				0.21287,
				0.108829,
				0.099748
			],
			[
				0.3,
				-0.000665,
				0.21287,
				0.109179,
				0.100097
			],
			[
				0.31,
				-0.000665,
				0.21287,
				0.109528,
				0.100446
			],
			[
				0.32,
				-0.000665,
				0.21287,
				0.109877,
				0.100796
			],
			[
				0.33,
				-0.000665,
				0.21287,
				0.110226,
				0.101145
			],
			[
				0.34,
				-0.002066,
				0.21287,
				0.108997,
				0.101494
			],
			[
				0.35,
				-0.002066,
				0.21287,
				0.109345,
				0.101843
			],
			[
				0.36,
				-0.000665,
				0.21287,
				0.111276,
				0.102192
			],
			[
				0.37,
				-0.000665,
				0.21287,
				0.111625,
				0.102542
			],
			[
				0.38,
				-0.000665,
				0.21287,
				0.111975,
				0.102891
			],
			[
				0.39,
				-0.000665,
				0.21287,
				0.112324,
				0.10324
			],
			[
				0.4,
				-0.000665,
				0.21287,
				0.112673,
				0.103589
			],
			[
				0.41,
				-0.000665,
				0.21287,
				0.113022,
				0.103938
			],
			[
				0.42,
				-0.000665,
				0.21287,
				0.113371,
				0.104288
			],
			[
				0.44,
				-0.000665,
				0.21287,
				0.114069,
				0.104986
			],
			[
				0.45,
				-0.000665,
				0.21287,
				0.114418,
				0.105335
			],
			[
				0.46,
				-0.002066,
				0.21287,
				0.113188,
				0.105684
			],
			[
				0.47,
				-0.002066,
				0.21287,
				0.113537,
				0.106034
			],
			[
				0.48,
				-0.000665,
				0.21287,
				0.115465,
				0.106383
			],
			[
				0.49,
				-0.000665,
				0.21287,
				0.115814,
				0.106732
			],
			[
				0.5,
				-0.000665,
				0.21287,
				0.116164,
				0.107081
			],
			[
				0.51,
				-0.000665,
				0.21287,
				0.116513,
				0.10743
			],
			[
				0.52,
				-0.000665,
				0.21287,
				0.116863,
				0.10778
			],
			[
				0.53,
				-0.000665,
				0.21287,
				0.117212,
				0.108129
			],
			[
				0.54,
				-0.000665,
				0.21287,
				0.117561,
				0.108478
			],
			[
				0.55,
				-0.000665,
				0.21287,
				0.117911,
				0.108827
			],
			[
				0.56,
				-0.000665,
				0.21287,
				0.11826,
				0.109177
			],
			[
				0.57,
				-0.000665,
				0.21287,
				0.11861,
				0.109526
			],
			[
				0.58,
				-0.000665,
				0.21287,
				0.118959,
				0.109875
			],
			[
				0.59,
				-0.002066,
				0.21287,
				0.117726,
				0.110224
			],
			[
				0.6,
				-0.000665,
				0.21287,
				0.119657,
				0.110573
			],
			[
				0.61,
				-0.000665,
				0.21287,
				0.120006,
				0.110923
			],
			[
				0.62,
				-0.000665,
				0.21287,
				0.120355,
				0.111272
			],
			[
				0.63,
				-0.000665,
				0.21287,
				0.120704,
				0.111621
			],
			[
				0.64,
				-0.000665,
				0.21287,
				0.121053,
				0.11197
			],
			[
				0.65,
				-0.000665,
				0.21287,
				0.121403,
				0.112319
			],
			[
				0.66,
				-0.000665,
				0.21287,
				0.121752,
				0.112669
			],
			[
				0.67,
				-0.000665,
				0.21287,
				0.122101,
				0.113018
			],
			[
				0.68,
				-0.002066,
				0.21287,
				0.12087,
				0.113367
			],
			[
				0.69,
				-0.002066,
				0.21287,
				0.121218,
				0.113716
			],
			[
				0.7,
				0.000105,
				0.212631,
				0.120892,
				0.113509
			],
			[
				0.71,
				0.000381,
				0.211985,
				0.119648,
				0.112297
			],
			[
				0.72,
				0.000658,
				0.211338,
				0.118405,
				0.111085
			],
			[
				0.73,
				0.00147,
				0.209473,
				0.114816,
				0.107657
			],
			[
				0.74,
				0.002361,
				0.207384,
				0.110878,
				0.10382
			],
			[
				0.75,
				0.003704,
				0.2043,
				0.104942,
				0.098124
			],
			[
				0.76,
				0.005436,
				0.200269,
				0.097276,
				0.090658
			],
			[
				0.77,
				0.010033,
				0.189755,
				0.086829,
				0.080816
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
				0.000105,
				0.212631
			],
			[
				0.71,
				0.000381,
				0.211985
			],
			[
				0.72,
				0.000658,
				0.211338
			],
			[
				0.73,
				0.00147,
				0.209473
			],
			[
				0.74,
				0.002361,
				0.207384
			],
			[
				0.75,
				0.003704,
				0.2043
			],
			[
				0.76,
				0.005436,
				0.200269
			],
			[
				0.77,
				0.010033,
				0.189755
			]
		]
	},
	"tail": {
		"planform": "one-piece elevator behind a swept-leading-edge stabilizer; linear fits over the clean stations, carry-through at the centreline",
		"span": {
			"value": 0.596,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): elevator mesh x extent (the stabilizer slice disappears between x = 0.29 and 0.30 m)"
		},
		"y": {
			"value": -0.032,
			"unit": "m",
			"kind": "measured",
			"source": "r1/metadata.json (author's CAD export): elevator hinge height"
		},
		"hinge_z": {
			"value": 0.704,
			"unit": "m",
			"kind": "measured",
			"source": "r1/metadata.json (author's CAD export): elevator pivot"
		},
		"le_z_centreline": {
			"value": 0.623121,
			"unit": "m",
			"kind": "derived",
			"source": "linear fit of the stabilizer leading edge extrapolated to x = 0"
		},
		"te_z_centreline": {
			"value": 0.77072,
			"unit": "m",
			"kind": "derived",
			"source": "linear fit of the elevator trailing edge extrapolated to x = 0"
		},
		"root_chord": {
			"value": 0.147599,
			"unit": "m",
			"kind": "derived",
			"source": "centreline chord from the fits"
		},
		"tip_chord": {
			"value": 0.107785,
			"unit": "m",
			"kind": "derived",
			"source": "chord at the elevator tip from the fits"
		},
		"le_sweep_deg": {
			"value": 4.988,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): leading-edge slope"
		},
		"te_sweep_deg": {
			"value": -2.653,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): elevator trailing-edge slope (negative = forward)"
		},
		"area": {
			"value": 0.076104,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: planform between the fitted edges from the centreline to the tip, both sides (r1 CAD: 0.0756 m2)"
		},
		"elevator_chord_aft_of_hinge_root": {
			"value": 0.064615,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the trailing edge at x = 0.04 m"
		},
		"elevator_chord_aft_of_hinge_tip": {
			"value": 0.050068,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the trailing edge at x = 0.29 m"
		},
		"section_y_extent": {
			"value": 0.008629,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): mean vertical extent of the stabilizer sections"
		},
		"tail_arm_quarter_chords": {
			"value": 0.607302,
			"unit": "m",
			"kind": "derived",
			"source": "stabilizer centreline quarter chord minus wing quarter chord (r1 CAD Lt: 0.612 m)"
		},
		"stations": [
			[
				0.04,
				0.62662,
				0.701788,
				0.768614
			],
			[
				0.05,
				0.627526,
				0.705097,
				0.768181
			],
			[
				0.06,
				0.628433,
				0.705097,
				0.767749
			],
			[
				0.07,
				0.62934,
				0.701809,
				0.767317
			],
			[
				0.08,
				0.630246,
				0.701816,
				0.766884
			],
			[
				0.09,
				0.631153,
				0.701823,
				0.766452
			],
			[
				0.1,
				0.632059,
				0.70183,
				0.76602
			],
			[
				0.11,
				0.632966,
				0.701837,
				0.765587
			],
			[
				0.12,
				0.633873,
				0.701845,
				0.765155
			],
			[
				0.13,
				0.634691,
				0.701852,
				0.764723
			],
			[
				0.14,
				0.634947,
				0.701859,
				0.76429
			],
			[
				0.15,
				0.635852,
				0.701866,
				0.763858
			],
			[
				0.16,
				0.636758,
				0.705097,
				0.763426
			],
			[
				0.17,
				0.637663,
				0.70188,
				0.762993
			],
			[
				0.18,
				0.638569,
				0.701887,
				0.762561
			],
			[
				0.19,
				0.639474,
				0.701894,
				0.762129
			],
			[
				0.2,
				0.64038,
				0.701901,
				0.761696
			],
			[
				0.21,
				0.641285,
				0.701908,
				0.761264
			],
			[
				0.22,
				0.642191,
				0.701916,
				0.760832
			],
			[
				0.23,
				0.643096,
				0.701922,
				0.760399
			],
			[
				0.24,
				0.644002,
				0.701928,
				0.760067
			],
			[
				0.25,
				0.644907,
				0.705097,
				0.759675
			],
			[
				0.26,
				0.645813,
				0.701939,
				0.759284
			],
			[
				0.27,
				0.646718,
				0.701944,
				0.758892
			],
			[
				0.28,
				0.647742,
				0.701979,
				0.757843
			],
			[
				0.29,
				0.649247,
				0.702143,
				0.754066
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
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): highest vertex of the model (rudder/fin tip)"
		},
		"root_y": {
			"value": 0.03,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): first horizontal slice clear of the fuselage"
		},
		"hinge_z": {
			"value": 0.738,
			"unit": "m",
			"kind": "measured",
			"source": "r1/metadata.json (author's CAD export): rudder pivot"
		},
		"rudder_te_z": {
			"value": 0.833099,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): aft-most rudder vertex"
		},
		"rudder_y": [
			-0.0704,
			0.178
		],
		"le_sweep_deg": {
			"value": 32.512,
			"unit": "deg",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): fin leading-edge slope dz/dy"
		},
		"le_z_at_root": {
			"value": 0.61726,
			"unit": "m",
			"kind": "derived",
			"source": "fitted leading edge at root_y"
		},
		"root_chord": {
			"value": 0.215839,
			"unit": "m",
			"kind": "derived",
			"source": "rudder_te_z - fitted leading edge at root_y"
		},
		"tip_chord": {
			"value": 0.12151,
			"unit": "m",
			"kind": "derived",
			"source": "rudder_te_z - fitted leading edge at top_y"
		},
		"area_above_fuselage": {
			"value": 0.024964,
			"unit": "m2",
			"kind": "derived",
			"source": "assets/aircraft/turbo-lumber-evolution/build_geometry.py: trapezoid between root_y and top_y"
		},
		"rudder_chord_aft_of_hinge": {
			"value": 0.095099,
			"unit": "m",
			"kind": "measured",
			"source": "distance from the hinge axis to the aft-most rudder vertex"
		},
		"rudder_area": {
			"value": 0.023623,
			"unit": "m2",
			"kind": "derived",
			"source": "rudder chord aft of hinge x rudder height"
		},
		"stations": [
			[
				0.03,
				0.617174,
				0.735747,
				0.832
			],
			[
				0.04,
				0.623569,
				0.7391,
				0.832
			],
			[
				0.05,
				0.629965,
				0.735967,
				0.832
			],
			[
				0.06,
				0.636361,
				0.736078,
				0.832
			],
			[
				0.07,
				0.642756,
				0.736171,
				0.832
			],
			[
				0.08,
				0.649152,
				0.736238,
				0.832
			],
			[
				0.09,
				0.655548,
				0.736305,
				0.832
			],
			[
				0.1,
				0.661943,
				0.736338,
				0.832
			],
			[
				0.11,
				0.668339,
				0.736338,
				0.832
			],
			[
				0.12,
				0.674735,
				0.736326,
				0.832
			],
			[
				0.13,
				0.681131,
				0.7391,
				0.832
			],
			[
				0.14,
				0.687526,
				0.736165,
				0.832
			],
			[
				0.15,
				0.693922,
				0.73603,
				0.832
			],
			[
				0.16,
				0.699286,
				0.735838,
				0.832
			],
			[
				0.17,
				0.706713,
				0.735593,
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
				0.041913,
				-0.035964,
				0.02417,
				false,
				false
			],
			[
				-0.2,
				0.049861,
				-0.04248,
				0.027191,
				false,
				false
			],
			[
				-0.18,
				0.067265,
				-0.045977,
				0.029999,
				false,
				false
			],
			[
				-0.16,
				0.067632,
				-0.047292,
				0.029146,
				false,
				false
			],
			[
				-0.14,
				0.067158,
				-0.048098,
				0.027944,
				false,
				false
			],
			[
				-0.12,
				0.052651,
				-0.048884,
				0.026743,
				false,
				false
			],
			[
				-0.1,
				0.052577,
				-0.051412,
				0.025599,
				false,
				false
			],
			[
				-0.08,
				0.053381,
				-0.055232,
				0.024467,
				false,
				false
			],
			[
				-0.06,
				0.056249,
				-0.062731,
				0.023335,
				false,
				false
			],
			[
				-0.04,
				0.058553,
				-0.068531,
				0.035057,
				false,
				false
			],
			[
				-0.02,
				0.05902,
				-0.073198,
				0.057143,
				false,
				false
			],
			[
				0.0,
				0.084491,
				-0.077865,
				0.103032,
				true,
				false
			],
			[
				0.02,
				0.05994,
				-0.08151,
				0.110555,
				true,
				false
			],
			[
				0.04,
				0.060383,
				-0.084379,
				0.113595,
				true,
				false
			],
			[
				0.06,
				0.060797,
				-0.086686,
				0.115308,
				true,
				false
			],
			[
				0.08,
				0.060969,
				-0.088993,
				0.11517,
				true,
				false
			],
			[
				0.1,
				0.061111,
				-0.091301,
				0.113535,
				true,
				false
			],
			[
				0.12,
				0.061147,
				-0.093014,
				0.110992,
				true,
				false
			],
			[
				0.14,
				0.060963,
				-0.094456,
				0.107671,
				true,
				false
			],
			[
				0.16,
				0.060747,
				-0.095897,
				0.105624,
				true,
				false
			],
			[
				0.18,
				0.060204,
				-0.097178,
				0.100866,
				true,
				false
			],
			[
				0.2,
				0.059442,
				-0.097496,
				0.095403,
				true,
				false
			],
			[
				0.22,
				0.058539,
				-0.097813,
				0.085938,
				false,
				false
			],
			[
				0.24,
				0.057636,
				-0.098131,
				0.085114,
				false,
				false
			],
			[
				0.26,
				0.055034,
				-0.09783,
				0.071705,
				false,
				false
			],
			[
				0.28,
				0.051297,
				-0.097117,
				0.049909,
				false,
				false
			],
			[
				0.3,
				0.049271,
				-0.096872,
				0.047573,
				false,
				false
			],
			[
				0.32,
				0.047252,
				-0.096631,
				0.045326,
				false,
				false
			],
			[
				0.34,
				0.045232,
				-0.095307,
				0.041954,
				false,
				false
			],
			[
				0.36,
				0.043212,
				-0.095134,
				0.039668,
				false,
				false
			],
			[
				0.38,
				0.040693,
				-0.094001,
				0.036458,
				false,
				false
			],
			[
				0.4,
				0.038179,
				-0.092546,
				0.033209,
				false,
				false
			],
			[
				0.42,
				0.036077,
				-0.091333,
				0.029818,
				false,
				false
			],
			[
				0.44,
				0.033975,
				-0.090029,
				0.026499,
				false,
				false
			],
			[
				0.46,
				0.031873,
				-0.088664,
				0.023229,
				false,
				false
			],
			[
				0.48,
				0.02977,
				-0.087228,
				0.020046,
				false,
				false
			],
			[
				0.5,
				0.027668,
				-0.085653,
				0.016863,
				false,
				false
			],
			[
				0.52,
				0.025566,
				-0.084097,
				0.01368,
				false,
				false
			],
			[
				0.54,
				0.023464,
				-0.083107,
				0.010497,
				false,
				false
			],
			[
				0.56,
				0.021362,
				-0.082063,
				0.012691,
				false,
				false
			],
			[
				0.58,
				0.019474,
				-0.080849,
				0.01928,
				false,
				false
			],
			[
				0.6,
				0.017858,
				-0.07954,
				0.025869,
				false,
				false
			],
			[
				0.62,
				0.016243,
				-0.078494,
				0.034419,
				false,
				true
			],
			[
				0.64,
				0.087636,
				-0.077284,
				0.06569,
				false,
				true
			],
			[
				0.66,
				0.085479,
				-0.076025,
				0.096961,
				false,
				true
			],
			[
				0.68,
				0.043389,
				-0.074614,
				0.128232,
				false,
				true
			],
			[
				0.7,
				0.087696,
				-0.073068,
				0.161112,
				false,
				true
			],
			[
				0.72,
				0.009216,
				-0.072002,
				0.178,
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
		"note": "airframe skin slices (glazing, lenses and grey brackets excluded) limited to |x| <= 0.09 m; stations inside the wing chord include the wing carry-through and stations inside the tail include the fin/stabilizer roots",
		"cowl_front_z": {
			"value": -0.234775,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): front of the airframe mesh (cowl)"
		},
		"aft_end_z": {
			"value": 0.7391,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): aft-most airframe skin vertex (fin trailing edge ahead of the rudder)"
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
			"value": 0.058002,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): largest radial vertex distance of wheel_left about its axle (author estimate 0.058 m)"
		},
		"tail_wheel_radius": {
			"value": 0.014,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): largest radial vertex distance of tailwheel about its axle (author estimate 0.014 m)"
		},
		"main_wheel_width": {
			"value": 0.043924,
			"unit": "m",
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json)"
		},
		"track": {
			"value": 0.263958,
			"unit": "m",
			"kind": "measured",
			"source": "right minus left axle x (r1 CAD: 0.264 m)"
		},
		"contacts_neutral": {
			"main_left": [
				-0.131979,
				-0.256002,
				0.008
			],
			"main_right": [
				0.131979,
				-0.256002,
				0.008
			],
			"tail": [
				0.0,
				-0.126,
				0.759
			]
		},
		"contacts_measured_bottom_y": {
			"main_left": -0.256,
			"main_right": -0.256,
			"tail": -0.126
		},
		"three_point_attitude_deg": {
			"value": 9.821,
			"unit": "deg",
			"kind": "derived",
			"source": "line through the main and tail contact points (r1 CAD: 9.8 deg)"
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
				"value": 12.0,
				"unit": "deg",
				"kind": "estimated",
				"source": "r1/metadata.json (author's CAD export): derived from the parametric CAD v12 (modelo_v12.py) (spring stretch audit)"
			},
			"spring_stiffness": "unknown (author); the simulator's contact stiffness is a model input (TT-07)",
			"cable_endpoints": {
				"der": {
					"fuselage_eyelet": [
						0.022,
						-0.090218,
						0.044
					],
					"leg_anchor_rest": [
						-0.075252,
						-0.167396,
						0.017683
					],
					"anchored_to_leg": "gear_left_suspension",
					"rigid_cable_length_m": 0.07091288250880178,
					"spring_length_rest_m": 0.056
				},
				"izq": {
					"fuselage_eyelet": [
						-0.022,
						-0.090218,
						0.03
					],
					"leg_anchor_rest": [
						0.074971,
						-0.167173,
						0.015498
					],
					"anchored_to_leg": "gear_right_suspension",
					"rigid_cable_length_m": 0.06864208183123924,
					"spring_length_rest_m": 0.056
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
			"positive": "same sense as rudder (wheel trails to the right)",
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
				"value": 0.064615,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the trailing edge at x = 0.04 m (root)"
			},
			"high_deg": {
				"value": 17.806,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0646 m"
			},
			"low_deg": {
				"value": 13.331,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 15 mm, r = 0.0646 m"
			},
			"high_deg_at_tip": {
				"value": 23.042,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0501 m"
			},
			"authored_range_deg": 22.0,
			"note": "the tapered elevator gives a larger angle for the same millimetres at the tip; the root station is the assumption"
		},
		"rudder": {
			"r": {
				"value": 0.095099,
				"unit": "m",
				"kind": "measured",
				"source": "hinge axis to the aft-most rudder vertex"
			},
			"high_deg": {
				"value": 18.15,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 30 mm, r = 0.0951 m"
			},
			"low_deg": {
				"value": 12.072,
				"unit": "deg",
				"kind": "derived",
				"source": "2 asin(d / 2r) with d = 20 mm, r = 0.0951 m"
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
	"r1_component_stations": {
		"note": "author's class-typical component estimates (1.46 kg total) as stations only; the manual's 2.190 kg flying mass is the TT-07 target (TT-00-R1 section 2)",
		"components": [
			{
				"name": "ala (2 semialas, flaps, alerones)",
				"mass_kg_r1_estimate": 0.2556,
				"z_model": 0.1013
			},
			{
				"name": "fuselaje",
				"mass_kg_r1_estimate": 0.29,
				"z_model": 0.2208
			},
			{
				"name": "cola",
				"mass_kg_r1_estimate": 0.0613,
				"z_model": 0.7033
			},
			{
				"name": "tren principal",
				"mass_kg_r1_estimate": 0.135,
				"z_model": 0.012
			},
			{
				"name": "rueda de cola",
				"mass_kg_r1_estimate": 0.012,
				"z_model": 0.7384
			},
			{
				"name": "helice y cono",
				"mass_kg_r1_estimate": 0.032,
				"z_model": -0.251
			},
			{
				"name": "motor",
				"mass_kg_r1_estimate": 0.16,
				"z_model": -0.2125
			},
			{
				"name": "variador",
				"mass_kg_r1_estimate": 0.06,
				"z_model": -0.142
			},
			{
				"name": "receptor",
				"mass_kg_r1_estimate": 0.012,
				"z_model": 0.118
			},
			{
				"name": "servos_cola",
				"mass_kg_r1_estimate": 0.026,
				"z_model": 0.228
			},
			{
				"name": "servos_ala",
				"mass_kg_r1_estimate": 0.036,
				"z_model": 0.1001
			},
			{
				"name": "cableado_luces",
				"mass_kg_r1_estimate": 0.04,
				"z_model": 0.058
			},
			{
				"name": "bateria",
				"mass_kg_r1_estimate": 0.34,
				"z_model": -0.052
			}
		]
	},
	"discrepancies": {
		"span_mm": {
			"value": -7.088,
			"unit": "mm",
			"kind": "derived",
			"source": "measured span (lenses included) minus the manual span"
		},
		"length_mm": {
			"value": 76.56,
			"unit": "mm",
			"kind": "derived",
			"source": "measured length minus the manual length; the author attributes most of it to the nose/cowl ahead of the wing (r2 request); kept as delivered (decision D4)"
		},
		"area_vs_r1_cad_percent": {
			"value": -0.236,
			"unit": "%",
			"kind": "derived",
			"source": "measured planform area against the author's CAD 0.329 m2"
		},
		"propeller_radius_mm": {
			"value": 2.221,
			"unit": "mm",
			"kind": "derived",
			"source": "measured blade-tip radius minus the author's estimate (0.1381 m); the manual propeller is 11 in = 0.1397 m radius"
		},
		"silhouette_overlay": "pending owner review: r1 side/top previews over the manual three-view (TT-02 evidence lists the files)"
	},
	"evidence": {
		"pivots": {
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json); agree with r1/metadata.json (author's CAD export) within 1e-6 m and 1e-6 in axis components"
		},
		"planform": {
			"kind": "measured",
			"source": "research/timber/tt02/measure_mesh.gd on the Godot-imported r1 scene (mesh-measurements.json): plane slices of the white/red/black skin and the control-surface meshes"
		},
		"ranges": {
			"kind": "estimated",
			"source": "r1/metadata.json (author's CAD export): authored approximations, no manual available to the modeller"
		},
		"throws": {
			"kind": "derived",
			"source": "manual millimetres (manual.json) converted at the assumed stations (controls.stations)"
		},
		"installation_angles": {
			"kind": "estimated",
			"source": "r1/metadata.json (author's CAD export): 2 deg incidence, dihedral, down and right thrust typical for the type; the export carries them, so they are measured in the mesh but not validated against the aircraft"
		},
		"length": {
			"kind": "measured",
			"source": "76.6 mm longer than the manual; unresolved (TT-02 discrepancies)"
		}
	}
}
