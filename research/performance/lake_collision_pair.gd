## LU-25-R6: bytewise parity and paired timing of LakeCollision.first_hit, an explicit prior
## lake_collision.gd (reference, extracted outside app/) versus the working tree, on the default Stik hull,
## gear and propeller with the default lake. Tick pairs sweep a grid across the bank bounds ± 60 m, from
## clear above to below the water level, plus distant airborne ticks. Research-only.
## See research/performance/README.md#lake-collision-early-rejection-lu-25-r6.
extends SceneTree

const Candidate := preload("res://sim/lake_collision.gd")
const Session := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0

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
	session.setup()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	_check("session with field and lake", session.set_field(Field.load_from().field) and session.set_lake_context(lake))
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var gear: Dictionary = session.current_landing_gear()
	var prop_disc: Dictionary = session.get("_prop_disc") if session.get("_prop_disc") is Dictionary else {}
	var mass: float = float(session.sim.mass)
	var inertia: PackedFloat64Array = session.sim.inertia
	var bounds := _bounds(lake.bank_ne_m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261027
	var pairs: Array = []
	for gi: int in 31:
		for gj: int in 31:
			var north := lerpf(bounds[0] - 60.0, bounds[1] + 60.0, gi / 30.0)
			var east := lerpf(bounds[2] - 60.0, bounds[3] + 60.0, gj / 30.0)
			for height: float in [0.2, 0.6, 1.5, -0.3]:
				pairs.append(_pair(rng, north, east, height))
	for k: int in 2000: # distant airborne ticks, the common case in flight
		pairs.append(_pair(rng, rng.randf_range(-400.0, 400.0), rng.randf_range(-400.0, 400.0), rng.randf_range(5.0, 120.0)))
	var mismatches := 0
	var hits := 0
	for pair: Array in pairs:
		var a: Variant = reference.first_hit(lake, pair[0], pair[1], hull, gear, 120, DT, mass, inertia, true, prop_disc)
		var b: Variant = Candidate.first_hit(lake, pair[0], pair[1], hull, gear, 120, DT, mass, inertia, true, prop_disc)
		if a != null: hits += 1
		if var_to_bytes(_fields(a)) != var_to_bytes(_fields(b)):
			if mismatches == 0:
				var fa: Array = _fields(a)
				var fb: Array = _fields(b)
				for k: int in fa.size():
					if var_to_bytes(fa[k]) != var_to_bytes(fb[k]):
						print("differs: ", fa[k][0], " type ", typeof(fa[k][1]), " ref=", str(fa[k][1]).left(160), " cand=", str(fb[k][1]).left(160))
			mismatches += 1
	print("tick_pairs=%d hits=%d mismatches=%d" % [pairs.size(), hits, mismatches])
	_check("first_hit events bytewise equal", mismatches == 0, "mismatches=%d" % mismatches)
	_check("water or bank hits are exercised", hits > 50, "hits=%d" % hits)
	var distant: Array = pairs.slice(pairs.size() - 2000)
	var ref_us := PackedFloat64Array()
	var cand_us := PackedFloat64Array()
	for round: int in 12:
		for order: int in 2:
			var use_ref: bool = (round + order) % 2 == 0
			var started := Time.get_ticks_usec()
			for pair: Array in distant:
				if use_ref: reference.first_hit(lake, pair[0], pair[1], hull, gear, 120, DT, mass, inertia, true, prop_disc)
				else: Candidate.first_hit(lake, pair[0], pair[1], hull, gear, 120, DT, mass, inertia, true, prop_disc)
			var per_call: float = float(Time.get_ticks_usec() - started) / float(distant.size())
			if use_ref: ref_us.append(per_call)
			else: cand_us.append(per_call)
	ref_us.sort()
	cand_us.sort()
	print("TIMING distant first_hit reference_median_us=%.2f candidate_median_us=%.2f ratio=%.3f" % [
		ref_us[6], cand_us[6], cand_us[6] / ref_us[6]])
	session.free()
	print("LAKE COLLISION PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


## One accepted tick: previous and candidate states 1/240 s apart at `height` above the datum (negative is
## below), with random attitude, velocity and rates.
func _pair(rng: RandomNumberGenerator, north: float, east: float, height: float) -> Array:
	var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	var q := M.q_from_axis_angle(PackedFloat64Array([axis.x, axis.y, axis.z]), rng.randf_range(-0.8, 0.8))
	var velocity := M.v3(rng.randf_range(-5.0, 25.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-4.0, 4.0))
	var rates := M.v3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
	var previous := RB.make_state(M.v3(north, east, -height), velocity, q, rates)
	var world := M.q_rotate(q, velocity)
	var candidate := RB.make_state(M.v3(north + world[0] * DT, east + world[1] * DT, -height + world[2] * DT), velocity, q, rates)
	return [previous, candidate]


## Script variables by value, recursing into nested objects (the event's crossing record), arrays and
## dictionaries, so two calls compare by content rather than by instance.
func _fields(event: Variant) -> Array:
	if event == null:
		return []
	var out: Array = []
	for property: Dictionary in (event as Object).get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append([property.name, _plain(event.get(property.name))])
	return out


func _plain(value: Variant) -> Variant:
	if value is Object:
		return _fields(value)
	if value is Array:
		return (value as Array).map(func(item: Variant) -> Variant: return _plain(item))
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			copy[key] = _plain(value[key])
		return copy
	return value


func _bounds(polygon: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([INF, -INF, INF, -INF])
	for i: int in range(0, polygon.size(), 2):
		out[0] = minf(out[0], polygon[i]); out[1] = maxf(out[1], polygon[i])
		out[2] = minf(out[2], polygon[i + 1]); out[3] = maxf(out[3], polygon[i + 1])
	return out


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
