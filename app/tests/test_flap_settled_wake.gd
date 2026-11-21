## A36 R6-G02: the quasi-static flap route (downwash NAN) must equal the explicitly settled flapped wake for the
## complete force and moment, tail drag and its pitch arm included. Before the contract the P-51 differed by 0.1539 N
## of drag and -0.0244 N·m of pitch at 20 m/s with 10 deg flap. Stock data; component and shared Dynamics loads.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
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


func _max_difference(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for i in a.size():
		worst = maxf(worst, absf(a[i] - b[i]) / maxf(1.0, absf(b[i])))
	return worst


func _case(name: String, model: Dictionary, speed: float, alpha_deg: float, flap_deg: float, ground: bool) -> void:
	var alpha := deg_to_rad(alpha_deg)
	var zero := M.v3(0.0, 0.0, 0.0)
	var state := RB.make_state(M.v3(0.0, 0.0, -0.25), M.v3(speed * cos(alpha), 0.0, speed * sin(alpha)), M.q_identity(), zero)
	var air := Air.compute(state, zero, RHO)
	var ground_up: float = 0.0 if ground else NAN
	var d := {elevator = 0.0, rudder = 0.0, aileron_left = 0.0, aileron_right = 0.0, flap = deg_to_rad(flap_deg)}
	var settled := Aero.wing_wake_velocity(state, air, d, model, ground_up)
	var static_loads := Aero.loads(state, air, d, model, RHO, NAN, ground_up)
	var held_loads := Aero.loads(state, air, d, model, RHO, settled, ground_up)
	var label := "%s %.0f m/s alpha %.0f flap %s%s" % [name, speed, alpha_deg, str(flap_deg), " ground" if ground else ""]
	check(label + ": static equals the explicitly settled wake", _max_difference(static_loads, held_loads) < 1.0e-12,
		[static_loads, held_loads])
	var static_total := Dynamics.loads(state, model, d, 0.0, RHO, zero, NAN, PackedFloat64Array(), ground_up)
	var held_total := Dynamics.loads(state, model, d, 0.0, RHO, zero, settled, PackedFloat64Array(), ground_up)
	check(label + ": shared Dynamics agrees", _max_difference(static_total, held_total) < 1.0e-12)


func _run() -> void:
	for name: String in ["f4u_corsair_250", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var info := AD.load_file("res://data/aircraft/%s.json" % name)
		check(name + " admitted", info.ok, info.get("errors", []))
		if not info.ok:
			continue
		var model: Dictionary = info.model
		for speed: float in [10.0, 20.0, 30.0]:
			_case(name, model, speed, 0.0, 10.0, false)
		_case(name, model, 20.0, 0.0, 0.0001, false)
		_case(name, model, 20.0, 6.0, 10.0, false)
		_case(name, model, 20.0, 30.0, 10.0, false)
		_case(name, model, 20.0, 0.0, 10.0, true)
		_case(name, model, 20.0, 3.0, float(model.flaps.max_angle_deg), false)
	print("flap settled wake: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
