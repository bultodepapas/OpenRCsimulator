extends RefCounted
class_name WindsockMotion

## Render-only, deterministic motion for a field windsock.
## wind_ned is the actual air-velocity vector in NED (m/s), so its horizontal
## direction is where the sock tail points (wind TO). No simulation state is
## changed, and this model has no process callback.

const STEP_S: float = 1.0 / 120.0
const MAX_GAP_S: float = 0.5
const MAX_STEPS_PER_UPDATE: int = 60
const MAX_WIND_SPEED_MPS: float = 40.0
const CENTERLINE_POINT_COUNT: int = 13
const RIGID_FRACTION: float = 0.375

## FAA AC 150/5345-27F specifies a 3 kt swivel acceptance condition and full
## cone extension at 15 kt. It gives no response time or partial extension law.
const SWIVEL_REFERENCE_MPS: float = 1.54333
const FULL_EXTENSION_MPS: float = 7.71667

## Dynamic response rates and the partial inflation mapping are estimates.
const YAW_NATURAL_FREQUENCY_RAD_S: float = 4.0
const YAW_DAMPING_RATIO: float = 1.0
const YAW_RATE_LIMIT_RAD_S: float = 4.0
const YAW_PASSIVE_DAMPING_PER_S: float = 2.0
const INFLATION_RISE_TIME_S: float = 0.35
const INFLATION_FALL_TIME_S: float = 0.8
const FLEX_NATURAL_FREQUENCY_RAD_S: float = 3.5
const FLEX_DAMPING_RATIO: float = 1.0

## Seven inextensible tail links turn smoothly toward the gravity-hanging pose.
const CALM_DROOP_ANGLE_RAD: float = PI * 0.5
const BEND_RAMP_FRACTION: float = 0.42
const MAX_CROSSWIND_ANGLE_RAD: float = 0.45
const MAX_VERTICAL_AIRFLOW_ANGLE_RAD: float = 0.25
const MAX_UPWARD_FLEX_ANGLE_RAD: float = 0.25

var length_m: float = 2.5
var throat_diameter_m: float = 0.45
var tail_diameter_m: float = 0.12

## Yaw about the pole's local +Y axis. Zero is local +X; positive yaw turns +X
## toward local -Z, matching Godot's rotation convention.
var basket_yaw_rad: float = 0.0
## Normalized fabric extension. Intermediate extension is a presentation estimate.
var inflation: float = 0.0
## Thirteen mouth-to-tail points in metres, relative to the mouth and before yaw.
## Local +X points downwind, +Y is up, and +Z is crosswind.
var centerline_local: PackedVector3Array = PackedVector3Array()

## Exact time represented by the current integrated state.
var simulated_time_s: float = 0.0
## Absolute fixed-step count since the most recent reset epoch.
var simulated_step_index: int = 0

var _initialized: bool = false
var _epoch_time_s: float = 0.0
var _last_observed_time_s: float = 0.0
var _held_wind_render: Vector3 = Vector3.ZERO
var _yaw_rate_rad_s: float = 0.0
var _droop_angle_rad: float = CALM_DROOP_ANGLE_RAD
var _droop_rate_rad_s: float = 0.0
var _crosswind_angle_rad: float = 0.0
var _crosswind_rate_rad_s: float = 0.0


func _init(
		p_length_m: float = 2.5,
		p_throat_diameter_m: float = 0.45,
		p_tail_diameter_m: float = 0.12) -> void:
	length_m = _dimension_or_default(p_length_m, 2.5, 0.25, 10.0)
	throat_diameter_m = _dimension_or_default(p_throat_diameter_m, 0.45, 0.02, 2.0)
	tail_diameter_m = _dimension_or_default(p_tail_diameter_m, 0.12, 0.01, 1.0)
	centerline_local.resize(CENTERLINE_POINT_COUNT)
	reset()


## Reset clears all lag and sets the basket to the current horizontal wind.
## The sleeve starts uninflated with its unsupported tail hanging under gravity.
func reset(time_s: float = 0.0, wind_ned: Array = [0.0, 0.0, 0.0]) -> bool:
	if not _valid_time_and_wind(time_s, wind_ned):
		return false
	_epoch_time_s = time_s
	_last_observed_time_s = time_s
	simulated_step_index = 0
	simulated_time_s = time_s
	_held_wind_render = _render_wind_from_ned(wind_ned)
	var horizontal_speed: float = Vector2(_held_wind_render.x, _held_wind_render.z).length()
	if horizontal_speed > 1.0e-6:
		basket_yaw_rad = atan2(-_held_wind_render.z, _held_wind_render.x)
	else:
		basket_yaw_rad = 0.0
	_yaw_rate_rad_s = 0.0
	inflation = 0.0
	_droop_angle_rad = CALM_DROOP_ANGLE_RAD
	_droop_rate_rad_s = 0.0
	_crosswind_angle_rad = 0.0
	_crosswind_rate_rad_s = 0.0
	_initialized = true
	_rebuild_centerline()
	return true


## Advance to an absolute simulation time. Feed each field sample when wind
## varies; same-time calls hold state (pause). Backward time resets at the
## supplied sample, so exact rewind requires reset() and replaying the same
## samples. A forward gap over 0.5 s resets rather than causing catch-up work.
func update_to(time_s: float, wind_ned: Array) -> bool:
	if not _valid_time_and_wind(time_s, wind_ned):
		return false
	if not _initialized:
		return reset(time_s, wind_ned)
	if time_s < _last_observed_time_s - 1.0e-12:
		return reset(time_s, wind_ned)
	var elapsed_s: float = time_s - _last_observed_time_s
	_last_observed_time_s = time_s
	_held_wind_render = _render_wind_from_ned(wind_ned)
	if elapsed_s > MAX_GAP_S:
		return reset(time_s, wind_ned)
	var target_step_index: int = int(floor((time_s - _epoch_time_s) / STEP_S + 1.0e-9))
	if target_step_index < simulated_step_index:
		return reset(time_s, wind_ned)
	var steps_to_run: int = target_step_index - simulated_step_index
	if steps_to_run > MAX_STEPS_PER_UPDATE:
		return reset(time_s, wind_ned)
	for _step: int in range(steps_to_run):
		_integrate_step(STEP_S)
		simulated_step_index += 1
	simulated_time_s = _epoch_time_s + float(simulated_step_index) * STEP_S
	return true


## State snapshot supports deterministic evidence and comparisons.
func state_snapshot() -> Dictionary:
	return {
		"simulated_time_s": simulated_time_s,
		"simulated_step_index": simulated_step_index,
		"basket_yaw_rad": basket_yaw_rad,
		"yaw_rate_rad_s": _yaw_rate_rad_s,
		"inflation": inflation,
		"droop_angle_rad": _droop_angle_rad,
		"droop_rate_rad_s": _droop_rate_rad_s,
		"crosswind_angle_rad": _crosswind_angle_rad,
		"crosswind_rate_rad_s": _crosswind_rate_rad_s,
		"centerline_local": centerline_local.duplicate(),
	}


func _integrate_step(dt_s: float) -> void:
	var horizontal_speed_mps: float = Vector2(_held_wind_render.x, _held_wind_render.z).length()
	_update_yaw(horizontal_speed_mps, dt_s)
	var wind_local: Vector3 = _held_wind_render.rotated(Vector3.UP, -basket_yaw_rad)
	# Only positive flow down the sock axis enters the mouth and inflates it.
	var positive_axial_speed_mps: float = maxf(wind_local.x, 0.0)
	var target_inflation: float = clampf(positive_axial_speed_mps / FULL_EXTENSION_MPS, 0.0, 1.0)
	var inflation_time_s: float = INFLATION_RISE_TIME_S if target_inflation > inflation else INFLATION_FALL_TIME_S
	var inflation_alpha: float = 1.0 - exp(-dt_s / inflation_time_s)
	inflation = clampf(inflation + (target_inflation - inflation) * inflation_alpha, 0.0, 1.0)

	var total_speed_mps: float = maxf(wind_local.length(), 1.0e-6)
	var vertical_ratio: float = clampf(wind_local.y / total_speed_mps, -1.0, 1.0)
	var cross_ratio: float = clampf(wind_local.z / total_speed_mps, -1.0, 1.0)
	var vertical_speed_gain: float = clampf(total_speed_mps / FULL_EXTENSION_MPS, 0.0, 1.0)
	vertical_speed_gain *= vertical_speed_gain
	var target_droop_rad: float = CALM_DROOP_ANGLE_RAD * (1.0 - inflation)
	target_droop_rad -= MAX_VERTICAL_AIRFLOW_ANGLE_RAD * maxf(vertical_ratio, 0.0) * vertical_speed_gain
	target_droop_rad += MAX_VERTICAL_AIRFLOW_ANGLE_RAD * maxf(-vertical_ratio, 0.0) * vertical_speed_gain
	target_droop_rad = clampf(target_droop_rad, -MAX_UPWARD_FLEX_ANGLE_RAD, CALM_DROOP_ANGLE_RAD)
	var crosswind_gain: float = clampf(total_speed_mps / FULL_EXTENSION_MPS, 0.0, 1.0)
	var target_crosswind_rad: float = MAX_CROSSWIND_ANGLE_RAD * cross_ratio * crosswind_gain
	var droop_state: Vector2 = _advance_flex_mode(
		_droop_angle_rad, _droop_rate_rad_s, target_droop_rad,
		-MAX_UPWARD_FLEX_ANGLE_RAD, CALM_DROOP_ANGLE_RAD, PI, dt_s)
	_droop_angle_rad = droop_state.x
	_droop_rate_rad_s = droop_state.y
	var crosswind_state: Vector2 = _advance_flex_mode(
		_crosswind_angle_rad, _crosswind_rate_rad_s, target_crosswind_rad,
		-MAX_CROSSWIND_ANGLE_RAD, MAX_CROSSWIND_ANGLE_RAD,
		MAX_CROSSWIND_ANGLE_RAD * 8.0, dt_s)
	_crosswind_angle_rad = crosswind_state.x
	_crosswind_rate_rad_s = crosswind_state.y
	_rebuild_centerline()


func _update_yaw(horizontal_speed_mps: float, dt_s: float) -> void:
	if horizontal_speed_mps < 1.0e-6:
		var decay: float = exp(-YAW_PASSIVE_DAMPING_PER_S * dt_s)
		basket_yaw_rad = wrapf(
			basket_yaw_rad + _yaw_rate_rad_s * (1.0 - decay) / YAW_PASSIVE_DAMPING_PER_S,
			-PI,
			PI)
		_yaw_rate_rad_s *= decay
		return
	var target_yaw_rad: float = atan2(-_held_wind_render.z, _held_wind_render.x)
	# wrapf maps the exact 180-degree tie to -PI, so reversal direction is stable.
	var yaw_error_rad: float = wrapf(target_yaw_rad - basket_yaw_rad, -PI, PI)
	# The 3 kt FAA condition is not a lower-speed dead zone; response scales down
	# continuously so light winds can still slowly turn the vane.
	var speed_ratio: float = minf(horizontal_speed_mps / SWIVEL_REFERENCE_MPS, 3.0)
	var natural_frequency_rad_s: float = YAW_NATURAL_FREQUENCY_RAD_S * sqrt(speed_ratio)
	var angular_acceleration_rad_s2: float = natural_frequency_rad_s * natural_frequency_rad_s * yaw_error_rad
	angular_acceleration_rad_s2 -= 2.0 * YAW_DAMPING_RATIO * natural_frequency_rad_s * _yaw_rate_rad_s
	_yaw_rate_rad_s = clampf(
		_yaw_rate_rad_s + angular_acceleration_rad_s2 * dt_s,
		-YAW_RATE_LIMIT_RAD_S,
		YAW_RATE_LIMIT_RAD_S)
	basket_yaw_rad = wrapf(basket_yaw_rad + _yaw_rate_rad_s * dt_s, -PI, PI)


func _advance_flex_mode(
		value: float,
		velocity: float,
		target: float,
		minimum: float,
		maximum: float,
		maximum_rate: float,
		dt_s: float) -> Vector2:
	var natural_frequency_rad_s: float = FLEX_NATURAL_FREQUENCY_RAD_S
	var acceleration: float = natural_frequency_rad_s * natural_frequency_rad_s * (target - value)
	acceleration -= 2.0 * FLEX_DAMPING_RATIO * natural_frequency_rad_s * velocity
	velocity = clampf(velocity + acceleration * dt_s, -maximum_rate, maximum_rate)
	value += velocity * dt_s
	var bounded_value: float = clampf(value, minimum, maximum)
	if not is_equal_approx(value, bounded_value):
		if (value > maximum and velocity > 0.0) or (value < minimum and velocity < 0.0):
			velocity = 0.0
		value = bounded_value
	return Vector2(value, velocity)


func _rebuild_centerline() -> void:
	if centerline_local.size() != CENTERLINE_POINT_COUNT:
		centerline_local.resize(CENTERLINE_POINT_COUNT)
	var rigid_length_m: float = length_m * RIGID_FRACTION
	var flexible_length_m: float = length_m - rigid_length_m
	for point_index: int in CENTERLINE_POINT_COUNT:
		if point_index <= 5:
			var station_m: float = rigid_length_m * float(point_index) / 5.0
			centerline_local[point_index] = Vector3(station_m, 0.0, 0.0)
			continue
	var segment_length_m: float = flexible_length_m / 7.0
	var cursor: Vector3 = Vector3(rigid_length_m, 0.0, 0.0)
	for segment_index: int in 7:
		var segment_midpoint_fraction: float = (float(segment_index) + 0.5) / 7.0
		var ramp_fraction: float = clampf(segment_midpoint_fraction / BEND_RAMP_FRACTION, 0.0, 1.0)
		var bend_weight: float = ramp_fraction * ramp_fraction * (3.0 - 2.0 * ramp_fraction)
		var droop_angle_rad: float = _droop_angle_rad * bend_weight
		var lateral_angle_rad: float = _crosswind_angle_rad * bend_weight
		var horizontal_fraction: float = cos(droop_angle_rad)
		cursor += Vector3(
			segment_length_m * horizontal_fraction * cos(lateral_angle_rad),
			-segment_length_m * sin(droop_angle_rad),
			segment_length_m * horizontal_fraction * sin(lateral_angle_rad))
		centerline_local[6 + segment_index] = cursor


func _valid_time_and_wind(time_s: float, wind_ned: Array) -> bool:
	if not is_finite(time_s) or time_s < 0.0 or wind_ned.size() != 3:
		return false
	for component: Variant in wind_ned:
		if typeof(component) != TYPE_FLOAT and typeof(component) != TYPE_INT:
			return false
		if not is_finite(float(component)):
			return false
	return true


func _render_wind_from_ned(wind_ned: Array) -> Vector3:
	var north_mps: float = float(wind_ned[0])
	var east_mps: float = float(wind_ned[1])
	var down_mps: float = float(wind_ned[2])
	var component_scale: float = maxf(absf(north_mps), maxf(absf(east_mps), absf(down_mps)))
	if component_scale > 0.0:
		var north_unit: float = north_mps / component_scale
		var east_unit: float = east_mps / component_scale
		var down_unit: float = down_mps / component_scale
		var scaled_norm: float = sqrt(north_unit * north_unit + east_unit * east_unit + down_unit * down_unit)
		if component_scale > MAX_WIND_SPEED_MPS / scaled_norm:
			var scale: float = (MAX_WIND_SPEED_MPS / scaled_norm) / component_scale
			north_mps *= scale
			east_mps *= scale
			down_mps *= scale
	return Vector3(east_mps, -down_mps, -north_mps)


static func _dimension_or_default(value: float, default_value: float, minimum: float, maximum: float) -> float:
	if not is_finite(value):
		return default_value
	return clampf(value, minimum, maximum)
