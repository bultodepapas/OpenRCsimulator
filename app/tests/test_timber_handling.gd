# TT-09: fly the estimated Timber through the same FlightSession callbacks and coupled electric step used by the app.
# These are software-consistency and broad-plausibility checks; the estimate is not physical validation.
# Run: godot --headless --path . --script res://tests/test_timber_handling.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Recorder := preload("res://sim/recorder.gd")
const Trace := preload("res://sim/trace.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")

const ID := "turbo-lumber-evolution"
const G := 9.80665

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var entry: Dictionary = Catalog.entry(ID)
	var session := FlightSession.new()
	session.setup(entry.data, ID)
	root.add_child(session)
	var loaded: bool = session.aircraft.get("ok", false) and session.start.get("ok", false)
	_check("Timber FlightSession loads and trims its own data", loaded,
		"%s; %s" % [session.start.get("V", "?"), session.start.get("message", "")])
	if not loaded:
		print("%d checks, %d failed" % [_checks, _failures + 1])
		quit(1)
		return

	var model: Dictionary = session.aircraft.model
	var prop: Dictionary = model.propulsion
	var v0: float = float(model.start_speed)
	_check("Timber uses its 2.190 kg, 1.555 m experimental model", model.id == ID
		and absf(float(model.mass_kg) - 2.190) < 0.001 and absf(float(model.reference.b) - 1.555) < 1e-9,
		"%s / %.3f kg / %.3f m" % [model.id, model.mass_kg, model.reference.b])
	_check("electric motor shaft is integrated with the coupled RK4 law", session.shaft_is_coupled()
		and session.trace_meta().propulsion_model == FlightSession.ELECTRIC_LAW)
	_check("in-air start is level, flaps-up and at the data start speed", session.start.mode == "level"
		and absf(float(session.start.V) - v0) < 1e-9 and session.start.state.size() >= 13)

	# A full-throttle static equilibrium is a useful ceiling check for the 70 A ESC rating. This is model output,
	# not a measured-current claim and does not validate the borrowed two-blade propeller map.
	var static_point: Dictionary = Propulsion.steady_operating_point(1.0, 0.0, prop, 1.225)
	var static_source: Dictionary = Propulsion.electric_source_state(float(static_point.get("rpm", NAN)), 1.0, prop)
	var static_current: float = float(static_source.get("motor_current_a", NAN))
	_check("full-throttle static current stays below the stated 70 A controller rating",
		static_point.get("ok", false) and static_source.get("ok", false) and is_finite(static_current)
		and static_current > 0.0 and static_current < 70.0,
		"%.2f A at %.0f rpm" % [static_current, static_point.get("rpm", NAN)])

	var hands_off: Callable = func(_t: float, _state: PackedFloat64Array) -> Dictionary:
		return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = 0.0 }
	var hold: RefCounted = _fly(session, "level", v0, 30.0, hands_off)
	var hold_last: int = hold.row_count() - 1
	var hold_altitude: float = hold.value(hold_last, "alt_m") - hold.value(0, "alt_m") if hold_last >= 0 else NAN
	var hold_speed: float = hold.value(hold_last, "speed_mps") - v0 if hold_last >= 0 else NAN
	_check("30 s hands-off trace is complete, continuous and finite", _finite(hold)
		and hold_last == roundi(30.0 / session.sim.dt()), "%d rows" % hold.row_count())
	_check("30 s trimmed level flight stays within 2 m and 0.3 m/s", absf(hold_altitude) < 2.0
		and absf(hold_speed) < 0.3, "Δalt %.3f m, Δspeed %.4f m/s" % [hold_altitude, hold_speed])

	# A full command step must raise the RPM and current in the same session whose controls fly the model.
	var full_power: RefCounted = _fly(session, "level", v0, 3.0, func(t: float, _state: PackedFloat64Array) -> Dictionary:
		return { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = 1.0 if t >= 0.0 else 0.0 })
	var start_rpm: float = full_power.value(0, "engine_rpm")
	var full_rpm: float = _max(full_power, "engine_rpm")
	var full_current: float = _max(full_power, "motor_current_a")
	_check("3 s throttle-up produces finite RPM/current response", _finite(full_power)
		and full_rpm > start_rpm + 500.0 and is_finite(full_current) and full_current > 0.0,
		"RPM %.0f→%.0f, peak current %.2f A" % [start_rpm, full_rpm, full_current])

	# Stop the source in flight, let the coupled rotor reach the stopped state, then re-enable at full command.
	session.input_enabled = false
	session.engine_running = false
	session.commands = { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0 }
	_step(session, roundi(5.5 / session.sim.dt()))
	var stopped_rpm: float = session.sim.aux[FlightSession.AUX_RPM]
	var stopped_electrical: Dictionary = session.electrical_state()
	_check("source-off reaches the coupled motor stop with no motor current",
		stopped_rpm < 100.0 and stopped_electrical.get("ok", false)
		and float(stopped_electrical.get("motor_current_a", NAN)) == 0.0,
		"%.1f rpm, %.3f A" % [stopped_rpm, stopped_electrical.get("motor_current_a", NAN)])
	session.engine_running = true
	_step(session, roundi(3.0 / session.sim.dt()))
	var restarted_rpm: float = session.sim.aux[FlightSession.AUX_RPM]
	var restarted_electrical: Dictionary = session.electrical_state()
	_check("re-enabled full command spins the motor back up", restarted_rpm > 1000.0
		and restarted_electrical.get("ok", false) and float(restarted_electrical.get("motor_current_a", 0.0)) > 0.0,
		"%.1f rpm, %.2f A" % [restarted_rpm, restarted_electrical.get("motor_current_a", NAN)])

	var glide: RefCounted = _fly(session, "glide", v0, 6.0, hands_off)
	var glide_last: int = glide.row_count() - 1
	var glide_altitude: float = glide.value(glide_last, "alt_m") - glide.value(0, "alt_m") if glide_last >= 0 else NAN
	_check("flaps-up power-off trim glides down with the source disabled", _finite(glide)
		and session.start.mode == "glide" and not session.engine_running
		and absf(_max_abs(glide, "engine_rpm")) < 100.0 and glide_altitude < -0.25,
		"Δalt %.3f m, max RPM %.1f" % [glide_altitude, _max_abs(glide, "engine_rpm")])

	# Confirm that each pilot direction actually accelerates the corresponding rigid-body axis.
	# Input-route tests separately prove that physical keys/radio samples reach these same commands.
	for axis: int in 3:
		for direction: float in [-1.0, 1.0]:
			var pulse: Callable = func(_t: float, _state: PackedFloat64Array) -> Dictionary:
				var sticks := { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle_delta = 0.0 }
				sticks[["roll", "pitch", "yaw"][axis]] = direction * 0.35
				return sticks
			var response: RefCounted = _fly(session, "level", v0, 0.5, pulse)
			var rate: float = session.sim.state[RB.RATE + axis]
			_check("%s command %+.2f produces the intended body rotation" % [["roll", "pitch", "yaw"][axis], direction * 0.35],
				_finite(response) and is_finite(rate) and direction * rate > 0.01,
				"rate %+.6f rad/s" % rate)

	# The coupled shaft, wheel state and rigid body must replay from a serialized in-air checkpoint bit-for-bit.
	session.trim_at(v0, "level")
	session.reset()
	session.input_enabled = false
	for _tick in 50:
		session.sim.inputs = PackedFloat64Array([0.1, 0.0, 0.0, 0.6])
		session.sim.step()
	var checkpoint: Dictionary = session.checkpoint()
	for _tick in 80:
		session.sim.inputs[1] = -0.1
		session.sim.step()
	var expected: Dictionary = session.sim.checkpoint()
	session.reset()
	var restored: bool = session.restore_checkpoint(bytes_to_var(var_to_bytes(checkpoint)))
	for _tick in 80:
		session.sim.inputs[1] = -0.1
		session.sim.step()
	_check("checkpoint restores Timber and exactly replays the electric shaft and wheels", restored
		and not checkpoint.is_empty() and _matches_snapshot(session.sim, expected),
		"checkpoint %s; tick %d" % [checkpoint.get("format", "missing"), session.sim.tick])

	session.free()
	print("TT-09 Timber handling: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _fly(session: Node, mode: String, speed: float, duration: float, sticks: Callable) -> RefCounted:
	session.input_enabled = false
	var trim: Dictionary = session.trim_at(speed, mode)
	_check(mode + " trim succeeds", trim.get("ok", false), str(trim.get("message", "")))
	if not trim.get("ok", false):
		return Trace.new()
	session.set_start_altitude(100.0)
	session.reset()
	var recorder := Recorder.new(session.sim, session.electrical_state)
	recorder.start(session.trace_meta())
	var steps: int = roundi(duration / session.sim.dt())
	for _tick in steps:
		var command: Dictionary = sticks.call(session.sim.time(), session.sim.state)
		session.commands = { roll = command.roll, pitch = command.pitch, yaw = command.yaw,
			throttle = clampf(float(session.start.throttle) + float(command.throttle_delta), 0.0, 1.0) }
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			break
		session.sim.step()
	session._physics_process(0.0)
	recorder.detach()
	_check(mode + " trace completes without crash, pause or simulation fault",
		recorder.trace.row_count() == steps + 1 and _finite(recorder.trace)
		and session.crash.is_empty() and session.sim.fault_reason.is_empty() and not session.sim.paused,
		"%d/%d rows; %s" % [recorder.trace.row_count(), steps + 1, session.sim.fault_reason])
	return recorder.trace


func _step(session: Node, steps: int) -> void:
	for _tick in steps:
		session.sim.inputs = session._inputs()
		session._physics_process(session.sim.dt())
		if not session.crash.is_empty() or not session.sim.fault_reason.is_empty() or session.sim.paused:
			return
		session.sim.step()


func _finite(trace: RefCounted) -> bool:
	if trace.row_count() < 2 or not trace.is_continuous():
		return false
	for row in trace.row_count():
		for column in trace.columns():
			if not is_finite(trace.value(row, column)):
				return false
	return true


func _max(trace: RefCounted, column: String) -> float:
	var result := -INF
	for row in trace.row_count():
		result = maxf(result, trace.value(row, column))
	return result


func _max_abs(trace: RefCounted, column: String) -> float:
	var result := 0.0
	for row in trace.row_count():
		result = maxf(result, absf(trace.value(row, column)))
	return result


func _matches_snapshot(sim: Node, expected: Dictionary) -> bool:
	if expected.is_empty():
		return false
	for key in ["state", "previous", "aux", "continuous", "inputs", "modes", "last_loads", "tick", "stop_at_tick"]:
		if var_to_bytes(sim.get(key)) != var_to_bytes(expected.get(key)):
			return false
	return true
