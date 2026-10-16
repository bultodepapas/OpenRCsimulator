extends SceneTree
# Disposable probe: full-throttle pull-up step at several stick sizes and entry speeds.
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

func _initialize() -> void:
	var session := FlightSession.new()
	session.setup("res://data/aircraft/p51d_mustang_120.json")
	root.add_child(session)
	session.input_enabled = false
	for V: float in [27.0, 32.0]:
		for stick: float in [0.3, 0.4, 0.5, 0.6, 0.7]:
			var m := { mode = "level", speed = V, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
				return Maneuvers._pulse(t, 0.2, 8.0, { pitch = stick, throttle_delta = 1.0 }) }
			var lt: RefCounted = Maneuvers.fly(session, m)
			var turned := 0.0
			var loop_time := NAN
			var a_max := -1e9
			var b_max := 0.0
			var top := -1e9
			var vmin := 1e9
			for r in lt.row_count():
				turned += float(lt.value(r, "q_radps")) * session.sim.dt()
				if is_nan(loop_time) and turned >= TAU:
					loop_time = r * session.sim.dt()
				if is_nan(loop_time):
					var u: float = lt.value(r, "u_mps")
					var w: float = lt.value(r, "w_mps")
					a_max = maxf(a_max, rad_to_deg(atan2(w, u)))
					b_max = maxf(b_max, absf(rad_to_deg(atan2(float(lt.value(r, "v_mps")), sqrt(u * u + w * w)))))
					top = maxf(top, float(lt.value(r, "pitch_deg")))
					vmin = minf(vmin, float(lt.value(r, "speed_mps")))
			print("V %.0f stick %.1f | turned %4.0f t %4.1f | alpha max %5.1f beta max %5.1f pitch max %4.0f vmin %4.1f" % [V, stick, rad_to_deg(turned), loop_time, a_max, b_max, top, vmin])
	quit(0)
