# Rudder-recovery diagnosis (2026-10-18): the test_rudder_authority reference doublet (Ugly Stik, 15 m/s, full rudder
# right 0.5–1.0 s then left 1.0–1.5 s, released after) flown through the real FlightSession for a longer window.
# Splits the body yaw rate r into the coordinated-turn part r_turn = (g/V)·sinφ·cosθ, which a banked airplane needs
# to turn, and the uncoordinated remainder r − r_turn, and reports the linear lateral modes at the same speed.
# Read-only: nothing under app/ changes. Run from the repository root:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/probe.gd" -- [--seconds=12] [--hz=240] [--reverse] [--csv=out.csv]
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Modes := preload("res://physics/flight_modes.gd")
const G := 9.80665


func _initialize() -> void:
	var seconds := 12.0
	var hz := 240
	var reverse := false
	var csv_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
		elif arg == "--reverse": reverse = true
		elif arg.begins_with("--csv="): csv_path = arg.trim_prefix("--csv=")
	Engine.physics_ticks_per_second = hz
	var session := Session.new()
	session.setup()
	session.reset()
	root.add_child(session)
	var modes: Dictionary = Modes.analyze(session.aircraft.model, 15.0)
	if modes.ok:
		print("MODES 15 m/s: roll_tau %.3f s, dutch roll %.3f Hz zeta %.3f, spiral_tau %.2f s (negative = divergent)" % [
			modes.roll_tau, modes.dutch_roll.f_hz, modes.dutch_roll.zeta, modes.spiral_tau])
	else:
		print("MODES unavailable: ", modes.message)
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet.duplicate()
	maneuver.duration = seconds
	var original: Callable = maneuver.sticks
	var sign := -1.0 if reverse else 1.0
	maneuver.sticks = func(t: float, s: PackedFloat64Array) -> Dictionary:
		var out: Dictionary = original.call(t, s)
		out.yaw = sign * float(out.yaw)
		return out
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	var lines := PackedStringArray(["t_s,phi_deg,theta_deg,beta_deg,V_mps,p_degps,r_degps,r_turn_degps,r_uncoord_degps,psi_dot_degps,alt_m"])
	var t0: float = trace.value(0, "t_s")
	var marks := [1.5, 2.0, 2.5, 3.0, 4.0, 6.0, 8.0, 10.0, 12.0]
	print("t_s   phi°    beta°   r°/s   r_turn°/s  r-r_turn°/s  psi_dot°/s  V m/s  alt m")
	for i in trace.row_count():
		var t: float = trace.value(i, "t_s") - t0
		var phi := deg_to_rad(trace.value(i, "roll_deg"))
		var theta := deg_to_rad(trace.value(i, "pitch_deg"))
		var u: float = trace.value(i, "u_mps")
		var v: float = trace.value(i, "v_mps")
		var V: float = trace.value(i, "speed_mps")
		var p: float = trace.value(i, "p_radps")
		var q: float = trace.value(i, "q_radps")
		var r: float = trace.value(i, "r_radps")
		var beta := asin(clampf(v / V, -1.0, 1.0)) if V > 0.0 else 0.0
		var r_turn := G / V * sin(phi) * cos(theta)
		var psi_dot := (q * sin(phi) + r * cos(phi)) / cos(theta)
		lines.append("%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.4f" % [t, rad_to_deg(phi), rad_to_deg(theta),
			rad_to_deg(beta), V, rad_to_deg(p), rad_to_deg(r), rad_to_deg(r_turn), rad_to_deg(r - r_turn), rad_to_deg(psi_dot),
			trace.value(i, "alt_m")])
		for m: float in marks:
			if absf(t - m) < 0.5 / hz:
				print("%5.2f %7.2f %7.2f %7.2f %8.2f %10.2f %11.2f %7.2f %6.2f" % [t, rad_to_deg(phi), rad_to_deg(beta),
					rad_to_deg(r), rad_to_deg(r_turn), rad_to_deg(r - r_turn), rad_to_deg(psi_dot), V, trace.value(i, "alt_m")])
	if not csv_path.is_empty():
		var f := FileAccess.open(csv_path, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("wrote ", csv_path)
	session.free()
	quit(0)
