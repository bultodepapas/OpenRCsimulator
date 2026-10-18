# Linear lateral/longitudinal modes for every flyable catalog airplane at its start speed and 1.4× that speed
# (physics/flight_modes.gd on the loaded model). Read-only. Run from the repository root:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/modes_fleet.gd"
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Modes := preload("res://physics/flight_modes.gd")
const RB := preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	print("MODES id V_mps SP_Hz SP_zeta DR_Hz DR_zeta roll_tau_s spiral_tau_s")
	for id: String in Catalog.airplane_flyable_ids():
		var session := FlightSession.new()
		session.input_enabled = false
		session.setup(Catalog.entry(id).data, id)
		if not session.is_flyable():
			session.free()
			continue
		var s: PackedFloat64Array = session.sim.state
		var v0 := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
		for V: float in [v0, 1.4 * v0]:
			var m: Dictionary = Modes.analyze(session.aircraft.model, V)
			if m.ok:
				print("MODES %s %.2f %.3f %.3f %.3f %.3f %.4f %.2f" % [id, V, m.short_period.f_hz, m.short_period.zeta,
					m.dutch_roll.f_hz, m.dutch_roll.zeta, m.roll_tau, m.spiral_tau])
			else:
				print("MODES %s %.2f unavailable: %s" % [id, V, m.message])
		session.free()
	quit(0)
