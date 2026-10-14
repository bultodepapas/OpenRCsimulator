## Resolve an authored, flat rotorcraft pad into an unforced four-skid rest state.
## Contact memory and static tangential friction are intentionally not part of this flat-pad slice.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Skids := preload("res://physics/rotorcraft/skid_contact.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")

const MAX_ITERATIONS := 24
const RELATIVE_RESIDUAL_LIMIT := 1.0e-4


## Input is the normalized FieldLoader field and RotorcraftData result. A failed
## or unsupported field/aircraft returns {ok:false, reason}; success includes
## a 13-value rigid-body `state` and the normalized pad with radian heading.
static func resolve(field: Dictionary, aircraft: Dictionary) -> Dictionary:
	if not field.has("rotorcraft_pad") or typeof(field.rotorcraft_pad) != TYPE_DICTIONARY:
		return _fail("field has no authored rotorcraft_pad; airborne fallback is not allowed")
	if not bool(aircraft.get("ok", false)):
		return _fail("selected rotorcraft data is invalid")
	var pad: Dictionary = field.rotorcraft_pad
	var context: Dictionary = aircraft.get("context", {})
	var skids: Dictionary = aircraft.get("skids", {})
	if context.is_empty() or skids.is_empty() or str(aircraft.get("id", "")).is_empty():
		return _fail("selected rotorcraft is missing its prepared body or skid model")
	if str(pad.get("material", "")) != "rotorpad":
		return _fail("rotorcraft_pad must reference the qualified zero-relief rotorpad material")
	var envelope: Dictionary = {}
	for candidate_value: Variant in pad.get("aircraft_envelopes", []):
		if typeof(candidate_value) == TYPE_DICTIONARY and str(candidate_value.get("aircraft_id", "")) == str(aircraft.id):
			envelope = candidate_value
			break
	if envelope.is_empty():
		return _fail("rotorcraft_pad has no supported envelope for '%s'" % str(aircraft.id))
	var authored_radius: float = float(envelope.get("radius", NAN))
	var actual_radius_result: Dictionary = _actual_envelope_radius(context, skids)
	if not bool(actual_radius_result.get("ok", false)):
		return _fail("selected aircraft has invalid rotor or skid envelope geometry")
	var actual_radius: float = float(actual_radius_result.radius)
	if not is_finite(authored_radius) or authored_radius <= 0.0 or actual_radius > authored_radius + 1.0e-9:
		return _fail("loaded main/tail discs or skids exceed the pad's authored aircraft envelope")
	var surface_table: Dictionary = GroundSurfaces.load_table()
	if not bool(surface_table.get("ok", false)):
		return _fail("ground material table is invalid: %s" % str(surface_table.get("errors", [])))
	var built: Dictionary = GroundSurfaces.build(surface_table.table, field)
	if not bool(built.get("ok", false)):
		return _fail("field ground surfaces are invalid: %s" % str(built.get("errors", [])))
	var surfaces: PackedFloat64Array = built.rects
	if not GroundTerrain.is_valid_surface_table(surfaces):
		return _fail("field ground surface table is not a valid float64 terrain table")
	if not _support_points_are_on_flat_pad(pad, skids, surfaces):
		return _fail("one or more skid supports are outside the flat rotorpad interior")
	var solved: Dictionary = _solve(pad, context, skids, surfaces, authored_radius)
	if not bool(solved.get("ok", false)):
		return _fail(str(solved.get("reason", "four-skid support solve failed")))
	var state: PackedFloat64Array = solved.state
	return {
		"ok": true,
		"reason": "",
		"pad": pad,
		"state": state,
		"loads_body": solved.loads_body,
		"normal_forces_n": solved.normal_forces_n,
		"compressions_m": solved.compressions_m,
		"contact_count": solved.contact_count,
		"force_residual_n": solved.force_residual_n,
		"moment_residual_nm": solved.moment_residual_nm,
		"force_residual_magnitude_n": solved.force_residual_magnitude_n,
		"moment_residual_magnitude_nm": solved.moment_residual_magnitude_nm,
		"relative_force_residual": solved.relative_force_residual,
		"relative_moment_residual": solved.relative_moment_residual,
		"actual_envelope_radius_m": actual_radius,
		"authored_envelope_radius_m": authored_radius,
		"iterations": solved.iterations,
		"tangential_support": "not modeled; result is qualified only on this horizontal zero-relief pad",
	}


static func _solve(pad: Dictionary, context: Dictionary, skids: Dictionary,
		surfaces: PackedFloat64Array, envelope_radius: float) -> Dictionary:
	var mass: float = float(context.get("mass_kg", NAN))
	var gravity: float = float(context.get("gravity_m_s2", NAN))
	var stiffness: float = float(skids.get("spring_n_m", NAN))
	var points: PackedFloat64Array = skids.get("points_body_frd_m", PackedFloat64Array())
	if not is_finite(mass) or mass <= 0.0 or not is_finite(gravity) or gravity <= 0.0 \
			or not is_finite(stiffness) or stiffness <= 0.0 or points.size() != 12:
		return {"ok": false, "reason": "aircraft mass, gravity, skid stiffness or support points are invalid"}
	var maximum_down_arm: float = 0.0
	for index: int in range(2, 12, 3):
		maximum_down_arm = maxf(maximum_down_arm, points[index])
	var initial_sag: float = mass * gravity / (4.0 * stiffness)
	var x := PackedFloat64Array([-maximum_down_arm + initial_sag, 0.0, 0.0])
	var scale: float = maxf(envelope_radius, 0.1)
	var converged := false
	var iterations := 0
	for iteration: int in MAX_ITERATIONS:
		iterations = iteration
		var current: Dictionary = _evaluate(x, pad, context, skids, surfaces, scale)
		if not bool(current.get("ok", false)):
			return {"ok": false, "reason": "skid support evaluation failed during the static solve"}
		var residual: PackedFloat64Array = current.residual
		var residual_norm: float = _norm(residual)
		if residual_norm <= 1.0e-11:
			converged = true
			break
		var jacobian := PackedFloat64Array()
		jacobian.resize(9)
		for column: int in 3:
			var h: float = 1.0e-6 if column == 0 else 1.0e-6
			var plus: PackedFloat64Array = x.duplicate()
			var minus: PackedFloat64Array = x.duplicate()
			plus[column] += h
			minus[column] -= h
			var r_plus: Dictionary = _evaluate(plus, pad, context, skids, surfaces, scale)
			var r_minus: Dictionary = _evaluate(minus, pad, context, skids, surfaces, scale)
			if not bool(r_plus.get("ok", false)) or not bool(r_minus.get("ok", false)):
				return {"ok": false, "reason": "support Jacobian evaluation failed"}
			for row: int in 3:
				jacobian[row * 3 + column] = (r_plus.residual[row] - r_minus.residual[row]) / (2.0 * h)
		var step_result: Dictionary = _solve_3x3(jacobian, PackedFloat64Array([-residual[0], -residual[1], -residual[2]]))
		if not bool(step_result.get("ok", false)):
			return {"ok": false, "reason": "support Jacobian is singular"}
		var step: PackedFloat64Array = step_result.x
		var accepted := false
		var fraction: float = 1.0
		for line_search: int in 10:
			var trial: PackedFloat64Array = x.duplicate()
			for axis: int in 3:
				trial[axis] += fraction * step[axis]
			var trial_result: Dictionary = _evaluate(trial, pad, context, skids, surfaces, scale)
			if bool(trial_result.get("ok", false)) and _norm(trial_result.residual) < residual_norm:
				x = trial
				accepted = true
				break
			fraction *= 0.5
		if not accepted:
			return {"ok": false, "reason": "support Newton solve could not reduce its force/moment residual"}
	if not converged:
		var final_check: Dictionary = _evaluate(x, pad, context, skids, surfaces, scale)
		converged = bool(final_check.get("ok", false)) and _norm(final_check.residual) <= 1.0e-11
	if not converged:
		return {"ok": false, "reason": "four-skid static support solve did not converge"}
	var evaluated: Dictionary = _evaluate(x, pad, context, skids, surfaces, scale, true)
	if not bool(evaluated.get("ok", false)):
		return {"ok": false, "reason": "final skid support evaluation failed"}
	var contacts: Dictionary = evaluated.contacts
	if int(contacts.get("contact_count", 0)) != 4:
		return {"ok": false, "reason": "static solution does not have all four intended skid contacts"}
	var normal_forces: PackedFloat64Array = contacts.normal_forces_n
	var compressions: PackedFloat64Array = contacts.compressions_m
	for index: int in 4:
		if normal_forces[index] <= 0.0 or compressions[index] <= 0.0:
			return {"ok": false, "reason": "static solution has a missing or tensile skid support"}
	var force_residual: PackedFloat64Array = evaluated.force_residual_n
	var moment_residual: PackedFloat64Array = evaluated.moment_residual_nm
	var force_magnitude: float = _norm(force_residual)
	var moment_magnitude: float = _norm(moment_residual)
	var weight: float = mass * gravity
	var relative_force: float = force_magnitude / weight
	var relative_moment: float = moment_magnitude / (weight * scale)
	if relative_force >= RELATIVE_RESIDUAL_LIMIT or relative_moment >= RELATIVE_RESIDUAL_LIMIT:
		return {"ok": false, "reason": "full six-axis static force/moment residual exceeds the flat-pad tolerance"}
	return {
		"ok": true,
		"state": evaluated.state,
		"loads_body": contacts.loads,
		"normal_forces_n": normal_forces,
		"compressions_m": compressions,
		"contact_count": int(contacts.contact_count),
		"force_residual_n": force_residual,
		"moment_residual_nm": moment_residual,
		"force_residual_magnitude_n": force_magnitude,
		"moment_residual_magnitude_nm": moment_magnitude,
		"relative_force_residual": relative_force,
		"relative_moment_residual": relative_moment,
		"iterations": iterations,
	}


static func _evaluate(x: PackedFloat64Array, pad: Dictionary, context: Dictionary,
		skids: Dictionary, surfaces: PackedFloat64Array, scale: float,
		diagnostics: bool = false) -> Dictionary:
	if x.size() != 3:
		return {"ok": false}
	var heading: float = float(pad.get("heading", NAN))
	var attitude: PackedFloat64Array = M.q_from_euler(heading, x[2], x[1])
	var state: PackedFloat64Array = RB.make_state(
		M.v3(float(pad.north), float(pad.east), x[0]),
		M.v3(0.0, 0.0, 0.0), attitude, M.v3(0.0, 0.0, 0.0))
	var contacts: Dictionary = Skids.evaluate(state, skids, surfaces, diagnostics)
	if not bool(contacts.get("ok", false)) or not contacts.has("loads"):
		return {"ok": false}
	var mass: float = float(context.mass_kg)
	var gravity: float = float(context.gravity_m_s2)
	var world_force: PackedFloat64Array = M.q_rotate(attitude, contacts.loads.slice(0, 3))
	world_force[2] += mass * gravity
	var world_moment: PackedFloat64Array = M.q_rotate(attitude, contacts.loads.slice(3, 6))
	var residual := PackedFloat64Array([
		world_force[2] / (mass * gravity),
		world_moment[0] / (mass * gravity * scale),
		world_moment[1] / (mass * gravity * scale),
	])
	for value: float in world_force:
		if not is_finite(value): return {"ok": false}
	for value: float in world_moment:
		if not is_finite(value): return {"ok": false}
	return {"ok": true, "state": state, "contacts": contacts, "force_residual_n": world_force,
		"moment_residual_nm": world_moment, "residual": residual}


static func _support_points_are_on_flat_pad(pad: Dictionary, skids: Dictionary,
		surfaces: PackedFloat64Array) -> bool:
	var points: PackedFloat64Array = skids.get("points_body_frd_m", PackedFloat64Array())
	if points.size() != 12:
		return false
	var q: PackedFloat64Array = M.q_from_euler(float(pad.heading), 0.0, 0.0)
	var flat_samples := 0
	for index: int in range(0, 12, 3):
		var arm: PackedFloat64Array = M.q_rotate(q, points.slice(index, index + 3))
		var sample: PackedFloat64Array = GroundTerrain.sample_validated(
			float(pad.north) + arm[0], float(pad.east) + arm[1], surfaces)
		if sample.size() != 3 or absf(sample[0]) > 1.0e-12 or absf(sample[1]) > 1.0e-12 or absf(sample[2]) > 1.0e-12:
			return false
		flat_samples += 1
	return flat_samples == 4


static func _actual_envelope_radius(context: Dictionary, skids: Dictionary) -> Dictionary:
	var main: Dictionary = context.get("main_model", {})
	var tail: Dictionary = context.get("tail_model", {})
	var points: PackedFloat64Array = skids.get("points_body_frd_m", PackedFloat64Array())
	if main.is_empty() or tail.is_empty() or points.size() != 12:
		return {"ok": false, "radius": NAN}
	for key: String in ["hub_x_m", "hub_y_m", "hub_z_m", "rotor_radius_m"]:
		if not main.has(key) or not is_finite(float(main[key])):
			return {"ok": false, "radius": NAN}
	for key: String in ["hub_distance_aft_m", "hub_height_above_cg_m", "tail_rotor_radius_m"]:
		if not tail.has(key) or not is_finite(float(tail[key])):
			return {"ok": false, "radius": NAN}
	var main_hub: float = M.sqrt_(main.hub_x_m * main.hub_x_m + main.hub_y_m * main.hub_y_m + main.hub_z_m * main.hub_z_m)
	var main_reach: float = main_hub + float(main.rotor_radius_m)
	var tail_hub: float = M.sqrt_(tail.hub_distance_aft_m * tail.hub_distance_aft_m + tail.hub_height_above_cg_m * tail.hub_height_above_cg_m)
	var tail_reach: float = tail_hub + float(tail.tail_rotor_radius_m)
	var skid_reach: float = 0.0
	for index: int in range(0, 12, 3):
		skid_reach = maxf(skid_reach, M.norm(points.slice(index, index + 3)))
	return {"ok": true, "radius": maxf(maxf(main_reach, tail_reach), skid_reach),
		"main_disc_reach_m": main_reach, "tail_disc_reach_m": tail_reach, "skid_reach_m": skid_reach}


static func _solve_3x3(matrix: PackedFloat64Array, vector: PackedFloat64Array) -> Dictionary:
	if matrix.size() != 9 or vector.size() != 3:
		return {"ok": false}
	var a := PackedFloat64Array(matrix)
	var b := PackedFloat64Array(vector)
	for pivot: int in 3:
		var best_row: int = pivot
		for row: int in range(pivot + 1, 3):
			if absf(a[row * 3 + pivot]) > absf(a[best_row * 3 + pivot]):
				best_row = row
		if absf(a[best_row * 3 + pivot]) < 1.0e-12:
			return {"ok": false}
		if best_row != pivot:
			for column: int in 3:
				var swap_value: float = a[pivot * 3 + column]
				a[pivot * 3 + column] = a[best_row * 3 + column]
				a[best_row * 3 + column] = swap_value
			var swap_rhs: float = b[pivot]
			b[pivot] = b[best_row]
			b[best_row] = swap_rhs
		var diagonal: float = a[pivot * 3 + pivot]
		for column: int in range(pivot, 3):
			a[pivot * 3 + column] /= diagonal
		b[pivot] /= diagonal
		for row: int in 3:
			if row == pivot:
				continue
			var factor: float = a[row * 3 + pivot]
			for column: int in range(pivot, 3):
				a[row * 3 + column] -= factor * a[pivot * 3 + column]
			b[row] -= factor * b[pivot]
	return {"ok": true, "x": b}


static func _norm(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value * value
	return M.sqrt_(sum)


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
