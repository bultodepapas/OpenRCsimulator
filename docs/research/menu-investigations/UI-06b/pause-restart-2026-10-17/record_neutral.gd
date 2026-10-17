extends SceneTree
const Flight = preload("res://sim/flight_session.gd")
const Log = preload("res://sim/flight_log.gd")
const Fields = preload("res://data/field_loader.gd")

func _initialize() -> void:
	var destination: String = OS.get_cmdline_user_args()[0]
	var flight = Flight.new()
	flight.setup()
	flight.set_field(Fields.load_from().field)
	flight.start_choice = Flight.START_RUNWAY
	flight.reset()
	flight.input_enabled = true
	flight.radio.disconnect_device()
	flight.read_raw = func() -> Dictionary: return {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
	var logger = Log.new(flight)
	if logger.start(destination) != OK:
		printerr(logger.failure)
		quit(1)
		return
	logger.mark("runway reset; no pilot input")
	for tick in 120:
		flight._physics_process(flight.sim.dt())
		flight.sim.step()
	logger.mark("120 neutral pilot ticks")
	print("RUNWAY cmd=",flight.commands.throttle," sampled=",flight.sim.inputs[3]," tick=",flight.sim.tick)
	var result = logger.stop()
	logger = null
	flight.free()
	quit(0 if result == OK else 1)
