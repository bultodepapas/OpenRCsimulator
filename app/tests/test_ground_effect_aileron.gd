## A36 R5-G01: near the ground the attached/global aerodynamic path must apply ground effect to differential aileron
## loading as the local strips do. Stock Ugly Stik at 15 m/s, CG 0.4 m above flat ground: +/-2 deg ailerons used to give
## -0.56054504 N·m on the public path but -0.63844911 N·m on the strips (a 13.9 % difference).
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const GE := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const RHO := 1.225

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _run() -> void:
	var info := AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	check("stock Stik admitted", info.ok, info.get("errors", []))
	if not info.ok:
		_finish()
		return
	var model: Dictionary = info.model
	for alpha_deg: float in [0.0, 3.0, 6.0]:
		var alpha := deg_to_rad(alpha_deg)
		var state := RB.make_state(M.v3(0.0, 0.0, -0.4), M.v3(15.0 * cos(alpha), 0.0, 15.0 * sin(alpha)), M.q_identity(),
			M.v3(0.0, 0.0, 0.0))
		var air := Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
		var factors := GE.factors(state, model, 0.0)
		var neutral := {elevator = 0.0, rudder = 0.0, aileron_right = 0.0, aileron_left = 0.0}
		var neutral_global := Aero._global_loads(state, air, neutral, model, RHO, NAN, factors)
		var neutral_local := Aero._local_loads(state, air, neutral, model, RHO, NAN, null, factors)
		for da_deg: float in [-2.0, 2.0]:
			var da := deg_to_rad(da_deg)
			var d := {elevator = 0.0, rudder = 0.0, aileron_right = da, aileron_left = -da}
			var global_free := Aero._global_loads(state, air, d, model, RHO)
			var global_ge := Aero._global_loads(state, air, d, model, RHO, NAN, factors)
			var local_free := Aero._local_loads(state, air, d, model, RHO)
			var local_ge := Aero._local_loads(state, air, d, model, RHO, NAN, null, factors)
			var label := "alpha %.0f aileron %+.0f" % [alpha_deg, da_deg]
			# Control increments relative to neutral isolate the aileron term from each path's own neutral roll. The global
			# path is the linear attached law; the strips keep their geometric nonlinearity (0.16 % apart at 6 deg).
			var global_increment: float = (global_ge[3] - neutral_global[3]) - global_free[3]
			var local_increment: float = (local_ge[3] - neutral_local[3]) - local_free[3]
			check(label + ": global ground-effect aileron increment matches the strips",
				absf(global_increment - local_increment) <= 5.0e-3 * absf(local_increment) and absf(local_increment) > 1.0e-3,
				"global %.12f local %.12f N m" % [global_increment, local_increment])
		if alpha_deg == 0.0:
			var d2 := {elevator = 0.0, rudder = 0.0, aileron_right = deg_to_rad(2.0), aileron_left = deg_to_rad(-2.0)}
			var public_ge := Aero.loads(state, air, d2, model, RHO, NAN, 0.0)
			check("R5 witness: public near-ground roll moment now follows the strips (-0.63844911 N m)",
				absf(public_ge[3] - (-0.63844911174621)) < 1.0e-9, "%.14f" % public_ge[3])
			var public_free := Aero.loads(state, air, d2, model, RHO)
			check("free-air roll moment is unchanged (-0.56054504 N m)", absf(public_free[3] - (-0.56054504117601)) < 1.0e-12,
				"%.14f" % public_free[3])
			var public_neutral := Aero.loads(state, air, neutral, model, RHO, NAN, 0.0)
			check("neutral ailerons still give zero roll near the ground", absf(public_neutral[3]) < 1.0e-12, public_neutral[3])
	_finish()


func _finish() -> void:
	print("ground effect aileron: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
