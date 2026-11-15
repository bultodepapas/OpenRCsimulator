# SPDX-License-Identifier: MIT
# Standalone analytical/contract fixture; not OpenRC integration/flight evidence.
extends SceneTree

const Core := preload("res://core/afterburner_core.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_test_validation()
	_test_modes_and_geometry()
	_test_stage_purity_and_ignition()
	_test_hysteresis_and_rearm()
	_test_hard_cut_and_soft_tail()
	_test_soft_tail_reengagement()
	_test_analytical_lag_and_fuel()
	_test_restore_and_independent_engines()
	print("AFTERBURNER_CORE: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s: actual=%.17f expected=%.17f" % [label, actual, expected])


func _command(request: float = 1.0, throttle: float = 1.0) -> Dictionary:
	return {"request": request, "throttle": throttle}


func _permits(rpm_ratio: float = 1.0) -> Dictionary:
	return {"armed": true, "input_valid": true, "engine_running": true,
		"source_available": true, "rpm_ratio": rpm_ratio}


func _lit(config: Dictionary, intensity: float = 0.0) -> Dictionary:
	var state: Dictionary = Core.initial_state(config)
	state.phase = Core.Phase.LIT
	state.latched = true
	state.intensity = intensity
	return state


## Test-only scalar RK4 quadrature. Production must use the existing Simulation
## owner and its event remainder; do not copy this as a second runtime clock.
func _integrate(intensity: float, sample: Dictionary, config: Dictionary, dt: float,
		combustion_available: bool = true) -> Dictionary:
	var k1: Dictionary = Core.evaluate(intensity, sample, combustion_available, config)
	var k2: Dictionary = Core.evaluate(intensity + dt * k1.intensity_derivative * 0.5,
		sample, combustion_available, config)
	var k3: Dictionary = Core.evaluate(intensity + dt * k2.intensity_derivative * 0.5,
		sample, combustion_available, config)
	var k4: Dictionary = Core.evaluate(intensity + dt * k3.intensity_derivative,
		sample, combustion_available, config)
	return {"intensity": intensity + dt / 6.0 * (k1.intensity_derivative \
		+ 2.0 * k2.intensity_derivative + 2.0 * k3.intensity_derivative + k4.intensity_derivative),
		"fuel_used_kg": dt / 6.0 * (k1.additional_fuel_flow_kg_s \
		+ 2.0 * k2.additional_fuel_flow_kg_s + 2.0 * k3.additional_fuel_flow_kg_s \
		+ k4.additional_fuel_flow_kg_s)}


func _one_interval(state: Dictionary, command: Dictionary, permits: Dictionary,
		config: Dictionary, dt: float = 1.0 / 240.0) -> Dictionary:
	var sample: Dictionary = Core.freeze_sample(state, command, permits, config)
	var integrated: Dictionary = _integrate(float(state.intensity), sample, config, dt,
		bool(permits.source_available) and bool(permits.engine_running))
	var result: Dictionary = Core.finish_interval(state, sample, integrated.intensity, dt,
		bool(permits.source_available) and bool(permits.engine_running), config)
	result.fuel_used_kg = integrated.fuel_used_kg
	return result


func _test_validation() -> void:
	var config: Dictionary = Core.example_config()
	_check(Core.validate_config(config).ok, "example config accepted")
	_check(Core.step_supported(config, 1.0 / 240.0), "240 Hz interval supported")
	_check(not Core.step_supported(config, 1.0), "oversized explicit interval rejected")
	_check(not Core.step_supported(config, NAN), "NaN interval rejected")
	_check(not Core.step_supported(config, 0.0), "zero interval rejected")
	for field: String in Core.CONFIG_SCALARS:
		var invalid: Dictionary = config.duplicate(true)
		invalid[field] = NAN
		_check(not Core.validate_config(invalid).ok, "NaN config rejected: " + field)
	var bad: Dictionary = config.duplicate(true)
	bad.rise_tau_s = 0.0
	_check(not Core.validate_config(bad).ok, "zero response time rejected")
	bad = config.duplicate(true)
	bad.throttle_off = bad.throttle_on
	_check(not Core.validate_config(bad).ok, "zero hysteresis width rejected")
	bad = config.duplicate(true)
	bad.additional_fuel_kg_s = 0.0
	_check(not Core.validate_config(bad).ok, "free augmented thrust rejected")
	bad = config.duplicate(true)
	bad.axis_frd = PackedFloat64Array([2.0, 0.0, 0.0])
	_check(not Core.validate_config(bad).ok, "non-unit nozzle axis rejected")
	bad = config.duplicate(true)
	bad.nozzle_arm_frd_m = PackedFloat64Array([0.0, INF, 0.0])
	_check(not Core.validate_config(bad).ok, "infinite installation arm rejected")
	var state: Dictionary = Core.initial_state(config)
	state.intensity = NAN
	_check(not Core.valid_state(state, config), "NaN state rejected")
	state = Core.initial_state(config)
	state.intensity = 0.5
	_check(not Core.valid_state(state, config), "ready state cannot hide nonzero intensity")
	state = Core.initial_state(config)
	_check(not Core.freeze_sample(state, _command(NAN), _permits(), config).ok,
		"NaN accepted request rejected")
	var permit: Dictionary = _permits()
	permit.rpm_ratio = INF
	_check(not Core.freeze_sample(state, _command(), permit, config).ok, "infinite rpm rejected")
	var sample: Dictionary = Core.freeze_sample(state, _command(), _permits(), config)
	_check(not Core.evaluate(NAN, sample, true, config).ok, "NaN trial state rejected")
	_check(not Core.evaluate(1.01, sample, true, config).ok, "out-of-domain trial state rejected")
	var bad_sample: Dictionary = sample.duplicate()
	bad_sample.target = NAN
	_check(not Core.evaluate(0.0, bad_sample, true, config).ok, "invalid frozen sample rejected")
	bad = config.duplicate(true)
	bad.additional_gross_thrust_n = 1.0e308
	bad.nozzle_arm_frd_m = PackedFloat64Array([0.0, 1.0e308, 0.0])
	var lit_sample: Dictionary = Core.freeze_sample(_lit(bad, 1.0), _command(), _permits(), bad)
	_check(not Core.evaluate(1.0, lit_sample, true, bad).ok, "overflowing physical load refused")


func _test_modes_and_geometry() -> void:
	var zeros := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]).to_byte_array()
	for mode: int in [Core.EffectMode.DISABLED, Core.EffectMode.COSMETIC]:
		var config: Dictionary = Core.example_config(mode)
		var state: Dictionary = Core.initial_state(config) if mode == Core.EffectMode.DISABLED else _lit(config, 0.9)
		var sample: Dictionary = Core.freeze_sample(state, _command(), _permits(), config)
		var result: Dictionary = Core.evaluate(float(state.intensity), sample, true, config)
		_check(result.ok, "nonphysical mode evaluates")
		_check(result.additional_loads_frd.to_byte_array() == zeros, "nonphysical loads are bit-exact +zero")
		_check(PackedFloat64Array([result.additional_gross_thrust_n,
			result.additional_fuel_flow_kg_s]).to_byte_array() == PackedFloat64Array([0.0, 0.0]).to_byte_array(),
			"nonphysical gross/fuel are bit-exact +zero")
		if mode == Core.EffectMode.COSMETIC:
			_near(result.flame_intensity, 0.9, 0.0, "cosmetic presentation still works")
	var config: Dictionary = Core.example_config()
	config.axis_frd = PackedFloat64Array([0.6, 0.8, 0.0])
	config.nozzle_arm_frd_m = PackedFloat64Array([2.0, -1.0, 0.5])
	var sample: Dictionary = Core.freeze_sample(_lit(config, 0.5), _command(), _permits(), config)
	var result: Dictionary = Core.evaluate(0.5, sample, true, config)
	var expected := PackedFloat64Array([9.0, 12.0, 0.0, -6.0, 4.5, 33.0])
	for i: int in 6:
		_near(result.additional_loads_frd[i], expected[i], 1.0e-14, "analytical FRD load index %d" % i)
	_near(result.additional_gross_thrust_n, 15.0, 0.0, "gross thrust in newtons")
	_near(result.additional_fuel_flow_kg_s, 0.0025, 0.0, "additional fuel in kg/s")
	_near(result.additional_fuel_flow_kg_s * 3600.0, 9.0, 0.0, "kg/s to kg/h arithmetic")
	config.nozzle_arm_frd_m = PackedFloat64Array([0.0, 0.0, 0.0])
	result = Core.evaluate(0.5, sample, true, config)
	_check(result.additional_loads_frd.slice(3, 6) == PackedFloat64Array([0.0, 0.0, 0.0]),
		"centered nozzle has no added moment")


func _test_stage_purity_and_ignition() -> void:
	var config: Dictionary = Core.example_config()
	var state: Dictionary = Core.initial_state(config)
	var command: Dictionary = _command()
	var permit: Dictionary = _permits()
	var before := var_to_bytes([state, command, permit, config])
	var sample: Dictionary = Core.freeze_sample(state, command, permit, config)
	_check(sample.is_read_only(), "accepted sample is immutable")
	_check(sample.phase == Core.Phase.IGNITING, "valid request enters ignition proposal")
	var sample_before := var_to_bytes(sample)
	var first := var_to_bytes(Core.evaluate(0.0, sample, true, config))
	var all_identical: bool = true
	for _i: int in 100:
		all_identical = all_identical and var_to_bytes(Core.evaluate(0.0, sample, true, config)) == first
	_check(all_identical, "100 repeated stages produce identical results")
	_check(var_to_bytes([state, command, permit, config]) == before, "stage/sampling inputs unmodified")
	_check(var_to_bytes(sample) == sample_before, "stage did not advance sampled ignition timer")
	var dt: float = 1.0 / 240.0
	var proposal: Dictionary = Core.finish_interval(state, sample, 0.0, dt, true, config)
	_check(proposal.ok, "accepted ignition proposal valid")
	_near(proposal.state.ignition_elapsed_s, dt, 0.0, "timer advances once at accepted boundary")
	_check(proposal.events.size() == 1, "one proposed mode event at first accepted boundary")
	_check(var_to_bytes(proposal) == var_to_bytes(Core.finish_interval(state, sample, 0.0, dt, true, config)),
		"repeated endpoint proposal has same sequence; no side effects")
	state = proposal.state
	var elapsed: float = dt
	var lit_events: int = 0
	while state.phase != Core.Phase.LIT and elapsed < 1.0:
		proposal = _one_interval(state, command, permit, config, dt)
		for event: Dictionary in proposal.events:
			if event.to == Core.Phase.LIT:
				lit_events += 1
		state = proposal.state
		elapsed += dt
	_check(state.phase == Core.Phase.LIT and lit_events == 1, "one accepted light event")
	_check(elapsed >= config.ignition_delay_s - 1.0e-14 \
		and elapsed <= config.ignition_delay_s + dt + 1.0e-14, "ignition quantization bounded by one interval")
	_near(state.intensity, 0.0, 0.0, "no thrust growth during ignition delay")


func _test_hysteresis_and_rearm() -> void:
	var config: Dictionary = Core.example_config()
	var state: Dictionary = _lit(config, 0.7)
	for throttle: float in [0.919, 0.921, 0.918, 0.920, 0.90]:
		var sample: Dictionary = Core.freeze_sample(state, _command(1.0, throttle), _permits(0.79), config)
		_check(sample.phase == Core.Phase.LIT and sample.latched, "latched hysteresis rejects threshold chatter")
	var release: Dictionary = Core.freeze_sample(state, _command(1.0, 0.88), _permits(), config)
	_check(release.phase == Core.Phase.EXTINGUISHING and not release.latched, "off threshold releases latch")
	var cold: Dictionary = Core.initial_state(config)
	_check(Core.freeze_sample(cold, _command(1.0, 0.919), _permits(), config).phase == Core.Phase.READY,
		"unlatched throttle below engage does not ignite")
	_check(Core.freeze_sample(cold, _command(), _permits(0.79), config).phase == Core.Phase.READY,
		"unlatched RPM below engage does not ignite")
	var lost: Dictionary = _permits()
	lost.input_valid = false
	var sample: Dictionary = Core.freeze_sample(state, _command(), lost, config)
	var cut: Dictionary = Core.finish_interval(state, sample, 0.6, 1.0 / 240.0, true, config)
	_check(cut.ok and cut.state.phase == Core.Phase.INHIBITED and cut.state.rearm_required,
		"input loss inhibits and requires release")
	var held: Dictionary = Core.freeze_sample(cut.state, _command(), _permits(), config)
	_check(held.phase == Core.Phase.INHIBITED and held.inhibit_reason == "release_required",
		"reconnection with held request cannot reignite")
	var released: Dictionary = _one_interval(cut.state, _command(0.0), _permits(), config)
	_check(released.state.phase == Core.Phase.READY and not released.state.rearm_required,
		"fresh release clears inhibit")
	_check(Core.freeze_sample(released.state, _command(), _permits(), config).phase == Core.Phase.IGNITING,
		"new request after release can ignite")


func _test_hard_cut_and_soft_tail() -> void:
	var config: Dictionary = Core.example_config()
	var state: Dictionary = _lit(config, 1.0)
	var sample: Dictionary = Core.freeze_sample(state, _command(), _permits(), config)
	var dry: Dictionary = Core.evaluate(1.0, sample, false, config)
	_check(dry.additional_loads_frd == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		"located source cut overrides previously permitted frozen sample")
	_near(dry.additional_fuel_flow_kg_s, 0.0, 0.0, "source cut has zero AB fuel request")
	var cut: Dictionary = Core.finish_interval(state, sample, 0.9, 1.0 / 240.0, false, config)
	_check(cut.state.phase == Core.Phase.INHIBITED and cut.state.intensity == 0.0,
		"hard cut clears physical intensity at accepted endpoint")
	var unavailable: Dictionary = _permits(1.0)
	unavailable.source_available = false
	var denied: Dictionary = Core.freeze_sample(state, _command(), unavailable, config)
	_near(Core.evaluate(1.0, denied, false, config).additional_gross_thrust_n, 0.0, 0.0,
		"high RPM does not authorize fuel-less afterburner")
	var soft: Dictionary = Core.freeze_sample(state, _command(0.0), _permits(), config)
	var tail: Dictionary = Core.evaluate(0.5, soft, true, config)
	_check(soft.phase == Core.Phase.EXTINGUISHING, "ordinary release enters soft tail")
	_near(tail.additional_gross_thrust_n, 15.0, 0.0, "soft tail retains modeled thrust")
	_near(tail.additional_fuel_flow_kg_s, 0.0025, 0.0, "soft tail consumes corresponding fuel")
	_check(tail.intensity_derivative < 0.0, "soft tail intensity decays")
	var extinguished: Dictionary = Core.finish_interval(state, soft, 1.0e-9, 1.0 / 240.0, true, config)
	_check(extinguished.state.phase == Core.Phase.READY and extinguished.state.intensity == 0.0,
		"small tail terminates at explicit tolerance")


func _lag_run(hz: int) -> Dictionary:
	var config: Dictionary = Core.example_config()
	var state: Dictionary = _lit(config, 0.0)
	var fuel: float = 0.0
	for _tick: int in hz:
		var result: Dictionary = _one_interval(state, _command(), _permits(), config, 1.0 / float(hz))
		state = result.state
		fuel += result.fuel_used_kg
	return {"intensity": state.intensity, "fuel_kg": fuel}


func _test_soft_tail_reengagement() -> void:
	var config: Dictionary = Core.example_config()
	var extinguishing: Dictionary = _lit(config, 0.8)
	extinguishing.phase = Core.Phase.EXTINGUISHING
	extinguishing.latched = false
	var sample: Dictionary = Core.freeze_sample(extinguishing, _command(), _permits(), config)
	var output: Dictionary = Core.evaluate(0.8, sample, true, config)
	_check(sample.phase == Core.Phase.LIT and sample.inhibit_reason == "resume_existing_burn",
		"reengagement resumes still-burning tail without an ignition gap")
	_near(output.additional_gross_thrust_n, 24.0, 0.0, "reengagement preserves force continuity")
	_near(output.additional_fuel_flow_kg_s, 0.004, 0.0, "reengagement preserves fuel continuity")
	_check(output.intensity_derivative > 0.0, "reengagement grows from current intensity")
	var result: Dictionary = _one_interval(extinguishing, _command(), _permits(), config)
	_check(result.state.phase == Core.Phase.LIT and result.state.intensity > 0.8,
		"first resumed endpoint has no cold-ignition wait")
	_check(result.events.size() == 1 and result.events[0].from == Core.Phase.EXTINGUISHING \
		and result.events[0].reason == "resume_existing_burn",
		"resume event is distinguishable from a cold ignition")
	var ready: Dictionary = Core.initial_state(config)
	var cold_sample: Dictionary = Core.freeze_sample(ready, _command(), _permits(), config)
	_check(cold_sample.phase == Core.Phase.IGNITING, "fully extinguished reengagement still requires ignition")
	_near(Core.evaluate(0.0, cold_sample, true, config).additional_gross_thrust_n, 0.0, 0.0,
		"cold ignition does not revive residual thrust")


func _test_analytical_lag_and_fuel() -> void:
	var config: Dictionary = Core.example_config()
	var analytic_a: float = 1.0 - exp(-1.0 / float(config.rise_tau_s))
	var analytic_fuel: float = config.additional_fuel_kg_s \
		* (1.0 - config.rise_tau_s * (1.0 - exp(-1.0 / float(config.rise_tau_s))))
	var fine: Dictionary = _lag_run(240)
	var coarse: Dictionary = _lag_run(60)
	var medium: Dictionary = _lag_run(120)
	_near(fine.intensity, analytic_a, 3.0e-9, "RK4 matches analytic first-order rise")
	_near(fine.fuel_kg, analytic_fuel, 1.0e-11, "stage-integrated fuel matches analytic burn integral")
	_check(absf(medium.intensity - analytic_a) < absf(coarse.intensity - analytic_a) / 10.0,
		"step halving shows fourth-order refinement for smooth law")
	var state: Dictionary = _lit(config, 1.0)
	var fuel: float = 0.0
	for _tick: int in 240:
		var result: Dictionary = _one_interval(state, _command(0.0), _permits(), config)
		state = result.state
		fuel += result.fuel_used_kg
	_near(state.intensity, exp(-1.0 / float(config.fall_tau_s)), 1.0e-9,
		"RK4 matches analytic extinction tail")
	_near(fuel, config.additional_fuel_kg_s * config.fall_tau_s \
		* (1.0 - exp(-1.0 / float(config.fall_tau_s))), 1.0e-11,
		"soft-tail fuel integral is accounted for")


func _replay(state: Dictionary, config: Dictionary) -> Dictionary:
	var accepted: Dictionary = state.duplicate(true)
	var events: Array = []
	var fuel: float = 0.0
	for tick: int in 160:
		var request: float = 1.0 if tick < 100 else 0.0
		var result: Dictionary = _one_interval(accepted, _command(request), _permits(), config)
		accepted = result.state
		events.append_array(result.events)
		fuel += result.fuel_used_kg
	return {"state": accepted, "events": events, "fuel_kg": fuel}


func _test_restore_and_independent_engines() -> void:
	var config: Dictionary = Core.example_config()
	var state: Dictionary = Core.initial_state(config)
	for _tick: int in 17:
		state = _one_interval(state, _command(), _permits(), config).state
	_check(state.phase == Core.Phase.IGNITING, "checkpoint fixture is mid-ignition")
	var checkpoint: PackedByteArray = var_to_bytes(state)
	var replay_a: Dictionary = _replay(state, config)
	var restored: Dictionary = bytes_to_var(checkpoint)
	var replay_b: Dictionary = _replay(restored, config)
	_check(var_to_bytes(replay_a) == var_to_bytes(replay_b),
		"restored accepted state produces identical trace result/events/fuel in same engine")
	_check(var_to_bytes(state) == checkpoint, "replay does not mutate checkpoint input")
	var left: Dictionary = Core.initial_state(config)
	var right: Dictionary = Core.initial_state(config)
	var right_before := var_to_bytes(right)
	for _tick: int in 120:
		left = _one_interval(left, _command(), _permits(), config).state
	_check(left.phase == Core.Phase.LIT and left.intensity > 0.0, "left engine reaches burn")
	_check(var_to_bytes(right) == right_before, "independent right engine stays untouched")
	var left_sample: Dictionary = Core.freeze_sample(left, _command(), _permits(), config)
	var output: Dictionary = Core.evaluate(left.intensity, left_sample, true, config)
	var before := var_to_bytes(output)
	output.additional_loads_frd[0] = -123.0
	_check(var_to_bytes(Core.evaluate(left.intensity, left_sample, true, config)) == before,
		"stage output does not alias future stage result")
