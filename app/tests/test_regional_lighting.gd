extends SceneTree
const FieldLoader := preload("res://data/field_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const Lighting := preload("res://render/landscape_upgrade/airfield_lighting.gd")
var failures := 0
var checks := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	var field: Dictionary = FieldLoader.load_from().field
	var scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field).scenery
	var helper: Node3D = Lighting.build(field, {}, scenery, true)
	var regional: Node3D = helper.get_node("RegionalLighting")
	var counts: Dictionary = regional.get_meta("counts")
	check("nine steady tower top lights", counts.get("pylon_top_lights", 0) == 9)
	check("eight upper conductor markers", counts.get("power_wire_markers", 0) == 8)
	check("one top beacon on every existing turbine", counts.get("turbine_beacons", 0) == 4)
	check("two downloaded communications towers", counts.get("antenna_towers", 0) == 2)
	check("two top and four middle antenna markers", counts.get("antenna_top_beacons", 0) == 2 and counts.get("antenna_mid_lights", 0) == 4)
	check("hill houses installed", regional.get_meta("hill_houses", 0) == 12)
	for category: String in ["occupied_house_windows", "house_porches", "farm_upper_windows",
			"barn_loading", "silo_access", "church_entrance", "church_windows",
			"shed_worklight", "rural_junctions", "village_street_ends", "farm_gate_bollards", "turbine_service"]:
		check("installed detail " + category, counts.get(category, 0) > 0)
	check("no per-object dynamic lights", regional.find_children("*", "Light3D", true, false).is_empty())
	check("no additional frame callback", not regional.is_processing())
	check("bounded regional optical draw groups", int(regional.get_meta("batch_count")) < 90)
	check("regional fixture geometry remains bounded", int(regional.get_meta("hardware_triangles")) < 10000)
	helper.apply_lighting({sun_elevation_deg = 12.0})
	check("daytime emission off", regional.get_meta("night_factor") == 0.0)
	helper.apply_lighting({sun_elevation_deg = -0.5})
	check("continuous dusk halfway", is_equal_approx(float(regional.get_meta("night_factor")), 0.5))
	helper.apply_lighting({sun_elevation_deg = -8.0})
	check("night emission on", regional.get_meta("night_factor") == 1.0)
	helper.set_profile("off")
	check("club switch does not extinguish regional beacons", regional.get_meta("night_factor") == 1.0)
	var instances := 0
	for node: MultiMeshInstance3D in regional.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := node.multimesh
		instances += mm.instance_count
		for i in mm.instance_count:
			check("finite regional instance", mm.get_instance_transform(i).origin.is_finite())
			# The dummy headless renderer does not retain custom GPU instance buffers.
			if node.name.begins_with("beacon") and DisplayServer.get_name() != "headless":
				var custom := mm.get_instance_custom_data(i)
				check("positive finite optical range", is_finite(custom.a) and custom.a >= 2000)
	check("bounded optical instances", instances < 250)
	print("LU-29 counts: ", counts, "; optical batches: ", regional.get_meta("batch_count"), "; optical instances: ", instances)
	helper.free()
	print("LU-29 regional lighting: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
