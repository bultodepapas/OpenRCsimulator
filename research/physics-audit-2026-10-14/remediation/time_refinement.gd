## VAL-AUD-R11 numerical refinement, outside production; not a physical validation.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const RB := preload("res://physics/rigid_body.gd")
const RATES := [120, 240, 480, 960]
const SECONDS := 3
var failures := 0

func _initialize() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("--out must name a fresh JSON")
		quit(1)
		return
	var report := {format = "openrc-audit-time-refinement-v1", solver_sha256 = Log.solver_identity(),
		godot = Engine.get_version_info(), rates_hz = RATES, duration_s = SECONDS, observation_hz = 30,
		method = "Same fresh body/internal state and held trim throttle. Post-conditioning control increment [roll=.15,pitch=.10,yaw=.20] during [0.5,1.0) seconds, zero increment otherwise. Event times align on every grid. Compare 30 Hz body observations with 960 Hz; reference is a numerical refinement, not exact truth. Sampled servos/wake mean the complete session is not claimed fourth order.", aircraft = []}
	for name in ["jensen_ugly_stik_60", "sebart_avanti_s_a200"]:
		var runs: Array = []
		var initial := PackedByteArray()
		for hz: int in RATES:
			Engine.physics_ticks_per_second = hz
			var s := Flight.new()
			s.input_enabled = false
			s.crash_auto_restart = false
			s.setup("res://data/aircraft/" + name + ".json")
			s.set_start_altitude(300.0)
			s.reset()
			var identity := var_to_bytes([s.sim.state, s.sim.aux, s.sim.continuous, s.sim.modes, s.sim.inputs])
			if runs.is_empty(): initial = identity
			var initial_equal := identity == initial
			if not initial_equal or not s.is_flyable(): failures += 1
			var initial_inputs: PackedFloat64Array = s.sim.inputs.duplicate()
			var row := {rate_hz = hz, dt_s = s.sim.dt(), initial_equal = initial_equal,
				aircraft_identity = s.aircraft.get("input_identity", {}), observations = [s.sim.state.duplicate()],
				initial_inputs = initial_inputs, initial_state = s.sim.state.duplicate(),
				initial_aux = s.sim.aux.duplicate(), initial_continuous = s.sim.continuous.duplicate()}
			for tick in hz * SECONDS:
				s.sim.inputs = initial_inputs.duplicate()
				if tick >= hz / 2 and tick < hz:
					s.sim.inputs[0] += 0.15
					s.sim.inputs[1] += 0.10
					s.sim.inputs[2] += 0.20
				s.sim.step()
				if not s.sim.fault_reason.is_empty() or s.sim.tick != tick + 1: break
				if s.sim.tick % (hz / 30) == 0: row.observations.append(s.sim.state.duplicate())
			row.completed_ticks = s.sim.tick
			row.fault = s.sim.fault_reason
			row.complete = s.sim.tick == hz * SECONDS and s.sim.fault_reason.is_empty()
			if not row.complete: failures += 1
			runs.append(row)
			s.free()
		var comparisons: Array = []
		for index in RATES.size() - 1:
			comparisons.append({rate_hz = RATES[index], versus_960_hz = _difference(runs[index], runs[-1]),
				versus_next_grid = _difference(runs[index], runs[index + 1])})
		report.aircraft.append({name = name, runs = runs, comparisons = comparisons})
		print(name, " ", JSON.stringify(comparisons))
	report.source_unchanged = report.solver_sha256 == Log.solver_identity()
	if not report.source_unchanged: failures += 1
	report.failures = failures
	report.ok = failures == 0
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	quit(0 if report.ok else 1)

func _difference(a: Dictionary, b: Dictionary) -> Dictionary:
	if a.observations.size() != b.observations.size():
		failures += 1
		return {ok = false, error = "incomplete comparison"}
	var result := {ok = true, max_position_norm_m = 0.0, max_velocity_norm_mps = 0.0,
		max_rate_norm_radps = 0.0, max_attitude_angle_rad = 0.0}
	for index in a.observations.size():
		var first: PackedFloat64Array = a.observations[index]
		var second: PackedFloat64Array = b.observations[index]
		result.max_position_norm_m = maxf(result.max_position_norm_m, _norm_difference(first, second, RB.POS))
		result.max_velocity_norm_mps = maxf(result.max_velocity_norm_mps, _norm_difference(first, second, RB.VEL))
		result.max_rate_norm_radps = maxf(result.max_rate_norm_radps, _norm_difference(first, second, RB.RATE))
		var dot := 0.0
		for k in 4: dot += first[RB.ATT + k] * second[RB.ATT + k]
		var sign_b := -1.0 if dot < 0.0 else 1.0
		var minus_sq := 0.0
		var plus_sq := 0.0
		for k in 4:
			var delta := first[RB.ATT + k] - sign_b * second[RB.ATT + k]
			var sum_ := first[RB.ATT + k] + sign_b * second[RB.ATT + k]
			minus_sq += delta * delta
			plus_sq += sum_ * sum_
		result.max_attitude_angle_rad = maxf(result.max_attitude_angle_rad, 4.0 * atan2(sqrt(minus_sq), sqrt(plus_sq)))
	return result

func _norm_difference(a: PackedFloat64Array, b: PackedFloat64Array, offset: int) -> float:
	var sum_ := 0.0
	for i in 3: sum_ += (a[offset + i] - b[offset + i]) * (a[offset + i] - b[offset + i])
	return sqrt(sum_)
