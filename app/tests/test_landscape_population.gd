# LU-02: check catalog-complete field population and bounded procedural life.
# Run: godot --headless --path . --script res://tests/test_landscape_population.gd
extends SceneTree

const AircraftCatalog = preload("res://app_state/aircraft_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Models = preload("res://scenery/models.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Prefabs = preload("res://scenery/prefabs.gd")
const Population = preload("res://scenery/population.gd")
const Scenery = preload("res://scenery/scenery.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var loaded := Loader.load_from(Loader.DEFAULT_PATH, field)
	_check("default population data validates", loaded.ok, str(loaded.errors))
	if loaded.ok:
		_test_catalog_fleet(loaded.scenery.groups)
		_test_parking_and_people(loaded.scenery.groups)
		_test_population_mapping()
		_test_cradle_support()
		_test_prefab_proportions()
		_test_animated_parts(field, loaded.scenery)
	print("all landscape population checks passed" if _failures == 0 else "%d landscape population checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _group(groups: Array, id: String) -> Dictionary:
	for g: Dictionary in groups:
		if g.id == id:
			return g
	return {}


func _test_catalog_fleet(groups: Array) -> void:
	var fleet := _group(groups, "fleet")
	var catalog_ids := Array(AircraftCatalog.flyable_ids()) # TT-06: a preview has no parked snapshot (TT-13b decides)
	var model_ids: Array = Models.FLEET.values()
	var unique_models: Dictionary = {}
	for id: String in model_ids:
		unique_models[id] = true
	_check("parked fleet IDs exactly match the flyable flight catalog in order",
		fleet.get("aircraft", []) == catalog_ids and fleet.get("aircraft", []).size() == 4,
		"flight=%s parked=%s" % [catalog_ids, fleet.get("aircraft", [])])
	_check("baked fleet source map exactly covers the flight catalog",
		model_ids.size() == catalog_ids.size() and unique_models.size() == model_ids.size()
		and model_ids.all(func(id: String) -> bool: return catalog_ids.has(id)))
	for id: String in catalog_ids:
		var model_id := str(Models.FLEET.find_key(id))
		_check("%s resolves to a baked display model" % id,
			not model_id.is_empty() and not Models.arrays(model_id).is_empty(), model_id)


func _test_parking_and_people(groups: Array) -> void:
	var cars := _group(groups, "cars")
	var car_styles: Array = cars.get("choices", [])
	var seen_styles: Dictionary = {}
	var headings: Dictionary = {}
	for p: Dictionary in cars.get("placements", []):
		seen_styles[p.prefab] = true
		headings[int(round(float(p.heading) / 5.0))] = true
	_check("all four catalog car styles are used across 11 parking places",
		car_styles.size() == 4 and cars.placements.size() == 11 and seen_styles.size() == 4,
		"styles=%s placements=%d used=%s" % [car_styles, cars.get("placements", []).size(), seen_styles.keys()])
	_check("parked cars have a staggered, rotated layout",
		cars.placements.size() == 11 and headings.size() >= 5,
		"distinct heading bands=%d" % headings.size())
	var person_count := 0
	var person_prefabs: Dictionary = {}
	for id: String in ["pilots", "pits-people", "seated", "veranda-people"]:
		var group := _group(groups, id)
		person_count += group.get("placements", []).size()
		var prefab := str(group.get("prefab", ""))
		if not prefab.is_empty():
			person_prefabs[prefab] = int(person_prefabs.get(prefab, 0)) + group.get("placements", []).size()
	_check("all 13 existing people placements remain in the layout", person_count == 13, str(person_count))
	_check("all three population person types occur in those 13 placements",
		person_prefabs.keys().size() == 3 and person_prefabs.has("person_standing")
		and person_prefabs.has("person_sitting") and person_prefabs.has("person_pilot"), str(person_prefabs))
	var population_people := 0
	for prefab: String in person_prefabs:
		population_people += int(person_prefabs[prefab])
	_check("every default person placement is covered by the population source map",
		population_people == 13 and person_prefabs.keys().all(func(id: String) -> bool:
			return Population.ASSETS.has(id) and Population.handles(id)), str(person_prefabs))


func _test_population_mapping() -> void:
	var car_ids := ["car_sedan", "car_hatch", "car_suv", "car_sport"]
	var car_sources: Dictionary = {}
	for id: String in car_ids:
		var asset := str(Population.ASSETS.get(id, ""))
		car_sources[asset] = true
		_check("%s uses the production population batch" % id,
			Models.CATALOG.has(id) and Population.handles(id) and not asset.is_empty(), asset)
	_check("the four legacy car IDs resolve to exactly three replacement body styles",
		car_sources.size() == 3 and car_sources.has("sedan") and car_sources.has("hatch")
		and car_sources.has("crossover"), str(car_sources.keys()))
	for id: String in ["person_standing", "person_sitting", "person_pilot"]:
		_check("%s uses a production population batch" % id,
			Population.ASSETS.has(id) and Population.handles(id), str(Population.ASSETS.get(id, "missing")))


func _test_cradle_support() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Loader.DEFAULT_PATH))
	var fleet_raw := {}
	var cradle_raw := {}
	for g: Dictionary in raw.groups:
		if g.id == "fleet":
			fleet_raw = g
		elif g.id == "avanti-cradle":
			cradle_raw = g
	var idx: int = fleet_raw.aircraft.find("sebart-avanti-s-a200-p100rx")
	var aircraft_row: Array = fleet_raw.placements.value[idx]
	var cradle_row: Array = cradle_raw.placements.value[0] if not cradle_raw.is_empty() else []
	var aligned := cradle_row.size() == 3
	if aligned:
		aligned = absf(float(cradle_row[0]) - float(aircraft_row[0])) < 0.01 \
			and absf(float(cradle_row[1]) - float(aircraft_row[1])) < 0.01 \
			and absf(float(cradle_row[2]) - float(aircraft_row[2])) < 0.01
	_check("gear-up Avanti display cradle aligns with its catalog snapshot", aligned,
		"aircraft=%s cradle=%s" % [aircraft_row, cradle_row])
	var kit := MeshKit.new()
	Prefabs.build("avanti_cradle", kit, 1, "temperate")
	_check("Avanti cradle has padded trestle geometry", kit.triangle_count() > 40)
	var cradle_top := -INF
	for v: Vector3 in kit.verts:
		cradle_top = maxf(cradle_top, v.y)
	var aircraft: Dictionary = Models.arrays("fleet_avanti")
	var model_bottom := INF
	for v: Vector3 in aircraft.pos:
		model_bottom = minf(model_bottom, v.y)
	var clearance := Models.parked_base_height("fleet_avanti") + model_bottom - cradle_top
	_check("Avanti's lifted snapshot clears the cradle without a visible gap",
		clearance >= 0.0 and clearance <= 0.03,
		"base=%.3f model-bottom=%.3f cradle-top=%.3f gap=%.3f m" %
		[Models.parked_base_height("fleet_avanti"), model_bottom, cradle_top, clearance])


func _test_prefab_proportions() -> void:
	for id: String in ["person_standing", "person_sitting", "person_pilot"]:
		var kit := MeshKit.new()
		var moving: Array = Prefabs.build(id, kit, 1234, "temperate")
		var box := AABB(kit.verts[0], Vector3.ZERO)
		var lowest_y := INF
		for v: Vector3 in kit.verts:
			box = box.expand(v)
			lowest_y = minf(lowest_y, v.y)
		for part: Dictionary in moving:
			var part_kit: MeshKit = part.kit
			for v: Vector3 in part_kit.verts:
				box = box.expand(v + part.pivot)
		print("     %s measured full mesh bounds: %s" % [id, box.size])
		var expected_height := Vector2(1.55, 1.95) if id != "person_sitting" else Vector2(1.15, 1.5)
		var width_ok := box.size.x >= 0.48 and box.size.x <= 1.05
		_check("%s has adult-scale head-to-foot proportions" % id,
			box.size.y >= expected_height.x and box.size.y <= expected_height.y,
			"bbox=%s" % box.size)
		_check("%s has a plausible body width" % id, width_ok, "bbox=%s" % box.size)
		_check("%s geometry includes garments and limbs" % id, kit.triangle_count() > 100, str(kit.triangle_count()))
		_check("%s shoe soles meet the prefab ground plane" % id,
			absf(lowest_y) <= 0.001, "lowest local vertex y=%.4f m" % lowest_y)


func _test_animated_parts(field: Dictionary, scenery: Dictionary) -> void:
	var root := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"})
	var motion: Node = root.get_node("Motion")
	var counts := {rotor = 0, flag = 0, crown = 0, bush_tips = 0, person = 0}
	for node: Node in motion.get_children():
		for kind: String in counts:
			if str(node.name).begins_with(kind + "_"):
				counts[kind] += 1
	var stats: Dictionary = root.get_meta("stats")
	var population: Node3D = root.get_node_or_null("Population") as Node3D
	var moving_people := int(stats.get("moving_people", -1))
	_check("scenery retains the original rotor and flag count", counts.rotor == 4 and counts.flag == 1, str(counts))
	_check("tree and shrub tip motions match 10 shade trees and 6 shrubs",
		counts.crown == 10 and counts.bush_tips == 6, str(counts))
	_check("people animate through the bounded population shader, not per-person Motion nodes",
		counts.person == 0 and moving_people >= 2 and moving_people <= 9,
		"legacy nodes=%d population moving=%d" % [counts.person, moving_people])
	_check("the production population batches all 24 default placements",
		population != null and int(stats.get("population", -1)) == 24
		and int(population.get_meta("instances", -1)) == 24,
		"stats=%d node=%d" % [int(stats.get("population", -1)), int(population.get_meta("instances", -1)) if population != null else -1])
	_check("added motion stays below 40 moving draws", motion.get_child_count() <= 40,
		"moving mesh count=%d" % motion.get_child_count())
	root.free()
