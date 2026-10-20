# G2a: real P-51 smooth throttle transient must retain RK4 order and a bounded 240 Hz error.
# E0a2c: the P-51 now carries the tail's downwash lag, an auxiliary state advanced once per tick and held through the
# RK stages (E0a2b, like the split integrator's rpm). That hold limits the whole-session refinement of every state to
# second order, so the integrator's own fourth order is checked on the same data without the gradient (no lag state),
# and the production data is checked for its second-order convergence at a negligible absolute error.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const WheelProfiles = preload("res://physics/wheel_profiles.gd")
const PATH: String = "res://data/aircraft/p51d_mustang_120.json"
var failures: int = 0


func run_flight(rate: int, mode: String, lagged: bool) -> PackedFloat64Array:
	Engine.physics_ticks_per_second = rate
	var flight: Flight = Flight.new()
	flight.setup(PATH)
	if not lagged or mode == "split":
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if mode == "split":
			# The current v11 P-51 has finite fuel and requires coupled RK4; retain its older
			# prescribed-fuel compatibility path only for measuring the split integrator.
			raw.propulsion.erase("fuel_consumption")
			raw.capabilities.energy = "prescribed_fuel"
		if not lagged:
			raw.aero.surfaces.horizontal.erase("downwash_gradient")
			# The optional ground-effect closure requires the gradient-derived free-tail law.
			# Remove both only from this in-memory integrator fixture; production lag/ground effect stay enabled.
			raw.aero.erase("ground_effect")
		var candidate: Dictionary = AircraftData.validate_and_derive(raw)
		var profiled: Dictionary = WheelProfiles.apply_to_model(candidate.model) if candidate.get("ok", false) else {}
		if not candidate.get("ok", false) or not profiled.get("ok", false):
			failures += 1
			printerr("FAIL refinement flight could not prepare its in-memory model: ",
				candidate.get("errors", profiled.get("errors", [])))
			flight.free()
			return PackedFloat64Array()
		candidate.model = profiled.model
		candidate.wheel_profile_identity = profiled.identity
		if not flight._apply(candidate) or (not lagged and flight.downwash_index() != -1):
			failures += 1
			printerr("FAIL refinement flight could not apply its in-memory model")
			flight.free()
			return PackedFloat64Array()
	if not flight.setup_shaft_integrator(mode):
		failures += 1
		printerr("FAIL refinement flight refused shaft mode ", mode, ": ", flight.shaft_error)
		flight.free()
		return PackedFloat64Array()
	flight.reset()
	flight.input_enabled = false
	flight.sim.inputs[3] += 0.03
	for tick: int in rate / 2:
		flight.sim.step()
	if flight.sim.tick != rate / 2 or not flight.sim.fault_reason.is_empty():
		failures += 1
		printerr("FAIL refinement flight stopped: ", flight.sim.fault_reason)
	var out: PackedFloat64Array = flight.sim.state.duplicate()
	out.append(flight.sim.aux[0])
	flight.free()
	return out


func _initialize() -> void:
	var old_rate: int = Engine.physics_ticks_per_second
	var cases := [
		{ mode = "coupled-rk4", lagged = false, lo = 13.0, hi = 20.0, floor = 1e-7, label = "coupled-rk4 without the downwash lag (integrator order)" },
		{ mode = "coupled-rk4", lagged = true, lo = 3.0, hi = 6.0, floor = 1e-5, label = "coupled-rk4 with the held downwash lag (second order, bounded)" },
		{ mode = "split", lagged = true, lo = 1.8, hi = 2.5, floor = 10.0, label = "split" },
	]
	for c in cases:
		var coarse: PackedFloat64Array = run_flight(60, c.mode, c.lagged)
		var middle: PackedFloat64Array = run_flight(120, c.mode, c.lagged)
		var fine: PackedFloat64Array = run_flight(240, c.mode, c.lagged)
		var reference: PackedFloat64Array = run_flight(1920, c.mode, c.lagged)
		if coarse.is_empty() or middle.is_empty() or fine.is_empty() or reference.is_empty():
			continue # Refused candidates already fail; never measure convergence on the retained model.
		var errors: Array[float] = []
		for state: PackedFloat64Array in [coarse, middle, fine]:
			errors.append(absf(state[-1] - reference[-1]))
		var ratios: Array[float] = [errors[0] / errors[1], errors[1] / errors[2]]
		var good: bool = ratios[0] > c.lo and ratios[0] < c.hi and ratios[1] > c.lo and ratios[1] < c.hi and errors[2] < c.floor
		print(("ok " if good else "FAIL ") + c.label + " smooth full-session RPM refinement: errors %s rpm, ratios %s" % [errors, ratios])
		if not good:
			failures += 1
	Engine.physics_ticks_per_second = old_rate
	print("G2 refinement: %d checks, %d failed" % [cases.size(), failures])
	quit(1 if failures else 0)
