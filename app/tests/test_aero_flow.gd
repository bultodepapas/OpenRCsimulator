# H4: allocation removal must retain exact blend decisions, including live geometry edits.
# H12: the scalar local loads must equal the frozen vector-form loads byte for byte.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Reference := preload("res://tests/aero_flow_reference.gd")
const RB := preload("res://physics/rigid_body.gd")
const TIMBER := "turbo-lumber-evolution"
var checks := 0
var failures := 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44117
	for id in Catalog.flyable_ids(): # TT-06: previews carry no data file
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		for key in ["downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0"]:
			model.surfaces.horizontal.erase(key) # E0a2a: the frozen oracle predates the tail downwash split
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
	_check_wing_section_couple()
	quit(1 if failures else 0)


func _check_local_loads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51212
	var load_checks := 0
	var load_failures := 0
	var stalled := 0
	var zero_flow := 0
	for id in Catalog.flyable_ids(): # TT-06: previews carry no data file
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var authored_model: Dictionary = flight.aircraft.model.duplicate(true)
		var oracle_model: Dictionary = authored_model.duplicate(true)
		var actual_model: Dictionary = authored_model.duplicate(true)
		# D11d couples the strips through an induced-flow map; without it the strip law is the frozen one, so the
		# refactored two-pass loop must still reproduce it byte for byte (test_strip_induced.gd covers the map).
		# H12's frozen oracle predates D11j's optional wing-section Cm_ac couple. Keep that optional term neutral in
		# both the frozen and current model copies for this legacy byte-parity comparison; its enabled effect is checked
		# independently below against the analytic strip sum.
		for key in ["induced_map", "strip_slope", "strip_cl0"]:
			oracle_model.envelope.erase(key)
			actual_model.envelope.erase(key)
		for key in ["downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0"]:
			oracle_model.surfaces.horizontal.erase(key) # E0a2a: the frozen oracles predate the tail downwash split
			actual_model.surfaces.horizontal.erase(key)
		if oracle_model.surfaces.has("wing_cm_ac"):
			oracle_model.surfaces.wing_cm_ac = 0.0
		if actual_model.surfaces.has("wing_cm_ac"):
			actual_model.surfaces.wing_cm_ac = 0.0
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
				var cg_x_delta: float = rng.randf_range(-0.01, 0.01)
				var cg_z_delta: float = rng.randf_range(-0.005, 0.005)
				var horizontal_z_delta: float = rng.randf_range(-0.01, 0.01)
				var vertical_x_delta: float = rng.randf_range(-0.01, 0.01)
				for model: Dictionary in [oracle_model, actual_model]:
					model.cg_le[0] += cg_x_delta
					model.cg_le[2] += cg_z_delta
					model.surfaces.horizontal.position[2] += horizontal_z_delta
					model.surfaces.vertical.position[0] += vertical_x_delta
			var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
			if absf(air.alpha) > actual_model.envelope.a1:
				stalled += 1
			var expected: PackedFloat64Array = Reference.local_loads(state, air, d, oracle_model, Air.RHO_SEA_LEVEL)
			var actual: PackedFloat64Array = Aero._local_loads(state, air, d, actual_model, Air.RHO_SEA_LEVEL)
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


func _check_wing_section_couple() -> void:
	var flight := Flight.new()
	flight.setup(Catalog.entry(TIMBER).data, TIMBER)
	root.add_child(flight)
	if not flight.aircraft.get("ok", false):
		failures += 1
		printerr("FAIL wing-section couple: Timber data did not load")
		flight.free()
		return
	var model: Dictionary = flight.aircraft.model.duplicate(true)
	var cm_ac: float = float(model.surfaces.get("wing_cm_ac", NAN))
	if not is_finite(cm_ac) or cm_ac == 0.0:
		failures += 1
		printerr("FAIL wing-section couple: Timber has no enabled Cm_ac value")
		flight.free()
		return
	var no_couple: Dictionary = model.duplicate(true)
	no_couple.surfaces.wing_cm_ac = 0.0
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[RB.VEL] = 30.0
	state[RB.VEL + 1] = 0.0
	state[RB.VEL + 2] = 0.0
	for axis in 3:
		state[RB.RATE + axis] = 0.0
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	var deflections: Dictionary = flight._deflections(flight.sim.aux).duplicate()
	var enabled_loads: PackedFloat64Array = Aero._local_loads(state, air, deflections, model, Air.RHO_SEA_LEVEL)
	var neutral_loads: PackedFloat64Array = Aero._local_loads(state, air, deflections, no_couple, Air.RHO_SEA_LEVEL)
	var expected_moment := 0.0
	var station_count: int = model.envelope.station_ys.size()
	var station_area: float = model.reference.S / station_count
	for chord: float in model.envelope.station_chords:
		expected_moment += 0.5 * Air.RHO_SEA_LEVEL * 30.0 * 30.0 * station_area * chord * cm_ac
	var moment_increment: float = enabled_loads[4] - neutral_loads[4]
	var force_and_other_moments_same := true
	for index in [0, 1, 2, 3, 5]:
		force_and_other_moments_same = force_and_other_moments_same and enabled_loads[index] == neutral_loads[index]
	var tolerance: float = maxf(1e-10, absf(expected_moment) * 1e-12)
	checks += 2
	if not force_and_other_moments_same:
		failures += 1
		printerr("FAIL wing-section Cm_ac adds only pitching couple; non-pitch loads changed")
	if absf(moment_increment - expected_moment) > tolerance:
		failures += 1
		printerr("FAIL Timber wing-section Cm_ac analytic strip sum: ", moment_increment, " != ", expected_moment)
	print("D11j Timber section moment: ΔMy %.12f Nm, analytic %.12f Nm, Cm_ac %.6f" % [moment_increment, expected_moment, cm_ac])
	flight.free()
