# H13 / VAL-AUD-R02: frozen geometry plus independently projected section-flow reference.
# Full 3D legacy drag is intentionally obsolete; zero loads and unchanged wake retain exact comparisons.
extends SceneTree
const M := preload("res://physics/math3d.gd")
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
	for id in Catalog.airplane_flyable_ids(): # TT-06: previews carry no data file
		var flight := Flight.new()
		flight.setup(Catalog.entry(id).data)
		root.add_child(flight)
		var model: Dictionary = flight.aircraft.model.duplicate(true)
		if model.propulsion.get("slipstream", {}).is_empty():
			flight.free()
			continue
		# E0a2c/D11j: the frozen H13 oracle predates the P-51's free tail law and the strips' section pitching moment;
		# the scalar form is compared on the same legacy law (test_aero_flow.gd does the same for its oracle).
		for key in ["downwash_gradient", "free_slope", "elevator_tau", "downwash_per_cl", "free_incidence", "wing_cl0"]:
			model.surfaces.horizontal.erase(key)
		model.surfaces.erase("wing_cm_ac")
		# P51-26: the oracle is the legacy centroid swirl; the opt-in segmented law has its own test_slipstream_sidewash.gd.
		model.propulsion.slipstream.erase("propeller_sidewash")
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
			var expected: PackedFloat64Array = _projected_reference(state, air, d, model, rpm, Air.RHO_SEA_LEVEL)
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
			if not _close_loads(actual, expected):
				failures += 1
				if failures <= 5:
					printerr("FAIL ", id, " sample ", sample, ": ", actual, " != ", expected)
		flight.free()
	# Exercise the comparator actually used above, at its declared reduction tolerance.
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var moved := one.duplicate()
	moved[2] += 1e-9
	checks += 1
	if _close_loads(moved, one):
		failures += 1
		printerr("FAIL projected-load comparator accepted an above-tolerance change")
	if aircraft == 0 or washed < 5000 or static_air < 1000 or stopped < 300:
		failures += 1
		printerr("FAIL coverage: %d aircraft, %d washed, %d static, %d stopped" % [aircraft, washed, static_air, stopped])
	print("H13/R02 slipstream: %d projected-load comparisons (%d aircraft, %d washed, %d static air, %d stopped), %d failed"
		% [checks, aircraft, washed, static_air, stopped, failures])
	quit(1 if failures else 0)


## The old section oracle is evaluated with the velocity projected geometrically
## before pressure is formed. Wake and immersion retain their frozen reference.
func _projected_reference(state: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rpm: float, rho: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	if rpm < Propulsion.STOPPED_RPM:
		return out
	var prop: Dictionary = model.propulsion
	var tq := Propulsion.thrust_torque(air.v_air, rpm, prop, rho)
	var wake := Reference.wake(air.v_air, tq[0], tq[1], prop, rho)
	var axis := Propulsion.axis(prop)
	var wash := M.scale(axis, wake.dv)
	var rates := state.slice(RB.RATE, RB.RATE+3)
	for piece in prop.slipstream.pieces:
		var im := Reference.immersion(piece, wake, prop.slipstream.hub, prop, air.v_air, air.V, model, axis)
		if im.area <= 0.0:
			continue
		var tail: Dictionary = model.surfaces[piece.surface]
		var arm := M.add(Reference._arm(tail.position, model.cg_le), im.shift)
		var rate_flow := M.cross(rates, arm)
		var free_flow := M.add(air.v_air, rate_flow)
		var washed_flow := M.add(M.add(air.v_air, M.sub(wash, im.swirl)), rate_flow)
		var vertical: bool = piece.surface == "vertical"
		free_flow[2 if vertical else 1] = 0.0
		washed_flow[2 if vertical else 1] = 0.0
		var free := Reference._tail_surface_from_flow(free_flow, arm, d, tail, model.surfaces, im.area, vertical, rho)
		var washed := Reference._tail_surface_from_flow(washed_flow, arm, d, tail, model.surfaces, im.area, vertical, rho)
		for i in 6:
			out[i] += washed[i]-free[i]
	return out


func _close_loads(actual: PackedFloat64Array, expected: PackedFloat64Array) -> bool:
	for i in 6:
		if not is_finite(actual[i]) or absf(actual[i]-expected[i]) > 1e-11*(1.0+absf(expected[i])):
			return false
	return true
