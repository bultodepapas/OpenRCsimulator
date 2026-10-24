## Exact reuse, input invalidation, result isolation and bounded retention for launch trim.
## Uses a real Stik model and compares raw solver results with cold and repeated cache calls.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Cache := preload("res://sim/launch_trim_cache.gd")
const CruiseTrim := preload("res://physics/cruise_trim.gd")
const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cache := Cache.new()
	var session := Flight.new()
	session.setup(AIRCRAFT_PATH, AIRCRAFT_ID)
	_check("Stik model prepares", session.is_flyable(), session.start_error)
	if not session.is_flyable():
		session.free()
		_finish()
		return

	var arguments: Array = _stik_arguments(session)
	_check_key_participation(cache, arguments)
	_check_solver_and_cache(cache, arguments)
	session.free()
	_finish()


func _stik_arguments(session: Variant) -> Array:
	# Recompute the launch model and atmosphere at the raw solver boundary, as FlightSession does.
	var model: Dictionary = session._trim_model(session.aircraft.model)
	var speed: float = float(model.get("start_speed", 15.0))
	var target: float = 0.5
	var max_speed: float = minf(CruiseTrim.MAX_SEARCH_SPEED_MPS, 2.5 * speed)
	var throws: Dictionary = model.controls.throw_rad
	var density: float = session._weather.air_density(-30.0)
	var charge: float = session._weather.engine_charge_ratio(-30.0)
	return [speed, target, max_speed, model, session.sim.gravity, throws,
		density, charge, CruiseTrim.DEFAULT_MAX_ALPHA_RAD]


func _check_key_participation(cache: Variant, baseline: Array) -> void:
	var baseline_encoded: Dictionary = cache._encode_arguments(baseline)
	_check("Stik solver arguments are serializable", baseline_encoded.get("ok", false),
		str(baseline_encoded.get("reason", "")))
	if not baseline_encoded.get("ok", false):
		return
	var stable_encoded: Dictionary = cache._encode_arguments(baseline)
	_check("same Stik tuple has exact same key bytes", stable_encoded.get("ok", false)
		and stable_encoded.key == baseline_encoded.key)

	var changed: Array = baseline.duplicate(true)
	changed[0] = float(baseline[0]) + 0.1
	_expect_key_change(cache, "reference speed", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	changed[1] = float(baseline[1]) + 0.001
	_expect_key_change(cache, "target throttle", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	changed[2] = float(baseline[2]) + 0.1
	_expect_key_change(cache, "maximum speed", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	var mass_model: Dictionary = baseline[3].duplicate(true)
	mass_model["mass_kg"] = float(mass_model.get("mass_kg", 0.0)) * 1.001
	_expect_key_change(cache, "model mass", baseline_encoded.key, _replace_argument(changed, 3, mass_model))
	changed = baseline.duplicate(true)
	var full_model: Dictionary = baseline[3].duplicate(true)
	full_model["cache_probe_model_field"] = "part of the complete model tuple"
	_expect_key_change(cache, "full model data", baseline_encoded.key, _replace_argument(changed, 3, full_model))
	changed = baseline.duplicate(true)
	changed[4] = float(baseline[4]) + 0.0001
	_expect_key_change(cache, "gravity", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	var changed_throws: Dictionary = baseline[5].duplicate(true)
	changed_throws["elevator"] = float(changed_throws.elevator) * 1.001
	_expect_key_change(cache, "control throws", baseline_encoded.key, _replace_argument(changed, 5, changed_throws))
	changed = baseline.duplicate(true)
	changed[6] = float(baseline[6]) * 1.001
	_expect_key_change(cache, "density", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	changed[7] = float(baseline[7]) + 0.001
	_expect_key_change(cache, "engine charge", baseline_encoded.key, changed)
	changed = baseline.duplicate(true)
	changed[8] = float(baseline[8]) + 0.001
	_expect_key_change(cache, "maximum alpha", baseline_encoded.key, changed)


func _replace_argument(arguments: Array, index: int, replacement: Variant) -> Array:
	arguments[index] = replacement
	return arguments


func _expect_key_change(cache: Variant, label: String, baseline_key: PackedByteArray,
		arguments: Array) -> void:
	var encoded: Dictionary = cache._encode_arguments(arguments)
	_check(label + " changes the same baseline key",
		encoded.get("ok", false) and encoded.key != baseline_key,
		str(encoded.get("reason", "")))


func _check_solver_and_cache(cache: Variant, arguments: Array) -> void:
	var raw: Dictionary = _call_solver(arguments)
	_check("raw Stik solver succeeds", raw.get("ok", false), str(raw.get("message", "")))
	if not raw.get("ok", false):
		return
	var raw_bytes: PackedByteArray = var_to_bytes(raw)

	var cold: Dictionary = _call_cache(cache, arguments)
	_check("cold Stik result equals raw result byte-for-byte", var_to_bytes(cold) == raw_bytes)
	var after_cold: Dictionary = cache.stats()
	_check("first call is a miss and retains one of two bounded keys",
		after_cold.misses == 1 and after_cold.hits == 0 and after_cold.has_entry
			and after_cold.entries == 1 and after_cold.entry_limit == 2
			and after_cold.retained_key_bytes <= after_cold.retained_key_limit_bytes)
	var retained_base_key_bytes: int = int(after_cold.retained_key_bytes)

	var exposed_state: PackedFloat64Array = cold.state
	exposed_state[0] += 123.0
	cold.state = exposed_state
	cold["cache_probe_mutation"] = true
	_check("caller can mutate its cold result", var_to_bytes(cold) != raw_bytes)
	var first_hit: Dictionary = _call_cache(cache, arguments)
	_check("hit is unpoisoned and equals raw result", var_to_bytes(first_hit) == raw_bytes
		and not first_hit.has("cache_probe_mutation"))
	var hit_state: PackedFloat64Array = first_hit.state
	hit_state[0] -= 234.0
	first_hit.state = hit_state
	first_hit["cache_probe_hit_mutation"] = true
	var second_hit: Dictionary = _call_cache(cache, arguments)
	_check("mutating a hit cannot poison the stored result", var_to_bytes(second_hit) == raw_bytes
		and not second_hit.has("cache_probe_hit_mutation"))
	_check("repeated calls register as hits", cache.stats().hits == 2)

	# Invalid requests must be recomputed, must not replace the successful entry, and must not become hits.
	var invalid: Array = arguments.duplicate(true)
	invalid[1] = -1.0
	var misses_before_invalid: int = int(cache.stats().misses)
	var first_failure: Dictionary = _call_cache(cache, invalid)
	var second_failure: Dictionary = _call_cache(cache, invalid)
	_check("invalid solver requests remain failures", not first_failure.get("ok", true)
		and not second_failure.get("ok", true))
	_check("failures are not cached", cache.stats().misses == misses_before_invalid + 2
		and cache.stats().hits == 2)
	var restored_base: Dictionary = _call_cache(cache, arguments)
	_check("uncached failures preserve the successful entry", var_to_bytes(restored_base) == raw_bytes
		and cache.stats().hits == 3)

	# Unsafe values and oversized exact keys use the solver path without consuming or replacing the entry.
	var unsafe: Array = arguments.duplicate(true)
	var unsafe_model: Dictionary = arguments[3].duplicate(true)
	unsafe_model["cache_probe_object"] = self
	unsafe[3] = unsafe_model
	unsafe[1] = -1.0 # Keep fallback solver work bounded while still testing its failure result.
	var bypasses_before: int = int(cache.stats().bypasses)
	var misses_before_bypass: int = int(cache.stats().misses)
	_check("Object-bearing input falls through to solver", not _call_cache(cache, unsafe).get("ok", true))
	_check("unsafe values bypass without replacing the entry",
		cache.stats().bypasses == bypasses_before + 1
		and cache.stats().misses == misses_before_bypass
		and cache.stats().retained_key_bytes == retained_base_key_bytes)

	var oversized: Array = arguments.duplicate(true)
	var oversized_model: Dictionary = arguments[3].duplicate(true)
	var payload := PackedByteArray()
	payload.resize(int(cache.MAX_RETAINED_KEY_BYTES) + 1)
	oversized_model["cache_probe_payload"] = payload
	oversized[3] = oversized_model
	var oversized_key: Dictionary = cache._encode_arguments(oversized)
	_check("oversized fixture exceeds the retained-key cap",
		oversized_key.get("ok", false)
		and oversized_key.key.size() > int(cache.MAX_RETAINED_KEY_BYTES))
	var misses_before_oversized: int = int(cache.stats().misses)
	var oversized_result: Dictionary = _call_cache(cache, oversized)
	_check("oversized successful input still follows the raw solver",
		oversized_result.get("ok", false) and var_to_bytes(oversized_result) == raw_bytes)
	_check("oversized key bypasses retention without replacing the base entry",
		cache.stats().bypasses == bypasses_before + 2
		and cache.stats().misses == misses_before_oversized
		and cache.stats().retained_key_bytes == retained_base_key_bytes)
	var base_after_bypasses: Dictionary = _call_cache(cache, arguments)
	_check("base entry still hits after both bypasses", var_to_bytes(base_after_bypasses) == raw_bytes
		and cache.stats().hits == 4)

	# Alter an unused model identity field: raw trim stays successful, while the exact complete tuple gets a second entry.
	var replacement: Array = arguments.duplicate(true)
	var replacement_model: Dictionary = arguments[3].duplicate(true)
	replacement_model["id"] = str(replacement_model.get("id", AIRCRAFT_ID)) + "-cache-replacement"
	replacement[3] = replacement_model
	var replacement_raw: Dictionary = _call_solver(replacement)
	_check("replacement Stik input remains a successful raw solve", replacement_raw.get("ok", false),
		str(replacement_raw.get("message", "")))
	if replacement_raw.get("ok", false):
		var misses_before_replacement: int = int(cache.stats().misses)
		var replacement_cold: Dictionary = _call_cache(cache, replacement)
		_check("different full-model tuple is a successful cold miss",
			var_to_bytes(replacement_cold) == var_to_bytes(replacement_raw)
			and cache.stats().misses == misses_before_replacement + 1
			and cache.stats().entries == 2 and cache.stats().entry_limit == 2)
		var replacement_hit: Dictionary = _call_cache(cache, replacement)
		_check("replacement tuple hits its exact retained entry",
			var_to_bytes(replacement_hit) == var_to_bytes(replacement_raw)
			and cache.stats().hits == 5)
		var misses_before_base_again: int = int(cache.stats().misses)
		var base_again: Dictionary = _call_cache(cache, arguments)
		_check("two-entry cache still hits the original exact tuple",
			var_to_bytes(base_again) == raw_bytes
			and cache.stats().misses == misses_before_base_again
			and cache.stats().hits == 6 and cache.stats().entries == 2)

		# A failure cannot replace or evict either successful entry.
		var two_entry_invalid: Array = arguments.duplicate(true)
		two_entry_invalid[1] = -1.0
		var misses_before_two_entry_failure: int = int(cache.stats().misses)
		var hits_before_two_entry_failure: int = int(cache.stats().hits)
		var invalid_a: Dictionary = _call_cache(cache, two_entry_invalid)
		var invalid_b: Dictionary = _call_cache(cache, two_entry_invalid)
		_check("two-entry failures are recomputed and not cached",
			not invalid_a.get("ok", true) and not invalid_b.get("ok", true)
			and cache.stats().misses == misses_before_two_entry_failure + 2
			and cache.stats().hits == hits_before_two_entry_failure
			and cache.stats().entries == 2)
		var base_after_failures: Dictionary = _call_cache(cache, arguments)
		var replacement_after_failures: Dictionary = _call_cache(cache, replacement)
		_check("failures preserve both successful deep-copied entries",
			var_to_bytes(base_after_failures) == raw_bytes
			and var_to_bytes(replacement_after_failures) == var_to_bytes(replacement_raw)
			and cache.stats().entries == 2)
		# Make A most recently used and B least recently used before adding C.
		var base_lru_touch: Dictionary = _call_cache(cache, arguments)
		_check("exact A hit refreshes LRU order", var_to_bytes(base_lru_touch) == raw_bytes)

		var third: Array = arguments.duplicate(true)
		var third_model: Dictionary = arguments[3].duplicate(true)
		third_model["id"] = str(third_model.get("id", AIRCRAFT_ID)) + "-cache-third"
		third[3] = third_model
		var third_raw: Dictionary = _call_solver(third)
		_check("third distinct full-model tuple is a successful raw solve", third_raw.get("ok", false),
			str(third_raw.get("message", "")))
		if third_raw.get("ok", false):
			var misses_before_third: int = int(cache.stats().misses)
			var third_cold: Dictionary = _call_cache(cache, third)
			_check("third tuple inserts while retention remains exactly bounded at two",
				var_to_bytes(third_cold) == var_to_bytes(third_raw)
				and cache.stats().misses == misses_before_third + 1
				and cache.stats().entries == 2 and cache.stats().entry_limit == 2
				and cache.stats().retained_key_bytes <= cache.stats().retained_key_limit_bytes)
		var hits_before_base_after_third: int = int(cache.stats().hits)
		var misses_before_base_after_third: int = int(cache.stats().misses)
		var base_after_third: Dictionary = _call_cache(cache, arguments)
		_check("LRU eviction keeps recently used A after C inserts",
			var_to_bytes(base_after_third) == raw_bytes
			and cache.stats().hits == hits_before_base_after_third + 1
			and cache.stats().misses == misses_before_base_after_third)
		var misses_before_evicted: int = int(cache.stats().misses)
		var replacement_after_eviction: Dictionary = _call_cache(cache, replacement)
		_check("least-recently-used B is evicted and exact reuse becomes a miss",
			var_to_bytes(replacement_after_eviction) == var_to_bytes(replacement_raw)
			and cache.stats().misses == misses_before_evicted + 1
			and cache.stats().entries == 2)
	var final_stats: Dictionary = cache.stats()
	_check("retention remains two-entry and aggregate-byte bounded", final_stats.has_entry
		and final_stats.entries <= final_stats.entry_limit and final_stats.entry_limit == 2
		and final_stats.retained_key_bytes <= final_stats.retained_key_limit_bytes)
	cache.clear()
	var cleared_stats: Dictionary = cache.stats()
	_check("clear invalidates both entries and resets cache statistics",
		not cleared_stats.has_entry and cleared_stats.entries == 0
		and cleared_stats.retained_key_bytes == 0 and cleared_stats.hits == 0
		and cleared_stats.misses == 0 and cleared_stats.bypasses == 0)
	var after_clear: Dictionary = _call_cache(cache, arguments)
	_check("exact tuple after clear is a cold miss again",
		var_to_bytes(after_clear) == raw_bytes and cache.stats().misses == 1
		and cache.stats().hits == 0 and cache.stats().entries == 1)
	_check_aggregate_key_byte_budget(arguments)
	print("Stik trim-cache fixture: %d checks, %d failures; stats=%s" % [
		checks, failures, str(cache.stats())])


func _check_aggregate_key_byte_budget(arguments: Array) -> void:
	var cache := Cache.new()
	var payload_size: int = int(cache.MAX_RETAINED_KEY_BYTES * 0.6)
	var padded_a: Array = arguments.duplicate(true)
	var model_a: Dictionary = arguments[3].duplicate(true)
	var payload_a := PackedByteArray()
	payload_a.resize(payload_size)
	model_a["cache_probe_payload"] = payload_a
	model_a["cache_probe_id"] = "aggregate-budget-a"
	padded_a[3] = model_a
	var padded_b: Array = arguments.duplicate(true)
	var model_b: Dictionary = arguments[3].duplicate(true)
	var payload_b := PackedByteArray()
	payload_b.resize(payload_size)
	model_b["cache_probe_payload"] = payload_b
	model_b["cache_probe_id"] = "aggregate-budget-b"
	padded_b[3] = model_b
	var encoded_a: Dictionary = cache._encode_arguments(padded_a)
	var encoded_b: Dictionary = cache._encode_arguments(padded_b)
	var key_a: PackedByteArray = encoded_a.key if encoded_a.get("ok", false) else PackedByteArray()
	var key_b: PackedByteArray = encoded_b.key if encoded_b.get("ok", false) else PackedByteArray()
	_check("two individually admissible exact keys exceed the aggregate byte budget",
		encoded_a.get("ok", false) and encoded_b.get("ok", false)
		and key_a.size() <= cache.MAX_RETAINED_KEY_BYTES
		and key_b.size() <= cache.MAX_RETAINED_KEY_BYTES
		and key_a.size() + key_b.size() > cache.MAX_RETAINED_KEY_BYTES,
		"key bytes=%d+%d cap=%d" % [key_a.size(), key_b.size(), cache.MAX_RETAINED_KEY_BYTES])
	var result_a: Dictionary = _call_cache(cache, padded_a)
	var result_b: Dictionary = _call_cache(cache, padded_b)
	_check("byte-budget insertion retains only the newest key after aggregate overflow",
		result_a.get("ok", false) and result_b.get("ok", false)
		and cache.stats().entries == 1 and cache.stats().entry_limit == 2
		and cache.stats().retained_key_bytes == key_b.size()
		and cache.stats().retained_key_bytes <= cache.stats().retained_key_limit_bytes)
	var hits_before_b: int = int(cache.stats().hits)
	var cached_b: Dictionary = _call_cache(cache, padded_b)
	_check("aggregate-byte eviction keeps the newest exact key reusable",
		var_to_bytes(cached_b) == var_to_bytes(result_b)
		and cache.stats().hits == hits_before_b + 1)
	var misses_before_a: int = int(cache.stats().misses)
	var recomputed_a: Dictionary = _call_cache(cache, padded_a)
	_check("aggregate-byte cap evicts the older admissible key",
		var_to_bytes(recomputed_a) == var_to_bytes(result_a)
		and cache.stats().misses == misses_before_a + 1
		and cache.stats().entries == 1
		and cache.stats().retained_key_bytes == key_a.size())


func _call_solver(arguments: Array) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(float(arguments[0]), float(arguments[1]),
		float(arguments[2]), arguments[3], float(arguments[4]), arguments[5],
		float(arguments[6]), float(arguments[7]), float(arguments[8]))


func _call_cache(cache: Variant, arguments: Array) -> Dictionary:
	return cache.solve_level_at_throttle(float(arguments[0]), float(arguments[1]),
		float(arguments[2]), arguments[3], float(arguments[4]), arguments[5],
		float(arguments[6]), float(arguments[7]), float(arguments[8]))


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		return
	failures += 1
	push_error("FAIL: " + label + (" — " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	print("Stik trim-cache fixture complete: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
