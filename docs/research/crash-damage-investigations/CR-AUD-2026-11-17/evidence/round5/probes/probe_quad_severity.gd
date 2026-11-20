## Draft only. Copy into a disposable hydrated app's res:// path and use the
## checked runner. No Godot execution has been performed for this draft.
## Two modes: (1) real accepted stock-quad session ticks from prescribed
## near-ground frames; (2) a direct endpoint-transition isolation. Both route
## the resulting state through the real Activity._on_crashed and QuadCrashFx.crash;
## the inert audio receiver captures its actual severity dictionary.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const QuadFx := preload("res://vehicles/multirotor/quad_crash_fx.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


class VisualStandIn extends RefCounted:
	var root := Node3D.new()


class CaptureAudio extends Node3D:
	var reports: Array[Dictionary] = []
	func impact(_position: Vector3, severity: Dictionary, _turbine: bool) -> void:
		reports.append(severity.duplicate(true))


var assertions: Array[Dictionary] = []
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail: Dictionary = {}) -> void:
	assertions.append({label = label, ok = ok, detail = detail})
	if not ok:
		failures += 1


func _session(label: String) -> Node:
	var session: Node = Session.new()
	root.add_child(session)
	var prepared: bool = session.prepare({}, {crash_model = "graded", start = "air", altitude_m = 1.0,
		north_offset_m = 0.0, east_offset_m = 0.0, heading_deg = 0.0})
	_check(label + ": stock flat-ground session prepared", prepared, {error = str(session.load_error)})
	return session


## Attach real scene and FX methods without starting a rendered activity. The
## only substitutes are a visual root and an audio sink that records the FX's
## severity. No particle, sound or on-screen capture is claimed.
func _presentation(session: Node, connect_signal: bool) -> Dictionary:
	var activity := Activity.new()
	var visual := VisualStandIn.new()
	var fx := QuadFx.new()
	var audio := CaptureAudio.new()
	activity.session = session
	activity.visual = visual
	activity.crash_fx = fx
	fx.enable_audio = false
	fx.enable_effects = false
	fx.audio = audio
	if connect_signal:
		session.crashed.connect(Callable(activity, "_on_crashed"))
	return {activity = activity, visual = visual, fx = fx, audio = audio}


func _dispose(session: Node, presentation: Dictionary) -> void:
	var activity: Node = presentation.activity
	var visual: RefCounted = presentation.visual
	var fx: Node = presentation.fx
	var audio: Node = presentation.audio
	activity.crash_fx = null
	activity.visual = null
	activity.session = null
	fx.audio = null
	(visual.root as Node).free()
	# Free the emitter first so its connection to the activity is removed.
	session.free()
	activity.free()
	fx.free()
	audio.free()


func _world_velocity(body: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(RB._att(body), M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2]))


func _point_closing_max(session: Node, body: PackedFloat64Array) -> float:
	var velocity := M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates := M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var result := 0.0
	for point: PackedFloat64Array in session.plant._points:
		var world: PackedFloat64Array = M.q_rotate(RB._att(body), M.add(velocity, M.cross(rates, point)))
		result = maxf(result, world[2]) # flat upward normal is (0,0,-1)
	return result


func _run_accepted(label: String, down_mps: float) -> Dictionary:
	var session := _session(label)
	var out := {label = label, ready = false, requested_down_mps = down_mps}
	if not session.prepared:
		session.free()
		return out
	var presentation := _presentation(session, true)
	var pilot := FC.neutral_input(0)
	var frame: Dictionary = session.frame()
	var body: PackedFloat64Array = frame.body.duplicate()
	body[RB.VEL] = 0.0
	body[RB.VEL + 1] = 0.0
	body[RB.VEL + 2] = down_mps
	for i in 3:
		body[RB.RATE + i] = 0.0
	frame.body = body
	var continuous: PackedFloat64Array = frame.continuous.duplicate()
	for rotor in 4:
		continuous[Plant.C_SPEED + rotor] = 0.0
	frame.continuous = continuous
	var valid: bool = session.plant.state_validator(frame, {})
	var prepared_reset: Dictionary = session.sim.prepare_reset_frame(frame, pilot) if valid else {}
	var committed: bool = bool(prepared_reset.get("ok", false)) and session.sim.commit_prepared_reset_frame(prepared_reset)
	var resumed: bool = session.resume() if committed else false
	_check(label + ": prescribed frame admitted and resumed", valid and committed and resumed,
		{valid = valid, committed = committed, reset_error = str(prepared_reset.get("message", ""))})
	if not resumed:
		_dispose(session, presentation)
		return out
	out.ready = true
	var previous := PackedFloat64Array()
	var all_accepted := true
	for _step in 60:
		previous = (session.sim.state as PackedFloat64Array).duplicate()
		if not session.tick_once(pilot):
			all_accepted = false
			break
		if not session.crash.is_empty():
			break
	var terminal: bool = str(session.crash.get("reason", "")) == "Hard impact"
	var reports: Array[Dictionary] = presentation.audio.reports
	var before_velocity := _world_velocity(previous) if not previous.is_empty() else PackedFloat64Array()
	var after_body: PackedFloat64Array = session.sim.state
	var after_velocity := _world_velocity(after_body)
	out.merge({accepted = all_accepted, terminal = terminal, crash = session.crash.duplicate(true),
		tick = int(session.sim.tick), fault = str(session.fault_reason),
		previous_cg_velocity_ned = Array(before_velocity), previous_max_candidate_point_closing_mps = _point_closing_max(session, previous),
		post_cg_velocity_ned = Array(after_velocity), post_cg_speed_mps = M.norm(after_velocity),
		motor = int(session.sim.modes[FC.MODE_MOTOR]), cut = float(session.sim.continuous[Plant.C_CUT_LATCH]),
		terminal_events = session.sim.last_events.duplicate(true), reports = reports.duplicate(true)}, true)
	_check(label + ": accepted tick produced one hard-impact report with the cut latched",
		all_accepted and terminal and reports.size() == 1 and out.motor == FC.MOTOR_CRASHED and out.cut == 1.0, out)
	if reports.size() == 1:
		var report: Dictionary = reports[0]
		var expected: float = clampf(float(out.post_cg_speed_mps) / QuadFx.FULL_CRASH_SPEED_MPS, 0.0, 1.0)
		_check(label + ": production presentation power equals post-settlement CG speed / 20",
			absf(float(report.get("severity", -1.0)) - expected) < 1.0e-6, out)
	_dispose(session, presentation)
	return out


func _run_direct(label: String, down_mps: float) -> Dictionary:
	var session := _session(label)
	var out := {label = label, ready = false, requested_down_mps = down_mps}
	if not session.prepared:
		session.free()
		return out
	var presentation := _presentation(session, false)
	var previous: Dictionary = session.frame()
	var candidate: Dictionary = session.frame()
	var stopped: PackedFloat64Array = candidate.continuous.duplicate()
	for rotor in 4:
		stopped[Plant.C_SPEED + rotor] = 0.0
	candidate.continuous = stopped
	previous.continuous = stopped.duplicate()
	var before_body: PackedFloat64Array = previous.body.duplicate()
	before_body[RB.POS + 2] = -1.0
	before_body[RB.VEL] = 0.0
	before_body[RB.VEL + 1] = 0.0
	before_body[RB.VEL + 2] = down_mps
	for i in 3:
		before_body[RB.RATE + i] = 0.0
	previous.body = before_body
	var contact_body := before_body.duplicate()
	contact_body[RB.POS + 2] = -0.01
	candidate.body = contact_body
	var result: Dictionary = session.plant.endpoint_transition(previous, candidate, {time_s = 1.0 / 240.0})
	var terminal := false
	var reason := ""
	for event: Dictionary in result.get("events", []):
		if str(event.get("type", "")) == "crash":
			terminal = true
			reason = str(event.get("reason", ""))
	if not result.is_empty():
		# This assignment and callback are deliberately direct: no tick is
		# accepted in this isolation case. The prior cases exercise the real tick.
		session.sim.state = result.body.duplicate()
		presentation.activity._on_crashed(reason)
	var reports: Array[Dictionary] = presentation.audio.reports
	var post_velocity := _world_velocity(result.body) if not result.is_empty() else PackedFloat64Array()
	out.merge({ready = not result.is_empty(), terminal = terminal, reason = reason,
		previous_cg_velocity_ned = Array(_world_velocity(before_body)), post_cg_velocity_ned = Array(post_velocity),
		reports = reports.duplicate(true), events = result.get("events", []).duplicate(true),
		motor = int(result.modes[FC.MODE_MOTOR]) if not result.is_empty() else -1,
		cut = float(result.continuous[Plant.C_CUT_LATCH]) if not result.is_empty() else -1.0}, true)
	_check(label + ": direct candidate is a hard-impact terminal with cut and one presentation report",
		terminal and reason == "Hard impact" and reports.size() == 1 and out.motor == FC.MOTOR_CRASHED and out.cut == 1.0, out)
	_dispose(session, presentation)
	return out


func _compare(label: String, slow: Dictionary, fast: Dictionary) -> void:
	var slow_reports: Array = slow.get("reports", [])
	var fast_reports: Array = fast.get("reports", [])
	if slow_reports.size() != 1 or fast_reports.size() != 1:
		_check(label + ": comparison has two reports", false, {slow = slow, fast = fast})
		return
	var slow_report: Dictionary = slow_reports[0]
	var fast_report: Dictionary = fast_reports[0]
	var detail := {slow = slow, fast = fast}
	_check(label + ": post-settlement reports distinguish stronger incoming vertical impacts",
		float(fast_report.get("severity", -1.0)) > float(slow_report.get("severity", -1.0)) + 0.001, detail)


func _run() -> void:
	_check("fixed 240 Hz project tick", Engine.physics_ticks_per_second == Session.FIXED_HZ)
	var slow := _run_accepted("accepted_19", 19.0)
	var fast := _run_accepted("accepted_28", 28.0)
	if slow.get("terminal", false) and fast.get("terminal", false):
		_check("accepted controls approach at materially different measured previous-boundary point speeds",
			float(slow.previous_max_candidate_point_closing_mps) > 15.0
			and float(fast.previous_max_candidate_point_closing_mps) > float(slow.previous_max_candidate_point_closing_mps) + 4.0,
			{slow = slow, fast = fast})
		_compare("accepted", slow, fast)
	var direct_slow := _run_direct("direct_19", 19.0)
	var direct_fast := _run_direct("direct_28", 28.0)
	if direct_slow.get("terminal", false) and direct_fast.get("terminal", false):
		_compare("direct", direct_slow, direct_fast)
	print("QUAD_SEVERITY_DRAFT_JSON " + JSON.stringify({assertions = assertions, failure_count = failures,
		accepted_cases = [slow, fast], direct_cases = [direct_slow, direct_fast]}))
	print("QUAD_SEVERITY_DRAFT_COMPLETE assertions=%d failures=%d" % [assertions.size(), failures])
	quit(1 if failures > 0 else 0)
