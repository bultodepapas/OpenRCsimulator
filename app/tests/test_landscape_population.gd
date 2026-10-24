# LU-02: check catalog-complete field population and bounded procedural life.
# Run: godot --headless --path . --script res://tests/test_landscape_population.gd
extends SceneTree

const AircraftCatalog = preload("res://app_state/aircraft_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const Models = preload("res://scenery/models.gd")
const ParkedAircraft = preload("res://scenery/parked_aircraft.gd")
const GroundFeatures = preload("res://scenery/ground_features.gd")
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
		_test_parked_support()
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
	var catalog_ids := Array(AircraftCatalog.airplane_flyable_ids())
	var parked_ids: Array = fleet.get("aircraft", [])
	var model_ids: Array = ParkedAircraft.AIRCRAFT.keys()
	var unique_models: Dictionary = {}
	for id: String in model_ids:
		unique_models[id] = true
	var unique_parked: Dictionary = {}
	for id: String in parked_ids:
		unique_parked[id] = true
	var parked_are_flyable: bool = not parked_ids.is_empty() and unique_parked.size() == parked_ids.size()
	for id: String in parked_ids:
		parked_are_flyable = parked_are_flyable and catalog_ids.has(id)
	_check("parked snapshots are a nonempty unique subset of flyable aircraft",
		parked_are_flyable, "flyable=%s parked=%s" % [catalog_ids, parked_ids])
	_check("fleet placement IDs match the baked snapshot source map",
		parked_ids == model_ids and model_ids.size() == unique_models.size(),
		"parked=%s baked=%s" % [parked_ids, model_ids])
	for id: String in parked_ids:
		var mesh := ParkedAircraft.mesh(id)
		_check("%s resolves to a material-preserving static mesh" % id,
			mesh != null and not ParkedAircraft.info(id).is_empty(), id)


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
	for id: String in ["pilots", "pits-people", "pits-workers", "seated", "veranda-people"]:
		var group := _group(groups, id)
		person_count += group.get("placements", []).size()
		var prefab := str(group.get("prefab", ""))
		if not prefab.is_empty():
			person_prefabs[prefab] = int(person_prefabs.get(prefab, 0)) + group.get("placements", []).size()
	_check("all 13 existing people placements remain in the layout", person_count == 13, str(person_count))
	_check("all four population person types occur in those 13 placements (SC-HUM-06 adds pit workers)",
		person_prefabs.keys().size() == 4 and person_prefabs.has("person_standing")
		and person_prefabs.has("person_sitting") and person_prefabs.has("person_pilot")
		and person_prefabs.has("person_working"), str(person_prefabs))
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
	for id: String in ["person_standing", "person_sitting", "person_pilot", "person_working"]:
		_check("%s uses a production population batch" % id,
			Population.ASSETS.has(id) and Population.handles(id), str(Population.ASSETS.get(id, "missing")))


func _test_parked_support() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var counts := {grass = 0, slab = 0, table = 0, service = 0}
	var scales := {}
	for group: Dictionary in scenery.groups:
		if group.type != "fleet":
			continue
		for placement: Dictionary in group.placements:
			var mesh := ParkedAircraft.mesh(placement.aircraft, placement.configuration)
			_check("snapshot has a grounded bottom " + str(group.id),
				absf(mesh.get_aabb().position.y) < 0.002, str(mesh.get_aabb()))
			var base := float(placement.elevation)
			if is_zero_approx(base):
				counts.grass += 1
			elif is_equal_approx(base, 0.1):
				counts.slab += 1
			else:
				counts.table += 1
				_check("bench receiver is the existing table or foam top",
					is_equal_approx(base, 0.9) or is_equal_approx(base, 1.12))
			if placement.configuration == "service":
				counts.service += 1
			scales[placement.scale] = true
	_check("layout has five slab, five grass and three bench aircraft",
		counts.slab == 5 and counts.grass == 5 and counts.table == 3, str(counts))
	_check("one maintenance configuration and at least four uniform scales",
		counts.service == 1 and scales.size() >= 4, str(scales))
	for sun: Vector3 in [Vector3(-0.4, 0.8, -0.3).normalized(), Vector3(0.8, 0.1, 0.5).normalized()]:
		var shadow := MeshKit.new()
		var table := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-42.6, 0.9, 19.9))
		GroundFeatures.contact_shadow(shadow, table, Vector3(1.0, 0.4, 1.1), "aircraft_jet_bench", sun)
		var on_worktop := not shadow.verts.is_empty()
		for vertex: Vector3 in shadow.verts:
			on_worktop = on_worktop and absf(vertex.y - 0.904) < 0.001 \
				and absf(vertex.x - table.origin.x) <= 1.201 and absf(vertex.z - table.origin.z) <= 0.401
		_check("bench shadows stay on the table at high and low sun", on_worktop)


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
	var imported_plants: Node3D = root.get_node_or_null("ImportedVegetationBatches") as Node3D
	var moving_people := int(stats.get("moving_people", -1))
	_check("scenery retains the original rotor and flag count", counts.rotor == 4 and counts.flag == 1, str(counts))
	_check("downloaded trees and shrubs use source batches without procedural tip motions",
		counts.crown == 0 and counts.bush_tips == 0 and imported_plants != null
		and int(stats.get("vegetation_instances", 0)) >= 16
		and imported_plants.get_children().all(func(child: Node) -> bool: return child is MultiMeshInstance3D),
		"motion=%s instances=%d" % [counts, int(stats.get("vegetation_instances", 0))])
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
