# EX-14h probe (read-only): the 1-g stall the GP Extra owners describe (RCU thread 1062376: "Stalls were very very mild
# ...it sort of mushes forward while loosing a bit of altitude. Center the elevator and its flying again"; "Wingtips
# didnt drop and the nose really didnt drop either"). Unlike the FT card (full rates, feet on the ball, wing drop
# detected from the bank), this flies the owner's test: idle, altitude held with the elevator until the stick is at its
# stop, then the stop held 5 s with the ailerons and rudder hands-off (or ailerons holding the wings level), then the
# elevator centred for 3 s, still hands-off. On the manual's LOW rate (controls.rates.normal, rate_profile "normal")
# and on HIGH rate ("full"). Reports the angle of attack the stop reaches, bank, nose drop, rotation and height lost,
# plus a 0.25 s series from the stop. One JSON line per case.
#   godot --headless --path <app> --audio-driver Dummy --script <abs>/stall_probe.gd -- [--aircraft=gp-extra-300s-60]
#     [--data=<abs json>]
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const P := preload("../../flight-test/pilot.gd")

const ALTITUDE := 300.0
const HOLD_S := 5.0
const RELEASE_S := 3.0
const ENTRY_VS := 1.4  # entry speed / the FT card's power-off stall speed (summary-extra-d.md: 11.11 m/s)
const VS_CARD := 11.11


func _initialize() -> void:
	var id := "gp-extra-300s-60"
	var data_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			id = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--data="):
			data_path = arg.trim_prefix("--data=")
	var data: Variant = Catalog.entry(id).data
	if not data_path.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	for rates in ["normal", "full"]:
		for ailerons in ["hands_off", "wings_level"]:
			print(JSON.stringify(_stall(data, rates, ailerons)))
	quit(0)


func _stall(data: Variant, rates: String, ailerons: String) -> Dictionary:
	var session := Flight.new()
	session.setup(data)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	session.trim_at(ENTRY_VS * VS_CARD, "level")
	session.set_start_altitude(ALTITUDE)
	session.reset()
	session.rate_profile = rates
	var sim: Node = session.sim
	var dt: float = sim.dt()
	var ctx := {}
	var out := {case = "%s/%s" % [rates, ailerons], rates_active = session.rates_active(),
		pitch_trim = session.trims.pitch}
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
				stop = {t_s = t, speed_mps = P.speed(s), alpha_deg = rad_to_deg(P.alpha(s)), pitch_deg = rad_to_deg(e[1]),
					alt_m = P.altitude(s)}
		var since := t - t_stop if t_stop >= 0.0 else -1.0
		if since >= 0.0 and since <= HOLD_S:
			c.pitch = 1.0
			c.roll = P.bank(s, 0.0, k) if ailerons == "wings_level" else 0.0
			max_alpha = maxf(max_alpha, rad_to_deg(P.alpha(s)))
			max_bank = maxf(max_bank, absf(rad_to_deg(e[2])))
			min_pitch = minf(min_pitch, rad_to_deg(e[1]))
			var yaw_rate := absf(rad_to_deg(_earth_yaw_rate(s)))
			max_yaw_rate = maxf(max_yaw_rate, yaw_rate)
			if since > 3.0:
				late_yaw += yaw_rate * dt
			if first_bank_20 < 0.0 and absf(rad_to_deg(e[2])) > 20.0:
				first_bank_20 = since
		elif since > HOLD_S:
			c.pitch = 0.0
			c.roll = 0.0
			if not out.has("hold_end"):
				out.hold_end = _row(s, since)
			if since > HOLD_S + RELEASE_S:
				out.release_end = _row(s, since)
				break
		if since >= 0.0 and roundi(since / dt) % roundi(0.25 / dt) == 0:
			series.append(_row(s, since))
		session.commands = {roll = c.roll, pitch = c.pitch, yaw = c.yaw, throttle = c.throttle}
		sim.inputs = session._inputs()
		sim.step()
		if not sim.fault_reason.is_empty() or not session.crash.is_empty():
			out.stopped = sim.fault_reason + str(session.crash)
			break
	var late_rate := late_yaw / 2.0
	out.stop = stop
	out.elevator_at_stop_deg = _stop_deflection(session)
	out.max_alpha_held_deg = max_alpha
	out.max_bank_held_deg = max_bank
	out.first_bank_20_after_stop_s = first_bank_20
	out.nose_drop_deg = float(stop.get("pitch_deg", NAN)) - min_pitch
	out.max_rotation_rate_dps = max_yaw_rate
	out.rotation_rate_last_2_s_dps = late_rate
	out.height_lost_held_m = float(stop.get("alt_m", NAN)) - float(out.get("hold_end", {}).get("alt_m", NAN))
	out.outcome = "spin entry" if late_rate > 90.0 else ("wing drop" if max_bank >= 30.0 else "mush")
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


func _row(s: PackedFloat64Array, since: float) -> Dictionary:
	var e := P.euler(s)
	return {t = snappedf(since, 0.01), alpha = snappedf(rad_to_deg(P.alpha(s)), 0.1), beta = snappedf(rad_to_deg(P.beta(s)), 0.1),
		bank = snappedf(rad_to_deg(e[2]), 0.1), pitch = snappedf(rad_to_deg(e[1]), 0.1), v = snappedf(P.speed(s), 0.01),
		climb = snappedf(P.climb_rate(s), 0.01), p = snappedf(rad_to_deg(s[RB.RATE]), 1.0), r = snappedf(rad_to_deg(s[RB.RATE + 2]), 1.0),
		alt_m = snappedf(P.altitude(s), 0.1)}


## Rotation rate about the earth vertical (rad/s, positive right), from the body rates and attitude.
func _earth_yaw_rate(s: PackedFloat64Array) -> float:
	var e := P.euler(s)
	var q: float = s[RB.RATE + 1]
	var r: float = s[RB.RATE + 2]
	return (q * sin(e[2]) + r * cos(e[2])) / maxf(cos(e[1]), 1e-3)
