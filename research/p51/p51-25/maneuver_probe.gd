# P51-25: the P-51 handling-test inside loop (or spin) flown through the real session, printed every 0.25 s, with a
# loop summary up to closure (integrated q >= 360 deg): peak pitch attitude and peak |beta|. A loop passes the vertical;
# a rolling departure also integrates 360 deg of q. Research only.
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/maneuver_probe.gd [-- --which=loop|spin --stick=0.7 --data=...]
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")


func _initialize() -> void:
	var data := "res://data/aircraft/p51d_mustang_120.json"
	var which := "loop"
	var stick := 0.7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--data="):
			data = a.substr(7)
		if a.begins_with("--stick="):
			stick = float(a.substr(8))
		if a.begins_with("--which="):
			which = a.substr(8)
	var session := FlightSession.new()
	session.setup(data)
	root.add_child(session)
	session.input_enabled = false
	var m: Dictionary
	if which == "loop":
		m = { mode = "level", speed = 27.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			return Maneuvers._pulse(t, 0.2, 8.0, { pitch = stick, throttle_delta = 1.0 }) }
	else:
		m = { mode = "level", speed = 18.0, altitude = 200.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
			var c := Maneuvers._pulse(t, 0.25, 4.0, { pitch = 1.0, yaw = 1.0 })
			if t >= 4.0 and t < 4.9:
				c = { roll = 0.0, pitch = -0.5, yaw = -1.0, throttle_delta = 0.0 }
			c.throttle_delta = -1.0
			return c }
	var tr: RefCounted = Maneuvers.fly(session, m)
	var dt: float = session.sim.dt()
	var every := int(round(0.25 / dt))
	print("t    V     alt   pitch  roll   yaw    beta   alpha  p      q      r      rpm   srv_yaw")
	for r in range(0, tr.row_count(), every):
		var u: float = tr.value(r, "u_mps")
		var v: float = tr.value(r, "v_mps")
		var w: float = tr.value(r, "w_mps")
		print("%4.2f %5.1f %5.1f %6.1f %6.1f %6.1f %6.1f %6.1f %6.2f %6.2f %6.2f %5.0f %6.2f" % [r * dt, tr.value(r, "speed_mps"), tr.value(r, "alt_m"),
			tr.value(r, "pitch_deg"), tr.value(r, "roll_deg"), tr.value(r, "yaw_deg"), rad_to_deg(atan2(v, sqrt(u * u + w * w))),
			rad_to_deg(atan2(w, u)), tr.value(r, "p_radps"), tr.value(r, "q_radps"), tr.value(r, "r_radps"), tr.value(r, "engine_rpm"), tr.value(r, "srv_yaw")])
	var turned := 0.0
	var top := -1e9
	var slip := 0.0
	var roll_top := 0.0
	for r in tr.row_count():
		if turned >= TAU:
			break
		turned += float(tr.value(r, "q_radps")) * dt
		var u: float = tr.value(r, "u_mps")
		var w: float = tr.value(r, "w_mps")
		slip = maxf(slip, absf(rad_to_deg(atan2(float(tr.value(r, "v_mps")), sqrt(u * u + w * w)))))
		if tr.value(r, "pitch_deg") > top:
			top = tr.value(r, "pitch_deg")
	print("SUMMARY turned %.0f deg, pitch max %.1f, |beta| max %.1f until closure" % [rad_to_deg(turned), top, slip])
	quit(0)
