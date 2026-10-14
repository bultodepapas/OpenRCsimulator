extends SceneTree

const SessionA = preload("res://sim/helicopter_flight_session.gd")
const SessionB = preload("res://sim/helicopter_flight_session_candidate.gd")
const Field = preload("res://data/field_loader.gd")
const TICK_RATE_HZ: int = 240
const RESULT_PATH: String = "res://ground_contact_abba_raw.json"
const RESULT_MARKER: String = "GROUND_CONTACT_ABBA_RESULT:"

var _segments: Array[Dictionary] = []


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("GROUND_CONTACT_ABBA_PARSE_OK")
		quit(0)
		return
	call_deferred("_run")


func _run() -> void:
	if Engine.physics_ticks_per_second != TICK_RATE_HZ:
		_finish(false, "project fixed tick rate is not 240 Hz")
		return
	var specs: Array[Dictionary] = [
		{"name": "stoppedground", "start": "ground", "mode": "stopped", "ticks": 1200, "warmup": 120},
		{"name": "12ssoftspool", "start": "ground", "mode": "soft_spool", "ticks": 2880, "warmup": 0},
		{"name": "governedground", "start": "ground", "mode": "governed", "ticks": 1200, "warmup": 120},
		{"name": "legacyairbornehover", "start": "airborne", "mode": "airborne", "ticks": 1200, "warmup": 120},
	]
	for spec: Dictionary in specs:
		var prepared: Dictionary = _prepare_case(spec)
		if not prepared.get("ok", false):
			_finish(false, str(prepared.get("error", "case preparation failed")))
			return
		var session_a: Node = prepared.session_a
		var session_b: Node = prepared.session_b
		var checkpoint: Dictionary = prepared.checkpoint
		for pair_index: int in 2:
			var order: PackedStringArray = PackedStringArray(["A", "B"]) if pair_index == 0 else PackedStringArray(["B", "A"])
			var pair_runs: Dictionary = {}
			for label: String in order:
				var session: Node = session_a if label == "A" else session_b
				var restore: Dictionary = session.restore_checkpoint(checkpoint)
				if not restore.get("ok", false):
					_finish(false, "%s pair %d %s checkpoint restore failed: %s" % [str(spec.name), pair_index + 1, label, "; ".join(restore.get("errors", []))])
					return
				session.resume()
				if session.sim.paused or session.sim.dt() != 1.0 / float(TICK_RATE_HZ):
					_finish(false, "%s pair %d %s did not resume at exactly 240 Hz" % [str(spec.name), pair_index + 1, label])
					return
				var measured: Dictionary = _measure(session, int(spec.ticks))
				if not measured.get("ok", false):
					_finish(false, "%s pair %d %s rejected a measured tick: %s" % [str(spec.name), pair_index + 1, label, str(measured.get("error", "unknown failure"))])
					return
				pair_runs[label] = measured
			var run_a: Dictionary = pair_runs["A"]
			var run_b: Dictionary = pair_runs["B"]
			var parity: Dictionary = {}
			for key: String in ["state", "aux", "continuous", "phase"]:
				parity[key] = run_a.streams[key] == run_b.streams[key]
			var serialized_runs: Dictionary = {}
			for label: String in ["A", "B"]:
				var run: Dictionary = pair_runs[label]
				var serialized: Dictionary = {
					"elapsed_usec": run.elapsed_usec,
					"accepted_ticks": run.accepted_ticks,
					"start_tick": run.start_tick,
					"end_tick": run.end_tick,
					"final_power_phase": run.final_power_phase,
					"state_stream_sha256": _sha256(run.streams.state),
					"aux_stream_sha256": _sha256(run.streams.aux),
					"continuous_stream_sha256": _sha256(run.streams.continuous),
					"phase_stream_sha256": _sha256(run.streams.phase),
				}
				serialized_runs[label] = serialized
				_segments.append({
					"case": str(spec.name),
					"pair": pair_index + 1,
					"order": order.duplicate(),
					"variant": label,
					"accepted_ticks": run.accepted_ticks,
					"elapsed_usec": run.elapsed_usec.duplicate(),
					"start_tick": run.start_tick,
					"end_tick": run.end_tick,
					"final_power_phase": run.final_power_phase,
					"signature_sha256": {
						"state": serialized.state_stream_sha256,
						"aux": serialized.aux_stream_sha256,
						"continuous": serialized.continuous_stream_sha256,
						"phase": serialized.phase_stream_sha256,
					},
				})
			var parity_ok: bool = true
			for key: String in parity:
				parity_ok = parity_ok and bool(parity[key])
			if not parity_ok:
				_finish(false, "%s pair %d byte parity failed: %s" % [str(spec.name), pair_index + 1, JSON.stringify(parity)])
				return
			print("PAIR_OK %s #%d %s ticks=%d exact_state_aux_continuous_phase=true" % [str(spec.name), pair_index + 1, str(order), int(spec.ticks)])
		prepared.session_a.free()
		prepared.session_b.free()
	_finish(true, "")


func _prepare_case(spec: Dictionary) -> Dictionary:
	var session_a: Node = _new_session(SessionA, str(spec.start))
	var session_b: Node = _new_session(SessionB, str(spec.start))
	if session_a == null or session_b == null:
		if session_a != null:
			session_a.free()
		if session_b != null:
			session_b.free()
		return {"ok": false, "error": "%s setup failed" % str(spec.name)}
	if str(spec.mode) in ["soft_spool", "governed"]:
		if not session_a.toggle_motor_arm() or not session_a.set_drive_hold(false):
			return _prepare_error(session_a, session_b, "%s explicit arm/hold release failed" % str(spec.name))
	if str(spec.mode) == "governed":
		if not _advance_unmeasured(session_a, 2880):
			return _prepare_error(session_a, session_b, "%s 12 s spool pre-roll faulted: %s" % [str(spec.name), str(session_a.pause_reason)])
		if session_a.power_phase() != "GOVERNED":
			return _prepare_error(session_a, session_b, "%s pre-roll did not reach governed RPM" % str(spec.name))
	if int(spec.warmup) > 0 and not _advance_unmeasured(session_a, int(spec.warmup)):
		return _prepare_error(session_a, session_b, "%s warmup faulted: %s" % [str(spec.name), str(session_a.pause_reason)])
	var checkpoint: Dictionary = session_a.checkpoint()
	if checkpoint.is_empty():
		return _prepare_error(session_a, session_b, "%s produced no valid checkpoint" % str(spec.name))
	var restored: Dictionary = session_b.restore_checkpoint(checkpoint)
	if not restored.get("ok", false):
		return _prepare_error(session_a, session_b, "%s candidate restore failed: %s" % [str(spec.name), "; ".join(restored.get("errors", []))])
	var start_choice: String = str(spec.start)
	if session_a.sim.continuous.size() != (14 if start_choice == "ground" else 6):
		return _prepare_error(session_a, session_b, "%s continuous layout mismatch" % str(spec.name))
	return {"ok": true, "session_a": session_a, "session_b": session_b, "checkpoint": checkpoint}


func _new_session(session_script: Script, start_choice: String) -> Node:
	var session: Node = session_script.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
	if not field.get("ok", false) or not session.setup() \
			or not session.set_field(field.field) or not session.set_start_choice(start_choice) \
			or not session.reset() or not session.is_flyable():
		session.free()
		return null
	if session.sim.dt() != 1.0 / float(TICK_RATE_HZ):
		session.free()
		return null
	return session


func _advance_unmeasured(session: Node, count: int) -> bool:
	for _index: int in count:
		var previous_tick: int = session.sim.tick
		session.sim.step()
		if session.sim.tick != previous_tick + 1 or not session.is_flyable():
			return false
	return true


func _prepare_error(session_a: Node, session_b: Node, message: String) -> Dictionary:
	if is_instance_valid(session_a):
		session_a.free()
	if is_instance_valid(session_b):
		session_b.free()
	return {"ok": false, "error": message}


func _measure(session: Node, count: int) -> Dictionary:
	var timings: Array[int] = []
	timings.resize(count)
	var streams: Dictionary = {
		"state": PackedByteArray(),
		"aux": PackedByteArray(),
		"continuous": PackedByteArray(),
		"phase": PackedByteArray(),
	}
	var start_tick: int = session.sim.tick
	for index: int in count:
		var previous_tick: int = session.sim.tick
		var clock_start: int = Time.get_ticks_usec()
		session.sim.step()
		var elapsed_usec: int = Time.get_ticks_usec() - clock_start
		if session.sim.tick != previous_tick + 1 or not session.is_flyable():
			return {"ok": false, "error": str(session.sim.fault_reason) if not session.sim.fault_reason.is_empty() else str(session.pause_reason)}
		timings[index] = elapsed_usec
		streams.state.append_array(session.sim.state.to_byte_array())
		streams.aux.append_array(session.sim.aux.to_byte_array())
		streams.continuous.append_array(session.sim.continuous.to_byte_array())
		streams.phase.append_array(session.shaft_phase.to_byte_array())
	return {
		"ok": true,
		"elapsed_usec": timings,
		"accepted_ticks": count,
		"start_tick": start_tick,
		"end_tick": session.sim.tick,
		"final_power_phase": session.power_phase(),
		"streams": streams,
	}


func _sha256(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _finish(complete: bool, error: String) -> void:
	var report: Dictionary = {
		"format": "heli-ground-contact-abba-raw-v1",
		"complete": complete,
		"error": error,
		"tick_rate_hz": TICK_RATE_HZ,
		"tick_duration_s": 1.0 / float(TICK_RATE_HZ),
		"step_call": "session.sim.step()",
		"order_design": "AB then BA, two paired replicates per regime",
		"accepted_tick_observer": "existing Session._on_stepped observer; tick increments checked; no extra signal observer",
		"control_trace_recording": false,
		"parity_bytes": ["state", "aux", "continuous", "shaft_phase"],
		"host_load_note": "Development run while parse_all.py had two other Godot processes active; host load was not isolated.",
		"segments": _segments,
	}
	var output: FileAccess = FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if output == null:
		push_error("Could not write temporary experiment output: " + RESULT_PATH)
		print("GROUND_CONTACT_ABBA_ERROR: output file could not be created")
		quit(1)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	print(RESULT_MARKER + JSON.stringify({"complete": complete, "error": error, "segments": _segments.size(), "output": RESULT_PATH}))
	quit(0 if complete else 1)
