# D9b: asymmetric stall. No stall moment without rotation; autorotation (propelling roll) inside the stall break and
# linear damping outside it; a symmetric airplane stalls without rolling; a cross-controlled stall spins; the standard
# recovery (opposite rudder, stick forward) stops it.
# Run: godot --headless --path . --script res://tests/test_spin.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

const ZERO := { elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


## Total roll-moment coefficient (static + rate terms) at airspeed V, α, roll rate p.
func _cl_total(model: Dictionary, V: float, alpha: float, p: float) -> float:
	var s := RB.make_state(M.v3(0, 0, -50), M.v3(V * cos(alpha), 0.0, V * sin(alpha)), M.q_identity(), M.v3(p, 0.0, 0.0))
	var air := Air.compute(s, M.v3(0, 0, 0))
	var l := Aero.loads(s, air, ZERO, model, 1.225)
	return l[3] / (air.qbar * model.reference.S * model.reference.b)


func _initialize() -> void:
	var model: Dictionary = AD.load_file(Scenarios.AIRCRAFT).model
	var b: float = model.reference.b

	# 1. Stalled but not rotating: both stations stall alike → no roll or yaw from the stall.
	var c := Aero.coefficients(Air.compute(RB.make_state(M.v3(0, 0, -50), M.v3(12 * cos(0.28), 0, 12 * sin(0.28)), M.q_identity(), M.v3(0, 0, 0)), M.v3(0, 0, 0)), M.v3(0, 0, 0), ZERO, model.aero, model.envelope)
	_check("stalled (α 16°), no rotation: no stall roll or yaw moment", c.Cl == 0.0 and c.Cn == 0.0, str(c))

	# 2. Roll damping ∂Cl/∂p̂: the data's Clp in attached flow; positive (autorotation) inside the stall break.
	var V := 12.0
	var dp := 0.05
	var phat := dp * b / (2.0 * V)
	var linear := model.duplicate()
	linear.erase("envelope")
	var at5 := (_cl_total(model, V, deg_to_rad(5.0), dp) - _cl_total(model, V, deg_to_rad(5.0), -dp)) / (2.0 * phat)
	var at5_lin := (_cl_total(linear, V, deg_to_rad(5.0), dp) - _cl_total(linear, V, deg_to_rad(5.0), -dp)) / (2.0 * phat)
	# (Clp −0.4496 plus the side force CYp·p acting 0.07 m above the CG: the linear oracle's total damping.)
	_check("α 5°: roll damping = the linear oracle's (attached flow at every strip)", at5 == at5_lin and absf(at5 - model.aero.Clp) < 0.005, "%.6f vs %.6f (Clp %.4f)" % [at5, at5_lin, model.aero.Clp])
	var csum := 0.0
	for y in model.envelope.station_ys:
		csum += (y / b) * (y / b)
	var n_side: int = model.envelope.station_ys.size() / 2
	_check("κ: the strips reproduce |Clp| in attached flow", absf(model.envelope.station_kappa * model.aero.CLa * csum / n_side - absf(model.aero.Clp)) < 1e-12)
	var at13 := (_cl_total(model, V, deg_to_rad(13.5), dp) - _cl_total(model, V, deg_to_rad(13.5), -dp)) / (2.0 * phat)
	_check("α 13.5° (stall break): roll damping turns positive → autorotation", at13 > 0.0, "%.3f" % at13)

	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	var m := Maneuvers.all()

	# 3. Symmetric stall (dead stick, full up elevator). A symmetric airplane does not roll; the inventory's mass
	#    asymmetry (Jxy ≠ 0) is enough to drop a wing, as a real airplane's small asymmetries do.
	var tr: RefCounted = Maneuvers.fly(session, m.symmetric_stall)
	var roll_inv := _max_abs(tr, "roll_deg")
	var j: PackedFloat64Array = session.aircraft.model.inertia.duplicate()
	var jxy := j[3]
	j[3] = 0.0
	j[5] = 0.0
	session.aircraft.model.inertia = j
	session.sim.inertia = j
	tr = Maneuvers.fly(session, m.symmetric_stall)
	var alpha_max := 0.0
	for r in tr.row_count():
		alpha_max = maxf(alpha_max, rad_to_deg(atan2(float(tr.value(r, "w_mps")), float(tr.value(r, "u_mps")))))
	_check("symmetric airplane: stalls (α > 20°) without rolling (< 0.5°)", alpha_max > 20.0 and _max_abs(tr, "roll_deg") < 0.5, "α max %.0f°, roll max %.2f°" % [alpha_max, _max_abs(tr, "roll_deg")])
	_check("inventory airplane (Jxy %.4f): the stall drops a wing" % jxy, roll_inv > 20.0, "roll max %.0f°" % roll_inv)
	session.aircraft = AD.load_file(Scenarios.AIRCRAFT)
	session.sim.inertia = session.aircraft.model.inertia

	# 4. Spin: power-off, full up elevator + full right rudder; then the standard recovery.
	tr = Maneuvers.fly(session, m.spin_right)
	var r_mean := 0.0
	var rows := 0
	for r in range(roundi(2.5 * 240), roundi(4.0 * 240)):
		r_mean += tr.value(r, "r_radps")
		rows += 1
	r_mean /= rows
	var sink: float = (tr.value(roundi(2.0 * 240), "alt_m") - tr.value(roundi(4.0 * 240), "alt_m")) / 2.0
	_check("cross-controlled stall → right spin: mean yaw rate 3–10 rad/s over 2.5–4 s (about 1 turn/s)", r_mean > 3.0 and r_mean < 10.0, "%.2f rad/s" % r_mean)
	_check("spin sink rate 6–14 m/s", sink > 6.0 and sink < 14.0, "%.1f m/s" % sink)
	var ok_recovered := true
	for r in range(roundi(6.0 * 240), tr.row_count()):
		var a := rad_to_deg(atan2(float(tr.value(r, "w_mps")), float(tr.value(r, "u_mps"))))
		ok_recovered = ok_recovered and absf(tr.value(r, "p_radps")) < 1.0 and absf(tr.value(r, "r_radps")) < 1.0 and a < 10.0
	_check("standard recovery (opposite rudder, forward stick, 0.9 s): rotation stopped and stays stopped from 6 s", ok_recovered)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _max_abs(trace: RefCounted, column: String) -> float:
	var m := 0.0
	for r in trace.row_count():
		m = maxf(m, absf(trace.value(r, column)))
	return m
