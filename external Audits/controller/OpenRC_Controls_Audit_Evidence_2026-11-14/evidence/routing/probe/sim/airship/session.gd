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
const WindFieldLaw := preload("res://physics/wind_field.gd")
const WindSettings := preload("res://physics/wind_config.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

const DEFAULT_DATA := "res://data/airships/rc-blimp-5m.json"
const FORMAT := "openrc-airship-session v1"
const FIXED_HZ := 240
const MAX_TAPE_TICKS := FIXED_HZ * 60 * 30
const MAX_WIND_MPS := 4.0
const ARM_THROTTLE := 0.05
const ARM_YAW := 0.1
const FOCUS_PAUSE := "Paused: the window lost focus."

signal tick_advanced(tick: int, time_s: float)
signal crashed(reason: String)
signal pause_changed(paused: bool, reason: String)
signal faulted(reason: String)
## Emitted before a reset or reconfiguration replaces the flight (recorders close their file here).
signal resetting

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
## BL-11: immutable scenery obstacle inventory (scenery/collision_world.gd); empty = terrain only.
var _collision_world: Dictionary = {}
## Broad-phase superset of nearby proxies and its query centre [north, east, down, reach].
const BROAD_SLACK_M := 2.0
var _broad: Array[Dictionary] = []
var _broad_center := PackedFloat64Array()
## Envelope axis samples [x, R, margin] (see _obstacle_hit).
const AXIS_STEP_M := 0.05
const AXIS_BLOCK := 10
var _axis := PackedFloat64Array()


func _init() -> void:
	sim.name = "Simulation"
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	sim.faulted.connect(func(reason: String) -> void: _fault("airship kernel: " + reason))
	# The kernel pauses itself when the application loses focus; the flight follows and needs an explicit resume.
	sim.paused_changed.connect(func(value: bool) -> void:
		if value and not paused and sim.fault_reason.is_empty():
			_set_paused(true, FOCUS_PAUSE))


static func default_options() -> Dictionary:
	return {data_path = DEFAULT_DATA, heaviness_kg = NAN, wind_speed_mps = 0.0, wind_from_deg = 0.0,
		start = "air", altitude_m = 6.0, north_offset_m = 22.0, east_offset_m = 0.0, heading_deg = 90.0}


## Build every derived object before replacing the running configuration. Refusal keeps the old session.
func prepare(field: Dictionary, requested: Dictionary = {}) -> bool:
	var opts := default_options()
	opts.merge(requested, true)
	# A frozen Workshop variant arrives as an in-memory document; otherwise the shipped data file is read.
	var loaded := Data.load_document(opts.data, "workshop variant") if opts.get("data") is Dictionary \
		else Data.load_file(str(opts.data_path))
	if not loaded.ok:
		load_error = "; ".join(loaded.errors)
		return false
	var wind_speed := float(opts.wind_speed_mps)
	if not is_finite(wind_speed) or wind_speed < 0.0 or wind_speed > MAX_WIND_MPS or not is_finite(float(opts.wind_from_deg)):
		load_error = "airship weather admits calm or steady wind up to %.1f m/s" % MAX_WIND_MPS
		return false
	var weather_raw := WindSettings.defaults()
	weather_raw.speed_mps = wind_speed
	weather_raw.from_deg = fposmod(float(opts.wind_from_deg), 360.0)
	var built_weather := WindFieldLaw.build(weather_raw)
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
	captured_model.ground_ceiling = candidate_env.ground_max_height()
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
	_build_axis_samples()
	prepared = true
	load_error = ""
	return reset()


## Release state: airborne at the chosen height, or resting on the gear (datum lowered until the lowest gear or hull
## witness touches). Pauses until the pilot resumes with armed, low-throttle controls.
func reset() -> bool:
	if not prepared:
		return false
	resetting.emit()
	var heading := deg_to_rad(float(options.heading_deg))
	var pilot: Dictionary = _field.get("pilot", {north = 0.0, east = 0.0, down = 0.0})
	var north := float(pilot.north) + float(options.north_offset_m)
	var east := float(pilot.east) + float(options.east_offset_m)
	var height := environment.ground(north, east)[0]
	var down := -height - float(options.altitude_m)
	var pitch := 0.0
	if options.start == "ground":
		# Stand on both wheels: pitch so the front and rear contact points are level, then lower the datum until the
		# lowest gear or hull witness touches the terrain.
		var gear: Array = model.contacts.gear
		if gear.size() >= 2:
			var front: PackedFloat64Array = gear[0].point
			var rear: PackedFloat64Array = gear[1].point
			pitch = M.atan2_(front[2] - rear[2], front[0] - rear[0])
	var q := M.q_from_euler(heading, pitch, 0.0)
	if options.start == "ground":
		var lowest := -INF
		for gear_item: Dictionary in model.contacts.gear:
			lowest = maxf(lowest, M.q_rotate(q, gear_item.point)[2])
		var hull: PackedFloat64Array = model.contacts.hull_points
		for i in hull.size() / 3:
			lowest = maxf(lowest, M.q_rotate(q, hull.slice(3 * i, 3 * i + 3))[2])
		down = -height - lowest
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
	# Yaw drives the reversible stern lateral motor directly, so it must be centred too.
	if absf(sticks[2]) > ARM_YAW:
		pause_reason = "Centre the yaw stick to resume."
		return false
	sim.set_paused(false)
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
	# Contacts only: the detailed telemetry evaluation is computed lazily by its readers (HUD, logs).
	var contact := Dynamics.observe_contacts(model, sim.state, sim.continuous, _ground)
	var reason := ""
	var obstacle := _obstacle_hit()
	if not obstacle.is_empty():
		reason = "Obstacle strike: %s" % obstacle
	elif contact.get("prop_contact", false):
		reason = "Propeller strike"
	elif contact.get("hull_contact", false) and float(contact.get("hull_approach_mps", 0.0)) > float(model.contacts.impact_speed):
		reason = "Hard envelope impact (%.1f m/s)" % float(contact.hull_approach_mps)
	if not reason.is_empty():
		crash = {reason = reason, tick = sim.tick, time_s = sim.time(), state = sim.state.duplicate()}
		_set_paused(true, reason + ". Restart to fly again.")
		crashed.emit(reason)


## Install the field obstacle inventory before reset; refused while a flight is under way.
func set_collision_world(world: Dictionary) -> bool:
	if sim.tick > 0 and not paused:
		return false
	if not world.is_empty():
		if not CollisionWorld._world_header_is_valid(world):
			return false
		for proxy: Dictionary in world.proxies:
			if not CollisionWorld._proxy_is_valid(proxy):
				return false
	_collision_world = world.duplicate(true)
	_broad_center = PackedFloat64Array()
	return true


## Proxies overlapping the reach sphere around O. The broad phase queries the world once with an extra
## BROAD_SLACK_M and reuses that superset while O stays within the slack; the exact sphere filter keeps the
## world's own candidate order, so the result equals a fresh CollisionWorld.nearby query.
func _nearby_proxies(north: float, east: float, down: float, reach: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := _broad_center
	var moved := INF if c.size() != 4 or c[3] != reach else \
		sqrt((north - c[0]) * (north - c[0]) + (east - c[1]) * (east - c[1]) + (down - c[2]) * (down - c[2]))
	if moved > BROAD_SLACK_M:
		_broad = CollisionWorld.nearby(_collision_world, north, east, down, reach + BROAD_SLACK_M)
		_broad_center = PackedFloat64Array([north, east, down, reach])
	for proxy: Dictionary in _broad:
		if CollisionWorld._aabb_sphere_overlap(proxy, north, east, down, reach):
			out.append(proxy)
	return out


## Accepted-tick obstacle test, two parts:
## 1. Envelope: the hull of revolution R(x) against every nearby proxy, by axis samples at most AXIS_STEP_M apart.
##    Between samples the clearance dist(P(x), proxy) - R(x) cannot drop by more than h/2 * (1 + |dR/dx|) (distance
##    is 1-Lipschitz along the axis), so each sample carries that margin: thin wires, poles and off-axis intrusions
##    are found, at worst about 3 cm early along the body and up to about 10 cm at the blunt nose tip. Samples
##    are also inflated by the largest witness travel of one tick, so a crossing between two clear endpoints is
##    reported (swept superset; admitted below 10 m/s).
## 2. Appendages: fin, gondola, gear and vector-following propeller witnesses inside a proxy. A proxy thinner than
##    the witness spacing can pass between appendage witnesses (declared limit).
## Every response class is terminal for the fabric envelope. Returns "kind (response class)" or "".
func _obstacle_hit() -> String:
	if _collision_world.is_empty():
		return ""
	var s: PackedFloat64Array = sim.state
	var reach: float = float(model.bound_radius) + 0.25
	var near := _nearby_proxies(s[0], s[1], s[2], reach)
	if near.is_empty():
		return ""
	var q := s.slice(6, 10)
	var nose := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
	var speed := sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])
	var rate := sqrt(s[10] * s[10] + s[11] * s[11] + s[12] * s[12])
	var travel: float = (speed + rate * float(model.bound_radius)) * float(sim.dt())
	for proxy: Dictionary in near:
		if _envelope_hits(proxy, s, nose, travel):
			return _strike_label(proxy)
	var points := PackedFloat64Array()
	points.append_array(model.contacts.hull_points)
	points.append_array(Dynamics.prop_points(model, sim.continuous))
	for gear: Dictionary in model.contacts.gear:
		points.append_array(gear.point)
	for i in points.size() / 3:
		var w := M.q_rotate(q, points.slice(3 * i, 3 * i + 3))
		for proxy: Dictionary in near:
			if _clearance(proxy, s[0] + w[0], s[1] + w[1], s[2] + w[2]) <= travel:
				return _strike_label(proxy)
	return ""


static func _strike_label(proxy: Dictionary) -> String:
	return "%s (%s)" % [proxy.kind, proxy.get("response_class", "rigid")]


## Axis samples [x, R(x), margin] of the envelope from nose to tail, built once per prepared model.
func _build_axis_samples() -> void:
	_axis = PackedFloat64Array()
	var profile: PackedFloat64Array = model.envelope.radius_profile
	var count := profile.size() / 2
	var previous_margin := 0.0
	for i in count - 1:
		var xa := profile[2 * i]
		var ra := profile[2 * i + 1]
		var xb := profile[2 * i + 2]
		var rb := profile[2 * i + 3]
		var length := absf(xa - xb)
		var steps := maxi(1, ceili(length / AXIS_STEP_M))
		var h := length / float(steps)
		var margin := 0.5 * h * (1.0 + (absf(rb - ra) / length if length > 0.0 else 0.0))
		# Samples k = 0..steps-1 of every segment, then the tail station; a profile station shared by two
		# segments keeps the larger of their margins.
		for k in steps:
			var f := float(k) / float(steps)
			_axis.append_array([lerpf(xa, xb, f), lerpf(ra, rb, f), maxf(margin, previous_margin) if k == 0 else margin])
		previous_margin = margin
	_axis.append_array([profile[2 * count - 2], profile[2 * count - 1], previous_margin])

## Envelope against one proxy. Blocks of AXIS_BLOCK samples are rejected first from their centre sample (clearance
## is 1-Lipschitz along the axis), so a far proxy costs a few distance evaluations.
func _envelope_hits(proxy: Dictionary, s: PackedFloat64Array, nose: PackedFloat64Array, travel: float) -> bool:
	var samples := _axis.size() / 3
	var block := 0
	while block < samples:
		var last := mini(block + AXIS_BLOCK, samples) - 1
		var mid := (block + last) / 2
		var half_span := maxf(absf(_axis[3 * block] - _axis[3 * mid]), absf(_axis[3 * last] - _axis[3 * mid]))
		var widest := 0.0
		for i in range(block, last + 1):
			widest = maxf(widest, _axis[3 * i + 1] + _axis[3 * i + 2])
		var xm := _axis[3 * mid]
		if _clearance(proxy, s[0] + nose[0] * xm, s[1] + nose[1] * xm, s[2] + nose[2] * xm) - half_span <= widest + travel:
			for i in range(block, last + 1):
				var x := _axis[3 * i]
				var gap := _clearance(proxy, s[0] + nose[0] * x, s[1] + nose[1] * x, s[2] + nose[2] * x)
				if gap <= _axis[3 * i + 1] + _axis[3 * i + 2] + travel:
					return true
		block = last + 1
	return false


## Euclidean distance from a world NED point to the proxy solid (<= 0 inside).
static func _clearance(proxy: Dictionary, n: float, e: float, d: float) -> float:
	var dn := n - float(proxy.north)
	var de := e - float(proxy.east)
	var dd := d - float(proxy.down)
	if proxy.shape == "capsule":
		var along := clampf(dd, -float(proxy.half_length), float(proxy.half_length))
		return sqrt(dn * dn + de * de + (dd - along) * (dd - along)) - float(proxy.radius)
	var sh: float = proxy.sin_heading
	var ch: float = proxy.cos_heading
	var ox := absf(-dn * sh + de * ch) - float(proxy.half_x)
	var oz := absf(dn * ch + de * sh) - float(proxy.half_z)
	var od := absf(dd) - float(proxy.half_down)
	var outside := sqrt(maxf(ox, 0.0) ** 2 + maxf(oz, 0.0) ** 2 + maxf(od, 0.0) ** 2)
	return outside + minf(maxf(ox, maxf(oz, od)), 0.0)

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


## Identity of the installed obstacle inventory ("" = terrain only).
func collision_identity() -> String:
	return str(_collision_world.get("identity", ""))


## BL-08 replay: continue from a recorded accepted state (tick numbering restarts; the law is time-invariant in the
## admitted calm/steady weather). Leaves the flight running, ready for the recorded sticks.
func restore_checkpoint(state: PackedFloat64Array, continuous: PackedFloat64Array) -> bool:
	if not prepared or continuous.size() != Data.CONTINUOUS_SIZE:
		return false
	resetting.emit()
	sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	sim.continuous = continuous.duplicate()
	if not sim.reset(state.duplicate()):
		return false
	tape = PackedFloat64Array()
	tape_overflow = false
	crash = {}
	fault_reason = ""
	_info_tick = -1
	sim.set_paused(false)
	_set_paused(false, "")
	return true


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
