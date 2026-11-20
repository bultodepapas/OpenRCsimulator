# Observation-only probe. Runs the shipped document from a stock field pad,
# then applies a bounded scripted throttle pulse and chop through Session.
# A negative endpoint current or an increasing accepted charge is reported
# separately from charge exceeding the initially full pack. No frame is edited.
# A negative result says nothing about all possible pilot tapes.
extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.get("ok", false):
		print("SETUP FAILURE field ", str(loaded.get("errors", [])))
		quit(1)
		return
	var failures := 0
	for throttle: float in [0.2, 0.5, 1.0]:
		for duration: int in [1, 4, 12, 36, 96]:
			if not _trial(loaded.field, throttle, duration):
				failures += 1
	print("Completed 15 bounded scripted pad trials; setup/refusal count: ", failures)
	print("These are session-level trajectories, not a controller/UI scene or exhaustive reachability proof.")
	quit(1 if failures else 0)


func _trial(field: Dictionary, throttle: float, duration: int) -> bool:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field, {start = "pad", initial_soc = 1.0}) or not s.resume():
		print("SETUP FAILURE ", s.load_error, " ", s.pause_reason)
		s.free()
		return false
	var capacity: float = 3600.0 * float(s.data.battery.capacity_ah)
	var stats := {throttle = throttle, pulse_ticks = duration, field = str(field.get("id", "")),
		data_sha256 = str(s.source_sha256), bus = str(s.sim.model.identity.get("bus", "")),
		initial_charge_c = s.sim.continuous[Plant.C_CHARGE], capacity_c = capacity,
		max_charge_c = s.sim.continuous[Plant.C_CHARGE], max_one_tick_charge_gain_c = 0.0,
		min_endpoint_current_a = 1.0e20, negative_current_samples = 0, positive_charge_ticks = 0,
		accepted_ticks = 0, stop = "completed"}
	var ok := _step(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), stats)
	ok = ok and _step(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), stats)
	if not ok or s.sim.modes[FC.MODE_MOTOR] != FC.MOTOR_ARMED:
		stats.stop = "arm failed: " + str(s.fault_reason) + " " + str(s.load_error)
		print("TRIAL ", JSON.stringify(stats))
		s.free()
		return false
	for phase: Array in [[throttle, duration], [0.0, 60]]:
		for _i: int in int(phase[1]):
			if not _step(s, Fixtures.pilot(0.0, 0.0, 0.0, float(phase[0]), 1), stats):
				stats.stop = "tick refused: " + str(s.fault_reason) + " " + str(s.load_error)
				ok = false
				break
			if s.sim.modes[FC.MODE_MOTOR] in [FC.MOTOR_CRASHED, FC.MOTOR_DEPLETED]:
				stats.stop = "terminal: " + str(s.crash)
				break
		if stats.stop != "completed":
			break
	stats.final_charge_c = s.sim.continuous[Plant.C_CHARGE]
	stats.charge_above_capacity = float(stats.max_charge_c) > capacity
	stats.final_consumed_mah = float(s.plant.telemetry(s.frame()).consumed_mah)
	print("TRIAL ", JSON.stringify(stats))
	s.free()
	return ok


func _step(s: Node, pilot: PackedFloat64Array, stats: Dictionary) -> bool:
	var before: float = s.sim.continuous[Plant.C_CHARGE]
	if not s.tick_once(pilot):
		return false
	var charge: float = s.sim.continuous[Plant.C_CHARGE]
	var current: float = float(s.plant.telemetry(s.frame()).pack_current_a)
	stats.accepted_ticks += 1
	stats.max_charge_c = maxf(float(stats.max_charge_c), charge)
	stats.max_one_tick_charge_gain_c = maxf(float(stats.max_one_tick_charge_gain_c), charge - before)
	stats.min_endpoint_current_a = minf(float(stats.min_endpoint_current_a), current)
	if current < 0.0:
		stats.negative_current_samples += 1
	if charge > before:
		stats.positive_charge_ticks += 1
	return true
