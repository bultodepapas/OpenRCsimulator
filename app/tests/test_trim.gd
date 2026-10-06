# D4/D5: six-axis trim against the predicted-handling table, flown on the real integrator, and visible failure.
# Run: godot --headless --path . --script res://tests/test_trim.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")

const G := 9.80665
var THROWS := { elevator = deg_to_rad(20.0), aileron = deg_to_rad(20.0), rudder = deg_to_rad(25.0) }

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


## Fly a trim result hands-off (fixed surfaces, engine at its trim rpm) through the real integrator.
func _fly(model: Dictionary, t: Dictionary, seconds: float) -> PackedFloat64Array:
	var j_inv := RB.inertia_inverse(model.inertia)
	var d := { elevator = t.elevator, aileron_right = t.aileron, aileron_left = -t.aileron, rudder = t.rudder }
	var rpm: float = t.rpm
	var f := func(s: PackedFloat64Array) -> PackedFloat64Array:
		var air := Air.compute(s, M.v3(0, 0, 0))
		var l := Aero.loads(s, air, d, model, Air.RHO_SEA_LEVEL)
		var p := Propulsion.loads(air.v_air, rpm, model.propulsion, Air.RHO_SEA_LEVEL)
		return RB.derivative(s, model.mass_kg, model.inertia, j_inv, M.v3(l[0] + p[0], l[1] + p[1], l[2] + p[2]), M.v3(l[3] + p[3], l[4] + p[4], l[5] + p[5]), G)
	var s: PackedFloat64Array = t.state
	for i in roundi(seconds * 240.0):
		s = RK.rk4_step(s, 1.0 / 240.0, f)
	return s


func _heading_deg(s: PackedFloat64Array) -> float:
	return rad_to_deg(M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))[0])


func _initialize() -> void:
	var model: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model

	# Linear solver: a known 6×6 system.
	var a := []
	var want := PackedFloat64Array([1, -2, 3, 0.5, -0.25, 4])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := PackedFloat64Array()
	for i in 6:
		var row := PackedFloat64Array()
		var acc := 0.0
		for k in 6:
			row.append(rng.randf_range(-1, 1) + (5.0 if i == k else 0.0))
			acc += row[k] * want[k]
		a.append(row)
		b.append(acc)
	var got := Trim.solve_linear(a, b)
	var err := 0.0
	for k in 6:
		err = maxf(err, absf(got[k] - want[k]))
	_check("Gaussian elimination solves a known system", err < 1e-12, String.num_scientific(err))

	# Reference build rebalanced in D1-R1 (2.885 kg); revised regression targets, not measurements.
	# Level flight at 15 m/s with the engine: predicted alpha 4.26°, thrust ≈ drag ≈ 3 N.
	var lv := Trim.solve("level", 15.0, model, G, THROWS)
	_check("level 15 m/s trims (six axes, with throttle)", lv.ok, lv.message)
	_check("trim alpha 4.26° ± 0.5°", absf(rad_to_deg(lv.alpha) - 4.26) < 0.5, "%.2f°" % rad_to_deg(lv.alpha))
	_check("thrust ≈ drag ≈ 3 N", absf(lv.thrust - 3.0) < 0.3, "%.3f N at throttle %.3f (%.0f rpm)" % [lv.thrust, lv.throttle, lv.rpm])
	_check("up elevator trim (borrowed Cm0 < 0)", lv.pitch_command > 0.0 and lv.pitch_command < 1.0, "pitch trim %.3f" % lv.pitch_command)
	_check("prop torque trimmed out with small aileron/rudder", absf(lv.roll_command) > 1e-4 and absf(lv.roll_command) < 0.2 and absf(lv.yaw_command) < 0.3, "roll trim %.4f, yaw trim %.4f, beta %.3f°" % [lv.roll_command, lv.yaw_command, rad_to_deg(lv.beta)])
	_check("converged tightly", lv.residual < 1e-10, "residual %s in %d iterations" % [String.num_scientific(lv.residual), lv.iterations])

	# ROADMAP D5 proof: hands-off trimmed level flight holds ±1 m for 30 s, and does not spiral away.
	var end := _fly(model, lv, 30.0)
	var dz: float = end[RB.POS + 2] - lv.state[RB.POS + 2]
	var dpsi := _heading_deg(end) - _heading_deg(lv.state)
	_check("level flight holds ±1 m for 30 s", absf(dz) < 1.0, "Δalt %.4f m" % -dz)
	_check("no spiral: heading holds within 1° for 30 s", absf(dpsi) < 1.0, "Δheading %.4f°" % dpsi)

	# Faster: less alpha, more throttle.
	var fast := Trim.solve("level", 25.0, model, G, THROWS)
	_check("25 m/s: less alpha, more throttle", fast.ok and fast.alpha < lv.alpha and fast.throttle > lv.throttle, "alpha %.2f°, throttle %.3f" % [rad_to_deg(fast.alpha), fast.throttle])

	# Engine-stopped glide: L/D ≈ 9.1, and nothing to trim laterally (no prop torque).
	var gl := Trim.solve("glide", 15.0, model, G, THROWS)
	var ld := 1.0 / tan(-gl.gamma)
	_check("glide 15 m/s trims", gl.ok, gl.message)
	_check("glide ratio ≈ 9.1", absf(ld - 9.11) < 0.3, "L/D %.2f, glide angle %.2f°" % [ld, rad_to_deg(gl.gamma)])
	_check("glide: no lateral trim needed", absf(gl.roll_command) < 1e-6 and absf(gl.yaw_command) < 1e-6 and absf(gl.beta) < 1e-6)

	# Impossible requests fail with a reason, never a fake trim.
	var slow := Trim.solve("level", 5.0, model, G, THROWS)
	_check("5 m/s is impossible and says why", not slow.ok and not slow.message.is_empty(), slow.message)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
