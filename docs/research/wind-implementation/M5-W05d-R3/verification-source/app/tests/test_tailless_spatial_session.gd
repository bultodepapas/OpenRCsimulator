## M5-W05d-R3 session, checkpoint, and ORFL self-replay coverage for the X8 ideal/pack variants.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const CheckpointJson := preload("res://sim/checkpoint_json.gd")
const Config := preload("res://physics/wind_config.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const X8_PATHS := [
	"res://data/aircraft/skywalker_x8.json",
	"res://data/aircraft/battery/skywalker_x8_6s_pack.json",
]
const RECORD_TICKS := 120 # 0.5 s at 240 Hz.
const CONTINUE_TICKS := 120 # The source, restored target, and self-replay each advance 0.5 s.

var checks := 0
var failures := 0
var legacy_mode := false
var output_dir := ""
var field := {}


func _initialize() -> void:
	_parse_arguments()
	_run.call_deferred()


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		var argument: String = args[i]
		if argument == "--legacy":
			legacy_mode = true
		elif argument.begins_with("--out-dir="):
			output_dir = argument.trim_prefix("--out-dir=")
		elif argument == "--out-dir" and i + 1 < args.size():
			output_dir = args[i + 1]
	if output_dir.begins_with("res://") or output_dir.begins_with("user://"):
		output_dir = ProjectSettings.globalize_path(output_dir)
	elif not output_dir.is_empty() and not output_dir.is_absolute_path():
		output_dir = ProjectSettings.globalize_path("res://../" + output_dir.trim_prefix("./"))
	if not output_dir.is_empty():
		output_dir = output_dir.simplify_path()
	else:
		output_dir = ProjectSettings.globalize_path("res://../tmp/tailless-spatial-%d" % Time.get_ticks_usec())


func _run() -> void:
	var mode_name: String = "legacy gentle" if legacy_mode else "opt-in spatial v5"
	var field_result: Dictionary = FieldLoader.load_from()
	check("default hand-launch field loads", field_result.get("ok", false), str(field_result.get("errors", [])))
	if not field_result.get("ok", false):
		_finish()
		return
	field = field_result.field
	var weather: Dictionary = _weather_config()
	var validated: Dictionary = Config.validate(weather)
	check(mode_name + " weather configuration validates", validated.get("ok", false),
		str(validated.get("errors", [])))
	if not validated.get("ok", false):
		_finish()
		return
	if not legacy_mode:
		check("spatial profile opts into v5 with mean, gust event, and turbulence",
			validated.config.get("format", "") == Config.SPATIAL_FORMAT
				and validated.config.spatial_wind.profile.reference_speed_mps > 0.0
				and validated.config.spatial_wind.gusts.events.size() == 1
				and validated.config.spatial_wind.turbulence.rms_mps > 0.0)
	for path_value: Variant in X8_PATHS:
		var path: String = path_value
		var route_weather := weather.duplicate(true)
		if not legacy_mode and path.contains("6s_pack"):
			route_weather.spatial_wind.profile.reference_from_deg = 270.0
			route_weather.spatial_wind.profile.free_air_wind_ned_mps = [0.0, 1.5, 0.0]
		for start_choice: String in [Flight.START_AIRBORNE, Flight.START_HAND_LAUNCH]:
			_run_route(path, start_choice, route_weather, mode_name)
	print("tailless spatial session (%s): %d checks, %d failures; ORFL directory %s" % [
		mode_name, checks, failures, output_dir])
	_finish()


func _finish() -> void:
	quit(1 if failures > 0 else 0)


func _weather_config() -> Dictionary:
	if legacy_mode:
		# --legacy uses the same route and control tape with the existing v2 gentle weather preset.
		return Config.GENTLE_PRACTICE.duplicate(true)
	var config: Dictionary = Config.spatial_defaults()
	config.spatial_wind.profile.reference_speed_mps = 1.5
	config.spatial_wind.profile.reference_from_deg = 90.0
	config.spatial_wind.profile.free_air_wind_ned_mps = [0.0, -1.5, 0.0]
	config.spatial_wind.gusts.events = [{
		"id": "x8-r3-session-gust",
		"start_s": 0.15,
		"duration_s": 0.8,
		"amplitude_ned_mps": [0.15, -0.25, 0.0],
	}]
	config.spatial_wind.turbulence.rms_mps = 0.03
	config.spatial_wind.turbulence.min_wavelength_m = 5.0
	config.spatial_wind.turbulence.max_wavelength_m = 30.0
	config.spatial_wind.turbulence.mode_count = 12
	config.spatial_wind.turbulence.coherence_time_s = 3.0
	return config


func _new_session(path: String, start_choice: String, weather: Dictionary) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.start_choice = start_choice
	session.setup(path)
	root.add_child(session)
	if not session.aircraft.get("ok", false):
		return session
	if start_choice == Flight.START_HAND_LAUNCH and not session.set_field(field):
		check(path.get_file().get_basename() + " installs the hand-launch field", false)
		return session
	if not session.setup_weather(weather.duplicate(true)):
		check(path.get_file().get_basename() + " installs " + _mode_label(), false, session.weather_error)
		return session
	session.reset()
	return session


func _run_route(path: String, start_choice: String, weather: Dictionary, mode_name: String) -> void:
	var variant_name: String = path.get_file().get_basename()
	var route_name: String = "airborne" if start_choice == Flight.START_AIRBORNE else "hand_launch"
	var label: String = "%s %s %s" % [variant_name, route_name, mode_name]
	var source: Node = _new_session(path, start_choice, weather)
	var target: Node = _new_session(path, start_choice, weather)
	var source_ready: bool = source.aircraft.get("ok", false) and source.is_flyable()
	var target_ready: bool = target.aircraft.get("ok", false) and target.is_flyable()
	check(label + " session setup and selected start succeed", source_ready and target_ready
		and source.start_error.is_empty() and target.start_error.is_empty()
		and source.sim.fault_reason.is_empty() and target.sim.fault_reason.is_empty(),
		"source=%s target=%s" % [source.start_error, target.start_error])
	if not source_ready or not target_ready:
		source.free()
		target.free()
		return
	_check_start_metadata(source, start_choice, label)
	_check_session_weather(source, label)
	if start_choice == Flight.START_HAND_LAUNCH and not legacy_mode:
		_check_release_flow(source, label)

	var log_path: String = output_dir.path_join("%s-%s-%s.orfl" % [variant_name, route_name,
		"legacy" if legacy_mode else "spatial-v5"])
	check(label + " ORFL output does not already exist", not FileAccess.file_exists(log_path), log_path)
	if FileAccess.file_exists(log_path):
		source.free()
		target.free()
		return
	var logger := FlightLog.new(source)
	var log_started: bool = logger.start(log_path) == OK
	check(label + " recorder starts at the accepted session boundary", log_started, logger.failure)
	if not log_started:
		source.free()
		target.free()
		return
	var record_advance_ok: bool = _advance(source, RECORD_TICKS, 0)
	var log_stopped: bool = logger.stop() == OK
	check(label + " advances 0.5 s with finite state and loads", record_advance_ok
		and source.sim.tick == RECORD_TICKS and source.sim.fault_reason.is_empty())
	check(label + " recording closes with a complete footer", log_stopped, logger.failure)
	if log_stopped:
		_check_orfl_self_replay(log_path, label)

	var checkpoint_payload: String = source.checkpoint_json()
	var decoded: Dictionary = CheckpointJson.decode(checkpoint_payload)
	check(label + " session checkpoint encodes", decoded.get("ok", false), str(decoded.get("errors", [])))
	if decoded.get("ok", false):
		_check_checkpoint_format(decoded.snapshot, label)
	var restored: bool = not checkpoint_payload.is_empty() and target.restore_checkpoint_json(checkpoint_payload)
	check(label + " fresh session restores the exact checkpoint", restored
		and target.checkpoint_json() == checkpoint_payload
		and var_to_bytes(source.sim.checkpoint()) == var_to_bytes(target.sim.checkpoint()))
	if restored:
		# Restore intentionally pauses; resume explicitly before exercising the product contact gate.
		target.sim.set_paused(false)
		var continuation_ok: bool = _continue_pair(source, target, CONTINUE_TICKS, RECORD_TICKS)
		check(label + " checkpoint continuation advances finite and byte-exactly", continuation_ok
			and source.sim.fault_reason.is_empty() and target.sim.fault_reason.is_empty()
			and source.checkpoint_json() == target.checkpoint_json())
	source.free()
	target.free()


func _check_start_metadata(session: Node, start_choice: String, label: String) -> void:
	var metadata: Dictionary = session.trace_meta()
	if start_choice == Flight.START_HAND_LAUNCH:
		check(label + " metadata identifies the hand-launch release",
			metadata.selected_start_choice == Flight.START_HAND_LAUNCH
				and metadata.launch_choice == Flight.START_HAND_LAUNCH
				and metadata.launch_kind == "hand_launch_release", str(metadata))
	else:
		check(label + " metadata identifies the trimmed airborne start",
			metadata.selected_start_choice == Flight.START_AIRBORNE
				and metadata.launch_choice == Flight.START_AIRBORNE
				and metadata.launch_kind == "trimmed_airborne", str(metadata))


func _check_session_weather(session: Node, label: String) -> void:
	var installed: Dictionary = session.weather_configuration()
	if legacy_mode:
		check(label + " installs the same legacy gentle weather profile", installed.get("format", "") == Config.TURBULENCE_FORMAT
			and installed.get("gust_mps", 0.0) > 0.0 and installed.get("turbulence_rms_mps", []).size() == 3)
	else:
		check(label + " installs the opted-in v5 spatial mean/gust/turbulence profile",
			installed.get("format", "") == Config.SPATIAL_FORMAT
				and installed.get("spatial_wind", {}).get("gusts", {}).get("events", []).size() == 1
				and installed.get("spatial_wind", {}).get("turbulence", {}).get("rms_mps", 0.0) > 0.0,
			str(installed))


func _check_checkpoint_format(snapshot: Dictionary, label: String) -> void:
	var format: String = str(snapshot.get("format", ""))
	if legacy_mode:
		check(label + " legacy checkpoint has its matching versioned envelope",
			format.begins_with("openrc-flight-checkpoint v"))
	else:
		check(label + " v5 checkpoint retains the spatial weather receipt",
			format == "openrc-flight-checkpoint v12" and snapshot.has("weather_config")
				and snapshot.has("spatial_weather_receipt"))


func _check_release_flow(session: Node, label: String) -> void:
	var body: PackedFloat64Array = session.sim.state
	var q: PackedFloat64Array = body.slice(RB.ATT, RB.ATT + 4)
	var velocity: PackedFloat64Array = body.slice(RB.VEL, RB.VEL + 3)
	var position: PackedFloat64Array = body.slice(RB.POS, RB.POS + 3)
	var wind: PackedFloat64Array = session._weather.sample_world(position, 0.0)
	var heading: float = M.q_to_euler(q)[0]
	check(label + " release retains ground-relative throw speed", absf(M.norm(velocity) - Flight.HAND_LAUNCH_SPEED_MPS) < 1e-12)
	check(label + " heading faces the wind at the actual release height",
		-(wind[0] * cos(heading) + wind[1] * sin(heading)) > 0.0)
	var prop: Dictionary = session.aircraft.model.propulsion
	# Authored offsets use aft/right/up; the simulation arm uses forward/right/down.
	var hub_arm := M.v3(-prop.offset[0], prop.offset[1], -prop.offset[2])
	var hub_position := M.add(position, M.q_rotate(q, hub_arm))
	var hub_wind: PackedFloat64Array = session._weather.sample_world(hub_position, 0.0)
	# Released without body rotation: subtract the independently sampled hub wind directly.
	var axial := M.dot(M.sub(velocity, M.q_rotate(M.q_conj(q), hub_wind)), Propulsion.axis(prop))
	var point := Propulsion.steady_operating_point(Flight.HAND_LAUNCH_THROTTLE, axial, prop, session.air_density(body))
	check(label + " starting motor solve uses local hub airspeed", point.get("ok", false)
		and absf(session._hand_launch_rpm(body) - float(point.get("rpm", NAN))) < 1e-7,
		"axial=%s expected=%s actual=%s" % [axial, point.get("rpm", NAN), session._hand_launch_rpm(body)])


func _advance(session: Node, ticks: int, first_tape_tick: int) -> bool:
	var initial_tick: int = session.sim.tick
	for offset in ticks:
		_set_tape_inputs(session, first_tape_tick + offset)
		if not session._session_after_input():
			return false
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or not _finite_session_sample(session):
			return false
	return session.sim.tick == initial_tick + ticks


func _continue_pair(source: Node, target: Node, ticks: int, first_tape_tick: int) -> bool:
	var source_tick: int = source.sim.tick
	var target_tick: int = target.sim.tick
	for offset in ticks:
		var tape_tick: int = first_tape_tick + offset
		_set_tape_inputs(source, tape_tick)
		_set_tape_inputs(target, tape_tick)
		if not source._session_after_input() or not target._session_after_input():
			printerr("continuation gate: source paused=%s ready=%s fault=%s; target paused=%s ready=%s fault=%s" % [
				source.sim.paused, source._flight_ready(), source.sim.fault_reason,
				target.sim.paused, target._flight_ready(), target.sim.fault_reason])
			return false
		source.sim.step()
		target.sim.step()
		if not source.sim.fault_reason.is_empty() or not target.sim.fault_reason.is_empty() \
				or not _finite_session_sample(source) or not _finite_session_sample(target):
			return false
		if var_to_bytes(source.sim.checkpoint()) != var_to_bytes(target.sim.checkpoint()):
			return false
	return source.sim.tick == source_tick + ticks and target.sim.tick == target_tick + ticks


func _set_tape_inputs(session: Node, tick: int) -> void:
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	if inputs.size() < 4:
		return
	inputs[0] = 0.015 * sin(float(tick) * 0.025)
	inputs[1] = -0.01 * cos(float(tick) * 0.02)
	inputs[2] = 0.005 * sin(float(tick) * 0.015)
	# Retain the selected start's throttle; the tape is otherwise identical for baseline/candidate mode.
	session.sim.inputs = inputs


func _finite_session_sample(session: Node) -> bool:
	return _finite_array(session.sim.state) and _finite_array(session.sim.last_loads) \
		and _finite_array(session.sim.aux) and _finite_array(session.sim.continuous)


func _finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check_orfl_self_replay(path: String, label: String) -> void:
	var inspected: Dictionary = Reader.inspect(path)
	check(label + " ORFL is complete with one row per accepted endpoint",
		inspected.get("ok", false) and inspected.get("complete", false)
			and inspected.get("rows", 0) == RECORD_TICKS + 1, str(inspected.get("error", "")))
	if not inspected.get("ok", false) or not inspected.get("complete", false):
		return
	var header: Dictionary = inspected.header
	check(label + " recorded solver identity is unchanged",
		str(header.get("solver_sha256", "")) == FlightLog.solver_identity())
	var replay: Dictionary = Reader.prepare_replay(header)
	check(label + " exact self-replay prepares on the recorded solver", replay.get("ok", false),
		str(replay.get("error", "")))
	if not replay.get("ok", false):
		return
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null:
		check(label + " ORFL packet stream opens", false)
		replay.flight.free()
		return
	stream.seek(8) # ORFL0001 magic, followed by the already inspected header packet.
	var header_packet: Dictionary = FlightLog.read_packet(stream)
	check(label + " ORFL replay starts after its checked header", header_packet.get("ok", false)
		and header_packet.get("value", {}).get("kind", "") == "header")
	if not header_packet.get("ok", false):
		stream.close()
		replay.flight.free()
		return
	var observer := FlightLog.new(replay.flight)
	var first_sample := true
	var replayed_ticks := 0
	var replay_error := ""
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = FlightLog.read_packet(stream)
		if not packet.get("ok", false):
			replay_error = str(packet.get("error", "packet read failed"))
			break
		var value: Dictionary = packet.value
		if value.get("kind", "") == "footer":
			break
		for row: Dictionary in value.get("rows", []):
			if first_sample:
				first_sample = false
				continue
			for key: Variant in row.get("intervention", {}):
				replay.flight.sim.set(key, row.intervention[key].duplicate())
			replay.flight.sim.inputs = row.inputs.duplicate()
			replay.flight.sim.step()
			var disagreement: String = Reader.disagreement(row, observer._sample({}))
			if not disagreement.is_empty():
				replay_error = disagreement
				break
			replayed_ticks += 1
		if not replay_error.is_empty():
			break
	stream.close()
	check(label + " exact self-replay matches every recorded endpoint",
		replayed_ticks == RECORD_TICKS and replay_error.is_empty(), replay_error)
	check(label + " replay session finishes without a solver fault",
		replay.flight.sim.fault_reason.is_empty(), replay.flight.sim.fault_reason)
	replay.flight.free()


func _mode_label() -> String:
	return "legacy gentle weather" if legacy_mode else "spatial v5 weather"
