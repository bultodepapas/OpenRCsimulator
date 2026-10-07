# H4: allocation removal must retain exact blend decisions, including live geometry edits.
# H12: the scalar local loads must equal the frozen vector-form loads byte for byte.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Reference := preload("res://tests/aero_flow_reference.gd")
const RB := preload("res://physics/rigid_body.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44117
	for id in Catalog.ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		var state: PackedFloat64Array = flight.sim.state.duplicate()
		var d: Dictionary = flight._deflections(flight.sim.aux).duplicate()
		for sample in 2500:
			state[RB.VEL] = rng.randf_range(-40.0, 40.0)
			state[RB.VEL+1] = rng.randf_range(-8.0, 8.0)
			state[RB.VEL+2] = rng.randf_range(-12.0, 12.0)
			for axis in 3:
				state[RB.RATE+axis] = rng.randf_range(-5.0, 5.0)
			for control in d:
				d[control] = rng.randf_range(-0.6, 0.6)
			# Keep many samples attached, where every local station is inspected.
			if sample % 2 == 0:
				state[RB.VEL] = 30.0
				state[RB.VEL+1] *= 0.1
				state[RB.VEL+2] *= 0.1
				for control in d:
					d[control] *= 0.1
			if sample % 50 == 0:
				model.cg_le[0] += rng.randf_range(-0.01, 0.01)
				model.surfaces.horizontal.position[2] += rng.randf_range(-0.01, 0.01)
			var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
			var expected: float = Reference.local_flow_weight(state, air, d, model)
			var actual: float = Aero.local_flow_weight(state, air, d, model)
			checks += 1
			if PackedFloat64Array([actual]).to_byte_array() != PackedFloat64Array([expected]).to_byte_array():
				failures += 1
				printerr("FAIL ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	print("H4 local flow: %d byte-exact comparisons, %d failed" % [checks, failures])
	_check_local_loads()
	quit(1 if failures else 0)


func _check_local_loads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51212
	var load_checks := 0
	var load_failures := 0
	var stalled := 0
	var zero_flow := 0
	for id in Catalog.ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		# D11d couples the strips through an induced-flow map; without it the strip law is the frozen one, so the
		# refactored two-pass loop must still reproduce it byte for byte (test_strip_induced.gd covers the map).
		for key in ["induced_map", "strip_slope", "strip_cl0"]:
			model.envelope.erase(key)
		var state: PackedFloat64Array = flight.sim.state.duplicate()
		var d: Dictionary = flight._deflections(flight.sim.aux).duplicate()
		for sample in 2500:
			# Forward, stalled, sideslipping and reverse flow, with spin-like body rates.
			state[RB.VEL] = rng.randf_range(-40.0, 40.0)
			state[RB.VEL+1] = rng.randf_range(-15.0, 15.0)
			state[RB.VEL+2] = rng.randf_range(-25.0, 25.0)
			for axis in 3:
				state[RB.RATE+axis] = rng.randf_range(-6.0, 6.0)
			for control in d:
				d[control] = rng.randf_range(-0.6, 0.6)
			if sample % 5 == 0: # still air, no rotation: every surface takes the zero-flow branch
				for axis in 3:
					state[RB.VEL+axis] = 0.0
					state[RB.RATE+axis] = 0.0
				zero_flow += 1
			if sample % 50 == 0:
				model.cg_le[0] += rng.randf_range(-0.01, 0.01)
				model.cg_le[2] += rng.randf_range(-0.005, 0.005)
				model.surfaces.horizontal.position[2] += rng.randf_range(-0.01, 0.01)
				model.surfaces.vertical.position[0] += rng.randf_range(-0.01, 0.01)
			var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
			if absf(air.alpha) > model.envelope.a1:
				stalled += 1
			var expected: PackedFloat64Array = Reference.local_loads(state, air, d, model, Air.RHO_SEA_LEVEL)
			var actual: PackedFloat64Array = Aero._local_loads(state, air, d, model, Air.RHO_SEA_LEVEL)
			load_checks += 1
			if actual.to_byte_array() != expected.to_byte_array():
				load_failures += 1
				if load_failures <= 5:
					printerr("FAIL local loads ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	# The comparison is not vacuous: a one-ulp change in a single component must be rejected.
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var moved := one.duplicate()
	moved[4] = 5.000000000000001
	load_checks += 1
	if moved.to_byte_array() == one.to_byte_array():
		load_failures += 1
		printerr("FAIL comparator accepted a one-ulp change")
	if stalled < 1000 or zero_flow < 1000:
		load_failures += 1
		printerr("FAIL coverage: %d stalled, %d zero-flow samples" % [stalled, zero_flow])
	print("H12 local loads: %d byte-exact comparisons (%d stalled, %d zero-flow), %d failed"
		% [load_checks, stalled, zero_flow, load_failures])
	failures += load_failures
