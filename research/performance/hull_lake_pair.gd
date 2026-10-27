## LU-25-R4: bytewise parity and paired timing of HullContact.loads/terminal, an explicit prior
## hull_contact.gd (reference, extracted outside app/) versus the working tree (candidate), on the
## default Stik prepared hull with the default lake. Research-only.
## See research/performance/README.md#hull-lake-bounds-rejection-lu-25-r4.
extends SceneTree

const Candidate = preload("res://physics/hull_contact.gd")
const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const RB = preload("res://physics/rigid_body.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"

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
	var session: Node = Session.new()
	session.input_enabled = false
	session.soft_hull_contacts = true
	session.setup(STIK)
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("Stik session with installed default field and lake", session.is_flyable() and lake.ok
		and session.set_field(Field.load_from().field) and session.set_lake_context(lake.lake))
	var prepared: Dictionary = session._hull_contact
	_check("prepared hull carries the lake and its bounds", not prepared.get("lake", {}).is_empty()
		and prepared.get("lake_bounds_ne_m", PackedFloat64Array()).size() == 4)
	# Live-mass (glow, finite fuel) sessions prepare geometry only and pass mass properties per call.
	var glow: Node = Session.new()
	glow.input_enabled = false
	glow.soft_hull_contacts = true
	glow.setup(GLOW)
	root.add_child(glow)
	glow.set_process(false)
	glow.set_physics_process(false)
	_check("glow session with installed default field and lake", glow.is_flyable() and glow.finite_fuel_is_active()
		and glow.set_field(Field.load_from().field) and glow.set_lake_context(lake.lake))
	var geometry: Dictionary = glow._hull_contact
	var properties: Dictionary = glow.mass_properties()
	_check("glow geometry is geometry-only with lake bounds", bool(geometry.get("geometry_only", false))
		and geometry.get("lake_bounds_ne_m", PackedFloat64Array()).size() == 4)
	if _failures > 0:
		quit(1)
		return
	var bounds: PackedFloat64Array = prepared.lake_bounds_ne_m
	var runway: PackedFloat64Array = session.sim.state.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var states: Array[PackedFloat64Array] = []
	for gi: int in 41:
		for gj: int in 41:
			var north := lerpf(bounds[0] - 40.0, bounds[1] + 40.0, gi / 40.0)
			var east := lerpf(bounds[2] - 40.0, bounds[3] + 40.0, gj / 40.0)
			states.append(_state(rng, north, east))
	for k: int in 400: # runway neighbourhood, the measured idle case
		states.append(_state(rng, runway[0] + rng.randf_range(-20.0, 20.0), runway[1] + rng.randf_range(-20.0, 20.0)))
	var no_samples: Array[Dictionary] = []
	var mismatches := 0
	var glow_mismatches := 0
	var glow_active := 0
	var clear := 0
	var covered := 0
	var touching := 0
	for s: PackedFloat64Array in states:
		var previous := s.duplicate()
		previous[RB.POS + 2] -= 0.01
		previous[RB.VEL + 2] = rng.randf_range(-3.0, 3.0)
		var ref_array: Array = []
		var cand_array: Array = []
		var ref_dict := {}
		var cand_dict := {}
		var a := var_to_bytes([reference.loads(s, prepared), reference.loads(s, prepared, no_samples, ref_array),
			reference.loads(s, prepared, no_samples, ref_dict), ref_array, ref_dict, reference.terminal(previous, s, prepared)])
		var b := var_to_bytes([Candidate.loads(s, prepared), Candidate.loads(s, prepared, no_samples, cand_array),
			Candidate.loads(s, prepared, no_samples, cand_dict), cand_array, cand_dict, Candidate.terminal(previous, s, prepared)])
		if a != b: mismatches += 1
		# contacts() and the live-mass entry points; terminal_at_properties needs a unit previous attitude.
		var unit_previous := previous.duplicate()
		var norm := sqrt(unit_previous[RB.ATT] ** 2 + unit_previous[RB.ATT + 1] ** 2 + unit_previous[RB.ATT + 2] ** 2 + unit_previous[RB.ATT + 3] ** 2)
		for i: int in 4:
			unit_previous[RB.ATT + i] /= norm
		var ref_glow := {}
		var cand_glow := {}
		var ga := var_to_bytes([reference.contacts(previous, s, prepared), reference.loads_at_properties(s, geometry, properties, ref_glow),
			ref_glow, reference.terminal_at_properties(unit_previous, s, geometry, properties)])
		var gb := var_to_bytes([Candidate.contacts(previous, s, prepared), Candidate.loads_at_properties(s, geometry, properties, cand_glow),
			cand_glow, Candidate.terminal_at_properties(unit_previous, s, geometry, properties)])
		if ga != gb: glow_mismatches += 1
		if not Candidate.loads_at_properties(s, geometry, properties).loads.is_empty(): glow_active += 1
		if Candidate._hull_clear_of_lake(s, prepared): clear += 1
		if not Candidate.loads(s, prepared).is_empty(): touching += 1
		if ref_dict.get("reason", "") == "covered_lake_branch_unqualified": covered += 1
	print("states=%d clear_of_lake=%d covered_lake=%d with_loads=%d" % [states.size(), clear, covered, touching])
	_check("loads, diagnostics and terminal bytewise equal", mismatches == 0, "mismatches=%d" % mismatches)
	_check("both the rejection and the sampled branch are exercised", clear > 0 and clear < states.size() and covered > 0)
	_check("contact loads are exercised", touching > 100)
	_check("contacts, loads_at_properties and terminal_at_properties bytewise equal", glow_mismatches == 0,
		"mismatches=%d" % glow_mismatches)
	_check("live-mass contact loads are exercised", glow_active > 100, "with_loads=%d" % glow_active)
	# Paired timing on the runway neighbourhood: loads as one RK stage calls it.
	var runway_states := states.slice(states.size() - 400)
	var ref_us := PackedFloat64Array()
	var cand_us := PackedFloat64Array()
	for round: int in 12:
		for order: int in 2:
			var use_ref: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for s: PackedFloat64Array in runway_states:
				if use_ref: reference.loads(s, prepared)
				else: Candidate.loads(s, prepared)
			var per_call: float = float(Time.get_ticks_usec() - started) / float(runway_states.size())
			if use_ref: ref_us.append(per_call)
			else: cand_us.append(per_call)
	ref_us.sort()
	cand_us.sort()
	print("TIMING runway loads reference_median_us=%.2f candidate_median_us=%.2f ratio=%.3f" % [
		ref_us[6], cand_us[6], cand_us[6] / ref_us[6]])
	session.free()
	glow.free()
	print("HULL LAKE PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


## Near-ground state: some hull points below the datum, random attitude with a non-unit quaternion
## (stage states are not normalized), random body velocity and rates.
func _state(rng: RandomNumberGenerator, north: float, east: float) -> PackedFloat64Array:
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	var angle := rng.randf_range(-0.6, 0.6)
	var scale := rng.randf_range(0.9, 1.1)
	var q := PackedFloat64Array([cos(angle / 2.0) * scale, axis.x * sin(angle / 2.0) * scale,
		axis.y * sin(angle / 2.0) * scale, axis.z * sin(angle / 2.0) * scale])
	var s := PackedFloat64Array()
	s.resize(RB.SIZE)
	s[RB.POS] = north
	s[RB.POS + 1] = east
	s[RB.POS + 2] = rng.randf_range(-0.6, 0.3)
	for i: int in 3:
		s[RB.VEL + i] = rng.randf_range(-6.0, 6.0)
		s[RB.RATE + i] = rng.randf_range(-3.0, 3.0)
	for i: int in 4:
		s[RB.ATT + i] = q[i]
	return s


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
