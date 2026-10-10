# Validated, SI-valued practice weather settings. Wind values are scenario controls, not field measurements.
class_name WindConfig
extends RefCounted

const Atmosphere = preload("res://physics/atmosphere.gd")
const ATMOSPHERE_FORMAT := "openrc-weather v3"
const ATMOSPHERE_KEYS := ["atmosphere_mode", "field_elevation_m", "temperature_c", "qnh_hpa", "relative_humidity_pct"]
const FORMAT := "openrc-weather v1"
const TURBULENCE_FORMAT := "openrc-weather v2"
const TURBULENCE_KEYS := ["turbulence_rms_mps", "turbulence_tau_s", "turbulence_seed"]

const REQUIRED_KEYS := [
	"format", "speed_mps", "from_deg", "gust_mps", "gust_up_mps",
	"gust_duration_s", "gust_period_s", "gust_delay_s",
]


static func defaults() -> Dictionary:
	return {
		"format": FORMAT,
		"speed_mps": 0.0,
		"from_deg": 0.0,
		"gust_mps": 0.0,
		"gust_up_mps": 0.0,
		"gust_duration_s": 4.0,
		"gust_period_s": 12.0,
		"gust_delay_s": 2.0,
	}


## Validate a complete weather object and return a detached, canonical configuration.
## Values are never rounded; 360 degrees is the sole canonicalization to 0 degrees.
static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("weather configuration must be an object")
		return { ok = false, config = {}, errors = errors }

	var source: Dictionary = raw
	var keys: Array = REQUIRED_KEYS.duplicate()
	var with_atmosphere: bool = source.get("format") == ATMOSPHERE_FORMAT
	var turbulent: bool = source.get("format") in [TURBULENCE_FORMAT, ATMOSPHERE_FORMAT]
	if turbulent:
		keys.append_array(TURBULENCE_KEYS)
	if with_atmosphere:
		keys.append_array(ATMOSPHERE_KEYS)
	for key: String in keys:
		if not source.has(key):
			errors.append("missing required field '%s'" % key)
	for key: Variant in source:
		if key not in keys:
			errors.append("unknown field '%s'" % str(key))
	if typeof(source.get("format")) != TYPE_STRING or source.get("format") not in [FORMAT, TURBULENCE_FORMAT, ATMOSPHERE_FORMAT]:
		errors.append("format must be '%s'" % FORMAT)

	var speed := _number(source.get("speed_mps"), "speed_mps", 0.0, 15.0, errors)
	var from_deg := _number(source.get("from_deg"), "from_deg", 0.0, 360.0, errors)
	var gust := _number(source.get("gust_mps"), "gust_mps", 0.0, 8.0, errors)
	var gust_up := _number(source.get("gust_up_mps"), "gust_up_mps", -8.0, 8.0, errors)
	var duration := _number(source.get("gust_duration_s"), "gust_duration_s", 0.5, 20.0, errors)
	var period := _number(source.get("gust_period_s"), "gust_period_s", 0.5, 120.0, errors)
	var delay := _number(source.get("gust_delay_s"), "gust_delay_s", 0.0, 3600.0, errors)
	if typeof(duration) == TYPE_FLOAT and typeof(period) == TYPE_FLOAT and period < duration:
		errors.append("gust_period_s must be greater than or equal to gust_duration_s")
	var sigma: Array = []
	var tau_s := 2.0
	var seed_value: int = 20261009
	if turbulent:
		var raw_sigma: Variant = source.get("turbulence_rms_mps")
		if not raw_sigma is Array or raw_sigma.size() != 3:
			errors.append("turbulence_rms_mps must contain three NED components")
		else:
			for axis: int in 3:
				sigma.append(_number(raw_sigma[axis], "turbulence_rms_mps[%d]" % axis, 0.0, 3.0, errors))
		tau_s = _number(source.get("turbulence_tau_s"), "turbulence_tau_s", 0.2, 30.0, errors)
		var raw_seed: Variant = source.get("turbulence_seed")
		# JSON numbers are floats; accept exactly integral uint32 values without truncation.
		if typeof(raw_seed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_seed)) \
				or float(raw_seed) < 0.0 or float(raw_seed) > 4294967295.0 or float(raw_seed) != floor(float(raw_seed)):
			errors.append("turbulence_seed must be an integer in [0, 4294967295]")
		else:
			seed_value = int(raw_seed)
	var atmosphere_settings: Dictionary = {}
	if with_atmosphere:
		var mode: Variant = source.get("atmosphere_mode")
		if typeof(mode) != TYPE_STRING or mode not in ["reference", "custom"]:
			errors.append("atmosphere_mode must be reference or custom")
		var checked_air: Dictionary = Atmosphere.evaluate(source.get("field_elevation_m"), source.get("temperature_c"),
			source.get("qnh_hpa"), source.get("relative_humidity_pct"))
		if not checked_air.ok:
			errors.append_array(checked_air.errors)
		else:
			atmosphere_settings = {atmosphere_mode = mode, field_elevation_m = float(source.field_elevation_m),
				temperature_c = float(source.temperature_c), qnh_hpa = float(source.qnh_hpa),
				relative_humidity_pct = float(source.relative_humidity_pct)}
	if not errors.is_empty():
		return { ok = false, config = {}, errors = errors }

	var result: Dictionary = {
		ok = true,
		config = {
			"format": ATMOSPHERE_FORMAT if with_atmosphere else (TURBULENCE_FORMAT if turbulent else FORMAT),
			"speed_mps": speed,
			"from_deg": 0.0 if from_deg == 360.0 else from_deg,
			"gust_mps": gust,
			"gust_up_mps": gust_up,
			"gust_duration_s": duration,
			"gust_period_s": period,
			"gust_delay_s": delay,
		},
		errors = errors,
	}

	if turbulent:
		result.config.turbulence_rms_mps = sigma
		result.config.turbulence_tau_s = tau_s
		result.config.turbulence_seed = seed_value
	if with_atmosphere:
		result.config.merge(atmosphere_settings)
	return result


## Calm-first presets are authored practice settings, not measurements of a particular flying site.
static func presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({ id = "calm", label = "Calm", config = defaults() })
	out.append({ id = "steady", label = "Steady breeze", config = _with({ "speed_mps": 3.0, "from_deg": 270.0 }) })
	out.append({ id = "crosswind", label = "Crosswind", config = _with({ "speed_mps": 5.0, "from_deg": 0.0 }) })
	out.append({ id = "gusty", label = "Gusty", config = _with({
		"speed_mps": 3.0, "from_deg": 270.0, "gust_mps": 3.0, "gust_up_mps": 1.5,
	}) })
	out.append({ id = "updraft", label = "Updraft", config = _with({
		"gust_up_mps": 2.0, "gust_period_s": 10.0,
	}) })
	out.append({ id = "turbulent", label = "Turbulence practice", config = _with({
		"format": TURBULENCE_FORMAT, "speed_mps": 3.0, "from_deg": 270.0,
		"turbulence_rms_mps": [0.6, 0.6, 0.4], "turbulence_tau_s": 2.0, "turbulence_seed": 20261009,
	}) })
	out.append({id = "hot-high", label = "Hot and high", config = upgrade_atmosphere(defaults(), {
		atmosphere_mode = "custom", field_elevation_m = 1500.0, temperature_c = 35.0, relative_humidity_pct = 50.0})})
	out.append({id = "cool-dense", label = "Cool dense air", config = upgrade_atmosphere(defaults(), {
		atmosphere_mode = "custom", temperature_c = 5.0})})
	return out


static func preset(id: String) -> Dictionary:
	for entry: Dictionary in presets():
		if entry.id == id:
			return entry.config.duplicate(true)
	return {}


## A short English summary suitable for a condition picker.
static func summary(config: Variant) -> String:
	var checked := validate(config)
	if not checked.ok:
		return "Invalid weather"
	var c: Dictionary = checked.config
	if float(c.speed_mps) == 0.0 and float(c.gust_mps) == 0.0 and float(c.gust_up_mps) == 0.0 and not has_turbulence(c) and not has_atmosphere(c):
		return "Calm"
	var parts := PackedStringArray()
	if float(c.speed_mps) > 0.0:
		parts.append("%.1f m/s from %03.0f°" % [float(c.speed_mps), float(c.from_deg)])
	if float(c.gust_mps) > 0.0 or float(c.gust_up_mps) != 0.0:
		parts.append("repeating gust every %.1f s" % float(c.gust_period_s))
	if has_turbulence(c):
		parts.append("turbulence RMS %s m/s; tau %.1f s; seed %d" % [str(c.turbulence_rms_mps), c.turbulence_tau_s, c.turbulence_seed])
	if has_atmosphere(c):
		var air: Dictionary = atmosphere(c)
		parts.append("air density %.3f kg/m³; density altitude %.0f m" % [air.rho_kgm3, air.density_altitude_m])
	return "; ".join(parts)


static func _with(changes: Dictionary) -> Dictionary:
	var config := defaults()
	for key: Variant in changes:
		config[key] = changes[key]
	return config


static func _number(value: Variant, key: String, minimum: float, maximum: float,
		errors: PackedStringArray) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("'%s' must be a finite number" % key)
		return NAN
	var number := float(value)
	if not is_finite(number):
		errors.append("'%s' must be a finite number" % key)
		return NAN
	if number < minimum or number > maximum:
		errors.append("'%s' must be in [%s, %s]" % [key, minimum, maximum])
	return number


static func has_turbulence(config: Dictionary) -> bool:
	if config.get("format") not in [TURBULENCE_FORMAT, ATMOSPHERE_FORMAT]:
		return false
	for value: float in config.turbulence_rms_mps:
		if value > 0.0:
			return true
	return false


## Promote a validated legacy configuration without losing existing wind or turbulence settings.
static func upgrade_atmosphere(config: Dictionary, changes: Dictionary = {}) -> Dictionary:
	var result: Dictionary = config.duplicate(true)
	if result.get("format") == FORMAT:
		result.merge({turbulence_rms_mps = [0.0, 0.0, 0.0], turbulence_tau_s = 2.0, turbulence_seed = 20261009})
	if result.get("format") != ATMOSPHERE_FORMAT:
		result.merge({atmosphere_mode = "reference", field_elevation_m = 0.0, temperature_c = 15.0,
			qnh_hpa = 1013.25, relative_humidity_pct = 0.0})
	result.format = ATMOSPHERE_FORMAT
	result.merge(changes, true)
	return result


static func has_atmosphere(config: Dictionary) -> bool:
	return config.get("format") == ATMOSPHERE_FORMAT and config.get("atmosphere_mode") == "custom"


## UI preview and field construction share the physical kernel; reference stays the literal legacy density.
static func atmosphere(config: Dictionary) -> Dictionary:
	if not has_atmosphere(config):
		return Atmosphere.standard()
	return Atmosphere.evaluate(config.field_elevation_m, config.temperature_c, config.qnh_hpa, config.relative_humidity_pct)
