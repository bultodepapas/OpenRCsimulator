# Evaluates the replacement recovery criteria (fixed from the flight references before measuring, 2026-10-18) for the
# data Cnβ and for an in-memory Cnβ: linear Dutch roll at the Ultra Stick 25e CL (ω·b/2V within ±20 % of 0.1658,
# ζ within 0.264–0.396), spiral stable or doubling time ≥ 20 s, and the nonlinear decay of the uncoordinated yaw rate
# |r − (g/V)·sinφ·cosθ| over 2.5–4.0 s after release ≤ 10 % of the doublet's |r| peak, both doublet directions.
# Run: godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/acceptance_probe.gd" -- [--cnb=0.0742]
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const G := 9.80665


func _initialize() -> void:
	var cnb := NAN
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--cnb="): cnb = float(arg.trim_prefix("--cnb="))
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	if not is_nan(cnb): model.aero.Cnb = cnb
	var cl: float = 2.0 * 1.959 * G / (1.225 * 19.0 * 19.0 * 0.31)
	var v: float = sqrt(2.0 * model.mass_kg * G / (1.225 * model.reference.S * cl))
	var m: Dictionary = FlightModes.analyze(model, v)
	var nd: float = TAU * m.dutch_roll.f_hz * model.reference.b / (2.0 * v) / 0.1658
	var doubling: float = INF if m.spiral_tau > 0.0 else -m.spiral_tau * log(2.0)
	print("Cnβ %.4f: DR ω·b/2V ratio %.3f [0.8, 1.2], ζ %.3f [0.264, 0.396], spiral τ %.2f s (doubling %s s, ≥ 20)" % [model.aero.Cnb, nd, m.dutch_roll.zeta, m.spiral_tau, str(snappedf(doubling, 0.01))])
	for sign: float in [1.0, -1.0]:
		var d := _doublet(cnb, sign)
		print("  %s-first: |r| peak %.1f°/s, β peak %.2f°, decay max|r−r_turn| 4.0–5.5 s %.2f°/s = %.1f %% of peak (≤ 10 %%), r(3 s) %.2f°/s" % [
			"right" if sign > 0.0 else "left", d.r_pk, d.beta_pk, d.decay, 100.0 * d.decay / d.r_pk, d.r3])
	quit(0)


func _doublet(cnb: float, sign: float) -> Dictionary:
	Engine.physics_ticks_per_second = 240
	var session := FlightSession.new()
	session.setup()
	session.reset()
	root.add_child(session)
	if not is_nan(cnb):
		session.aircraft.model.aero.Cnb = cnb
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet.duplicate()
	var original: Callable = maneuver.sticks
	maneuver.sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
		var out: Dictionary = original.call(t, s)
		out.yaw = sign * float(out.yaw)
		return out
	maneuver.duration = 5.5
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	var t0: float = trace.value(0, "t_s")
	var out := { r_pk = 0.0, beta_pk = 0.0, decay = 0.0, r3 = NAN }
	for i in trace.row_count():
		var t: float = trace.value(i, "t_s") - t0
		var V: float = trace.value(i, "speed_mps")
		var r := rad_to_deg(trace.value(i, "r_radps"))
		var beta := rad_to_deg(asin(clampf(trace.value(i, "v_mps") / V, -1.0, 1.0)))
		var r_turn := rad_to_deg(G / V * sin(deg_to_rad(trace.value(i, "roll_deg"))) * cos(deg_to_rad(trace.value(i, "pitch_deg"))))
		if t <= 3.0 + 1e-9:
			out.r_pk = maxf(out.r_pk, absf(r))
			out.beta_pk = maxf(out.beta_pk, absf(beta))
		if absf(t - 3.0) < 0.5 / 240.0: out.r3 = r
		if t >= 4.0 - 1e-9 and t <= 5.5 + 1e-9:
			out.decay = maxf(out.decay, absf(r - r_turn))
	session.free()
	return out
