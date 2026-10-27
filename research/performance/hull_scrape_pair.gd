## GP-19e: paired accepted hull-scrape observations, explicit prior flight_session.gd and
## hull_contact.gd (reference, extracted outside app/) versus the working tree (candidate).
## Research-only. See research/performance/README.md#hull-scrape-observation-key-gp-19e.
extends SceneTree

const Candidate = preload("res://sim/flight_session.gd")
const H = preload("res://physics/hull_contact.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Field = preload("res://data/field_loader.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"
const TICKS := 480

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _script(path: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	return script if not script.source_code.is_empty() and script.reload() == OK else null


func _session(script: Script, path: String) -> Node:
	var f: Node = script.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.soft_hull_contacts = true
	f.setup(path)
	f.set_process(false)
	f.set_physics_process(false)
	f.engine_running = false
	root.add_child(f)
	return f


func _body(f: Node) -> PackedFloat64Array:
	var q := M.q_from_euler(0.0, 0.0, deg_to_rad(40.0))
	var extent := -INF
	for i in range(0, f.aircraft.model.crash_hull.size(), 3):
		extent = maxf(extent, M.q_rotate(q, f.aircraft.model.crash_hull.slice(i, i + 3))[2])
	return RB.make_state(M.v3(0, 0, .001 - extent), M.q_rotate(M.q_conj(q), M.v3(5, 0, 0)), q, M.v3(0, 0, 0))


func _run() -> void:
	var ref_path := ""
	var hull_ref_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): ref_path = arg.trim_prefix("--reference=")
		elif arg.begins_with("--hull-reference="): hull_ref_path = arg.trim_prefix("--hull-reference=")
	var reference := _script(ref_path)
	var hull_reference := _script(hull_ref_path)
	if reference == null or hull_reference == null:
		push_error("reference scripts failed to load")
		quit(2)
		return
	_check("memoized law identity equals the HEAD formatter", H.law() == hull_reference.law() and H.law() == H.law(), H.law())
	for path: String in [STIK, GLOW]:
		var ref: Node = _session(reference, path)
		var cand: Node = _session(Candidate, path)
		_check(path + " sessions flyable", ref.is_flyable() and cand.is_flyable())
		_check(path + " field installed", ref.set_field(Field.load_from().field) and cand.set_field(Field.load_from().field))
		var initial := _body(cand)
		_check(path + " identical start", ref.sim.reset(initial) and cand.sim.reset(initial))
		ref.sim.set_paused(false)
		cand.sim.set_paused(false)
		var compared := 0
		var loaded := 0
		var mismatches := 0
		var ref_us := 0
		var cand_us := 0
		for tick: int in TICKS:
			ref.sim.step()
			cand.sim.step()
			if tick == 200:
				ref.sim.set_paused(true); cand.sim.set_paused(true)
				ref.sim.set_paused(false); cand.sim.set_paused(false)
			for call: int in 1 + tick % 3:
				var started := Time.get_ticks_usec()
				var a: Dictionary = ref.hull_scrape_observation()
				var middle := Time.get_ticks_usec()
				var b: Dictionary = cand.hull_scrape_observation()
				if call == 0:
					ref_us += middle - started
					cand_us += Time.get_ticks_usec() - middle
				compared += 1
				if not b.contacts.is_empty(): loaded += 1
				if var_to_bytes(a) != var_to_bytes(b): mismatches += 1
				# Callers own their packet: mutating it must not leak into a later same-tick read.
				for row: Dictionary in b.contacts: row.friction_power_w = -1.0
				for row: Dictionary in a.contacts: row.friction_power_w = -1.0
		var same_state: bool = ref.sim.state == cand.sim.state and ref.sim.continuous == cand.sim.continuous \
			and ref.sim.aux == cand.sim.aux and ref.sim.tick == cand.sim.tick
		_check(path + " observations bytewise equal", mismatches == 0, "mismatches=%d of %d" % [mismatches, compared])
		_check(path + " scenario exercises loaded scrape rows", loaded > 0, "loaded=%d" % loaded)
		_check(path + " physical state identical", same_state)
		print("%s compared=%d loaded=%d first_call_us reference=%d candidate=%d ratio=%.3f" % [
			path.get_file(), compared, loaded, ref_us, cand_us, float(cand_us) / maxf(1.0, float(ref_us))])
		ref.free()
		cand.free()
	print("HULL PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
