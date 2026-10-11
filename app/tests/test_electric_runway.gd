# EL2a-E1: parked electric runway state, source startup and complete boundary replay.
extends SceneTree
const Flight: Script = preload("res://sim/flight_session.gd")
const Field: Script = preload("res://data/field_loader.gd")
const GroundStart: Script = preload("res://physics/ground_start.gd")
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func flight(path: String, field: Dictionary) -> Node:
	var a: Node = Flight.new()
	a.setup(path)
	root.add_child(a)
	a.input_enabled = false
	check("field accepted", a.set_field(field))
	return a

func advance(a: Node, count: int) -> bool:
	for tick: int in count:
		if a.sim.paused or not a.sim.fault_reason.is_empty() or not a.crash.is_empty():
			return false
		var before: int = a.sim.tick
		a.sim.step()
		a._physics_process(a.sim.dt())
		if a.sim.tick != before + 1 or not a.sim.fault_reason.is_empty() or not a.crash.is_empty():
			print("advance refused: ", a.sim.fault_reason, " ", a.crash)
			return false
	return true

func runway_case(pack_name: String, dynamic: bool, field: Dictionary, eastbound: bool) -> void:
	var path: String = "res://data/aircraft/synthetic_stik_electric_%s%s.json" % [pack_name, "_battery" if dynamic else ""]
	var a: Node = flight(path, field)
	var spot: Dictionary = GroundStart.threshold(field, eastbound)
	var initial_choice: String = a.start_choice
	var initial_start: PackedByteArray = var_to_bytes(a.start)
	var label: String = "%s battery=%s east=%s" % [pack_name, dynamic, eastbound]
	var ready: bool = a.reset_on_runway(spot.north, spot.east, spot.heading)
	check(label + " runway succeeds", ready)
	if not ready:
		a.free()
		return
	check(label + " one-shot helper preserves selected start/trim", a.start_choice == initial_choice and var_to_bytes(a.start) == initial_start)
	check(label + " source enabled with zero duty and exact rest", a.engine_running and a.sim.inputs[3] == 0.0 and a.sim.aux[0] == 0.0 and a.sim.continuous[0] == 0.0)
	check(label + " ground pose has three compressed wheels", a.gear_compressions(a.sim.state).size() == 3 and a.gear_compressions(a.sim.state)[0] > 0.0 and a.gear_compressions(a.sim.state)[1] > 0.0 and a.gear_compressions(a.sim.state)[2] > 0.0)
	check(label + " launch metadata describes stopped electric source", "electric" in a.trace_meta().scenario and "zero duty" in a.trace_meta().scenario)
	var pose: PackedFloat64Array = a.sim.state.duplicate()
	var q0: float = a.sim.continuous[1] if dynamic else 0.0
	check(label + " parked second advances", advance(a, 240))
	var drift: float = 0.0
	for i: int in 13:
		drift = maxf(drift, absf(a.sim.state[i] - pose[i]))
	check(label + " holds the parked pose and rotor", drift < 1e-8 and a.sim.aux[0] == 0.0)
	var point: Dictionary = a.electrical_state()
	check(label + " no motor current or torque at rest", point.ok and point.motor_current_a == 0.0 and point.shaft_torque_nm == 0.0)
	if dynamic:
		var pack: Dictionary = a.aircraft.model.propulsion.battery
		var duration: float = 240.0 * a.sim.dt()
		var expected_q: float = q0 - pack.auxiliary_current_a * duration
		var expected_heat: float = pack.resistance_ohm * pack.auxiliary_current_a * pack.auxiliary_current_a * duration
		var knots: PackedFloat64Array = pack.ocv_points
		var chemical: float = knots[1] * (q0 - expected_q) + (knots[3] - knots[1]) / (7200.0 * pack.capacity_ah) * (q0*q0 - expected_q*expected_q)
		check(label + " parked auxiliary charge matches analytic budget", absf(point.remaining_charge_c - expected_q) < 3e-9)
		check(label + " parked heat/energy match analytic budget", absf(point.pack_heat_j-expected_heat) < 1e-12 and absf(point.terminal_energy_j-(chemical-expected_heat)) < 1e-7)
	var parked_energy: float = a.sim.continuous[2] if dynamic else 0.0
	var parked_charge: float = a.sim.continuous[1] if dynamic else 0.0
	var saved: Dictionary = a.checkpoint()
	var b: Node = flight(path, field)
	check(label + " parked checkpoint restores fresh owner", not saved.is_empty() and b.restore_checkpoint(bytes_to_var(var_to_bytes(saved))))
	b.sim.set_paused(false) # Deliberate recorded-input continuation, no live input sampling.
	a.sim.inputs[3] = 0.7
	b.sim.inputs[3] = 0.7
	check(label + " both sources start from physical rest", advance(a, 24) and advance(b, 24) and a.sim.aux[0] > 100.0)
	check(label + " startup replay is byte exact", var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
	point = a.electrical_state()
	check(label + " powered startup draws motor current", point.ok and point.motor_current_a > 0.0)
	if dynamic:
		check(label + " powered startup consumes pack charge and energy", point.pack_current_a > a.aircraft.model.propulsion.battery.auxiliary_current_a and point.remaining_charge_c < parked_charge and point.terminal_energy_j > parked_energy)
	check(label + " repeat runway resets source to rest", a.reset_on_runway(spot.north, spot.east, spot.heading) and a.sim.tick == 0 and a.sim.continuous[0] == 0.0)
	if dynamic:
		check(label + " runway restart refills and clears ledgers", a.sim.continuous[1] == q0 and a.sim.continuous[2] == 0.0 and a.sim.continuous[3] == 0.0)
		var pack: Dictionary = a.aircraft.model.propulsion.battery
		a.sim.continuous[1] = pack.auxiliary_current_a * a.sim.dt() * 0.37
		check(label + " near-empty parked seed accepted", a.sim.reset(a.sim.state))
		check(label + " auxiliary exhaustion at rest completes", advance(a, 1) and a.electrical_state().exhausted and a.sim.continuous[0] == 0.0)
		var energy: float = a.sim.continuous[2]
		var heat: float = a.sim.continuous[3]
		a.sim.inputs[3] = 1.0
		check(label + " empty source cannot restart or consume energy", advance(a, 24) and a.sim.continuous[0] == 0.0 and a.sim.aux[0] == 0.0 and a.sim.continuous[1] == 0.0 and a.sim.continuous[2] == energy and a.sim.continuous[3] == heat and a.electrical_state().motor_current_a == 0.0 and a.electrical_state().pack_current_a == 0.0)
		check(label + " new runway flight refills exhausted pack", a.reset_on_runway(spot.north, spot.east, spot.heading) and a.sim.continuous[1] == q0 and a.sim.continuous[2] == 0.0)
		a.sim.inputs[3] = 0.7
		check(label + " replenished source can start", advance(a, 24) and a.sim.continuous[0] > 100.0)
	a.reset()
	check(label + " normal restart still returns to airborne trim", a.sim.tick == 0 and a.sim.state[2] < -10.0 and a.sim.continuous[0] > 100.0 and a.trace_meta().launch_choice == "airborne")
	var airborne: PackedByteArray = var_to_bytes([a.sim.state, a.sim.aux, a.sim.inputs, a.sim.continuous, a.sim.modes])
	check(label + " invalid runway pose refuses and restores trimmed flight", not a.reset_on_runway(NAN, spot.east, spot.heading) and a.sim.tick == 0 and var_to_bytes([a.sim.state, a.sim.aux, a.sim.inputs, a.sim.continuous, a.sim.modes]) == airborne and a.trace_meta().launch_choice == "airborne" and a.sim.fault_reason.is_empty() and a.start_choice == initial_choice and var_to_bytes(a.start) == initial_start)
	if dynamic:
		check(label + " refused runway restores full battery and zero ledgers", a.sim.continuous[1] == q0 and a.sim.continuous[2] == 0.0 and a.sim.continuous[3] == 0.0)
	a.free()
	b.free()

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var loaded: Dictionary = Field.load_from()
	check("field loads", loaded.ok)
	if loaded.ok:
		for pack_name: String in ["4s", "6s"]:
			for dynamic: bool in [false, true]:
				for eastbound: bool in [true, false]:
					runway_case(pack_name, dynamic, loaded.field, eastbound)
	print("EL2a-E1 electric runway: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
