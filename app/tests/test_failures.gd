extends SceneTree

const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FailureRuntime := preload("res://failures/runtime.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_config_contract()
	_test_occurrence_and_plan_determinism()
	_test_catalog_and_parameter_bounds()
	_test_candidate_rollback_and_jam()
	_test_bias_trim_compensation()
	_test_throttle_limit_and_snapshot_consistency()
	_test_radio_hold_profile()
	_test_restart_and_self_contained_restore()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _test_config_contract() -> void:
	var defaults: Dictionary = FailureConfig.defaults()
	_check("default probability is zero", defaults.get("probability_percent") == 0, defaults)
	_check("catastrophic failures default off", defaults.get("include_catastrophic") == false, defaults)
	_check("notices default on", defaults.get("notify") == true, defaults)
	_check("defaults validate unchanged", FailureConfig.validate(defaults).get("config") == defaults)
	_check("100 percent is accepted", FailureConfig.validate({
		"probability_percent": 100, "include_catastrophic": true, "notify": false,
	}).get("ok", false))
	_check("non-object config is rejected", not FailureConfig.validate(null).get("ok", true))
	_check("missing key is rejected", not FailureConfig.validate({"probability_percent": 0}).get("ok", true))
	_check("unknown key is rejected", not FailureConfig.validate({
		"probability_percent": 0, "include_catastrophic": false, "notify": true, "seed": 12,
	}).get("ok", true))
	_check("probability is not coerced from float", not FailureConfig.validate({
		"probability_percent": 2.0, "include_catastrophic": false, "notify": true,
	}).get("ok", true))
	_check("probability range is enforced", not FailureConfig.validate({
		"probability_percent": 101, "include_catastrophic": false, "notify": true,
	}).get("ok", true))
	_check("boolean is not accepted as integer probability", not FailureConfig.validate({
		"probability_percent": true, "include_catastrophic": false, "notify": true,
	}).get("ok", true))


func _test_occurrence_and_plan_determinism() -> void:
	var off_config := FailureConfig.defaults()
	var off := FailureRuntime.new()
	_check("disabled plan begins", off.begin(off_config, 10, 1.0))
	var off_plan: Dictionary = off.plan()
	_check("zero probability never assigns event", not bool(off_plan.selected) and str(off_plan.id).is_empty(), off_plan)
	_check("zero probability has no onset", int(off_plan.onset_airborne_ticks) == 0)
	var disabled_fast_path: Dictionary = off.prepare(PackedFloat64Array(), PackedFloat64Array(), true)
	_check("disabled prepare leaves incomplete arrays untouched and skips fault work", bool(disabled_fast_path.get("ok", false)) and not bool(disabled_fast_path.get("activation_due", true)), disabled_fast_path)
	for tick in range(1, 125):
		var prepared: Dictionary = off.prepare(_inputs(), _servos(), true)
		_check("disabled candidate prepares", bool(prepared.get("ok", false)), prepared)
		_check("disabled candidate never activates", not bool(prepared.get("activation_due", true)))
		_check("disabled event never commits", not off.commit(tick))
	_check("disabled flight stays inactive", not bool(off.status().active))

	var full_config := _config(100, false, true)
	var first := FailureRuntime.new()
	var second := FailureRuntime.new()
	_check("100 percent plan begins", first.begin(full_config, 321, 1.0))
	_check("same seed plan begins", second.begin(full_config, 321, 1.0))
	var first_plan: Dictionary = first.plan()
	_check("100 percent assigns event", bool(first_plan.selected) and not str(first_plan.id).is_empty(), first_plan)
	_check("same seed resolves identical immutable plan", first_plan == second.plan())
	_check("onset lies in 20 to 120 seconds", int(first_plan.onset_airborne_seconds) >= 20 and int(first_plan.onset_airborne_seconds) <= 120)
	_check("dt=1 onset tick equals resolved second", int(first_plan.onset_airborne_ticks) == int(first_plan.onset_airborne_seconds))
	var fractional_dt := FailureRuntime.new()
	fractional_dt.begin(full_config, 321, 0.7)
	var quantized_seconds := float(fractional_dt.plan().onset_airborne_ticks) * 0.7
	_check("non-dividing timestep still keeps onset within 20..120 seconds", quantized_seconds >= 20.0 and quantized_seconds <= 120.0, quantized_seconds)
	var changed_seed := FailureRuntime.new()
	changed_seed.begin(full_config, 322, 1.0)
	_check("different seed changes plan identity", str(first_plan.identity) != str(changed_seed.plan().identity))
	var hidden_notice := FailureRuntime.new()
	hidden_notice.begin(_config(100, false, false), 321, 1.0)
	_check("notify setting does not change the physical plan identity", str(first_plan.identity) == str(hidden_notice.plan().identity))
	_check("notify setting remains stored in the plan", not bool(hidden_notice.plan().config.notify))
	var detached: Dictionary = first.plan()
	detached["id"] = "tampered"
	_check("plan result is detached", str(first.plan().id) != "tampered")
	_check("seed outside uint32 is rejected", not FailureRuntime.new().begin(full_config, -1, 1.0))
	_check("invalid timestep is rejected", not FailureRuntime.new().begin(full_config, 1, 0.0))
	_check("invalid config is rejected", not FailureRuntime.new().begin({"probability_percent": 100}, 1, 1.0))


func _test_catalog_and_parameter_bounds() -> void:
	var expected_ordinary := [
		"roll_jam", "pitch_jam", "yaw_jam", "roll_bias", "pitch_bias", "roll_slow",
		"throttle_limit", "throttle_stuck",
	]
	_check("ordinary catalog has the supported logical cases", FailureCatalog.ORDINARY_IDS == expected_ordinary)
	_check("radio loss is the only catastrophic event", FailureCatalog.CATASTROPHIC_IDS == ["radio_loss"])
	var seen: Dictionary = {}
	var config := _config(100, true, true)
	for seed in 2048:
		var runtime := FailureRuntime.new()
		if not runtime.begin(config, seed, 1.0):
			_check("catalog plan resolves", false, seed)
			continue
		var resolved: Dictionary = runtime.plan()
		var failure_id := str(resolved.id)
		seen[failure_id] = true
		_check("selected plan has bounded onset", int(resolved.onset_airborne_seconds) >= 20 and int(resolved.onset_airborne_seconds) <= 120, resolved)
		var parameters: Dictionary = resolved.parameters
		if failure_id in ["roll_jam", "pitch_jam", "yaw_jam"]:
			_check(failure_id + " maps one logical axis", int(parameters.axis) >= 0 and int(parameters.axis) <= 2, parameters)
		elif failure_id in ["roll_bias", "pitch_bias"]:
			var bias := absf(float(parameters.bias))
			_check(failure_id + " bias stays within 0.08..0.18", bias >= 0.08 and bias <= 0.18, parameters)
		elif failure_id == "roll_slow":
			var rate_factor := float(parameters.rate_factor)
			_check("roll servo rate stays within 0.25..0.50", rate_factor >= 0.25 and rate_factor <= 0.50, parameters)
		elif failure_id == "throttle_limit":
			var ceiling := float(parameters.maximum_demand)
			_check("throttle ceiling stays within 0.45..0.70", ceiling >= 0.45 and ceiling <= 0.70, parameters)
		elif failure_id == "throttle_stuck":
			var high := float(parameters.high_demand)
			_check("stuck throttle target stays within 0.70..0.90", high >= 0.70 and high <= 0.90, parameters)
		elif failure_id == "radio_loss":
			_check("radio-loss preset is idle", float(parameters.throttle_preset) == 0.0, parameters)
	_check("all ordinary IDs are reachable", _contains_all(seen, FailureCatalog.ORDINARY_IDS), seen)
	_check("radio loss is reachable when opted in", seen.has("radio_loss"), seen)
	var no_cat_seen: Dictionary = {}
	for seed in 512:
		var runtime := FailureRuntime.new()
		runtime.begin(_config(100, false, true), seed, 1.0)
		no_cat_seen[str(runtime.plan().id)] = true
	_check("catastrophic event is excluded unless opted in", not no_cat_seen.has("radio_loss"), no_cat_seen)


func _test_candidate_rollback_and_jam() -> void:
	var picked := _runtime_for("roll_jam", false)
	_check("seed search found roll jam", not picked.is_empty())
	if picked.is_empty():
		return
	var runtime: RefCounted = picked.runtime
	var onset := int(runtime.plan().onset_airborne_ticks)
	var inputs := _inputs()
	var servo := PackedFloat64Array([0.0, 0.37, -0.2, 0.1])
	for tick in range(1, onset):
		var prepared: Dictionary = runtime.prepare(inputs, servo, true)
		_check("pending event tick prepares", bool(prepared.ok), prepared)
		_check("fault stays inactive before onset", not runtime.commit(tick))
	var before: Dictionary = runtime.snapshot()
	var due: Dictionary = runtime.prepare(inputs, servo, true)
	_check("onset prepares one activation candidate", bool(due.activation_due), due)
	_check("staged jam holds current actual servo", runtime.effective_axis(0, inputs[0]) == servo[1])
	_check("staged jam has zero servo rate", runtime.servo_rate_factor(0) == 0.0)
	_check("staged event is not yet visible as active", not bool(runtime.status().active))
	runtime.rollback()
	_check("rollback leaves tick and event state unchanged", runtime.snapshot() == before)
	_check("rollback removes staged jam effect", runtime.effective_axis(0, inputs[0]) == inputs[0] and runtime.servo_rate_factor(0) == 1.0)
	var due_again: Dictionary = runtime.prepare(inputs, servo, true)
	_check("same resolved event is staged after rollback", bool(due_again.activation_due) and str(runtime.plan().id) == "roll_jam")
	_check("accepted onset commits exactly once", runtime.commit(onset))
	_check("commit publishes jam and activation tick", bool(runtime.status().active) and int(runtime.status().activation_tick) == onset)
	_check("active jam still holds captured actual position after opposing stick/trim", runtime.effective_axis(0, -0.9) == servo[1])
	_check("event record carries useful English label and hint", not str(runtime.status().label).is_empty() and not str(runtime.status().hint).is_empty(), runtime.status())
	_check("event has a plain English source label", not str(runtime.status().source_label).is_empty(), runtime.status())


func _test_bias_trim_compensation() -> void:
	var runtime := FailureRuntime.new()
	_check("fixed roll-bias seed begins", runtime.begin(_config(100, false, true), 158, 1.0))
	_check("fixed seed resolves roll bias at 20 seconds", str(runtime.plan().id) == "roll_bias" and int(runtime.plan().onset_airborne_seconds) == 20, runtime.plan())
	var bias := float(runtime.plan().parameters.bias)
	var inputs := _inputs()
	for tick in range(1, 20):
		var prepared: Dictionary = runtime.prepare(inputs, _servos(), true)
		_check("roll-bias pending tick prepares", bool(prepared.ok))
		_check("roll bias stays inactive before onset", not runtime.commit(tick))
	var staged: Dictionary = runtime.prepare(inputs, _servos(), true)
	_check("roll bias stages at onset", bool(staged.activation_due))
	# This is the post-trim roll command delivered to the failure layer.
	var compensated := runtime.effective_axis(0, -bias)
	_check("opposite trim cancels persistent roll command bias", absf(compensated) < 1e-12, {"bias": bias, "effective": compensated})
	_check("roll bias remains staged until accepted tick", not bool(runtime.status().active))
	_check("roll bias activates on commit", runtime.commit(20) and bool(runtime.status().active))
	var active_compensation := runtime.effective_axis(0, -bias)
	_check("trim compensation still applies during active bias", absf(active_compensation) < 1e-12)


func _test_throttle_limit_and_snapshot_consistency() -> void:
	var runtime := FailureRuntime.new()
	_check("fixed throttle-limit seed begins", runtime.begin(_config(100, false, true), 223, 1.0))
	_check("fixed seed resolves throttle limit at 20 seconds", str(runtime.plan().id) == "throttle_limit" and int(runtime.plan().onset_airborne_seconds) == 20, runtime.plan())
	var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.95])
	for tick in range(1, 20):
		var prepared: Dictionary = runtime.prepare(inputs, _servos(), true)
		_check("throttle-limit pending tick prepares", bool(prepared.ok))
		_check("throttle ceiling stays inactive before onset", not runtime.commit(tick))
	var staged: Dictionary = runtime.prepare(inputs, _servos(), true)
	var ceiling := float(runtime.plan().parameters.maximum_demand)
	_check("throttle limit applies a ceiling at onset", bool(staged.activation_due) and runtime.effective_throttle(inputs[3]) == ceiling)
	_check("throttle-limit event activates", runtime.commit(20))
	var snapshot: Dictionary = runtime.snapshot()
	_check("throttle-limit checkpoint contains capped demand", float(snapshot.last_inputs[3]) == ceiling, snapshot.last_inputs)
	var corrupt: Dictionary = snapshot.duplicate(true)
	var corrupted_inputs: PackedFloat64Array = corrupt.last_inputs.duplicate()
	corrupted_inputs[3] = 1.0
	corrupt["last_inputs"] = corrupted_inputs
	_check("restore rejects control state above resolved throttle ceiling", not FailureRuntime.new().can_restore(corrupt, 20))


func _test_radio_hold_profile() -> void:
	var picked := _runtime_for("radio_loss", true)
	_check("seed search found opted-in radio loss", not picked.is_empty())
	if picked.is_empty():
		return
	var runtime: RefCounted = picked.runtime
	var onset := int(runtime.plan().onset_airborne_ticks)
	var last_inputs := PackedFloat64Array([0.2, -0.15, 0.05, 0.65])
	for tick in range(1, onset):
		var prepared: Dictionary = runtime.prepare(last_inputs, _servos(), true)
		_check("radio pending tick prepares", bool(prepared.ok), prepared)
		_check("radio pending tick does not activate", not runtime.commit(tick))
	var changed_inputs := PackedFloat64Array([0.8, 0.7, -0.5, 0.95])
	var due: Dictionary = runtime.prepare(changed_inputs, _servos(), true)
	_check("radio loss stages at resolved onset", bool(due.activation_due))
	var held: PackedFloat64Array = runtime.effective_inputs(changed_inputs)
	_check("radio loss holds last accepted surfaces", held[0] == last_inputs[0] and held[1] == last_inputs[1] and held[2] == last_inputs[2], held)
	_check("radio loss stages idle throttle preset", held[3] == 0.0, held)
	_check("radio loss event commits", runtime.commit(onset))
	var following := PackedFloat64Array([-0.9, -0.8, 0.4, 0.8])
	var next: Dictionary = runtime.prepare(following, _servos(), true)
	_check("active radio loss remains prepared", bool(next.ok))
	var still_held: PackedFloat64Array = runtime.effective_inputs(following)
	_check("radio loss remains sustained across accepted ticks", still_held[0] == last_inputs[0] and still_held[1] == last_inputs[1] and still_held[2] == last_inputs[2] and still_held[3] == 0.0, still_held)
	_check("radio loss has explicit catastrophe classification", FailureCatalog.definition("radio_loss").get("severity") == "catastrophic")
	_check("radio loss commits without redrawing", not runtime.commit(onset + 1) and bool(runtime.status().active))


func _test_restart_and_self_contained_restore() -> void:
	var picked := _runtime_for("throttle_stuck", false)
	_check("seed search found throttle-stuck event", not picked.is_empty())
	if picked.is_empty():
		return
	var runtime: RefCounted = picked.runtime
	var stable_plan: Dictionary = runtime.plan()
	var onset := int(stable_plan.onset_airborne_ticks)
	var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.15])
	for tick in range(1, onset):
		var prepared: Dictionary = runtime.prepare(inputs, _servos(), true)
		_check("throttle pending tick prepares", bool(prepared.ok))
		_check("throttle pending tick does not activate", not runtime.commit(tick))
	var due: Dictionary = runtime.prepare(inputs, _servos(), true)
	_check("stuck throttle activates at resolved tick", bool(due.activation_due))
	var stuck: float = runtime.effective_throttle(inputs[3])
	_check("stuck throttle uses resolved elevated demand", stuck >= 0.70 and stuck <= 0.90, stuck)
	_check("staged throttle remains invisible until commit", not bool(runtime.status().active))
	_check("stuck-throttle event commits", runtime.commit(onset))
	for tick in range(onset + 1, onset + 4):
		var prepared: Dictionary = runtime.prepare(inputs, _servos(), true)
		_check("active throttle tick prepares", bool(prepared.ok))
		_check("active throttle does not emit duplicate onset", not runtime.commit(tick))
	var snapshot: Dictionary = runtime.snapshot()
	var restored := FailureRuntime.new()
	_check("self-contained snapshot can restore into a new runtime", restored.can_restore(snapshot, onset + 3))
	_check("restore succeeds into a new runtime", restored.restore(snapshot, onset + 3))
	_check("restored plan identity and event are unchanged", restored.plan() == runtime.plan())
	_check("restored state matches snapshot", restored.snapshot() == snapshot)
	_check("restored active throttle remains stuck", restored.effective_throttle(0.1) == snapshot.held_inputs[3])
	var corrupt: Dictionary = snapshot.duplicate(true)
	corrupt["plan"]["seed"] = int(corrupt.plan.seed) + 1
	_check("plan mutation is refused", not restored.can_restore(corrupt, onset + 3))
	corrupt = snapshot.duplicate(true)
	corrupt["event_id"] = "radio_loss"
	_check("event identity mismatch is refused", not restored.can_restore(corrupt, onset + 3))
	corrupt = snapshot.duplicate(true)
	corrupt["tick"] = onset + 2
	_check("snapshot tick mismatch is refused", not restored.can_restore(corrupt, onset + 3))
	corrupt = snapshot.duplicate(true)
	corrupt["active"] = "true"
	_check("wrong snapshot field type is refused", not restored.can_restore(corrupt, onset + 3))
	corrupt = snapshot.duplicate(true)
	corrupt["extra"] = 1
	_check("unknown snapshot key is refused", not restored.can_restore(corrupt, onset + 3))
	var before_refusal: Dictionary = restored.snapshot()
	_check("failed restore does not mutate running runtime", not restored.restore(corrupt, onset + 3) and restored.snapshot() == before_refusal)
	_check("restore refuses mismatched current tick", not restored.restore(snapshot, onset + 4))
	var completed_identity := str(runtime.plan().identity)
	runtime.restart()
	_check("restart preserves resolved plan identity", str(runtime.plan().identity) == completed_identity)
	_check("restart clears activation and airborne clock", not bool(runtime.status().active) and int(runtime.status().airborne_ticks) == 0 and int(runtime.status().activation_tick) == -1)
	var restarted_status: Dictionary = runtime.status()
	_check("restarted plan preserves same event and onset", str(restarted_status.event_id) == str(stable_plan.id) and int(restarted_status.onset_airborne_ticks) == int(stable_plan.onset_airborne_ticks))


func _runtime_for(event_id: String, include_catastrophic: bool) -> Dictionary:
	var config := _config(100, include_catastrophic, true)
	for seed in 4096:
		var runtime := FailureRuntime.new()
		if runtime.begin(config, seed, 1.0) and str(runtime.plan().id) == event_id:
			return {"runtime": runtime, "seed": seed}
	return {}


func _config(probability: int, include_catastrophic: bool, notify: bool) -> Dictionary:
	return {
		"probability_percent": probability,
		"include_catastrophic": include_catastrophic,
		"notify": notify,
	}


func _inputs() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.5])


func _servos() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


func _contains_all(source: Dictionary, values: Array[String]) -> bool:
	for value: String in values:
		if not source.has(value):
			return false
	return true
