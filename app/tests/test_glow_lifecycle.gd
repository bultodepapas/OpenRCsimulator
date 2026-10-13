extends SceneTree

const Profile := preload("res://physics/glow/profile.gd")
const Lifecycle := preload("res://physics/glow/lifecycle.gd")

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _near(label: String, actual: float, expected: float, tolerance: float = 1.0e-12) -> void:
	_check(label, is_finite(actual) and absf(actual - expected) <= tolerance,
		"got %s, expected %s" % [str(actual), str(expected)])


func _initialize() -> void:
	var two_loaded: Dictionary = Profile.load_file("res://data/glow/os_max_55ax_candidate.json")
	var four_loaded: Dictionary = Profile.load_file("res://data/glow/os_fs_64v_candidate.json")
	_check("2T candidate model loads", two_loaded.ok)
	_check("4T candidate model loads", four_loaded.ok)
	if not two_loaded.ok or not four_loaded.ok:
		quit(1)
		return
	var two: Dictionary = two_loaded.model
	var four: Dictionary = four_loaded.model
	var settings_two: Dictionary = Lifecycle.candidate_settings_for_tests("glow_2t")
	var settings_four: Dictionary = Lifecycle.candidate_settings_for_tests("glow_4t")
	_check("test settings label estimates", settings_two.evidence_kind == "estimated" and settings_four.evidence_source.contains("not measured"))
	_test_state_and_lags(two, settings_two)
	_test_lifecycle(two, settings_two)
	_test_family_cadence(two, settings_two, four, settings_four)
	_test_overheat(two, settings_two)
	_test_invalid_inputs(two, settings_two)
	print("NITRO lifecycle: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _make_state(model: Dictionary, settings: Dictionary, fuel_kg: float = 0.02, running: bool = true) -> Dictionary:
	var created: Dictionary = Lifecycle.create(model, settings, fuel_kg, 390.0, 6000.0, running)
	_check("create accepts %s state" % model.family, created.get("ok", false), str(created.get("message", "")))
	return created.get("state", {})


func _test_state_and_lags(model: Dictionary, settings: Dictionary) -> void:
	var state: Dictionary = _make_state(model, settings)
	if state.is_empty():
		return
	var packed: PackedFloat64Array = Lifecycle.pack_state(state)
	_check("six float64 lifecycle values pack", packed.size() == 6 and Lifecycle.continuous_keys().size() == 6)
	var result: Dictionary = Lifecycle.evaluate(model, settings, state, 6000.0, 1.0,
		float(model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	_check("valid loaded stage evaluates", result.get("ok", false), str(result.get("message", "")))
	if not result.get("ok", false):
		return
	_check("servo moves before inducted air", result.rates.servo_fraction > 0.0 and absf(result.rates.air_fraction) < 1.0e-12)
	_check("tank loss equals carb delivered premix", absf(result.rates.fuel_kg + result.source.delivered_fuel_kg_s) < 1.0e-15)
	_check("thermal rate is finite", is_finite(result.rates.temperature_k))
	var edited := packed.duplicate()
	edited[2] = 1.0
	edited[4] = 0.0
	var open_stage: Dictionary = Lifecycle.with_continuous_state(state, edited)
	_check("stage vector produces a detached dictionary", not open_stage.is_empty() and open_stage != state)
	if open_stage.is_empty():
		return
	var lagged: Dictionary = Lifecycle.evaluate(model, settings, open_stage, 6000.0, 1.0,
		float(model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	_check("air lags the faster servo", lagged.get("ok", false) and lagged.rates.air_fraction > 0.0)
	_check("fuel transport fills separately", lagged.get("ok", false) and lagged.rates.fuel_transport_kg_s > 0.0 and lagged.source.delivered_fuel_kg_s == 0.0)
	_check("stage edit leaves accepted source state intact", state.servo_fraction == 0.0 and state.fuel_transport_kg_s > 0.0)
	var cold_values: PackedFloat64Array = Lifecycle.pack_state(state)
	cold_values[1] = 300.0
	var cold_state: Dictionary = Lifecycle.with_continuous_state(state, cold_values)
	var cold: Dictionary = Lifecycle.evaluate(model, settings, cold_state, 6000.0, 0.0,
		float(model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	var warm: Dictionary = Lifecycle.evaluate(model, settings, state, 6000.0, 0.0,
		float(model.operation.nominal_mixture), 1.225, 295.0, 10.0)
	_check("head temperature feeds back into firing success", cold.ok and warm.ok and cold.firing_fraction < warm.firing_fraction)


func _test_lifecycle(model: Dictionary, settings: Dictionary) -> void:
	var stopped: Dictionary = _make_state(model, settings, 0.02, false)
	if stopped.is_empty():
		return
	var denied: Dictionary = Lifecycle.request_start(model, settings, stopped, 2500.0, false)
	_check("starter interlock refuses a start", denied.ok and not denied.started and denied.reason == "starter_unavailable")
	var started: Dictionary = Lifecycle.request_start(model, settings, stopped, 2500.0, true)
	_check("start requires starter speed and usable fuel", started.ok and started.started and started.state.running and started.state.fuel_transport_kg_s == 0.0)
	var empty: Dictionary = _make_state(model, settings, 0.0, false)
	var no_fuel_start: Dictionary = Lifecycle.request_start(model, settings, empty, 2500.0, true)
	_check("empty tank cannot start", no_fuel_start.ok and not no_fuel_start.started and no_fuel_start.reason == "fuel_exhausted")
	var running: Dictionary = _make_state(model, settings)
	var cut_result: Dictionary = Lifecycle.cut(running)
	var cut_state: Dictionary = cut_result.state
	_check("cut closes lifecycle and carb transport", cut_state.stop_reason == "cut" and not cut_state.running and cut_state.fuel_transport_kg_s == 0.0)
	var coast: Dictionary = Lifecycle.evaluate(model, settings, cut_state, 6000.0, 0.0,
		float(model.operation.nominal_mixture), 1.225, 295.0, 60.0)
	_check("cut has no combustion or tank flow", coast.ok and coast.source.firing_frequency_hz == 0.0 and coast.source.delivered_fuel_kg_s == 0.0 and coast.rates.fuel_kg == 0.0)
	_check("coasting engine still cools thermally", coast.ok and coast.rates.temperature_k < 0.0)

	var vector: PackedFloat64Array = Lifecycle.pack_state(running)
	var stall_candidate: Dictionary = Lifecycle.with_continuous_state(running, vector)
	var stalled: Dictionary = Lifecycle.accepted(model, settings, running, stall_candidate,
		1.0 / 240.0, 6000.0, float(settings.stall_rpm) - 1.0, 1.0)
	_check("low accepted RPM latches a stall", stalled.ok and not stalled.state.running and stalled.state.stop_reason == "stall")
	var fuel_vector: PackedFloat64Array = Lifecycle.pack_state(running)
	fuel_vector[0] = 0.0
	fuel_vector[4] = 0.0
	var exhausted_candidate: Dictionary = Lifecycle.with_continuous_state(running, fuel_vector)
	var exhausted: Dictionary = Lifecycle.accepted(model, settings, running, exhausted_candidate,
		1.0 / 240.0, 6000.0, 6000.0, 1.0)
	_check("exact tank boundary latches fuel exhaustion", exhausted.ok and not exhausted.state.running and exhausted.state.stop_reason == "fuel_exhausted")
	_check("fuel exhaustion is an accepted event", exhausted.ok and exhausted.events.size() == 1 and exhausted.events[0].kind == "fuel_exhausted")
	var negative_vector: PackedFloat64Array = Lifecycle.pack_state(running)
	negative_vector[0] = -1.0e-8
	var negative_candidate: Dictionary = Lifecycle.with_continuous_state(running, negative_vector)
	var rejected: Dictionary = Lifecycle.accepted(model, settings, running, negative_candidate,
		1.0 / 240.0, 6000.0, 6000.0, 1.0)
	_check("negative tank trial is rejected instead of silently clamped", not rejected.ok and str(rejected.message).contains("split the step"))


func _test_family_cadence(two: Dictionary, settings_two: Dictionary, four: Dictionary, settings_four: Dictionary) -> void:
	var two_state: Dictionary = _make_state(two, settings_two)
	var four_state: Dictionary = _make_state(four, settings_four)
	if two_state.is_empty() or four_state.is_empty():
		return
	var nominal_two_flow: float = float(two_state.fuel_transport_kg_s)
	var rich_values: PackedFloat64Array = Lifecycle.pack_state(two_state)
	rich_values[4] = nominal_two_flow * 1.525
	var rich_state: Dictionary = Lifecycle.with_continuous_state(two_state, rich_values)
	var rich: Dictionary = Lifecycle.evaluate(two, settings_two, rich_state, 6000.0, 0.0,
		float(two.operation.nominal_mixture), 1.225, 390.0, 10.0)
	var healthy_four: Dictionary = Lifecycle.evaluate(four, settings_four, four_state, 6000.0, 0.0,
		float(four.operation.nominal_mixture), 1.225, 390.0, 10.0)
	_check("rich 2T loses successful fires without changing its family", rich.ok and rich.firing_fraction > 0.49 and rich.firing_fraction < 0.51 and rich.source.family == "glow_2t" and rich.source.cycle_revolutions == 1)
	_check("healthy 4T keeps its independent two-revolution cycle", healthy_four.ok and healthy_four.firing_fraction == 1.0 and healthy_four.source.family == "glow_4t" and healthy_four.source.cycle_revolutions == 2)
	if not rich.ok or not healthy_four.ok:
		return
	_near("both phase rates remain mechanical RPM/60", rich.rates.phase_revolutions, 100.0)
	_near("4T phase rate is also mechanical RPM/60", healthy_four.rates.phase_revolutions, 100.0)
	var two_vector: PackedFloat64Array = Lifecycle.pack_state(rich_state)
	two_vector[5] = 2.0
	var two_candidate: Dictionary = Lifecycle.with_continuous_state(rich_state, two_vector)
	var two_accept: Dictionary = Lifecycle.accepted(two, settings_two, rich_state, two_candidate,
		0.02, 6000.0, 6000.0, rich.firing_fraction)
	var four_vector: PackedFloat64Array = Lifecycle.pack_state(four_state)
	four_vector[5] = 2.0
	var four_candidate: Dictionary = Lifecycle.with_continuous_state(four_state, four_vector)
	var four_accept: Dictionary = Lifecycle.accepted(four, settings_four, four_state, four_candidate,
		0.02, 6000.0, 6000.0, healthy_four.firing_fraction)
	_check("rich 2T still has two opportunities per two revolutions", two_accept.ok and two_accept.state.opportunity_count == 2 and two_accept.state.cycle_revolutions == 1)
	_check("true 4T has one opportunity per two revolutions", four_accept.ok and four_accept.state.opportunity_count == 1 and four_accept.state.cycle_revolutions == 2)
	_check("mean rich 2T can match true 4T fire count", two_accept.ok and four_accept.ok and two_accept.state.fire_count == 1 and four_accept.state.fire_count == 1)
	_check("opportunity events preserve family and substep time", two_accept.ok and four_accept.ok and two_accept.opportunities[0].family == "glow_2t" and four_accept.opportunities[0].family == "glow_4t" and absf(two_accept.opportunities[0].time_s - 0.01) < 1.0e-12 and absf(four_accept.opportunities[0].time_s - 0.02) < 1.0e-12)
	_check("accepted phase wraps separately by mechanical cycle length", two_accept.ok and two_accept.state.phase_revolutions == 0.0 and four_accept.ok and four_accept.state.phase_revolutions == 0.0)


func _test_overheat(model: Dictionary, settings: Dictionary) -> void:
	var running: Dictionary = _make_state(model, settings)
	if running.is_empty():
		return
	var nominal: float = float(model.operation.nominal_mixture)
	var hot_values: PackedFloat64Array = Lifecycle.pack_state(running)
	hot_values[1] = 500.0
	var hot_state: Dictionary = Lifecycle.with_continuous_state(running, hot_values)
	var hot_eval: Dictionary = Lifecycle.evaluate(model, settings, hot_state, 6000.0, 0.0,
		nominal, 1.225, 295.0, 10.0)
	_check("hot-side temperature degradation reduces firing success", hot_eval.ok and hot_eval.firing_fraction > 0.0 and hot_eval.firing_fraction < 1.0)
	var zero_values: PackedFloat64Array = hot_values.duplicate()
	zero_values[1] = float(settings.temperature_firing_hot_zero_k)
	var zero_state: Dictionary = Lifecycle.with_continuous_state(running, zero_values)
	var zero_eval: Dictionary = Lifecycle.evaluate(model, settings, zero_state, 6000.0, 0.0,
		nominal, 1.225, 295.0, 10.0)
	_check("hot-zero temperature suppresses firing", zero_eval.ok and zero_eval.firing_fraction == 0.0)
	var shutdown: Dictionary = Lifecycle.accepted(model, settings, running, zero_state,
		1.0 / 240.0, 6000.0, 6000.0, 0.0)
	_check("accepted hot boundary latches overheat and cuts fuel transport", shutdown.ok and not shutdown.state.running and shutdown.state.stop_reason == "overheat" and shutdown.state.fuel_transport_kg_s == 0.0)
	_check("overheat is exposed as a stop event", shutdown.ok and shutdown.events.size() == 1 and shutdown.events[0].kind == "overheat")
	var restart: Dictionary = Lifecycle.request_start(model, settings, shutdown.state, 2500.0, true)
	_check("overheated engine cannot restart until cooled", restart.ok and not restart.started and restart.reason == "overheated")


func _test_invalid_inputs(model: Dictionary, settings: Dictionary) -> void:
	var invalid: Dictionary = settings.duplicate(true)
	invalid.servo_time_constant_s = 0.0
	var rejected: Dictionary = Lifecycle.create(model, invalid, 0.02, 390.0, 6000.0, true)
	_check("zero servo time constant is refused", not rejected.ok)
	var invalid_temperature_order: Dictionary = settings.duplicate(true)
	invalid_temperature_order.temperature_firing_hot_full_k = invalid_temperature_order.temperature_firing_full_k
	var rejected_temperature_order: Dictionary = Lifecycle.create(model, invalid_temperature_order, 0.02, 390.0, 6000.0, true)
	_check("overlapping cold and hot firing thresholds are refused", not rejected_temperature_order.ok)
	_check("unknown family has no candidate settings", Lifecycle.candidate_settings_for_tests("glow_prop").is_empty())
