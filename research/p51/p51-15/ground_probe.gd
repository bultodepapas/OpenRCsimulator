## P51-15 model-prediction probe for ground handling and FlightSession lifecycle.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Sim := preload("res://sim/simulation.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const G := 9.80665
const THRESHOLD := [15.0, -45.0]
const TAKEOFF_SECONDS := 12.0
const LANDING_SECONDS := 28.0
const IDLE_SECONDS := 10.0
const REPLAY_TICKS := 240

var tick_hz := 240
var output_path := ""
var session: Node
var model: Dictionary
var vs1g := 0.0
var density := 1.225
var setup_error := ""


func _initialize() -> void:
	if not _parse_args():
		quit(2)
		return
	Engine.physics_ticks_per_second = tick_hz
	if not _setup_session():
		printerr(setup_error)
		_write_report({ "schema": "p51-ground-probe-v1", "tick_hz": tick_hz, "evidence_kind": "model_prediction",
			"physical_validation": false, "completed": false, "setup_error": setup_error })
		quit(1)
		return
	var fixture := _parked_fixture()
	if not fixture.get("ok", false):
		var fixture_error := str(fixture.get("error", "unknown"))
		printerr("parked fixture failed: ", fixture_error)
		_write_report({ "schema": "p51-ground-probe-v1", "tick_hz": tick_hz, "evidence_kind": "model_prediction",
			"physical_validation": false, "completed": false, "fixture": _public_metrics(fixture), "setup_error": fixture_error })
		quit(1)
		return
	var parked: PackedFloat64Array = fixture.state
	var idle_rpm: float = Propulsion.steady_rpm(0.0, 0.0, model.propulsion, density)
	var report := {
		"schema": "p51-ground-probe-v1",
		"aircraft_id": str(model.get("id", "")),
		"tick_hz": tick_hz,
		"dt_s": session.sim.dt(),
		"air_density_kg_m3": density,
		"stall_speed_1g_mps": vs1g,
		"field_id": session.ground_field_id,
		"start_choice": session.start_choice,
		"shaft_integrator": session.shaft_integrator(),
		"aux_slots_after_reset": session.sim.aux.size(),
		"continuous_slots_after_reset": session.sim.continuous.size(),
		"evidence_kind": "model_prediction",
		"physical_validation": false,
		"scope": "P-51 model on the default field; constructed three-point ground fixture; real FlightSession tick and lifecycle paths",
		"fixture": _public_metrics(fixture),
		"cases": {},
		"lifecycle": {},
	}
	var cases: Dictionary = report.cases
	cases["parked_engine_off"] = _public_metrics(_run_case("parked_engine_off", parked, 0.0, false, 5.0,
		func(_t: float, _s: PackedFloat64Array) -> Dictionary:
			return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0 }))
	cases["parked_idle"] = _public_metrics(_run_case("parked_idle", parked, idle_rpm, true, IDLE_SECONDS,
		func(_t: float, _s: PackedFloat64Array) -> Dictionary:
			return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0 }))
	cases["takeoff_unguided"] = _public_metrics(_run_case("takeoff_unguided", parked, idle_rpm, true,
		TAKEOFF_SECONDS, _takeoff_pilot(false)))
	cases["takeoff_heading_hold"] = _public_metrics(_run_case("takeoff_heading_hold", parked, idle_rpm, true,
		TAKEOFF_SECONDS, _takeoff_pilot(true)))
	var landing_start := _landing_start()
	if landing_start.ok:
		cases["approach_flare_landing"] = _public_metrics(_run_case("approach_flare_landing", landing_start.state,
			float(landing_start.rpm), true, LANDING_SECONDS, _landing_pilot(float(landing_start.v_app), float(landing_start.aim_east))))
	else:
		cases["approach_flare_landing"] = { "complete": false, "error": str(landing_start.error) }
	var lifecycle := _lifecycle_probe()
	report.lifecycle = lifecycle
	report.numerics_ok = bool(fixture.ok) and _all_case_states_finite(cases) and lifecycle.get("reset_ok", false) \
		and lifecycle.get("checkpoint_replay_exact", false) and lifecycle.get("crash_restart_ok", false)
	report.cases_completed = _all_cases_completed(cases)
	report.completed = bool(report.numerics_ok) and bool(report.cases_completed)
	if not _write_report(report):
		quit(1)
		return
	quit(0 if report.completed else 1)


func _parse_args() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at := 0
	while at < args.size():
		var arg: String = args[at]
		if arg.begins_with("--hz="):
			var hz_text: String = arg.substr(5)
			if not hz_text.is_valid_int():
				printerr("--hz must be 240 or 480")
				return false
			tick_hz = int(hz_text)
		elif arg == "--hz":
			at += 1
			if at >= args.size() or not args[at].is_valid_int():
				printerr("--hz needs 240 or 480")
				return false
			tick_hz = int(args[at])
		elif arg.begins_with("--output="):
			output_path = arg.substr(9)
		elif arg == "--output":
			at += 1
			if at >= args.size() or args[at].is_empty():
				printerr("--output needs a file path")
				return false
			output_path = args[at]
		elif arg == "--help":
			print("Usage: --hz=240|480 [--output=report.json]")
			return false
		else:
			printerr("unknown option: ", arg)
			return false
		at += 1
	if tick_hz not in [240, 480]:
		printerr("--hz must be 240 or 480")
		return false
	return true


func _setup_session() -> bool:
	session = FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	session.start_choice = "airborne"
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var field: Dictionary = loaded.get("field", {})
	if not loaded.get("ok", false) or field.is_empty():
		setup_error = "default field failed to load"
		return false
	if not session.set_field(field):
		setup_error = "default field surfaces failed: " + str(session.surface_error)
		return false
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		setup_error = "P-51 session reset failed: " + str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason)
		return false
	if session._weather.has_turbulence():
		setup_error = "probe does not model turbulent restart state"
		return false
	model = session.aircraft.model
	density = session.air_density()
	vs1g = sqrt(2.0 * float(model.mass_kg) * G / (density * float(model.reference.S) * float(model.envelope.CL_max)))
	return is_finite(vs1g) and vs1g > 0.0


## P51-21: the parked fixture is the product's qualified runway start (GroundStart equilibrium with the solved
## stiction anchors) at the field threshold, heading east. Airborne cases keep the airborne reset's sliding anchors.
var runway_launch := PackedFloat64Array()


func _parked_fixture() -> Dictionary:
	session.start_choice = "runway"
	session.reset()
	var ok: bool = session.start_error.is_empty() and session.is_flyable() and session.sim.fault_reason.is_empty()
	var out: PackedFloat64Array = session.sim.state.duplicate()
	session.start_choice = "airborne"
	if not ok:
		return { ok = false, error = "runway start failed: " + str(session.start_error) }
	runway_launch = out.duplicate()
	var contacts := _contact_count(out)
	return {
		"ok": contacts == 3 and Sim.state_is_valid(out),
		"error": "fixture is not a finite three-contact pose" if contacts != 3 or not Sim.state_is_valid(out) else "",
		"method": "P51-21 product runway start: GroundStart equilibrium at the field threshold with stiction anchors",
		"pitch_deg": rad_to_deg(_euler(out)[1]),
		"contacts": contacts,
		"settle_complete": true,
		"settle_crash": "",
		"state_finite": Sim.state_is_valid(out),
		"state": out,
	}


func _landing_start() -> Dictionary:
	var v_app := 1.3 * vs1g
	var gamma := deg_to_rad(4.0)
	var aim_east: float = THRESHOLD[1] - 30.0
	var initial_east: float = aim_east - 14.5 / tan(gamma)
	var trim: Dictionary = session.trim_at(v_app, "level")
	if not trim.get("ok", false):
		return { "ok": false, "error": "approach trim failed: " + str(trim.get("message", "")) }
	session.set_start_altitude(15.0)
	var state: PackedFloat64Array = session.start.state.duplicate()
	state[RB.POS] = THRESHOLD[0]
	state[RB.POS + 1] = initial_east
	return { "ok": Sim.state_is_valid(state), "state": state, "rpm": float(trim.rpm), "v_app": v_app, "aim_east": aim_east,
		"error": "approach state is invalid" if not Sim.state_is_valid(state) else "" }


func _run_case(label: String, initial: PackedFloat64Array, rpm: float, engine_running: bool, seconds: float, pilot: Callable) -> Dictionary:
	var on_runway := not runway_launch.is_empty() and initial == runway_launch
	session.start_choice = "runway" if on_runway else "airborne"
	session.reset()
	session.start_choice = "airborne"
	if session.anchor_count() > 0 and not on_runway and _contact_count(initial) > 0:
		return _failed_case(label, "ground poses start from the qualified runway start")
	if on_runway and session.sim.state != runway_launch:
		return _failed_case(label, "runway start did not reproduce the parked launch: " + str(session.start_error))
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return _failed_case(label, "session reset failed: " + str(session.pause_reason if not session.pause_reason.is_empty() else session.sim.fault_reason))
	if not Sim.state_is_valid(initial):
		return _failed_case(label, "initial state is invalid")
	session.engine_running = engine_running
	var first: Dictionary = pilot.call(0.0, initial)
	_set_commands(first)
	session.sim.inputs = session._inputs()
	var aux: PackedFloat64Array = session.sim.aux.duplicate()
	if aux.size() < 4:
		return _failed_case(label, "reset auxiliary layout has fewer than four base slots")
	aux[0] = rpm
	aux[1] = session.sim.inputs[0]
	aux[2] = session.sim.inputs[1]
	aux[3] = session.sim.inputs[2]
	if session.downwash_index() >= 0:
		aux[session.downwash_index()] = session._wing_cl(initial, aux, 0.0)
	session.sim.aux = aux
	session.sim.continuous = session._settled_continuous(initial, aux)
	if not session.sim.reset(initial):
		return _failed_case(label, "simulation reset failed: " + session.sim.fault_reason)
	session.sim.set_paused(false)
	var dt: float = session.sim.dt()
	var requested_ticks := roundi(seconds / dt)
	var initial_heading: float = _euler(initial)[0]
	var previous: PackedFloat64Array = session.sim.state.duplicate()
	var previous_contacts := _contact_count(previous)
	var min_contacts := previous_contacts
	var max_contacts := previous_contacts
	var max_heading_deviation := 0.0
	var max_cross_track := absf(previous[RB.POS] - THRESHOLD[0])
	var ground_distance := 0.0
	var peak_speed := _speed(previous)
	var max_rudder_command := 0.0
	var peak_rpm := rpm
	var liftoff_time := -1.0
	var liftoff_east := 0.0
	var liftoff_speed := 0.0
	var liftoff_ground_speed := 0.0
	var touchdown_time := -1.0
	var touchdown_east := 0.0
	var touchdown_speed := 0.0
	var touchdown_ground_speed := 0.0
	var touchdown_sink := 0.0
	var post_touchdown_airborne := false
	var steps := 0
	var crashed := ""
	var fault := ""
	var finite := true
	for k in requested_ticks:
		var current: PackedFloat64Array = session.sim.state
		var t := float(k) * dt
		_set_commands(pilot.call(t, current.duplicate()))
		session.sim.inputs = session._inputs()
		max_rudder_command = maxf(max_rudder_command, absf(float(session.commands.yaw)))
		session._physics_process(dt)
		if not session.crash.is_empty():
			crashed = str(session.pause_reason)
			break
		if not session.sim.fault_reason.is_empty():
			fault = session.sim.fault_reason
			break
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			fault = session.sim.fault_reason
			break
		steps += 1
		var next: PackedFloat64Array = session.sim.state.duplicate()
		if not Sim.state_is_valid(next):
			finite = false
			fault = "simulation produced an invalid state"
			break
		var contacts := _contact_count(next)
		min_contacts = mini(min_contacts, contacts)
		max_contacts = maxi(max_contacts, contacts)
		max_heading_deviation = maxf(max_heading_deviation, absf(wrapf(_euler(next)[0] - initial_heading, -PI, PI)))
		max_cross_track = maxf(max_cross_track, absf(next[RB.POS] - THRESHOLD[0]))
		peak_speed = maxf(peak_speed, _speed(next))
		if previous_contacts > 0 or contacts > 0:
			ground_distance += _horizontal_step(previous, next)
		if liftoff_time < 0.0 and previous_contacts > 0 and contacts == 0:
			liftoff_time = session.sim.time()
			liftoff_east = next[RB.POS + 1]
			liftoff_speed = _speed(next)
			liftoff_ground_speed = _ground_speed(next)
		if touchdown_time < 0.0 and previous_contacts == 0 and contacts > 0:
			touchdown_time = session.sim.time()
			touchdown_east = next[RB.POS + 1]
			touchdown_speed = _speed(next)
			touchdown_ground_speed = _ground_speed(next)
			touchdown_sink = -_climb_rate(next)
		elif touchdown_time >= 0.0 and session.sim.time() > touchdown_time + 0.3 and contacts == 0 and -next[RB.POS + 2] - 0.5 > 0.3:
			post_touchdown_airborne = true
		if session.sim.aux.size() > 0:
			peak_rpm = maxf(peak_rpm, float(session.sim.aux[0]))
		previous = next
		previous_contacts = contacts
	var final_state: PackedFloat64Array = session.sim.state.duplicate()
	var final_valid: bool = Sim.state_is_valid(final_state)
	var result := {
		"label": label,
		"engine_running": engine_running,
		"requested_s": seconds,
		"elapsed_s": session.sim.time(),
		"steps": steps,
		"complete": steps == requested_ticks and crashed.is_empty() and fault.is_empty() and final_valid,
		"finite": finite and final_valid,
		"crashed": crashed,
		"fault": fault,
		"start_contacts": _contact_count(initial) if Sim.state_is_valid(initial) else 0,
		"final_contacts": _contact_count(final_state) if final_valid else 0,
		"min_contacts": min_contacts,
		"max_contacts": max_contacts,
		"start_speed_mps": _speed(initial),
		"final_speed_mps": _speed(final_state) if final_valid else 0.0,
		"final_ground_speed_mps": _ground_speed(final_state) if final_valid else 0.0,
		"peak_speed_mps": peak_speed,
		"ground_distance_m": ground_distance,
		"along_runway_displacement_m": final_state[RB.POS + 1] - initial[RB.POS + 1] if final_valid else 0.0,
		"max_cross_track_m": max_cross_track,
		"start_heading_deg": rad_to_deg(initial_heading),
		"final_heading_deg": rad_to_deg(_euler(final_state)[0]) if final_valid else 0.0,
		"heading_change_deg": rad_to_deg(wrapf(_euler(final_state)[0] - initial_heading, -PI, PI)) if final_valid else 0.0,
		"max_heading_deviation_deg": rad_to_deg(max_heading_deviation),
		"liftoff_s": liftoff_time,
		"liftoff_along_runway_m": liftoff_east - initial[RB.POS + 1] if liftoff_time >= 0.0 else -1.0,
		"liftoff_speed_mps": liftoff_speed,
		"liftoff_ground_speed_mps": liftoff_ground_speed,
		"touchdown_s": touchdown_time,
		"touchdown_along_runway_m": touchdown_east - THRESHOLD[1] if touchdown_time >= 0.0 else -1.0,
		"touchdown_speed_mps": touchdown_speed,
		"touchdown_ground_speed_mps": touchdown_ground_speed,
		"touchdown_sink_mps": touchdown_sink,
		"post_touchdown_airborne": post_touchdown_airborne,
		"rudder_command_peak_abs": max_rudder_command,
		"rpm_initial": rpm,
		"rpm_peak": peak_rpm,
		"rpm_final": float(session.sim.aux[0]) if final_valid and session.sim.aux.size() > 0 else 0.0,
		"final_state": final_state,
	}
	return result


func _failed_case(label: String, error: String) -> Dictionary:
	return { "label": label, "complete": false, "finite": false, "crashed": "", "fault": error, "error": error,
		"steps": 0, "elapsed_s": 0.0, "ground_distance_m": 0.0, "heading_change_deg": 0.0,
		"final_contacts": 0, "final_speed_mps": 0.0, "final_state": PackedFloat64Array() }


func _takeoff_pilot(use_heading_hold: bool) -> Callable:
	return func(t: float, s: PackedFloat64Array) -> Dictionary:
		var v := _speed(s)
		var c := { "roll": _wings_level(s), "yaw": _hold_heading(s, PI / 2.0) if use_heading_hold else 0.0,
			"throttle": clampf(t / 2.0, 0.0, 1.0), "pitch": 0.0 }
		if v < 0.4 * vs1g:
			c.pitch = 0.6
		elif v < 1.25 * vs1g:
			c.pitch = _hold_pitch(s, deg_to_rad(1.0))
		else:
			c.pitch = _hold_pitch(s, deg_to_rad(8.0))
		return c


func _landing_pilot(v_app: float, aim_east: float) -> Callable:
	var gamma := deg_to_rad(4.0)
	var touchdown := { "seen": false }
	return func(_t: float, s: PackedFloat64Array) -> Dictionary:
		var h := -s[RB.POS + 2] - 0.5
		var c := { "roll": _wings_level(s), "yaw": _hold_heading(s, PI / 2.0), "throttle": 0.0, "pitch": 0.0 }
		if _contact_count(s) > 0:
			touchdown.seen = true
		if not touchdown.seen and h > 1.5:
			var h_path := (aim_east - s[RB.POS + 1]) * tan(gamma)
			c.pitch = _hold_speed(s, v_app, -gamma)
			c.throttle = clampf(0.08 + 0.1 * (h_path - h) + 0.15 * (-v_app * tan(gamma) - _climb_rate(s)), 0.0, 0.6)
		elif not touchdown.seen:
			var sink_target := 0.3 + 0.6 * h
			c.pitch = _hold_pitch(s, clampf(deg_to_rad(3.0) + 0.15 * (_climb_rate(s) + sink_target) * -1.0,
				deg_to_rad(-2.0), deg_to_rad(8.0)))
		else:
			c.pitch = _hold_pitch(s, deg_to_rad(3.0)) if _speed(s) > 0.7 * vs1g else clampf((0.7 * vs1g - _speed(s)) / 3.0, 0.0, 1.0)
		return c


func _lifecycle_probe() -> Dictionary:
	session.reset()
	var reset_ok: bool = session.is_flyable() and session.sim.fault_reason.is_empty() and Sim.state_is_valid(session.sim.state)
	var reset_result := { "reset_ok": reset_ok, "reset_tick": session.sim.tick, "reset_crash": not session.crash.is_empty(),
		"reset_fault": session.sim.fault_reason }
	var replay := _checkpoint_replay()
	var crash := _crash_restart()
	reset_result.merge(replay, true)
	reset_result.merge(crash, true)
	return reset_result


func _checkpoint_replay() -> Dictionary:
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return { "checkpoint_replay_exact": false, "checkpoint_error": "session reset failed before checkpoint" }
	session.commands = { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0 }
	session.sim.inputs = session._inputs()
	session.sim.set_paused(false)
	var checkpoint: Dictionary = session.checkpoint()
	if checkpoint.is_empty():
		return { "checkpoint_replay_exact": false, "checkpoint_error": "session checkpoint refused the reset boundary" }
	var dt: float = session.sim.dt()
	if not _advance_replay(REPLAY_TICKS):
		return { "checkpoint_replay_exact": false, "checkpoint_error": "first checkpoint branch crashed or faulted" }
	var expected: PackedByteArray = var_to_bytes(session.sim.checkpoint())
	var expected_state: PackedFloat64Array = session.sim.state.duplicate()
	if not session.restore_checkpoint(bytes_to_var(var_to_bytes(checkpoint))):
		return { "checkpoint_replay_exact": false, "checkpoint_error": "session refused its own exact checkpoint" }
	session.engine_running = true
	session.commands = { "roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0 }
	session.sim.set_paused(false)
	if not _advance_replay(REPLAY_TICKS):
		return { "checkpoint_replay_exact": false, "checkpoint_error": "replayed checkpoint branch crashed or faulted" }
	var actual: PackedByteArray = var_to_bytes(session.sim.checkpoint())
	return {
		"checkpoint_replay_exact": expected == actual,
		"checkpoint_replay_ticks": REPLAY_TICKS,
		"checkpoint_replay_s": REPLAY_TICKS * dt,
		"checkpoint_final_state_max_abs_delta": _max_state_delta(expected_state, session.sim.state),
		"checkpoint_replay_error": "",
	}


func _advance_replay(ticks: int) -> bool:
	var dt: float = session.sim.dt()
	for _k in ticks:
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty():
			return false
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or not Sim.state_is_valid(session.sim.state):
			return false
	return true


func _crash_restart() -> Dictionary:
	session.reset()
	if not session.is_flyable() or not session.sim.fault_reason.is_empty():
		return { "crash_restart_ok": false, "crash_error": "session reset failed before crash fixture" }
	var impact_state: PackedFloat64Array = session.sim.state.duplicate()
	var found_hull_contact := false
	for depth in [0.0, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]:
		impact_state[RB.POS + 2] = float(depth)
		if session.touches_ground(impact_state):
			found_hull_contact = true
			break
	if not found_hull_contact:
		return { "crash_restart_ok": false, "crash_error": "could not construct a P-51 hull-contact crash state" }
	session.sim.continuous = session._settled_continuous(impact_state, session.sim.aux)
	if not session.sim.reset(impact_state):
		return { "crash_restart_ok": false, "crash_error": "crash fixture reset failed: " + session.sim.fault_reason }
	session.sim.set_paused(false)
	session.crash_auto_restart = true
	session._physics_process(session.sim.dt())
	var detected: bool = not session.crash.is_empty()
	var crash_reason := str(session.pause_reason)
	var held_ticks := int(session.crash.get("ticks_left", 0))
	var ticks_waited := 0
	var expected_hold_ticks := roundi(FlightSession.CRASH_HOLD_S / session.sim.dt())
	var max_wait := expected_hold_ticks + 2
	while not session.crash.is_empty() and ticks_waited <= max_wait:
		session._physics_process(session.sim.dt())
		ticks_waited += 1
	var restarted: bool = session.crash.is_empty() and session.is_flyable() and session.sim.fault_reason.is_empty()
	var restart_delta: float = _max_state_delta(session.start.state, session.sim.state) if restarted else -1.0
	var restart_matches: bool = restart_delta == 0.0
	return {
		"crash_detected": detected,
		"crash_reason": crash_reason,
		"crash_countdown_ticks": held_ticks,
		"crash_countdown_ticks_waited": ticks_waited,
		"crash_countdown_expected_ticks": expected_hold_ticks,
		"crash_countdown_s": held_ticks * session.sim.dt(),
		"crash_restart_exact_state": restart_matches,
		"crash_restart_ok": detected and restarted and session.sim.tick == 0 and Sim.state_is_valid(session.sim.state)
			and held_ticks == expected_hold_ticks and ticks_waited == expected_hold_ticks and restart_matches,
		"crash_restart_tick": session.sim.tick,
		"crash_restart_state_max_abs_delta": restart_delta,
		"crash_error": "" if restarted else "automatic reset did not return to a valid trimmed start",
	}


func _set_commands(commands: Dictionary) -> void:
	session.commands = {
		"roll": clampf(float(commands.get("roll", 0.0)), -1.0, 1.0),
		"pitch": clampf(float(commands.get("pitch", 0.0)), -1.0, 1.0),
		"yaw": clampf(float(commands.get("yaw", 0.0)), -1.0, 1.0),
		"throttle": clampf(float(commands.get("throttle", 0.0)), 0.0, 1.0),
	}


func _contact_count(s: PackedFloat64Array) -> int:
	if not Sim.state_is_valid(s) or not model.has("landing_gear"):
		return 0
	var count := 0
	for compression in Ground.compressions(s, model.landing_gear):
		count += int(compression > 0.0)
	return count


func _euler(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))


func _speed(s: PackedFloat64Array) -> float:
	return sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)


func _ground_speed(s: PackedFloat64Array) -> float:
	var world: PackedFloat64Array = M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]),
		M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
	return sqrt(world[0] ** 2 + world[1] ** 2)


func _climb_rate(s: PackedFloat64Array) -> float:
	var world: PackedFloat64Array = M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]),
		M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
	return -world[2]


func _horizontal_step(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	return sqrt((right[RB.POS] - left[RB.POS]) ** 2 + (right[RB.POS + 1] - left[RB.POS + 1]) ** 2)


func _wings_level(s: PackedFloat64Array) -> float:
	return 2.0 * -_euler(s)[2] - 0.3 * s[RB.RATE]


func _hold_heading(s: PackedFloat64Array, heading: float) -> float:
	return 3.0 * wrapf(heading - _euler(s)[0], -PI, PI) - s[RB.RATE + 2]


func _hold_pitch(s: PackedFloat64Array, pitch: float) -> float:
	return 3.0 * (pitch - _euler(s)[1]) - 0.6 * s[RB.RATE + 1]


func _hold_speed(s: PackedFloat64Array, speed: float, pitch_trim: float) -> float:
	return _hold_pitch(s, clampf(pitch_trim + 0.04 * (_speed(s) - speed), -0.5, 0.5))


func _max_state_delta(left: PackedFloat64Array, right: PackedFloat64Array) -> float:
	if left.size() != right.size():
		return INF
	var largest := 0.0
	for i in left.size():
		largest = maxf(largest, absf(left[i] - right[i]))
	return largest


func _all_case_states_finite(cases: Dictionary) -> bool:
	for entry in cases.values():
		if not entry.get("finite", false) or not str(entry.get("fault", "")).is_empty():
			return false
	return true


func _all_cases_completed(cases: Dictionary) -> bool:
	for entry in cases.values():
		if not entry.get("complete", false):
			return false
	return true


func _public_metrics(metrics: Dictionary) -> Dictionary:
	var out: Dictionary = metrics.duplicate(true)
	out.erase("final_state")
	out.erase("state")
	return out


func _write_report(report: Dictionary) -> bool:
	var json := JSON.stringify(report, "\t")
	if output_path.is_empty():
		print(json)
		return true
	var target := output_path
	if not target.is_absolute_path():
		if not target.begins_with("res://") and not target.begins_with("user://"):
			target = "res://" + target
		target = ProjectSettings.globalize_path(target)
	var directory := target.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(directory)
		if mkdir_error != OK:
			printerr("cannot create output directory: ", directory)
			return false
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("cannot write JSON report: ", target, " (", FileAccess.get_open_error(), ")")
		return false
	file.store_string(json + "\n")
	file.close()
	print("wrote ", target)
	return true
