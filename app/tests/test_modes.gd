# D8a: flight modes of the real equations (physics/flight_modes.gd) at 10, 15 and 25 m/s. Regression bands (± 3 %
# around the values recorded on 2026-10-05) plus physical sanity: every mode stable and of the expected kind.
# A deliberate change to the aero (e.g. a Clp sign flip) moves the modes out of their bands.
# Run: godot --headless --path . --script res://tests/test_modes.gd
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightModes := preload("res://physics/flight_modes.gd")
const L := preload("res://physics/linearize.gd")
const Scenarios := preload("res://sim/scenarios.gd")

## V → [short period Hz, ζ; phugoid Hz, ζ; roll τ s; dutch roll Hz, ζ; spiral τ s], recorded 2026-10-05.
const BANDS := {
	10.0: [1.4167, 0.7611, 0.1539, 0.1431, 0.07755, 0.5091, 0.3995, 14.296],
	15.0: [2.0333, 0.7835, 0.09991, 0.3054, 0.05101, 0.7098, 0.3943, 9.535],
	25.0: [3.3168, 0.7971, 0.05908, 0.8639, 0.03041, 1.1391, 0.4004, 11.575],
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
		_near("%.0f m/s spiral τ" % V, r.spiral_tau, b[7])
		_check("%.0f m/s: every mode stable" % V, r.short_period.zeta > 0 and r.phugoid.zeta > 0 and r.roll_tau > 0 and r.dutch_roll.zeta > 0 and r.spiral_tau > 0)
		_check("%.0f m/s: short period well damped (0.5–1), faster than the dutch roll" % V, r.short_period.zeta > 0.5 and r.short_period.zeta < 1.0 and r.short_period.f_hz > r.dutch_roll.f_hz)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
