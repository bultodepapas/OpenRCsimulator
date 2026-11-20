## CR-AUD-20 regression (collision audit 2026-11-17, promoted probe): a terminal quad wall strike leaves the solid at
## its contact and the wreck keeps colliding afterwards; the 3 m/s control keeps its nonterminal bounce.
# Source-only draft; run in a disposable hydrated app project with the checked Godot runner.
# A stock-data, graded quad is reset to a valid, disarmed airborne test frame with stopped
# shafts and prescribed northward velocity. Gravity and the ordinary plant aerodynamics
# remain enabled. This is a synthetic initial condition and synthetic wall, not a flown route.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

const WALL_FRONT_N_M := 0.6
const WALL_BACK_N_M := 0.9
const ALTITUDE_M := 30.0
const RUN_TICKS := 120

var _checks: Array[Dictionary] = []
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, details: Dictionary = {}) -> void:
	_checks.append({"label": label, "ok": ok, "details": details})
	if not ok:
		_failures += 1


func _wall_world() -> Dictionary:
	# Heading zero: length is N/S and width is E/W. This is a 0.3 m thick,
	# 12 m wide, 12 m tall hard box centred at the airborne test height.
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "audit:quad:wall", "building", "wall", "hard_terminal",
		0.5 * (WALL_FRONT_N_M + WALL_BACK_N_M), 0.0, -ALTITUDE_M,
		12.0, 12.0, WALL_BACK_N_M - WALL_FRONT_N_M, 0.0)
	return {"format": CollisionWorld.FORMAT, "identity": "audit-quad-wall-v1",
		"cell_size_m": CollisionWorld.CELL_SIZE_M, "proxies": proxies,
		"bins": CollisionWorld._build_bins(proxies)}


func _sample(s: Node) -> Dictionary:
	var body: PackedFloat64Array = s.sim.state
	var attitude: PackedFloat64Array = RB._att(body)
	var center_model: PackedFloat64Array = s.plant._frame_box_centre
	var half: PackedFloat64Array = s.plant._frame_box_half
	var center_offset: PackedFloat64Array = M.q_rotate(attitude, center_model)
	var body_velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var body_rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var world_velocity: PackedFloat64Array = M.q_rotate(attitude, body_velocity)
	var wall_normal_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), M.v3(-1.0, 0.0, 0.0))
	var support: Dictionary = s.plant._box_support(wall_normal_body)
	var contact_body: PackedFloat64Array = support.point
	var contact_velocity: PackedFloat64Array = M.q_rotate(attitude,
		M.add(body_velocity, M.cross(body_rates, contact_body)))
	var axes: Array[PackedFloat64Array] = [M.v3(1.0, 0.0, 0.0), M.v3(0.0, 1.0, 0.0), M.v3(0.0, 0.0, 1.0)]
	var north_extent := 0.0
	for i in 3:
		var axis_world: PackedFloat64Array = M.q_rotate(attitude, axes[i])
		north_extent += float(half[i]) * absf(axis_world[0])
	var center_north: float = body[RB.POS] + center_offset[0]
	var front: float = center_north + north_extent
	var rear: float = center_north - north_extent
	return {"tick": int(s.sim.tick), "time_s": float(s.sim.time()),
		"position_ned_m": [body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]],
		"world_velocity_ned_mps": [world_velocity[0], world_velocity[1], world_velocity[2]],
		"cg_inward_velocity_mps": world_velocity[0],
		"front_contact_inward_velocity_mps": contact_velocity[0],
		"frame_front_north_m": front, "frame_rear_north_m": rear,
		"front_penetration_m": maxf(front - WALL_FRONT_N_M, 0.0),
		"rear_past_wall_back_m": rear - WALL_BACK_N_M,
		"motor_mode": int(s.sim.modes[FC.MODE_MOTOR]),
		"arm_block": int(s.sim.modes[FC.MODE_ARM_BLOCK]),
		"cut_latch": float(s.sim.continuous[Plant.C_CUT_LATCH])}


func _run_case(label: String, speed: float, with_wall: bool) -> Dictionary:
	var s: Node = Session.new()
	root.add_child(s)
	var out := {"label": label, "initial_speed_mps": speed, "with_wall": with_wall,
		"ready": false, "accepted_ticks": 0, "events": [], "samples": [],
		"crash": {}, "crash_sample": {}, "first_frame_impact": {},
		"fully_crossed_after_crash": false, "max_rear_past_wall_back_m": -1000000.0}
	var options := {"crash_model": "graded", "start": "air", "altitude_m": ALTITUDE_M,
		"north_offset_m": 0.0, "east_offset_m": 0.0, "heading_deg": 0.0}
	var prepared: bool = s.prepare({}, options)
	_check(label + ": stock quad session prepares", prepared, {"error": str(s.load_error)})
	if not prepared:
		s.free()
		return out
	_check(label + ": graded electric plant", bool(s.plant.electric) and bool(s.plant.graded_impacts))
	if with_wall:
		var installed: bool = s.set_collision_world(_wall_world())
		_check(label + ": hard box installs through the session", installed)
		if not installed:
			s.free()
			return out
	var pilot: PackedFloat64Array = FC.neutral_input(0)
	var frame: Dictionary = s.frame()
	var body: PackedFloat64Array = frame.body
	body[RB.VEL] = speed # heading zero, so body forward is north
	frame.body = body
	var continuous: PackedFloat64Array = frame.continuous
	for rotor in 4:
		continuous[Plant.C_SPEED + rotor] = 0.0 # isolate frame contact from prop-disc contact
	frame.continuous = continuous
	var in_domain: bool = s.plant.state_validator(frame, {})
	_check(label + ": prescribed frame is valid", in_domain)
	if not in_domain:
		s.free()
		return out
	var reset: Dictionary = s.sim.prepare_reset_frame(frame, pilot)
	var committed: bool = bool(reset.get("ok", false)) and s.sim.commit_prepared_reset_frame(reset)
	_check(label + ": initial frame commits", committed, {"message": str(reset.get("message", ""))})
	if not committed:
		s.free()
		return out
	var resumed: bool = s.resume()
	_check(label + ": session resumes", resumed)
	if not resumed:
		s.free()
		return out
	out.ready = true
	out.initial = _sample(s)
	for _step in RUN_TICKS:
		if not s.tick_once(pilot):
			break
		out.accepted_ticks = int(s.sim.tick)
		var sample := _sample(s)
		var event_on_tick := false
		for event: Dictionary in s.sim.last_events:
			event_on_tick = true
			var summary := {"tick": int(s.sim.tick), "type": str(event.get("type", "")),
				"reason": str(event.get("reason", "")), "part": str(event.get("part", "")),
				"surface": str(event.get("surface", ""))}
			if event.has("normal_speed_mps"):
				summary["normal_speed_mps"] = float(event.normal_speed_mps)
			out.events.append(summary)
			if str(event.get("type", "")) == "impact" and str(event.get("part", "")) == "frame" \
					and (out.first_frame_impact as Dictionary).is_empty():
				out.first_frame_impact = {"event": summary, "sample": sample}
		if not s.crash.is_empty() and (out.crash as Dictionary).is_empty():
			out.crash = s.crash.duplicate(true)
			out.crash_sample = sample
		if not (out.crash as Dictionary).is_empty():
			out.max_rear_past_wall_back_m = maxf(float(out.max_rear_past_wall_back_m), float(sample.rear_past_wall_back_m))
			if float(sample.rear_past_wall_back_m) > 0.0:
				out.fully_crossed_after_crash = true
		var since_crash: int = int(s.sim.tick) - int(out.crash.get("tick", -10000))
		if event_on_tick or int(s.sim.tick) % 24 == 0 or since_crash in [1, 4, 12, 24, 48, 72]:
			out.samples.append(sample)
	out.final = _sample(s)
	out.fault = str(s.fault_reason)
	out.paused = bool(s.paused)
	_check(label + ": all requested ticks accepted", int(out.accepted_ticks) == RUN_TICKS,
		{"accepted": out.accepted_ticks, "fault": out.fault, "paused": out.paused})
	s.free()
	return out


func _event_count(result: Dictionary, type: String) -> int:
	var count := 0
	for event: Dictionary in result.get("events", []):
		if str(event.get("type", "")) == type:
			count += 1
	return count


func _run() -> void:
	_check("project uses the session's 240 Hz fixed step", Engine.physics_ticks_per_second == Session.FIXED_HZ,
		{"physics_ticks_per_second": Engine.physics_ticks_per_second})
	var slow := _run_case("wall_3_mps", 3.0, true)
	var fast := _run_case("wall_9_mps", 9.0, true)
	var slow_clear := _run_case("clear_3_mps", 3.0, false)
	var fast_clear := _run_case("clear_9_mps", 9.0, false)
	if bool(slow.ready):
		var first: Dictionary = slow.first_frame_impact
		_check("3 m/s wall contact is an observed, nonterminal frame bounce",
			not first.is_empty() and (slow.crash as Dictionary).is_empty()
			and float((first.get("sample", {}) as Dictionary).get("front_contact_inward_velocity_mps", 1.0)) < 0.0,
			{"first_frame_impact": first, "crash": slow.crash})
	if bool(fast.ready):
		var crash: Dictionary = fast.crash
		var final: Dictionary = fast.final
		_check("9 m/s hard-box hit publishes one obstacle crash and latches the cut",
			str(crash.get("reason", "")) == "Obstacle strike" and _event_count(fast, "crash") == 1
			and int(final.get("motor_mode", -1)) == FC.MOTOR_CRASHED
			and float(final.get("cut_latch", -1.0)) == 1.0,
			{"crash": crash, "event_count": _event_count(fast, "crash"), "final": final})
		# Desired invariant, not a calibrated restitution model: the visible frame should
		# not pass fully through a fixed solid after a terminal frame contact. Endpoint
		# detection can still produce a small initial overlap at the impact tick.
		_check("terminal frame does not fully cross the hard box during aftermath",
			not bool(fast.fully_crossed_after_crash),
			{"max_rear_past_wall_back_m": fast.max_rear_past_wall_back_m,
				"crash_sample": fast.crash_sample, "final": final})
	for clear: Dictionary in [slow_clear, fast_clear]:
		if bool(clear.ready):
			_check(str(clear.label) + ": no wall means no impact or crash",
				(clear.crash as Dictionary).is_empty() and _event_count(clear, "crash") == 0
				and _event_count(clear, "impact") == 0,
				{"events": clear.events, "crash": clear.crash})
	var result := {"fixture": "stock quad; disarmed air start; stopped shafts; gravity and ordinary aero; synthetic hard box",
		"wall_front_north_m": WALL_FRONT_N_M, "wall_back_north_m": WALL_BACK_N_M,
		"cases": [slow, fast, slow_clear, fast_clear], "assertions": _checks,
		"assertion_count": _checks.size(), "failure_count": _failures}
	print("ROUND2_QUAD_OBSTACLE_AFTERMATH_JSON " + JSON.stringify(result))
	print("ROUND2_QUAD_OBSTACLE_AFTERMATH_COMPLETE assertions=%d failures=%d" % [_checks.size(), _failures])
	quit(1 if _failures > 0 else 0)
