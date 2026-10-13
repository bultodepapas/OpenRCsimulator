## Stage-local reuse must preserve the independently evaluated aircraft loads exactly.
extends SceneTree
const Aircraft := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 131026
	for name: String in ["55ax_2t", "fs64v_4t", "55ax_2t_apc_13x6", "fs64v_4t_apc_13x6"]:
		var aircraft: Dictionary = Aircraft.load_file("res://data/aircraft/stik_glow_" + name + ".json")
		if not aircraft.ok:
			failures += 1
			continue
		var model: Dictionary = aircraft.model
		var prop: Dictionary = model.propulsion
		for sample in 250:
			var body := PackedFloat64Array([0., 0., -100., rng.randf_range(-20., 50.), rng.randf_range(-8., 8.),
				rng.randf_range(-8., 8.), 1., 0., 0., 0., .1, -.2, .3])
			var rpm: float = rng.randf_range(1., prop.glow.profile.operation.max_rpm)
			if sample % 11 == 0: rpm = 0.
			var rho: float = rng.randf_range(.8, 1.3)
			var air: Dictionary = Air.compute(body, PackedFloat64Array([0., 0., 0.]), rho)
			var point: Dictionary = Blade.evaluate(rpm, M.dot(air.v_air, prop.axis), rho, prop.glow.propeller)
			var reused: PackedFloat64Array = Propulsion.loads_from_thrust_torque(air.v_air, rpm, prop, rho, point.thrust_n, point.torque_nm)
			var separate: PackedFloat64Array = Propulsion.loads(air.v_air, rpm, prop, rho)
			_check(reused.to_byte_array() == separate.to_byte_array(), name + " propeller stage " + str(sample))
			var d := {aileron_left = .01, aileron_right = -.01, elevator = .03, rudder = -.02}
			var reference: PackedFloat64Array = Dynamics.loads_from_air(body, model, d, rpm, rho, air)
			var combined: PackedFloat64Array = Dynamics.loads_from_air(body, model, d, rpm, rho, air, NAN, PackedFloat64Array(), NAN, reused)
			_check(combined.to_byte_array() == reference.to_byte_array(), name + " total stage " + str(sample))
	print("Glow stage reuse: %d byte-exact comparisons, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 5: printerr("FAIL ", label)
