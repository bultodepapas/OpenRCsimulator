# M5-W01d: preserve calm v3 and record weather/state/k1-load timing explicitly in v4.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Recorder = preload("res://sim/recorder.gd")
const Trace = preload("res://sim/trace.gd")
const Config = preload("res://physics/wind_config.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var session: Session = Session.new()
	session.input_enabled = false
	session.setup()
	var recorder: Recorder = Recorder.new(session.sim)
	recorder.start(session.trace_meta())
	session.sim.step()
	check("calm CSV keeps v3 format", recorder.trace.to_csv().begins_with("# format: openrc-trace v3\n"))
	check("calm schema/columns unchanged", recorder.trace.meta.metadata_schema == "openrc-flight-meta v2" and recorder.trace.columns() == Trace.COLUMNS)
	recorder.recording = false
	session.reset()
	check("gust weather config accepted", session.setup_weather(Config.preset("gusty")))
	session.reset()
	var metadata: Dictionary = session.trace_meta()
	recorder.start(metadata)
	metadata.weather_config = "{}"
	check("recorder owns detached metadata", recorder.trace.meta.weather_config != metadata.weather_config)
	var base: PackedFloat64Array = session.start.state
	var calm_velocity_ned: PackedFloat64Array = M.q_rotate(M.quat(base[RB.ATT], base[RB.ATT + 1], base[RB.ATT + 2], base[RB.ATT + 3]), M.v3(base[RB.VEL], base[RB.VEL + 1], base[RB.VEL + 2]))
	var expected_ground_speed: float = M.sqrt_(calm_velocity_ned[0] * calm_velocity_ned[0] + (calm_velocity_ned[1] + 3.0) * (calm_velocity_ned[1] + 3.0))
	check("moving air trim records TAS/GS separately", absf(recorder.trace.value(0, "tas_mps") - session.start.V) < 1e-10 and absf(recorder.trace.value(0, "ground_horizontal_mps") - expected_ground_speed) < 1e-10)
	for _tick: int in 840:
		session.sim.step()
	var row: int = recorder.trace.row_count() - 1
	var tick: int = session.sim.tick
	var load_time: float = (tick - 1) * session.sim.dt()
	var wind: PackedFloat64Array = session.wind_at(session.sim.time())
	var load_wind: PackedFloat64Array = session.wind_at(load_time)
	check("weather trace is v4", recorder.trace.to_csv().begins_with("# format: openrc-trace v4\n"))
	check("v4 metadata schema follows weather", recorder.trace.meta.metadata_schema == "openrc-flight-meta v3")
	check("all tick rows remain continuous", recorder.trace.row_count() == 841 and recorder.trace.is_continuous())
	check("k1 time is previous tick", recorder.trace.value(row, "loads_t_s") == load_time)
	for axis: int in 3:
		check("state wind component %d" % axis, recorder.trace.value(row, ["wind_north_mps", "wind_east_mps", "wind_down_mps"][axis]) == wind[axis])
		check("k1 wind component %d" % axis, recorder.trace.value(row, ["loads_wind_north_mps", "loads_wind_east_mps", "loads_wind_down_mps"][axis]) == load_wind[axis])
	check("state TAS uses state time", recorder.trace.value(row, "tas_mps") == session.air_data(session.sim.state).V)
	check("k1 TAS uses previous state/previous time", recorder.trace.value(row, "loads_tas_mps") == session.air_data(session.sim.previous, load_time).V)
	check("gust state and load samples differ", wind != load_wind)
	recorder.recording = false
	# Mid-flight T starts from the observed preceding state, not an inferred first-row body velocity.
	recorder.start(session.trace_meta())
	check("first mid-flight row reconstructs k1 correctly", absf(recorder.trace.value(0, "loads_tas_mps") - session.air_data(session.sim.previous, load_time).V) < 1e-12)
	session.sim.step()
	check("mid-flight recording stays continuous", recorder.trace.row_count() == 2 and recorder.trace.is_continuous())
	var frozen: String = recorder.trace.to_csv()
	recorder.trace.meta.weather_config = "{}"
	check("v4 headers cannot change beneath recorded samples", recorder.trace.to_csv() == frozen)
	var header: String = ""
	for line: String in frozen.split("\n"):
		if line.is_empty() or line.begins_with("#"):
			continue
		if header.is_empty():
			header = line
		check("every row has explicit weather columns", line.split(",").size() == Trace.COLUMNS.size() + Trace.WEATHER_COLUMNS.size())
	recorder.detach()
	for defect: String in ["config", "previous", "time", "state", "quaternion"]:
		var trace: Trace = Trace.new()
		trace.meta = session.trace_meta()
		var state: PackedFloat64Array = session.sim.state.duplicate()
		var at: float = session.sim.time()
		if defect == "config":
			trace.meta.weather_config = "{}"
		elif defect == "previous":
			trace.meta.erase("recording_start_previous_state")
		elif defect == "time":
			at += session.sim.dt()
		elif defect == "state":
			state[RB.VEL] = INF
		elif defect == "quaternion":
			for axis: int in 4:
				state[RB.ATT + axis] = 0.0
		trace.record(session.sim.tick, at, state, session.sim.last_loads, session.sim.inputs, session.sim.aux)
		check("malformed wind recording refused: " + defect, trace.to_csv().is_empty() and trace.save("user://wind-invalid-never-written.csv") == ERR_INVALID_DATA)
	session.free()
	print("wind trace: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
