# G2a: real P-51 smooth throttle transient must retain RK4 order and a bounded 240 Hz error.
extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const PATH: String = "res://data/aircraft/p51d_mustang_120.json"
var failures: int = 0


func run_flight(rate: int, mode: String) -> PackedFloat64Array:
	Engine.physics_ticks_per_second = rate
	var flight: Flight = Flight.new()
	flight.setup_shaft_integrator(mode)
	flight.setup(PATH)
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
	for mode: String in ["coupled-rk4", "split"]:
		var coarse: PackedFloat64Array = run_flight(60, mode)
		var middle: PackedFloat64Array = run_flight(120, mode)
		var fine: PackedFloat64Array = run_flight(240, mode)
		var reference: PackedFloat64Array = run_flight(1920, mode)
		var errors: Array[float] = []
		for state: PackedFloat64Array in [coarse, middle, fine]:
			errors.append(absf(state[-1] - reference[-1]))
		var ratios: Array[float] = [errors[0] / errors[1], errors[1] / errors[2]]
		var good: bool = ratios[0] > 13.0 and ratios[0] < 20.0 and ratios[1] > 13.0 and ratios[1] < 20.0 and errors[2] < 1e-7 \
			if mode == "coupled-rk4" else ratios[0] > 1.8 and ratios[0] < 2.5 and ratios[1] > 1.8 and ratios[1] < 2.5
		print(("ok " if good else "FAIL ") + mode + " smooth full-session RPM refinement: errors %s rpm, ratios %s" % [errors, ratios])
		if not good:
			failures += 1
	Engine.physics_ticks_per_second = old_rate
	print("G2 refinement: 2 checks, %d failed" % failures)
	quit(1 if failures else 0)
