# D4: trim against the predicted-handling table, stability of the trimmed state, and visible failure.
# Run: godot --headless --path . --script res://tests/test_trim.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")

const G := 9.80665
const THROW := deg_to_rad(20.0)

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])
	if not ok:
		_failures += 1


## Fly the trimmed state with fixed controls (and fixed thrust) through the real integrator.
func _fly(model: Dictionary, t: Dictionary, seconds: float) -> PackedFloat64Array:
	var j_inv := RB.inertia_inverse(model.inertia)
	var d := { elevator = t.elevator, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0 }
	var thrust: float = t.thrust
	var f := func(s: PackedFloat64Array) -> PackedFloat64Array:
		var l := Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), d, model, Air.RHO_SEA_LEVEL)
		return RB.derivative(s, model.mass_kg, model.inertia, j_inv, M.v3(l[0] + thrust, l[1], l[2]), M.v3(l[3], l[4], l[5]), G)
	var s: PackedFloat64Array = t.state
	for i in roundi(seconds * 240.0):
		s = RK.rk4_step(s, 1.0 / 240.0, f)
	return s


func _initialize() -> void:
	var model: Dictionary = AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model

	# Level flight at 15 m/s: predicted alpha 3.6°, drag 2.93 N (ROADMAP predicted-handling table).
	var lv := Trim.solve("level", 15.0, model, G, THROW)
	_check("level 15 m/s trims", lv.ok, lv.message)
	_check("trim alpha 3.6° ± 0.5°", absf(rad_to_deg(lv.alpha) - 3.6) < 0.5, "%.2f°" % rad_to_deg(lv.alpha))
	_check("thrust ≈ drag ≈ 2.9 N", absf(lv.thrust - 2.93) < 0.3, "%.3f N" % lv.thrust)
	_check("needs some up elevator (borrowed Cm0 < 0)", lv.pitch_command > 0.0 and lv.pitch_command < 1.0, "pitch command %.3f (%.1f° TE up)" % [lv.pitch_command, -rad_to_deg(lv.elevator)])
	_check("converged tightly", lv.residual < 1e-10, "residual %s in %d iterations" % [String.num_scientific(lv.residual), lv.iterations])

	# The trimmed state holds when flown: 10 s, fixed controls and thrust.
	var end := _fly(model, lv, 10.0)
	var dz: float = end[RB.POS + 2] - lv.state[RB.POS + 2]
	var dv := sqrt(end[RB.VEL] ** 2 + end[RB.VEL + 1] ** 2 + end[RB.VEL + 2] ** 2) - 15.0
	_check("trimmed level flight holds 10 s (±0.05 m, ±0.01 m/s)", absf(dz) < 0.05 and absf(dv) < 0.01, "Δalt %.4f m, ΔV %.5f m/s" % [-dz, dv])

	# Power-off glide at 15 m/s: L/D ≈ 8.7 → glide angle ≈ −6.6°.
	var gl := Trim.solve("glide", 15.0, model, G, THROW)
	var ld := 1.0 / tan(-gl.gamma)
	_check("glide 15 m/s trims", gl.ok, gl.message)
	_check("glide ratio ≈ 8.7", absf(ld - 8.7) < 0.3, "L/D %.2f, glide angle %.2f°" % [ld, rad_to_deg(gl.gamma)])
	var gend := _fly(model, gl, 10.0)
	var sink: float = (gend[RB.POS + 2] - gl.state[RB.POS + 2]) / 10.0
	_check("trimmed glide holds: sink = V·sin(−γ)", absf(sink - 15.0 * sin(-gl.gamma)) < 0.01, "%.3f m/s" % sink)

	# Faster flight needs less alpha (predicted 1.5° at 20 m/s).
	var fast := Trim.solve("level", 20.0, model, G, THROW)
	_check("20 m/s: alpha ≈ 1.5°", fast.ok and absf(rad_to_deg(fast.alpha) - 1.5) < 0.5, "%.2f°" % rad_to_deg(fast.alpha))

	# Impossible requests fail with a reason, never a fake trim.
	var slow := Trim.solve("level", 5.0, model, G, THROW)
	_check("5 m/s is impossible and says why", not slow.ok and "elevator" in slow.message, slow.message)

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
