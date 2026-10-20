extends SceneTree

const Config := preload("res://ai/companions/config.gd")
const Pilot := preload("res://ai/companions/pilot.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")
const WindConfig := preload("res://physics/wind_config.gd")

const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const STIK_ID := "jensen-das-ugly-stik-60"
const TICKS_PER_SECOND := 240
const COMMAND_DIVISOR := 4 # pilot is sampled at 60 Hz; the packet is held for four physics ticks.
const FLIGHT_TICKS := 120 * TICKS_PER_SECOND
const SEED := 20261020

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("Club field loads from accepted data", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		quit(1)
		return
	var field: Dictionary = loaded.field
	var rejected := Pilot.new()
	_check("unsupported field is refused", not rejected.configure(0, 1, SEED, {"V": 15.0, "throttle": 0.5}, {"id": "workshop"}))
	_check("invalid slot is refused", not rejected.configure(1, 1, SEED, {"V": 15.0, "throttle": 0.5}, field))
	var missing_trim := Pilot.new()
	_check("missing solved trim is refused", not missing_trim.configure(0, 1, SEED, {}, field))
	var invalid_wind: Dictionary = _flight_packet(rejected, {}, 0, [], PackedFloat64Array())
	_check("unconfigured controller returns a finite bounded refusal packet", not invalid_wind.ok and _packet_bounded(invalid_wind))

	var calm_results: Array = []
	for count in range(1, 4):
		calm_results.append(_run_fleet(field, count, "calm", false))
	var gentle_results: Array = []
	for count in range(1, 4):
		gentle_results.append(_run_fleet(field, count, "gentle-practice", false))
	var deterministic_first: Dictionary = _run_fleet(field, 3, "calm", true)
	var deterministic_second: Dictionary = _run_fleet(field, 3, "calm", true)
	_check("seeded three-aircraft calm replay has bit-identical sampled state and command trace",
		deterministic_first.get("trace", PackedFloat64Array()).to_byte_array()
			== deterministic_second.get("trace", PackedFloat64Array()).to_byte_array())
	_check("seeded replay completes all 120 simulated seconds", deterministic_first.get("ticks", -1) == FLIGHT_TICKS
		and deterministic_second.get("ticks", -1) == FLIGHT_TICKS)
	var refusal_pilot := Pilot.new()
	var reference: Dictionary = _trim_for_field(field, WindConfig.defaults())
	var refusal_field: Dictionary = _session_field(field)
	var refusal_configured: bool = refusal_pilot.configure(0, 1, SEED, reference, refusal_field)
	var refusal_packet: Dictionary = {}
	if refusal_configured:
		var bad_snapshot: Dictionary = {
			"state": PackedFloat64Array([0, 0, -50, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0]),
			"airspeed_m_s": 15.0, "wind_ned": PackedFloat64Array([6, 0, 0]),
			"ground_clearance_m": 50.0, "trim": reference,
		}
		refusal_packet = refusal_pilot.command(bad_snapshot, 0)
	_check("unqualified strong wind is refused with finite safe inputs", refusal_configured
		and not refusal_packet.get("ok", true) and _packet_bounded(refusal_packet))
	var turbulence_packet: Dictionary = {}
	if refusal_configured:
		var turbulence_snapshot: Dictionary = {
			"state": PackedFloat64Array([0, 0, -50, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0]),
			"airspeed_m_s": 15.0, "wind_ned": PackedFloat64Array([0, 0, 0]),
			"ground_clearance_m": 50.0, "trim": reference,
			"turbulence_rms_m_s": PackedFloat64Array([1.0, 0.0, 0.0]),
		}
		turbulence_packet = refusal_pilot.command(turbulence_snapshot, 0)
	_check("unqualified turbulence is refused with finite safe inputs", refusal_configured
		and not turbulence_packet.get("ok", true) and _packet_bounded(turbulence_packet))
	print("companion pilot: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_fleet(field: Dictionary, count: int, weather_id: String, record_trace: bool) -> Dictionary:
	var weather: Dictionary = WindConfig.preset(weather_id)
	var sessions: Array = []
	var pilots: Array = []
	var packets: Array = []
	var trace := PackedFloat64Array()
	var min_clearance := INF
	var max_radius_error: float = 0.0
	var min_player_separation := INF
	var max_control: float = 0.0
	var max_bank: float = 0.0
	var min_pair_separation := INF
	var refusals: int = 0
	var spawn_positions: Array = []
	var player_state: PackedFloat64Array = _player_state(field)
	var player_traffic: Array = [{"id": "player", "is_player": true, "wingspan_m": 1.7, "state": player_state}]
	var stop_reason: String = ""
	for slot in count:
		var session: Node = FlightSession.new()
		session.start_choice = FlightSession.START_AIRBORNE
		session.input_enabled = false
		session.rate_profile = "full"
		if not weather.is_empty():
			var weather_ok: bool = session.setup_weather(weather)
			_check("%s %d-slot weather preset loads" % [weather_id, slot], weather_ok, str(session.weather_error))
		session.setup(STIK_PATH, STIK_ID)
		root.add_child(session)
		session.input_enabled = false
		var field_ok: bool = session.set_field(field)
		_check("%s %d-slot Club field installs" % [weather_id, slot], field_ok, str(session.surface_error))
		session.reset()
		var trim: Dictionary = session.start.duplicate(true)
		var pilot := Pilot.new()
		var configured: bool = pilot.configure(slot, count, SEED, trim, field)
		_check("%s %d-slot pilot accepts the current Stik trim" % [weather_id, slot], configured, str(pilot.configure_error))
		if not configured:
			session.free()
			for old: Node in sessions:
				old.free()
			return {"ticks": 0, "trace": PackedFloat64Array()}
		var pose: Dictionary = pilot.initial_pose()
		var spawn: PackedFloat64Array = session.start.state.duplicate()
		spawn[RigidBody.POS] = float(pose.north)
		spawn[RigidBody.POS + 1] = float(pose.east)
		spawn[RigidBody.POS + 2] = -float(pose.height_m)
		var old_attitude: PackedFloat64Array = Math3D.quat(spawn[RigidBody.ATT], spawn[RigidBody.ATT + 1], spawn[RigidBody.ATT + 2], spawn[RigidBody.ATT + 3])
		var attitude_euler: PackedFloat64Array = Math3D.q_to_euler(old_attitude)
		var new_attitude: PackedFloat64Array = Math3D.q_from_euler(float(pose.heading_rad), attitude_euler[1], attitude_euler[2])
		for axis in 4:
			spawn[RigidBody.ATT + axis] = new_attitude[axis]
		session.start.state = spawn
		session.reset()
		session.sim.set_paused(false)
		var initial_radius_error: float = absf(_radius_error(pose, pilot, slot, count, field))
		_check("%s %d-slot has separated north-side reset pose" % [weather_id, slot], pose.get("ok", false)
			and float(pose.north) > float(field.surfaces[1].center_north) + 30.0
			and float(pose.height_m) >= 35.0 and initial_radius_error < 1e-5)
		sessions.append(session)
		pilots.append(pilot)
		packets.append({})
		spawn_positions.append(pose)

	for tick in FLIGHT_TICKS:
		for slot in count:
			var session: Node = sessions[slot]
			var pilot: Variant = pilots[slot]
			if tick % COMMAND_DIVISOR == 0:
				var snapshot: Dictionary = _snapshot(session, weather)
				var traffic: Array = player_traffic.duplicate()
				for other_slot in count:
					if other_slot == slot:
						continue
					var other_session: Node = sessions[other_slot]
					traffic.append({"id": "companion-%d" % other_slot, "slot": other_slot, "is_player": false,
						"wingspan_m": 1.7, "state": other_session.sim.state.duplicate()})
				var packet: Dictionary = pilot.command(snapshot, tick, traffic)
				if not packet.get("ok", false):
					refusals += 1
					stop_reason = str(packet.get("reason", "pilot refused snapshot"))
				packets[slot] = packet
				var control_peak: float = maxf(maxf(absf(float(packet.get("roll", 0.0))), absf(float(packet.get("pitch", 0.0)))),
					maxf(absf(float(packet.get("yaw", 0.0))), absf(float(packet.get("throttle", 0.0)))))
				max_control = maxf(max_control, control_peak)
				if record_trace:
					for control_name: String in ["roll", "pitch", "yaw", "throttle"]:
						trace.append(float(packet.get(control_name, NAN)))
					trace.append(float(session.sim.state[RigidBody.POS]))
					trace.append(float(session.sim.state[RigidBody.POS + 1]))
					trace.append(float(session.sim.state[RigidBody.POS + 2]))
			var packet: Dictionary = packets[slot]
			session.commands = {
				"roll": float(packet.get("roll", 0.0)),
				"pitch": float(packet.get("pitch", 0.0)),
				"yaw": float(packet.get("yaw", 0.0)),
				"throttle": float(packet.get("throttle", session.start.throttle)),
			}
			session.sim.inputs = session._inputs()
		for slot in count:
			var session: Node = sessions[slot]
			session.sim.step()
		for slot in count:
			var session: Node = sessions[slot]
			session._physics_process(0.0)
			var state: PackedFloat64Array = session.sim.state
			var clearance: float = -state[RigidBody.POS + 2] + float(field.pilot.down)
			min_clearance = minf(min_clearance, clearance)
			if not session.crash.is_empty():
				stop_reason = "crash at tick %d: %s" % [tick + 1, str(session.crash.get("why", "ground/hull contact"))]
			var pose: Dictionary = spawn_positions[slot]
			var pilot: Variant = pilots[slot]
			var current_error: float = absf(_radius_error_for_state(state, pilot))
			max_radius_error = maxf(max_radius_error, current_error)
			var controls: Dictionary = packets[slot]
			max_bank = maxf(max_bank, absf(Math3D.q_to_euler(Math3D.quat(state[6], state[7], state[8], state[9]))[2]))
			var player_distance: float = _distance3(state, player_state)
			min_player_separation = minf(min_player_separation, player_distance)
			if record_trace and (tick + 1) % TICKS_PER_SECOND == 0:
				trace.append(state[RigidBody.POS])
				trace.append(state[RigidBody.POS + 1])
				trace.append(state[RigidBody.POS + 2])
				trace.append(state[RigidBody.VEL])
				trace.append(state[RigidBody.VEL + 1])
				trace.append(state[RigidBody.VEL + 2])
				trace.append(controls.get("roll", NAN))
				trace.append(controls.get("pitch", NAN))
				trace.append(controls.get("yaw", NAN))
				trace.append(controls.get("throttle", NAN))
				for other_slot in count:
					if other_slot > slot:
						min_pair_separation = minf(min_pair_separation, _distance3(state, sessions[other_slot].sim.state))
			if not session.sim.fault_reason.is_empty():
				stop_reason = "simulation fault at tick %d: %s" % [tick + 1, session.sim.fault_reason]
			if not SimStateFinite(state):
				stop_reason = "nonfinite rigid-body state at tick %d" % (tick + 1)
			if not stop_reason.is_empty():
				break
		if not stop_reason.is_empty():
			break

	var completed_ticks: int = int(sessions[0].sim.tick) if not sessions.is_empty() else 0
	var no_crash: bool = stop_reason.is_empty() and completed_ticks >= FLIGHT_TICKS
	var detail: String = "ticks=%d/%d min_height=%.2fm max_radius_error=%.2fm min_player_separation=%.2fm min_pair_separation=%.2fm max_bank=%.1fdeg max_input=%.4f refusals=%d%s" % [
		completed_ticks, FLIGHT_TICKS, min_clearance, max_radius_error, min_player_separation, min_pair_separation,
		rad_to_deg(max_bank), max_control, refusals, " stop=" + stop_reason if not stop_reason.is_empty() else "",
	]
	var label: String = "%s %d-Stik flight for 120 simulated seconds" % [weather_id, count]
	_check(label + " stays airborne without a session fault/crash", no_crash, detail)
	_check(label + " stays above the 20 m minimum clearance", min_clearance >= 20.0, detail)
	_check(label + " stays on the assigned circuit band", max_radius_error <= 40.0, detail)
	_check(label + " keeps the player 30 m clear", min_player_separation >= 30.0, detail)
	_check(label + " keeps all normalized inputs within travel", max_control <= 1.0, detail)
	if count > 1:
		_check(label + " keeps aircraft centers at least 15 m apart", min_pair_separation >= 15.0, detail)
	for session_value: Variant in sessions:
		var session: Node = session_value
		session.free()
	return {"ticks": completed_ticks, "trace": trace, "min_clearance": min_clearance,
		"max_radius_error": max_radius_error, "min_player_separation": min_player_separation,
		"min_pair_separation": min_pair_separation, "max_control": max_control}


func _snapshot(session: Node, weather: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var now: float = session.sim.time()
	var air: Dictionary = session.air_data(state, now)
	var turbulence: Variant = weather.get("turbulence_rms_mps", PackedFloat64Array([0.0, 0.0, 0.0]))
	if turbulence is Array:
		turbulence = PackedFloat64Array(turbulence)
	return {
		"state": state,
		"airspeed_m_s": float(air.get("V", NAN)),
		"wind_ned": session.wind_at(now),
		"ground_clearance_m": -state[RigidBody.POS + 2],
		"trim": session.start.duplicate(true),
		"turbulence_rms_m_s": turbulence,
	}


func _player_state(field: Dictionary) -> PackedFloat64Array:
	var pilot: Dictionary = field.pilot
	return RigidBody.make_state(
		PackedFloat64Array([float(pilot.north), float(pilot.east), float(pilot.down)]),
		PackedFloat64Array([0.0, 0.0, 0.0]), Math3D.q_identity(), PackedFloat64Array([0.0, 0.0, 0.0]))


func _radius_error_for_state(state: PackedFloat64Array, pilot: Variant) -> float:
	var center_north: float = float(pilot.get("_center_north_m"))
	var center_east: float = float(pilot.get("_center_east_m"))
	var radius: float = float(pilot.get("_radius_m"))
	var dn: float = state[RigidBody.POS] - center_north
	var de: float = state[RigidBody.POS + 1] - center_east
	return sqrt(dn * dn + de * de) - radius


func _radius_error(pose: Dictionary, pilot: Variant, _slot: int, _count: int, _field: Dictionary) -> float:
	return _radius_error_for_state(PackedFloat64Array([pose.north, pose.east, -pose.height_m]), pilot)


func _distance3(first: PackedFloat64Array, second: PackedFloat64Array) -> float:
	var north: float = first[RigidBody.POS] - second[RigidBody.POS]
	var east: float = first[RigidBody.POS + 1] - second[RigidBody.POS + 1]
	var down: float = first[RigidBody.POS + 2] - second[RigidBody.POS + 2]
	return sqrt(north * north + east * east + down * down)


func _packet_bounded(packet: Dictionary) -> bool:
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		var value: Variant = packet.get(key, NAN)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return absf(float(packet.roll)) <= 1.0 and absf(float(packet.pitch)) <= 1.0 \
		and absf(float(packet.yaw)) <= 1.0 and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0


func _flight_packet(pilot: RefCounted, snapshot: Dictionary, tick: int, traffic: Array, _unused_wind: PackedFloat64Array) -> Dictionary:
	return pilot.command(snapshot, tick, traffic)


func _trim_for_field(_field: Dictionary, _weather: Dictionary) -> Dictionary:
	return {"V": 15.0, "throttle": 0.45}


func _session_field(field: Dictionary) -> Dictionary:
	return field


func SimStateFinite(state: PackedFloat64Array) -> bool:
	if state.size() != RigidBody.SIZE:
		return false
	for value: float in state:
		if not is_finite(value):
			return false
	return true
