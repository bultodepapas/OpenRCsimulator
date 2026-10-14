extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Skids = preload("res://physics/rotorcraft/skid_contact.gd")

const WARMUP_TICKS := 256
const SAMPLE_TICKS := 8000
const LANDING_TICKS := 7200

var _session: Node
var _landing_integral: float = 0.0
var _hover_throttle: float = 0.0
var _failed: bool = false
var _failure_messages: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_session = Session.new()
	_session.input_enabled = false
	_session.physics_enabled = false
	_session.external_controller_selection = true
	root.add_child(_session)
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
	if not field.ok or not _session.setup() or not _session.set_field(field.field) or not _session.reset():
		printerr("ERROR: session benchmark setup failed")
		quit(1)
		return

	var hover: Dictionary = _measure("hover", false)
	if not hover.ok:
		_failed = true
	var ground: Dictionary = {}
	if not _session.reset():
		_failed = true
		_failure_messages.append("reset before ground regime failed")
	else:
		_hover_throttle = _session.commands.throttle
		_landing_integral = 0.0
		var landing_ok := true
		for tick: int in LANDING_TICKS:
			_update_landing_input()
			_session.sim.step()
			if not _session.is_flyable():
				landing_ok = false
				break
		var landing_state: PackedFloat64Array = _session.sim.state
		var altitude_m: float = -landing_state[2]
		var vertical_speed_m_s: float = landing_state[5]
		if not landing_ok or altitude_m < 0.08 or altitude_m > 0.15 or absf(vertical_speed_m_s) >= 0.08:
			_failed = true
			_failure_messages.append("ground precondition did not reach the existing session suite landing envelope")
		ground = _measure("ground_contact", true)
		if not ground.ok:
			_failed = true

	var report := {
		"format": "openrc-heli-current-session-percentiles-v1",
		"engine": Engine.get_version_info().string,
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"fixed_dt_s": _session.sim.dt(),
		"sample_ticks_per_regime": SAMPLE_TICKS,
		"warmup_ticks_per_regime": WARMUP_TICKS,
		"measurement_scope": "Time.get_ticks_usec around Simulation.step; includes the complete helicopter joint RK4 session stage and stepped callbacks, excludes render, physics-frame scheduling, device polling, and command updates.",
		"hover": hover,
		"ground_contact_condition": "Powered, pilot-compensated contact after the existing 7200-tick descent procedure; not rotor-off full-weight support and not a ground-start test.",
		"ground_contact": ground,
		"failure_messages": _failure_messages,
		"ok": not _failed
	}
	var output_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if not output_path.is_empty():
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			printerr("ERROR: cannot write percentile report")
			quit(1)
			return
		output.store_string(JSON.stringify(report, "	", true, true) + "
")
	print(JSON.stringify(report, "	", true, true))
	_session.free()
	quit(1 if _failed else 0)

func _measure(name: String, keep_landing_input: bool) -> Dictionary:
	var control_enabled: bool = keep_landing_input
	for tick: int in WARMUP_TICKS:
		if control_enabled:
			_update_landing_input()
		_session.sim.step()
		if not _session.is_flyable():
			_failed = true
			return {"ok": false, "fault": "session not flyable during warmup"}
	var before_contact: Dictionary = _contact_snapshot()
	var samples: Array[float] = []
	var started_tick: int = _session.sim.tick
	var altitude_before_m: float = -_session.sim.state[2]
	for tick: int in SAMPLE_TICKS:
		if control_enabled:
			_update_landing_input()
		var started_usec: int = Time.get_ticks_usec()
		_session.sim.step()
		var elapsed_usec: int = Time.get_ticks_usec() - started_usec
		samples.append(float(elapsed_usec))
		if not _session.is_flyable():
			_failed = true
			_failure_messages.append(name + " became non-flyable at sample tick " + str(tick))
			break
	var ended_tick: int = _session.sim.tick
	var sorted_samples: Array[float] = samples.duplicate()
	sorted_samples.sort()
	if sorted_samples.is_empty():
		return {"ok": false, "fault": "no timing samples"}
	var sum_usec: float = 0.0
	var over_500: int = 0
	var over_frame_budget: int = 0
	for sample: float in sorted_samples:
		sum_usec += sample
		if sample > 500.0:
			over_500 += 1
		if sample > 1.0e6 / float(Engine.physics_ticks_per_second):
			over_frame_budget += 1
	var after_contact: Dictionary = _contact_snapshot()
	var first_state: PackedFloat64Array = _session.sim.state.duplicate()
	first_state.append_array(_session.sim.continuous)
	return {
		"ok": samples.size() == SAMPLE_TICKS and _session.is_flyable(),
		"sample_count": samples.size(),
		"start_tick": started_tick,
		"end_tick": ended_tick,
		"percentile_method": "nearest rank, ceil(p*n)-1",
		"samples_us": samples,
		"p50_us": _quantile(sorted_samples, 0.50),
		"p95_us": _quantile(sorted_samples, 0.95),
		"p99_us": _quantile(sorted_samples, 0.99),
		"mean_us": sum_usec / float(sorted_samples.size()),
		"max_us": sorted_samples[-1],
		"over_500_us_count": over_500,
		"over_500_us_fraction": float(over_500) / float(sorted_samples.size()),
		"over_240hz_budget_count": over_frame_budget,
		"over_240hz_budget_fraction": float(over_frame_budget) / float(sorted_samples.size()),
		"altitude_start_m": altitude_before_m,
		"vertical_speed_end_m_s": _session.sim.state[5],
		"main_shaft_rpm_end": _session.sim.continuous[0] * 60.0 / (2.0 * PI),
		"contact_before": before_contact,
		"contact_after": after_contact,
		"end_state_sha256": _hash(first_state.to_byte_array())
	}

func _update_landing_input() -> void:
	var down_target: float = clampf((-_session.sim.state[2] - 0.10) * 0.3, 0.0, 0.3)
	var error: float = down_target - _session.sim.state[5]
	_landing_integral = clampf(_landing_integral + 0.03 * error * _session.sim.dt(), -0.1, 0.1)
	_session.commands.throttle = clampf(_hover_throttle - 0.07 * error - _landing_integral, 0.25, 0.75)
	_session.sim.inputs[3] = _session.commands.throttle

func _contact_snapshot() -> Dictionary:
	var result: Dictionary = Skids.evaluate(_session.sim.state, _session.aircraft.skids, _session.ground_surfaces)
	return {
		"ok": result.get("ok", false),
		"max_depth_m": result.get("max_depth_m", -1.0),
		"body_vertical_load_n": result.loads[2] if result.get("ok", false) else 0.0,
		"sim_state_z_down_m": _session.sim.state[2]
	}

func _quantile(sorted_samples: Array[float], q: float) -> float:
	var index: int = clampi(int(ceil(float(sorted_samples.size()) * q)) - 1, 0, sorted_samples.size() - 1)
	return sorted_samples[index]

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
