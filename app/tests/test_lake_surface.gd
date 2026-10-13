## LU-25: the lake's bounded NED terrain, water surface and swept probes share one definition.
## Run: godot --headless --path app --script res://tests/test_lake_surface.gd
extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const Lake := preload("res://physics/lake_surface.gd")

var _failures: int = 0
var _raw: Dictionary = {}
var _lake: Dictionary = {}


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH)
	_check("authored lake definition loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	_lake = loaded.lake
	_raw = JSON.parse_string(FileAccess.get_file_as_string(Loader.DEFAULT_PATH))
	_test_definition()
	_test_terrain()
	_test_water()
	_test_sweeps()
	print("all lake surface checks passed" if _failures == 0 else "%d lake surface checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_definition() -> void:
	_check("lake id and stable identity are present", _lake.id == "near_runway" and String(_lake.identity).length() == 64)
	var north_min: float = INF
	var north_max: float = -INF
	var east_min: float = INF
	var east_max: float = -INF
	for index: int in range(0, _lake.shoreline_ne_m.size(), 2):
		north_min = minf(north_min, _lake.shoreline_ne_m[index])
		north_max = maxf(north_max, _lake.shoreline_ne_m[index])
		east_min = minf(east_min, _lake.shoreline_ne_m[index + 1])
		east_max = maxf(east_max, _lake.shoreline_ne_m[index + 1])
	_check("authored irregular shoreline is about 90 by 60 metres at N110 E125",
		_lake.origin_north_m == 110.0 and _lake.origin_east_m == 125.0
		and _lake.shoreline_ne_m.size() == 40 and absf((east_max - east_min) - 90.0) < 1e-9
		and absf((north_max - north_min) - 59.0) < 1e-9)
	_check("profile includes a shallow shelf and five-metre deep basin",
		absf(_lake.bed_profile[1].inset_m - 5.5) < 1e-9 and absf(_lake.bed_profile[1].depth_m - 0.8) < 1e-9
		and absf(_lake.bed_profile[2].depth_m - 5.0) < 1e-9)
	var repeated: Dictionary = Loader.validate(_raw.duplicate(true))
	_check("normalized identity is repeatable", repeated.ok and repeated.lake.identity == _lake.identity)
	var moved_level: Dictionary = _raw.duplicate(true)
	moved_level.water_level_down_m = 0.46
	var changed: Dictionary = Loader.validate(moved_level)
	_check("identity changes with physical definition", changed.ok and changed.lake.identity != _lake.identity)
	_check("missing file is refused", not Loader.load_from("res://data/fields/missing_lake.json").ok)
	_refuse("unknown format", func(c: Dictionary) -> void: c.format = "openrc-lake v0", "format")
	_refuse("non-finite or out-of-range water level", func(c: Dictionary) -> void: c.water_level_down_m = -2.0, "water_level_down_m")
	_refuse("self-crossing shoreline", func(c: Dictionary) -> void: c.shoreline_offsets_ne_m[3] = c.shoreline_offsets_ne_m[12], "shoreline_offsets_ne_m")
	_refuse("undersized bed profile", func(c: Dictionary) -> void: c.bed_profile = [c.bed_profile[0]], "bed_profile")
	_refuse("non-monotonic basin profile", func(c: Dictionary) -> void: c.bed_profile[1].depth_m = 6.0, "bed_profile")
	_refuse("unbounded wave amplitude", func(c: Dictionary) -> void: c.waves.max_amplitude_m = 1.0, "waves.max_amplitude_m")
	_refuse("summed component amplitude exceeds bound", func(c: Dictionary) -> void: c.waves.components[1].amplitude_m = 0.04, "waves.components")
	_check("invalid normalized data fails closed", not Lake.sample_terrain({}, 110.0, 125.0).covered)
	var malformed: Dictionary = _lake.duplicate(true)
	malformed.bed_profile = [{"inset_m": 0.0, "depth_m": 0.0}]
	_check("malformed normalized profile fails closed", Lake.sample_terrain(malformed, 110.0, 125.0).region == "invalid")


func _test_terrain() -> void:
	var center: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 125.0)
	_check("deep basin sample stays bounded inside lake", center.covered and center.region == "bed")
	_check("sample exposes blend, signed distances, and depth-only slope", center.blend_fraction == 1.0
		and center.signed_shore_distance_m > 0.0 and center.signed_bank_distance_m > 0.0
		and is_finite(center.bed_depth_slope_north) and is_finite(center.bed_depth_slope_east))
	var shore_center: float = Lake.shore_distance_validated(_lake, 110.0, 125.0)
	var shore_bank: float = Lake.shore_distance_validated(_lake, 110.0, 174.0)
	_check("shore-only distance matches terrain sign without a terrain sample",
		absf(shore_center - center.signed_shore_distance_m) < 1e-9
		and shore_center > 0.0 and shore_bank < 0.0)
	_check("shore-only distance rejects non-finite and malformed geometry",
		is_nan(Lake.shore_distance_validated(_lake, NAN, 125.0))
		and is_nan(Lake.shore_distance_validated({}, 110.0, 125.0)))
	_check("shore-only query does not require a bed profile or wave state",
		Lake.shore_distance_validated({shoreline_ne_m = _lake.shoreline_ne_m}, 110.0, 125.0) > 0.0)
	_check("deep floor is five metres under the mean waterline",
		absf(center.water_down_m - 0.45) < 1e-12 and absf(center.depth_m - 5.0) < 1e-9
		and absf(center.ground_down_m - 5.45) < 1e-9, str(center))
	_check("terrain slopes are finite float64 values", is_finite(center.slope_north) and is_finite(center.slope_east))
	var bank: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 174.0)
	_check("bank is a covered, shallower terrain region", bank.covered and bank.region == "bank"
		and bank.ground_down_m > 0.0 and bank.ground_down_m < center.ground_down_m
		and bank.blend_fraction > 0.0 and bank.blend_fraction < 1.0
		and bank.signed_shore_distance_m < 0.0 and bank.signed_bank_distance_m > 0.0, str(bank))
	var outside: Dictionary = Lake.sample_terrain_validated(_lake, 200.0, 200.0)
	_check("outside bounded bank is untouched", not outside.covered and outside.region == "outside"
		and outside.ground_down_m == 0.0 and outside.slope_north == 0.0 and outside.slope_east == 0.0
		and outside.blend_fraction == 0.0 and outside.signed_bank_distance_m < 0.0, str(outside))
	var shore_inside: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 170.0 - 0.000001)
	var shore_outside: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 170.0 + 0.000001)
	_check("bank and submerged bed meet continuously at the shoreline",
		shore_inside.covered and shore_outside.covered and absf(shore_inside.ground_down_m - shore_outside.ground_down_m) < 0.00001,
		"inside=%s outside=%s" % [shore_inside, shore_outside])
	var bank_edge: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 176.0)
	var beyond_bank: Dictionary = Lake.sample_terrain_validated(_lake, 110.0, 176.1)
	_check("bank height joins the unchanged field datum", bank_edge.covered and not beyond_bank.covered
		and absf(bank_edge.ground_down_m - beyond_bank.ground_down_m) < 0.00001, "edge=%s beyond=%s" % [bank_edge, beyond_bank])
	var bad_query: Dictionary = Lake.sample_terrain_validated(_lake, NAN, 125.0)
	_check("non-finite terrain query fails closed", bad_query.region == "invalid" and is_nan(bad_query.ground_down_m))


func _test_water() -> void:
	var mean: float = Lake.water_mean_down(_lake)
	_check("water mean datum is shared with the renderer", absf(mean - 0.45) < 1e-12)
	_check("water outside the shoreline has no surface sample", is_nan(Lake.water_height_down(_lake, 200.0, 200.0)))
	var zero_wave: Array[Dictionary] = [{"amplitude_m": 0.0, "wavelength_m": 8.0, "period_s": 2.4, "heading_rad": 0.3, "phase_rad": 0.2}]
	_check("zero wave matches shared mean-down surface",
		absf(Lake.water_height_down(_lake, 110.0, 125.0, 0.4, zero_wave) - mean) < 1e-12)
	var waves: Array[Dictionary] = [{"amplitude_m": 0.05, "wavelength_m": 8.0, "period_s": 2.4, "heading_rad": 0.3, "phase_rad": 0.2}]
	var first: float = Lake.water_height_down(_lake, 110.0, 125.0, 0.4, waves)
	var next_period: float = Lake.water_height_down(_lake, 110.0, 125.0, 2.8, waves)
	_check("bounded wave repeats on the supplied simulation period", is_finite(first) and absf(first - next_period) < 1e-9)
	_check("wave displacement stays within authored amplitude", absf(first - mean) <= 0.1 + 1e-9)
	_check("water-down displacement mirrors positive-up render waves",
		absf((first - mean) + 0.05 * sin(6.2831853071795864769 * (cos(0.3) * 110.0 + sin(0.3) * 125.0) / 8.0 - 6.2831853071795864769 * 0.4 / 2.4 + 0.2)) < 1e-8)
	_check("shoreline wave fades to the shared mean", absf(Lake.water_height_down(_lake, 110.0, 170.0, 0.4, waves) - mean) < 1e-9)
	var invalid_waves: Array[Dictionary] = [{"amplitude_m": 0.07, "wavelength_m": 8.0, "period_s": 2.4, "heading_rad": 0.3, "phase_rad": 0.2}]
	_check("unbounded wave parameters fail closed", is_nan(Lake.water_height_down(_lake, 110.0, 125.0, 0.0, invalid_waves)))
	_check("authored renderer components are bounded to two", _lake.waves.size() == 2
		and absf(_lake.waves[0].amplitude_m + _lake.waves[1].amplitude_m - 0.055) < 1e-12)


func _test_sweeps() -> void:
	var probes: Array[Dictionary] = [
		{"name": "body", "from": PackedFloat64Array([110.0, 50.0, -2.0]), "to": PackedFloat64Array([110.0, 160.0, 1.0])},
		{"name": "wingtip", "from": PackedFloat64Array([117.0, 50.0, -2.0]), "to": PackedFloat64Array([117.0, 160.0, 1.0])},
		{"name": "gear", "from": PackedFloat64Array([103.0, 50.0, -2.0]), "to": PackedFloat64Array([103.0, 160.0, 1.0])},
	]
	for probe: Dictionary in probes:
		var probe_name: String = probe.name
		var event: Dictionary = Lake.sweep_probe(_lake, probe.from, probe.to, 0.0, 1.0, _flat_waves())
		_check("high-speed %s probe finds earliest water crossing" % probe_name,
			bool(event.get("ok", false)) and bool(event.get("hit", false)) and event.get("material") == "water"
			and float(event.fraction) > 0.0 and float(event.fraction) < 1.0
			and event.east_m > 80.0 and event.east_m < 170.0, str(event))
	var above_water := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 90.0, 0.44]), PackedFloat64Array([110.0, 160.0, 0.44]), 0.0, 1.0, _flat_waves())
	_check("a grazing horizontal flight above the waterline does not collide", above_water.ok and not above_water.hit, str(above_water))
	var high_airborne := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 40.0, -0.001]), PackedFloat64Array([110.0, 190.0, -0.001]), 0.0, 1.0)
	_check("a high-speed chord above the entire water and bank envelope misses cleanly",
		high_airborne.ok and not high_airborne.hit, str(high_airborne))
	var invalid_high_airborne := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 40.0, -10.0]), PackedFloat64Array([110.0, 190.0, -10.0]),
		0.0, 1.0, [{"amplitude_m": 0.07, "wavelength_m": 8.0,
		"period_s": 2.4, "heading_rad": 0.0, "phase_rad": 0.0}])
	_check("airborne rejection still refuses wave data beyond validated bounds",
		not invalid_high_airborne.ok and not invalid_high_airborne.hit, str(invalid_high_airborne))
	var touching_water := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 90.0, 0.45]), PackedFloat64Array([110.0, 160.0, 0.45]), 0.0, 1.0, _flat_waves())
	_check("a probe that only grazes the water plane reports contact", touching_water.ok and touching_water.hit
		and touching_water.material == "water", str(touching_water))
	var outside := Lake.sweep_probe(_lake,
		PackedFloat64Array([146.0, 60.0, 0.1]), PackedFloat64Array([146.0, 180.0, 0.1]), 0.0, 1.0, _flat_waves())
	_check("a path outside the bank polygon remains clear", outside.ok and not outside.hit, str(outside))
	var bank_hit := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 180.0, 0.2]), PackedFloat64Array([110.0, 160.0, 0.2]), 0.0, 0.2, _flat_waves())
	_check("the dry bank reports its own terminal material", bank_hit.ok and bank_hit.hit
		and bank_hit.material == "bank_ground" and bank_hit.east_m > 170.0, str(bank_hit))
	var highest_bank_graze := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 176.1, 0.0]), PackedFloat64Array([110.0, 174.5, 0.0]),
		0.0, 0.1, _flat_waves())
	_check("exact contact at the highest bank edge is not rejected by the vertical envelope",
		highest_bank_graze.ok and highest_bank_graze.hit
		and highest_bank_graze.material == "bank_ground", str(highest_bank_graze))
	var tangent_bank := Lake.sweep_probe(_lake,
		PackedFloat64Array([145.0, 100.0, 0.2]), PackedFloat64Array([145.0, 160.0, 0.2]), 0.0, 0.1, _flat_waves())
	_check("a tangent bank-vertex touch remains a terminal ground event", tangent_bank.ok and tangent_bank.hit
		and tangent_bank.material == "bank_ground" and absf(tangent_bank.north_m - 145.0) < 1e-8, str(tangent_bank))
	var tangent_shore := Lake.sweep_probe(_lake,
		PackedFloat64Array([140.0, 130.0, 0.45]), PackedFloat64Array([140.0, 140.0, 0.45]), 0.0, 0.1, _flat_waves())
	_check("a tangent shoreline touch is classified as water", tangent_shore.ok and tangent_shore.hit
		and tangent_shore.material == "water" and absf(tangent_shore.north_m - 140.0) < 1e-8, str(tangent_shore))
	var time_order := Lake.sweep_probe(_lake, probes[0].from, probes[0].to, 2.0, 1.0, _flat_waves())
	_check("unordered sweep time is rejected", not time_order.ok and not time_order.hit, str(time_order))
	var bad_point := Lake.sweep_probe(_lake, PackedFloat64Array([0.0, 0.0]), probes[0].to)
	_check("malformed probe point is rejected", not bad_point.ok and not bad_point.hit, str(bad_point))
	var starts_below := Lake.sweep_probe(_lake,
		PackedFloat64Array([110.0, 90.0, 0.6]), PackedFloat64Array([110.0, 160.0, 0.6]), 0.0, 0.5, _flat_waves())
	_check("already-submerged probe reports immediate water contact", starts_below.ok and starts_below.hit
		and starts_below.material == "water" and starts_below.fraction == 0.0, str(starts_below))


func _flat_waves() -> Array[Dictionary]:
	return [{"amplitude_m": 0.0, "wavelength_m": 8.0, "period_s": 2.4, "heading_rad": 0.0, "phase_rad": 0.0}]


func _refuse(label: String, edit: Callable, needle: String) -> void:
	var copy: Dictionary = _raw.duplicate(true)
	edit.call(copy)
	var result: Dictionary = Loader.validate(copy)
	var found: bool = false
	for error_text: String in result.errors:
		found = found or error_text.contains(needle)
	_check("refused: " + label, not result.ok and found, str(result.errors))


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
