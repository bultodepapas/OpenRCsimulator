# P51-25: steady roll helix angle pb/2V after an abrupt aileron step with the rudder held at trim, as in the NACA
# flying-qualities tests (MR L-566 Figure 28: XP-51, cruising, pb/2V versus total aileron deflection).
# Uses the real FlightSession loop. Research only.
# Run: <godot> --headless --path app --audio-driver Dummy --script <abs>/roll_probe.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup("res://data/aircraft/p51d_mustang_120.json")
	root.add_child(session)
	session.input_enabled = false
	var model: Dictionary = session.aircraft.model
	var b: float = model.reference.b
	var throw_deg: float = model.controls.throw_deg.aileron
	for speed: float in [20.0, 25.0, 35.0, 45.0]:
		for stick: float in [0.25, 0.5, 1.0]:
			var m := { mode = "level", speed = speed, altitude = 300.0, duration = 2.5, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
				return Maneuvers._pulse(t, 0.2, 2.5, { roll = stick }) }
			var tr: RefCounted = Maneuvers.fly(session, m)
			var p_max := 0.0
			var v_at := speed
			for r in tr.row_count():
				var p: float = absf(tr.value(r, "p_radps"))
				if p > p_max:
					p_max = p
					v_at = tr.value(r, "speed_mps")
			# Total aileron deflection = sum of both surfaces = 2 x one-side throw x stick (antisymmetric ailerons).
			var total_deg := 2.0 * throw_deg * stick
			var helix := p_max * b / (2.0 * v_at)
			print("V %.0f stick %.2f total %.1f deg: p_max %.3f rad/s pb/2V %.4f per total deg %.5f" % [speed, stick, total_deg, p_max, helix, helix / total_deg])
	quit(0)
