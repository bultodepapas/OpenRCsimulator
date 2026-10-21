# EX-14h: the Extra 300S's post-stall wing polar (aero.wing_polar, the D8b-R2d post-stall v2 method fitted to NASA FASER's
# measured lift retention and stall-onset roll damping by research/extra-300/ex14/fit_wing_polar.gd). Checks that the
# data declare the fitted table with full spanwise progression and carry the fitter's rows exactly; that the
# whole-aircraft roll damping stays stable through 16-18 deg, where the legacy blend it replaces is unstable (+0.5..+1.0,
# the violent stall wing drop), and that lift is retained after the stall. Static loads at 25 m/s, controls neutral, the
# bench's definitions (post_stall_sweep.gd). This verifies the data chain and its mechanism; it does not validate the Extra.
# Run: godot --headless --path . --script res://tests/test_extra_post_stall.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const EXTRA := "res://data/aircraft/gp_extra_300s_60.json"
const FIT := "res://../research/extra-300/ex14/wing_polar_fit.json"
const SPEED := 25.0
const RHO := 1.225
const NEUTRAL := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + "  " + detail)
	if not ok:
		_failures += 1


func _loads(model: Dictionary, alpha_deg: float, p: float) -> PackedFloat64Array:
	var a := deg_to_rad(alpha_deg)
	var s := RB.make_state(M.v3(0, 0, -300), M.v3(SPEED * cos(a), 0, SPEED * sin(a)), M.q_identity(), M.v3(p, 0, 0))
	return Aero.loads(s, Air.compute(s, M.v3(0, 0, 0)), NEUTRAL, model, RHO)


## Whole-aircraft CL and Clp (dMx/dp at p = 0, central difference) at one angle of attack.
func _cl_clp(model: Dictionary, alpha_deg: float) -> PackedFloat64Array:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var a := deg_to_rad(alpha_deg)
	var f := _loads(model, alpha_deg, 0.0)
	var cl: float = (f[0] * sin(a) - f[2] * cos(a)) / (0.5 * RHO * SPEED * SPEED * S)
	var d: float = (_loads(model, alpha_deg, 1e-5)[3] - _loads(model, alpha_deg, -1e-5)[3]) / 2e-5
	return PackedFloat64Array([cl, d * 2.0 / (0.5 * RHO * SPEED * S * b * b)])


func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXTRA))
	var loaded: Dictionary = AD.validate_and_derive(raw.duplicate(true))
	_check("Extra loads with its wing polar", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var polar: Dictionary = raw.aero.get("wing_polar", {})
	_check("Extra declares tabulated-wing-v1 with full spanwise progression",
		polar.get("method") == "tabulated-wing-v1" and float(polar.get("spanwise_progression", {}).get("value", 0.0)) == 1.0)
	var fit: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(FIT)))
	_check("declared rows are the fitter's (research/extra-300/ex14/wing_polar_fit.json)", fit is Dictionary
		and str(polar.get("positive", {}).get("value")) == str(fit.positive) and str(polar.get("negative", {}).get("value")) == str(fit.negative))

	var legacy_raw: Dictionary = raw.duplicate(true)
	legacy_raw.aero.erase("wing_polar")
	var legacy: Dictionary = AD.validate_and_derive(legacy_raw)
	var peak := 0.0
	for k in range(16, 37):
		peak = maxf(peak, _cl_clp(loaded.model, k * 0.5)[0])
	for alpha_deg in [16.0, 17.0, 18.0]:
		var now := _cl_clp(loaded.model, alpha_deg)
		var before := _cl_clp(legacy.model, alpha_deg)
		_check("roll damping stable at %.0f deg (legacy blend unstable there)" % alpha_deg, now[1] < 0.0 and before[1] > 0.3,
			"Clp %+.3f, legacy %+.3f" % [now[1], before[1]])
	var at20 := _cl_clp(loaded.model, 20.0)
	var legacy_peak := 0.0
	for k in range(16, 37):
		legacy_peak = maxf(legacy_peak, _cl_clp(legacy.model, k * 0.5)[0])
	var legacy20 := _cl_clp(legacy.model, 20.0)
	_check("lift retained after the stall: CL(20 deg) >= 0.85 CLmax (legacy collapses)", at20[0] >= 0.85 * peak
		and legacy20[0] < 0.75 * legacy_peak, "%.3f of %.3f; legacy %.3f of %.3f" % [at20[0], peak, legacy20[0], legacy_peak])
	_finish()


func _finish() -> void:
	print("EX-14h Extra post-stall polar: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
