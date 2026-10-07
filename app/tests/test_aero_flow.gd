# H4: allocation removal must retain exact blend decisions, including live geometry edits.
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
	quit(1 if failures else 0)
