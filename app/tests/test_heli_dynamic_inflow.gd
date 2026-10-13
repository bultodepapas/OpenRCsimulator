# HELI-04-R1: transient induced velocity and known-seam numerical qualification.
extends SceneTree

const Dynamic = preload("res://physics/rotorcraft/dynamic_inflow.gd")
const Equilibrium = preload("res://physics/rotorcraft/inflow.gd")
const RK = preload("res://physics/integrator.gd")
const M = preload("res://physics/math3d.gd")
const STEP: float = 1.0 / 240.0
var checks: int = 0
var failures: int = 0
var report: Array = []


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	_lag()
	_residual_wake()
	_invalid()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--oracle="):
			_oracle(argument.substr(9))
	print("HELI-04-R1 dynamic inflow: %d checks, %d failed" % [checks, failures])
	if not report.is_empty():
		print("DYNAMIC_QUALIFICATION=" + JSON.stringify(report))
	quit(1 if failures else 0)


func _state(velocity: float) -> PackedFloat64Array:
	var state := PackedFloat64Array()
	state.resize(14)
	state[6] = 1.0 # Identity body attitude; the existing RK4 core normalizes it.
	state[13] = velocity
	return state


func _lag() -> void:
	var r: Dictionary = Dynamic.derivative(0.0, 4.0, 0.775, 4.0, 0.1)
	check("dimensional lag finite", r.ok)
	close("hover lag radius/flow conversion", r.tau, 0.849 * 0.775 / 16.0)
	close("lag derivative dimensions close", r.rate * r.tau, 4.0)
	close("equilibrium remains still", Dynamic.derivative(4.0, 4.0, 0.775, 4.0, 0.1).rate, 0.0)
	var errors := PackedFloat64Array()
	for divisor: int in [1, 2, 4]:
		var dt: float = STEP / float(divisor)
		var state: PackedFloat64Array = _state(0.0)
		var rate := func(stage: PackedFloat64Array, _t: float) -> PackedFloat64Array:
			var d := PackedFloat64Array()
			d.resize(14)
			d[13] = Dynamic.derivative(stage[13], 4.0, 0.775, 4.0, 0.1).rate
			return d
		for tick: int in range(24 * divisor):
			state = RK.rk4_step_at(state, float(tick) * dt, dt, rate)
		var exact: float = 4.0 * (1.0 - M.exp_(-0.1 / r.tau))
		errors.append(absf(state[13] - exact))
		check("RK4 agrees with independent exponential", errors[-1] < 2e-6)
		check("stationary rigid body preserved", state[6] == 1.0 and state[0] == 0.0 and state[10] == 0.0)
	check("smooth fixed-target RK4 refinement order", errors[0] / errors[1] > 14.0 and errors[1] / errors[2] > 14.0)
	var coupled: Dictionary = Dynamic.evaluate(1.5, 80.4, 1.225, 0.775, -0.4, 2.0, 0.1)
	var mirrored: Dictionary = Dynamic.evaluate(-1.5, -80.4, 1.225, 0.775, 0.4, 2.0, 0.1)
	check("signed stage response accepted", coupled.ok and mirrored.ok)
	close("stage flow responds to current vi", coupled.effective_flow, M.sqrt_(4.0 + 1.1 * 1.1))
	close("stage signed derivative mirror", mirrored.rate, -coupled.rate)
	close("stage signed tau mirror", mirrored.tau, coupled.tau)


func _residual_wake() -> void:
	var stopped: Dictionary = Dynamic.evaluate(3.0, 0.0, 1.225, 0.775, 0.0, 0.0, 0.1)
	check("zero-thrust wake decays rather than freezing", stopped.ok and stopped.target == 0.0 and stopped.rate < 0.0)
	var state: PackedFloat64Array = _state(3.0)
	var rate := func(stage: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var d := PackedFloat64Array()
		d.resize(14)
		d[13] = Dynamic.evaluate(stage[13], 0.0, 1.225, 0.775, 0.0, 0.0, 0.1).rate
		return d
	for tick: int in range(120):
		state = RK.rk4_step_at(state, float(tick) * STEP, STEP, rate)
	# Before the flow floor is active, dv/dt=-4 v^2/(0.849 R).
	var exact: float = 3.0 / (1.0 + 4.0 * 3.0 * 0.5 / (0.849 * 0.775))
	close("zero-thrust decay matches rational analytic solution", state[13], exact, 2e-6)
	var empty: Dictionary = Dynamic.evaluate(0.0, 0.0, 1.225, 0.775, 0.0, 0.0, 0.1)
	check("zero state remains finite with explicit floor", empty.ok and empty.rate == 0.0 and is_finite(empty.tau))
	close("floor limits longest lag", empty.tau, 0.849 * 0.775 / 0.4)


func _invalid() -> void:
	for bad: float in [NAN, INF, -INF]:
		check("nonfinite lag velocity refused", not Dynamic.derivative(bad, 0.0, 0.775, 4.0, 0.1).ok)
		check("nonfinite radius refused", not Dynamic.derivative(0.0, 0.0, bad, 4.0, 0.1).ok)
		check("nonfinite target-stage velocity refused", not Dynamic.evaluate(bad, 80.4, 1.225, 0.775, 0.0, 0.0, 0.1).ok)
	check("zero flow floor refused", not Dynamic.derivative(0.0, 0.0, 0.775, 4.0, 0.0).ok)
	check("negative effective flow refused", not Dynamic.derivative(0.0, 0.0, 0.775, -4.0, 0.1).ok)
	check("invalid density refused by joint stage", not Dynamic.evaluate(1.0, 80.4, 0.0, 0.775, 0.0, 0.0, 0.1).ok)
	check("overflowing derived lag refused", not Dynamic.derivative(0.0, 0.0, 1e308, 0.0, 1e-308).ok)


func _controls(profile: Dictionary, time: float) -> Dictionary:
	if profile.interpolation == "step":
		return profile.before.duplicate() if time < profile.step_time_s else profile.after.duplicate()
	var fraction: float = clampf((time - profile.start_time_s) / (profile.end_time_s - profile.start_time_s), 0.0, 1.0)
	var controls: Dictionary = {}
	for key: String in ["thrust_n", "climb_mps", "crossflow_mps"]:
		controls[key] = float(profile.start[key]) + (float(profile.end[key]) - float(profile.start[key])) * fraction
	return controls


func _event_controls(fixture: Dictionary, event: Dictionary, before: bool) -> Dictionary:
	if event.get("control") == "step" or event.get("event_kind") == "forcing_step":
		return fixture.profile.before.duplicate() if before else fixture.profile.after.duplicate()
	var controls: Dictionary = _controls(fixture.profile, event.time_s)
	var c: Dictionary = fixture.constants
	var hover: float = M.sqrt_(absf(controls.thrust_n) / (2.0 * c.density_kg_m3 * PI * c.radius_m * c.radius_m))
	var sense: float = -1.0 if event.direction == "increasing" else 1.0
	if not before:
		sense = -sense
	var epsilon: float = event.get("epsilon_normalized", 1e-9 if event.boundary == "C" else 1e-10)
	controls.crossflow_mps = hover * (event.threshold_normalized + sense * epsilon)
	return controls


func _fixture_rate(fixture: Dictionary, state: PackedFloat64Array, time: float, override: Dictionary) -> PackedFloat64Array:
	var controls: Dictionary = _controls(fixture.profile, time) if override.is_empty() else override
	var c: Dictionary = fixture.constants
	var response: Dictionary = Dynamic.evaluate(state[13], controls.thrust_n, c.density_kg_m3, c.radius_m,
		controls.climb_mps, controls.crossflow_mps, c.velocity_floor_mps, c.height_over_radius, c.loss, c.instability)
	if c.effective_flow_mode == "fixed":
		response = Dynamic.derivative(state[13], response.target, c.radius_m, c.fixed_effective_speed_mps, c.velocity_floor_mps)
	var d := PackedFloat64Array()
	d.resize(14)
	d[13] = response.rate
	return d


# This is a fixture-only forcing driver. A runtime state-dependent event
# detector is not provided by the fixture's predeclared crossing times.
func _trajectory(fixture: Dictionary, dt: float, split: bool, local: bool) -> Array:
	var state: PackedFloat64Array = _state(fixture.initial_vi_mps)
	var trajectory: Array = [state[13]]
	var events: Array = fixture.event_splits.duplicate()
	if fixture.profile.interpolation == "step" and events.is_empty():
		events.append({"time_s": fixture.profile.step_time_s, "control": "step"})
	if not split:
		events = []
	var ticks: int = int(roundf(fixture.duration_s / dt))
	for tick: int in range(ticks):
		var begin: float = float(tick) * dt
		var end: float = float(tick + 1) * dt
		var interior: Dictionary = {}
		var near: bool = false
		for event: Dictionary in events:
			if event.time_s > begin and event.time_s < end:
				interior = event
			if end >= event.time_s - dt - 1e-14 and begin <= event.time_s + dt + 1e-14:
				near = true
		var times: PackedFloat64Array = PackedFloat64Array([begin, end])
		if local and near:
			if not interior.is_empty():
				times = PackedFloat64Array([begin, 0.5 * (begin + interior.time_s), interior.time_s, 0.5 * (interior.time_s + end), end])
			else:
				times = PackedFloat64Array([begin, begin + 0.25 * dt, begin + 0.5 * dt, begin + 0.75 * dt, end])
		elif not interior.is_empty():
			times = PackedFloat64Array([begin, interior.time_s, end])
		for segment: int in range(times.size() - 1):
			var start_override: Dictionary = {}
			var end_override: Dictionary = {}
			for event: Dictionary in events:
				if absf(times[segment] - event.time_s) < 1e-14:
					start_override = _event_controls(fixture, event, false)
				if absf(times[segment + 1] - event.time_s) < 1e-14:
					end_override = _event_controls(fixture, event, true)
			var start: float = times[segment]
			var stop: float = times[segment + 1]
			var rate := func(stage: PackedFloat64Array, time: float) -> PackedFloat64Array:
				var override: Dictionary = {}
				if absf(time - start) < 1e-14:
					override = start_override
				elif absf(time - stop) < 1e-14:
					override = end_override
				return _fixture_rate(fixture, stage, time, override)
			state = RK.rk4_step_at(state, start, stop - start, rate)
		trajectory.append(state[13])
	return trajectory


func _oracle(path: String) -> void:
	var json: JSON = JSON.new()
	check("dynamic oracle parses", json.parse(FileAccess.get_file_as_string(path)) == OK)
	if typeof(json.data) != TYPE_DICTIONARY:
		check("dynamic oracle is object", false)
		return
	check("dynamic oracle format", json.data.get("format") == "openrc-dynamic-inflow-oracle-v1")
	var unsplit_worst: float = 0.0
	var qualified_worst: float = 0.0
	for fixture: Dictionary in json.data.fixtures:
		var raw: Array = _trajectory(fixture, STEP, false, false)
		var qualified: Array = _trajectory(fixture, STEP, true, true)
		var max_raw: float = 0.0
		var max_qualified: float = 0.0
		for sample: Dictionary in fixture.samples:
			var index: int = int(roundf(sample.time_s / STEP))
			var error: float = absf(float(qualified[index]) - sample.expected_vi_mps)
			check("known-seam RK4 vs independent transient oracle " + fixture.name, error <= 1e-3)
			max_qualified = maxf(max_qualified, error)
			max_raw = maxf(max_raw, absf(float(raw[index]) - sample.expected_vi_mps))
			if sample.expected_lambda != null:
				close("diagnostic ratio uses dimensional state " + fixture.name,
					float(qualified[index]) / (fixture.constants.omega_rad_s * fixture.constants.radius_m), sample.expected_lambda, 2e-5)
		unsplit_worst = maxf(unsplit_worst, max_raw)
		qualified_worst = maxf(qualified_worst, max_qualified)
		report.append({"fixture": fixture.name, "raw_peak_error_mps": max_raw, "known_seam_refined_peak_error_mps": max_qualified})
	check("raw 240 Hz failure is exposed", unsplit_worst > 1e-3)
	check("localized known-seam procedure meets numerical fixture gate", qualified_worst <= 1e-3)
