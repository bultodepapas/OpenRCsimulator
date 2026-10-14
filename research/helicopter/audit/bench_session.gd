## HELI-09/16-R1: reproducible actual-session timing and complete-state digest.
extends SceneTree
const Session = preload("res://sim/helicopter_flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Flight = preload("res://physics/rotorcraft/flight_dynamics.gd")
const Electronics = preload("res://physics/rotorcraft/electronics.gd")
var _session: Node
var _reference: Node
var _failed := false

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
	var state: PackedFloat64Array = _session.sim.state.duplicate()
	state.append_array(_session.sim.continuous)
	var sticks: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 2.0 * _session.commands.throttle - 1.0])
	var trim: Dictionary = _session.checkpoint().trim
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-session="):
			var script: Script = load(arg.trim_prefix("--reference-session="))
			_reference = script.new()
			_reference.input_enabled = false
			_reference.physics_enabled = false
			_reference.external_controller_selection = true
			root.add_child(_reference)
			if not _reference.setup() or not _reference.set_field(field.field) or not _reference.reset():
				printerr("ERROR: reference session setup failed")
				quit(1)
				return
	var samples := {"electronics_us": [], "electronics_prepared_us": [], "flight_evaluation_us": [], "whole_tick_us": []}
	var digests: Array[String] = []
	var reference_times: Array[float] = []
	var reference_digests: Array[String] = []
	for round_index: int in range(7):
		for warmup: int in range(60):
			Electronics.evaluate(_session.aircraft.context.electronics_model, state, sticks, "normal", true, trim)
		var started := Time.get_ticks_usec()
		for index: int in range(1000):
			var out: Dictionary = Electronics.evaluate(_session.aircraft.context.electronics_model, state, sticks, "normal", true, trim)
			if not out.ok: _failed = true
		samples.electronics_us.append(float(Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		for index: int in range(1000):
			var out: Dictionary = Electronics.fast_evaluate(_session.aircraft.context.electronics_model, state, sticks, "normal", true, trim)
			if not out.ok: _failed = true
		samples.electronics_prepared_us.append(float(Time.get_ticks_usec() - started) / 1000.0)
		started = Time.get_ticks_usec()
		for index: int in range(500):
			var out: Dictionary = Flight.evaluate(state, _session.aircraft.context, sticks, "normal", true, false, PackedFloat64Array([0,0,0]), false, PackedFloat64Array(), trim, 4.0)
			if not out.ok: _failed = true
		samples.flight_evaluation_us.append(float(Time.get_ticks_usec() - started) / 500.0)
		var reference: Dictionary = {}
		if _reference != null and round_index % 2 == 0:
			reference = _measure_ticks(_reference)
		var candidate: Dictionary = _measure_ticks(_session)
		if _reference != null and round_index % 2 == 1:
			reference = _measure_ticks(_reference)
		samples.whole_tick_us.append(candidate.us)
		digests.append(candidate.sha256)
		if _reference != null:
			reference_times.append(reference.us)
			reference_digests.append(reference.sha256)
			if reference.sha256 != candidate.sha256: _failed = true
	var medians := {}
	for key: String in samples:
		var sorted: Array = samples[key].duplicate()
		sorted.sort()
		medians[key] = sorted[3]
	for digest: String in digests:
		if digest != digests[0]: _failed = true
	var report := {"step":"HELI-09/16-R1", "engine":Engine.get_version_info().string, "os":OS.get_name(),
		"cpu":OS.get_processor_name(), "aircraft_sha256":_session.aircraft.input_identity.sha256,
		"rounds":7, "ticks_per_round":480, "samples":samples, "medians":medians,
		"state_hashes":digests, "ok":not _failed, "target_performance_qualified":false}
	if _reference != null:
		var sorted := reference_times.duplicate()
		sorted.sort()
		report["reference_whole_tick_samples_us"] = reference_times
		report["reference_whole_tick_median_us"] = sorted[3]
		report["reference_state_hashes"] = reference_digests
		report["paired_whole_tick_speedup"] = sorted[3] / medians.whole_tick_us
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null: _failed = true
		else: file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	print(JSON.stringify(report, "", true, true))
	_session.free()
	if _reference != null: _reference.free()
	quit(1 if _failed else 0)

func _measure_ticks(session: Node) -> Dictionary:
	if not session.reset(): _failed = true
	var started := Time.get_ticks_usec()
	for tick: int in range(480):
		session.sim.inputs[0] = 0.05 if tick < 60 else (-0.05 if tick < 120 else 0.0)
		session.sim.inputs[1] = 0.04 if tick >= 120 and tick < 180 else 0.0
		session.sim.inputs[2] = 0.03 if tick >= 180 and tick < 240 else 0.0
		session.sim.step()
		if not session.is_flyable(): _failed = true
	var elapsed := float(Time.get_ticks_usec() - started) / 480.0
	var complete: PackedFloat64Array = session.sim.state.duplicate()
	complete.append_array(session.sim.continuous)
	return {"us":elapsed, "sha256":_hash(complete.to_byte_array())}

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
