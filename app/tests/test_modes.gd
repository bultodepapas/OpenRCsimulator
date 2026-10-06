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
const BANDS := {
	10.0: [0.93456108, 0.60606421, 0.18538193, 0.03848759, 0.04835588, 0.56133800, 0.28171259, 0.34469273],
	15.0: [1.49500773, 0.73929294, 0.10320199, 0.25587799, 0.05132182, 0.77321646, 0.28941683, 0.03421904],
	25.0: [2.42675587, 0.75475678, 0.06150803, 0.74298038, 0.03054795, 1.24178630, 0.27935633, -0.00020070],
}
const TOL := 0.03

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
		_check("%.0f m/s: short period well damped (0.5–1), faster than the dutch roll" % V, r.short_period.zeta > 0.5 and r.short_period.zeta < 1.0 and r.short_period.f_hz > r.dutch_roll.f_hz)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
