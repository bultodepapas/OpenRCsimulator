extends SceneTree

const FIELD = preload("res://data/field_loader.gd")
const WIND = preload("res://physics/wind_config.gd")
const ROOT = "C:/DEVELOPMENT/OpenRCsimulator/tmp/audit-rotor-diagnostics-20261108-capture01"

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()

func _run() -> void:
	var baseline: bool = "--baseline" in OS.get_cmdline_user_args()
	var script: GDScript
	if baseline:
		script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(ROOT.path_join("baseline_session.gd"))
		if script.reload() != OK:
			print("WITNESS baseline script reload failed")
			quit(1)
			return
	else:
		script = load("res://sim/helicopter_flight_session.gd")
	var session: Node = script.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	var weather: Dictionary = WIND.defaults()
	weather.speed_mps = 15.0
	weather.from_deg = 0.0
	weather.gust_mps = 8.0
	weather.gust_duration_s = 12.0
	weather.gust_period_s = 120.0
	weather.gust_delay_s = 0.0
	var prepared: bool = session.setup() and session.set_field(FIELD.load_from().field) and session.setup_weather(weather) and session.set_start_choice("ground") and session.reset()
	if not prepared:
		print("WITNESS setup failed ", session.start_error, " ", session.weather_error)
		session.free()
		quit(1)
		return
	var checkpoints: Array = [var_to_bytes(session.checkpoint()).hex_encode().sha256_text()]
	var armed: bool = session.toggle_motor_arm() and session.set_drive_hold(false)
	var hashes: Array = []
	var inputs: Array = []
	var before_fault: Dictionary = {}
	for i: int in 1000:
		var before := {tick=session.sim.tick, body=session.sim.state.duplicate(), continuous=session.sim.continuous.duplicate(), phase=session.shaft_phase.duplicate(), aux=session.sim.aux.duplicate()}
		session.sim.step()
		if not session.is_flyable():
			before_fault = before
			break
		inputs.append(session.sim.inputs.duplicate())
		hashes.append(var_to_bytes([session.sim.state, session.sim.continuous, session.sim.aux, session.sim.inputs, session.shaft_phase, session.sim.last_loads]).hex_encode().sha256_text())
		if session.sim.tick == 360 or session.sim.tick == 740:
			checkpoints.append(var_to_bytes(session.checkpoint()).hex_encode().sha256_text())
	var rolled_back: bool = not before_fault.is_empty() and session.sim.tick == before_fault.tick and session.sim.state.to_byte_array() == before_fault.body.to_byte_array() and session.sim.continuous.to_byte_array() == before_fault.continuous.to_byte_array() and session.shaft_phase.to_byte_array() == before_fault.phase.to_byte_array() and session.sim.aux.to_byte_array() == before_fault.aux.to_byte_array()
	var output: Dictionary = {ok=armed and rolled_back and not session.sim.fault_reason.is_empty(), baseline=baseline, tick=session.sim.tick, omega=session.sim.continuous[0], reason=session.pause_reason, fault=session.sim.fault_reason, rolled_back=rolled_back, checkpoints=checkpoints, hashes=hashes, inputs_sha256=var_to_bytes(inputs).hex_encode().sha256_text(), engine=Engine.get_version_info().string, session_sha256=FileAccess.get_sha256(ROOT.path_join("baseline_session.gd") if baseline else "res://sim/helicopter_flight_session.gd"), flight_sha256=FileAccess.get_sha256("res://physics/rotorcraft/flight_dynamics.gd")}
	var file: FileAccess = FileAccess.open(ROOT.path_join("baseline-confirmed.json" if baseline else "candidate-confirmed.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t", true, true))
	file.close()
	print("WITNESS baseline=",baseline," tick=",session.sim.tick," rollback=",rolled_back," reason=",session.pause_reason)
	session.free()
	quit(0 if output.ok else 1)
