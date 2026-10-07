# D8a: flight modes of the real equations (physics/flight_modes.gd) at 10, 15 and 25 m/s. Regression bands (± 3 %
# around the values recorded on 2026-10-05) plus physical sanity: oscillatory/roll modes damped and the measured numerical spiral root retained.
# A deliberate change to the aero (e.g. a Clp sign flip) moves the modes out of their bands. D11g: the Stik's modes carry
# the tail's downwash lag as a ninth state; its linear model must predict the nonlinear flight (time-domain check).
# Run: godot --headless --path . --script res://tests/test_modes.gd
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const L := preload("res://physics/linearize.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

## V → [short period Hz, ζ; phugoid Hz, ζ; roll τ s; dutch roll Hz, ζ; spiral eigenvalue 1/s], recorded 2026-10-06 after D9-R/D1-R1; see flight-repair-implementation.md.
## 10 m/s re-recorded 2026-10-07 by D11d: it trims at α 12.2°, in the local strip model, where the wing's induced-flow
## map removed the strip-theory over-damping (roll τ 0.048 → 0.092 s) and the lift-slope bump that had masked the
## local tail's weak pitch damping (short period ζ 0.61 → 0.47, E0a2) and fin yaw damping (spiral 0.34 → 0.59, D11f).
## 10 m/s re-recorded again by E0a2a the same day: pitch rate now acts on the free tail slope (Cmq ×0.28 → ×0.64 of
## the oracle), short period ζ 0.47 → 0.52 and 0.90 → 0.99 Hz; roll, dutch roll and spiral nearly unchanged.
## All re-recorded by D11g (2026-10-07): the oracle's Cmq/CLq/Cnr are the Stik's own (−7.476/2.951/−0.1319 for the
## borrowed −13.57/6.16/−0.1833) and the modes carry the downwash lag (ninth value: its real root, 1/s). 10 m/s: the lag
## state alone (ζ 0.52 → 0.60). 15/25 m/s: short period ζ 0.74/0.75 → 0.78/0.81, phugoid ζ 0.26/0.74 → 0.21/0.64,
## dutch roll ζ 0.29/0.28 → 0.24/0.23, spiral +0.034/−0.0002 → +0.086/+0.032 1/s (Cnr). Report: D11g.
const BANDS := {
	10.0: [1.03203198, 0.59932354, 0.19049088, 0.07156103, 0.09205808, 0.58713489, 0.33835158, 0.59118689, -11.98778185],
	15.0: [1.42880691, 0.78398615, 0.11682285, 0.20967634, 0.05133627, 0.76704244, 0.24301315, 0.08570071, -16.75947762],
	25.0: [2.30492474, 0.80907652, 0.07020446, 0.64062557, 0.03055681, 1.23159251, 0.22767165, 0.03246443, -27.81774077],
}
const TOL := 0.03
## Short-period damping floor per speed (default 0.5). D11d had to pin 10 m/s at 0.45 (ζ 0.47 with the tail's Cmq at
## 0.28× the oracle); E0a2a's free tail slope brought it back to 0.52, so no speed needs an exception now.
const SHORT_PERIOD_ZETA_FLOOR := {}

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(label: String, got: float, want: float) -> void:
	_check(label, absf(got - want) <= TOL * absf(want), "%.4f vs %.4f" % [got, want])


func _initialize() -> void:
	# Known answer for the eigenvalue machinery: (x+1)(x+2)(x²+2x+5) → −1, −2, −1 ± 2i.
	var ev := L.classify(L.eigenvalues([
		PackedFloat64Array([0, 1, 0, 0]), PackedFloat64Array([0, 0, 1, 0]),
		PackedFloat64Array([0, 0, 0, 1]), PackedFloat64Array([-10, -19, -13, -5])]))
	_check("eigenvalues of a known companion matrix", ev.real.size() == 2 and absf(ev.real[0] + 2.0) < 1e-9 and absf(ev.real[1] + 1.0) < 1e-9
		and absf(ev.oscillatory[0].wn - sqrt(5.0)) < 1e-9 and absf(ev.oscillatory[0].zeta - 1.0 / sqrt(5.0)) < 1e-9, str(ev))
	# D11g: the 5×5 longitudinal block with the lag. (x+3)(x²+2x+5)(x²+x+1) → −3, −1 ± 2i, −0.5 ± 0.866i.
	var ev5 := L.classify(L.eigenvalues([
		PackedFloat64Array([0, 1, 0, 0, 0]), PackedFloat64Array([0, 0, 1, 0, 0]), PackedFloat64Array([0, 0, 0, 1, 0]),
		PackedFloat64Array([0, 0, 0, 0, 1]), PackedFloat64Array([-15, -26, -31, -17, -6])]))
	_check("eigenvalues of a known 5×5 companion matrix", ev5.real.size() == 1 and absf(ev5.real[0] + 3.0) < 1e-9
		and ev5.oscillatory.size() == 2 and absf(ev5.oscillatory[0].wn - sqrt(5.0)) < 1e-9 and absf(ev5.oscillatory[1].wn - 1.0) < 1e-9
		and absf(ev5.oscillatory[1].zeta - 0.5) < 1e-9, str(ev5))

	var model: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT).model
	for V in BANDS:
		var b: Array = BANDS[V]
		var r := FlightModes.analyze(model, V)
		_check("%.0f m/s: modes found" % V, r.ok, r.get("message", ""))
		if not r.ok:
			continue
		_near("%.0f m/s short period Hz" % V, r.short_period.f_hz, b[0])
		_near("%.0f m/s short period ζ" % V, r.short_period.zeta, b[1])
		_near("%.0f m/s phugoid Hz" % V, r.phugoid.f_hz, b[2])
		_near("%.0f m/s phugoid ζ" % V, r.phugoid.zeta, b[3])
		_near("%.0f m/s roll τ" % V, r.roll_tau, b[4])
		_near("%.0f m/s dutch roll Hz" % V, r.dutch_roll.f_hz, b[5])
		_near("%.0f m/s dutch roll ζ" % V, r.dutch_roll.zeta, b[6])
		_near("%.0f m/s signed spiral eigenvalue" % V, -1.0 / r.spiral_tau, b[7])
		_near("%.0f m/s downwash lag root" % V, r.downwash_lag_root, b[8])
		var lag_rate: float = V / float(model.surfaces.horizontal.downwash_lag_length)
		_check("%.0f m/s: the lag root is real and near −V/l = %.1f (coupled with the short period: 0.7–1.0×)" % [V, -lag_rate],
			r.downwash_lag_root < -0.7 * lag_rate and r.downwash_lag_root > -lag_rate, "%.2f" % r.downwash_lag_root)
		_check("%.0f m/s: oscillatory modes and roll subsidence are damped" % V, r.short_period.zeta > 0 and r.phugoid.zeta > 0 and r.roll_tau > 0 and r.dutch_roll.zeta > 0)
		var floor: float = SHORT_PERIOD_ZETA_FLOOR.get(V, 0.5)
		_check("%.0f m/s: short period well damped (%.2f–1), faster than the dutch roll" % [V, floor], r.short_period.zeta > floor and r.short_period.zeta < 1.0 and r.short_period.f_hz > r.dutch_roll.f_hz)

	_time_domain(model)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## D11g: the real flight (FlightSession, RK4, lag advanced in _pre_step) from its 15 m/s trim, kicked in w by 0.6 m/s,
## against the linear 9-state model (full Jacobian with the lag) propagated with the same tick. Must agree within 3 % of
## the peak pitch-rate response over 1.5 s; the quasi-static 8-state model (no lag state) is reported for comparison.
func _time_domain(model: Dictionary) -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	var lag: int = session.downwash_index()
	var lagged := FlightModes.analyze(model, 15.0)
	var quasi_model := model.duplicate(true)
	quasi_model.surfaces.horizontal.erase("downwash_lag_length")
	var quasi := FlightModes.analyze(quasi_model, 15.0)
	var x_of := func(st: PackedFloat64Array, lag_cl: float) -> PackedFloat64Array:
		var e := M.q_to_euler(st.slice(RB.ATT, RB.ATT + 4))
		return PackedFloat64Array([st[RB.VEL], st[RB.VEL + 1], st[RB.VEL + 2], st[RB.RATE], st[RB.RATE + 1], st[RB.RATE + 2], e[2], e[1], lag_cl])
	var trim: PackedFloat64Array = x_of.call(session.sim.state, session.sim.aux[lag])
	var s: PackedFloat64Array = session.sim.state
	s[RB.VEL + 2] += 0.6
	session.sim.state = s
	var dt := 1.0 / 240.0
	var x9 := PackedFloat64Array()
	var start: PackedFloat64Array = x_of.call(session.sim.state, session.sim.aux[lag])
	for j in 9:
		x9.append(start[j] - trim[j])
	var x8 := x9.slice(0, 8)
	var worst := 0.0
	var worst_quasi := 0.0
	var peak := 0.0
	for i in 360:
		session.sim.step()
		x9 = _rk4(lagged.full_jacobian, x9, dt)
		x8 = _rk4(quasi.full_jacobian, x8, dt)
		var dq: float = session.sim.state[RB.RATE + 1] - trim[4]
		peak = maxf(peak, absf(dq))
		worst = maxf(worst, absf(x9[4] - dq))
		worst_quasi = maxf(worst_quasi, absf(x8[4] - dq))
	session.queue_free()
	print("info 15 m/s w-kick: peak q %.3f rad/s; linear error with the lag state %.2f %%, quasi-static %.1f %%"
		% [peak, 100.0 * worst / peak, 100.0 * worst_quasi / peak])
	_check("15 m/s: the linear model with the lag state predicts the flight's pitch response within 3 % of its peak",
		worst < 0.03 * peak, "%.2f %%" % (100.0 * worst / peak))


func _rk4(a: Array, x: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var k1 := _times(a, x)
	var k2 := _times(a, _plus(x, k1, 0.5 * dt))
	var k3 := _times(a, _plus(x, k2, 0.5 * dt))
	var k4 := _times(a, _plus(x, k3, dt))
	var out := x.duplicate()
	for j in x.size():
		out[j] += dt / 6.0 * (k1[j] + 2.0 * k2[j] + 2.0 * k3[j] + k4[j])
	return out


func _times(a: Array, x: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(x.size())
	for i in x.size():
		var row: PackedFloat64Array = a[i]
		var acc := 0.0
		for j in x.size():
			acc += row[j] * x[j]
		out[i] = acc
	return out


func _plus(x: PackedFloat64Array, k: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var out := x.duplicate()
	for j in x.size():
		out[j] += h * k[j]
	return out
