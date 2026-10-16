extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const Log = preload("res://sim/flight_log.gd")
const Maneuvers = preload("res://sim/maneuvers.gd")

func _initialize() -> void:
	var destination := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			destination = argument.trim_prefix("--out=")
	if destination.is_empty():
		quit(2)
		return
	for spec in [[240, 3.0, 1.0], [480, 3.0, 1.0], [240, 12.0, 1.0], [240, 12.0, -1.0]]:
		if not _record(destination, int(spec[0]), float(spec[1]), float(spec[2])):
			quit(1)
			return
	quit(0)

func _record(destination: String, hz: int, duration: float, direction: float) -> bool:
	Engine.physics_ticks_per_second = hz
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup()
	flight.reset()
	root.add_child(flight)
	flight.set_physics_process(false)
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet
	var trim: Dictionary = flight.trim_at(maneuver.speed, maneuver.mode)
	if not trim.ok:
		printerr("trim failed: ", trim)
		flight.free()
		return false
	flight.reset()
	var name := "rudder-%dhz-%ds-%s.orfl" % [hz, int(duration), "right" if direction > 0.0 else "left"]
	var logger := Log.new(flight)
	if logger.start(destination.path_join(name)) != OK:
		printerr("log start failed: ", name)
		flight.free()
		return false
	for tick in roundi(duration / flight.sim.dt()):
		var t: float = flight.sim.time()
		var sticks: Dictionary = maneuver.sticks.call(t, flight.sim.state)
		flight.commands = {roll = sticks.roll, pitch = sticks.pitch, yaw = direction * sticks.yaw,
			throttle = clampf(flight.start.throttle + sticks.throttle_delta, 0.0, 1.0)}
		flight.sim.inputs = flight._inputs()
		if tick == roundi(0.5 * hz): logger.mark("first rudder pulse")
		if tick == roundi(1.0 * hz): logger.mark("rudder reversal")
		if tick == roundi(1.5 * hz): logger.mark("neutral recovery")
		flight.sim.step()
	var success: bool = logger.stop() == OK and flight.sim.tick == roundi(duration * hz)
	print(name, " ticks=", flight.sim.tick, " r_deg_s=", rad_to_deg(flight.sim.state[12]), " complete=", success)
	flight.free()
	return success
