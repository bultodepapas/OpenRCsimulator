# Source-only draft: run in a hydrated disposable app with the checked runner.
# Stock graded quad and production box/world/query; prescribed valid airborne
# frame, stationary body, exactly one spinning rotor. Calls _graded_impacts
# directly: no accepted integration tick, gravity, or motor work is claimed.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

const ALTITUDE_M := 30.0
const SELECTED := 1 # stock rotor with positive forward and right hub coordinates
const BOX_HALF_M := 0.005
const BODY_EPS := 1.0e-12

var _checks: Array[Dictionary] = []
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: Dictionary = {}) -> void:
	_checks.append({"label": label, "ok": ok, "detail": detail})
	if not ok:
		_failures += 1


func _plain3(v: PackedFloat64Array) -> Array:
	return [v[0], v[1], v[2]]


func _world(center: PackedFloat64Array, label: String, extra_center: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	# Heading zero: width runs east, length north. All three edges are 10 mm.
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "audit:quad:primary", "building", "box", "hard_terminal",
		center[0], center[1], center[2], 2.0 * BOX_HALF_M, 2.0 * BOX_HALF_M, 2.0 * BOX_HALF_M, 0.0)
	if extra_center.size() == 3:
		CollisionWorld._add_box_at_down(proxies, "audit:quad:decoy", "building", "box", "hard_terminal",
			extra_center[0], extra_center[1], extra_center[2], 2.0 * BOX_HALF_M, 2.0 * BOX_HALF_M, 2.0 * BOX_HALF_M, 0.0)
	return {"format": CollisionWorld.FORMAT, "identity": "quad-disc-box-" + label,
		"cell_size_m": CollisionWorld.CELL_SIZE_M, "proxies": proxies,
		"bins": CollisionWorld._build_bins(proxies)}


func _events(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		out.append({"type": str(event.get("type", "")), "cause": str(event.get("cause", "")),
			"rotor": int(event.get("rotor", -1)), "health": float(event.get("health", -1.0)),
			"part": str(event.get("part", ""))})
	return out


func _nearest(proxies: Array[Dictionary], point: PackedFloat64Array) -> Dictionary:
	var nearest := INF
	var id := ""
	var distances: Array = []
	for proxy: Dictionary in proxies:
		var distance := Session._clearance(proxy, point[0], point[1], point[2])
		distances.append({"id": str(proxy.id), "clearance_m": distance})
		if distance < nearest:
			nearest = distance
			id = str(proxy.id)
	return {"id": id, "clearance_m": nearest, "distances": distances}


func _normal_samples(p: RefCounted, proxies: Array[Dictionary], point: PackedFloat64Array) -> Array:
	# A central difference samples the UNION field at six different locations.
	# Record each nearest proxy independently; the one nearest at the hub need
	# not be the one determining either side of a difference.
	var samples: Array = []
	for axis in 3:
		for direction: float in [-1.0, 1.0]:
			var sample: PackedFloat64Array = point.duplicate()
			sample[axis] += direction * Plant.OBSTACLE_NORMAL_STEP_M
			var nearest := _nearest(proxies, sample)
			samples.append({"axis": axis, "direction": direction, "nearest_id": str(nearest.id),
				"per_proxy_clearances": nearest.distances,
				"callback_clearance_m": float(p.obstacle.call(sample[0], sample[1], sample[2]))})
	return samples


func _case(s: Node, label: String, east_offset: float, down_offset: float, spinning: bool,
		extra_offset: PackedFloat64Array = PackedFloat64Array()) -> Dictionary:
	var p: RefCounted = s.plant
	var frame: Dictionary = s.frame()
	var pos := M.v3(0.0, 0.0, -ALTITUDE_M)
	frame.body = RB.make_state(pos, M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var continuous: PackedFloat64Array = frame.continuous
	for i in 4:
		continuous[Plant.C_SPEED + i] = 0.0
	if spinning:
		continuous[Plant.C_SPEED + SELECTED] = float(p.prepared.contacts.rotor_strike_speed_rad_s) + 1.0
	frame.continuous = continuous
	var rotor: Dictionary = p.prepared.rotors[SELECTED]
	var hub: PackedFloat64Array = M.add(pos, rotor.hub_frd)
	var radius: float = 0.5 * float(rotor.diameter_m)
	var center: PackedFloat64Array = M.add(hub, M.v3(0.0, east_offset, down_offset))
	var extra_center := PackedFloat64Array()
	if extra_offset.size() == 3:
		extra_center = M.add(hub, extra_offset)
	var world := _world(center, label, extra_center)
	var installed: bool = s.set_collision_world(world)
	var domain_ok: bool = p.state_validator(frame, {})
	var reset: Dictionary = s.sim.prepare_reset_frame(frame, FC.neutral_input(0))
	var reset_ok: bool = bool(reset.get("ok", false))
	_check(label + ": world installs and prescribed frame validates", installed and domain_ok and reset_ok,
		{"installed": installed, "domain_valid": domain_ok, "reset_prepared": reset_ok,
			"reset_message": str(reset.get("message", ""))})
	if not installed or not domain_ok or not reset_ok:
		return {"label": label, "valid": false}
	var proxies: Array[Dictionary] = world.proxies
	var clearance: float = float(p.obstacle.call(hub[0], hub[1], hub[2]))
	var nearest_hub := _nearest(proxies, hub)
	var direct_clearance: float = float(nearest_hub.clearance_m)
	var normal: PackedFloat64Array = p._obstacle_normal(hub)
	var normal_samples := _normal_samples(p, proxies, hub)
	# Identity attitude, so this is already the same normal in body axes.
	var support: Dictionary = Plant._disc_support(normal, M.v3(0.0, 0.0, -1.0), radius)
	var depth: float = float(support.extent) - clearance
	var box_center: PackedFloat64Array = M.add(pos, p._frame_box_centre)
	var box_center_clearance: float = float(p.obstacle.call(box_center[0], box_center[1], box_center[2]))
	var broad_radius: float = M.norm(p._frame_box_half)
	# Independent geometric oracles, valid for this axis-aligned, level fixture:
	# prop occupies |down-hub.down| <= half thickness; the obstacle's east
	# minimum is outside the frame box's east maximum. No SDF normal is used.
	var prop_vertical_gap: float = absf(center[2] - hub[2]) - BOX_HALF_M - Plant.PROP_DISC_HALF_THICKNESS_M
	var frame_east_gap: float = (center[1] - BOX_HALF_M) \
		- (box_center[1] + float(p._frame_box_half[1]))
	var extra_frame_east_gap := INF
	var extra_prop_vertical_gap := INF
	if extra_center.size() == 3:
		extra_frame_east_gap = (extra_center[1] - BOX_HALF_M) \
			- (box_center[1] + float(p._frame_box_half[1]))
		extra_prop_vertical_gap = absf(extra_center[2] - hub[2]) - BOX_HALF_M - Plant.PROP_DISC_HALF_THICKNESS_M
	var center_radial_distance := absf(center[1] - hub[1])
	_check(label + ": real query selects hard box, frame is separately clear",
		absf(clearance - direct_clearance) < BODY_EPS \
		and str(p.obstacle_class.call(hub[0], hub[1], hub[2])) == "hard_terminal" \
		and frame_east_gap > 0.0 and extra_frame_east_gap > 0.0 and box_center_clearance > broad_radius,
		{"frame_east_gap_m": frame_east_gap, "frame_center_clearance_m": box_center_clearance,
			"frame_broad_radius_m": broad_radius, "hub_clearance_m": clearance,
			"direct_proxy_clearance_m": direct_clearance})
	var before_body: PackedFloat64Array = (frame.body as PackedFloat64Array).duplicate()
	var before_continuous: PackedFloat64Array = continuous.duplicate()
	var result: Dictionary = p._graded_impacts(before_body, before_body, before_continuous, 0.0)
	var after_body: PackedFloat64Array = result.body
	var after_continuous: PackedFloat64Array = result.continuous
	var after_frame: Dictionary = frame.duplicate(true)
	after_frame.body = after_body
	after_frame.continuous = after_continuous
	var output_valid: bool = p.state_validator(after_frame, {})
	var output_reset: Dictionary = s.sim.prepare_reset_frame(after_frame, FC.neutral_input(0))
	_check(label + ": returned frame is within the stock model domain", output_valid \
		and bool(output_reset.get("ok", false)), {"reset_message": str(output_reset.get("message", ""))})
	var result_info := {"label": label, "valid": true, "spinning": spinning,
		"box_center_ned_m": _plain3(center), "hub_ned_m": _plain3(hub),
		"rotor_index": SELECTED, "rotor_radius_m": radius,
		"disc_half_thickness_m": Plant.PROP_DISC_HALF_THICKNESS_M,
		"box_half_extents_m": [BOX_HALF_M, BOX_HALF_M, BOX_HALF_M],
		"prop_vertical_gap_m": prop_vertical_gap, "box_center_radial_distance_m": center_radial_distance,
		"frame_east_gap_m": frame_east_gap, "frame_center_clearance_m": box_center_clearance,
		"frame_broad_radius_m": broad_radius, "hub_clearance_m": clearance,
		"direct_proxy_clearance_m": direct_clearance, "finite_difference_normal_ned": _plain3(normal),
		"nearest_at_hub": nearest_hub, "normal_samples": normal_samples,
		"normal_difference_step_m": Plant.OBSTACLE_NORMAL_STEP_M,
		"disc_support_m": float(support.extent), "support_minus_clearance_m": depth,
		"reason": str(result.reason), "events": _events(result.events),
		"omega_before_rad_s": before_continuous[Plant.C_SPEED + SELECTED],
		"omega_after_rad_s": after_continuous[Plant.C_SPEED + SELECTED],
		"health_before": before_continuous[Plant.C_HEALTH + SELECTED],
		"health_after": after_continuous[Plant.C_HEALTH + SELECTED],
		"position_before_ned_m": _plain3(RB._slice3(before_body, RB.POS)),
		"position_after_ned_m": _plain3(RB._slice3(after_body, RB.POS)),
		"velocity_before_frd_mps": _plain3(RB._slice3(before_body, RB.VEL)),
		"velocity_after_frd_mps": _plain3(RB._slice3(after_body, RB.VEL)),
		"rates_before_rad_s": _plain3(RB._slice3(before_body, RB.RATE)),
		"rates_after_rad_s": _plain3(RB._slice3(after_body, RB.RATE)),
		"body_changed": after_body != before_body, "continuous_changed": after_continuous != before_continuous}
	if extra_center.size() == 3:
		result_info["extra_box_center_ned_m"] = _plain3(extra_center)
		result_info["extra_box_frame_east_gap_m"] = extra_frame_east_gap
		result_info["extra_box_prop_vertical_gap_m"] = extra_prop_vertical_gap
	return result_info


func _no_prop_damage(c: Dictionary) -> bool:
	return (c.events as Array).is_empty() and float(c.omega_after_rad_s) == float(c.omega_before_rad_s) \
		and float(c.health_after) == float(c.health_before) and not bool(c.body_changed) \
		and not bool(c.continuous_changed) and str(c.reason).is_empty()


func _run() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var prepared: bool = s.prepare({}, {"crash_model": "graded", "start": "air", "altitude_m": ALTITUDE_M,
		"north_offset_m": 0.0, "east_offset_m": 0.0, "heading_deg": 0.0})
	_check("stock electric graded quad prepares", prepared and bool(s.plant.electric) and bool(s.plant.graded_impacts),
		{"error": str(s.load_error)})
	if not prepared:
		s.free()
		_finish([])
		return
	# The separated box is 12 mm away from the entire disc volume in the
	# vertical direction. The overlap control translates only the box down to
	# the disc plane; its centre is inside the disc and inside the box.
	var separated := _case(s, "separated_spinning", 0.060, -0.020, true)
	var overlapping := _case(s, "overlapping_spinning", 0.060, 0.0, true)
	var remote := _case(s, "remote_spinning", 0.200, -0.020, true)
	var stopped := _case(s, "separated_stopped", 0.060, -0.020, false)
	var decoy := _case(s, "decoy_alone", 0.0051, -0.059, true)
	var both := _case(s, "contact_and_decoy", 0.060, 0.0, true, M.v3(0.0, 0.0051, -0.059))
	var cases: Array = [separated, overlapping, remote, stopped, decoy, both]
	if bool(separated.valid) and bool(overlapping.valid) and bool(remote.valid) and bool(stopped.valid) \
			and bool(decoy.valid) and bool(both.valid):
		_check("independent geometry proves the separated disc and box have a 12 mm vertical gap",
			absf(float(separated.prop_vertical_gap_m) - 0.012) < 1.0e-10,
			{"case": separated})
		_check("overlap control has a box-center witness inside the disc and disc thickness",
			float(overlapping.prop_vertical_gap_m) < 0.0 \
			and float(overlapping.box_center_radial_distance_m) < float(overlapping.rotor_radius_m),
			{"case": overlapping})
		var positive_events: Array = overlapping.events
		_check("overlapping spinning prop reports damage and braking",
			positive_events.size() == 1 and str(positive_events[0].get("type", "")) == "prop_damage" \
			and str(positive_events[0].get("cause", "")) == "obstacle" \
			and int(positive_events[0].get("rotor", -1)) == SELECTED \
			and float(overlapping.omega_after_rad_s) < float(overlapping.omega_before_rad_s) \
			and float(overlapping.health_after) < float(overlapping.health_before), {"case": overlapping})
		_check("remote spinning prop is unchanged", _no_prop_damage(remote), {"case": remote})
		_check("separated stopped prop is unchanged", _no_prop_damage(stopped), {"case": stopped})
		_check("decoy alone is separated from prop and unchanged", float(decoy.prop_vertical_gap_m) > 0.05 \
			and _no_prop_damage(decoy), {"case": decoy})
		_check("two-box fixture has an intersection witness and a separated decoy",
			float(both.prop_vertical_gap_m) < 0.0 \
			and float(both.box_center_radial_distance_m) < float(both.rotor_radius_m) \
			and float(both.extra_box_prop_vertical_gap_m) > 0.05 \
			and float(both.extra_box_frame_east_gap_m) > 0.0,
			{"case": both})
		_check("the decoy is nearest at the hub in the two-box fixture",
			str((both.nearest_at_hub as Dictionary).id) == "audit:quad:decoy",
			{"nearest_at_hub": both.nearest_at_hub, "normal_samples": both.normal_samples})
		var both_events: Array = both.events
		# Desired invariant: a separate nearby solid cannot suppress a real prop
		# intersection, regardless of which proxy determines the hub normal.
		_check("contacting prop is still damaged with a closer separated decoy",
			both_events.size() == 1 and str(both_events[0].get("type", "")) == "prop_damage" \
			and str(both_events[0].get("cause", "")) == "obstacle" \
			and int(both_events[0].get("rotor", -1)) == SELECTED \
			and float(both.omega_after_rad_s) < float(both.omega_before_rad_s) \
			and float(both.health_after) < float(both.health_before), {"case": both})
		# Desired invariant: absent geometric contact, a stationary obstacle must
		# not cause a prop event, health loss, shaft braking, kick, or push-out.
		_check("separated spinning prop is unchanged", _no_prop_damage(separated), {"case": separated})
	s.free()
	_finish(cases)


func _finish(cases: Array) -> void:
	var output := {"scope": "direct production graded-contact transition with validated prescribed stock frame; no tick integration",
		"cases": cases, "assertions": _checks, "assertion_count": _checks.size(), "failure_count": _failures}
	print("ROUND4_QUAD_DISC_BOX_SEPARATION_JSON " + JSON.stringify(output))
	print("ROUND4_QUAD_DISC_BOX_SEPARATION_COMPLETE assertions=%d failures=%d" % [_checks.size(), _failures])
	quit(1 if _failures > 0 else 0)
