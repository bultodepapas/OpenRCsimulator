## CR-01e: the crash card and log say why the airplane crashed (docs/plans/crash-realism.md §3.5). Synthetic
## histories pin each rule; two real Stik flights through the production scene check the end-to-end path.
extends SceneTree

const CrashCause = preload("res://render/crash/cause.gd")
const MainScene = preload("res://main.tscn")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

const REF := {stall_alpha_deg = 14.0, start_speed = 15.0}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_rules()
	_guards()
	_formatting()
	await _real_flights()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


## `seconds` of samples ending at t = 10 s; `late` overrides apply to the last `late_s` seconds.
func _history(base: Dictionary, late: Dictionary = {}, late_s := 0.0, seconds := 4.0) -> Array:
	var out: Array = []
	var n := int(round(seconds / CrashCause.SAMPLE_INTERVAL_S))
	for i in n + 1:
		var t := 10.0 - seconds + i * CrashCause.SAMPLE_INTERVAL_S
		var s := {t = t, airspeed = 15.0, ground_speed = 15.0, alpha_deg = 4.0, pitch_deg = 0.0, bank_deg = 0.0, roll_rate_dps = 0.0,
			yaw_rate_dps = 0.0, height_agl = 10.0, vertical_speed = -0.5, throttle = 0.6, engine_running = true}
		s.merge(base, true)
		if t > 10.0 - late_s + 1e-9:
			s.merge(late, true)
		out.append(s)
	return out


func _id(samples: Array, impact := {trigger = "hull_contact"}, reference := REF) -> String:
	return String(CrashCause.classify(samples, impact, reference).id)


func _rules() -> void:
	_check("an obstacle hit names the obstacle", CrashCause.classify(_history({}), {trigger = "scenery", obstacle_kind = "tree_trunk", speed_mps = 12.0}, REF).label == "Hit a tree trunk")
	_check("gear overtravel in a landing attitude is a collapsed-gear hard landing", _id(_history({}, {vertical_speed = -3.0, height_agl = 0.3}, 0.5), {trigger = "gear_limit"}) == "gear_collapse")
	_check("gear overtravel at the end of a dive is still a dive", _id(_history({}, {vertical_speed = -28.0, ground_speed = 12.0, airspeed = 30.0}, 0.5), {trigger = "gear_limit"}) == "dive")
	_check("a long nose-up stall straight ahead is a stall", _id(_history({}, {alpha_deg = 18.0, airspeed = 9.0, vertical_speed = -6.0}, 1.0)) == "stall")
	_check("a stall with a fast roll-off is a tip stall", _id(_history({}, {alpha_deg = 18.0, airspeed = 9.0, roll_rate_dps = 200.0}, 1.0)) == "tip_stall")
	_check("a stall with a large bank change is a tip stall", _id(_history({}, {alpha_deg = 18.0, airspeed = 9.0, bank_deg = 70.0}, 0.8)) == "tip_stall")
	_check("a stall with sustained yaw rate is a spin", _id(_history({}, {alpha_deg = 25.0, airspeed = 10.0, yaw_rate_dps = 180.0, roll_rate_dps = 200.0}, 1.5)) == "spin")
	_check("a steep fast dive", _id(_history({}, {pitch_deg = -60.0, airspeed = 30.0, ground_speed = 15.0, vertical_speed = -25.0}, 0.5)) == "dive")
	var pull_out := _history({}, {airspeed = 32.0, ground_speed = 12.0, vertical_speed = -28.0}, 1.5)
	for s: Dictionary in pull_out.slice(pull_out.size() - 4):
		s.ground_speed = 34.0
		s.vertical_speed = -9.0
	var late := CrashCause.classify(pull_out, {trigger = "gear_limit"}, REF)
	_check("a pull-out that starts too late is still a dive", late.id == "dive" and String(late.label).begins_with("Too late"), CrashCause.line(late))
	_check("a fast shallow descent is not a dive", _id(_history({}, {pitch_deg = -60.0, airspeed = 30.0, ground_speed = 29.0, vertical_speed = -5.0}, 0.5)) != "dive")
	_check("a level heavy sink is a hard landing", _id(_history({}, {pitch_deg = 2.0, vertical_speed = -3.0, height_agl = 0.3}, 0.5)) == "hard_landing")
	_check("a steep bank near the ground", _id(_history({}, {bank_deg = 75.0, vertical_speed = -1.0, height_agl = 1.0}, 0.5)) == "steep_bank")
	_check("a controlled descent into the ground", _id(_history({}, {pitch_deg = -10.0, vertical_speed = -1.5}, 0.5)) == "flew_into_ground")
	_check("an engine stopped for seconds is a dead stick", _id(_history({engine_running = false, throttle = 0.0})) == "dead_stick")
	_check("an airplane on the ground noses over", _id(_history({height_agl = 0.2, airspeed = 6.0})) == "ground_handling")
	_check("a propeller hit on the ground is a prop strike", _id(_history({height_agl = 0.2, airspeed = 6.0}), {trigger = "hull_contact", component_group = "propeller"}) == "prop_strike")


func _guards() -> void:
	_check("a brief α spike is not a stall", _id(_history({}, {alpha_deg = 20.0}, 0.1)) != "stall")
	_check("α measured below the minimum airspeed is ignored", _id(_history({}, {alpha_deg = 40.0, airspeed = 2.0}, 1.0)) not in ["stall", "tip_stall", "spin"])
	var stalled := _history({}, {alpha_deg = 16.0, airspeed = 9.0}, 1.0)
	_check("the stall threshold comes from the aircraft data", _id(stalled, {trigger = "hull_contact"}, {stall_alpha_deg = 14.0, start_speed = 15.0}) == "stall"
		and _id(stalled, {trigger = "hull_contact"}, {stall_alpha_deg = 25.0, start_speed = 15.0}) != "stall")
	_check("an engine that just stopped is not yet a dead stick", _id(_history({}, {engine_running = false}, 0.5)) != "dead_stick")
	_check("a ground run needs the whole window on the ground", _id(_history({}, {height_agl = 0.2}, 0.4)) != "ground_handling")
	_check("no history still yields a cause", _id([]) == "unknown")


func _formatting() -> void:
	var cause := CrashCause.classify(_history({}, {alpha_deg = 18.0, airspeed = 8.2, roll_rate_dps = 200.0, height_agl = 4.0, bank_deg = 35.0, throttle = 0.0}, 1.0), {trigger = "hull_contact"}, REF)
	var line := CrashCause.line(cause)
	_check("the line names cause, height, α, speed and bank", line.begins_with("Tip stall at 4 m: α 18°, 8.2 m/s, bank 35°"), line)
	_check("the line lists contributing factors", line.contains("throttle closed") and line.contains("low airspeed"), line)


func _real_flights() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("aircraft_id", "jensen-das-ugly-stik-60")
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var director: Variant = main.get("_crash_director")
	if session == null or director == null:
		_check("production scene ready", false)
		main.queue_free()
		return
	session.input_enabled = false
	session.set_physics_process(false)
	# Slow and nose-high at 8 m, throttle closed: it stalls and falls.
	var stall := await _fly(session, director, RB.make_state(M.v3(0, 0, -8), M.v3(7, 0, 0), M.q_from_euler(0, deg_to_rad(20), 0), M.v3(0, 0, 0)), 0.0)
	_check("real stall flight ends in a crash", not session.crash.is_empty())
	_check("real stall flight is explained as a stall", stall.id in ["stall", "tip_stall", "spin"], CrashCause.line(stall))
	_check("the crash card shows the cause", director.description().contains("Cause: "), director.description().get_slice("\n", 3))
	session.reset()
	director.update(session.sim.dt())
	_check("restart starts a fresh history", director.history.size() <= 1 and (director.history.is_empty() or float(director.history[0].t) < 0.1))
	# Steep dive at full throttle from 25 m.
	var q := M.q_from_euler(0, deg_to_rad(-65), 0)
	var dive := await _fly(session, director, RB.make_state(M.v3(0, 0, -25), M.q_rotate(M.q_conj(q), M.v3(14, 0, 30)), q, M.v3(0, 0, 0)), 1.0)
	_check("real dive is explained as a dive", dive.id == "dive", CrashCause.line(dive))
	main.queue_free()
	await process_frame


func _fly(session: Variant, director: Variant, s: PackedFloat64Array, throttle: float) -> Dictionary:
	session.reset()
	director.update(session.sim.dt())
	session.sim.reset(s)
	session.sim.set_paused(false)
	for tick in 2400:
		session.sim.inputs[3] = throttle
		session._physics_process(session.sim.dt())
		director.update(session.sim.dt())
		if not session.crash.is_empty():
			break
		session.sim.step()
	return director.report.get("cause", {id = "none"})
