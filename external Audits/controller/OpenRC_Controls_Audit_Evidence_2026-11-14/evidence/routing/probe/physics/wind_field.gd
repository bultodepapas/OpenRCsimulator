# Versioned NED wind for fixed-step flight physics. 64-bit values only.
class_name WindField
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Config := preload("res://physics/wind_config.gd")
const Atmosphere := preload("res://physics/atmosphere.gd")
const SpatialField := preload("res://physics/wind_spatial_field.gd")
var _spatial: RefCounted

var _atmosphere: Dictionary = {}
var _atmosphere_active := false
var _vertical_air := false
var _rho := 1.225
var _engine_charge := 1.0
var _config: Dictionary = {}
var _mean_ned := PackedFloat64Array([0.0, 0.0, 0.0])
var _gust_ned := PackedFloat64Array([0.0, 0.0, 0.0])
var _gust_duration_s := 4.0
var _gust_period_s := 12.0
var _gust_delay_s := 2.0
var _has_gust := false
var _calm := true
var _turbulent := false
var _turbulence_rms := PackedFloat64Array([0.0, 0.0, 0.0])
var _turbulence_tau := 2.0
var _turbulence_seed: int = 20261009


func _init() -> void:
	_apply_config(Config.defaults())


## Build a field from an untrusted configuration. Failure returns a null field and all validation errors.
static func build(raw: Variant) -> Dictionary:
	var checked: Dictionary = Config.validate(raw)
	if not checked.ok:
		return { ok = false, field = null, errors = checked.errors }
	var script: Script = load("res://physics/wind_field.gd")
	var field: Variant = script.new()
	if not field.call("_apply_config", checked.config):
		return {ok = false, field = null, errors = PackedStringArray(["spatial wind provider could not be constructed"])}
	return { ok = true, field = field, errors = PackedStringArray() }


## A detached copy of the canonical settings used to build this field.
func configuration() -> Dictionary:
	return _config.duplicate(true)


func is_calm() -> bool:
	# Spatial point-flow law has its own identity even if all weather amplitudes are zero.
	return _calm and _spatial == null


func is_spatial() -> bool:
	return _spatial != null


func spatial_identity() -> Dictionary:
	return _spatial.identity() if _spatial != null else {}


func spatial_content_hash() -> String:
	return _spatial.content_hash() if _spatial != null else ""


## Deterministic mean/gust background velocity [north, east, down] in m/s at simulation time.
## Stateful turbulence is added by FlightSession; this pure profile never advances RNG state.
## Legacy uniform fields only; the explicit spatial law requires sample_world.
## Invalid time is surfaced as nonfinite wind for the simulation's existing fail-closed guard.
func sample(time_s: float) -> PackedFloat64Array:
	if _spatial != null:
		return M.v3(NAN, NAN, NAN) # a spatial query must supply its physical position
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


## Position-aware query; preserves the exact legacy law for weather v1-v4.
func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	if position_ned.size() != 3:
		return M.v3(NAN, NAN, NAN)
	for component: float in position_ned:
		if not is_finite(component):
			return M.v3(NAN, NAN, NAN)
	if _spatial != null:
		var result: Dictionary = _spatial.sample_world(position_ned, time_s)
		return result.wind_ned_mps if result.get("ok", false) else M.v3(NAN, NAN, NAN)
	return sample(time_s)


func _apply_config(config: Dictionary) -> bool:
	var spatial: RefCounted = null
	if config.format == Config.SPATIAL_FORMAT:
		var built := SpatialField.build(config.spatial_wind)
		if not built.ok:
			return false
		spatial = built.field
	_config = config.duplicate(true)
	_spatial = spatial
	_atmosphere = Config.atmosphere(_config)
	_atmosphere_active = Config.has_atmosphere(_config)
	_vertical_air = Config.has_vertical_atmosphere(_config)
	_rho = _atmosphere.rho_kgm3
	_engine_charge = _atmosphere.engine_charge_ratio
	_turbulent = Config.has_turbulence(_config)
	_turbulence_rms = PackedFloat64Array(_config.get("turbulence_rms_mps", [0.0, 0.0, 0.0]))
	_turbulence_tau = float(_config.get("turbulence_tau_s", 2.0))
	_turbulence_seed = int(_config.get("turbulence_seed", 20261009))
	var from_deg: float = float(_config.from_deg)
	_mean_ned = _direction_ned(from_deg, float(_config.speed_mps))
	_gust_ned = _direction_ned(from_deg, float(_config.gust_mps))
	_gust_ned[2] = -float(_config.gust_up_mps)
	_gust_duration_s = float(_config.gust_duration_s)
	_gust_period_s = float(_config.gust_period_s)
	_gust_delay_s = float(_config.gust_delay_s)
	_has_gust = float(_config.gust_mps) != 0.0 or float(_config.gust_up_mps) != 0.0
	_calm = float(_config.speed_mps) == 0.0 and not _has_gust and not has_turbulence()
	return true


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


func has_turbulence() -> bool:
	return _turbulent


func turbulence_rms() -> PackedFloat64Array:
	return _turbulence_rms.duplicate()


func turbulence_tau() -> float:
	return _turbulence_tau


func turbulence_seed() -> int:
	return _turbulence_seed


func has_atmosphere() -> bool:
	return _atmosphere_active


func has_vertical_atmosphere() -> bool:
	return _vertical_air


func atmosphere_law() -> String:
	if _vertical_air:
		return Atmosphere.STANDARD_COLUMN_LAW
	return "uniform-field-qnh-isa-buck-liquid-v1"


func atmosphere(down_m: float = 0.0) -> Dictionary:
	if _vertical_air:
		return Atmosphere.standard_column(float(_config.field_elevation_m) - down_m)
	return _atmosphere.duplicate(true)


func air_density(down_m: float = 0.0) -> float:
	if _vertical_air:
		var air: Dictionary = atmosphere(down_m)
		if not air.ok:
			return NAN
		return float(air.rho_kgm3)
	return _rho


func engine_charge_ratio(down_m: float = 0.0) -> float:
	if _vertical_air:
		var air: Dictionary = atmosphere(down_m)
		if not air.ok:
			return NAN
		return float(air.engine_charge_ratio)
	return _engine_charge
