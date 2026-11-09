# EX-14j: the Extra's existing wing/body estimate survives the oracle/local transition.
# These are model-consistency checks, not independent flight identification.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO := 1.225
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
var failures := 0
var checks := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _loads(model: Dictionary, alpha: float, beta: float, local: bool) -> PackedFloat64Array:
	var state := RB.make_state(M.v3(0, 0, -100),
		M.v3(25.0 * cos(alpha) * cos(beta), 25.0 * sin(beta), 25.0 * sin(alpha) * cos(beta)),
		M.q_identity(), M.v3(0, 0, 0))
	var air := Air.compute(state, M.v3(0, 0, 0), RHO)
	return Aero._local_loads(state, air, ZERO, model, RHO) if local else Aero._global_loads(state, air, ZERO, model, RHO)


func _clb(model: Dictionary, alpha: float, local: bool) -> float:
	var beta := deg_to_rad(1.0)
	return (_loads(model, alpha, beta, local)[3] - _loads(model, alpha, -beta, local)[3]) / (
		2.0 * beta * 0.5 * RHO * 25.0 * 25.0 * float(model.reference.S) * float(model.reference.b))


func _initialize() -> void:
	var path := "res://data/aircraft/gp_extra_300s_60.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			path = arg.substr(7)
	var loaded := AD.load_file(path)
	_check("Extra data loads", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var model: Dictionary = loaded.model
	_check("Extra declares positive wing/body Clbeta", float(model.surfaces.get("wing_body_cl_beta", 0.0)) > 0.0)
	var old_local: Dictionary = model.duplicate(true)
	old_local.surfaces.erase("wing_body_cl_beta")
	for degrees in [0.0, 8.0, 12.0, 20.0]:
		var alpha := deg_to_rad(degrees)
		var oracle := _clb(model, alpha, false)
		var gap_before := absf(_clb(old_local, alpha, true) - oracle)
		var gap_after := absf(_clb(model, alpha, true) - oracle)
		# The attached oracle is a consistency target near the blend, not a post-stall reference.
		if degrees <= 12.0:
			_check("alpha %.0f: local/oracle Clbeta gap reduced by at least 80 percent" % degrees,
				gap_before > 0.003 and gap_after < 0.2 * gap_before)
		var beta := deg_to_rad(1.0)
		_check("alpha %.0f: oracle loads preserved" % degrees,
			_loads(model, alpha, beta, false) == _loads(old_local, alpha, beta, false))
		var before := _loads(old_local, alpha, beta, true)
		var after := _loads(model, alpha, beta, true)
		var other_axes_equal := true
		for axis in [0, 1, 2, 4, 5]:
			other_axes_equal = other_axes_equal and before[axis] == after[axis]
		_check("alpha %.0f: local force, pitch and yaw preserved" % degrees, other_axes_equal)
		_check("alpha %.0f: positive sideslip adds positive local roll" % degrees, after[3] > before[3])
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
