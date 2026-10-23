extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Fields := preload("res://data/field_loader.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var flight := Flight.new()
	flight.setup(Catalog.entry("turbo-lumber-evolution").data, "turbo-lumber-evolution")
	if not flight.is_flyable():
		printerr("aircraft setup failed: ", flight.start_error, " ", flight.pause_reason); quit(2); return
	var loaded := Fields.load_from()
	if not loaded.get("ok", false) or not flight.set_field(loaded.field):
		printerr("field setup failed: ", loaded.get("errors", []), " ", flight.surface_error); quit(3); return
	flight.start_choice = Flight.START_RUNWAY
	flight.reset()
	if not flight.runway_start_outcome.get("ok", false):
		printerr("runway setup failed: ", flight.runway_start_outcome); quit(4); return
	# Replace terrain with a level smooth pad at the validated minimum rolling factor.
	flight.ground_surfaces = PackedFloat64Array([-INF, INF, -INF, INF, 0.7, 0.5])
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	state[3] = 2.0
	flight.sim.reset(state)
	flight.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	flight.sim.inputs = flight._inputs()
	flight.sim.set_paused(false)
	var log := Log.new(flight)
	var log_path := "C:/DEVELOPMENT/OpenRCsimulator/tmp/physics-ground-audit-20261023/agent/timber-smooth-pad-baseline.orfl"
	if log.start(log_path) != OK:
		printerr("recorder start failed: ", log.failure); quit(5); return
	for i in 600:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			printerr("simulation fault at tick ", i, ": ", flight.sim.fault_reason); log.stop("probe fault"); quit(6); return
	if log.stop("smooth-pad constant-throttle taxi probe") != OK:
		printerr("recorder stop failed: ", log.failure); quit(7); return
	print("BASELINE path=", log_path, " rows=", log.rows_written, " seconds=", log.seconds(), " ground_factor=0.5 ground_field=", flight.ground_field_id, " final_u=", flight.sim.state[3], " wheel_aux=", flight.sim.aux.slice(4, flight.sim.aux.size()))
	flight.free(); quit(0)
