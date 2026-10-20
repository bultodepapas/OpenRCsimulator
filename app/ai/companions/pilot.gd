extends RefCounted

## Float64, trim-relative circuit pilot for the accepted Jensen Das Ugly Stik 60.
## The manager supplies a complete session snapshot and applies this packet through FlightSession.
const Math3D := preload("res://physics/math3d.gd")
const RigidBody := preload("res://physics/rigid_body.gd")

const G := 9.80665
const UINT32_MODULUS := 4294967296.0
const MIN_COUNT := 1
const MAX_COUNT := 3
const MIN_TRIM_SPEED_MPS := 10.0
const MAX_TRIM_SPEED_MPS := 25.0
const MIN_TRIM_THROTTLE := 0.0
const MAX_TRIM_THROTTLE := 1.0
const ROUTE_RADIUS_LENGTH_FACTOR := 0.8
const ROUTE_RADIUS_WIDTH_FACTOR := 4.0
const ROUTE_CENTER_RADIUS_FACTOR := 2.0
const ROUTE_CENTER_WIDTH_FACTOR := 2.0
const BASE_HEIGHT_AGL_M := 35.0
const HEIGHT_BAND_M := 20.0
const MIN_CLEARANCE_M := 20.0
const RECOVERY_CLEARANCE_M := 30.0
const MAX_BANK_RAD := 0.4363323129985824 # 25 degrees, radians
const MAX_WIND_MPS := 4.0
const MAX_TURBULENCE_RMS_MPS := 0.30
const AVOIDANCE_HORIZON_S := 6.0
const DEFAULT_PLAYER_SEPARATION_M := 30.0

var configure_error: String = ""
var _configured: bool = false
var _slot: int = -1
var _count: int = 0
var _seed: int = 0
var _phase_rad: float = 0.0
var _direction: float = 1.0
var _target_speed_mps: float = 15.0
var _trim_throttle: float = 0.45
var _field_ground_up_m: float = 0.0
var _target_height_agl_m: float = 0.0
var _runway_north_m: float = 0.0
var _runway_east_m: float = 0.0
var _runway_length_m: float = 0.0
var _runway_width_m: float = 0.0
var _pilot_north_m: float = 0.0
var _pilot_east_m: float = 0.0
var _center_north_m: float = 0.0
var _center_east_m: float = 0.0
var _radius_m: float = 0.0
var _target_height_m: float = 0.0


## `trim` is the accepted FlightSession start/trim result (expects V and throttle when present).
## `field` is FieldLoader's normalized Club field, including its referenced runway surface.
func configure(slot: int, count: int, seed_value: int, trim: Dictionary, field: Dictionary) -> bool:
	_configured = false
	configure_error = ""
	if count < MIN_COUNT or count > MAX_COUNT or slot < 0 or slot >= count:
		return _refuse("slot/count must identify one of 1..3 companions")
	if seed_value < 0 or seed_value > 4294967295:
		return _refuse("seed must be an unsigned 32-bit integer")
	if field.get("id", "") != "default":
		return _refuse("the airborne Stik profile is qualified only for the Club field")
	if trim.is_empty():
		return _refuse("a solved FlightSession trim is required")
	var speed_result: Dictionary = _read_number(trim, ["V", "airspeed_m_s", "speed_m_s", "speed"], NAN)
	if not speed_result.ok or float(speed_result.value) < MIN_TRIM_SPEED_MPS or float(speed_result.value) > MAX_TRIM_SPEED_MPS:
		return _refuse("the trim speed must be finite and between %.1f and %.1f m/s" % [MIN_TRIM_SPEED_MPS, MAX_TRIM_SPEED_MPS])
	var throttle_result: Dictionary = _read_number(trim, ["throttle", "trim_throttle", "throttle_command"], NAN)
	if not throttle_result.ok or float(throttle_result.value) < MIN_TRIM_THROTTLE or float(throttle_result.value) > MAX_TRIM_THROTTLE:
		return _refuse("trim throttle must be finite and in [0, 1]")
	var pilot_value: Variant = field.get("pilot", {})
	if typeof(pilot_value) != TYPE_DICTIONARY:
		return _refuse("Club field is missing its normalized pilot position")
	var pilot: Dictionary = pilot_value
	var pilot_north: Dictionary = _read_number(pilot, ["north"], NAN)
	var pilot_east: Dictionary = _read_number(pilot, ["east"], NAN)
	var pilot_down: Dictionary = _read_number(pilot, ["down"], NAN)
	if not pilot_north.ok or not pilot_east.ok or not pilot_down.ok:
		return _refuse("Club field pilot coordinates must be finite")
	var runway_id: String = str(field.get("runway", ""))
	var runway: Dictionary = {}
	var surfaces_value: Variant = field.get("surfaces", [])
	if not surfaces_value is Array:
		return _refuse("Club field is missing its normalized runway surface")
	for surface_value: Variant in surfaces_value:
		if typeof(surface_value) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_value
		if str(surface.get("id", "")) == runway_id and str(surface.get("type", "")) == "runway":
			runway = surface
			break
	if runway.is_empty():
		return _refuse("Club field's referenced runway is unavailable")
	var runway_north: Dictionary = _read_number(runway, ["center_north"], NAN)
	var runway_east: Dictionary = _read_number(runway, ["center_east"], NAN)
	var runway_length: Dictionary = _read_number(runway, ["length_east_west"], NAN)
	var runway_width: Dictionary = _read_number(runway, ["width_north_south"], NAN)
	if not runway_north.ok or not runway_east.ok or not runway_length.ok or not runway_width.ok \
			or float(runway_length.value) < 40.0 or float(runway_width.value) <= 0.0:
		return _refuse("Club runway geometry must be finite and large enough for a circuit")

	_slot = slot
	_count = count
	_seed = seed_value
	_target_speed_mps = float(speed_result.value)
	_trim_throttle = float(throttle_result.value)
	_pilot_north_m = float(pilot_north.value)
	_pilot_east_m = float(pilot_east.value)
	_field_ground_up_m = -float(pilot_down.value)
	_runway_north_m = float(runway_north.value)
	_runway_east_m = float(runway_east.value)
	_runway_length_m = float(runway_length.value)
	_runway_width_m = float(runway_width.value)
	_radius_m = maxf(_runway_length_m * ROUTE_RADIUS_LENGTH_FACTOR, _runway_width_m * ROUTE_RADIUS_WIDTH_FACTOR)
	_center_north_m = _runway_north_m + ROUTE_CENTER_RADIUS_FACTOR * _radius_m + ROUTE_CENTER_WIDTH_FACTOR * _runway_width_m
	_center_east_m = _runway_east_m
	_target_height_agl_m = BASE_HEIGHT_AGL_M + float(slot) * HEIGHT_BAND_M
	_target_height_m = _field_ground_up_m + _target_height_agl_m
	# The seed moves the fleet around its shared orbit; slot offsets preserve separation.
	var seed_phase: float = TAU * float(seed_value) / UINT32_MODULUS
	_phase_rad = fposmod(seed_phase + TAU * float(slot) / float(count), TAU)
	_direction = 1.0 if (seed_value & 1) == 0 else -1.0
	var pilot_distance: float = Math3D.sqrt_((_center_north_m - _pilot_north_m) ** 2 + (_center_east_m - _pilot_east_m) ** 2)
	if not is_finite(pilot_distance) or pilot_distance - _radius_m < DEFAULT_PLAYER_SEPARATION_M:
		return _refuse("derived Club circuit intersects the pilot's 30 m exclusion volume")
	_configured = true
	return true


## Reset-boundary pose for FlightSession; the controller never writes simulation state.
func initial_pose() -> Dictionary:
	if not _configured:
		return {"ok": false, "reason": "pilot is not configured"}
	var north: float = _center_north_m + _radius_m * Math3D.cos_(_phase_rad)
	var east: float = _center_east_m + _radius_m * Math3D.sin_(_phase_rad)
	var heading: float = wrapf(_phase_rad + _direction * PI / 2.0, -PI, PI)
	return {
		"ok": true,
		"north": north,
		"east": east,
		"height_m": _target_height_m,
		"height_agl_m": _target_height_agl_m,
		"heading_rad": heading,
	}


## Snapshot contract:
## - state: PackedFloat64Array[13], rigid-body NED position, FRD body velocity, quaternion and body rates.
## - airspeed_m_s: atmosphere-relative true airspeed; wind_ned: PackedFloat64Array[3] in NED m/s.
## - ground_clearance_m: local terrain clearance; trim: FlightSession trim result (V/throttle).
## - turbulence_rms_m_s: accepted NED RMS vector. Traffic entries use the same `state` layout and may set is_player.
## Packet surface values are normalized stick deltas from solved trim; throttle is an absolute 0..1 position.
func command(snapshot: Dictionary, tick: int, traffic: Array = []) -> Dictionary:
	if not _configured:
		return _packet(false, "pilot is not configured")
	var state_value: Variant = snapshot.get("state", PackedFloat64Array())
	if not state_value is PackedFloat64Array or state_value.size() != RigidBody.SIZE:
		return _packet(false, "snapshot state must be a 13-value PackedFloat64Array")
	var state: PackedFloat64Array = state_value
	if not _array_finite(state):
		return _packet(false, "snapshot state contains a nonfinite value")
	var attitude := Math3D.quat(state[RigidBody.ATT], state[RigidBody.ATT + 1], state[RigidBody.ATT + 2], state[RigidBody.ATT + 3])
	var euler: PackedFloat64Array = Math3D.q_to_euler(attitude)
	var wind_result: Dictionary = _vector3(snapshot.get("wind_ned", PackedFloat64Array([0.0, 0.0, 0.0])))
	if not wind_result.ok:
		return _packet(false, "snapshot wind_ned must contain three finite NED values")
	var wind: PackedFloat64Array = wind_result.value
	var wind_speed: float = Math3D.sqrt_(wind[0] * wind[0] + wind[1] * wind[1] + wind[2] * wind[2])
	if wind_speed > MAX_WIND_MPS:
		return _packet(false, "Stik circuit profile is unqualified above %.1f m/s wind" % MAX_WIND_MPS)
	var turbulence_result: Dictionary = _turbulence_magnitude(snapshot)
	if not turbulence_result.ok or float(turbulence_result.value) > MAX_TURBULENCE_RMS_MPS:
		return _packet(false, "Stik circuit profile is unqualified for this turbulence level")
	var active_trim: Dictionary = snapshot.get("trim", {}) if typeof(snapshot.get("trim", {})) == TYPE_DICTIONARY else {}
	var speed_result: Dictionary = _read_number(active_trim, ["V", "airspeed_m_s", "speed_m_s", "speed"], _target_speed_mps)
	var throttle_result: Dictionary = _read_number(active_trim, ["throttle", "trim_throttle", "throttle_command"], _trim_throttle)
	if not speed_result.ok or not throttle_result.ok:
		return _packet(false, "snapshot trim speed and throttle must be finite")
	var target_speed: float = clampf(float(speed_result.value), MIN_TRIM_SPEED_MPS, MAX_TRIM_SPEED_MPS)
	var base_throttle: float = clampf(float(throttle_result.value), 0.0, 1.0)
	var wind_body: PackedFloat64Array = Math3D.q_rotate(Math3D.q_conj(attitude), wind)
	var air_body := PackedFloat64Array([
		state[RigidBody.VEL] - wind_body[0],
		state[RigidBody.VEL + 1] - wind_body[1],
		state[RigidBody.VEL + 2] - wind_body[2],
	])
	var airspeed_value: Variant = snapshot.get("airspeed_m_s", NAN)
	var airspeed: float = float(airspeed_value) if typeof(airspeed_value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(airspeed_value)) else Math3D.norm(air_body)
	if not is_finite(airspeed) or airspeed <= 0.0:
		return _packet(false, "snapshot airspeed must be finite and positive")
	var ground_velocity: PackedFloat64Array = Math3D.q_rotate(attitude,
		PackedFloat64Array([state[RigidBody.VEL], state[RigidBody.VEL + 1], state[RigidBody.VEL + 2]]))
	var north: float = state[RigidBody.POS]
	var east: float = state[RigidBody.POS + 1]
	var height: float = -state[RigidBody.POS + 2]
	var radial_north: float = north - _center_north_m
	var radial_east: float = east - _center_east_m
	var distance: float = Math3D.sqrt_(radial_north * radial_north + radial_east * radial_east)
	if not is_finite(distance) or distance < 1e-6:
		return _packet(false, "snapshot position is at the circuit center")
	var unit_north: float = radial_north / distance
	var unit_east: float = radial_east / distance
	var tangent_north: float = -_direction * unit_east
	var tangent_east: float = _direction * unit_north
	var radius_error: float = distance - _radius_m
	var radial_target: float = clampf(-0.55 * radius_error, -6.0, 6.0)
	var wind_radial: float = wind[0] * unit_north + wind[1] * unit_east
	var target_air_north: float = tangent_north * target_speed + unit_north * (radial_target - wind_radial)
	var target_air_east: float = tangent_east * target_speed + unit_east * (radial_target - wind_radial)
	var avoidance: Dictionary = _avoidance_velocity(state, attitude, ground_velocity, target_air_north, target_air_east, traffic)
	target_air_north = float(avoidance.air_north)
	target_air_east = float(avoidance.air_east)
	var target_heading: float = Math3D.atan2_(target_air_east, target_air_north)
	var course_error: float = wrapf(target_heading - euler[0], -PI, PI)
	var feed_forward_bank: float = _direction * atan2(target_speed * target_speed, G * _radius_m)
	var bank_target: float = clampf(feed_forward_bank + clampf(1.6 * course_error, -deg_to_rad(12.0), deg_to_rad(12.0)), -MAX_BANK_RAD, MAX_BANK_RAD)
	var roll_delta: float = clampf(1.8 * (bank_target - euler[2]) - 0.35 * state[RigidBody.RATE], -1.0, 1.0)
	var beta: float = Math3D.atan2_(air_body[1], Math3D.sqrt_(air_body[0] * air_body[0] + air_body[2] * air_body[2]))
	var coordinated_rate: float = G * tan(euler[2]) / maxf(airspeed, 3.0)
	var yaw_delta: float = clampf(4.0 * beta + 0.5 * (coordinated_rate - state[RigidBody.RATE + 2]), -1.0, 1.0)
	var world_velocity: PackedFloat64Array = Math3D.q_rotate(attitude,
		PackedFloat64Array([state[RigidBody.VEL], state[RigidBody.VEL + 1], state[RigidBody.VEL + 2]]))
	var target_height: float = _target_height_m
	if float(avoidance.altitude_delta) != 0.0:
		target_height += float(avoidance.altitude_delta)
	var clearance_value: Variant = snapshot.get("ground_clearance_m", height - _field_ground_up_m)
	var clearance: float = float(clearance_value) if typeof(clearance_value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(clearance_value)) else height - _field_ground_up_m
	# Avoidance descent must not enter the terrain-recovery band. Use local terrain,
	# with the lowest circuit band as the target floor; higher bands may still descend.
	if float(avoidance.altitude_delta) < 0.0:
		target_height = maxf(target_height, height - clearance + BASE_HEIGHT_AGL_M)
	var recovery: bool = clearance < RECOVERY_CLEARANCE_M
	if recovery:
		target_height = maxf(target_height, height + 10.0)
	var target_down_speed: float = -clampf((target_height - height) * 0.12, -1.5, 1.5)
	var pitch_delta: float = clampf(0.8 * (world_velocity[2] - target_down_speed) - 0.5 * state[RigidBody.RATE + 1], -1.0, 1.0)
	var throttle: float = clampf(base_throttle + 0.10 * (target_speed - airspeed), 0.0, 1.0)
	if recovery:
		throttle = 1.0
	var packet := {
		"ok": true,
		"roll": roll_delta,
		"pitch": pitch_delta,
		"yaw": yaw_delta,
		"throttle": throttle,
		"radius_error_m": radius_error,
		"target_height_m": target_height,
		"avoidance_active": bool(avoidance.active),
		"recovering_clearance": recovery,
		"tick": tick,
	}
	return packet if _packet_finite(packet) else _packet(false, "controller produced a nonfinite demand")


func _avoidance_velocity(
		state: PackedFloat64Array,
		attitude: PackedFloat64Array,
		own_velocity: PackedFloat64Array,
		base_air_north: float,
		base_air_east: float,
		traffic: Array) -> Dictionary:
	var best_severity: float = 0.0
	var best_away_north: float = 0.0
	var best_away_east: float = 0.0
	var best_vertical_delta: float = 0.0
	var own_north: float = state[RigidBody.POS]
	var own_east: float = state[RigidBody.POS + 1]
	var own_down: float = state[RigidBody.POS + 2]
	for item_value: Variant in traffic:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var item_id: String = str(item.get("id", ""))
		if item_id == "companion-%d" % _slot \
				and (not item.has("slot") or int(item.get("slot", -1)) == _slot):
			continue
		var other: Dictionary = _traffic_kinematics(item)
		if not other.ok:
			continue
		var rel_north: float = float(other.north) - own_north
		var rel_east: float = float(other.east) - own_east
		var rel_down: float = float(other.down) - own_down
		var rel_v_north: float = float(other.velocity_north) - own_velocity[0]
		var rel_v_east: float = float(other.velocity_east) - own_velocity[1]
		var rel_v_down: float = float(other.velocity_down) - own_velocity[2]
		var rel_speed_sq: float = rel_v_north * rel_v_north + rel_v_east * rel_v_east + rel_v_down * rel_v_down
		var closest_time: float = 0.0
		if rel_speed_sq > 1e-9:
			closest_time = clampf(-(rel_north * rel_v_north + rel_east * rel_v_east + rel_down * rel_v_down) / rel_speed_sq,
				0.0, AVOIDANCE_HORIZON_S)
		var closest_north: float = rel_north + rel_v_north * closest_time
		var closest_east: float = rel_east + rel_v_east * closest_time
		var closest_down: float = rel_down + rel_v_down * closest_time
		var closest_distance: float = Math3D.sqrt_(closest_north * closest_north + closest_east * closest_east + closest_down * closest_down)
		var closure_speed: float = Math3D.sqrt_(rel_speed_sq)
		var is_player: bool = bool(item.get("is_player", item.get("player", true)))
		var minimum_distance: float = DEFAULT_PLAYER_SEPARATION_M if is_player else 15.0
		minimum_distance = maxf(minimum_distance, 3.0 * float(item.get("wingspan_m", 1.7)))
		minimum_distance = maxf(minimum_distance, closure_speed * 0.5)
		if closest_distance >= minimum_distance:
			continue
		var severity: float = (minimum_distance - closest_distance) / minimum_distance
		if severity <= best_severity:
			continue
		var horizontal_distance: float = Math3D.sqrt_(closest_north * closest_north + closest_east * closest_east)
		var away_north: float
		var away_east: float
		if horizontal_distance > 1e-6:
			away_north = -closest_north / horizontal_distance
			away_east = -closest_east / horizontal_distance
		else:
			var rel_horizontal_speed: float = Math3D.sqrt_(rel_v_north * rel_v_north + rel_v_east * rel_v_east)
			if rel_horizontal_speed > 1e-6:
				away_north = _direction * rel_v_east / rel_horizontal_speed
				away_east = -_direction * rel_v_north / rel_horizontal_speed
			else:
				away_north = cos(_phase_rad)
				away_east = sin(_phase_rad)
		best_severity = severity
		best_away_north = away_north
		best_away_east = away_east
		# Replace the whole response; a weaker threat must not leave a vertical demand.
		best_vertical_delta = 0.0
		if absf(closest_down) < minimum_distance * 0.4:
			best_vertical_delta = 10.0 if closest_down > 0.0 else -10.0
	var correction_speed: float = 14.0 * best_severity if best_severity > 0.0 else 0.0
	return {
		"active": best_severity > 0.0,
		"air_north": base_air_north + best_away_north * correction_speed,
		"air_east": base_air_east + best_away_east * correction_speed,
		"altitude_delta": best_vertical_delta,
	}


func _traffic_kinematics(item: Dictionary) -> Dictionary:
	var state_value: Variant = item.get("state", PackedFloat64Array())
	if state_value is PackedFloat64Array and state_value.size() == RigidBody.SIZE and _array_finite(state_value):
		var state: PackedFloat64Array = state_value
		var attitude: PackedFloat64Array = Math3D.quat(state[RigidBody.ATT], state[RigidBody.ATT + 1], state[RigidBody.ATT + 2], state[RigidBody.ATT + 3])
		var velocity: PackedFloat64Array = Math3D.q_rotate(attitude,
			PackedFloat64Array([state[RigidBody.VEL], state[RigidBody.VEL + 1], state[RigidBody.VEL + 2]]))
		return {
			"ok": true,
			"north": state[RigidBody.POS], "east": state[RigidBody.POS + 1], "down": state[RigidBody.POS + 2],
			"velocity_north": velocity[0], "velocity_east": velocity[1], "velocity_down": velocity[2],
		}
	var position_result: Dictionary = _vector3(item.get("position_ned", PackedFloat64Array()))
	var velocity_result: Dictionary = _vector3(item.get("velocity_ned", PackedFloat64Array()))
	if not position_result.ok or not velocity_result.ok:
		return {"ok": false}
	var position: PackedFloat64Array = position_result.value
	var velocity: PackedFloat64Array = velocity_result.value
	return {
		"ok": true,
		"north": position[0], "east": position[1], "down": position[2],
		"velocity_north": velocity[0], "velocity_east": velocity[1], "velocity_down": velocity[2],
	}


func _turbulence_magnitude(snapshot: Dictionary) -> Dictionary:
	var value: Variant = snapshot.get("turbulence_rms_m_s", snapshot.get("turbulence_rms_mps", PackedFloat64Array([0.0, 0.0, 0.0])))
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		var scalar: float = float(value)
		return {"ok": is_finite(scalar) and scalar >= 0.0, "value": scalar}
	var vector_result: Dictionary = _vector3(value)
	if not vector_result.ok:
		return {"ok": false, "value": INF}
	return {"ok": true, "value": Math3D.norm(vector_result.value)}


func _packet(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason, "roll": 0.0, "pitch": 0.0, "yaw": 0.0,
		"throttle": _trim_throttle, "radius_error_m": 0.0, "target_height_m": _target_height_m,
		"avoidance_active": false, "recovering_clearance": false}


func _packet_finite(packet: Dictionary) -> bool:
	for key: String in ["roll", "pitch", "yaw", "throttle"]:
		if typeof(packet.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(packet[key])):
			return false
	return float(packet.roll) >= -1.0 and float(packet.roll) <= 1.0 \
		and float(packet.pitch) >= -1.0 and float(packet.pitch) <= 1.0 \
		and float(packet.yaw) >= -1.0 and float(packet.yaw) <= 1.0 \
		and float(packet.throttle) >= 0.0 and float(packet.throttle) <= 1.0


func _refuse(message: String) -> bool:
	configure_error = message
	return false


static func _read_number(source: Dictionary, keys: Array, fallback: float) -> Dictionary:
	for key_value: Variant in keys:
		var key: String = str(key_value)
		if not source.has(key):
			continue
		var value: Variant = source[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {"ok": false, "value": NAN}
		return {"ok": true, "value": float(value)}
	return {"ok": is_finite(fallback), "value": fallback}


static func _vector3(value: Variant) -> Dictionary:
	if value is PackedFloat64Array:
		if value.size() != 3 or not _array_finite(value):
			return {"ok": false, "value": PackedFloat64Array()}
		return {"ok": true, "value": value.duplicate()}
	if value is Array and value.size() == 3:
		var out := PackedFloat64Array()
		for entry: Variant in value:
			if typeof(entry) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry)):
				return {"ok": false, "value": PackedFloat64Array()}
			out.append(float(entry))
		return {"ok": true, "value": out}
	return {"ok": false, "value": PackedFloat64Array()}


static func _array_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
