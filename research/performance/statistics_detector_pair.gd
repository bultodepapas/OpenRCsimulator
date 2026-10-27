## UI-FS-08-R1: the flight-statistics detector from an explicit prior detector.gd
## (reference, extracted outside app/) and the working tree, fed identical real samples from one session
## through a trimmed cruise, descents and touchdowns. Events and complete snapshots must be bytewise equal
## after every tick. Research-only. See research/performance/README.md#statistics-observer-cost-ui-fs-08-r1.
extends SceneTree

const CandidateDetector := preload("res://statistics/detector.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
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
	var total := {ticks = 0, mismatches = 0, events = 0, candidates = 0, ref_us = 0, cand_us = 0}
	for case: Array in [["cruise", -1.0, 0.0, 0.0, 7200], ["glide-in", 18.0, 14.0, 1.6, 2880], ["steep", 25.0, 18.0, 4.0, 2880]]:
		_case(reference, case, total)
	print("ticks=%d events=%d speed_candidates=%d mismatches=%d observe_us reference=%.1f candidate=%.1f ratio=%.3f" % [
		total.ticks, total.events, total.candidates, total.mismatches, float(total.ref_us) / total.ticks,
		float(total.cand_us) / total.ticks, float(total.cand_us) / maxf(1.0, float(total.ref_us))])
	_check("events and snapshots bytewise equal after every tick", total.mismatches == 0, "mismatches=%d" % total.mismatches)
	_check("speed candidates are exercised", total.candidates > 1000, "candidates=%d" % total.candidates)
	print("STATISTICS DETECTOR PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _case(reference: GDScript, case: Array, total: Dictionary) -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(Field.load_from().field)
	session.reset()
	if float(case[1]) >= 0.0:
		session.engine_running = false
		session.sim.reset(RB.make_state(M.v3(0.0, -40.0, -float(case[1])), M.v3(float(case[2]), 0.0, float(case[3])),
			M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	session.sim.set_paused(false)
	var adapter: RefCounted = Adapter.new()
	adapter.configure(session, "jensen-das-ugly-stik-60", func(_sample: Dictionary) -> void: pass)
	var ref_detector: RefCounted = reference.new()
	var cand_detector: RefCounted = CandidateDetector.new()
	ref_detector.configure(adapter.profile, true)
	cand_detector.configure(adapter.profile, true)
	for _i: int in int(case[4]):
		session.sim.step()
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			break
		var sample: Dictionary = adapter.sample()
		var started := Time.get_ticks_usec()
		var a: Array = ref_detector.observe(sample.duplicate(true))
		var middle := Time.get_ticks_usec()
		var b: Array = cand_detector.observe(sample.duplicate(true))
		total.cand_us += Time.get_ticks_usec() - middle
		total.ref_us += middle - started
		total.ticks += 1
		total.events += a.size()
		if var_to_bytes([a, ref_detector.snapshot()]) != var_to_bytes([b, cand_detector.snapshot()]):
			total.mismatches += 1
		# A full speed window adds one median candidate on this tick.
		if float(ref_detector.get("_speed_window_s")) + 1e-12 >= 0.25:
			total.candidates += 1
	session.free()


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
