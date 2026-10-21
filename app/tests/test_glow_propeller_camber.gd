# EX-14f: the Glow propeller surrogate's optional cambered-section zero-lift angle (zero_lift_angle_rad).
# Checks: absent and 0 are byte-identical; invalid values are refused; a cambered section lifts the zero-thrust advance
# ratio above the geometric pitch ratio and absorbs more static power (measured APC Sport props: zero thrust near
# 1.4x the pitch ratio); the runtime equals the independent Python mirror (research/glow-engines/calibration_report.py
# annular_prop_performance); the actuator-disk power bound still holds. Software verification only.
# Run: godot --headless --path . --script res://tests/test_glow_propeller_camber.gd
extends SceneTree

const GlowProp := preload("res://physics/glow/propeller.gd")

const BASE := {diameter_m = 0.3048, pitch_m = 0.1524, chord_m = 0.0165, blades = 2.0, lift_slope = 5.5, cd0 = 0.022,
	induced_drag = 0.06}
# [rpm, axial m/s, thrust N, torque N·m] from annular_prop_performance with zero_lift_angle_rad -0.1, the same geometry.
const PYTHON_MIRROR := [
	[11000.0, 0.0, 39.2038431906915, 0.8234191575087326],
	[12000.0, 20.0, 34.87712221490864, 1.0313416628929637],
	[14000.0, 35.0, 28.865857776699844, 1.025786583824755],
	[9000.0, 30.0, 3.9159279384916488, 0.19818732057781052],
]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _with(zero_lift: Variant) -> Dictionary:
	var p := BASE.duplicate()
	if zero_lift != null:
		p.zero_lift_angle_rad = zero_lift
	return p


## Advance ratio of zero thrust at 12,000 rpm, by bisection on the axial speed.
func _zero_thrust_j(p: Dictionary) -> float:
	var n := 12000.0 / 60.0
	var lo := 0.0
	var hi := 2.0 * n * float(p.diameter_m)
	for _i in 60:
		var mid := 0.5 * (lo + hi)
		var r: Dictionary = GlowProp.evaluate(12000.0, mid, 1.225, p)
		if r.get("ok", false) and float(r.thrust_n) > 0.0:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi) / (n * float(p.diameter_m))


func _initialize() -> void:
	# Absent and an explicit 0 give the same bytes over a grid of rpm and axial speed (incl. windmilling and reverse).
	var identical := true
	for rpm in [0.0, 2000.0, 9000.0, 16000.0]:
		for v in [-5.0, 0.0, 12.0, 30.0, 55.0]:
			var a: Dictionary = GlowProp.evaluate(rpm, v, 1.225, _with(null))
			var b: Dictionary = GlowProp.evaluate(rpm, v, 1.225, _with(0.0))
			identical = identical and str(a) == str(b)
	_check("absent and zero_lift_angle_rad 0 are byte-identical (symmetric section unchanged)", identical)
	for bad in [0.01, -0.31, NAN, "x"]:
		var prepared: Dictionary = GlowProp.prepare_evaluator(_with(bad))
		_check("refuses zero_lift_angle_rad %s" % str(bad), not prepared.get("ok", false), str(prepared.get("message", "")))

	# Camber moves zero thrust past the geometric pitch ratio (0.5 for a 12x6) and loads the static disc more.
	var j_flat := _zero_thrust_j(_with(null))
	var j_cambered := _zero_thrust_j(_with(-0.1))
	_check("symmetric section: zero thrust at the geometric pitch ratio", absf(j_flat - 0.5) < 0.02, "J0 %.3f" % j_flat)
	_check("cambered section (-0.1 rad): zero thrust well past it", j_cambered > 0.65, "J0 %.3f" % j_cambered)
	var s_flat: Dictionary = GlowProp.evaluate(11000.0, 0.0, 1.225, _with(null))
	var s_cambered: Dictionary = GlowProp.evaluate(11000.0, 0.0, 1.225, _with(-0.1))
	_check("cambered section absorbs more static power at the same rpm", float(s_cambered.torque_nm) > float(s_flat.torque_nm),
		"%.4f vs %.4f N·m" % [float(s_cambered.torque_nm), float(s_flat.torque_nm)])

	# The runtime and the independent Python mirror agree.
	var worst := 0.0
	for row in PYTHON_MIRROR:
		var r: Dictionary = GlowProp.evaluate(float(row[0]), float(row[1]), 1.225, _with(-0.1))
		worst = maxf(worst, maxf(absf(float(r.thrust_n) / float(row[2]) - 1.0), absf(float(r.torque_nm) / float(row[3]) - 1.0)))
	_check("runtime equals the Python mirror at 4 operating points", worst < 1e-12, "max relative error %s" % String.num_scientific(worst))

	# The actuator-disk lower bound (a powered disc cannot beat ideal momentum work) still holds everywhere it applies.
	var bounded := true
	var cases := 0
	for rpm in [3000.0, 8000.0, 12000.0, 16000.0, 20000.0]:
		for v in [0.0, 5.0, 15.0, 25.0, 35.0, 45.0]:
			var r: Dictionary = GlowProp.evaluate(rpm, v, 1.225, _with(-0.105))
			bounded = bounded and r.get("ok", false)
			cases += 1
	_check("cambered evaluations pass the actuator-disk power bound over %d points" % cases, bounded)
	print("EX-14f propeller camber: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
