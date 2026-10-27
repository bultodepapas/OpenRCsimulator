## GP-19f: a real descent and touchdown observed by an explicit prior
## ground_audio_model.gd (reference, extracted outside app/) and the working tree, each feeding its own
## accepted GroundAudio observer. Near-ground rows must be bytewise equal and the captured touchdown cues
## identical; rows well above gear reach may differ only in unloaded presentation fields. Research-only.
## See research/performance/README.md#ground-audio-unloaded-rows-gp-19f.
extends SceneTree

const Candidate := preload("res://audio/ground_audio_model.gd")
const GroundAudio := preload("res://audio/ground_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ref_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
	var reference := GDScript.new()
	reference.source_code = FileAccess.get_file_as_string(ref_path)
	if reference.source_code.is_empty() or reference.reload() != OK:
		push_error("reference script failed to load: " + ref_path)
		quit(2)
		return
	var report := {}
	# "firm" starts inside the full-row band: a near-only control.
	var expect_far := {"glide-in": true, "firm": false, "steep": true}
	for case: Array in [["glide-in", 18.0, 14.0, 1.6], ["firm", 6.0, 12.0, 2.8], ["steep", 25.0, 18.0, 4.0]]:
		report[case[0]] = _descent(reference, case[1], case[2], case[3])
	for name: String in report:
		var r: Dictionary = report[name]
		print("%s: ticks=%d far=%d near=%d near_mismatches=%d events ref=%d cand=%d touchdown_tick=%d" % [
			name, r.ticks, r.far, r.near, r.near_mismatches, r.ref_events, r.cand_events, r.touchdown_tick])
		_check(name + ": near-ground rows bytewise equal", r.near_mismatches == 0)
		_check(name + ": touchdown cues identical", r.events_equal and r.ref_events > 0, "ref=%d cand=%d" % [r.ref_events, r.cand_events])
		_check(name + (": both paths exercised" if expect_far[name] else ": near-only control stays in full rows"),
			r.near > 0 and (r.far > 0) == bool(expect_far[name]))
	print("GROUND AUDIO FAR PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


## Level attitude, forward speed and sink rate from `height_m`; idle engine; 12 s of accepted ticks.
func _descent(reference: GDScript, height_m: float, forward_mps: float, sink_mps: float) -> Dictionary:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(Field.load_from().field)
	session.engine_running = false
	var start := RB.make_state(M.v3(0.0, -40.0, -height_m), M.v3(forward_mps, 0.0, sink_mps),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	session.sim.reset(start)
	session.sim.set_paused(false)
	var audio_ref: Node = GroundAudio.new()
	var audio_cand: Node = GroundAudio.new()
	root.add_child(audio_ref)
	root.add_child(audio_cand)
	audio_ref.set_accepted_tick_observation(true)
	audio_cand.set_accepted_tick_observation(true)
	var result := {ticks = 0, far = 0, near = 0, near_mismatches = 0, ref_events = 0, cand_events = 0,
		events_equal = true, touchdown_tick = -1}
	for _i: int in 2880:
		session.sim.step()
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		var a: Array = reference.snapshot_contacts(session, {})
		var b: Array = Candidate.snapshot_contacts(session, {})
		var far: bool = not b.is_empty() and str(b[0].material_id) == "unspecified" and not bool(b[0].material_resolved) \
			and var_to_bytes(a) != var_to_bytes(b)
		if far:
			result.far += 1
			for row: Dictionary in b:
				if float(row.normal_force_n) != 0.0: result.near_mismatches += 1
		else:
			result.near += 1
			if var_to_bytes(a) != var_to_bytes(b): result.near_mismatches += 1
		var tick: int = session.sim.tick
		audio_ref.observe_accepted({tick = tick, tick_rate = 240.0, paused = false, contacts = a})
		audio_cand.observe_accepted({tick = tick, tick_rate = 240.0, paused = false, contacts = b})
		var ref_events: Array = audio_ref.get("_accepted_events")
		var cand_events: Array = audio_cand.get("_accepted_events")
		if ref_events.size() > result.ref_events and result.touchdown_tick < 0: result.touchdown_tick = tick
		result.ref_events = ref_events.size()
		result.cand_events = cand_events.size()
		# Event contacts carry the touchdown row; they come from the full-row band on both sides.
		if var_to_bytes(_cues(ref_events)) != var_to_bytes(_cues(cand_events)): result.events_equal = false
		result.ticks += 1
	session.free()
	audio_ref.free()
	audio_cand.free()
	return result


func _cues(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		out.append([event.tick, event.force, event.reference, event.approach, event.contact])
	return out


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
