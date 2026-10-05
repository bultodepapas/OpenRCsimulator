# D2: air data against hand-computed values, including wind and zero airspeed.
# Run: godot --headless --path . --script res://tests/test_air_data.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _state(vel_body: Array, att := M.q_identity()) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -20), M.v3(vel_body[0], vel_body[1], vel_body[2]), att, M.v3(0, 0, 0))


func _initialize() -> void:
	var calm := M.v3(0, 0, 0)

	# Straight and level at 15 m/s: alpha = beta = 0, qbar = ½·1.225·15² = 137.8125 Pa.
	var a := Air.compute(_state([15, 0, 0]), calm)
	_check("level: V", absf(a.V - 15.0) < 1e-12)
	_check("level: alpha = beta = 0", absf(a.alpha) < 1e-15 and absf(a.beta) < 1e-15)
	_check("level: qbar", absf(a.qbar - 137.8125) < 1e-9, str(a.qbar))

	# Body w > 0 (air from below) is positive alpha: atan(1/15) = 3.8141°.
	a = Air.compute(_state([15, 0, 1]), calm)
	_check("alpha from w", absf(rad_to_deg(a.alpha) - 3.8140748342903543) < 1e-9, str(rad_to_deg(a.alpha)))
	# Body v > 0 (air from the right) is positive beta: asin(2/V).
	a = Air.compute(_state([15, 2, 0]), calm)
	_check("beta from v", absf(a.beta - asin(2.0 / sqrt(229.0))) < 1e-12, str(a.beta))

	# Wind: 5 m/s headwind (air moving south, airplane heading north at 15 m/s ground speed) → 20 m/s airspeed.
	a = Air.compute(_state([15, 0, 0]), M.v3(-5, 0, 0))
	_check("headwind adds airspeed", absf(a.V - 20.0) < 1e-12, str(a.V))
	# Crosswind from the east (air moving west) while heading north → air comes from the right → beta > 0.
	a = Air.compute(_state([15, 0, 0]), M.v3(0, -3, 0))
	_check("crosswind from the right → beta > 0", a.beta > 0.0 and absf(a.beta - atan2(3.0, 15.0)) < 1e-12, str(a.beta))
	# Same crosswind, airplane heading east: it is now a headwind (body frame rotates the wind).
	a = Air.compute(_state([15, 0, 0], M.q_from_euler(PI / 2, 0, 0)), M.v3(0, -3, 0))
	_check("wind rotated into body axes", absf(a.V - 18.0) < 1e-12 and absf(a.beta) < 1e-12, "%s %s" % [a.V, a.beta])

	# Hovering in a wind equal to the ground velocity: zero airspeed must be finite, not NaN.
	a = Air.compute(_state([15, 0, 0]), M.v3(15, 0, 0))
	_check("zero airspeed is finite", a.V == 0.0 and a.alpha == 0.0 and a.beta == 0.0 and a.qbar == 0.0, str(a))
	a = Air.compute(_state([0, 0, 1e-9]), calm)
	_check("tiny airspeed stays finite", is_finite(a.alpha) and is_finite(a.beta) and is_finite(a.qbar))

	# Falling flat (C6 throw at 1.5 s): u = 15, w = 14.71 → alpha ≈ 44.4°, the flat-fall the captures showed.
	a = Air.compute(_state([15, 0, 14.709975]), calm)
	_check("flat fall alpha ≈ 44.4°", absf(rad_to_deg(a.alpha) - 44.44) < 0.01, str(rad_to_deg(a.alpha)))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
