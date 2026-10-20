extends SceneTree

const Checker := preload("res://ai/companions/static_trajectory.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const FieldLights := preload("res://render/world/field_lights.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var field_result := FieldLoader.load_from()
	var aircraft := AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	var table := Surfaces.load_table()
	_check("real field, aircraft and surface data load", field_result.ok and aircraft.ok and table.ok)
	if not field_result.ok or not aircraft.ok or not table.ok:
		_finish()
		return
	var field: Dictionary = field_result.field
	var model: Dictionary = aircraft.model
	var surfaces: Dictionary = Surfaces.build(table.table, field)
	_check("normalized field surface build", surfaces.ok)
	var checker := Checker.new()
	var crossing := PackedFloat64Array([100, 200, -45, 300, 200, -45])
	_check("unconfigured assessment refuses", not checker.assess(crossing, 0).ok)
	_check("missing world refuses without deliberate opt-in", not checker.configure(field, {}, surfaces.rects, {}, model).ok)
	var configured: Dictionary = checker.configure(field, {}, surfaces.rects, {}, model, true)
	_check("empty scenery still has terrain and pilot protection", configured.ok and configured.protected == 1 and configured.aircraft_radius_m > 0)
	_check("clear high path passes", checker.assess(crossing, 0).clear)
	_check("low path refuses continuous terrain floor", not checker.assess(PackedFloat64Array([100, 200, -10, 300, 200, -10]), 0).clear)
	var over_pilot := PackedFloat64Array([field.pilot.north - 100, field.pilot.east, -500,
		field.pilot.north + 100, field.pilot.east, -500])
	_check("pilot exclusion applies at every altitude between endpoints", checker.assess(over_pilot, 0).get("reason") == "protected_footprint")
	var world := _world([_box("shed", "building", "shed_wall", 200, 200, -45)])
	_check("valid static inventory configures", checker.configure(field, world, surfaces.rects, {}, model).ok)
	var result: Dictionary = checker.assess(crossing, 0)
	_check("fast crossing cannot tunnel through proxy between points", result.ok and not result.clear and result.proxy_id == "shed")
	var around := PackedFloat64Array([100, 200, -45, 100, 240, -45, 300, 240, -45, 300, 200, -45])
	_check("whole-path overlap is refined with actual segments", checker.assess(around, 0).clear)
	var offset_path := PackedFloat64Array([100, 208, -45, 300, 208, -45])
	_check("clear path needs no invented error padding", checker.assess(offset_path, 0).clear)
	_check("supplied tracking error expands all segments", not checker.assess(offset_path, 10).clear)
	world.proxies[0] = _box("person", "person", "body", 200, 200, -1)
	_check("person context configures", checker.configure(field, world, surfaces.rects, {}, model).ok)
	_check("people protected footprint is independent of height", checker.assess(crossing, 0).get("reason") == "protected_footprint")
	world.proxies[0] = _box("pavilion", "building", "pavilion_roof", 200, 200, -3)
	_check("shelter context configures", checker.configure(field, world, surfaces.rects, {}, model).ok)
	_check("shelter protected footprint is independent of height", checker.assess(crossing, 0).get("reason") == "protected_footprint")
	world.proxies[0].bounds_north_min = 300.0
	_check("malformed configure invalidates previous context", not checker.configure(field, world, surfaces.rects, {}, model).ok
		and not checker.assess(around, 0).ok)
	var lake: Dictionary = LakeLoader.load_from()
	var lake_context: Dictionary = checker.configure(field, {}, surfaces.rects, lake.lake, model, true)
	_check("real lake context accepted", lake.ok and lake_context.ok)
	var water_floor: float = float(lake_context.ground_upper_m) + float(lake_context.aircraft_radius_m) + Checker.TERRAIN_CLEARANCE_M
	_check("terrain/wave height bound is enforced with aircraft footprint", not checker.assess(PackedFloat64Array([100, 200, -water_floor, 300, 200, -water_floor]), 0).clear
		and checker.assess(PackedFloat64Array([100, 200, -water_floor - 0.01, 300, 200, -water_floor - 0.01]), 0).clear)
	var malformed := crossing.duplicate()
	malformed[3] = NAN
	_check("nonfinite path refuses", not checker.assess(malformed, 0).ok)
	_check("invalid error bound refuses", not checker.assess(crossing, NAN).ok and not checker.assess(crossing, -1).ok)
	_check("unbounded point count refuses", not checker.assess(PackedFloat64Array(), 0).ok)
	var bounds := PackedFloat64Array([-2, 2, -2, 2, -2, 2])
	_check("parallel segment outside box is clear", not Checker._segment_hits_box(PackedFloat64Array([-5, 3, 0, 5, 3, 0]), 0, bounds, 3))
	_check("exact tangent blocks", Checker._segment_hits_box(PackedFloat64Array([-5, 2, 0, 5, 2, 0]), 0, bounds, 3))
	_check("stationary point inside blocks", Checker._segment_hits_box(PackedFloat64Array([0, 0, 0, 0, 0, 0]), 0, bounds, 3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var omissions := 0
	var oracle_hits := 0
	for fixture: int in 600:
		var path := PackedFloat64Array()
		for component: int in 6:
			path.append(rng.randf_range(-12, 12))
		var sampled_hit := false
		for sample: int in 201:
			var inside := true
			for axis: int in 3:
				var coordinate := lerpf(path[axis], path[axis + 3], float(sample) / 200.0)
				inside = inside and absf(coordinate) <= 2.0
			if inside:
				sampled_hit = true
				break
		if sampled_hit:
			oracle_hits += 1
			if not Checker._segment_hits_box(path, 0, bounds, 3):
				omissions += 1
	_check("independent point oracle has no missed segment intersections", oracle_hits > 20 and omissions == 0)
	print("static trajectory oracle: %d intersections, %d omissions" % [oracle_hits, omissions])
	# Exercise the complete assessment (context, bounds, radius, broad filter,
	# segments and result), against independent sampled points in occupied boxes.
	var proxies: Array = []
	for index: int in 12:
		proxies.append(_box("fixture-%d" % index, "building", "wall", 200 + rng.randf_range(-20, 20),
			200 + rng.randf_range(-20, 20), -60 + rng.randf_range(-12, 12)))
	checker.configure(field, _world(proxies), surfaces.rects, {}, model)
	var complete_hits := 0
	var complete_omissions := 0
	var clear_paths := 0
	for fixture: int in 250:
		var path := PackedFloat64Array([200 + rng.randf_range(-40, 40), 200 + rng.randf_range(-40, 40), -60 + rng.randf_range(-15, 15),
			200 + rng.randf_range(-40, 40), 200 + rng.randf_range(-40, 40), -60 + rng.randf_range(-15, 15)])
		var occupied := false
		for sample: int in 101:
			var t := float(sample) / 100.0
			var n := lerpf(path[0], path[3], t)
			var e := lerpf(path[1], path[4], t)
			var d := lerpf(path[2], path[5], t)
			for proxy: Dictionary in proxies:
				if absf(n - float(proxy.north)) <= 1.0 and absf(e - float(proxy.east)) <= 1.0 and absf(d - float(proxy.down)) <= 1.0:
					occupied = true
					break
			if occupied: break
		var assessment: Dictionary = checker.assess(path, 0.0)
		if assessment.clear: clear_paths += 1
		if occupied:
			complete_hits += 1
			if assessment.clear: complete_omissions += 1
	_check("complete assessment includes sampled occupied geometry", complete_hits > 0 and complete_omissions == 0 and clear_paths > 0)
	var scenery := SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field)
	var lights := FieldLights.load_from()
	_check("production scenery and lights load", scenery.ok and lights.ok)
	if scenery.ok and lights.ok:
		var built := CollisionWorld.build(field, scenery.scenery, lights.lights)
		_check("full production collision context configures", built.ok and checker.configure(field, built.world, surfaces.rects, lake.lake, model).ok)
		var circuit := PackedFloat64Array()
		for point: int in 33:
			var phase := TAU * float(point) / 32.0
			circuit.append_array(PackedFloat64Array([199.0 + 80.0 * cos(phase), 80.0 * sin(phase), -35.0]))
		_check("nominal circuit geometric polyline clears actual context", checker.assess(circuit, 0.5).clear)
		print("full trajectory context: %s proxies=%d" % [built.world.identity, built.world.proxies.size()])
		var dense_circuit := PackedFloat64Array()
		for point: int in Checker.MAX_POINTS:
			var phase := TAU * float(point) / float(Checker.MAX_POINTS - 1)
			dense_circuit.append_array(PackedFloat64Array([199.0 + 80.0 * cos(phase), 80.0 * sin(phase), -35.0]))
		_check("maximum-point circuit clears actual context", checker.assess(dense_circuit, 0.5).clear)
		var oversized := dense_circuit.duplicate()
		oversized.append_array(dense_circuit.slice(0, 3))
		_check("one point beyond maximum refuses", not checker.assess(oversized, 0.5).ok)
	# Every broad-phase box overlaps this square's bounds, while the actual
	# perimeter misses every obstacle: exercise the full bounded narrow phase.
	var maximum_proxies: Array = []
	for index: int in 10000:
		maximum_proxies.append(_box("maximum-%05d" % index, "building", "wall", 200, 200, -60))
	_check("maximum inventory configures", checker.configure(field, _world(maximum_proxies), surfaces.rects, {}, model).ok)
	var maximum_path := PackedFloat64Array()
	var corners := PackedFloat64Array([100, 100, -60, 100, 300, -60, 300, 300, -60, 300, 100, -60])
	for point: int in Checker.MAX_POINTS:
		var offset := (point % 4) * 3
		maximum_path.append_array(corners.slice(offset, offset + 3))
	var maximum_result: Dictionary = checker.assess(maximum_path, 0.0)
	_check("maximum work remains complete and clear", maximum_result.ok and maximum_result.clear
		and maximum_result.candidate_proxies == 10000 and maximum_result.segment_checks == 1280000)
	maximum_proxies.append(_box("over-limit", "building", "wall", 200, 200, -60))
	_check("inventory beyond limit refuses and invalidates", not checker.configure(field, _world(maximum_proxies), surfaces.rects, {}, model).ok
		and not checker.assess(maximum_path, 0).ok)
	var huge_proxy := _box("oversized", "building", "wall", 400000, 400000, -60)
	huge_proxy.half_x = 100000.0
	huge_proxy.half_z = 100000.0
	huge_proxy.bounds_north_min = 300000.0
	huge_proxy.bounds_north_max = 500000.0
	huge_proxy.bounds_east_min = 300000.0
	huge_proxy.bounds_east_max = 500000.0
	_check("oversized bin inventory falls back without omission", checker.configure(field, _world([huge_proxy]), surfaces.rects, {}, model).ok
		and checker.assess(PackedFloat64Array([399990, 400000, -60, 400010, 400000, -60]), 0).get("proxy_id") == "oversized")
	_check("oversized bin query falls back without omission", checker.configure(field, _world([_box("query-target", "building", "wall", 200, 200, -60)]), surfaces.rects, {}, model).ok
		and checker.assess(PackedFloat64Array([-900000, 200, -60, 900000, 200, -60]), 0).get("proxy_id") == "query-target")
	_finish()

func _box(id: String, kind: String, part: String, n: float, e: float, d: float) -> Dictionary:
	return {id = id, kind = kind, part = part, shape = "box", response_class = "rigid",
		north = n, east = e, down = d, radius = 1.0, half_length = 0.0, half_x = 1.0,
		half_z = 1.0, half_down = 1.0, sin_heading = 0.0, cos_heading = 1.0,
		bounds_north_min = n - 1, bounds_north_max = n + 1, bounds_east_min = e - 1,
		bounds_east_max = e + 1, bounds_down_min = d - 1, bounds_down_max = d + 1}

func _world(proxies: Array) -> Dictionary:
	return {format = "openrc-collision-world v1", identity = "analytic-test-fixture", proxies = proxies, bins = {}, cell_size_m = 32.0}

func _check(description: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", description)

func _finish() -> void:
	print("static trajectory: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
