# Plan review #3 tool (kept outside app/ so test.sh never parses it): linearize the REAL sim equations at the 15 m/s level trim and print the
# 8x8 Jacobian over x = [u, v, w, p, q, r, phi, theta] (controls and rpm frozen at trim).
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const Spec := preload("res://spec.gd")

var model: Dictionary
var d: Dictionary
var rpm: float
var j_inv: PackedFloat64Array
var g := 9.80665


func f(x: PackedFloat64Array) -> PackedFloat64Array:
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(x[0], x[1], x[2]), M.q_from_euler(0.0, x[7], x[6]), M.v3(x[3], x[4], x[5]))
	var air := Air.compute(s, M.v3(0, 0, 0))
	var l := Aero.loads(s, air, d, model, Air.RHO_SEA_LEVEL)
	var pl := Propulsion.loads(air.v_air, rpm, model.propulsion, Air.RHO_SEA_LEVEL)
	for i in 6:
		l[i] += pl[i]
	var dot := RB.derivative(s, model.mass_kg, model.inertia, j_inv, M.v3(l[0], l[1], l[2]), M.v3(l[3], l[4], l[5]), g)
	var phi := x[6]
	var th := x[7]
	var p := x[3]
	var q := x[4]
	var r := x[5]
	return PackedFloat64Array([dot[RB.VEL], dot[RB.VEL + 1], dot[RB.VEL + 2], dot[RB.RATE], dot[RB.RATE + 1], dot[RB.RATE + 2],
		p + (q * sin(phi) + r * cos(phi)) * tan(th), q * cos(phi) - r * sin(phi)])


func _initialize() -> void:
	var V := float(OS.get_environment("V")) if OS.get_environment("V") != "" else 15.0
	model = AircraftData.load_file("res://data/aircraft/jensen_ugly_stik_60.json").model
	var c: Dictionary = Spec.CONTROLS.max_throw_deg
	var throws := { elevator = deg_to_rad(c.elevator), aileron = deg_to_rad(c.aileron), rudder = deg_to_rad(c.rudder) }
	var t := Trim.solve("level", V, model, g, throws)
	d = { elevator = t.elevator, aileron_right = t.aileron, aileron_left = -t.aileron, rudder = t.rudder }
	rpm = t.rpm
	j_inv = RB.inertia_inverse(model.inertia)
	var s0: PackedFloat64Array = t.state
	var e := M.q_to_euler(s0.slice(RB.ATT, RB.ATT + 4)) # [yaw, pitch, roll]
	var x0 := PackedFloat64Array([s0[3], s0[4], s0[5], 0.0, 0.0, 0.0, e[2], e[1]])
	print("# trim ok=%s V=%.1f alpha=%.3f deg throttle=%.3f" % [t.ok, V, rad_to_deg(t.alpha), t.throttle])
	for k in 8:
		var h := 1e-6
		var xp := x0.duplicate()
		var xm := x0.duplicate()
		xp[k] += h
		xm[k] -= h
		var fp := f(xp)
		var fm := f(xm)
		var col := []
		for i in 8:
			col.append(String.num_scientific((fp[i] - fm[i]) / (2.0 * h)))
		print("COL ", ",".join(col))
	quit()
