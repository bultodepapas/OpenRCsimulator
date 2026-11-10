# EX-14h/k research probe: an explicit stall protocol motivated by qualitative GP Extra owner reports.
# Those reports do not establish this five-second hold, trim, CG or hands-off control sequence. This is a
# sensitivity experiment, not a reconstruction of an owner's test. Idle; altitude and wings held to the elevator
# stick stop, then held for --hold seconds (default 5); pitch stick centred for 3 s. Entry trims remain active.
# Ailerons are hands-off or wings-level; --rudder interventions begin only at the stop, with an identical lead-in.
# Rates are the manual LOW ("normal") or HIGH ("full"). Rotation labels do not establish a spin.
#   godot --headless --path <app> --audio-driver Dummy --script <abs>/stall_probe.gd -- [--aircraft=gp-extra-300s-60]
#     [--data=<abs json>] [--hold=0.25..5] [--rudder=hands_off|neutral_surface|ball]
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const P := preload("../../flight-test/pilot.gd")
const FlightLog := preload("res://sim/flight_log.gd")

const ALTITUDE := 300.0
const RELEASE_S := 3.0
const ENTRY_VS := 1.4  # entry speed / the FT card's power-off stall speed (summary-extra-d.md: 11.11 m/s)
const VS_CARD := 11.11
var output_dir := ""
var case_filter := ""
var failed := false
var hold_s := 5.0
var rudder_policy := "hands_off"


func _initialize() -> void:
	var id := "gp-extra-300s-60"
	var data_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			id = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--data="):
			data_path = arg.trim_prefix("--data=")
		elif arg.begins_with("--out="):
			output_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--case="):
			case_filter = arg.trim_prefix("--case=")
		elif arg.begins_with("--hold="):
			var value := arg.trim_prefix("--hold=")
			hold_s = value.to_float() if value.is_valid_float() else NAN
		elif arg.begins_with("--rudder="):
			rudder_policy = arg.trim_prefix("--rudder=")
		else:
			printerr("Unknown argument: " + arg)
			quit(2)
			return
	if not is_finite(hold_s) or hold_s < 0.25 or hold_s > 5.0 or not ["hands_off", "neutral_surface", "ball"].has(rudder_policy):
		printerr("Expected --hold in [0.25, 5] and --rudder=hands_off|neutral_surface|ball")
		quit(2)
		return
	if not case_filter.is_empty() and not ["normal/hands_off", "normal/wings_level", "full/hands_off", "full/wings_level"].has(case_filter):
		printerr("Unknown --case: " + case_filter)
		quit(2)
		return
	if not output_dir.is_empty():
		if DirAccess.dir_exists_absolute(output_dir) or DirAccess.make_dir_recursive_absolute(output_dir) != OK:
			printerr("Expected a fresh writable --out directory")
			quit(2)
			return
	var data: String = Catalog.entry(id).data if data_path.is_empty() else data_path
	for rates in ["normal", "full"]:
		for ailerons in ["hands_off", "wings_level"]:
			if not case_filter.is_empty() and case_filter != rates + "/" + ailerons:
				continue
			var result := _stall(data, rates, ailerons)
			print(JSON.stringify(result))
			if not output_dir.is_empty():
				var report := FileAccess.open(output_dir.path_join(rates + "_" + ailerons + ".json"), FileAccess.WRITE)
				report.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	print("EXTRA_STALL_PROBE_COMPLETE failures=", int(failed))
	quit(1 if failed else 0)


func _stall(data: String, rates: String, ailerons: String) -> Dictionary:
	var session := Flight.new()
	session.setup_stage_backend("gdscript_reference")
	session.setup(data)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	var trim: Dictionary = session.trim_at(ENTRY_VS * VS_CARD, "level")
	if not trim.get("ok", false):
		failed = true
		session.free()
		return {case = "%s/%s" % [rates, ailerons], error = "entry trim refused", trim = trim}
	session.set_start_altitude(ALTITUDE)
	session.reset()
	session.rate_profile = rates
	var sim: Node = session.sim
	var neutral_yaw := _neutral_yaw_command(session)
	if rudder_policy == "neutral_surface" and not is_finite(neutral_yaw):
		failed = true
		session.free()
		return {case = "%s/%s" % [rates, ailerons], error = "zero rudder surface is outside available stick travel"}
	var recorder: RefCounted = null
	if not output_dir.is_empty():
		recorder = FlightLog.new(session)
		if recorder.start(output_dir.path_join(rates + "_" + ailerons + ".orfl")) != OK:
			failed = true
			session.free()
			return {case = "%s/%s" % [rates, ailerons], error = "recording refused"}
	var dt: float = sim.dt()
	var ctx := {}
	var out := {format = "openrc-extra-stall-probe v2", case = "%s/%s" % [rates, ailerons], rates_active = session.rates_active(),
		pitch_trim = session.trims.pitch, entry_trims = session.trims.duplicate(), hold_s = hold_s,
		rudder_policy = rudder_policy, rudder_intervention = "at elevator stop through end of release",
		neutral_rudder_stick = neutral_yaw, aircraft_id = session.aircraft.model.id,
		aircraft_input_sha256 = session.aircraft.get("input_identity", {}).get("sha256", ""),
		solver_sha256 = FlightLog.solver_identity(),
		probe_sha256 = FileAccess.get_sha256(get_script().resource_path),
		deflection_convention = "controls use aerodynamic signs (elevator TE down, rudder TE left positive); legacy elevator_at_stop_deg is TE up positive",
		rotation_rate_convention = "legacy rotation_rate fields are absolute Euler heading derivatives, ill-conditioned near vertical; not spin rates",
		outcome_convention = "bank/heading thresholds only; no stall-type or spin identification",
		lateral_g_convention = "previous committed loads Fy / initial loaded mass / g; same normalization as FT pilot"}
	var t_stop := -1.0
	var at_stop := 0
	var stop := {}
	var series := []
	var max_alpha := 0.0
	var max_bank := 0.0
	var min_pitch := INF
	var max_yaw_rate := 0.0
	var first_bank_20 := -1.0
	var late_yaw := 0.0
	var max_beta := 0.0
	var max_lateral_g := 0.0
	var heading_rate_usable := true
	for tick in roundi(60.0 / dt):
		var t := tick * dt
		var s: PackedFloat64Array = sim.state
		var e := P.euler(s)
		var k := P.schedule(s, ENTRY_VS * VS_CARD)
		var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		if t_stop < 0.0:
			c.pitch = P.hold_altitude(s, ALTITUDE, k, ctx, dt)
			c.roll = P.bank(s, 0.0, k)
			at_stop = at_stop + 1 if c.pitch >= 0.999 else 0
			if at_stop >= roundi(0.25 / dt):
				t_stop = t
				if recorder != null:
					recorder.mark("elevator stop: " + rates + "/" + ailerons)
				stop = {t_s = t, speed_mps = P.speed(s), alpha_deg = rad_to_deg(P.alpha(s)), pitch_deg = rad_to_deg(e[1]),
					alt_m = P.altitude(s), bank_deg = rad_to_deg(e[2]), beta_deg = rad_to_deg(P.beta(s)),
					p_radps = float(s[RB.RATE]), r_radps = float(s[RB.RATE + 2]),
					tick = sim.tick, initial_controls = _controls(session)}
		var since := t - t_stop if t_stop >= 0.0 else -1.0
		if since >= 0.0:
			if rudder_policy == "neutral_surface":
				c.yaw = neutral_yaw
			elif rudder_policy == "ball":
				ctx.ay = _lateral_g(session)
				c.yaw = P.ball(s, k, ctx, dt)
		if since >= 0.0 and since <= hold_s:
			c.pitch = 1.0
			c.roll = P.bank(s, 0.0, k) if ailerons == "wings_level" else 0.0
			max_alpha = maxf(max_alpha, rad_to_deg(P.alpha(s)))
			max_bank = maxf(max_bank, absf(rad_to_deg(e[2])))
			max_beta = maxf(max_beta, absf(rad_to_deg(P.beta(s))))
			max_lateral_g = maxf(max_lateral_g, absf(_lateral_g(session)))
			min_pitch = minf(min_pitch, rad_to_deg(e[1]))
			heading_rate_usable = heading_rate_usable and absf(cos(e[1])) >= 0.1
			var yaw_rate := absf(rad_to_deg(_heading_rate(s)))
			max_yaw_rate = maxf(max_yaw_rate, yaw_rate)
			if since > maxf(0.0, hold_s - 2.0):
				late_yaw += yaw_rate * dt
			if first_bank_20 < 0.0 and absf(rad_to_deg(e[2])) > 20.0:
				first_bank_20 = since
		elif since > hold_s:
			c.pitch = 0.0
			c.roll = 0.0
			if not out.has("hold_end"):
				if recorder != null:
					recorder.mark("release elevator")
				out.hold_end = _row(s, since, session)
			if since > hold_s + RELEASE_S:
				out.release_end = _row(s, since, session)
				break
		if since >= 0.0 and roundi(since / dt) % roundi(0.25 / dt) == 0:
			series.append(_row(s, since, session))
		session.commands = {roll = c.roll, pitch = c.pitch, yaw = c.yaw, throttle = c.throttle}
		sim.inputs = session._inputs()
		sim.step()
		if not sim.fault_reason.is_empty() or not session.crash.is_empty():
			out.stopped = sim.fault_reason + str(session.crash)
			failed = true
			break
	if t_stop < 0.0 or not out.has("release_end"):
		out.error = "requested stop/hold/recovery did not complete"
		failed = true
	if recorder != null and recorder.stop() != OK:
		out.error = "recording did not close"
		failed = true
	var late_rate := late_yaw / minf(2.0, hold_s)
	out.stop = stop
	out.elevator_at_stop_deg = _stop_deflection(session)
	out.max_alpha_held_deg = max_alpha
	out.max_bank_held_deg = max_bank
	out.max_abs_beta_held_deg = max_beta
	out.max_abs_lateral_g_held = max_lateral_g
	out.first_bank_20_after_stop_s = first_bank_20
	out.nose_drop_deg = float(stop.get("pitch_deg", NAN)) - min_pitch
	out.max_rotation_rate_dps = max_yaw_rate
	out.rotation_rate_last_2_s_dps = late_rate
	out.rotation_window_s = minf(2.0, hold_s)
	out.heading_rate_usable = heading_rate_usable
	out.height_lost_held_m = float(stop.get("alt_m", NAN)) - float(out.get("hold_end", {}).get("alt_m", NAN))
	out.height_lost_release_m = float(out.get("hold_end", {}).get("alt_m", NAN)) - float(out.get("release_end", {}).get("alt_m", NAN))
	out.outcome = "heading rate unclassified near vertical" if not heading_rate_usable else (
		"large heading rate (spin unclassified)" if late_rate > 90.0 else (
		"large bank (cause unclassified)" if max_bank >= 30.0 else "limited bank (stall type unclassified)"))
	out.series = series
	session.free()
	return out


## Elevator deflection (deg, trailing edge up positive) the held stop commands under the active rate profile.
func _stop_deflection(session: Node) -> float:
	var saved: Dictionary = session.commands
	session.commands = {roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0}
	var f: Dictionary = session.flown_commands()
	session.commands = saved
	return rad_to_deg(float(f.pitch) * float(session.aircraft.model.controls.throw_rad.elevator))


func _row(s: PackedFloat64Array, since: float, session: Node) -> Dictionary:
	var e := P.euler(s)
	return {t = snappedf(since, 0.01), t_s = since, alpha = snappedf(rad_to_deg(P.alpha(s)), 0.1), beta = snappedf(rad_to_deg(P.beta(s)), 0.1),
		bank = snappedf(rad_to_deg(e[2]), 0.1), pitch = snappedf(rad_to_deg(e[1]), 0.1), v = snappedf(P.speed(s), 0.01),
		climb = snappedf(P.climb_rate(s), 0.01), p = snappedf(rad_to_deg(s[RB.RATE]), 1.0), r = snappedf(rad_to_deg(s[RB.RATE + 2]), 1.0),
		alt_m = snappedf(P.altitude(s), 0.1), controls = _controls(session), lateral_g = _lateral_g(session)}


func _lateral_g(session: Node) -> float:
	return float(session.sim.last_loads[1]) / (float(session.aircraft.model.mass_kg) * 9.80665) if session.sim.last_loads.size() >= 2 else 0.0


func _controls(session: Node) -> Dictionary:
	var d: Dictionary = session._deflections(session.sim.aux)
	return {aileron_right_deg = rad_to_deg(float(d.aileron_right)), elevator_deg = rad_to_deg(float(d.elevator)),
		rudder_deg = rad_to_deg(float(d.rudder)), engine_rpm = float(session.sim.aux[session.AUX_RPM])}


## Invert the actual rate/expo/trim pipeline without touching servo or rigid-body state.
func _neutral_yaw_command(session: Node) -> float:
	var saved: Dictionary = session.commands
	var lo := -1.0
	var hi := 1.0
	for _i in 48:
		var mid := (lo + hi) * 0.5
		session.commands = {roll = 0.0, pitch = 0.0, yaw = mid, throttle = 0.0}
		if float(session.flown_commands().yaw) > 0.0:
			hi = mid
		else:
			lo = mid
	var answer := (lo + hi) * 0.5
	session.commands = {roll = 0.0, pitch = 0.0, yaw = answer, throttle = 0.0}
	var reachable := absf(float(session.flown_commands().yaw)) < 1e-10
	session.commands = saved
	return answer if reachable else NAN


## Euler heading derivative (rad/s), not the earth-vertical angular-velocity component.
func _heading_rate(s: PackedFloat64Array) -> float:
	var e := P.euler(s)
	var q: float = s[RB.RATE + 1]
	var r: float = s[RB.RATE + 2]
	return (q * sin(e[2]) + r * cos(e[2])) / maxf(cos(e[1]), 1e-3)
