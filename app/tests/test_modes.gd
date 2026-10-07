# D8a: flight modes of the real equations (physics/flight_modes.gd) at 10, 15 and 25 m/s. Regression bands (± 3 %
# around the values recorded on 2026-10-05) plus physical sanity: oscillatory/roll modes damped and the measured numerical spiral root retained.
# A deliberate change to the aero (e.g. a Clp sign flip) moves the modes out of their bands.
# Run: godot --headless --path . --script res://tests/test_modes.gd
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const L := preload("res://physics/linearize.gd")
const Scenarios := preload("res://sim/scenarios.gd")

## V → [short period Hz, ζ; phugoid Hz, ζ; roll τ s; dutch roll Hz, ζ; spiral eigenvalue 1/s], recorded 2026-10-06 after D9-R/D1-R1; see flight-repair-implementation.md.
## 10 m/s re-recorded 2026-10-07 by D11d: it trims at α 12.2°, in the local strip model, where the wing's induced-flow
## map removed the strip-theory over-damping (roll τ 0.048 → 0.092 s) and the lift-slope bump that had masked the
## local tail's weak pitch damping (short period ζ 0.61 → 0.47, E0a2) and fin yaw damping (spiral 0.34 → 0.59, D11f).
## 10 m/s re-recorded again by E0a2a the same day: pitch rate now acts on the free tail slope (Cmq ×0.28 → ×0.64 of
## the oracle), short period ζ 0.47 → 0.52 and 0.90 → 0.99 Hz; roll, dutch roll and spiral nearly unchanged.
const BANDS := {
	10.0: [0.98753320, 0.51818297, 0.19060338, 0.06707253, 0.09213067, 0.58721214, 0.33844526, 0.59149735],
	15.0: [1.49500773, 0.73929294, 0.10320199, 0.25587799, 0.05132182, 0.77321646, 0.28941683, 0.03421904],
	25.0: [2.42675587, 0.75475678, 0.06150803, 0.74298038, 0.03054795, 1.24178630, 0.27935633, -0.00020070],
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
		_check("%.0f m/s: oscillatory modes and roll subsidence are damped" % V, r.short_period.zeta > 0 and r.phugoid.zeta > 0 and r.roll_tau > 0 and r.dutch_roll.zeta > 0)
		var floor: float = SHORT_PERIOD_ZETA_FLOOR.get(V, 0.5)
		_check("%.0f m/s: short period well damped (%.2f–1), faster than the dutch roll" % [V, floor], r.short_period.zeta > floor and r.short_period.zeta < 1.0 and r.short_period.f_hz > r.dutch_roll.f_hz)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
