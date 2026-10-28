## NK-3 experimental X-Cell native VehicleModel.stage and paired-tape oracle.
## The shared Simulation owns the same stop policy, controls and observers.
## Source coverage does not by itself admit the helicopter into the app.
extends "helicopter_oracle.gd"

const HeliStageAdapter := preload("res://sim/native/helicopter_stage_adapter.gd")
const HeliWeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const HeliWeatherField := preload("res://physics/wind_field.gd")


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/rotorcraft/simulation_step_adapter.gd", "res://sim/vehicle_model.gd",
			"res://physics/wind_config.gd", "res://physics/wind_field.gd", "res://sim/environment.gd",
			"res://data/field_loader.gd", "res://physics/ground_surfaces.gd"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-helicopter-stage-oracle v1"
	_report.reference_start_refusals = []
	_report.helicopter_stage = {cases = [], trajectories = [], replays = []}
	var ticks: int = int(_options.get("ticks", "16"))
	if _states < 16 or ticks < 1:
		_failures.append("helicopter stage needs at least 16 states per case and one tape tick")
		return
	var loaded_field: Dictionary = FieldLoader.load_from()
	if not loaded_field.ok:
		_failures.append("default field failed to load")
		return
	var weather_ids := ["calm", "steady", "crosswind", "gusty", "updraft", "hot-high", "cool-dense"]
	for start: String in ["airborne", "ground"]:
		for weather_id: String in weather_ids:
			var session := _make_session(loaded_field.field, start, weather_id)
			if session == null: continue
			var prepared := HeliStageAdapter.prepare(session, _native)
			if not prepared.get("ok", false):
				_failures.append("helicopter native stage %s/%s refused: %s" % [start, weather_id, str(prepared.get("error", ""))])
				session.free()
				continue
			_check_session(session, start, weather_id, _states)
			if weather_id == "calm":
				_check_malformed_stages(session, start)
				_check_stage_refusals(session, start)
			_report.helicopter_stage.cases.append({start = start, weather = weather_id, states = _states,
				seeded_only = weather_id == "hot-high", continuous_size = session.sim.continuous.size()})
			session.free()
			if weather_id != "hot-high":
				_check_trajectory(loaded_field.field, start, weather_id, ticks)
	_check_trajectory(loaded_field.field, "airborne", "crosswind", ticks, true)
	for start: String in ["airborne", "ground"]:
		_check_checkpoint_replay(loaded_field.field, start, ticks)
	if _report.helicopter_stage.cases.size() != 14:
		_failures.append("helicopter stage start/weather matrix incomplete")
	if _report.helicopter_stage.trajectories.size() != 13:
		_failures.append("helicopter supported start/weather and stop trajectories incomplete")
	if _report.helicopter_stage.replays.size() != 2:
		_failures.append("helicopter checkpoint replay matrix incomplete")
	if _report.reference_start_refusals.size() != 2:
		_failures.append("hot-high source start refusals were not both recorded")


## Override the component oracle's sampler. The native evaluator performs its
## own stage-time wind query and presents the actual VehicleModel.stage shape.
func _compare_stage(session: Node, body: PackedFloat64Array, continuous: PackedFloat64Array,
		time: float, label: Variant) -> bool:
	session._stage_failure = ""
	var reference: Dictionary = session._stage(body, continuous, time)
	var tick: Dictionary = HeliStageAdapter.tick(session, session.sim.inputs)
	var tick_ok: bool = _native.set_heli_tick_context(tick)
	var native: Dictionary = _native.stage(body, continuous, time) if tick_ok else {}
	var reference_ok := not reference.is_empty()
	var native_ok := not native.is_empty()
	var inputs := [label, body, continuous, time, tick, session._stage_failure, _native.heli_last_failure()]
	_compare("helicopter_stage_validity", PackedFloat64Array([1.0 if reference_ok else 0.0]),
		PackedFloat64Array([1.0 if native_ok else 0.0]), inputs)
	if not reference_ok or not native_ok:
		if reference_ok != native_ok: _tally("helicopter_stage", "validity_mismatches")
		if not reference_ok and not native_ok:
			_compare("helicopter_stage_failure", str(session._stage_failure), str(_native.heli_last_failure()), inputs)
		return false
	for key: String in ["loads", "body_derivative", "derivative", "rotor_momentum"]:
		_compare("helicopter_stage_" + key, reference[key], native.get(key), inputs)
	_compare("helicopter_stage_bytes", var_to_bytes(reference), var_to_bytes(native), inputs)
	_tally("helicopter", "accepted")
	return true


func _check_stage_refusals(session: Node, start: String) -> void:
	var model := HeliStageAdapter.snapshot(session)
	var weather := HeliStageAdapter.weather_snapshot(session)
	if weather.is_empty():
		_failures.append("reference helicopter weather snapshot missing: " + start)
		return
	var bad_weather: Dictionary = weather.duplicate(true)
	bad_weather.has_turbulence = true
	var refused: Dictionary = _native.prepare_heli_stage(model, bad_weather)
	_compare("helicopter_weather_refusal", PackedFloat64Array([0.0]),
		PackedFloat64Array([1.0 if refused.get("ok", false) else 0.0]), [start, "turbulence"])
	if not _native.stage(session.sim.state, session.sim.continuous, session.sim.time()).is_empty():
		_failures.append("failed helicopter prepare retained a native stage: " + start)
	bad_weather = weather.duplicate(true)
	bad_weather.atmosphere[1] *= 1.01
	refused = _native.prepare_heli_stage(model, bad_weather)
	_compare("helicopter_weather_refusal", PackedFloat64Array([0.0]),
		PackedFloat64Array([1.0 if refused.get("ok", false) else 0.0]), [start, "mismatched_density"])
	for preset: String in ["standard-column", "spatial-gusty-v1"]:
		var field: Dictionary = HeliWeatherField.build(HeliWindConfig.preset(preset))
		if not field.get("ok", false):
			_failures.append("helicopter weather refusal fixture did not prepare: " + preset)
			continue
		refused = _native.prepare_heli_stage(model, HeliWeatherAdapter.snapshot(field.field))
		_compare("helicopter_weather_refusal", PackedFloat64Array([0.0]),
			PackedFloat64Array([1.0 if refused.get("ok", false) else 0.0]), [start, preset])
	if not HeliStageAdapter.prepare(session, _native).get("ok", false):
		_failures.append("helicopter native stage could not recover after refusal: " + start)


static func _tape(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs,
		sim.last_loads, sim.modes, sim.last_events, session.shaft_phase, session.power, session.crash,
		session.flight_mode, session.trainer_enabled, session.zero_drive_hold, session.commands])


func _check_trajectory(field: Dictionary, start: String, weather_id: String, ticks: int, stop := false) -> void:
	var label := "%s/%s%s" % [start, weather_id, "/rotor-stop" if stop else ""]
	var reference := _make_session(field, start, weather_id)
	var native := _make_session(field, start, weather_id)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	if stop:
		# Same bounded low-RPM, zero-drive fixture as HELI-17b, on actual
		# accepted session body and shared Simulation event policy.
		for session: Node in [reference, native]:
			session.sim.continuous[0] = 0.001
			session.power.armed = false
			session.zero_drive_hold = true
			session.trainer_enabled = false
			session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	var installed := HeliStageAdapter.install(native, _native)
	if not installed.get("ok", false):
		_failures.append("helicopter trajectory %s prepare refused: %s" % [label, str(installed.get("error", ""))])
		reference.free()
		native.free()
		return
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var complete := true
	var ran := 0
	var stopped := false
	var changed_mode := false
	var changed_trainer := false
	var held_drive := false
	var first_divergence := -1
	if not _compare("helicopter_trajectory_tick", _tape(reference), _tape(native), [label, 0]): first_divergence = 0
	for i: int in ticks:
		if not stop and i == ticks / 3:
			reference.trainer_enabled = false
			native.trainer_enabled = false
			changed_trainer = true
		if not stop and i == ticks / 2:
			for session: Node in [reference, native]:
				if not session.request_flight_mode(): session.request_flight_mode()
			changed_mode = reference.flight_mode == "idle_up" and native.flight_mode == "idle_up"
		if not stop and i == (3 * ticks) / 4:
			held_drive = reference.set_drive_hold(true) and native.set_drive_hold(true)
		var inputs: PackedFloat64Array = reference.sim.inputs.duplicate()
		if not stop:
			inputs[0] = 0.01 if i % 40 < 20 else -0.01
			inputs[1] = 0.01 if i % 60 < 30 else -0.01
			inputs[2] = 0.01 if i % 32 < 16 else -0.01
		reference.sim.inputs = inputs.duplicate()
		native.sim.inputs = inputs.duplicate()
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		var healthy: bool = reference.sim.tick == i + 1 and native.sim.tick == i + 1 and bool(installed.context.ok) \
			and not reference.sim.paused and not native.sim.paused and reference.sim.fault_reason.is_empty() \
			and native.sim.fault_reason.is_empty() and reference.crash.is_empty() and native.crash.is_empty()
		var covered: bool = native.sim.model.stage == Callable(_native, "stage") and native.sim.model.pre_tick == installed.wrapped \
			and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		if not healthy or not covered:
			_failures.append("helicopter trajectory %s tick %d failed or lacked native coverage: %s/%s" %
				[label, i + 1, reference.sim.fault_reason, native.sim.fault_reason])
			complete = false
			break
		previous = stats
		ran += 1
		for event: Dictionary in reference.sim.last_events:
			if event.get("type") == "rotor_stop":
				stopped = true
				if reference.sim.continuous[0] != 0.0 or native.sim.continuous[0] != 0.0:
					_failures.append("located helicopter stop did not settle the rotor: " + label)
		if not _compare("helicopter_trajectory_tick", _tape(reference), _tape(native), [label, i + 1]) and first_divergence < 0:
			first_divergence = i + 1
	_report.helicopter_stage.trajectories.append({name = label, requested_ticks = ticks, ticks_run = ran,
		complete = complete and ran == ticks, first_divergence = first_divergence, stop_expected = stop,
		stop_observed = stopped, changed_mode = changed_mode, changed_trainer = changed_trainer,
		held_drive = held_drive, native_stage_calls = int(previous.get("stage_calls", 0)),
		native_context_calls = int(previous.get("context_calls", 0))})
	if first_divergence >= 0: _failures.append("helicopter trajectory %s diverged at tick %d" % [label, first_divergence])
	if stop and not stopped: _failures.append("helicopter stop trajectory did not locate rotor stop: " + label)
	if not stop and ticks >= 4 and (not changed_mode or not changed_trainer or not held_drive):
		_failures.append("helicopter trajectory missed a requested control boundary: " + label)
	reference.free()
	native.free()


func _check_checkpoint_replay(field: Dictionary, start: String, ticks: int) -> void:
	var reference := _make_session(field, start, "calm")
	if reference == null: return
	var total: int = maxi(4, ticks)
	var midpoint: int = total / 2
	var snapshot := {}
	var midpoint_tape := PackedByteArray()
	var continuation: Array[Dictionary] = []
	for i: int in total:
		var inputs := PackedFloat64Array([0.01 if i % 4 < 2 else -0.01,
			0.005 if i % 6 < 3 else -0.005, 0.0, float(reference.commands.throttle)])
		for axis: int in 4: reference.commands[["roll", "pitch", "yaw", "throttle"][axis]] = inputs[axis]
		reference.sim.inputs = inputs.duplicate()
		reference.sim.step()
		if reference.sim.tick != i + 1 or reference.sim.paused or not reference.sim.fault_reason.is_empty() \
				or not reference.crash.is_empty():
			_failures.append("helicopter reference checkpoint tape stopped: %s tick %d" % [start, i + 1])
			reference.free()
			return
		if i + 1 == midpoint:
			snapshot = reference.checkpoint()
			midpoint_tape = _tape(reference)
			if snapshot.is_empty():
				_failures.append("helicopter reference checkpoint unavailable: " + start)
				reference.free()
				return
		elif i + 1 > midpoint:
			continuation.append({inputs = inputs.duplicate(), tape = _tape(reference)})
	var native := _make_session(field, start, "calm")
	if native == null:
		reference.free()
		return
	var restored: Dictionary = native.restore_checkpoint(snapshot)
	if not restored.get("ok", false):
		_failures.append("helicopter checkpoint restore refused %s: %s" % [start, str(restored.get("errors", []))])
		reference.free()
		native.free()
		return
	var installed := HeliStageAdapter.install(native, _native)
	if not installed.get("ok", false):
		_failures.append("helicopter restored native install refused %s: %s" % [start, str(installed.get("error", ""))])
		reference.free()
		native.free()
		return
	native.sim.set_paused(false)
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var first_divergence := -1
	if not _compare("helicopter_replay_tick", midpoint_tape, _tape(native), [start, midpoint]):
		first_divergence = midpoint
	var ran := 0
	var complete := true
	for sample: Dictionary in continuation:
		var inputs: PackedFloat64Array = sample.inputs
		for axis: int in 4: native.commands[["roll", "pitch", "yaw", "throttle"][axis]] = inputs[axis]
		native.sim.inputs = inputs.duplicate()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		var covered: bool = native.sim.model.stage == Callable(_native, "stage") and native.sim.model.pre_tick == installed.wrapped \
			and int(stats.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4 \
			and int(stats.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1
		if native.sim.tick != midpoint + ran + 1 or native.sim.paused or not native.sim.fault_reason.is_empty() \
				or not native.crash.is_empty() or not bool(installed.context.ok) or not covered:
			_failures.append("helicopter checkpoint replay stopped or lacked native coverage: %s tick %d" % [start, midpoint + ran + 1])
			complete = false
			break
		previous = stats
		ran += 1
		if not _compare("helicopter_replay_tick", sample.tape, _tape(native), [start, midpoint + ran]) and first_divergence < 0:
			first_divergence = midpoint + ran
	_report.helicopter_stage.replays.append({start = start, checkpoint_tick = midpoint, requested_ticks = continuation.size(),
		ticks_run = ran, complete = complete and ran == continuation.size(), first_divergence = first_divergence,
		native_stage_calls = int(previous.get("stage_calls", 0)), native_context_calls = int(previous.get("context_calls", 0))})
	if first_divergence >= 0: _failures.append("helicopter checkpoint replay diverged: %s tick %d" % [start, first_divergence])
	reference.free()
	native.free()
