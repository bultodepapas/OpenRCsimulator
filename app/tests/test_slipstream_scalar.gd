# H13: the scalar slipstream loads must equal the frozen vector/dictionary oracle byte for byte.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Reference := preload("res://tests/slipstream_reference.gd")
const RB := preload("res://physics/rigid_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const CASES_PER_AIRCRAFT := 10000


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51313
	var checks := 0
	var failures := 0
	var aircraft := 0
	var washed := 0
	var static_air := 0
	var stopped := 0
	for id in Catalog.ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		if model.propulsion.get("slipstream", {}).is_empty():
			flight.free()
			continue
		aircraft += 1
		var state: PackedFloat64Array = flight.sim.state.duplicate()
		var d: Dictionary = flight._deflections(flight.sim.aux).duplicate()
		var start_rpm: float = flight.start.rpm
		for sample in CASES_PER_AIRCRAFT:
			# Mostly forward flight near the shaft line (pieces immersed), plus stalled, sideslipping and reverse flow.
			state[RB.VEL] = rng.randf_range(-10.0, 45.0)
			state[RB.VEL+1] = rng.randf_range(-6.0, 6.0) if sample % 3 else rng.randf_range(-20.0, 20.0)
			state[RB.VEL+2] = rng.randf_range(-4.0, 4.0) if sample % 3 else rng.randf_range(-25.0, 25.0)
			for axis in 3:
				state[RB.RATE+axis] = rng.randf_range(-4.0, 4.0)
			for control in d:
				d[control] = rng.randf_range(-0.6, 0.6)
			var rpm := rng.randf_range(0.0, 1.3) * start_rpm
			if sample % 7 == 0: # static run-up: no airspeed, so no free-stream drift
				for axis in 3:
					state[RB.VEL+axis] = 0.0
				static_air += 1
			if sample % 11 == 0:
				rpm = rng.randf_range(0.0, 2.0) # either side of Propulsion.STOPPED_RPM (1 rpm)
			if sample % 50 == 0:
				model.cg_le[0] += rng.randf_range(-0.01, 0.01)
				model.cg_le[2] += rng.randf_range(-0.005, 0.005)
				model.surfaces.horizontal.position[2] += rng.randf_range(-0.01, 0.01)
				model.surfaces.vertical.position[1] += rng.randf_range(-0.005, 0.005)
			var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
			var expected: PackedFloat64Array = Reference.loads(state, air, d, model, rpm, Air.RHO_SEA_LEVEL)
			var actual: PackedFloat64Array = Slipstream.loads(state, air, d, model, rpm, Air.RHO_SEA_LEVEL)
			checks += 1
			var zero := expected == PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			if rpm < Propulsion.STOPPED_RPM:
				stopped += 1
				if not zero:
					failures += 1
					printerr("FAIL stopped propeller washed the tail: ", expected)
			elif not zero:
				washed += 1
			if actual.to_byte_array() != expected.to_byte_array():
				failures += 1
				if failures <= 5:
					printerr("FAIL ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	# The comparison is not vacuous: a one-ulp change in a single component must be rejected.
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var moved := one.duplicate()
	moved[2] = 3.0000000000000004
	checks += 1
	if moved.to_byte_array() == one.to_byte_array():
		failures += 1
		printerr("FAIL comparator accepted a one-ulp change")
	if aircraft == 0 or washed < 5000 or static_air < 1000 or stopped < 300:
		failures += 1
		printerr("FAIL coverage: %d aircraft, %d washed, %d static, %d stopped" % [aircraft, washed, static_air, stopped])
	print("H13 slipstream: %d byte-exact comparisons (%d aircraft, %d washed, %d static air, %d stopped), %d failed"
		% [checks, aircraft, washed, static_air, stopped, failures])
	quit(1 if failures else 0)
