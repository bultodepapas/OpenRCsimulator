extends SceneTree

## EM-29/EM-30: per-type selection, severity, onset window and the v3 mechanisms.

const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FailureRuntime := preload("res://failures/runtime.gd")

const DT := 1.0 / 240.0
const LOGICAL := "logical-controls-v1"
const GLOW := "finite-glow-v1"
const ELECTRIC := "electric-drive-v1"
const SCALED_BANDS := {
	"roll_bias": ["bias", "bias"], "pitch_bias": ["bias", "bias"], "yaw_bias": ["bias", "bias"],
	"roll_slow": ["rate_factor", "rate_factor"], "pitch_slow": ["rate_factor", "rate_factor"],
	"yaw_slow": ["rate_factor", "rate_factor"],
	"roll_travel_limit": ["travel_limit", "limit"], "pitch_travel_limit": ["travel_limit", "limit"],
	"yaw_travel_limit": ["travel_limit", "limit"],
	"throttle_limit": ["throttle_ceiling", "maximum_demand"],
	"throttle_stuck": ["throttle_high", "high_demand"],
	"throttle_stuck_low": ["throttle_low", "low_demand"],
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_config_contract()
	_test_catalog_contract()
	_test_v3_plan_and_exclusions()
	_test_severity_bands()
	_test_onset_windows()
	_test_historical_formats_refuse_new_settings()
	_test_new_mechanisms()
	_test_restore_and_identity()
	print("Failure selection contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _test_config_contract() -> void:
	var defaults: Dictionary = FailureConfig.defaults()
	_check("defaults add standard severity, standard onset and no exclusions",
		defaults.severity == "standard" and defaults.onset == "standard" and defaults.excluded_ids == [], defaults)
	_check("defaults use the default selection", FailureConfig.uses_default_selection(defaults))
	var legacy: Dictionary = FailureConfig.validate({"probability_percent": 30, "include_catastrophic": true, "notify": false})
	_check("legacy three-key request upgrades explicitly", legacy.ok and legacy.config.size() == 6
		and legacy.config.probability_percent == 30 and legacy.config.severity == "standard", legacy)
	var full := _config(40, false, true, "severe", "late", ["yaw_jam", "pitch_bias"])
	var checked: Dictionary = FailureConfig.validate(full)
	_check("full request validates", checked.ok, checked)
	_check("exclusions are returned in stable sorted order", checked.ok and checked.config.excluded_ids == ["pitch_bias", "yaw_jam"], checked)
	_check("customized request is not the default selection", checked.ok and not FailureConfig.uses_default_selection(checked.config))
	var packed := _config(40, false, true, "mild", "early", PackedStringArray(["radio_loss"]))
	_check("packed string exclusions validate", FailureConfig.validate(packed).ok)
	for bad: Dictionary in [
		_config(40, false, true, "extreme", "standard", []),
		_config(40, false, true, "standard", "never", []),
		_config(40, false, true, 2, "standard", []),
		_config(40, false, true, "standard", "standard", ["no_such_failure"]),
		_config(40, false, true, "standard", "standard", ["roll_jam", "roll_jam"]),
		_config(40, false, true, "standard", "standard", [3]),
		_config(40, false, true, "standard", "standard", "roll_jam"),
	]:
		_check("invalid request is refused: " + JSON.stringify(bad), not FailureConfig.validate(bad).ok)
	var partial := {"probability_percent": 1, "include_catastrophic": false, "notify": true, "severity": "mild"}
	_check("partial new-shape request is refused, not upgraded", not FailureConfig.validate(partial).ok)
	var extra: Dictionary = FailureConfig.defaults()
	extra["max_failures"] = 2
	_check("unknown key is refused", not FailureConfig.validate(extra).ok)


func _test_catalog_contract() -> void:
	_check("frozen v1/v2 ordinary list is unchanged", FailureCatalog.ORDINARY_IDS == [
		"roll_jam", "pitch_jam", "yaw_jam", "roll_bias", "pitch_bias", "roll_slow",
		"throttle_limit", "throttle_stuck",
	])
	var grouped: Array[String] = []
	for group: Dictionary in FailureCatalog.GROUPS:
		_check("group %s has a title" % group.id, not str(group.title).is_empty())
		for failure_id: Variant in group.ids:
			grouped.append(str(failure_id))
	var known_sorted := FailureCatalog.KNOWN_IDS.duplicate()
	known_sorted.sort()
	var grouped_sorted := grouped.duplicate()
	grouped_sorted.sort()
	_check("every known failure appears exactly once in the player groups", grouped_sorted == known_sorted, grouped)
	for failure_id: String in FailureCatalog.KNOWN_IDS:
		var definition: Dictionary = FailureCatalog.definition(failure_id)
		_check(failure_id + " has name, label, hint and source", not str(definition.get("name", "")).is_empty()
			and not str(definition.get("label", "")).is_empty() and not str(definition.get("hint", "")).is_empty()
			and not str(definition.get("source_label", "")).is_empty(), definition)
		_check(failure_id + " declares whether severity scales it",
			typeof(definition.get("scaled_by_severity")) == TYPE_BOOL
			and bool(definition.scaled_by_severity) == SCALED_BANDS.has(failure_id), definition)
	for profile: String in FailureCatalog.PROFILES:
		var v2_ids: Array[String] = FailureCatalog.failure_ids(true, profile)
		var v3_ids: Array[String] = FailureCatalog.failure_ids_v3(true, profile)
		_check(profile + " v3 pool starts with the v2 pool order", v3_ids.slice(0, FailureCatalog.ORDINARY_IDS.size()) == FailureCatalog.ORDINARY_IDS)
		for failure_id: String in v2_ids:
			_check(profile + " v3 keeps v2 event " + failure_id, v3_ids.has(failure_id))
	_check("unknown profile has no v3 pool", FailureCatalog.failure_ids_v3(true, "future-profile-v9").is_empty())
	var elevon_model := {"controls": {"layout": "elevon"}}
	_check("elevon layout lacks every rudder-axis type", FailureCatalog.unsupported_ids(elevon_model) == FailureCatalog.YAW_AXIS_IDS)
	_check("conventional layout lacks nothing", FailureCatalog.unsupported_ids({"controls": {}}).is_empty()
		and FailureCatalog.unsupported_ids({}).is_empty())
	var player := _config(100, false, true, "standard", "standard", ["roll_jam", "yaw_slow"])
	var request: Dictionary = FailureCatalog.request_for_model(FailureConfig.validate(player).config, elevon_model)
	_check("elevon request merges missing axes without duplicates, sorted",
		request.excluded_ids == ["roll_jam", "yaw_bias", "yaw_jam", "yaw_slow", "yaw_travel_limit"], request)
	_check("merged request is still a valid failure request", FailureConfig.validate(request).ok)
	for seed in 1500:
		var runtime := FailureRuntime.new()
		runtime.begin(request, seed, DT, ELECTRIC)
		if FailureCatalog.YAW_AXIS_IDS.has(str(runtime.plan().id)):
			_check("an elevon request never draws a rudder failure", false, runtime.plan())
			break
	_check("glow-only event stays out of the electric pool", not FailureCatalog.failure_ids_v3(true, ELECTRIC).has("glow_fuel_cut"))


func _test_v3_plan_and_exclusions() -> void:
	for profile: String in FailureCatalog.PROFILES:
		var pool: Array[String] = FailureCatalog.failure_ids_v3(true, profile)
		var seen: Dictionary = {}
		var counts: Dictionary = {}
		var samples := 6000
		for seed in samples:
			var runtime := FailureRuntime.new()
			if not runtime.begin(_config(100, true, true), seed, DT, profile):
				_check(profile + " plan resolves", false, runtime.last_error)
				break
			var plan: Dictionary = runtime.plan()
			seen[str(plan.id)] = true
			counts[str(plan.id)] = int(counts.get(str(plan.id), 0)) + 1
			if seed == 0:
				_check(profile + " writes v3 format and catalog", plan.format == FailureRuntime.PLAN_FORMAT_V3
					and int(plan.catalog_version) == FailureCatalog.VERSION, plan)
		_check(profile + " reaches every v3 event", seen.size() == pool.size(), seen.keys())
		# Uniform selection: each count within ±35 % of the expected mean is a loose screen, not a fit.
		var expected := float(samples) / float(pool.size())
		for failure_id: String in pool:
			var count := int(counts.get(failure_id, 0))
			_check("%s %s selection is roughly uniform" % [profile, failure_id],
				absf(float(count) - expected) <= 0.35 * expected, {"count": count, "expected": expected})

	var excluded: Array[String] = ["roll_jam", "throttle_stuck", "radio_loss", "glow_fuel_cut", "pitch_slow"]
	for seed in 3000:
		var runtime := FailureRuntime.new()
		runtime.begin(_config(100, true, true, "standard", "standard", excluded), seed, DT, GLOW)
		if excluded.has(str(runtime.plan().id)):
			_check("excluded failure is never selected", false, runtime.plan())
			break
	var only_one: Array[String] = []
	for failure_id: String in FailureCatalog.KNOWN_IDS:
		if failure_id != "throttle_stuck_low":
			only_one.append(failure_id)
	for seed in 200:
		var runtime := FailureRuntime.new()
		if not runtime.begin(_config(100, false, true, "standard", "standard", only_one), seed, DT, LOGICAL) \
				or str(runtime.plan().id) != "throttle_stuck_low":
			_check("a single remaining type is always selected at 100 percent", false, runtime.plan())
			break
	var everything: Array[String] = FailureCatalog.KNOWN_IDS.duplicate()
	var empty_pool := FailureRuntime.new()
	_check("an empty eligible pool refuses the flight with a readable reason",
		not empty_pool.begin(_config(1, true, true, "standard", "standard", everything), 7, DT, LOGICAL)
		and empty_pool.last_error == FailureRuntime.NO_ELIGIBLE_MESSAGE, empty_pool.last_error)
	_check("refused begin leaves no plan", empty_pool.plan().is_empty())
	var healthy := FailureRuntime.new()
	var healthy_seed := -1
	for seed in 400:
		if healthy.begin(_config(10, false, true), seed, DT, LOGICAL) and not bool(healthy.plan().selected):
			healthy_seed = seed
			break
	_check("a configured healthy draw reports itself as enabled for the debrief",
		healthy_seed >= 0 and bool(healthy.status().get("enabled", false)) and not bool(healthy.status().selected), healthy.status())
	var off := FailureRuntime.new()
	_check("zero probability with an empty pool is a valid healthy plan",
		off.begin(_config(0, true, true, "standard", "standard", everything), 7, DT, LOGICAL)
		and not bool(off.plan().selected))
	var glow_only: Array[String] = []
	for failure_id: String in FailureCatalog.KNOWN_IDS:
		if failure_id != "glow_fuel_cut":
			glow_only.append(failure_id)
	var electric_with_glow_only := FailureRuntime.new()
	_check("a type unsupported by this aircraft does not make its pool non-empty",
		not electric_with_glow_only.begin(_config(50, false, true, "standard", "standard", glow_only), 7, DT, ELECTRIC))
	var catastrophic_only: Array[String] = []
	for failure_id: String in FailureCatalog.KNOWN_IDS:
		if failure_id != "radio_loss":
			catastrophic_only.append(failure_id)
	var gated := FailureRuntime.new()
	_check("catastrophic types stay gated by the catastrophic setting",
		not gated.begin(_config(100, false, true, "standard", "standard", catastrophic_only), 7, DT, LOGICAL))


func _test_severity_bands() -> void:
	for severity: String in FailureConfig.SEVERITIES:
		var seen: Dictionary = {}
		for seed in 4000:
			var runtime := FailureRuntime.new()
			runtime.begin(_config(100, false, true, severity, "standard", []), seed, DT, LOGICAL)
			var plan: Dictionary = runtime.plan()
			var failure_id := str(plan.id)
			if not SCALED_BANDS.has(failure_id):
				continue
			seen[failure_id] = true
			var band: Array = FailureRuntime.SEVERITY_BANDS[SCALED_BANDS[failure_id][0]][severity]
			var value := absf(float(plan.parameters[SCALED_BANDS[failure_id][1]]))
			if value < float(band[0]) / 100.0 - 1e-12 or value > float(band[1]) / 100.0 + 1e-12:
				_check("%s %s parameter stays in its band" % [severity, failure_id], false, {"value": value, "band": band})
		_check(severity + " exercises every scaled mechanism", seen.size() == SCALED_BANDS.size(), seen.keys())
	_check("standard bands reproduce the v1/v2 ranges",
		FailureRuntime.SEVERITY_BANDS.bias.standard == [8, 18]
		and FailureRuntime.SEVERITY_BANDS.rate_factor.standard == [25, 50]
		and FailureRuntime.SEVERITY_BANDS.throttle_ceiling.standard == [45, 70]
		and FailureRuntime.SEVERITY_BANDS.throttle_high.standard == [70, 90])
	for band_name: String in FailureRuntime.SEVERITY_BANDS:
		var bands: Dictionary = FailureRuntime.SEVERITY_BANDS[band_name]
		for severity: String in FailureConfig.SEVERITIES:
			var band: Array = bands[severity]
			_check("%s %s band is ordered within 0..100" % [band_name, severity],
				int(band[0]) >= 0 and int(band[0]) <= int(band[1]) and int(band[1]) <= 100, band)
	# Standard v3 parameters use the same draws as v2 for a shared event.
	for seed in 400:
		var v2 := FailureRuntime.new()
		var v3 := FailureRuntime.new()
		v2.begin(_config(100, false, true), seed, DT, LOGICAL, FailureRuntime.PLAN_FORMAT_V2)
		v3.begin(_config(100, false, true), seed, DT, LOGICAL)
		if str(v2.plan().id) == str(v3.plan().id) and v2.plan().parameters != v3.plan().parameters:
			_check("same event and seed resolve the same standard parameters", false, [v2.plan(), v3.plan()])
			break


func _test_onset_windows() -> void:
	for onset: String in FailureConfig.ONSET_WINDOWS:
		var window: Array = FailureConfig.onset_window(onset)
		var low_seen := 9999
		var high_seen := -1
		for seed in 3000:
			var runtime := FailureRuntime.new()
			runtime.begin(_config(100, false, true, "standard", onset, []), seed, DT, LOGICAL)
			var plan: Dictionary = runtime.plan()
			var seconds := int(plan.onset_airborne_seconds)
			var ticks := int(plan.onset_airborne_ticks)
			low_seen = mini(low_seen, seconds)
			high_seen = maxi(high_seen, seconds)
			if seconds < int(window[0]) or seconds > int(window[1]) \
					or ticks < int(ceili(float(window[0]) / DT)) or ticks > int(floor(float(window[1]) / DT)):
				_check(onset + " onset stays inside its window", false, plan)
				break
		_check(onset + " onset reaches both window edges", low_seen == int(window[0]) and high_seen == int(window[1]),
			[low_seen, high_seen, window])
	_check("standard onset keeps the 20–120 s window", FailureConfig.onset_window("standard") == [20, 120])


func _test_historical_formats_refuse_new_settings() -> void:
	var custom := _config(100, false, true, "severe", "standard", [])
	_check("v1 refuses a severity it cannot express", not FailureRuntime.new().begin(custom, 3, DT))
	_check("v2 refuses an exclusion it cannot express", not FailureRuntime.new().begin(
		_config(100, false, true, "standard", "standard", ["roll_jam"]), 3, DT, LOGICAL, FailureRuntime.PLAN_FORMAT_V2))
	_check("v2 refuses an onset window it cannot express", not FailureRuntime.new().begin(
		_config(100, false, true, "standard", "late", []), 3, DT, LOGICAL, FailureRuntime.PLAN_FORMAT_V2))
	_check("v2 needs a profile", not FailureRuntime.new().begin(_config(100, false, true), 3, DT, "", FailureRuntime.PLAN_FORMAT_V2))
	_check("unknown plan format is refused", not FailureRuntime.new().begin(_config(100, false, true), 3, DT, LOGICAL, "openrc-failure-plan v9"))
	var v1 := FailureRuntime.new()
	_check("v1 still writes the three-key config", v1.begin(_config(100, false, true), 1751, DT)
		and v1.plan().config.size() == 3 and str(v1.plan().id) == "roll_jam", v1.plan())


func _test_new_mechanisms() -> void:
	var inputs := PackedFloat64Array([0.2, -0.3, 0.4, 0.6])
	var servo := PackedFloat64Array([0.0, 0.1, -0.2, 0.3])
	for slow: String in ["pitch_slow", "yaw_slow"]:
		var runtime := _active_runtime(slow, inputs, servo)
		if runtime == null:
			continue
		var axis := 1 if slow == "pitch_slow" else 2
		var factor := float(runtime.plan().parameters.rate_factor)
		for other in 3:
			var expected := factor if other == axis else 1.0
			_check("%s scales only its own servo rate (axis %d)" % [slow, other], runtime.servo_rate_factor(other) == expected)
			_check("%s leaves commands unchanged (axis %d)" % [slow, other], runtime.effective_axis(other, inputs[other]) == inputs[other])
		_check(slow + " snapshot restores", _round_trips(runtime))

	var bias_runtime := _active_runtime("yaw_bias", inputs, servo)
	if bias_runtime != null:
		var bias := float(bias_runtime.plan().parameters.bias)
		_check("yaw bias offsets only the rudder command", bias_runtime.effective_axis(2, 0.1) == clampf(0.1 + bias, -1.0, 1.0)
			and bias_runtime.effective_axis(0, 0.1) == 0.1 and bias_runtime.effective_axis(1, 0.1) == 0.1)
		_check("yaw bias saturates at full deflection", bias_runtime.effective_axis(2, signf(bias)) == signf(bias))
		_check("opposite rudder trim cancels yaw bias", absf(bias_runtime.effective_axis(2, -bias)) < 1e-12)
		_check("yaw bias snapshot restores", _round_trips(bias_runtime))

	for travel: String in ["roll_travel_limit", "pitch_travel_limit", "yaw_travel_limit"]:
		var runtime := _active_runtime(travel, inputs, servo)
		if runtime == null:
			continue
		var axis := int(runtime.plan().parameters.axis)
		var limit := float(runtime.plan().parameters.limit)
		_check(travel + " maps its own axis", axis == ["roll_travel_limit", "pitch_travel_limit", "yaw_travel_limit"].find(travel))
		_check(travel + " clamps full positive command", runtime.effective_axis(axis, 1.0) == limit)
		_check(travel + " clamps full negative command", runtime.effective_axis(axis, -1.0) == -limit)
		_check(travel + " passes small commands", runtime.effective_axis(axis, limit * 0.5) == limit * 0.5)
		_check(travel + " keeps servo rate", runtime.servo_rate_factor(axis) == 1.0)
		for other in 3:
			if other != axis:
				_check("%s leaves axis %d unrestricted" % [travel, other], runtime.effective_axis(other, 1.0) == 1.0)
		_check(travel + " snapshot restores", _round_trips(runtime))

	var high_demand := PackedFloat64Array([0.0, 0.0, 0.0, 0.9])
	var low_runtime := _active_runtime("throttle_stuck_low", high_demand, servo)
	if low_runtime != null:
		var low := float(low_runtime.plan().parameters.low_demand)
		_check("stuck-low throttle captures the resolved low demand from a high setting",
			low_runtime.effective_throttle(1.0) == low and low_runtime.effective_throttle(0.0) == low)
		_check("stuck-low snapshot restores", _round_trips(low_runtime))
	var idle := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var idle_runtime := _active_runtime("throttle_stuck_low", idle, servo)
	if idle_runtime != null:
		_check("stuck-low throttle keeps an already lower demand", idle_runtime.effective_throttle(1.0) == 0.0)
		_check("stuck-low at idle snapshot restores", _round_trips(idle_runtime))
	var corrupt_source := _active_runtime("throttle_stuck_low", high_demand, servo)
	if corrupt_source != null:
		var corrupt: Dictionary = corrupt_source.snapshot()
		corrupt.held_inputs[3] = 0.95
		corrupt.last_inputs[3] = 0.95
		_check("stuck-low snapshot above its ceiling is refused", not FailureRuntime.new().can_restore(corrupt, int(corrupt.tick)))


func _test_restore_and_identity() -> void:
	var notices_on := FailureRuntime.new()
	var notices_off := FailureRuntime.new()
	notices_on.begin(_config(100, false, true, "severe", "late", ["roll_jam"]), 99, DT, GLOW)
	notices_off.begin(_config(100, false, false, "severe", "late", ["roll_jam"]), 99, DT, GLOW)
	_check("notices do not change v3 physical identity", str(notices_on.plan().identity) == str(notices_off.plan().identity))
	var mild := FailureRuntime.new()
	mild.begin(_config(100, false, true, "mild", "late", ["roll_jam"]), 99, DT, GLOW)
	_check("severity is part of v3 physical identity", str(mild.plan().identity) != str(notices_on.plan().identity))
	var again := FailureRuntime.new()
	again.begin(_config(100, false, true, "severe", "late", ["roll_jam"]), 99, DT, GLOW)
	_check("same request and seed resolve the identical v3 plan", again.plan() == notices_on.plan())
	var snapshot: Dictionary = notices_on.snapshot()
	var target := FailureRuntime.new()
	_check("v3 snapshot restores into a new runtime", target.restore(snapshot, int(snapshot.tick)) and target.plan() == notices_on.plan())
	var tampered: Dictionary = snapshot.duplicate(true)
	tampered.plan.config.severity = "mild"
	_check("v3 plan with altered severity is refused", not FailureRuntime.new().can_restore(tampered, int(tampered.tick)))
	tampered = snapshot.duplicate(true)
	tampered.plan.config.excluded_ids = []
	_check("v3 plan with altered exclusions is refused", not FailureRuntime.new().can_restore(tampered, int(tampered.tick)))
	tampered = snapshot.duplicate(true)
	tampered.plan.config.excluded_ids = ["roll_jam", "roll_jam"]
	_check("v3 plan with duplicate exclusions is refused", not FailureRuntime.new().can_restore(tampered, int(tampered.tick)))


## Activate the requested v3 event at its onset with the given inputs; null when no seed selects it.
func _active_runtime(failure_id: String, inputs: PackedFloat64Array, servo: PackedFloat64Array) -> RefCounted:
	var excluded: Array[String] = []
	for candidate: String in FailureCatalog.KNOWN_IDS:
		if candidate != failure_id:
			excluded.append(candidate)
	var runtime := FailureRuntime.new()
	if not runtime.begin(_config(100, true, true, "standard", "early", excluded), 41, 1.0, LOGICAL):
		_check(failure_id + " can be selected alone", false, runtime.last_error)
		return null
	var onset := int(runtime.plan().onset_airborne_ticks)
	for tick in range(1, onset + 1):
		var prepared: Dictionary = runtime.prepare(inputs, servo, true)
		if not bool(prepared.get("ok", false)):
			_check(failure_id + " prepares", false, prepared)
			return null
		runtime.commit(tick)
	_check(failure_id + " is active after onset", bool(runtime.status().active) and str(runtime.status().event_id) == failure_id)
	return runtime


func _round_trips(runtime: RefCounted) -> bool:
	var snapshot: Dictionary = runtime.snapshot()
	var restored := FailureRuntime.new()
	return restored.restore(snapshot, int(snapshot.tick)) and restored.snapshot() == snapshot


func _config(probability: int, include_catastrophic: bool, notify: bool, severity: Variant = null,
		onset: Variant = null, excluded: Variant = null) -> Dictionary:
	var config := {
		"probability_percent": probability,
		"include_catastrophic": include_catastrophic,
		"notify": notify,
	}
	if severity != null:
		config["severity"] = severity
		config["onset"] = onset
		config["excluded_ids"] = excluded
	return config
