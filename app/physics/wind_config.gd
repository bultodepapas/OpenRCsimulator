# Validated, SI-valued practice weather settings. Wind values are scenario controls, not field measurements.
class_name WindConfig
extends RefCounted

const FORMAT := "openrc-weather v1"

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
	for key: String in REQUIRED_KEYS:
		if not source.has(key):
			errors.append("missing required field '%s'" % key)
	for key: Variant in source:
		if key not in REQUIRED_KEYS:
			errors.append("unknown field '%s'" % str(key))
	if typeof(source.get("format")) != TYPE_STRING or source.get("format") != FORMAT:
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
	if not errors.is_empty():
		return { ok = false, config = {}, errors = errors }

	return {
		ok = true,
		config = {
			"format": FORMAT,
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
	if float(c.speed_mps) == 0.0 and float(c.gust_mps) == 0.0 and float(c.gust_up_mps) == 0.0:
		return "Calm"
	var parts := PackedStringArray()
	if float(c.speed_mps) > 0.0:
		parts.append("%.1f m/s from %03.0f°" % [float(c.speed_mps), float(c.from_deg)])
	if float(c.gust_mps) > 0.0 or float(c.gust_up_mps) != 0.0:
		parts.append("repeating gust every %.1f s" % float(c.gust_period_s))
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
