# Linear lateral/longitudinal modes for every flyable catalog airplane at its start speed and 1.4× that speed
# (physics/flight_modes.gd on the loaded model). Read-only. Run from the repository root:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/modes_fleet.gd" \
#     [-- --only=<catalog id> --speeds=10,10.5,11]
# --speeds replaces the two default speeds with absolute ones (m/s), e.g. near the stall where the local law carries
# part of the loads (D10-R5).
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Modes := preload("res://physics/flight_modes.gd")
const RB := preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	var only := ""
	var speeds := PackedFloat64Array()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--speeds="):
			for value in arg.trim_prefix("--speeds=").split(","):
				speeds.append(float(value))
	print("MODES id V_mps SP_Hz SP_zeta DR_Hz DR_zeta roll_tau_s spiral_tau_s")
	for id: String in Catalog.airplane_flyable_ids():
		if not only.is_empty() and id != only:
			continue
		var session := FlightSession.new()
		session.input_enabled = false
		session.setup(Catalog.entry(id).data, id)
		if not session.is_flyable():
			session.free()
			continue
		var s: PackedFloat64Array = session.sim.state
		var v0 := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
		for V: float in (speeds if not speeds.is_empty() else PackedFloat64Array([v0, 1.4 * v0])):
			var m: Dictionary = Modes.analyze(session.aircraft.model, V)
			if m.ok:
				print("MODES %s %.2f %.3f %.3f %.3f %.3f %.4f %.2f" % [id, V, m.short_period.f_hz, m.short_period.zeta,
					m.dutch_roll.f_hz, m.dutch_roll.zeta, m.roll_tau, m.spiral_tau])
			else:
				print("MODES %s %.2f unavailable: %s" % [id, V, m.message])
		session.free()
	quit(0)
