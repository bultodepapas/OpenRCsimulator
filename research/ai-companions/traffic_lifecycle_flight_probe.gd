## Research-only stopped-peer A/B using actual FlightSession stepping and FlightLog.
## This intentionally bypasses CompanionManager/profile admission and makes no production qualification claim.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const AGENT_CURRENT := "res://ai/companions/agent.gd"
const PILOT_CURRENT := "res://ai/companions/pilot.gd"
const TICKS_PER_SECOND := 240
const FLIGHT_SECONDS := 12
const STOPPED_PEER_AHEAD_M := 45.0
const SEED := 20261020

var _output := ""
var _baseline_agent_path := ""
var _baseline_pilot_path := ""
var _peer_ahead_m := STOPPED_PEER_AHEAD_M
var _field: Dictionary = {}
var _lake: Dictionary = {}
var _collision_world: Dictionary = {}
var _weather: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parse_only := false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--parse-only":
			parse_only = true
		elif argument.begins_with("--out="):
			_output = argument.trim_prefix("--out=")
		elif argument.begins_with("--baseline-agent="):
			_baseline_agent_path = argument.trim_prefix("--baseline-agent=")
		elif argument.begins_with("--baseline-pilot="):
			_baseline_pilot_path = argument.trim_prefix("--baseline-pilot=")
		elif argument.begins_with("--distance="):
			_peer_ahead_m = argument.trim_prefix("--distance=").to_float()
	if _baseline_agent_path.is_empty() or _baseline_pilot_path.is_empty():
		_fail("Supply external --baseline-agent=<path> and --baseline-pilot=<path> sources.", 2)
		return
	if not is_finite(_peer_ahead_m) or _peer_ahead_m < 20.0 or _peer_ahead_m > 200.0:
		_fail("--distance must be finite and between 20 and 200 metres.", 2)
		return
	if parse_only:
		var baseline_agent: Script = ResourceLoader.load(_baseline_agent_path) as Script
		var baseline_pilot: Script = ResourceLoader.load(_baseline_pilot_path) as Script
		print("STOPPED PEER PROBE PARSE OK; external baseline resources: %s %s" % [
			str(baseline_agent != null and baseline_agent.can_instantiate()),
			str(baseline_pilot != null and baseline_pilot.can_instantiate())])
		quit(0 if baseline_agent != null and baseline_pilot != null else 1)
		return
	if _output.is_empty() or not _output.is_absolute_path():
		_fail("Supply --out=<new absolute directory>.", 2)
		return
	if DirAccess.dir_exists_absolute(_output) or FileAccess.file_exists(_output):
		_fail("Output must be a new directory.", 2)
		return
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field_result.get("ok", false) or not lake_result.get("ok", false):
		_fail("Accepted field/lake load failed.")
		return
	_field = field_result.field
	_lake = lake_result.lake
	var collision_result: Dictionary = CollisionSetup.build(_field)
	if not collision_result.get("ok", false):
		_fail("Collision fixture failed: %s" % str(collision_result.get("errors", [])))
		return
	_collision_world = collision_result.world
	_weather = WeatherConfig.preset("calm")
	if DirAccess.make_dir_absolute(_output) != OK:
		_fail("Could not create output directory.")
		return
	var baseline_agent: Script = ResourceLoader.load(_baseline_agent_path) as Script
	var baseline_pilot: Script = ResourceLoader.load(_baseline_pilot_path) as Script
	var current_agent: Script = ResourceLoader.load(AGENT_CURRENT) as Script
	var current_pilot: Script = ResourceLoader.load(PILOT_CURRENT) as Script
	for candidate: Script in [baseline_agent, baseline_pilot, current_agent, current_pilot]:
		if candidate == null or not candidate.can_instantiate():
			_fail("A baseline/candidate Agent or Pilot resource could not be instantiated.")
			return
	var baseline: Dictionary = _run_case("baseline", baseline_agent, baseline_pilot)
	var candidate: Dictionary = _run_case("candidate", current_agent, current_pilot)
	var report := {
		"format": "openrc-stopped-peer-flight-probe v1",
		"purpose": "Research-only A/B of a stopped FlightSession peer; not an admitted production companion flight or physical validation.",
		"production_admission": false,
		"engine": Engine.get_version_info().string,
		"physics_hz": TICKS_PER_SECOND,
		"weather": "calm",
		"field_id": str(_field.get("id", "")),
		"aircraft_id": AIRCRAFT_ID,
		"seed": SEED,
		"flight_seconds": FLIGHT_SECONDS,
		"scenario": {"peer_state": "real trimmed FlightSession spawned at the tick-zero reset boundary, then stopped before its first accepted tick by a research fixture failure flag", "peer_initial_ahead_m": _peer_ahead_m, "peer_heading": "same as the AI initial course", "peer_velocity_in_frozen_state_m_s": 15.0, "actual_metric": "AI-to-peer FlightSession 3D center distance sampled every accepted AI tick; not hull clearance"},
		"identity": {
			"baseline_agent_path": _baseline_agent_path,
			"baseline_agent_sha256": _source_sha256(_baseline_agent_path),
			"baseline_pilot_path": _baseline_pilot_path,
			"baseline_pilot_sha256": _source_sha256(_baseline_pilot_path),
			"candidate_agent_path": AGENT_CURRENT,
			"candidate_agent_sha256": _source_sha256(AGENT_CURRENT),
			"candidate_pilot_path": PILOT_CURRENT,
			"candidate_pilot_sha256": _source_sha256(PILOT_CURRENT),
			"aircraft_path": AIRCRAFT_PATH,
			"aircraft_sha256": _source_sha256(AIRCRAFT_PATH),
			"field_path": FieldLoader.DEFAULT_PATH,
			"field_sha256": _source_sha256(FieldLoader.DEFAULT_PATH),
			"lake_path": LakeLoader.DEFAULT_PATH,
			"lake_sha256": _source_sha256(LakeLoader.DEFAULT_PATH),
			"probe_path": (get_script() as Script).resource_path,
			"probe_sha256": _source_sha256((get_script() as Script).resource_path),
		},
		"baseline": baseline,
		"candidate": candidate,
		"candidate_minus_baseline_min_center_distance_m": float(candidate.get("min_center_distance_m", NAN)) - float(baseline.get("min_center_distance_m", NAN)),
		"runs_complete": bool(baseline.get("complete", false)) and bool(candidate.get("complete", false)),
	}
	var report_path: String = _output.path_join("report.json")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write report: %s" % report_path)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.flush()
	file.close()
	print("STOPPED PEER REPORT %s" % report_path)
	print("STOPPED PEER RESULTS baseline_min=%.6f candidate_min=%.6f delta=%.6f complete=%s" % [
		float(baseline.get("min_center_distance_m", NAN)), float(candidate.get("min_center_distance_m", NAN)),
		float(report.candidate_minus_baseline_min_center_distance_m), str(report.runs_complete)])
	quit(0 if report.runs_complete else 1)


func _run_case(label: String, agent_script: Script, pilot_script: Script) -> Dictionary:
	var case_dir: String = _output.path_join(label)
	if DirAccess.make_dir_absolute(case_dir) != OK:
		return {"complete": false, "failure": "case output directory could not be created"}
	var own_build: Dictionary = _new_session()
	var peer_build: Dictionary = _new_session()
	if not own_build.get("ok", false) or not peer_build.get("ok", false):
		return {"complete": false, "failure": str(own_build.get("error", peer_build.get("error", "session setup failed")))}
	var own: Node = own_build.session
	var peer: Node = peer_build.session
	var pilot: RefCounted = pilot_script.new()
	var trim: Dictionary = own.start.duplicate(true)
	if not pilot.configure(0, 2, SEED, trim, _field):
		own.free()
		peer.free()
		return {"complete": false, "failure": "pilot configuration refused: " + str(pilot.configure_error)}
	var pose: Dictionary = pilot.initial_pose()
	if not pose.get("ok", false) or not _spawn(own, float(pose.north), float(pose.east), float(pose.height_m), float(pose.heading_rad)):
		own.free()
		peer.free()
		return {"complete": false, "failure": "AI FlightSession airborne reset-boundary spawn failed"}
	var attitude: PackedFloat64Array = Math3D.q_from_euler(float(pose.heading_rad), 0.0, 0.0)
	var forward: PackedFloat64Array = Math3D.q_rotate(attitude, PackedFloat64Array([1.0, 0.0, 0.0]))
	var peer_north: float = float(pose.north) + _peer_ahead_m * forward[0]
	var peer_east: float = float(pose.east) + _peer_ahead_m * forward[1]
	if not _spawn(peer, peer_north, peer_east, float(pose.height_m), float(pose.heading_rad)):
		own.free()
		peer.free()
		return {"complete": false, "failure": "stopped peer FlightSession airborne spawn failed"}
	var own_agent: Node = agent_script.new()
	own_agent.slot_id = 0
	own_agent.session = own
	own_agent.pilot = pilot
	own_agent._accepted_trim = trim.duplicate(true)
	var peer_agent: Node = agent_script.new()
	peer_agent.slot_id = 1
	peer_agent.session = peer
	peer_agent.failure = "research fixture: stopped before first accepted tick"
	var own_log: RefCounted = FlightLog.new(own)
	var peer_log: RefCounted = FlightLog.new(peer)
	var own_path: String = case_dir.path_join("ai.orfl")
	var peer_path: String = case_dir.path_join("stopped-peer.orfl")
	if own_log.start(own_path) != OK or peer_log.start(peer_path) != OK:
		own.free()
		peer.free()
		return {"complete": false, "failure": "FlightLog could not start", "ai_log": own_path, "peer_log": peer_path}
	own_log.mark("stopped-peer research case: " + label)
	peer_log.mark("stopped-peer research fixture: held before first accepted tick")
	var min_distance := INF
	var min_horizontal := INF
	var min_vertical := INF
	var first_held_tick: Variant = null
	var held_maneuver_samples := 0
	var refusal := ""
	var min_agl := INF
	var peak_bank_deg := 0.0
	var initial_distance: float = _distance(own.sim.state, peer.sim.state)
	var ticks := 0
	for tick in range(FLIGHT_SECONDS * TICKS_PER_SECOND):
		var snapshot: Dictionary = _snapshot(own, trim)
		var traffic: Array = [own_agent.observation(), peer_agent.observation()]
		if not own_agent.prepare(snapshot, tick, traffic):
			refusal = "Agent.prepare failed at tick %d: %s" % [tick, own_agent.failure]
			break
		if tick % 4 == 0:
			var controller_state: Dictionary = pilot.snapshot_state()
			if bool(controller_state.get("has_held_maneuver", false)):
				held_maneuver_samples += 1
				if first_held_tick == null:
					first_held_tick = tick
		if not own_agent.advance():
			refusal = "Agent.advance failed at tick %d: %s" % [tick, own_agent.failure]
			break
		ticks += 1
		var distance_components: PackedFloat64Array = _distance_components(own.sim.state, peer.sim.state)
		min_distance = minf(min_distance, distance_components[0])
		min_horizontal = minf(min_horizontal, distance_components[1])
		min_vertical = minf(min_vertical, distance_components[2])
		var terrain: PackedFloat64Array = own.environment.terrain(own.sim.state[RigidBody.POS], own.sim.state[RigidBody.POS + 1])
		if terrain.is_empty() or not is_finite(terrain[0]):
			refusal = "invalid terrain query at tick %d" % ticks
			break
		min_agl = minf(min_agl, -own.sim.state[RigidBody.POS + 2] - terrain[0])
		var euler: PackedFloat64Array = Math3D.q_to_euler(Math3D.quat(own.sim.state[6], own.sim.state[7], own.sim.state[8], own.sim.state[9]))
		if euler.size() == 3:
			peak_bank_deg = maxf(peak_bank_deg, absf(rad_to_deg(euler[2])))
		if not own.crash.is_empty() or not str(own.sim.fault_reason).is_empty():
			refusal = "AI terminal state at tick %d: crash=%s fault=%s" % [ticks, str(own.crash), str(own.sim.fault_reason)]
			break
		if (ticks % TICKS_PER_SECOND) == 0:
			print("STOPPED_PEER_SAMPLE %s tick=%d t=%.1f distance=%.3f held=%d" % [label, ticks, float(ticks) / TICKS_PER_SECOND, distance_components[0], held_maneuver_samples])
	var own_stop: Error = own_log.stop("completed" if refusal.is_empty() else refusal)
	var peer_stop: Error = peer_log.stop("peer intentionally stopped by research fixture")
	var actual_complete: bool = refusal.is_empty() and ticks == FLIGHT_SECONDS * TICKS_PER_SECOND \
		and own_stop == OK and peer_stop == OK and own_log.rows_written > 1 and peer_log.rows_written >= 1
	var result := {
		"agent_source": agent_script.resource_path,
		"agent_source_sha256": _source_sha256(agent_script.resource_path),
		"pilot_source": pilot_script.resource_path,
		"pilot_source_sha256": _source_sha256(pilot_script.resource_path),
		"ticks": ticks,
		"requested_ticks": FLIGHT_SECONDS * TICKS_PER_SECOND,
		"complete": actual_complete,
		"failure": refusal,
		"initial_center_distance_m": initial_distance,
		"min_center_distance_m": min_distance,
		"min_horizontal_center_distance_m": min_horizontal,
		"min_vertical_center_separation_m": min_vertical,
		"min_ai_agl_m": min_agl,
		"peak_abs_bank_deg": peak_bank_deg,
		"first_held_maneuver_tick": first_held_tick,
		"held_maneuver_plan_samples": held_maneuver_samples,
		"ai_final_state_sha256": _state_hash(own),
		"peer_state_tick": int(peer.sim.tick),
		"peer_state_unchanged_during_ai_flight": int(peer.sim.tick) == 0,
		"peer_observation": peer_agent.observation(),
		"flight_logs": {
			"ai": {"path": own_path, "sha256": FileAccess.get_sha256(own_path), "rows": own_log.rows_written, "stop_error": own_stop},
			"stopped_peer": {"path": peer_path, "sha256": FileAccess.get_sha256(peer_path), "rows": peer_log.rows_written, "stop_error": peer_stop},
		},
	}
	own_agent.free()
	peer_agent.free()
	own.free()
	peer.free()
	return result


func _new_session() -> Dictionary:
	var session: Node = FlightSession.new()
	session.start_choice = FlightSession.START_AIRBORNE
	session.input_enabled = false
	session.crash_auto_restart = false
	session.rate_profile = "full"
	if not session.setup_weather(_weather):
		session.free()
		return {"ok": false, "error": "weather setup refused"}
	session.setup(AIRCRAFT_PATH, AIRCRAFT_ID)
	if not session.aircraft.get("ok", false) or not session.set_field(_field) \
			or not session.set_collision_world(_collision_world) or not session.set_lake_context(_lake):
		var reason: String = str(session.aircraft.get("errors", [])) + " " + str(session.surface_error)
		session.free()
		return {"ok": false, "error": "aircraft/world setup refused: " + reason}
	session.reset()
	if session.sim == null or not session.start.get("ok", false) or not session.start_error.is_empty():
		var reason := "trim failed: " + str(session.start_error)
		session.free()
		return {"ok": false, "error": reason}
	return {"ok": true, "session": session}


func _spawn(session: Node, north: float, east: float, altitude_up: float, heading: float) -> bool:
	var terrain: PackedFloat64Array = session.environment.terrain(north, east)
	if terrain.is_empty() or not is_finite(terrain[0]) or not session.configure_external_driver():
		return false
	return session.external_spawn_airborne(north, east, altitude_up - terrain[0], heading)


func _snapshot(session: Node, trim: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var time_s: float = session.sim.time()
	var terrain: PackedFloat64Array = session.environment.terrain(state[RigidBody.POS], state[RigidBody.POS + 1])
	return {"state": state, "airspeed_m_s": float(session.air_data(state, time_s).get("V", NAN)),
		"wind_ned": session.wind_at(time_s),
		"ground_clearance_m": -state[RigidBody.POS + 2] - terrain[0],
		"trim": trim.duplicate(true), "turbulence_rms_m_s": PackedFloat64Array([0.0, 0.0, 0.0])}


func _distance_components(first: PackedFloat64Array, second: PackedFloat64Array) -> PackedFloat64Array:
	var dn: float = first[RigidBody.POS] - second[RigidBody.POS]
	var de: float = first[RigidBody.POS + 1] - second[RigidBody.POS + 1]
	var dd: float = first[RigidBody.POS + 2] - second[RigidBody.POS + 2]
	return PackedFloat64Array([sqrt(dn * dn + de * de + dd * dd), sqrt(dn * dn + de * de), absf(dd)])


func _distance(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	return float(_distance_components(first, second)[0])


func _state_hash(session: Node) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(session.sim.state.to_byte_array())
	digest.update(session.sim.previous.to_byte_array())
	digest.update(session.sim.aux.to_byte_array())
	digest.update(session.sim.continuous.to_byte_array())
	digest.update(session.sim.modes.to_byte_array())
	digest.update(session.sim.inputs.to_byte_array())
	return digest.finish().hex_encode()


func _source_sha256(path: String) -> String:
	var local_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	return FileAccess.get_sha256(local_path)


func _fail(message: String, code := 1) -> void:
	printerr(message)
	quit(code)
