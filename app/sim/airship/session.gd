# BL-07/BL-08: generic RC blimp session. Owns one Simulation with the airship VehicleModel (stage law in
# physics/airship/airship_dynamics.gd), the field environment, the admitted weather (calm or steady uniform wind),
# release/ground start, terminal impact detection on accepted ticks and a bounded input tape for exact replay.
# Ticks come only from tick_once(); the engine physics loop never steps this kernel. 64-bit floats only.
extends Node

const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Data := preload("res://physics/airship/airship_data.gd")
const Dynamics := preload("res://physics/airship/airship_dynamics.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const WindField := preload("res://physics/wind_field.gd")
const WindConfig := preload("res://physics/wind_config.gd")

const DEFAULT_DATA := "res://data/airships/rc-blimp-5m.json"
const FORMAT := "openrc-airship-session v1"
const FIXED_HZ := 240
const MAX_TAPE_TICKS := FIXED_HZ * 60 * 30
const MAX_WIND_MPS := 4.0
const ARM_THROTTLE := 0.05

signal tick_advanced(tick: int, time_s: float)
signal crashed(reason: String)
signal pause_changed(paused: bool, reason: String)
signal faulted(reason: String)

var sim: Node = Sim.new()
var environment: SimEnvironment = SimEnvironment.new()
var prepared := false
var paused := true
var pause_reason := "prepared"
var load_error := ""
var fault_reason := ""
var crash: Dictionary = {}
var data: Dictionary = {}
var model: Dictionary = {}
var options: Dictionary = {}
var source_sha256 := ""
var start_state := PackedFloat64Array()
var start_continuous := PackedFloat64Array()
var tape := PackedFloat64Array()
var tape_overflow := false
var _field: Dictionary = {}
var _wind_ned := PackedFloat64Array([0.0, 0.0, 0.0])
var _ground: Callable
var _last_info: Dictionary = {}
var _info_tick := -1


func _init() -> void:
	sim.name = "Simulation"
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	sim.faulted.connect(func(reason: String) -> void: _fault("airship kernel: " + reason))


static func default_options() -> Dictionary:
	return {data_path = DEFAULT_DATA, heaviness_kg = NAN, wind_speed_mps = 0.0, wind_from_deg = 0.0,
		start = "air", altitude_m = 6.0, north_offset_m = 22.0, east_offset_m = 0.0, heading_deg = 90.0}


## Build every derived object before replacing the running configuration. Refusal keeps the old session.
func prepare(field: Dictionary, requested: Dictionary = {}) -> bool:
	var opts := default_options()
	opts.merge(requested, true)
	var loaded := Data.load_file(str(opts.data_path))
	if not loaded.ok:
		load_error = "; ".join(loaded.errors)
		return false
	var wind_speed := float(opts.wind_speed_mps)
	if not is_finite(wind_speed) or wind_speed < 0.0 or wind_speed > MAX_WIND_MPS or not is_finite(float(opts.wind_from_deg)):
		load_error = "airship weather admits calm or steady wind up to %.1f m/s" % MAX_WIND_MPS
		return false
	var weather_raw := WindConfig.defaults()
	weather_raw.speed_mps = wind_speed
	weather_raw.from_deg = fposmod(float(opts.wind_from_deg), 360.0)
	var built_weather := WindField.build(weather_raw)
	if not built_weather.ok:
		load_error = "; ".join(built_weather.errors)
		return false
	var surfaces := PackedFloat64Array()
	if not field.is_empty():
		var table := GroundSurfaces.load_table()
		var built := GroundSurfaces.build(table.table, field) if table.ok else table
		if not built.ok:
			load_error = "; ".join(built.errors)
			return false
		surfaces = built.rects
		if not Terrain.is_valid_surface_table(surfaces):
			load_error = "field surface table is invalid"
			return false
	var candidate_env := SimEnvironment.new()
	candidate_env.surfaces = surfaces
	candidate_env.weather = built_weather.field
	var pilot: Dictionary = field.get("pilot", {north = 0.0, east = 0.0, down = 0.0})
	var north := float(pilot.north) + float(opts.north_offset_m)
	var east := float(pilot.east) + float(opts.east_offset_m)
	var under := candidate_env.ground(north, east)
	if under.size() != 3 or not is_finite(under[0]):
		load_error = "start position is outside the field"
		return false
	var release_down := -under[0] - (float(opts.altitude_m) if opts.start == "air" else 1.0)
	var rho := candidate_env.air_density(release_down)
	var heaviness: float = opts.heaviness_kg
	if not is_finite(heaviness):
		heaviness = loaded.data.ballast.default_heaviness
	var derived := Data.derive(loaded.data, rho, candidate_env.gravity, heaviness)
	if not derived.ok:
		load_error = "; ".join(derived.errors)
		return false
	var vehicle := VehicleModel.new()
	vehicle.input_size = 4
	vehicle.aux_size = 0
	vehicle.modes_size = 0
	vehicle.continuous_size = Data.CONTINUOUS_SIZE
	vehicle.identity = {vehicle = "airship", law = Dynamics.LAW, mixer = Dynamics.MIXER_LAW, layout = Data.STATE_LAYOUT,
		data_sha256 = loaded.source_sha256, heaviness_kg = heaviness, rho = rho}
	var captured_model: Dictionary = derived.model
	var captured_env := candidate_env
	var wind := candidate_env.wind(0.0)
	var ground := func(n: float, e: float) -> PackedFloat64Array: return captured_env.ground(n, e)
	vehicle.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, _t: float) -> Dictionary:
		return Dynamics.stage(captured_model, body, continuous, sim.inputs, wind, ground)
	if not VehicleModel.validate(vehicle).ok:
		load_error = "airship vehicle model is malformed"
		return false
	# Commit.
	data = loaded.data
	model = captured_model
	source_sha256 = loaded.source_sha256
	options = opts
	options.heaviness_kg = heaviness
	environment = candidate_env
	_wind_ned = wind
	_ground = ground
	_field = field.duplicate(true)
	sim.set_model(vehicle)
	sim.mass = model.mass
	sim.inertia = model.inertia.duplicate()
	sim.gravity = environment.gravity
	prepared = true
	load_error = ""
	return reset()


## Release state: airborne at the chosen height, or resting on the gear (datum lowered until the lowest gear or hull
## witness touches). Pauses until the pilot resumes with armed, low-throttle controls.
func reset() -> bool:
	if not prepared:
		return false
	var heading := deg_to_rad(float(options.heading_deg))
	var pilot: Dictionary = _field.get("pilot", {north = 0.0, east = 0.0, down = 0.0})
	var north := float(pilot.north) + float(options.north_offset_m)
	var east := float(pilot.east) + float(options.east_offset_m)
	var height := environment.ground(north, east)[0]
	var down := -height - float(options.altitude_m)
	if options.start == "ground":
		var lowest := -INF
		for gear: Dictionary in model.contacts.gear:
			lowest = maxf(lowest, float(gear.point[2]))
		var hull: PackedFloat64Array = model.contacts.hull_points
		for i in hull.size() / 3:
			lowest = maxf(lowest, hull[3 * i + 2])
		down = -height - lowest
	var q := M.q_from_euler(heading, 0.0, 0.0)
	var body := PackedFloat64Array([north, east, down, 0.0, 0.0, 0.0, q[0], q[1], q[2], q[3], 0.0, 0.0, 0.0])
	# Calm release moves with the air: the hull starts at rest relative to the wind (zero air-relative velocity).
	var wind_body := M.q_rotate(M.q_conj(q), _wind_ned)
	if options.start == "air":
		body[3] = wind_body[0]
		body[4] = wind_body[1]
		body[5] = wind_body[2]
	var continuous := PackedFloat64Array()
	continuous.resize(Data.CONTINUOUS_SIZE)
	continuous[Data.SOC] = model.battery.initial_soc
	sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	sim.aux = PackedFloat64Array()
	sim.modes = PackedInt64Array()
	sim.continuous = continuous
	if not sim.reset(body):
		load_error = "airship reset refused: " + sim.fault_reason
		return false
	start_state = body
	start_continuous = continuous
	tape = PackedFloat64Array()
	tape_overflow = false
	crash = {}
	fault_reason = ""
	_info_tick = -1
	_set_paused(true, "Ready. Arm with throttle low, then resume.")
	return true


func resume(sticks: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])) -> bool:
	if not prepared or not crash.is_empty() or not fault_reason.is_empty():
		return false
	if sticks.size() != 4 or sticks[3] > ARM_THROTTLE:
		pause_reason = "Lower the throttle to resume."
		return false
	_set_paused(false, "")
	return true


func pause(reason: String = "Paused") -> void:
	_set_paused(true, reason)


func _set_paused(value: bool, reason: String) -> void:
	paused = value
	pause_reason = reason
	pause_changed.emit(paused, reason)


## Advance exactly one 240 Hz tick with the sampled sticks [roll, pitch, yaw, throttle].
func tick_once(sticks: PackedFloat64Array) -> bool:
	if not prepared or paused or not fault_reason.is_empty():
		return false
	if sticks.size() != 4:
		_fault("stick sample must hold four values")
		return false
	for value: float in sticks:
		if not is_finite(value):
			_fault("nonfinite stick sample")
			return false
	var clean := PackedFloat64Array([clampf(sticks[0], -1.0, 1.0), clampf(sticks[1], -1.0, 1.0),
		clampf(sticks[2], -1.0, 1.0), clampf(sticks[3], 0.0, 1.0)])
	sim.inputs = clean
	sim.step()
	if not sim.fault_reason.is_empty():
		return false
	if tape.size() < MAX_TAPE_TICKS * 4:
		tape.append_array(clean)
	else:
		tape_overflow = true
	_observe_accepted()
	tick_advanced.emit(sim.tick, sim.time())
	return true


## Terminal observation on the accepted tick-end state: a propeller touching the ground, or the envelope striking
## at more than the declared impact speed, ends the flight (deterministic, replayed identically).
func _observe_accepted() -> void:
	var info := telemetry_info()
	var contact: Dictionary = info.get("contact", {})
	var reason := ""
	if contact.get("prop_contact", false):
		reason = "Propeller strike"
	elif contact.get("hull_contact", false) and float(contact.get("hull_approach_mps", 0.0)) > float(model.contacts.impact_speed):
		reason = "Hard envelope impact (%.1f m/s)" % float(contact.hull_approach_mps)
	if not reason.is_empty():
		crash = {reason = reason, tick = sim.tick, time_s = sim.time(), state = sim.state.duplicate()}
		_set_paused(true, reason + ". Restart to fly again.")
		crashed.emit(reason)


func _fault(reason: String) -> void:
	fault_reason = reason
	paused = true
	pause_reason = "Simulation paused: " + reason
	faulted.emit(reason)


## Detailed evaluation of the accepted state (cached per tick): forces, thrusts, battery and contacts.
func telemetry_info() -> Dictionary:
	if not prepared:
		return {}
	if _info_tick == sim.tick and not _last_info.is_empty():
		return _last_info
	var r := Dynamics.evaluate(model, sim.state, sim.continuous, sim.inputs, _wind_ned, _ground, true)
	_last_info = r.info
	_info_tick = sim.tick
	return _last_info


## Pilot-facing telemetry of the accepted state.
func telemetry() -> Dictionary:
	if not prepared:
		return {}
	var s: PackedFloat64Array = sim.state
	var q := s.slice(6, 10)
	var v_ned := M.q_rotate(q, s.slice(3, 6))
	var euler := M.q_to_euler(q)
	var height := environment.ground(s[0], s[1])[0]
	var info := telemetry_info()
	var c: PackedFloat64Array = sim.continuous
	return {
		tick = sim.tick, time_s = sim.time(),
		agl_m = -s[2] - height, altitude_m = -s[2],
		vertical_speed_mps = -v_ned[2],
		ground_speed_mps = sqrt(v_ned[0] * v_ned[0] + v_ned[1] * v_ned[1]),
		air_speed_mps = float(info.get("air_speed_mps", 0.0)),
		heading_deg = fposmod(rad_to_deg(euler[0]), 360.0), pitch_deg = rad_to_deg(euler[1]), roll_deg = rad_to_deg(euler[2]),
		wind_ned = _wind_ned.duplicate(), heaviness_kg = model.heaviness_kg, ballast_kg = model.ballast_mass, mass_kg = model.mass,
		buoyancy_n = model.buoyancy_n, weight_n = model.weight_n,
		motor = c.slice(Data.MOTOR, Data.MOTOR + 4), vector_deg = _degrees(c.slice(Data.VECTOR, Data.VECTOR + 3)),
		fin_deg = _degrees(c.slice(Data.FIN, Data.FIN + 3)), soc = c[Data.SOC],
		battery = info.get("battery", {}), thrust_n = info.get("thrust_n", PackedFloat64Array()),
		contact = info.get("contact", {}), crash = crash.duplicate(), paused = paused, pause_reason = pause_reason,
	}


static func _degrees(values: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for value: float in values:
		out.append(rad_to_deg(value))
	return out


func state_snapshot() -> PackedFloat64Array:
	return sim.state.duplicate()


func continuous_snapshot() -> PackedFloat64Array:
	return sim.continuous.duplicate()


func interpolated(fraction: float) -> PackedFloat64Array:
	return sim.interpolated(fraction)


func identity() -> Dictionary:
	return {format = FORMAT, law = Dynamics.LAW, mixer = Dynamics.MIXER_LAW, data_sha256 = source_sha256,
		layout = Data.STATE_LAYOUT, heaviness_kg = options.get("heaviness_kg", 0.0), rho = model.get("rho", 0.0),
		wind_ned = _wind_ned.duplicate(), start = options.get("start", ""), environment = environment.identity()}


## Exact replay: reset to the same release and feed a recorded tape. Returns true only if every tick was accepted.
func replay(recorded: PackedFloat64Array) -> bool:
	if not reset() or recorded.size() % 4 != 0:
		return false
	_set_paused(false, "")
	for i in recorded.size() / 4:
		if not tick_once(recorded.slice(4 * i, 4 * i + 4)):
			return not crash.is_empty() and i == recorded.size() / 4 - 1
		if not crash.is_empty():
			return i == recorded.size() / 4 - 1
	return true
