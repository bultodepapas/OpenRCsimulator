## LU-25-R1: cache invalidation, frozen-guard parity and bounded retention.
## Run: godot --headless --path app --script res://tests/test_lake_definition_cache.gd
extends SceneTree

const Loader := preload("res://data/lake_loader.gd")
const Lake := preload("res://physics/lake_surface.gd")
const Reference := preload("res://tests/fixtures/lake_definition_reference.gd")

var _failures: int = 0
var _base: Dictionary = {}


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH)
	_check("authored lake fixture loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	_base = loaded.lake.duplicate(true)
	_test_required_field_mutations()
	_test_missing_and_shape_mutations()
	_test_warm_nested_mutations_and_restore()
	_test_alternating_definitions_and_numeric_edges()
	_test_concurrent_callers()
	_test_uncacheable_extras()
	print("lake definition cache parity: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_required_field_mutations() -> void:
	_check("reference fixture is valid", Reference.is_valid_definition(_base))
	_check("candidate fixture is valid", Lake.is_valid_definition(_base))
	_expect_edit("format StringName keeps reference semantics", "format_string_name")
	# A numeric format already raises an engine diagnostic in the frozen guard;
	# this optimization deliberately preserves that guard, including its limits.
	_expect_edit("id StringName is rejected", "id_string_name", false)
	_expect_edit("id integer is rejected", "id_integer", false)
	_expect_edit("identity StringName is rejected", "identity_string_name", false)
	_expect_edit("identity integer is rejected", "identity_integer", false)
	_expect_edit("water boolean is rejected", "water_boolean", false)
	_expect_edit("water numeric string is rejected", "water_string", false)
	_expect_edit("water int remains valid under the reference predicate", "water_integer", true)
	_expect_edit("shoreline PackedFloat32Array is rejected", "shoreline_float32", false)
	_expect_edit("bank PackedFloat32Array is rejected", "bank_float32", false)
	_expect_edit("profile Dictionary is rejected", "profile_dictionary", false)
	_expect_edit("bounds Array is rejected", "bounds_array", false)
	_expect_edit("waves PackedFloat64Array is rejected", "waves_packed", false)
	_expect_edit("profile row String is rejected", "profile_row_string", false)
	_expect_edit("wave row String is rejected", "wave_row_string", false)
	_expect_edit("bounds boolean scalar is rejected", "bounds_boolean", false)
	_expect_edit("wave boolean scalar is rejected", "wave_boolean", false)

	_expect_number_edit("water NaN is rejected", "water", "", -1, NAN, false)
	_expect_number_edit("water infinity is rejected", "water", "", -1, INF, false)
	_expect_number_edit("shoreline NaN is rejected", "shoreline", "", -1, NAN, false)
	_expect_number_edit("bank infinity is rejected", "bank", "", -1, INF, false)
	_expect_number_edit("profile NaN is rejected", "profile", "depth_m", 1, NAN, false)
	_expect_number_edit("profile infinity is rejected", "profile", "inset_m", 1, INF, false)
	for key: String in ["max_amplitude_m", "min_wavelength_m", "max_wavelength_m",
			"min_period_s", "max_period_s", "shore_fade_m"]:
		_expect_number_edit("bounds NaN %s is rejected" % key, "bounds", key, -1, NAN, false)
		_expect_number_edit("bounds infinity %s is rejected" % key, "bounds", key, -1, INF, false)
	for key: String in ["amplitude_m", "wavelength_m", "period_s", "heading_rad", "phase_rad"]:
		_expect_number_edit("wave NaN %s is rejected" % key, "wave", key, 0, NAN, false)
		_expect_number_edit("wave infinity %s is rejected" % key, "wave", key, 0, INF, false)


func _test_missing_and_shape_mutations() -> void:
	_same("empty dictionary is rejected", {}, false)
	for key: String in ["format", "id", "identity", "water_level_down_m", "shoreline_ne_m",
			"bank_ne_m", "bed_profile", "wave_bounds", "waves"]:
		var missing: Dictionary = _base.duplicate(true)
		missing.erase(key)
		_same("missing required field %s is rejected" % key, missing, false)
	_expect_edit("short shoreline is rejected", "shoreline_short", false)
	_expect_edit("odd shoreline shape is rejected", "shoreline_odd", false)
	_expect_edit("short bank is rejected", "bank_short", false)
	_expect_edit("odd bank shape is rejected", "bank_odd", false)
	_expect_edit("one-point profile is rejected", "profile_short", false)
	_expect_edit("nine-point profile is rejected", "profile_long", false)
	_expect_edit("three waves are rejected", "waves_long", false)
	_expect_edit("profile non-monotonic inset is rejected", "profile_inset_not_monotonic", false)
	_expect_edit("profile non-monotonic depth is rejected", "profile_depth_not_monotonic", false)
	_expect_edit("negative maximum wave amplitude is rejected", "bounds_negative_amplitude", false)
	_expect_edit("reversed wavelength interval is rejected", "bounds_reversed_wavelength", false)
	_expect_edit("zero shore fade is rejected", "bounds_zero_fade", false)


func _test_warm_nested_mutations_and_restore() -> void:
	var warm: Dictionary = _base.duplicate(true)
	_check("warm cache from baseline", Lake.is_valid_definition(warm))
	var identity: String = warm.identity
	var before_profile: Array = warm.bed_profile.duplicate(true)
	warm.bed_profile[1].depth_m = float(warm.bed_profile[1].depth_m) + 0.125
	_same("valid profile edit after warm remains valid", warm, true)
	_check("profile edit leaves identity untouched", warm.identity == identity)
	warm.bed_profile[1].depth_m = NAN
	_same("invalid profile edit after warm is rejected", warm, false)
	warm.bed_profile = before_profile.duplicate(true)
	_same("restored profile after invalid edit is valid", warm, true)
	_check("profile restoration leaves identity untouched", warm.identity == identity)

	var before_bounds: Dictionary = warm.wave_bounds.duplicate(true)
	warm.wave_bounds.shore_fade_m = 0.0
	_same("invalid nested bounds edit after warm is rejected", warm, false)
	warm.wave_bounds = before_bounds.duplicate(true)
	_same("restored nested bounds are valid", warm, true)
	_check("bounds edit leaves identity untouched", warm.identity == identity)

	warm.waves = [_valid_wave()]
	_same("valid wave added after warm remains valid", warm, true)
	var before_waves: Array = warm.waves.duplicate(true)
	warm.waves[0].phase_rad = 2.25
	_same("valid nested wave edit after warm remains valid", warm, true)
	_check("wave edit leaves identity untouched", warm.identity == identity)
	warm.waves[0].phase_rad = INF
	_same("invalid nested wave edit after warm is rejected", warm, false)
	warm.waves = before_waves.duplicate(true)
	_same("restored nested waves are valid", warm, true)
	_check("wave restoration leaves identity untouched", warm.identity == identity)

	var before_shore: PackedFloat64Array = warm.shoreline_ne_m.duplicate()
	var edited_shore: PackedFloat64Array = warm.shoreline_ne_m
	edited_shore[0] += 0.25
	warm.shoreline_ne_m = edited_shore
	_same("valid packed polygon edit after warm remains valid", warm, true)
	_check("polygon edit leaves identity untouched", warm.identity == identity)
	var bad_shore: PackedFloat64Array = warm.shoreline_ne_m
	bad_shore[0] = INF
	warm.shoreline_ne_m = bad_shore
	_same("invalid packed polygon edit after warm is rejected", warm, false)
	warm.shoreline_ne_m = before_shore
	_same("restored packed polygon is valid", warm, true)
	_check("polygon restoration leaves identity untouched", warm.identity == identity)

	var in_place: Dictionary = _base.duplicate(true)
	_check("warm cache before literal in-place polygon edit", Lake.is_valid_definition(in_place))
	in_place.shoreline_ne_m[0] = INF
	_same("literal in-place PackedFloat64Array edit after warm is rejected", in_place, false)
	in_place.shoreline_ne_m[0] = float(_base.shoreline_ne_m[0])
	_same("literal in-place polygon restoration remains valid", in_place, true)


func _test_alternating_definitions_and_numeric_edges() -> void:
	var first: Dictionary = _base.duplicate(true)
	var second: Dictionary = _base.duplicate(true)
	second.water_level_down_m = 1
	_same("alternating definition A", first, true)
	_same("alternating definition B with unchanged identity", second, true)
	_check("alternation does not require identity edits", first.identity == second.identity)
	_same("alternating back to definition A", first, true)

	var signed_zero: Dictionary = _base.duplicate(true)
	signed_zero.bed_profile[0].inset_m = -0.0
	signed_zero.bed_profile[0].depth_m = -0.0
	signed_zero.wave_bounds.max_amplitude_m = -0.0
	_same("negative zero follows reference validator semantics", signed_zero, true)
	_expect_number_edit("negative zero water level remains below minimum", "water", "", -1, -0.0, false)
	_expect_edit("positive zero water level remains below minimum", "water_positive_zero", false)


func _test_concurrent_callers() -> void:
	var worker_count: int = 6
	var iterations_per_worker: int = 8
	var threads: Array[Thread] = []
	var start_failures: int = 0
	for worker_index: int in range(worker_count):
		# Every worker owns a detached input and makes one valid or invalid nested edit.
		var lake: Dictionary = _base.duplicate(true)
		var expected_valid: bool = worker_index % 2 == 0
		if expected_valid:
			lake.bed_profile[1].depth_m = float(lake.bed_profile[1].depth_m) + 0.01 * float(worker_index + 1)
		else:
			lake.wave_bounds.shore_fade_m = 0.0
		var thread: Thread = Thread.new()
		var start_error: int = thread.start(Callable(self, "_thread_validate").bind(
			lake, expected_valid, iterations_per_worker))
		if start_error == OK:
			threads.append(thread)
		else:
			start_failures += 1
	var aggregate_ok: bool = start_failures == 0 and threads.size() == worker_count
	var valid_results: int = 0
	var invalid_results: int = 0
	var details: Array[String] = []
	for worker_index: int in range(threads.size()):
		var result: Dictionary = threads[worker_index].wait_to_finish()
		var worker_ok: bool = bool(result.get("ok", false))
		aggregate_ok = aggregate_ok and worker_ok
		if bool(result.get("expected_valid", false)):
			valid_results += 1
		else:
			invalid_results += 1
		if not worker_ok:
			details.append("worker %d: %s" % [worker_index, result])
	_check("joined concurrent valid/invalid callers match reference (%d valid, %d invalid)" % [
		valid_results, invalid_results], aggregate_ok and valid_results == 3 and invalid_results == 3,
		"start failures=%d %s" % [start_failures, details])


func _test_uncacheable_extras() -> void:
	var cyclic: Dictionary = _base.duplicate(true)
	cyclic["extra_cycle"] = cyclic
	_same("cyclic ignored metadata preserves validation result", cyclic, true)
	_check("cyclic metadata is not retained in the cache", not Lake._definition_cache.has("extra_cycle"))
	cyclic.erase("extra_cycle")
	_same("cycle is broken and definition remains valid", cyclic, true)

	var huge: Dictionary = _base.duplicate(true)
	var huge_text: String = ""
	for index: int in range(2049):
		huge_text += "x"
	huge.extra_metadata = huge_text
	_same("oversized ignored metadata preserves validation result", huge, true)
	_check("oversized metadata is not retained in the cache", not Lake._definition_cache.has("extra_metadata"))

	var too_deep: Dictionary = _base.duplicate(true)
	too_deep.extra_metadata = {"level1": {"level2": {"level3": {"level4": "deep"}}}}
	_same("too-deep ignored metadata preserves validation result", too_deep, true)
	_check("too-deep metadata is not retained in the cache", not Lake._definition_cache.has("extra_metadata"))

	var too_many_items: Dictionary = _base.duplicate(true)
	var metadata_items: Dictionary = {}
	for index: int in range(300):
		metadata_items["item_%d" % index] = index
	too_many_items.extra_metadata = metadata_items
	_same("over-budget ignored metadata preserves validation result", too_many_items, true)
	_check("over-budget metadata is not retained in the cache", not Lake._definition_cache.has("extra_metadata"))

	var with_object: Dictionary = _base.duplicate(true)
	var held_object: Object = RefCounted.new()
	var held_weak: WeakRef = weakref(held_object)
	with_object.extra_object = held_object
	_same("Object ignored metadata preserves validation result", with_object, true)
	_check("Object metadata is not retained in the cache", not Lake._definition_cache.has("extra_object"))
	with_object.erase("extra_object")
	held_object = null
	_check("uncacheable Object is not retained by the successful snapshot", held_weak.get_ref() == null)

	var with_callable: Dictionary = _base.duplicate(true)
	with_callable.extra_callable = Callable(self, "_noop")
	_same("Callable ignored metadata preserves validation result", with_callable, true)
	_check("Callable metadata is not retained in the cache", not Lake._definition_cache.has("extra_callable"))


func _expect_edit(label: String, mutation: String, expected_valid: Variant = null) -> void:
	var changed: Dictionary = _base.duplicate(true)
	# Warm an unrelated successful snapshot before testing the edited input.
	Lake.is_valid_definition(_base)
	_apply_mutation(changed, mutation)
	_same(label, changed, expected_valid)


func _apply_mutation(changed: Dictionary, mutation: String) -> void:
	match mutation:
		"format_string_name": changed.format = StringName("openrc-lake v1")
		"id_string_name": changed.id = StringName(changed.id)
		"id_integer": changed.id = 1
		"identity_string_name": changed.identity = StringName(changed.identity)
		"identity_integer": changed.identity = 1
		"water_boolean": changed.water_level_down_m = true
		"water_string": changed.water_level_down_m = "0.45"
		"water_integer": changed.water_level_down_m = 1
		"water_positive_zero": changed.water_level_down_m = 0.0
		"shoreline_float32": changed.shoreline_ne_m = _to_float32(changed.shoreline_ne_m)
		"bank_float32": changed.bank_ne_m = _to_float32(changed.bank_ne_m)
		"profile_dictionary": changed.bed_profile = {}
		"bounds_array": changed.wave_bounds = []
		"waves_packed": changed.waves = PackedFloat64Array()
		"profile_row_string": changed.bed_profile = ["profile", {"inset_m": 1.0, "depth_m": 1.0}]
		"wave_row_string": changed.waves = ["wave"]
		"bounds_boolean": changed.wave_bounds.max_amplitude_m = false
		"wave_boolean": changed.waves = [_wave_with_boolean_phase()]
		"shoreline_short": changed.shoreline_ne_m = PackedFloat64Array([0.0, 1.0, 2.0, 3.0])
		"shoreline_odd": changed.shoreline_ne_m = PackedFloat64Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
		"bank_short": changed.bank_ne_m = PackedFloat64Array([0.0, 1.0, 2.0, 3.0])
		"bank_odd": changed.bank_ne_m = PackedFloat64Array([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
		"profile_short": changed.bed_profile = [{"inset_m": 0.0, "depth_m": 0.0}]
		"profile_long": changed.bed_profile = _nine_point_profile()
		"waves_long": changed.waves = [_valid_wave(), _valid_wave(), _valid_wave()]
		"profile_inset_not_monotonic": changed.bed_profile[1].inset_m = changed.bed_profile[0].inset_m
		"profile_depth_not_monotonic": changed.bed_profile[1].depth_m = changed.bed_profile[0].depth_m
		"bounds_negative_amplitude": changed.wave_bounds.max_amplitude_m = -0.001
		"bounds_reversed_wavelength": changed.wave_bounds.max_wavelength_m = changed.wave_bounds.min_wavelength_m - 1.0
		"bounds_zero_fade": changed.wave_bounds.shore_fade_m = 0.0


func _expect_number_edit(label: String, section: String, key: String, row_index: int,
		value: float, expected_valid: Variant = null) -> void:
	var changed: Dictionary = _base.duplicate(true)
	Lake.is_valid_definition(_base)
	match section:
		"water":
			changed.water_level_down_m = value
		"shoreline":
			var shoreline: PackedFloat64Array = changed.shoreline_ne_m
			shoreline[0] = value
			changed.shoreline_ne_m = shoreline
		"bank":
			var bank: PackedFloat64Array = changed.bank_ne_m
			bank[0] = value
			changed.bank_ne_m = bank
		"profile":
			changed.bed_profile[row_index][key] = value
		"bounds":
			changed.wave_bounds[key] = value
		"wave":
			changed.waves = [_valid_wave()]
			changed.waves[row_index][key] = value
	_same(label, changed, expected_valid)


func _thread_validate(lake: Dictionary, expected_valid: bool, iterations: int) -> Dictionary:
	var matches: bool = true
	var observed_valid: bool = false
	var reference_valid: bool = false
	for iteration: int in range(iterations):
		reference_valid = Reference.is_valid_definition(lake)
		observed_valid = Lake.is_valid_definition(lake)
		matches = matches and observed_valid == reference_valid and observed_valid == expected_valid
	return {"ok": matches, "expected_valid": expected_valid,
		"candidate_valid": observed_valid, "reference_valid": reference_valid, "iterations": iterations}


func _same(label: String, lake: Dictionary, expected_valid: Variant = null) -> void:
	var reference_valid: bool = Reference.is_valid_definition(lake)
	var candidate_valid: bool = Lake.is_valid_definition(lake)
	var matches: bool = candidate_valid == reference_valid
	if expected_valid != null:
		matches = matches and candidate_valid == bool(expected_valid)
	_check(label, matches, "reference=%s candidate=%s expected=%s" % [reference_valid,
		candidate_valid, expected_valid])


func _valid_wave() -> Dictionary:
	return {"amplitude_m": 0.0, "wavelength_m": 8.0, "period_s": 2.4,
		"heading_rad": 0.3, "phase_rad": 0.2}


func _wave_with_boolean_phase() -> Dictionary:
	var wave: Dictionary = _valid_wave()
	wave.phase_rad = false
	return wave


func _nine_point_profile() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in range(9):
		rows.append({"inset_m": float(index), "depth_m": float(index)})
	return rows


func _to_float32(source: PackedFloat64Array) -> PackedFloat32Array:
	var converted: PackedFloat32Array = []
	for value: float in source:
		converted.append(value)
	return converted


func _noop() -> void:
	pass


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
