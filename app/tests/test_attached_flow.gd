# H15: scalar air data and global (attached-flow) loads must equal the frozen oracle byte for byte.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Reference := preload("res://tests/attached_flow_reference.gd")
const RB := preload("res://physics/rigid_body.gd")

const CASES_PER_AIRCRAFT := 2500


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51515
	var air_checks := 0
	var load_checks := 0
	var failures := 0
	var windy := 0
	var stalled := 0
	var no_envelope := 0
	for id in Catalog.ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		var bare: Dictionary = model.duplicate(true)
		bare.erase("envelope") # the linear-model branch (no stall envelope)
		var state: PackedFloat64Array = flight.sim.state.duplicate()
		var d: Dictionary = flight._deflections(flight.sim.aux).duplicate()
		for sample in CASES_PER_AIRCRAFT:
			var quat := PackedFloat64Array([rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)])
			var n := sqrt(quat[0] * quat[0] + quat[1] * quat[1] + quat[2] * quat[2] + quat[3] * quat[3])
			for k in 4:
				state[RB.ATT + k] = quat[k] / n
			state[RB.VEL] = rng.randf_range(-15.0, 45.0)
			state[RB.VEL+1] = rng.randf_range(-12.0, 12.0)
			state[RB.VEL+2] = rng.randf_range(-20.0, 20.0)
			for axis in 3:
				state[RB.RATE+axis] = rng.randf_range(-5.0, 5.0)
			for control in d:
				d[control] = rng.randf_range(-0.6, 0.6)
			var wind := PackedFloat64Array([0.0, 0.0, 0.0])
			if sample % 2 == 1:
				wind = PackedFloat64Array([rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0), rng.randf_range(-4.0, 4.0)])
				windy += 1
			if sample % 50 == 0:
				model.cg_le[0] += rng.randf_range(-0.01, 0.01)
				bare.cg_le[2] += rng.randf_range(-0.005, 0.005)
			var rho := Air.RHO_SEA_LEVEL * rng.randf_range(0.8, 1.05)
			var air: Dictionary = Air.compute(state, wind, rho)
			var air_ref: Dictionary = Reference.air_compute(state, wind, rho)
			air_checks += 1
			for key in ["V", "alpha", "beta", "qbar"]:
				if PackedFloat64Array([air[key]]).to_byte_array() != PackedFloat64Array([air_ref[key]]).to_byte_array():
					failures += 1
					if failures <= 5:
						printerr("FAIL air ", id, " sample ", sample, " ", key, ": ", air[key], " != ", air_ref[key])
			if air.v_air.to_byte_array() != air_ref.v_air.to_byte_array() or air.keys() != air_ref.keys():
				failures += 1
				if failures <= 5:
					printerr("FAIL air ", id, " sample ", sample, " v_air/keys")
			if absf(air.alpha) > model.envelope.a1:
				stalled += 1
			var use: Dictionary = bare if sample % 5 == 0 else model
			if use == bare:
				no_envelope += 1
			var expected: PackedFloat64Array = Reference.global_loads(state, air, d, use, rho)
			var actual: PackedFloat64Array = Aero._global_loads(state, air, d, use, rho)
			load_checks += 1
			if actual.to_byte_array() != expected.to_byte_array():
				failures += 1
				if failures <= 5:
					printerr("FAIL global loads ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	# The comparison is not vacuous: a one-ulp change in a single component must be rejected.
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var moved := one.duplicate()
	moved[3] = 4.000000000000001
	if moved.to_byte_array() == one.to_byte_array():
		failures += 1
		printerr("FAIL comparator accepted a one-ulp change")
	if windy < 4000 or stalled < 2000 or no_envelope < 1500:
		failures += 1
		printerr("FAIL coverage: %d windy, %d stalled, %d without envelope" % [windy, stalled, no_envelope])
	print("H15 attached flow: %d air-data and %d global-load byte-exact comparisons (%d windy, %d stalled, %d without envelope), %d failed"
		% [air_checks, load_checks, windy, stalled, no_envelope, failures])
	quit(1 if failures else 0)
