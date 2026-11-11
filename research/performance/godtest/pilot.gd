extends RefCounted
## Experimental benchmark command generator. Aircraft laws and accepted state are read-only.
## Feedback gains describe this test pilot; they are not calibrated aircraft data.

const M := preload("res://physics/math3d.gd")
const Airdata := preload("res://ai/companions/observation_airdata.gd")
const Takeoff := preload("res://scenery/takeoff_pilot.gd")
const InputAdapter := preload("../sustained_input.gd")
const PHASES := ["takeoff", "climb_right", "farmhouse", "flag", "right_circuit", "roll", "recover", "large_loop", "approach", "landing", "stop"]
const STIK := "jensen-das-ugly-stik-60"
const PROFILE := "experimental-god-stik-v1"

var session: Node
var config: Dictionary = {}
var runway: Dictionary = {}
var landmarks: Dictionary = {}
var phase := "recover"
var done := false
var failed := false
var reason := ""
var phase_tick := 0
var last_tick := -1
var update_tick := -1
var stable_ticks := 0
var rotation := 0.0
var heading_rotation := 0.0
var previous_heading := 0.0
var initial_heading := 0.0
var target_heading := 0.0
var target_agl := 65.0
var target_speed := 15.0
var base_throttle := 0.45
var packet := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.45}
var telemetry: Dictionary = {}
var saturated_updates := 0
var pilot_updates := 0
var pilot_usec := 0
var orbit_north := 0.0
var orbit_east := 0.0
var orbit_radius := 90.0
var approach_stage := 0
var touchdown := false
var touchdown_data: Dictionary = {}
var contact_episodes := 0
var contact_active := false
var maximum_contact_sink := 0.0
var minimum_runway_margin := 1.0e30
var menu_release_pending := false


func release_for_menu() -> void:
	# HeldKeys.mask polls once on Continue. Supply a released virtual keyboard at
	# that boundary without consuming a physical tick or latching feedback forever.
	menu_release_pending = true


func configure(owner: Node, field: Dictionary, scenery: Dictionary, options: Dictionary) -> Dictionary:
	if not is_instance_valid(owner) or owner.sim == null or not owner.is_flyable() or owner.radio.connected or owner.external_driver_enabled:
		return {ok = false, reason = "normal flyable keyboard session required"}
	session = owner
	config = options.duplicate(true)
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")): runway = surface.duplicate(true)
	for group: Dictionary in scenery.get("groups", []):
		var id := str(group.get("id", ""))
		if id in ["farm-farmhouse", "flagpole"]:
			var placements: Variant = group.get("placements", {}).get("value", [])
			if placements is Array and not placements.is_empty(): landmarks[id] = placements[0].duplicate()
	target_speed = float(owner.start.get("V", owner.start.get("speed", 15.0)))
	if not is_finite(target_speed) or target_speed < 5.0: target_speed = 15.0
	base_throttle = float(owner.start.get("throttle", 0.45))
	initial_heading = M.q_to_euler(owner.sim.state.slice(6, 10))[0]
	target_heading = initial_heading
	orbit_radius = maxf(90.0, target_speed * target_speed / (9.80665 * tan(deg_to_rad(25.0))))
	phase_tick = owner.sim.tick
	packet.throttle = base_throttle
	return {ok = true, profile = PROFILE, experimental = true, target_speed_mps = target_speed,
		resolved_landmarks = landmarks.duplicate(true), runway_available = not runway.is_empty()}


func begin_phase(name_value: String) -> Dictionary:
	if not name_value in PHASES: return {ok = false, reason = "unknown pilot phase"}
	if not is_instance_valid(session) or session.sim == null: return {ok = false, reason = "session unavailable"}
	var stock := str(config.get("aircraft", "")) == STIK
	if name_value in ["takeoff", "roll", "large_loop", "approach", "landing", "stop"] and not stock:
		return {ok = false, reason = "maneuver profile not calibrated for this aircraft; basic navigation is experimental"}
	if name_value in ["takeoff", "approach", "landing", "stop"] and runway.is_empty():
		return {ok = false, reason = "runway unavailable"}
	if name_value == "farmhouse" and not landmarks.has("farm-farmhouse"):
		return {ok = false, reason = "farmhouse landmark unavailable"}
	if name_value == "flag" and not landmarks.has("flagpole"):
		return {ok = false, reason = "flag landmark unavailable"}
	phase = name_value
	phase_tick = session.sim.tick
	update_tick = -1
	stable_ticks = 0
	rotation = 0.0
	heading_rotation = 0.0
	done = false
	failed = false
	reason = ""
	var state: PackedFloat64Array = session.sim.state
	var euler := M.q_to_euler(state.slice(6, 10))
	previous_heading = euler[0]
	if name_value == "climb_right": target_heading = wrapf(euler[0] + PI / 2.0, -PI, PI)
	elif name_value == "recover": target_heading = euler[0]
	elif name_value == "right_circuit":
		orbit_north = state[0] - sin(euler[0]) * orbit_radius
		orbit_east = state[1] + cos(euler[0]) * orbit_radius
	elif name_value == "approach": approach_stage = 0
	return {ok = true, profile = PROFILE, experimental = true}


func read_raw() -> Dictionary:
	var started := Time.get_ticks_usec()
	var neutral := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if menu_release_pending:
		menu_release_pending = false
		return neutral
	if not is_instance_valid(session) or session.sim == null: return neutral
	var tick: int = session.sim.tick
	if last_tick >= 0 and tick != last_tick + 1:
		failed = true
		reason = "input tick discontinuity"
	last_tick = tick
	if update_tick < 0 or tick - update_tick >= 4:
		var elapsed: float = float(tick - update_tick) * session.sim.dt() if update_tick >= 0 else 4.0 * session.sim.dt()
		_update(elapsed)
		update_tick = tick
		pilot_updates += 1
	var converted: Dictionary = InputAdapter.keyboard_sample(packet, float(session.commands.throttle), session.sim.dt())
	pilot_usec += Time.get_ticks_usec() - started
	if not converted.get("ok", false):
		failed = true
		reason = str(converted.get("reason", "input conversion refused"))
		return neutral
	return converted.raw


func _update(dt: float) -> void:
	var state: PackedFloat64Array = session.sim.state
	if state.size() < 13:
		failed = true
		reason = "invalid rigid body state"
		return
	for value: float in state:
		if not is_finite(value):
			failed = true
			reason = "nonfinite state"
			return
	var attitude := state.slice(6, 10)
	var euler := M.q_to_euler(attitude)
	var velocity := M.q_rotate(attitude, state.slice(3, 6))
	var ground: PackedFloat64Array = session.environment.ground(state[0], state[1])
	var agl := -state[2] - ground[0]
	var wind: PackedFloat64Array = session.wind_at(session.sim.time(), state)
	var speed: float = Airdata.airspeed_m_s(state, wind)
	var elapsed: float = float(session.sim.tick - phase_tick) * session.sim.dt()
	heading_rotation += wrapf(euler[0] - previous_heading, -PI, PI)
	previous_heading = euler[0]
	var altitude_target := target_agl
	var speed_target := target_speed
	var heading := target_heading
	var distance := 0.0
	if phase == "takeoff":
		packet = Takeoff.step(elapsed, state, initial_heading).commands
		if speed >= Takeoff.VR_MS:
			packet.pitch = clampf(0.7 * (deg_to_rad(10.0) - euler[1]) - 0.12 * state[11], -0.6, 0.6)
		done = agl > 18.0 and velocity[2] < 0.0 and elapsed > 5.0
	elif phase == "farmhouse" or phase == "flag":
		var point: Array = landmarks["farm-farmhouse" if phase == "farmhouse" else "flagpole"]
		var dn := float(point[0]) - state[0]
		var de := float(point[1]) - state[1]
		distance = sqrt(dn * dn + de * de)
		heading = atan2(de * target_speed - wind[1], dn * target_speed - wind[0])
		# Direction correction uses unit ground-course demand before wind subtraction.
		if distance > 0.01: heading = atan2(de / distance * target_speed - wind[1], dn / distance * target_speed - wind[0])
		packet = _guidance(state, euler, velocity, wind, speed, heading, altitude_target, speed_target, agl)
		done = distance < maxf(30.0, target_speed * 2.0) and agl >= 20.0
	elif phase == "right_circuit":
		var dn := state[0] - orbit_north
		var de := state[1] - orbit_east
		var radius := sqrt(dn * dn + de * de)
		heading = atan2(de, dn) + PI / 2.0 + atan2(radius - orbit_radius, orbit_radius)
		packet = _guidance(state, euler, velocity, wind, speed, heading, altitude_target, speed_target, agl)
		done = heading_rotation >= TAU - 0.15 and elapsed > (float(config.get("sample_s", 1800)) if str(config.get("id", "")) == "soak" else 10.0)
	elif phase == "roll":
		rotation += state[10] * dt
		packet = _guidance(state, euler, velocity, wind, speed, target_heading, maxf(target_agl, 75.0), target_speed * 1.1, agl)
		if elapsed < 5.0 and agl < 55.0:
			pass # Acquire clearance before beginning the roll.
		elif agl < 25.0 and rotation < 5.0:
			failed = true
			reason = "roll recovery clearance lost"
		else:
			packet.roll = 0.75 if rotation < TAU - 0.15 else clampf(-1.8 * euler[2] - 0.35 * state[10], -1, 1)
			packet.pitch = -0.2 * state[11] if rotation < TAU - 0.15 else packet.pitch
			done = rotation >= TAU - 0.15 and absf(euler[2]) < 0.2 and absf(state[10]) < 0.5
	elif phase == "large_loop":
		rotation += state[11] * dt
		packet = {roll = clampf(-0.4 * state[10], -1, 1), pitch = 0.58, yaw = clampf(-0.2 * state[12], -1, 1), throttle = 1.0}
		if agl < 35.0 and rotation < 5.5:
			failed = true
			reason = "loop clearance prerequisite or recovery margin lost"
		if rotation >= TAU - 0.15:
			packet = _guidance(state, euler, velocity, wind, speed, target_heading, target_agl, target_speed, agl)
			done = absf(euler[1]) < 0.3 and absf(euler[2]) < 0.3 and absf(state[11]) < 0.8
	elif phase == "approach":
		var north := float(runway.center_north)
		var east := float(runway.center_east) - float(runway.length_east_west) / 2.0 - 220.0
		var dn := north - state[0]
		var de := east - state[1]
		distance = sqrt(dn * dn + de * de)
		heading = atan2(de, dn)
		if approach_stage == 0 and distance < 35.0: approach_stage = 1
		if approach_stage == 1:
			heading = PI / 2.0 + clampf((state[0] - north) * 0.02, -0.4, 0.4)
			altitude_target = 13.0
			speed_target = 13.5
		packet = _guidance(state, euler, velocity, wind, speed, heading, altitude_target, speed_target, agl)
		done = approach_stage == 1 and agl < 18.0 and absf(state[0] - north) < 15.0 and absf(wrapf(euler[0] - PI / 2.0, -PI, PI)) < 0.25 and state[1] < float(runway.center_east) - 70.0
	elif phase == "landing" or phase == "stop":
		var compressions: PackedFloat64Array = session.gear_compressions(state)
		var clearance := agl
		var supported := 0
		for compression: float in compressions:
			clearance = minf(clearance, -compression)
			if compression > 0: supported += 1
		var north := float(runway.center_north)
		heading = PI / 2.0 + clampf((state[0] - north) * 0.04, -0.3, 0.3)
		var along := float(runway.center_east) - 20.0 - state[1]
		altitude_target = maxf(0.0, along * 0.06)
		packet = _guidance(state, euler, velocity, wind, speed, heading, altitude_target, 12.0, agl, true)
		if clearance < 2.0:
			packet.throttle = 0.0
			packet.pitch = clampf(0.8 * (velocity[2] - 0.25) - 0.5 * state[11], -0.5, 0.8)
		if supported > 0:
			if not contact_active: contact_episodes += 1
			for contact: Dictionary in session.current_landing_gear(state).get("contacts", []):
				var arm: PackedFloat64Array = contact.position
				var point := M.add(state.slice(0, 3), M.q_rotate(attitude, arm))
				var wheel_velocity := M.q_rotate(attitude, M.add(state.slice(3, 6), M.cross(state.slice(10, 13), arm)))
				maximum_contact_sink = maxf(maximum_contact_sink, wheel_velocity[2])
				minimum_runway_margin = minf(minimum_runway_margin, minf(float(runway.length_east_west) / 2.0 - absf(point[1] - float(runway.center_east)), float(runway.width_north_south) / 2.0 - absf(point[0] - north)))
			if not touchdown:
				touchdown = true
				touchdown_data = {tick = session.sim.tick, north_m = state[0], east_m = state[1], roll_deg = rad_to_deg(euler[2]), datum_sink_mps = velocity[2], speed_mps = speed, wheels_supported = supported}
			packet.throttle = 0.0
			packet.pitch = clampf(-float(session.trims.pitch) - 0.4 * state[11], -1, 1)
			packet.yaw = clampf(0.8 * wrapf(PI / 2.0 - euler[0], -PI, PI) + 0.05 * (state[0] - north) - 0.3 * state[12], -1, 1)
			if session.wheel_brake_available(): session.set_wheel_brake(1.0)
		contact_active = supported > 0
		if phase == "landing": done = touchdown
		else:
			var ground_speed := sqrt(velocity[0] * velocity[0] + velocity[1] * velocity[1])
			stable_ticks = stable_ticks + 4 if ground_speed < 0.5 and supported > 0 else 0
			done = stable_ticks >= 720
	else:
		packet = _guidance(state, euler, velocity, wind, speed, heading, altitude_target, speed_target, agl)
		var stable := absf(euler[2]) < 0.15 and absf(velocity[2]) < 1.2 and absf(agl - altitude_target) < 10.0
		stable_ticks = stable_ticks + 4 if stable else 0
		if phase == "climb_right": done = stable_ticks >= 240 and absf(wrapf(target_heading - euler[0], -PI, PI)) < 0.25
		else: done = stable_ticks >= 480 and elapsed >= minf(float(config.get("sample_s", 10)), 5.0)
	if elapsed > float(config.get("phase_timeout_s", 180)):
		failed = true
		reason = "pilot simulation deadline reached"
	for axis: String in ["roll", "pitch", "yaw", "throttle"]:
		if not is_finite(float(packet[axis])):
			failed = true
			reason = "nonfinite pilot command"
		packet[axis] = clampf(float(packet[axis]), 0.0 if axis == "throttle" else -1.0, 1.0)
	if absf(packet.roll) >= 0.99 or absf(packet.pitch) >= 0.99 or absf(packet.yaw) >= 0.99: saturated_updates += 1
	telemetry = {profile = PROFILE, experimental = true, phase = phase, tick = session.sim.tick,
		elapsed_sim_s = elapsed, airspeed_mps = speed, agl_m = agl, heading_deg = rad_to_deg(euler[0]),
		roll_deg = rad_to_deg(euler[2]), pitch_deg = rad_to_deg(euler[1]), distance_to_gate_m = distance,
		rotation_rad = rotation, heading_rotation_rad = heading_rotation, command = packet.duplicate(),
		pilot_updates = pilot_updates, saturated_updates = saturated_updates, pilot_usec = pilot_usec,
		touchdown = touchdown_data.duplicate(), contact_episodes = contact_episodes,
		maximum_contact_sink_mps = maximum_contact_sink, minimum_wheel_runway_margin_m = minimum_runway_margin if touchdown else null}


func _guidance(s: PackedFloat64Array, euler: PackedFloat64Array, velocity: PackedFloat64Array, wind: PackedFloat64Array, speed: float, heading: float, agl_target: float, speed_target: float, agl: float, approach := false) -> Dictionary:
	var error := wrapf(heading - euler[0], -PI, PI)
	var bank := clampf(error * 1.4, -0.45, 0.45)
	var down_target := -clampf((agl_target - agl) * 0.10, -2.0, 2.0)
	if not approach and agl < 15.0: down_target = -2.5
	var air_body := M.sub(s.slice(3, 6), M.q_rotate(M.quat(s[6], -s[7], -s[8], -s[9]), wind))
	var beta := atan2(air_body[1], sqrt(air_body[0] * air_body[0] + air_body[2] * air_body[2]))
	var trim_alpha: float = float(session.start.get("alpha", 0.05))
	var pitch_target := trim_alpha + atan2(-down_target, maxf(speed, 5.0))
	return {roll = clampf(1.8 * (bank - euler[2]) - 0.35 * s[10], -1, 1),
		pitch = clampf(0.7 * (pitch_target - euler[1]) - 0.12 * s[11], -0.6, 0.6),
		yaw = clampf(4.0 * beta + 0.5 * (9.80665 * tan(euler[2]) / maxf(speed, 3.0) - s[12]), -1, 1),
		throttle = clampf(base_throttle + 0.1 * (speed_target - speed), 0, 1)}


func observe() -> Dictionary:
	return telemetry.merged({phase = phase, done = done, failed = failed, reason = reason}, true)
