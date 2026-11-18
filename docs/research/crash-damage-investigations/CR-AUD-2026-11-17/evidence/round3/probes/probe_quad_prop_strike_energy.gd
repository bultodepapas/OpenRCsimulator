# Source-only draft: run with the checked Godot runner in a hydrated disposable app.
# This is a prescribed, initially overlapping prop-only pose, not a flown trajectory.
# It calls the production graded-contact transition directly; no integration tick,
# gravity/aero work, motor work, ground contact, or charging occurs during the comparison.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const ALTITUDE_M := 30.0
const FULL_BITE_M := 0.020
const INWARD_MPS := 0.10
const TANGENTIAL_MPS := 25.0
const ENERGY_TOLERANCE_J := 1.0e-8

var _wall_radial := PackedFloat64Array([1.0, 0.0, 0.0])
var _wall_distance := 0.0
var _checks: Array[Dictionary] = []
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(name: String, condition: bool, detail: Dictionary = {}) -> void:
	_checks.append({"name": name, "ok": condition, "detail": detail})
	if not condition:
		_failures += 1


func _wall(north: float, east: float, down: float) -> float:
	return _wall_distance - M.dot(_wall_radial, M.v3(north, east, down))


func _hard_class(_north: float, _east: float, _down: float) -> String:
	return "hard_terminal"


func _plain3(v: PackedFloat64Array) -> Array:
	return [v[0], v[1], v[2]]


func _energy(prepared: Dictionary, body: PackedFloat64Array, continuous: PackedFloat64Array) -> Dictionary:
	# prepared.inertia_kg_m2 is the locked inertia including the rotors. For each
	# coaxial rotor the physical FRD shaft spin relative to the body is
	# -spin_i * omega_i about +z. Thus the independent total kinetic energy is
	# 1/2 m v^2 + 1/2 w^T I_locked w + sum(1/2 I_i omega_i^2)
	# + w_z * sum(-spin_i I_i omega_i). The cross term avoids double-counting
	# the rotating-body contribution already present in locked inertia.
	var v: PackedFloat64Array = RB._slice3(body, RB.VEL)
	var w: PackedFloat64Array = RB._slice3(body, RB.RATE)
	var linear := 0.5 * float(prepared.mass_kg) * M.dot(v, v)
	var rotational := 0.5 * M.dot(w, RB.inertia_mul(prepared.inertia_kg_m2, w))
	var relative_shafts := 0.0
	var shaft_momentum_z := 0.0
	for i in 4:
		var rotor: Dictionary = prepared.rotors[i]
		var inertia := float(rotor.inertia_kg_m2)
		var speed := float(continuous[Plant.C_SPEED + i])
		relative_shafts += 0.5 * inertia * speed * speed
		shaft_momentum_z += -float(rotor.spin) * inertia * speed
	var cross_term := w[2] * shaft_momentum_z
	return {"linear_j": linear, "locked_rotation_j": rotational,
		"relative_shafts_j": relative_shafts, "body_shaft_cross_j": cross_term,
		"total_kinetic_j": linear + rotational + relative_shafts + cross_term}


func _event_summaries(events: Array) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		result.append({"type": str(event.get("type", "")), "cause": str(event.get("cause", "")),
			"rotor": int(event.get("rotor", -1)), "part": str(event.get("part", ""))})
	return result


func _case(label: String, s: Node, rotor_index: int, radial: PackedFloat64Array,
		reaction: PackedFloat64Array, tangential_speed: float, rotor_speed: float, wall: bool) -> Dictionary:
	var p: RefCounted = s.plant
	p.obstacle = Callable(self, "_wall") if wall else Callable()
	p.obstacle_class = Callable(self, "_hard_class") if wall else Callable()
	var frame: Dictionary = s.frame()
	var body: PackedFloat64Array = frame.body
	var velocity := M.add(M.scale(reaction, tangential_speed), M.scale(radial, INWARD_MPS))
	for axis in 3:
		body[RB.VEL + axis] = velocity[axis]
		body[RB.RATE + axis] = 0.0
	frame.body = body
	var continuous: PackedFloat64Array = frame.continuous
	for i in 4:
		continuous[Plant.C_SPEED + i] = rotor_speed if i == rotor_index else 0.0
	frame.continuous = continuous
	var domain_ok: bool = p.state_validator(frame, {})
	var candidate: Dictionary = s.sim.prepare_reset_frame(frame, FC.neutral_input(0))
	_check(label + ": prescribed frame is accepted by the stock model", domain_ok and bool(candidate.get("ok", false)),
		{"reset_message": str(candidate.get("message", ""))})
	if not domain_ok or not bool(candidate.get("ok", false)):
		return {"label": label, "valid": false}
	var before := _energy(p.prepared, body, continuous)
	var result: Dictionary = p._graded_impacts(body, body, continuous, 0.0)
	var after_body: PackedFloat64Array = result.body
	var after_continuous: PackedFloat64Array = result.continuous
	var after := _energy(p.prepared, after_body, after_continuous)
	var mass := float(p.prepared.mass_kg)
	var impulse: PackedFloat64Array = M.scale(M.sub(RB._slice3(after_body, RB.VEL), velocity), mass)
	var rotor: Dictionary = p.prepared.rotors[rotor_index]
	var radius := 0.5 * float(rotor.diameter_m)
	var arm := M.scale(radial, radius)
	var rotor_tip: PackedFloat64Array = M.cross(M.v3(0.0, 0.0, -float(rotor.spin) * rotor_speed), arm)
	var contact_velocity := M.add(velocity, rotor_tip) # initial body rates are zero
	var source_unchanged := true
	for index in [Plant.C_CHARGE, Plant.C_TERMINAL_ENERGY, Plant.C_PACK_LOSS, Plant.C_CUT_LATCH]:
		source_unchanged = source_unchanged and after_continuous[index] == continuous[index]
	return {"label": label, "valid": true, "with_wall": wall,
		"tangential_speed_mps": tangential_speed, "inward_speed_mps": INWARD_MPS,
		"body_velocity_before_frd_mps": _plain3(velocity),
		"body_velocity_after_frd_mps": _plain3(RB._slice3(after_body, RB.VEL)),
		"body_rates_after_rad_s": _plain3(RB._slice3(after_body, RB.RATE)),
		"position_before_ned_m": _plain3(RB._slice3(body, RB.POS)),
		"position_after_ned_m": _plain3(RB._slice3(after_body, RB.POS)),
		"rotor_omega_before_rad_s": continuous[rotor_index],
		"rotor_omega_after_rad_s": after_continuous[rotor_index],
		"rotor_health_before": continuous[Plant.C_HEALTH + rotor_index],
		"rotor_health_after": after_continuous[Plant.C_HEALTH + rotor_index],
		"initial_contact_velocity_frd_mps": _plain3(contact_velocity),
		"net_body_impulse_frd_ns": _plain3(impulse),
		"initial_contact_velocity_dot_net_impulse_j": M.dot(contact_velocity, impulse),
		"energy_before": before, "energy_after": after,
		"delta_kinetic_j": float(after.total_kinetic_j) - float(before.total_kinetic_j),
		"source_energy_and_cut_fields_unchanged": source_unchanged,
		"reason": str(result.reason), "events": _event_summaries(result.events)}


func _run() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var prepared: bool = s.prepare({}, {"crash_model": "graded", "start": "air", "altitude_m": ALTITUDE_M,
		"north_offset_m": 0.0, "east_offset_m": 0.0, "heading_deg": 0.0})
	_check("stock electric quad prepares", prepared, {"error": str(s.load_error)})
	if not prepared:
		_finish({"cases": []})
		s.free()
		return
	var p: RefCounted = s.plant
	_check("graded electric law is selected", bool(p.graded_impacts) and bool(p.electric))
	var rotor_index := 0
	var rotor: Dictionary = p.prepared.rotors[rotor_index]
	var hub: PackedFloat64Array = rotor.hub_frd
	var radial := M.v3(hub[0], hub[1], 0.0)
	radial = M.scale(radial, 1.0 / M.norm(radial))
	var radius := 0.5 * float(rotor.diameter_m)
	var speed := float(p.prepared.contacts.rotor_strike_speed_rad_s) + 1.0
	var spin := float(rotor.spin)
	var tip: PackedFloat64Array = M.cross(M.v3(0.0, 0.0, -spin * speed), M.scale(radial, radius))
	var reaction: PackedFloat64Array = M.scale(tip, -1.0 / M.norm(tip))
	_wall_radial = radial
	_wall_distance = M.dot(hub, radial) + radius - FULL_BITE_M
	var centre: PackedFloat64Array = p._frame_box_centre
	var half: PackedFloat64Array = p._frame_box_half
	var frame_reach := M.dot(centre, radial)
	for i in 3:
		frame_reach += half[i] * absf(radial[i])
	var frame_gap := _wall_distance - frame_reach
	var actual_bite := radius - (_wall_distance - M.dot(hub, radial))
	_check("wall intersects selected prop disc but leaves the frame box clear",
		frame_gap > 0.01 and actual_bite >= Plant.PROP_FULL_BITE_M,
		{"frame_gap_m": frame_gap, "selected_prop_bite_m": actual_bite})
	var positive := _case("wall_tangent_with_kick", s, rotor_index, radial, reaction, TANGENTIAL_MPS, speed, true)
	var still := _case("wall_zero_tangent", s, rotor_index, radial, reaction, 0.0, speed, true)
	var opposite := _case("wall_opposite_tangent", s, rotor_index, radial, reaction, -TANGENTIAL_MPS, speed, true)
	var stopped := _case("wall_stopped_prop", s, rotor_index, radial, reaction, TANGENTIAL_MPS, 0.0, true)
	var clear := _case("no_wall", s, rotor_index, radial, reaction, TANGENTIAL_MPS, speed, false)
	var all_valid := bool(positive.valid) and bool(still.valid) and bool(opposite.valid) \
		and bool(stopped.valid) and bool(clear.valid)
	if all_valid:
		for collision: Dictionary in [positive, still, opposite]:
			var events: Array = collision.events
			_check(str(collision.label) + ": prop-only contact is nonterminal and brakes the selected shaft",
				str(collision.reason).is_empty() and events.size() == 1
				and str(events[0].get("type", "")) == "prop_damage"
				and str(events[0].get("cause", "")) == "obstacle"
				and int(events[0].get("rotor", -1)) == rotor_index
				and float(collision.rotor_omega_after_rad_s) < float(collision.rotor_omega_before_rad_s)
				and bool(collision.source_energy_and_cut_fields_unchanged), {"case": collision})
		for control: Dictionary in [stopped, clear]:
			_check(str(control.label) + ": no prop strike and no kinetic change",
				str(control.reason).is_empty() and (control.events as Array).is_empty()
				and absf(float(control.delta_kinetic_j)) < ENERGY_TOLERANCE_J, {"case": control})
		_check("zero-tangent prop strike does not increase coupled kinetic energy",
			float(still.delta_kinetic_j) <= ENERGY_TOLERANCE_J, {"delta_kinetic_j": still.delta_kinetic_j})
		_check("opposite-tangent prop strike does not increase coupled kinetic energy",
			float(opposite.delta_kinetic_j) <= ENERGY_TOLERANCE_J, {"delta_kinetic_j": opposite.delta_kinetic_j})
		# Desired invariant: an instantaneous collision with a static wall cannot
		# increase the combined locked-body plus relative-shaft kinetic energy.
		_check("moving prop strike does not increase coupled kinetic energy",
			float(positive.delta_kinetic_j) <= ENERGY_TOLERANCE_J,
			{"delta_kinetic_j": positive.delta_kinetic_j, "case": positive})
	var output := {"scope": "production graded-contact transition; prescribed prop-only wall overlap; no tick integration",
		"energy_model": "locked-body inertia plus relative shaft energies and body-shaft cross term",
		"rotor_index": rotor_index, "rotor_speed_rad_s": speed, "rotor_radius_m": radius,
		"shaft_tip_speed_mps": radius * speed, "wall_radial_frd": _plain3(radial),
		"reaction_direction_frd": _plain3(reaction), "wall_distance_m": _wall_distance,
		"frame_clearance_m": frame_gap, "prop_bite_m": actual_bite,
		"cases": [positive, still, opposite, stopped, clear]}
	s.free()
	_finish(output)


func _finish(output: Dictionary) -> void:
	output["assertion_count"] = _checks.size()
	output["failure_count"] = _failures
	output["assertions"] = _checks
	print("ROUND3_QUAD_PROP_STRIKE_ENERGY_JSON " + JSON.stringify(output))
	print("ROUND3_QUAD_PROP_STRIKE_ENERGY_COMPLETE assertions=%d failures=%d" % [_checks.size(), _failures])
	quit(1 if _failures > 0 else 0)
