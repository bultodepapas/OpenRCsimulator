## AUD-15: deterministic lifecycle capture through the production audio adapter.
## Fixed-wing portions use the real FlightSession runway route through takeoff/flight. At
## `landing_fixture`, the session is explicitly reset to a trimmed, descending approach;
## landing and wheel contacts then come from the real FlightSession integration. It is not
## one uninterrupted flight. Non-glow engine start/stop are labeled bench latch stimuli.
extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Math3D = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const GroundStart = preload("res://physics/ground_start.gd")
const Spec = preload("res://spec.gd")
const Trim = preload("res://physics/trim.gd")
const TakeoffPilot = preload("res://scenery/takeoff_pilot.gd")
const LandingManeuver = preload("res://sim/landing_maneuver.gd")
const StraightFlightPilotScript = preload("res://../tools/audio/straight_flight_pilot.gd")
const HelicopterSequencePilotScript = preload("res://../tools/audio/helicopter_sequence_pilot.gd")

var capture_fps := 60
var sequence_elapsed_s := 0.0
var sequence_wall_elapsed_s := 0.0
var sequence_start_usec := 0
var sequence_duration_s := 0.0
var sequence_wall_timeout_s := 360.0
var wall_timeout_reached := false
var sequence_interrupted_by_route_failure := false
var _last_session_tick := -1
var session_epoch := 0
var takeoff_sequence_start_s := -INF
var takeoff_heading_target := PI * 0.5
var _last_telemetry_wall_s := -INF
var continuous_mode := false
var continuous_straight_mode := false
var continuous_helicopter_mode := false
var continuous_pilot: RefCounted
var continuous_pilot_script: Script
var continuous_stop_dwell_s := 0.0
var continuous_shutdown_start_s := -INF
var continuous_done := false
var continuous_takeoff_separated := false
var continuous_takeoff_airborne_dwell_s := 0.0
var continuous_takeoff_handoff: Dictionary = {}
var continuous_takeoff_timeout_reached := false
var continuous_post_landing_soak_s := 0.0
var continuous_post_landing_soak_started_s := -INF
var continuous_helicopter_started := false
var continuous_pilot_failure_reason := ""
var sequence_interrupted_by_pilot_failure := false
var _continuous_last_tick := -1
var _continuous_pilot_start_sim_s := -INF
var _continuous_control_semantics := "unavailable"
var continuous_command_last: Dictionary = {}
var continuous_phase_last := ""
const FIXED_TIMELINE: Array = [
	[0.0, "off"], [2.0, "start"], [4.0, "idle"], [7.0, "taxi"],
	[10.0, "takeoff"], [22.0, "flight"], [27.0, "landing"],
	[35.0, "rollout"], [39.0, "shutdown"], [42.0, "done"],
]
const ROTOR_TIMELINE: Array = [
	[0.0, "off"], [2.0, "start"], [5.0, "ground_idle"], [8.0, "spinup"],
	[12.0, "takeoff"], [18.0, "flight"], [25.0, "landing"],
	[31.0, "settle"], [34.0, "shutdown"], [37.0, "done"],
]
const CONTINUOUS_STARTUP_TIMELINE: Array = [
	[0.0, "off"], [2.0, "start"], [4.0, "idle"], [7.0, "taxi"], [10.0, "takeoff"],
]
const CONTINUOUS_STAGE_ORDER: Array[String] = [
	"off", "start", "idle", "taxi", "takeoff", "flight", "landing", "rollout", "shutdown",
]
const CONTINUOUS_HELICOPTER_STAGE_ORDER: Array[String] = [
	"off", "start", "ground_idle", "spinup", "takeoff", "flight", "landing", "settle", "shutdown",
]

var args: Dictionary = {}
var frame := 0
var stage := ""
var aircraft_id := ""
var rotorcraft := false
var scene: Node3D
var adapter: Node
var premaster_capture: AudioEffectCapture
var master_capture: AudioEffectCapture
var premaster_samples := PackedVector2Array()
var master_samples := PackedVector2Array()
var premaster_chunks: Array[PackedVector2Array] = []
var master_chunks: Array[PackedVector2Array] = []
var pcm_frames_captured := 0
var final_pcm_clock: Dictionary = {}
var premaster_frames := 0
var premaster_peak := 0.0
var premaster_over_unity := 0
var premaster_invalid_sample := false
var premaster_discarded_frames := 0
var premaster_max_step := 0.0
var premaster_steps_over_08 := 0
var master_peak := 0.0
var master_over_unity := 0
var master_max_step := 0.0
var master_steps_over_08 := 0
var master_invalid_sample := false
var master_discarded_frames := 0
var events: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var bench_rows: Array[Array] = []
var notes: PackedStringArray = []
var takeoff_seen := false
var touchdown_seen := false
var rollout_contact_seen := false
var landing_fixture_ok := false
var landing_fixture_message := "not entered"
var engine_start_message := "not requested"
var focus_resumes := 0
var previous_grounded := 0
var rotor_start_throttle := 0.5
var rotor_start_diagnostics: Dictionary = {}
var landing_maneuver: RefCounted = null
var staged_flight_fixture_ok := false
var staged_flight_fixture_message := "not entered"
var route_crash_observed := false
var route_fault_observed := false
var route_failure_stage := ""
var route_failure_reason := ""
var route_failure_tick := -1
var route_failure_epoch := -1
var route_failure_history: Array[Dictionary] = []
var _route_failure_episode_active := false
var glow_skips_supported := false
var glow_skips_last := -1
var glow_skips_max := 0
var glow_skips_positive_deltas := 0
var glow_skip_counter_source := "unavailable"
var glow_pump_stats_supported := false
var glow_pump_stats_last: Dictionary = {}
var glow_pump_error_messages: Array[String] = []
var glow_pump_queue_min_frames := -1
var glow_pump_queue_max_frames := -1
var glow_pump_unprimed_samples := 0


func _initialize() -> void:
	seed(15015)
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	if args.has("list"):
		var ids := Catalog.airplane_flyable_ids()
		for id: String in ids:
			print("FLEET_AIRCRAFT_ID=", id)
		if Catalog.can_fly("xcell-60-research"):
			print("FLEET_AIRCRAFT_ID=xcell-60-research")
		quit(0)
		return
	if not args.has("out") or not args.has("aircraft"):
		printerr("--out=<absolute prefix> and --aircraft=<catalog ID> are required; --list prints the current fleet")
		quit(1)
		return
	var output_directory := str(args.out).get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if mkdir_error != OK:
			printerr("cannot create capture directory: ", output_directory, " error=", mkdir_error)
			quit(1)
			return
	aircraft_id = str(args.aircraft)
	continuous_straight_mode = args.has("continuous-straight")
	continuous_helicopter_mode = args.has("continuous-helicopter")
	continuous_mode = args.has("continuous") or continuous_straight_mode or continuous_helicopter_mode
	continuous_post_landing_soak_s = maxf(float(args.get("post-landing-soak", 0.0)), 0.0)
	var continuous_mode_count := int(args.has("continuous")) + int(continuous_straight_mode) + int(continuous_helicopter_mode)
	if continuous_mode_count > 1:
		printerr("choose exactly one continuous pilot mode")
		quit(1)
		return
	if continuous_post_landing_soak_s > 0.0 and not continuous_straight_mode:
		printerr("--post-landing-soak is available only with --continuous-straight")
		quit(1)
		return
	capture_fps = clampi(int(args.get("fps", 60)), 1, 60)
	if args.has("size"):
		var dimensions := str(args.size).split("x")
		if dimensions.size() == 2:
			get_root().size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if not Catalog.can_fly(aircraft_id):
		printerr("fleet sequence refuses unknown or non-flyable aircraft: ", aircraft_id)
		quit(1)
		return
	rotorcraft = Catalog.is_rotorcraft(aircraft_id)
	if rotorcraft and aircraft_id != "xcell-60-research":
		printerr("fleet sequence has no rotorcraft route for: ", aircraft_id)
		quit(1)
		return
	if continuous_helicopter_mode and (not rotorcraft or aircraft_id != "xcell-60-research"):
		printerr("--continuous-helicopter is limited to xcell-60-research")
		quit(1)
		return
	if continuous_mode and rotorcraft and not continuous_helicopter_mode:
		printerr("continuous fixed-wing routes are not supported for rotorcraft")
		quit(1)
		return
	if continuous_mode and not continuous_straight_mode and not continuous_helicopter_mode and aircraft_id not in ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]:
		printerr("--continuous is limited to the four Stik-family aircraft supported by the existing E3c2a experimental circuit pilot")
		quit(1)
		return
	if rotorcraft:
		scene = load("res://helicopter_main.tscn").instantiate() as Node3D
		scene.aircraft_id = aircraft_id
		scene.start_choice = "ground"
	else:
		scene = load("res://main.tscn").instantiate() as Node3D
		scene.aircraft_id = aircraft_id
		scene.start_choice = "runway"
	root.add_child(scene)
	if not str(scene.get("startup_error")).is_empty():
		printerr("fleet sequence startup refused: ", scene.get("startup_error"))
		quit(1)
		return
	adapter = scene.get("_soundscape_audio") as Node
	if adapter == null:
		printerr("fleet sequence requires the production flight audio adapter")
		quit(1)
		return
	var session: Node = scene.session
	session.read_raw = _controls
	if rotorcraft:
		rotor_start_throttle = float(session.commands.throttle)
		if continuous_helicopter_mode:
			if not _configure_continuous_helicopter_pilot(session):
				quit(1)
				return
			session.input_enabled = false
			session.sim.before_step.connect(_continuous_helicopter_before_step)
	else:
		var initial_orientation: PackedFloat64Array = Math3D.q_to_euler(session.sim.state.slice(RB.ATT, RB.ATT + 4))
		takeoff_heading_target = initial_orientation[0]
		if continuous_mode and not (_configure_straight_flight_pilot(session) if continuous_straight_mode else _configure_continuous_pilot(session)):
			quit(1)
			return
		if continuous_mode:
			# The existing E3c2a driver installs stick deltas directly into
			# FlightSession.commands once per accepted simulation tick. read_raw
			# is a rate command interface, so route commands must bypass it.
			session.input_enabled = false
			session.sim.before_step.connect(_continuous_before_step)
			_continuous_control_semantics = "direct session.commands and sim.inputs assignment in Simulation.before_step; matches the selected research pilot"
	_install_audio_probe()
	if rotorcraft:
		_enter_rotor_off()
	else:
		_enter_engine_off()
		if not _has_runway():
			notes.append("runway launch unavailable; takeoff segment remains a live aircraft-input attempt")
	var timeline: Array = ROTOR_TIMELINE if rotorcraft else (CONTINUOUS_STARTUP_TIMELINE if continuous_mode else FIXED_TIMELINE)
	sequence_duration_s = 240.0 if continuous_mode else float(timeline[-1][0])
	sequence_wall_timeout_s = maxf(float(args.get("wall-timeout", 360.0)), sequence_duration_s)
	_discard_probe_preamble()
	stage = str(timeline[0][1])
	sequence_start_usec = Time.get_ticks_usec()
	events.append(_event(stage, "initial production adapter state"))
	_last_session_tick = int(session.sim.tick)
	_continuous_last_tick = _last_session_tick
	while (sequence_elapsed_s < sequence_duration_s and not continuous_done) and sequence_wall_elapsed_s < sequence_wall_timeout_s:
		sequence_wall_elapsed_s = float(Time.get_ticks_usec() - sequence_start_usec) / 1000000.0
		var next := _continuous_stage(session) if continuous_mode else _stage_at(timeline, sequence_elapsed_s)
		if next != stage:
			stage = next
			_enter_stage(stage)
		if stage == "done":
			break
		await process_frame
		sequence_wall_elapsed_s = float(Time.get_ticks_usec() - sequence_start_usec) / 1000000.0
		_advance_sequence_time(session)
		_drain_audio_probe()
		_resume_focus_pause(session)
		_record_frame(sequence_elapsed_s)
		frame += 1
		_observe_route_failure(session)
		if continuous_helicopter_mode and continuous_pilot != null:
			var pilot_status: Dictionary = continuous_pilot.call("status")
			if bool(pilot_status.get("failed", false)) and continuous_pilot_failure_reason.is_empty():
				continuous_pilot_failure_reason = str(pilot_status.get("failure", "HELI-20 pilot failed"))
			if bool(pilot_status.get("complete", false)):
				continuous_done = true
		if not continuous_pilot_failure_reason.is_empty():
			notes.append("continuous pilot ended the route: " + continuous_pilot_failure_reason)
			sequence_interrupted_by_pilot_failure = true
			break
		if continuous_mode and not continuous_helicopter_mode and stage == "takeoff" and not continuous_takeoff_separated \
				and sequence_elapsed_s - takeoff_sequence_start_s >= float(args.get("takeoff-timeout", 30.0)):
			continuous_takeoff_timeout_reached = true
			notes.append("continuous takeoff did not achieve 0.1 s gear separation within %.1f accepted seconds; partial capture retained" % float(args.get("takeoff-timeout", 30.0)))
			break
		if _route_failure_active(session):
			if rotorcraft:
				notes.append("active helicopter crash/fault at %s; terminating this capture rather than waiting for accepted ticks" % stage)
				sequence_interrupted_by_route_failure = true
				break
			if continuous_mode:
				notes.append("continuous E3c2a pilot encountered a live crash/fault at %s; route ended without a reset or fixture recovery" % stage)
				sequence_interrupted_by_route_failure = true
				break
			for attempt: int in 2:
				if not _route_failure_active(session):
					break
				if not _recover_failed_runway_route(timeline):
					break
			if _route_failure_active(session):
				notes.append("active fixed-wing crash/fault persisted after the available fixture recovery at %s; capture ended early" % stage)
				sequence_interrupted_by_route_failure = true
				break
	sequence_wall_elapsed_s = float(Time.get_ticks_usec() - sequence_start_usec) / 1000000.0
	wall_timeout_reached = sequence_elapsed_s < sequence_duration_s and not continuous_done and sequence_wall_elapsed_s >= sequence_wall_timeout_s
	if sequence_elapsed_s < sequence_duration_s:
		if wall_timeout_reached:
			notes.append("wall timeout after %.2f s at accepted sequence time %.2f/%.2f s; remaining timeline stages are incomplete" % [
				sequence_wall_elapsed_s, sequence_elapsed_s, sequence_duration_s])
		elif not sequence_interrupted_by_route_failure and not continuous_takeoff_timeout_reached and not continuous_done:
			notes.append("sequence ended before its accepted-time duration; no wall-timeout or route interruption was recorded")
	_drain_audio_probe()
	final_pcm_clock = _pcm_clock_snapshot()
	_finalize_capture_samples()
	var wav_path := str(args.out) + ".wav"
	var wav_error := _save_wav(wav_path)
	if wav_error != OK:
		printerr("could not save master PCM WAV: ", wav_path, " error=", wav_error)
		quit(1)
		return
	var report := _report(timeline)
	var output := FileAccess.open(str(args.out) + ".json", FileAccess.WRITE)
	if output == null:
		printerr("cannot write sequence report: ", args.out)
		quit(1)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	root.remove_child(scene)
	scene.free()
	await process_frame
	quit(0)


func _has_runway() -> bool:
	var field: Dictionary = scene.get("field")
	if field.is_empty():
		return false
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			return true
	return false


func _configure_continuous_pilot(session: Node) -> bool:
	var field: Dictionary = scene.get("field")
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			runway = surface
	if runway.is_empty():
		printerr("continuous E3c2a route requires the field runway definition")
		return false
	var spot: Dictionary = GroundStart.threshold(field, true)
	if not spot.get("ok", false) or not session.reset_on_runway(float(spot.get("north", 0.0)),
			float(spot.get("east", 0.0)), float(spot.get("heading", PI * 0.5))):
		printerr("continuous E3c2a route could not establish its documented threshold runway start")
		return false
	var reset_heading: PackedFloat64Array = Math3D.q_to_euler(session.sim.state.slice(RB.ATT, RB.ATT + 4))
	takeoff_heading_target = reset_heading[0]
	var pilot_path := ProjectSettings.globalize_path("res://../research/landing/e3c2a/circuit_pilot.gd").simplify_path()
	var pilot_source := FileAccess.get_file_as_string(pilot_path)
	if pilot_source.is_empty():
		printerr("cannot load existing E3c2a circuit pilot: ", pilot_path)
		return false
	continuous_pilot_script = GDScript.new()
	continuous_pilot_script.source_code = pilot_source
	var pilot_error := continuous_pilot_script.reload()
	if pilot_error != OK:
		printerr("cannot compile existing E3c2a circuit pilot: ", pilot_path, " error=", pilot_error)
		return false
	var approach_trim: Dictionary = session.trim_at(12.0)
	var cruise_trim: Dictionary = session.trim_at(15.0)
	if not approach_trim.get("ok", false) or not cruise_trim.get("ok", false):
		printerr("continuous E3c2a route could not obtain its existing 12/15 m/s trim inputs")
		return false
	var pilot_parameters: Dictionary = approach_trim.duplicate(true)
	pilot_parameters.cruise_throttle = float(cruise_trim.get("throttle", approach_trim.get("throttle", 0.0)))
	continuous_pilot = continuous_pilot_script.new(runway, true, pilot_parameters)
	notes.append("continuous route uses TakeoffPilot at full power until 0.1 s of gear separation, then hands off in the same FlightSession to research/landing/e3c2a/circuit_pilot.gd initial_climb; no route reset is used")
	return continuous_pilot != null


func _configure_straight_flight_pilot(session: Node) -> bool:
	var field: Dictionary = scene.get("field")
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			runway = surface
	if runway.is_empty():
		printerr("continuous straight route requires the field runway definition")
		return false
	var spot: Dictionary = GroundStart.threshold(field, true)
	if not spot.get("ok", false) or not session.reset_on_runway(float(spot.get("north", 0.0)),
			float(spot.get("east", 0.0)), float(spot.get("heading", PI * 0.5))):
		printerr("continuous straight route could not establish its documented threshold runway start")
		return false
	var reset_heading: PackedFloat64Array = Math3D.q_to_euler(session.sim.state.slice(RB.ATT, RB.ATT + 4))
	takeoff_heading_target = reset_heading[0]
	continuous_pilot_script = StraightFlightPilotScript
	continuous_pilot = continuous_pilot_script.new()
	var model: Dictionary = session.aircraft.model
	var start_throttle := float(session.start.get("throttle", session.commands.throttle))
	if not bool(continuous_pilot.call("configure", model, start_throttle)):
		printerr("FT-card-v5 straight pilot refused current model/start trim for ", aircraft_id)
		return false
	notes.append("continuous straight route uses the research FT-card-v5 takeoff/climb/approach/flare/rollout laws in one FlightSession; landing is intentionally ahead on clear terrain, not a runway return")
	return true


func _configure_continuous_helicopter_pilot(_session: Node) -> bool:
	continuous_pilot_script = HelicopterSequencePilotScript
	continuous_pilot = continuous_pilot_script.new()
	_continuous_control_semantics = "HelicopterSequencePilot.before_accepted_tick connected to Simulation.before_step; HELI-20 law updates accepted session inputs without stepping or resetting"
	notes.append("continuous X-Cell route reuses the HELI-20 ground/spool/hover/landing/coast cycle in one FlightSession; the session owns its normal accepted tick loop")
	return continuous_pilot != null


func _continuous_helicopter_before_step(_tick: int) -> void:
	if not continuous_helicopter_mode or not continuous_helicopter_started or continuous_pilot == null:
		return
	continuous_pilot.call("before_accepted_tick")


func _continuous_stage(session: Node) -> String:
	if continuous_helicopter_mode:
		if sequence_elapsed_s < 2.0:
			return "off"
		if not continuous_helicopter_started:
			return "start"
		var status: Dictionary = continuous_pilot.call("status")
		if bool(status.get("failed", false)):
			return "shutdown"
		if bool(status.get("complete", false)):
			continuous_done = true
			return "done"
		var heli_phase := str(status.get("phase", ""))
		if heli_phase == "spool":
			if sequence_elapsed_s < 4.0:
				return "start"
			return "ground_idle" if sequence_elapsed_s < 7.0 else "spinup"
		if heli_phase == "flight":
			if not takeoff_seen:
				return "takeoff"
			var state: PackedFloat64Array = session.sim.state
			var velocity_ned: PackedFloat64Array = Math3D.q_rotate(state.slice(RB.ATT, RB.ATT + 4),
				state.slice(RB.VEL, RB.VEL + 3))
			if _height_m() < 0.6 and velocity_ned[2] > 0.0:
				return "landing"
			return "flight"
		if heli_phase == "lower_collective":
			return "settle"
		if heli_phase == "coast":
			return "shutdown"
		return "spinup"
	if sequence_elapsed_s < float(CONTINUOUS_STARTUP_TIMELINE[-1][0]):
		return _stage_at(CONTINUOUS_STARTUP_TIMELINE, sequence_elapsed_s)
	if not continuous_takeoff_separated:
		return "takeoff"
	var tick := int(session.sim.tick)
	var accepted_delta := 0.0
	if _continuous_last_tick >= 0 and tick >= _continuous_last_tick:
		accepted_delta = float(tick - _continuous_last_tick) * maxf(float(session.sim.dt()), 0.0)
	_continuous_last_tick = tick
	if continuous_shutdown_start_s >= 0.0:
		if sequence_elapsed_s - continuous_shutdown_start_s >= 2.0:
			continuous_done = true
			return "done"
		return "shutdown"
	if continuous_straight_mode:
		if bool(continuous_pilot.get("finished")):
			if continuous_post_landing_soak_s > 0.0:
				if continuous_post_landing_soak_started_s < 0.0:
					continuous_post_landing_soak_started_s = sequence_elapsed_s
				if sequence_elapsed_s - continuous_post_landing_soak_started_s < continuous_post_landing_soak_s:
					return "rollout"
			continuous_shutdown_start_s = sequence_elapsed_s
			return "shutdown"
		var straight_phase := str(continuous_pilot.get("phase"))
		match straight_phase:
			"takeoff": return "takeoff"
			"flight": return "flight"
			"approach", "flare": return "landing"
			"rollout": return "rollout"
			_:
				return "flight"
	var phase := str(continuous_pilot.get("phase")) if continuous_pilot != null else ""
	if phase == "takeoff_roll":
		return "takeoff"
	if phase in ["initial_climb", "crosswind_turn", "crosswind", "downwind_turn", "downwind", "base_turn", "base"]:
		return "flight"
	if phase in ["final_turn", "final_join", "approach", "flare"]:
		return "landing"
	if phase == "rollout":
		var grounded := false
		for compression: float in session.gear_compressions(session.sim.state):
			grounded = grounded or compression > 0.0
		var state: PackedFloat64Array = session.sim.state
		var settled := grounded and _speed_mps() < 0.08 and Math3D.norm(Math3D.v3(state[RB.RATE], state[RB.RATE + 1], state[RB.RATE + 2])) < 0.02
		continuous_stop_dwell_s = continuous_stop_dwell_s + accepted_delta if settled else 0.0
		if continuous_stop_dwell_s >= 2.0:
			continuous_shutdown_start_s = sequence_elapsed_s
			return "shutdown"
		return "rollout"
	return "flight"


func _continuous_before_step(_tick: int) -> void:
	if not continuous_mode or continuous_pilot == null:
		return
	var session: Node = scene.session
	var state: PackedFloat64Array = session.sim.state
	var command: Dictionary = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0}
	if stage == "taxi":
		var taxi_pilot: Dictionary = TakeoffPilot.step(2.0, state, takeoff_heading_target)
		var taxi_commands: Dictionary = taxi_pilot.get("commands", command)
		command = taxi_commands.duplicate(true)
		command.throttle = 0.2
	elif stage == "takeoff" and not continuous_takeoff_separated:
		if continuous_straight_mode:
			var clearance := 0.0
			var first := true
			for compression: float in session.gear_compressions(state):
				clearance = -compression if first else minf(clearance, -compression)
				first = false
			var elapsed := maxf(float(session.sim.time()) - _continuous_pilot_start_sim_s, 0.0)
			var output: Dictionary = continuous_pilot.call("commands", state, clearance, elapsed)
			command = output
			var airborne := clearance > 0.0
			continuous_takeoff_airborne_dwell_s = continuous_takeoff_airborne_dwell_s + session.sim.dt() if airborne else 0.0
			if continuous_takeoff_airborne_dwell_s >= 0.1:
				continuous_takeoff_separated = true
				continuous_takeoff_handoff = {tick = int(session.sim.tick), sim_time_s = float(session.sim.time()),
					speed_mps = _speed_mps(), height_m = _height_m(),
					airborne_dwell_s = continuous_takeoff_airborne_dwell_s, pilot_phase = str(continuous_pilot.get("phase"))}
		else:
			# Keep the existing Stik-tuned takeoff pilot at full power until real gear separation.
			# E3c2a switches into its estimated circuit-speed controller at 12 m/s, before this
			# lifecycle startup sequence has necessarily produced liftoff.
			var takeoff_output: Dictionary = TakeoffPilot.step(TakeoffPilot.IDLE_S + TakeoffPilot.THROTTLE_RAMP_S,
				state, takeoff_heading_target)
			command = takeoff_output.get("commands", command).duplicate(true)
			var airborne := true
			for compression: float in session.gear_compressions(state):
				if compression > 0.0:
					airborne = false
			continuous_takeoff_airborne_dwell_s = continuous_takeoff_airborne_dwell_s + session.sim.dt() if airborne else 0.0
			if continuous_takeoff_airborne_dwell_s >= 0.1:
				continuous_takeoff_separated = true
				continuous_pilot.set("phase", "initial_climb")
				continuous_takeoff_handoff = {tick = int(session.sim.tick), sim_time_s = float(session.sim.time()),
					speed_mps = _speed_mps(), height_m = _height_m(),
					airborne_dwell_s = continuous_takeoff_airborne_dwell_s}
	elif stage in ["takeoff", "flight", "landing", "rollout"]:
		var clearance := 0.0
		var first := true
		for compression: float in session.gear_compressions(state):
			clearance = -compression if first else minf(clearance, -compression)
			first = false
		var elapsed := maxf(float(session.sim.time()) - _continuous_pilot_start_sim_s, 0.0)
		command = continuous_pilot.call("commands", state, clearance, elapsed)
	elif stage in ["start", "idle"]:
		command.throttle = 0.12
	session.commands = command
	session.sim.inputs = session._inputs()
	continuous_command_last = command.duplicate(true)
	continuous_phase_last = str(continuous_pilot.get("phase")) if continuous_pilot != null else ""


func _enter_engine_off() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		if session.engine_running:
			session.glow_cut()
	else:
		var kind := str(prop.get("kind", "glow_prop"))
		if kind != "electric_prop":
			session.engine_running = false
			notes.append("combustion/turbine start and stop use the harness engine_running latch; no installed starter event exists")


func _start_airplane_engine() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		engine_start_message = "physical glow starter accepted" if session.glow_start() else "physical glow starter refused"
		if engine_start_message.ends_with("refused"):
			notes.append("physical glow_start() did not accept this start; its engine-running state is reported from session data")
	elif str(prop.get("kind", "glow_prop")) != "electric_prop":
		session.engine_running = true
		engine_start_message = "presentation engine_running latch start stimulus"
	else:
		notes.append("electric motor start is represented by its accepted low-power throttle/RPM rise")
		engine_start_message = "electric low-power throttle/RPM start stimulus"


func _stop_airplane_engine() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		if session.engine_running:
			session.glow_cut()
	elif str(prop.get("kind", "glow_prop")) != "electric_prop":
		session.engine_running = false


func _enter_rotor_off() -> void:
	var session: Node = scene.session
	session.set_drive_hold(true)
	if session.power.armed:
		session.toggle_motor_arm()


func _start_rotor() -> void:
	var session: Node = scene.session
	session.set_drive_hold(true)
	var pitch_before_arm := rad_to_deg(float(session.collective_pitch()))
	var arm_requested := not bool(session.power.armed)
	var arm_accepted := true if not arm_requested else bool(session.toggle_motor_arm())
	var drive_release_accepted := true
	if arm_accepted and session.power.armed:
		drive_release_accepted = bool(session.set_drive_hold(false))
	rotor_start_diagnostics = {"requested": arm_requested, "accepted": arm_accepted,
		"drive_release_accepted": drive_release_accepted, "zero_pitch_command": rotor_start_throttle,
		"collective_pitch_before_arm_deg": pitch_before_arm, "armed_after_start": bool(session.power.armed),
		"drive_held_after_start": bool(session.zero_drive_hold), "paused_after_start": bool(session.sim.paused),
		"pause_reason": str(session.pause_reason)}
	if not arm_accepted:
		notes.append("helicopter motor arm request was refused: " + str(session.pause_reason))
	if not drive_release_accepted:
		notes.append("helicopter drive-hold release was refused: " + str(session.pause_reason))


func _stop_rotor() -> void:
	var session: Node = scene.session
	session.set_drive_hold(true)
	if session.power.armed:
		session.toggle_motor_arm()


func _enter_stage(next: String) -> void:
	var action := ""
	var session: Node = scene.session
	if rotorcraft:
		match next:
			"start":
				if continuous_helicopter_mode:
					continuous_helicopter_started = bool(continuous_pilot.call("begin_cycle", session))
					if not continuous_helicopter_started:
						continuous_pilot_failure_reason = str(continuous_pilot.get("failure_reason"))
						action = "HELI-20 start refused: " + continuous_pilot_failure_reason
					else:
						action = "HELI-20 continuous ground-cycle start accepted; no session reset"
				else:
					_start_rotor()
					action = "accepted motor arm and drive-hold release requested"
			"landing":
				action = "collective reduced for pad descent; no wheeled rollout"
			"shutdown":
				if continuous_helicopter_mode:
					action = "HELI-20 rotor coast/disarm completed in the same session" if continuous_done else "HELI-20 rotor coast and disarm remain session-owned"
				else:
					_stop_rotor()
					action = "drive held and motor disarmed"
			"takeoff": action = "pad lift command; actual liftoff checked from contacts"
			"settle": action = "skid/pad settle; rollout is not applicable"
			_: pass
	else:
		match next:
			"start":
				_start_airplane_engine()
				action = engine_start_message
			"landing":
				action = "FT-card-v5 approach lands straight ahead on terrain; not a runway return" if continuous_straight_mode else ("continuous E3c2a circuit landing segment; no session reset" if continuous_mode else "reset to descending approach fixture; touchdown and rollout remain live session observations")
			"shutdown":
				_stop_airplane_engine()
				action = "engine cut requested; RPM remains session-owned"
			"takeoff":
				takeoff_sequence_start_s = sequence_elapsed_s
				if continuous_mode:
					_continuous_pilot_start_sim_s = float(session.sim.time())
				action = "FT-card-v5 direct-command takeoff; no reset after runway start" if continuous_straight_mode else "TakeoffPilot holds full power until 0.1 s gear separation, then hands off to E3c2a initial_climb"
			"flight":
				action = ("FT-card-v5 straight climb/brief level segment" if continuous_straight_mode else "continuous E3c2a circuit flight segment") if continuous_mode else ("live flight continuation" if takeoff_seen else "runway liftoff not observed; staging airborne flight fixture")
			"taxi": action = "low-power runway input; wheel motion/contact are measured, not assumed"
			"rollout": action = ("FT-card-v5 straight landing rollout; post-landing soak keeps the same session alive" if continuous_straight_mode and continuous_post_landing_soak_s > 0.0 else ("FT-card-v5 direct-command straight landing rollout" if continuous_straight_mode else ("continuous E3c2a circuit rollout" if continuous_mode else "idle input after staged approach; wheel contact is measured")))
			_: pass
	events.append(_event(next, action))
	if not continuous_mode and not rotorcraft and next == "flight" and not takeoff_seen:
		_stage_flight_fixture()
	elif not continuous_mode and not rotorcraft and next == "landing":
		_stage_landing_fixture()


func _stage_landing_fixture() -> void:
	var session: Node = scene.session
	var field: Dictionary = scene.field
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			runway = surface
	if runway.is_empty():
		landing_fixture_message = "staged landing skipped: field runway unavailable"
		notes.append(landing_fixture_message)
		return
	var speed := float(session.start.get("V", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		speed = 20.0
	var trim: Dictionary = session.trim_at(speed)
	if not trim.get("ok", false):
		landing_fixture_message = "staged landing skipped: trim failed at %.2f m/s" % speed
		notes.append(landing_fixture_message)
		return
	var eastbound := true
	var direction := 1.0 if eastbound else -1.0
	var half_length := float(runway.get("length_east_west", 240.0)) * 0.5
	var start_state: PackedFloat64Array = Trim.state_for(speed, float(trim.alpha), 0.0,
		direction * PI * 0.5, Math3D.v3(float(runway.get("center_north", 0.0)),
		float(runway.get("center_east", 0.0)) - direction * (half_length + 76.0), -8.0), float(trim.get("beta", 0.0)))
	var attitude := Math3D.q_from_euler(direction * PI * 0.5, float(trim.alpha), 0.0)
	for index: int in 4:
		start_state[RB.ATT + index] = attitude[index]
	start_state[RB.VEL + 2] += 0.7 # explicit descending approach fixture, then FlightSession owns every tick/contact
	session.start.state = start_state
	session.start_choice = "airborne"
	session.set_start_altitude(8.0)
	session.reset()
	session_epoch += 1
	_last_session_tick = int(session.sim.tick)
	landing_maneuver = null
	if aircraft_id in ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t"]:
		landing_maneuver = LandingManeuver.new(float(runway.get("center_north", 0.0)), eastbound,
			float(trim.get("throttle", session.commands.throttle)), float(trim.get("pitch_command", 0.0)))
	landing_fixture_ok = session.is_flyable()
	landing_fixture_message = "staged descending approach reset; landing physics/contact remain live" if landing_fixture_ok else "staged approach reset refused: " + str(session.pause_reason)
	if not landing_fixture_ok:
		notes.append(landing_fixture_message)


func _controls() -> Dictionary:
	var session: Node = scene.session
	if rotorcraft:
		# A ground start's exact zero-pitch stick comes from the accepted hover/trainer setup.
		# Keep that value through arming and rotor spool-up; 0.5 can be outside the model's
		# one-degree pickup window and silently refuse the motor arm.
		var collective_target := rotor_start_throttle
		match stage:
			"takeoff": collective_target = 0.68
			"flight": collective_target = 0.60
			"landing": collective_target = 0.49
			"settle", "shutdown", "off", "start", "ground_idle", "spinup": collective_target = rotor_start_throttle
		return {roll = 0.0, pitch = 0.0, yaw = 0.0,
			throttle = _throttle_rate_input(session, collective_target)}
	if continuous_mode and continuous_pilot != null and takeoff_sequence_start_s > -INF:
		var clearance := 0.0
		var first := true
		for compression: float in session.gear_compressions(session.sim.state):
			if first:
				clearance = -compression
				first = false
			else:
				clearance = minf(clearance, -compression)
		var elapsed := maxf(sequence_elapsed_s - takeoff_sequence_start_s, 0.0)
		var command: Dictionary = continuous_pilot.call("commands", session.sim.state, clearance, elapsed)
		return {roll = float(command.get("roll", 0.0)), pitch = float(command.get("pitch", 0.0)),
			yaw = float(command.get("yaw", 0.0)),
			throttle = _throttle_rate_input(session, float(command.get("throttle", 0.0)))}
	if stage == "taxi":
		var taxi_pilot: Dictionary = TakeoffPilot.step(2.0, session.sim.state, takeoff_heading_target)
		var taxi_commands: Dictionary = taxi_pilot.get("commands", {})
		return {roll = float(taxi_commands.get("roll", 0.0)), pitch = 0.0,
			yaw = float(taxi_commands.get("yaw", 0.0)),
			throttle = _throttle_rate_input(session, 0.2)}
	if stage == "takeoff":
		var elapsed := maxf(sequence_elapsed_s - takeoff_sequence_start_s, 0.0)
		var pilot: Dictionary = TakeoffPilot.step(elapsed, session.sim.state, takeoff_heading_target)
		var commands: Dictionary = pilot.get("commands", {})
		return {roll = float(commands.get("roll", 0.0)), pitch = float(commands.get("pitch", 0.0)),
			yaw = float(commands.get("yaw", 0.0)),
			throttle = _throttle_rate_input(session, float(commands.get("throttle", 0.0)))}
	if landing_maneuver != null and stage in ["landing", "rollout"]:
		var clearance := maxf(-float(session.sim.state[RB.POS + 2]), 0.0)
		var landing_commands: Dictionary = landing_maneuver.commands(session.sim.state, clearance)
		return {roll = float(landing_commands.get("roll", 0.0)), pitch = float(landing_commands.get("pitch", 0.0)),
			yaw = float(landing_commands.get("yaw", 0.0)),
			throttle = _throttle_rate_input(session, float(landing_commands.get("throttle", 0.0)))}
	var throttle_target := 0.0
	var pitch := 0.0
	match stage:
		"start", "idle", "landing": throttle_target = 0.12
		"taxi": throttle_target = 0.2
		"takeoff":
			throttle_target = 1.0
			pitch = 0.12
		"flight": throttle_target = 0.55
		"rollout", "shutdown", "off": throttle_target = 0.0
	return {roll = 0.0, pitch = pitch, yaw = 0.0,
		throttle = _throttle_rate_input(session, throttle_target)}


func _throttle_rate_input(session: Node, target: float) -> float:
	# read_raw receives a keyboard-style rate command (-1..1), not an RC throttle target.
	# Convert the scheduled position into the rate signal the production command integrator expects.
	var step: float = float(Spec.CONTROLS.throttle_rate) * maxf(float(session.sim.dt()), 0.0)
	if step <= 0.0:
		return 0.0
	return clampf((target - float(session.commands.throttle)) / step, -1.0, 1.0)


func _event(name: String, action: String) -> Dictionary:
	var session: Node = scene.session
	var tick := int(session.sim.tick)
	return {frame = frame, time_s = sequence_wall_elapsed_s, sequence_time_s = sequence_elapsed_s,
		stage = name, action = action, tick = tick, sim_time_s = float(session.sim.time()),
		session_epoch = session_epoch, aircraft = aircraft_id, pcm_clock = _pcm_clock_snapshot()}


func _pcm_clock_snapshot() -> Dictionary:
	var mix_rate := maxi(AudioServer.get_mix_rate(), 1)
	var elapsed_s := float(Time.get_ticks_usec() - sequence_start_usec) / 1000000.0 if sequence_start_usec > 0 else 0.0
	var expected_frames := roundi(elapsed_s * float(mix_rate))
	var master_count := pcm_frames_captured
	var premaster_count := premaster_frames
	return {wall_elapsed_s = elapsed_s, mix_rate_hz = mix_rate,
		expected_frames_from_wall_clock = expected_frames,
		master_captured_frames = master_count, master_frame_lag = expected_frames - master_count,
		master_frame_lag_ms = 1000.0 * float(expected_frames - master_count) / float(mix_rate),
		premaster_captured_frames = premaster_count, premaster_frame_lag = expected_frames - premaster_count,
		premaster_frame_lag_ms = 1000.0 * float(expected_frames - premaster_count) / float(mix_rate),
		meaning = "wall-clock expected PCM frames minus captured-frame count; a capture-clock lag proxy, not measured hardware output latency"}


func _stage_at(timeline: Array, t: float) -> String:
	var current := str(timeline[0][1])
	for entry: Array in timeline:
		if t >= float(entry[0]):
			current = str(entry[1])
	return current


func _timeline_time(timeline: Array, name: String) -> float:
	for entry: Array in timeline:
		if str(entry[1]) == name:
			return float(entry[0])
	return sequence_duration_s


func _advance_sequence_time(session: Node) -> void:
	var tick := int(session.sim.tick)
	if _last_session_tick < 0 or tick < _last_session_tick:
		_last_session_tick = tick
		return
	var sim_dt := maxf(float(session.sim.dt()), 0.0)
	sequence_elapsed_s += float(tick - _last_session_tick) * sim_dt
	_last_session_tick = tick


func _stage_flight_fixture() -> void:
	var session: Node = scene.session
	var field: Dictionary = scene.field
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			runway = surface
	if runway.is_empty():
		staged_flight_fixture_message = "staged airborne segment skipped: field runway unavailable"
		notes.append(staged_flight_fixture_message)
		return
	var speed := float(session.start.get("V", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		speed = 20.0
	var trim: Dictionary = session.trim_at(speed)
	if not trim.get("ok", false):
		staged_flight_fixture_message = "staged airborne segment skipped: trim failed at %.2f m/s" % speed
		notes.append(staged_flight_fixture_message)
		return
	var half_length := float(runway.get("length_east_west", 240.0)) * 0.5
	var start_state: PackedFloat64Array = Trim.state_for(speed, float(trim.alpha), 0.0,
		PI * 0.5, Math3D.v3(float(runway.get("center_north", 0.0)),
		float(runway.get("center_east", 0.0)) - (half_length + 76.0), -70.0), float(trim.get("beta", 0.0)))
	var attitude := Math3D.q_from_euler(PI * 0.5, float(trim.alpha), 0.0)
	for index: int in 4:
		start_state[RB.ATT + index] = attitude[index]
	session.start.state = start_state
	session.start_choice = "airborne"
	session.set_start_altitude(70.0)
	session.reset()
	session_epoch += 1
	_last_session_tick = int(session.sim.tick)
	staged_flight_fixture_ok = session.is_flyable()
	staged_flight_fixture_message = "trimmed 70 m airborne segment staged after runway phase; not a runway liftoff" if staged_flight_fixture_ok else "staged airborne reset refused: " + str(session.pause_reason)
	notes.append(staged_flight_fixture_message)


func _observe_route_failure(session: Node) -> void:
	var crash_now: bool = not session.crash.is_empty()
	var fault_now: bool = not str(session.sim.fault_reason).is_empty()
	if crash_now or fault_now:
		if not _route_failure_episode_active:
			route_failure_history.append({
				"stage": stage, "session_epoch": session_epoch, "tick": int(session.sim.tick),
				"crash": _crash_summary(session.crash), "fault_reason": str(session.sim.fault_reason),
			})
		_route_failure_episode_active = true
	else:
		_route_failure_episode_active = false
	if crash_now and not route_crash_observed:
		route_crash_observed = true
		route_failure_stage = stage
		route_failure_reason = str(session.crash.get("reason", session.crash.get("component", "route crash")))
		route_failure_tick = int(session.sim.tick)
		route_failure_epoch = session_epoch
	if fault_now and not route_fault_observed:
		route_fault_observed = true
		if route_failure_stage.is_empty():
			route_failure_stage = stage
			route_failure_reason = str(session.sim.fault_reason)
			route_failure_tick = int(session.sim.tick)
			route_failure_epoch = session_epoch


func _crash_summary(crash: Dictionary) -> Dictionary:
	var summary := crash.duplicate(true)
	summary.erase("impact")
	return summary


func _route_failure_active(session: Node) -> bool:
	return not session.crash.is_empty() or not str(session.sim.fault_reason).is_empty()


func _recover_failed_runway_route(timeline: Array) -> bool:
	if stage in ["off", "start", "idle", "taxi", "takeoff"]:
		notes.append("active route failure at %s; skipping the remaining runway segment and trying the marked airborne fixture" % stage)
		sequence_elapsed_s = maxf(sequence_elapsed_s, _timeline_time(timeline, "flight"))
		stage = "flight"
		_enter_stage(stage)
		return not _route_failure_active(scene.session)
	if stage == "flight":
		notes.append("active route failure during flight; skipping to the marked descending landing fixture")
		sequence_elapsed_s = maxf(sequence_elapsed_s, _timeline_time(timeline, "landing"))
		stage = "landing"
		_enter_stage(stage)
		return not _route_failure_active(scene.session)
	return false


func _resume_focus_pause(session: Node) -> void:
	if session.sim.paused and session.holds.is_empty() and session.crash.is_empty() \
			and session.pause_reason.is_empty() and session.sim.fault_reason.is_empty():
		session.resume()
		focus_resumes += 1


func _ground_snapshot() -> Dictionary:
	for property: Dictionary in adapter.get_property_list():
		if str(property.get("name", "")) == "ground_snapshot":
			var value: Variant = adapter.get("ground_snapshot")
			return value if value is Dictionary else {}
	if adapter.has_method("ground_snapshot"):
		var value: Variant = adapter.call("ground_snapshot")
		return value if value is Dictionary else {}
	if adapter.has_method("contact_snapshot"):
		var value: Variant = adapter.call("contact_snapshot")
		if value is Dictionary:
			return value
		if value is Array:
			return {contacts = value, tick = int(scene.session.sim.tick)}
	return {}


func _install_audio_probe() -> void:
	var soundscape: Node = adapter.get("soundscape") as Node
	if soundscape == null or not soundscape.has_method("output_bus"):
		notes.append("pre-master probe unavailable: soundscape output bus is not exposed")
		return
	var output_bus := AudioServer.get_bus_index(StringName(soundscape.call("output_bus")))
	if output_bus < 0:
		notes.append("pre-master probe unavailable: soundscape output bus is missing")
		return
	if args.has("engine-only") and soundscape.has_method("environment_bus"):
		var environment_bus := AudioServer.get_bus_index(StringName(soundscape.call("environment_bus")))
		if environment_bus >= 0:
			AudioServer.set_bus_mute(environment_bus, true)
	premaster_capture = AudioEffectCapture.new()
	premaster_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(output_bus, premaster_capture)
	var master_index := AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		notes.append("post-master probe unavailable: Master bus is missing")
		return
	master_capture = AudioEffectCapture.new()
	master_capture.buffer_length = 2.0
	# Appending after the configured Master effects captures the delivered software mix.
	AudioServer.add_bus_effect(master_index, master_capture)


func _drain_audio_probe() -> void:
	if premaster_capture != null:
		var available := premaster_capture.get_frames_available()
		if available > 0:
			var buffer: PackedVector2Array = premaster_capture.get_buffer(available)
			premaster_chunks.append(buffer)
			premaster_frames += buffer.size()
		premaster_discarded_frames = premaster_capture.get_discarded_frames()
	if master_capture != null:
		var master_available := master_capture.get_frames_available()
		if master_available > 0:
			var master_buffer: PackedVector2Array = master_capture.get_buffer(master_available)
			master_chunks.append(master_buffer)
			pcm_frames_captured += master_buffer.size()
			master_discarded_frames = master_capture.get_discarded_frames()


func _save_wav(path: String) -> Error:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = AudioServer.get_mix_rate()
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(master_samples.size() * 4)
	for index: int in master_samples.size():
		data.encode_s16(index * 4, clampi(roundi(master_samples[index].x * 32767.0), -32768, 32767))
		data.encode_s16(index * 4 + 2, clampi(roundi(master_samples[index].y * 32767.0), -32768, 32767))
	wav.data = data
	return wav.save_to_wav(path)


func _discard_probe_preamble() -> void:
	# Scene construction and route setup are outside the 37/42 s evidence interval.
	if premaster_capture != null:
		var premaster_available := premaster_capture.get_frames_available()
		if premaster_available > 0:
			premaster_capture.clear_buffer()
	if master_capture != null:
		var master_available := master_capture.get_frames_available()
		if master_available > 0:
			master_capture.clear_buffer()
	premaster_samples.clear()
	master_samples.clear()
	premaster_chunks.clear()
	master_chunks.clear()
	premaster_frames = 0
	premaster_peak = 0.0
	premaster_over_unity = 0
	premaster_invalid_sample = false
	premaster_discarded_frames = 0
	premaster_max_step = 0.0
	premaster_steps_over_08 = 0
	master_peak = 0.0
	master_over_unity = 0
	master_max_step = 0.0
	master_steps_over_08 = 0
	master_invalid_sample = false
	master_discarded_frames = 0
	pcm_frames_captured = 0
	_last_telemetry_wall_s = -INF
	glow_skips_supported = false
	glow_skips_last = -1
	glow_skips_max = 0
	glow_skips_positive_deltas = 0
	glow_skip_counter_source = "unavailable"
	glow_pump_stats_supported = false
	glow_pump_stats_last.clear()
	glow_pump_error_messages.clear()
	glow_pump_queue_min_frames = -1
	glow_pump_queue_max_frames = -1
	glow_pump_unprimed_samples = 0
	continuous_command_last.clear()
	continuous_phase_last = ""


func _finalize_capture_samples() -> void:
	premaster_samples.clear()
	for chunk: PackedVector2Array in premaster_chunks:
		premaster_samples.append_array(chunk)
	premaster_chunks.clear()
	master_samples.clear()
	for chunk: PackedVector2Array in master_chunks:
		master_samples.append_array(chunk)
	master_chunks.clear()
	pcm_frames_captured = master_samples.size()
	premaster_frames = premaster_samples.size()
	premaster_peak = 0.0
	premaster_over_unity = 0
	premaster_max_step = 0.0
	premaster_steps_over_08 = 0
	var previous := Vector2.ZERO
	var has_previous := false
	for index: int in premaster_samples.size():
		var sample := premaster_samples[index]
		if not is_finite(sample.x) or not is_finite(sample.y):
			premaster_invalid_sample = true
			sample = Vector2.ZERO
			premaster_samples[index] = sample
		var level := maxf(absf(sample.x), absf(sample.y))
		premaster_peak = maxf(premaster_peak, level)
		if level >= 1.0:
			premaster_over_unity += 1
		if has_previous:
			var step := maxf(absf(sample.x - previous.x), absf(sample.y - previous.y))
			premaster_max_step = maxf(premaster_max_step, step)
			if step >= 0.8:
				premaster_steps_over_08 += 1
		previous = sample
		has_previous = true
	master_peak = 0.0
	master_over_unity = 0
	master_max_step = 0.0
	master_steps_over_08 = 0
	master_invalid_sample = false
	previous = Vector2.ZERO
	has_previous = false
	for index: int in master_samples.size():
		var sample := master_samples[index]
		if not is_finite(sample.x) or not is_finite(sample.y):
			master_invalid_sample = true
			sample = Vector2.ZERO
			master_samples[index] = sample
		var level := maxf(absf(sample.x), absf(sample.y))
		master_peak = maxf(master_peak, level)
		if level >= 1.0:
			master_over_unity += 1
		if has_previous:
			var step := maxf(absf(sample.x - previous.x), absf(sample.y - previous.y))
			master_max_step = maxf(master_max_step, step)
			if step >= 0.8:
				master_steps_over_08 += 1
		previous = sample
		has_previous = true


func _contact_summary() -> Dictionary:
	var ground := _ground_snapshot()
	var contacts: Array = ground.get("contacts", [])
	var grounded := 0
	var rolling := 0
	var peak_speed := 0.0
	var peak_normal_force := 0.0
	for contact: Dictionary in contacts:
		if bool(contact.get("grounded", contact.get("touching", false))):
			grounded += 1
		if bool(contact.get("roll_enabled", false)):
			rolling += 1
		var velocity: Variant = contact.get("velocity_mps", Vector3.ZERO)
		if velocity is Vector3:
			peak_speed = maxf(peak_speed, velocity.length())
		peak_normal_force = maxf(peak_normal_force, float(contact.get("normal_force_n", contact.get("normal_load_n", 0.0))))
	if contacts.is_empty() and not rotorcraft:
		var session: Node = scene.session
		var compressions: PackedFloat64Array = session.gear_compressions(session.sim.state)
		for compression: float in compressions:
			if compression > 0.0:
				grounded += 1
	return {count = contacts.size(), grounded = grounded, rolling = rolling,
		peak_contact_speed_mps = peak_speed, peak_normal_force_n = peak_normal_force,
		tick = int(ground.get("tick", -1))}


func _record_frame(t: float) -> void:
	var session: Node = scene.session
	var wall_t := sequence_wall_elapsed_s
	var snapshot: Dictionary = adapter.call("snapshot") if adapter.has_method("snapshot") else {}
	var contacts := _contact_summary()
	var grounded := int(contacts.grounded)
	if stage in ["takeoff", "flight"] and not staged_flight_fixture_ok and grounded == 0 and _height_m() > 1.0:
		takeoff_seen = true
	if stage in ["landing", "rollout", "settle"]:
		if grounded > 0:
			touchdown_seen = true
			if stage in ["rollout", "settle"]:
				rollout_contact_seen = true
	var soundscape: Node = adapter.get("soundscape") as Node
	var source: Vector3 = snapshot.get("source", Vector3.ZERO)
	var listener: Vector3 = snapshot.get("listener", Vector3.ZERO)
	var pitch_scale := 1.0
	var volume_db := -120.0
	if soundscape != null:
		var powertrain: Node = soundscape.get("powertrain") as Node
		if powertrain != null and not powertrain.get("players").is_empty():
			var bank_player: AudioStreamPlayer3D = powertrain.get("players")[0]
			pitch_scale = bank_player.pitch_scale
			volume_db = bank_player.volume_db
		else:
			var glow: AudioStreamPlayer3D = soundscape.get("glow_player") as AudioStreamPlayer3D
			if glow != null:
				pitch_scale = glow.pitch_scale
				volume_db = glow.volume_db
			elif soundscape.get("voices").size() > 0:
				var legacy: AudioStreamPlayer3D = soundscape.get("voices")[0]
				pitch_scale = legacy.pitch_scale
				volume_db = legacy.volume_db
	bench_rows.append([wall_t, float(snapshot.get("rpm", 0.0)), source.distance_to(listener),
		pitch_scale, volume_db, float(soundscape.get("last_doppler")) if soundscape != null else 1.0])
	if wall_t - _last_telemetry_wall_s < 0.09:
		return
	_last_telemetry_wall_s = wall_t
	var glow_pump_stats := _glow_generator_stats(soundscape)
	var current_glow_skips := int(glow_pump_stats.get("skips", -1))
	if current_glow_skips < 0:
		current_glow_skips = _glow_generator_skips(soundscape)
	if current_glow_skips >= 0:
		glow_skips_supported = true
		if glow_skips_last >= 0 and current_glow_skips > glow_skips_last:
			glow_skips_positive_deltas += current_glow_skips - glow_skips_last
		glow_skips_last = current_glow_skips
		glow_skips_max = maxi(glow_skips_max, current_glow_skips)
	if glow_pump_stats.has("running"):
		glow_pump_stats_supported = true
		glow_pump_stats_last = glow_pump_stats.duplicate(true)
		var worker_error := str(glow_pump_stats.get("worker_error", ""))
		if not worker_error.is_empty() and not glow_pump_error_messages.has(worker_error):
			glow_pump_error_messages.append(worker_error)
		if glow_pump_stats.has("queue_frames"):
			var queue_frames := int(glow_pump_stats.get("queue_frames", 0))
			glow_pump_queue_min_frames = queue_frames if glow_pump_queue_min_frames < 0 else mini(glow_pump_queue_min_frames, queue_frames)
			glow_pump_queue_max_frames = maxi(glow_pump_queue_max_frames, queue_frames)
		if glow_pump_stats.has("primed") and not bool(glow_pump_stats.get("primed", false)):
			glow_pump_unprimed_samples += 1
	var targets: Dictionary = {}
	var powertrain: Node = null
	if soundscape != null:
		powertrain = soundscape.get("powertrain") as Node
		if powertrain != null:
			var value: Variant = powertrain.get("last_targets")
			if value is Dictionary:
				targets = value
	var accepted_tick := int(session.sim.tick)
	var continuous_control: Dictionary = {}
	if continuous_mode:
		var state: PackedFloat64Array = session.sim.state
		var attitude: PackedFloat64Array = Math3D.q_to_euler(state.slice(RB.ATT, RB.ATT + 4))
		var world_velocity: PackedFloat64Array = Math3D.q_rotate(state.slice(RB.ATT, RB.ATT + 4),
			state.slice(RB.VEL, RB.VEL + 3))
		var flown_command: Dictionary = session.commands.duplicate(true)
		var surface_command: Dictionary = {}
		if session.has_method("flown_commands"):
			flown_command = session.flown_commands()
		if session.has_method("surfaces"):
			surface_command = session.surfaces()
		if continuous_helicopter_mode and continuous_pilot != null:
			var pilot_status: Dictionary = continuous_pilot.call("status")
			continuous_phase_last = str(pilot_status.get("phase", ""))
			continuous_command_last = pilot_status.get("commands", {}).duplicate(true)
		continuous_control = {pilot_phase = continuous_phase_last,
			pilot_command = continuous_command_last, flown_command = flown_command,
			surface_command = surface_command, pitch_rad = attitude[1],
			pitch_rate_rad_s = state[RB.RATE + 1], vertical_speed_mps = -world_velocity[2],
			position_north_m = state[RB.POS], position_east_m = state[RB.POS + 1]}
	rows.append({frame = frame, t = wall_t, sequence_time_s = t, sim_time_s = float(session.sim.time()),
		tick = accepted_tick, session_epoch = session_epoch, stage = stage,
		rpm = float(snapshot.get("rpm", 0.0)), running = bool(snapshot.get("running", false)),
		throttle = float(snapshot.get("throttle", 0.0)), speed_mps = _speed_mps(),
		height_m = _height_m(), paused = bool(session.sim.paused),
		fault = str(session.sim.fault_reason), crash = not session.crash.is_empty(),
		contacts = contacts, powertrain = targets, audio_mix = _audio_mix_summary(soundscape),
		pcm_clock = _pcm_clock_snapshot(),
		continuous_control = continuous_control,
		glow_generator_skips = current_glow_skips,
		source_distance_m = source.distance_to(listener),
		audio_pitch_scale = pitch_scale, audio_player_volume_db = volume_db,
		glow_pump = glow_pump_stats})
	previous_grounded = grounded


func _glow_generator_skips(soundscape: Node) -> int:
	if soundscape == null:
		return -1
	var pump_stats := _glow_generator_stats(soundscape)
	if pump_stats.has("skips"):
		glow_skip_counter_source = "glow_pump.stats().skips"
		return int(pump_stats.get("skips", -1))
	var glow: AudioStreamPlayer3D = soundscape.get("glow_player") as AudioStreamPlayer3D
	if glow == null or not glow.playing:
		return -1
	var playback: Variant = glow.get_stream_playback()
	if playback == null or not playback.has_method("get_skips"):
		return -1
	glow_skip_counter_source = "AudioStreamGeneratorPlayback.get_skips()"
	return int(playback.call("get_skips"))


func _glow_generator_stats(soundscape: Node) -> Dictionary:
	if soundscape == null:
		return {}
	var pump: Variant = _optional_property(soundscape, "glow_pump")
	if pump == null or not pump.has_method("stats"):
		return {}
	var stats: Variant = pump.call("stats")
	if stats is Dictionary:
		glow_skip_counter_source = "glow_pump.stats().skips"
		return stats.duplicate(true)
	return {}


func _optional_property(target: Object, property_name: String) -> Variant:
	for property: Dictionary in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return target.get(property_name)
	return null


func _audio_mix_summary(soundscape: Node) -> Dictionary:
	var engine_level := 0.0
	var mix_engine_level := -100.0
	var engine_level_available := false
	var engine_level_source := "unavailable"
	if soundscape != null:
		var powertrain: Node = soundscape.get("powertrain") as Node
		if powertrain != null:
			var targets: Variant = powertrain.get("last_targets")
			if targets is Dictionary:
				engine_level = float(targets.get("level", 0.0))
				engine_level_available = true
				engine_level_source = "powertrain.last_targets.level"
			if not powertrain.get("players").is_empty():
				mix_engine_level = (powertrain.get("players")[0] as AudioStreamPlayer3D).volume_db
		else:
			var glow_level: Variant = _optional_property(soundscape, "_glow_level")
			var glow_player: AudioStreamPlayer3D = soundscape.get("glow_player") as AudioStreamPlayer3D
			if glow_player != null and glow_level != null:
				engine_level = float(glow_level)
				mix_engine_level = glow_player.volume_db
				engine_level_available = true
				engine_level_source = "soundscape._glow_level"
	var ground_slots := 0
	var ground_roll_gain := 0.0
	var active_impact_count := 0
	var ground_audio: Node = adapter.get("ground_audio") as Node if adapter != null else null
	if ground_audio != null:
		for slot: Dictionary in ground_audio.get("_slots"):
			ground_slots += 1
			for layer_gain: float in slot.get("layer_gain", []):
				ground_roll_gain += layer_gain
			var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
			if impact != null and impact.playing:
				active_impact_count += 1
	return {engine_gain_model = engine_level, engine_gain_available = engine_level_available,
		engine_gain_source = engine_level_source, engine_player_db = mix_engine_level,
		gear_roll_gain_model_sum = ground_roll_gain, gear_touchdown_players = active_impact_count,
		gear_contact_slots = ground_slots}


func _height_m() -> float:
	var session: Node = scene.session
	var state: PackedFloat64Array = session.sim.state
	if state.size() <= RB.POS + 2:
		return 0.0
	var altitude := -state[RB.POS + 2]
	if not rotorcraft and session.get("environment") != null:
		altitude -= float(session.environment.terrain(state[RB.POS], state[RB.POS + 1])[0])
	return altitude


func _speed_mps() -> float:
	var session: Node = scene.session
	var state: PackedFloat64Array = session.sim.state
	if state.size() < RB.VEL + 3:
		return 0.0
	return Math3D.norm(Math3D.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))


func _audio_source_info() -> Dictionary:
	var soundscape: Node = adapter.get("soundscape") as Node
	if soundscape == null:
		return {source = "none", recorded_layers = 0, fallback = false}
	var powertrain: Node = soundscape.get("powertrain") as Node
	var layer_count := 0
	var bank_family := ""
	if powertrain != null:
		var layers: Variant = powertrain.get("layers")
		if layers is Array:
			layer_count = layers.size()
		var profile: Variant = powertrain.get("profile")
		if profile is Dictionary:
			bank_family = str(profile.get("family", ""))
	var glow_player: Variant = soundscape.get("glow_player")
	var source := "recorded-bank" if layer_count > 0 else ("glow-fallback" if glow_player != null else "procedural-or-legacy")
	return {source = source, recorded_layers = layer_count, bank_family = bank_family,
		fallback = layer_count == 0 and glow_player != null}


func _report(timeline: Array) -> Dictionary:
	var session: Node = scene.session
	var route := "continuous-heli20-ground-hover-cycle" if continuous_helicopter_mode else ("helicopter-ground-lifecycle" if rotorcraft else ("continuous-ft-card-v5-straight-ahead" if continuous_straight_mode else ("continuous-stik-takeoffpilot-e3c2a" if continuous_mode else "runway-plus-staged-approach")))
	var source_info := _audio_source_info()
	var source_path := "res://audio/helicopter_audio.gd" if rotorcraft else "res://audio/flight_audio.gd"
	var trace_identity: Dictionary = session.trace_meta()
	var field: Dictionary = scene.get("field") if not rotorcraft else {}
	var aircraft_identity: Dictionary
	if rotorcraft:
		aircraft_identity = {
			"identity_contract": "rotorcraft-input-and-law-v1",
			"vehicle": "rotorcraft",
			"aircraft": str(trace_identity.get("aircraft_id", aircraft_id)),
			"input_sha256": str(trace_identity.get("aircraft_sha256", "")),
			"semantic_identity": "not defined by the rotorcraft data loader",
			"model_law": str(trace_identity.get("law", "")),
			"lifecycle_law": str(trace_identity.get("lifecycle_law", "")),
			"configuration": str(trace_identity.get("law", "")) + "/" + str(trace_identity.get("lifecycle_law", "")),
			"qualification": str(trace_identity.get("qualification", "")),
			"accepted_weather": session.weather_configuration(),
			"launch_choice": str(trace_identity.get("start_choice", "unknown")),
			"pad": trace_identity.get("pad", {}),
			"continuous_layout": str(trace_identity.get("continuous_layout", "")),
		}
	else:
		aircraft_identity = {
			"identity_contract": "airplane-semantic-identity-v1",
			"vehicle": "fixed-wing",
			"aircraft": str(trace_identity.get("aircraft", aircraft_id)),
			"input_file_sha256": str(trace_identity.get("aircraft_input_sha256", "unavailable")),
			"semantic_data_sha256": str(trace_identity.get("aircraft_semantic_sha256", "unavailable")),
			"configuration": str(trace_identity.get("configuration", "unspecified")),
			"field_id": str(field.get("id", trace_identity.get("launch_field_id", ""))),
			"runway_id": str(field.get("runway", "")),
			"accepted_weather": session.weather_configuration(),
			"launch_choice": str(trace_identity.get("launch_choice", "unknown")),
		}
	return {
		format = "openrc-audio-fleet-sequence-v1", aircraft = aircraft_id, vehicle = "rotorcraft" if rotorcraft else "fixed-wing",
		route_mode = "continuous" if continuous_mode else "staged-presentation",
		continuous_pilot = ("tools/audio/helicopter_sequence_pilot.gd (HELI-20 X-Cell ground cycle)" if continuous_helicopter_mode else ("tools/audio/straight_flight_pilot.gd (research FT-card-v5 laws)" if continuous_straight_mode else "research/landing/e3c2a/circuit_pilot.gd")) if continuous_mode else "",
		continuous_takeoff_pilot = ("HELI-20 ground-start/spool law; lift checked from live skid contacts" if continuous_helicopter_mode else ("research FT-card-v5 direct takeoff phase" if continuous_straight_mode else "app/scenery/takeoff_pilot.gd through verified 0.1 s gear separation")) if continuous_mode else "",
		continuous_route_kind = "heli20-ground-hover-cycle" if continuous_helicopter_mode else ("straight-ahead-terrain-landing" if continuous_straight_mode else ("experimental-stik-circuit" if continuous_mode else "staged-presentation")),
		continuous_post_landing_soak_s = continuous_post_landing_soak_s,
		continuous_post_landing_soak_elapsed_s = maxf(sequence_elapsed_s - continuous_post_landing_soak_started_s, 0.0) if continuous_post_landing_soak_started_s >= 0.0 else 0.0,
		continuous_takeoff_handoff = continuous_takeoff_handoff,
		continuous_takeoff_separated = continuous_takeoff_separated,
		continuous_takeoff_timeout_reached = continuous_takeoff_timeout_reached,
		continuous_pilot_failure_reason = continuous_pilot_failure_reason,
		sequence_interrupted_by_pilot_failure = sequence_interrupted_by_pilot_failure,
		continuous_pilot_status = continuous_pilot.call("status") if continuous_helicopter_mode and continuous_pilot != null else {},
		continuous_control_semantics = _continuous_control_semantics if continuous_mode else "production input rate-command interface",
		aircraft_identity = aircraft_identity,
		continuous_route_completed = continuous_mode and continuous_done and session_epoch == 0 and not sequence_interrupted_by_route_failure,
		expected_stage_order = CONTINUOUS_HELICOPTER_STAGE_ORDER if continuous_helicopter_mode else (CONTINUOUS_STAGE_ORDER if continuous_mode else []),
		godot = Engine.get_version_info().string, fps = capture_fps, mix_rate = AudioServer.get_mix_rate(),
		driver = AudioServer.get_driver_name(), frames = frame, duration_s = sequence_wall_elapsed_s,
		scheduled_duration_s = sequence_duration_s, accepted_sequence_s = sequence_elapsed_s,
		wall_timeout_s = sequence_wall_timeout_s, wall_timeout_reached = wall_timeout_reached,
		sequence_interrupted_by_route_failure = sequence_interrupted_by_route_failure,
		wall_elapsed_s = sequence_wall_elapsed_s, session_epochs = session_epoch + 1,
		pcm_wav = {path = str(args.out) + ".wav", sample_format = "signed PCM16 stereo",
			frames = master_samples.size(), seconds = float(master_samples.size()) / float(AudioServer.get_mix_rate()),
		ideal_frames_if_wall_time_equals_timeline = roundi(sequence_duration_s * float(AudioServer.get_mix_rate())),
		captured_frames = pcm_frames_captured,
			discarded_frames = master_discarded_frames, peak_linear = master_peak,
			peak_dbfs = linear_to_db(maxf(master_peak, 0.0000001)), over_unity_samples = master_over_unity,
			max_sample_step = master_max_step, sample_steps_over_0_8 = master_steps_over_08,
			invalid_sample_seen = master_invalid_sample,
			meaning = "AudioEffectCapture appended after configured Master bus effects; PCM is software output, not acoustic calibration."},
		pcm_clock = final_pcm_clock,
		route = route, staged_landing_fixture = landing_fixture_ok,
		staged_flight_fixture = staged_flight_fixture_ok,
		staged_flight_fixture_message = staged_flight_fixture_message,
		landing_fixture_message = landing_fixture_message,
		actual_contact_after_landing_stage = touchdown_seen, rollout_or_settle_contact_observed = rollout_contact_seen,
		landing_rollout_not_applicable = rotorcraft, actual_liftoff_observed = takeoff_seen,
		actual_runway_takeoff_observed = takeoff_seen if not rotorcraft else false,
		actual_rotor_liftoff_observed = takeoff_seen if rotorcraft else false,
		rotor_start = rotor_start_diagnostics,
		start_state = "accepted session snapshot; non-glow combustion start/stop are bench engine_running latch stimuli",
		start_choice = "ground" if rotorcraft else "runway", initial_stage_schedule = timeline,
		audio_source = source_info, contacts = _contact_summary(), events = events, samples = rows,
		telemetry_rate_hz = float(rows.size()) / maxf(sequence_wall_elapsed_s, 1e-9),
		columns = ["t", "rpm", "distance_m", "motor_pitch_scale", "motor_volume_db", "doppler"],
		rows = bench_rows,
		premaster = {frames = premaster_frames, peak_linear = premaster_peak,
			peak_dbfs = linear_to_db(maxf(premaster_peak, 0.0000001)), over_unity_samples = premaster_over_unity,
			discarded_frames = premaster_discarded_frames,
			invalid_sample_seen = premaster_invalid_sample,
			max_sample_step = premaster_max_step, sample_steps_over_0_8 = premaster_steps_over_08,
			meaning = "AudioEffectCapture on the soundscape sum before the Master limiter; sample-step threshold is a screening statistic, not a perceptual click verdict."},
		physics_ticks_per_second = Engine.physics_ticks_per_second,
		glow_generator = {skip_counter_supported = glow_skips_supported,
			counter_source = glow_skip_counter_source,
			max_observed_skips = glow_skips_max, last_observed_skips = glow_skips_last,
			positive_skip_delta_sum = glow_skips_positive_deltas,
			pump_stats_supported = glow_pump_stats_supported,
			pump_last_status = glow_pump_stats_last,
			worker_error_messages = glow_pump_error_messages,
			queue_frames_min = glow_pump_queue_min_frames,
			queue_frames_max = glow_pump_queue_max_frames,
			unprimed_telemetry_samples = glow_pump_unprimed_samples,
			meaning = "AudioStreamGeneratorPlayback.get_skips() readings are sampled with telemetry; they screen source starvation but are not a direct acoustic test."},
		fault = str(session.sim.fault_reason), crash = not session.crash.is_empty(),
		route_failure = {crash_observed = route_crash_observed, fault_observed = route_fault_observed,
			stage = route_failure_stage, reason = route_failure_reason,
			session_epoch = route_failure_epoch, tick = route_failure_tick,
			episodes = route_failure_history.duplicate(true),
			terminal = {active = _route_failure_active(session), stage = stage,
				session_epoch = session_epoch, tick = int(session.sim.tick),
				crash = _crash_summary(session.crash), fault_reason = str(session.sim.fault_reason)},
		},
		audio_seed = 15015,
		focus_resumes = focus_resumes,
		notes = notes, audio_adapter_sha256 = FileAccess.get_sha256(source_path),
		note = "Native WASAPI AudioEffectCapture PCM from the production adapter, with no Movie Maker render. Staged fixed-wing mode may stage an airborne segment and resets to a descending approach fixture before live landing contacts. Continuous fixed-wing modes keep one session; the FT-card-v5 straight route lands on terrain ahead, and the E3c2a circuit is a Stik-specific experimental route. The HELI-20 cycle is limited to the X-Cell ground-start hover sequence and does not claim wheel taxi. Helicopter identity uses its input-byte digest plus its explicit model/lifecycle laws; no semantic-data digest is defined by that loader. Engine gain and gear roll rows are normalized runtime diagnostics; gear shares the aircraft bus, so no separate gear PCM is claimed. Audio captures are software evidence, not speaker or acoustic validation.",
	}
