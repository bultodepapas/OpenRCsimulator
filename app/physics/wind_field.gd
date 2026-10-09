# Pure, spatially uniform NED wind for fixed-step flight physics. 64-bit values only.
class_name WindField
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Config := preload("res://physics/wind_config.gd")

var _config: Dictionary = {}
var _mean_ned := PackedFloat64Array([0.0, 0.0, 0.0])
var _gust_ned := PackedFloat64Array([0.0, 0.0, 0.0])
var _gust_duration_s := 4.0
var _gust_period_s := 12.0
var _gust_delay_s := 2.0
var _has_gust := false
var _calm := true


func _init() -> void:
	_apply_config(Config.defaults())


## Build a field from an untrusted configuration. Failure returns a null field and all validation errors.
static func build(raw: Variant) -> Dictionary:
	var checked: Dictionary = Config.validate(raw)
	if not checked.ok:
		return { ok = false, field = null, errors = checked.errors }
	var script: Script = load("res://physics/wind_field.gd")
	var field: Variant = script.new()
	field.call("_apply_config", checked.config)
	return { ok = true, field = field, errors = PackedStringArray() }


## A detached copy of the canonical settings used to build this field.
func configuration() -> Dictionary:
	return _config.duplicate(true)


func is_calm() -> bool:
	return _calm


## Air transport velocity [north, east, down] in m/s at simulation time.
## The field is uniform, so position is intentionally not an input in this first version.
## Invalid time is surfaced as nonfinite wind for the simulation's existing fail-closed guard.
func sample(time_s: float) -> PackedFloat64Array:
	if not is_finite(time_s) or time_s < 0.0:
		return M.v3(NAN, NAN, NAN)
	if _calm:
		return M.v3(0.0, 0.0, 0.0)
	if not _has_gust:
		return _mean_ned.duplicate()
	var elapsed: float = time_s - _gust_delay_s
	if elapsed < 0.0:
		return _mean_ned.duplicate()
	var phase: float = fposmod(elapsed, _gust_period_s)
	if not is_finite(phase):
		return M.v3(NAN, NAN, NAN)
	if phase <= 0.0 or phase >= _gust_duration_s:
		return _mean_ned.duplicate()
	var fraction: float = phase / _gust_duration_s
	var pulse: float = 0.5 * (1.0 - M.cos_(TAU * fraction))
	return M.v3(
		_mean_ned[0] + pulse * _gust_ned[0],
		_mean_ned[1] + pulse * _gust_ned[1],
		_mean_ned[2] + pulse * _gust_ned[2],
	)


func _apply_config(config: Dictionary) -> void:
	_config = config.duplicate(true)
	var from_deg: float = float(_config.from_deg)
	_mean_ned = _direction_ned(from_deg, float(_config.speed_mps))
	_gust_ned = _direction_ned(from_deg, float(_config.gust_mps))
	_gust_ned[2] = -float(_config.gust_up_mps)
	_gust_duration_s = float(_config.gust_duration_s)
	_gust_period_s = float(_config.gust_period_s)
	_gust_delay_s = float(_config.gust_delay_s)
	_has_gust = float(_config.gust_mps) != 0.0 or float(_config.gust_up_mps) != 0.0
	_calm = float(_config.speed_mps) == 0.0 and not _has_gust


## Meteorological direction is "from"; the returned vector points toward the air's transport direction.
static func _direction_ned(from_deg: float, magnitude: float) -> PackedFloat64Array:
	if magnitude == 0.0:
		return M.v3(0.0, 0.0, 0.0)
	match from_deg:
		0.0:
			return M.v3(-magnitude, 0.0, 0.0)
		90.0:
			return M.v3(0.0, -magnitude, 0.0)
		180.0:
			return M.v3(magnitude, 0.0, 0.0)
		270.0:
			return M.v3(0.0, magnitude, 0.0)
	var radians: float = deg_to_rad(from_deg)
	return M.v3(-magnitude * M.cos_(radians), -magnitude * M.sin_(radians), 0.0)
