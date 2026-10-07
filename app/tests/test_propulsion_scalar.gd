# H14: the scalar tilted-shaft propulsion loads must equal the frozen vector oracle byte for byte.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Reference := preload("res://tests/propulsion_reference.gd")

const CASES_PER_AIRCRAFT := 5000


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51414
	var checks := 0
	var failures := 0
	var tilted := 0
	var tilted_crossflow := 0
	var still_air := 0
	var stopped := 0
	for id in Catalog.ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var prop: Dictionary = flight.aircraft.model.propulsion
		var start_rpm: float = flight.start.rpm
		var has_axis := prop.has("axis")
		for sample in CASES_PER_AIRCRAFT:
			var v := PackedFloat64Array([rng.randf_range(-10.0, 45.0), rng.randf_range(-15.0, 15.0),
				rng.randf_range(-25.0, 25.0)])
			var rpm := rng.randf_range(0.0, 1.3) * start_rpm
			if sample % 7 == 0: # static run-up: no crossflow terms
				v = PackedFloat64Array([0.0, 0.0, 0.0])
				still_air += 1
			if sample % 11 == 0:
				rpm = rng.randf_range(0.0, 2.0) # either side of STOPPED_RPM (1 rpm)
			if rpm < Propulsion.STOPPED_RPM:
				stopped += 1
			var rho := Air.RHO_SEA_LEVEL * rng.randf_range(0.8, 1.05)
			var expected: PackedFloat64Array = Reference.loads(v, rpm, prop, rho)
			var actual: PackedFloat64Array = Propulsion.loads(v, rpm, prop, rho)
			checks += 1
			if has_axis and rpm >= Propulsion.STOPPED_RPM:
				tilted += 1
				if v[1] != 0.0 or v[2] != 0.0:
					tilted_crossflow += 1
			if actual.to_byte_array() != expected.to_byte_array():
				failures += 1
				if failures <= 5:
					printerr("FAIL ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	# The comparison is not vacuous: a one-ulp change in a single component must be rejected.
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var moved := one.duplicate()
	moved[5] = 6.000000000000001
	checks += 1
	if moved.to_byte_array() == one.to_byte_array():
		failures += 1
		printerr("FAIL comparator accepted a one-ulp change")
	if tilted_crossflow < 3000 or still_air < 2000 or stopped < 600:
		failures += 1
		printerr("FAIL coverage: %d tilted (%d with crossflow), %d still air, %d stopped"
			% [tilted, tilted_crossflow, still_air, stopped])
	print("H14 propulsion: %d byte-exact comparisons (%d tilted-shaft, %d with crossflow, %d still air, %d stopped), %d failed"
		% [checks, tilted, tilted_crossflow, still_air, stopped, failures])
	quit(1 if failures else 0)
