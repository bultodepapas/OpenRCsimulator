## UI-FS-08-R1: the statistics adapter's per-tick sample from an explicit prior
## fixed_wing_adapter.gd (reference, extracted outside app/) and the working tree, on one real session
## through a descent, touchdown and ground roll. Every sample must be bytewise equal. Research-only.
## See research/performance/README.md#statistics-observer-cost-ui-fs-08-r1.
extends SceneTree

const Candidate := preload("res://statistics/fixed_wing_adapter.gd")
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
	var total := {compared = 0, mismatches = 0, supported = 0, ref_us = 0, cand_us = 0}
	for case: Array in [["glide-in", 18.0, 14.0, 1.6], ["steep", 25.0, 18.0, 4.0], ["runway", 0.0, 0.0, 0.0]]:
		_case(reference, case, total)
	print("compared=%d supported=%d mismatches=%d sample_us reference=%.1f candidate=%.1f ratio=%.3f" % [
		total.compared, total.supported, total.mismatches, float(total.ref_us) / total.compared,
		float(total.cand_us) / total.compared, float(total.cand_us) / maxf(1.0, float(total.ref_us))])
	_check("every sample bytewise equal", total.mismatches == 0, "mismatches=%d" % total.mismatches)
	_check("ground support is exercised", total.supported > 100, "supported=%d" % total.supported)
	print("STATISTICS SAMPLE PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _case(reference: GDScript, case: Array, total: Dictionary) -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	if case[0] == "runway":
		session.start_choice = Session.START_RUNWAY
	session.setup()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(Field.load_from().field)
	session.reset() # the runway start resolves against the installed field
	session.engine_running = false
	if case[0] != "runway":
		session.sim.reset(RB.make_state(M.v3(0.0, -40.0, -float(case[1])), M.v3(float(case[2]), 0.0, float(case[3])),
			M.q_identity(), M.v3(0.0, 0.0, 0.0)))
	session.sim.set_paused(false)
	var ref_adapter: RefCounted = reference.new()
	var cand_adapter: RefCounted = Candidate.new()
	var sink := func(_sample: Dictionary) -> void: pass
	ref_adapter.configure(session, "jensen-das-ugly-stik-60", sink)
	cand_adapter.configure(session, "jensen-das-ugly-stik-60", sink)
	var before: int = total.compared
	for _i: int in 2400:
		session.sim.step()
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			print("%s: stopped at tick %d crash=%s fault=%s" % [case[0], session.sim.tick, session.crash, session.sim.fault_reason])
			break
		var started := Time.get_ticks_usec()
		var a: Dictionary = ref_adapter.sample()
		var middle := Time.get_ticks_usec()
		var b: Dictionary = cand_adapter.sample()
		total.cand_us += Time.get_ticks_usec() - middle
		total.ref_us += middle - started
		total.compared += 1
		if bool(a.get("supported", false)): total.supported += 1
		if var_to_bytes(a) != var_to_bytes(b): total.mismatches += 1
	print("%s: %d samples compared, paused=%s" % [case[0], total.compared - before, session.sim.paused])
	session.free()


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
