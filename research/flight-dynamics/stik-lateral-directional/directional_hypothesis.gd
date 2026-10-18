# Hypothesis test (2026-10-18): the Stik's data Cnβ (0.1274 = a_v·S_v/S·l_v/b, fin only, efficiency 1) omits the
# fin's sidewash/dynamic-pressure efficiency and the fuselage's destabilizing moment. Independent geometry estimates
# (directional_prediction.py: DATCOM ηv(1+dσ/dβ) 0.684 for this high wing, Raymer and Munk body terms) predict Cnβ 0.068–0.074.
# This probe edits ONLY the derived in-memory Cnβ (no data, loader or law change) and compares the linear modes with
# the flight-identified Ultra Stick 120 (Froude-scaled) and Ultra Stick 25e, then flies the test_rudder_authority
# reference doublet. Run from the repository root:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/directional_hypothesis.gd"
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const G := 9.80665

const VARIANTS := [
	["A data (fin only, η = 1)", NAN],
	["B predicted, Raymer body", 0.0741],
	["C predicted, Munk body", 0.0679],
	["E UltraStick 25e borrowed", 0.0723],
]
const US25E := { V = 19.0, m = 1.959, S = 0.31, b = 1.27, dr_wn = 4.96, dr_zeta = 0.33 }


func _initialize() -> void:
	print("Reference bands: US120 (Froude-scaled, 13.8 m/s): DR 0.57 Hz ζ 0.31, spiral stable τ 4.3 s; Ultra Stick 25e (19 m/s): DR ω·b/2V 0.1658 ζ 0.33")
	print("| Variant | Cnβ | DR 13.8 m/s | spiral 13.8 m/s | DR ω·b/2V vs 25e (ratio) | DR ζ (25e CL) | spiral (25e CL) | doublet βpk | rpk | r@3s | max|r−r_turn| 3.0–4.5 s | full-rudder β_ss |")
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for variant: Array in VARIANTS:
		var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
		if not is_nan(variant[1]):
			model.aero.Cnb = variant[1]
		var cnb: float = model.aero.Cnb
		var us120: Dictionary = FlightModes.analyze(model, 13.8)
		var rho := 1.225
		var cl: float = 2.0 * US25E.m * G / (rho * US25E.V * US25E.V * US25E.S)
		var v25: float = sqrt(2.0 * model.mass_kg * G / (rho * model.reference.S * cl))
		var e25: Dictionary = FlightModes.analyze(model, v25)
		var nd_sim: float = TAU * e25.dutch_roll.f_hz * model.reference.b / (2.0 * v25)
		var nd_ref: float = US25E.dr_wn * US25E.b / (2.0 * US25E.V)
		var doublet := _doublet(variant[1])
		var dr: float = deg_to_rad(25.0)
		var beta_ss: float = rad_to_deg(absf(model.aero.Cndr) * dr / cnb)
		print("| %s | %.4f | %.2f Hz ζ %.3f | %s τ %.1f s | %.4f (%.2f×) | %.3f | %s τ %.1f s | %.1f° | %.1f°/s | %.2f°/s | %.1f°/s | %.0f° |" % [variant[0], cnb,
			us120.dutch_roll.f_hz, us120.dutch_roll.zeta, "stable" if us120.spiral_tau > 0.0 else "unstable", us120.spiral_tau,
			nd_sim, nd_sim / nd_ref, e25.dutch_roll.zeta, "stable" if e25.spiral_tau > 0.0 else "unstable", e25.spiral_tau,
			doublet.beta_pk, doublet.r_pk, doublet.r3, doublet.uncoord_pk, beta_ss])
	quit(0)


func _doublet(cnb: float) -> Dictionary:
	Engine.physics_ticks_per_second = 240
	var session := FlightSession.new()
	session.setup()
	session.reset()
	root.add_child(session)
	if not is_nan(cnb):
		session.aircraft.model.aero.Cnb = cnb
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet.duplicate()
	maneuver.duration = 4.5
	var trace: RefCounted = Maneuvers.fly(session, maneuver)
	var t0: float = trace.value(0, "t_s")
	var out := { beta_pk = 0.0, r_pk = 0.0, r3 = NAN, uncoord_pk = 0.0 }
	for i in trace.row_count():
		var t: float = trace.value(i, "t_s") - t0
		var V: float = trace.value(i, "speed_mps")
		var beta := rad_to_deg(asin(clampf(trace.value(i, "v_mps") / V, -1.0, 1.0)))
		var r := rad_to_deg(trace.value(i, "r_radps"))
		var phi := deg_to_rad(trace.value(i, "roll_deg"))
		var theta := deg_to_rad(trace.value(i, "pitch_deg"))
		var r_turn := rad_to_deg(G / V * sin(phi) * cos(theta))
		if t <= 3.0 + 1e-9:
			out.beta_pk = maxf(out.beta_pk, absf(beta))
			out.r_pk = maxf(out.r_pk, absf(r))
		if absf(t - 3.0) < 0.5 / 240.0:
			out.r3 = r
		if t >= 3.0 and t <= 4.5:
			out.uncoord_pk = maxf(out.uncoord_pk, absf(r - r_turn))
	session.free()
	return out
