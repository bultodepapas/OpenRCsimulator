# FW-MOON-12 (docs/plans/moon.md): the player's moon choices, validated before they reach the renderer.
# Visual only: never part of physical weather, aircraft state, checkpoints of the flight model or traces.
# Precedence: command line, then environment, then the interactive session (preferences, set by app_root), then the
# defaults. Direct technical launches never read preferences.
#   --moon=real|off|phase:<name>   | OPENRC_MOON        <name>: one of PHASES
#   --night-look=eye|cinematic|camera | OPENRC_NIGHT_LOOK
#   --moon-size=real|large         | OPENRC_MOON_SIZE   large: 2× diameter, cinematic (not real)
#   --moonlight=real|bright        | OPENRC_MOONLIGHT   bright: 3× moonlight, an assist (not real)
#   --moon-halo=auto|off           | OPENRC_MOON_HALO
extends RefCounted

const Ephemeris := preload("res://render/world/ephemeris.gd")
const Lunar := preload("res://render/world/lunar.gd")

const FORMAT := "openrc-moon-config v1"
const KEYS := ["format", "moon", "phase", "night_look", "size", "moonlight", "halo"]
const MOON_MODES := ["real", "phase", "off"]
const PHASES := ["new", "waxing_crescent", "first_quarter", "waxing_gibbous", "full", "waning_gibbous", "last_quarter",
	"waning_crescent"]
const NIGHT_LOOKS := ["eye", "cinematic", "camera"]
const SIZES := ["real", "large"]
const MOONLIGHT_CHOICES := ["real", "bright"]
const HALOS := ["auto", "off"]
## The non-physical choices' factors (the interface labels them as cinematic / assist).
const LARGE_SIZE_FACTOR := 2.0
const BRIGHT_MOONLIGHT_FACTOR := 3.0
## Each named phase as the moon's age angle: ecliptic longitude of the moon minus the sun's, degrees.
const PHASE_ELONGATION := {new = 0.0, waxing_crescent = 45.0, first_quarter = 90.0, waxing_gibbous = 135.0,
	full = 180.0, waning_gibbous = 225.0, last_quarter = 270.0, waning_crescent = 315.0}
## How far the phase choice may move the calendar (half a synodic month).
const PHASE_SEARCH_DAYS := 15
const DEFAULTS := {format = FORMAT, moon = "real", phase = "full", night_look = "eye", size = "real", moonlight = "real",
	halo = "auto"}
const _CHOICES := {moon = MOON_MODES, phase = PHASES, night_look = NIGHT_LOOKS, size = SIZES,
	moonlight = MOONLIGHT_CHOICES, halo = HALOS}
const _ARGS := {"night-look": "night_look", "moon-size": "size", "moonlight": "moonlight", "moon-halo": "halo"}
const _ENV := {OPENRC_NIGHT_LOOK = "night_look", OPENRC_MOON_SIZE = "size", OPENRC_MOONLIGHT = "moonlight",
	OPENRC_MOON_HALO = "halo"}

## The interactive route's choice (app_root sets it from preferences before Home and Fly build their worlds).
static var session_config: Dictionary = {}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## {ok, config, errors}: a complete configuration with exactly KEYS and known values; anything else is refused.
static func validate(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {ok = false, config = {}, errors = PackedStringArray(["moon config must be a dictionary"])}
	var candidate: Dictionary = raw
	var errors := PackedStringArray()
	if candidate.size() != KEYS.size() or not candidate.has_all(KEYS):
		errors.append("moon config must contain exactly %s" % ", ".join(KEYS))
	elif candidate.format != FORMAT:
		errors.append("moon config format must be %s" % FORMAT)
	else:
		for key: String in _CHOICES:
			if typeof(candidate[key]) != TYPE_STRING or not (_CHOICES[key] as Array).has(candidate[key]):
				errors.append("moon %s must be one of %s" % [key, ", ".join(_CHOICES[key])])
	if not errors.is_empty():
		return {ok = false, config = {}, errors = errors}
	return {ok = true, config = candidate.duplicate(true), errors = errors}


## The configuration for this run: defaults, then the session (if valid), then environment, then command line.
## Unknown values warn and leave the previous layer in place.
static func resolve(args: PackedStringArray = OS.get_cmdline_user_args()) -> Dictionary:
	var config := defaults()
	if not session_config.is_empty():
		var checked := validate(session_config)
		if checked.ok:
			config = checked.config
		else:
			push_warning("Ignoring invalid saved moon config: %s" % "; ".join(checked.errors))
	var moon_env := OS.get_environment("OPENRC_MOON")
	if not moon_env.is_empty():
		_apply_moon(config, moon_env, "OPENRC_MOON")
	for env: String in _ENV:
		var value := OS.get_environment(env)
		if not value.is_empty():
			_apply(config, _ENV[env], value, env)
	for arg: String in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var key := arg.substr(2).get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		if key == "moon":
			_apply_moon(config, value, "--moon")
		elif _ARGS.has(key):
			_apply(config, _ARGS[key], value, "--" + key)
	return config


## Phase choice: the nearest local date, at most PHASE_SEARCH_DAYS away and at the same clock time, whose moon age is
## closest to the named phase (daily steps: within ±6° of age). Returns `when` unchanged for the real moon or no moon.
static func apply_phase(when: Dictionary, config: Dictionary) -> Dictionary:
	if config.get("moon", "real") != "phase":
		return when
	var target: float = PHASE_ELONGATION.get(config.get("phase", "full"), 180.0)
	var jd0 := Ephemeris.julian_day(int(when.year), int(when.month), int(when.day), float(when.hour) - float(when.utc_offset_h))
	var best_offset := 0
	var best_error := INF
	for offset in range(-PHASE_SEARCH_DAYS, PHASE_SEARCH_DAYS + 1):
		var error := absf(fposmod(age_deg(jd0 + offset) - target + 180.0, 360.0) - 180.0)
		# Ties (two candidates equally close) keep the earlier date, so the result never depends on float noise.
		if error < best_error - 1e-9:
			best_error = error
			best_offset = offset
	var local := Lunar.calendar(jd0 + best_offset + float(when.utc_offset_h) / 24.0)
	var out := when.duplicate()
	out.year = local.year
	out.month = local.month
	out.day = local.day
	return out


## The moon's age angle at a Julian Day (UT): its ecliptic longitude minus the sun's, in [0, 360).
static func age_deg(jd: float) -> float:
	return fposmod(float(Ephemeris.moon(jd).longitude_deg) - float(Ephemeris.sun(jd).longitude_deg), 360.0)


## The phase name nearest to a moon age angle (for the interface).
static func phase_name(age: float) -> String:
	var best := "new"
	var best_error := INF
	for name: String in PHASE_ELONGATION:
		var error := absf(fposmod(age - float(PHASE_ELONGATION[name]) + 180.0, 360.0) - 180.0)
		if error < best_error:
			best_error = error
			best = name
	return best


static func _apply_moon(config: Dictionary, value: String, source: String) -> void:
	if value == "real" or value == "off":
		config.moon = value
	elif value.begins_with("phase:") and PHASES.has(value.trim_prefix("phase:")):
		config.moon = "phase"
		config.phase = value.trim_prefix("phase:")
	else:
		push_warning("Bad %s '%s' (real, off or phase:<%s>); keeping %s" % [source, value, "|".join(PHASES), config.moon])


static func _apply(config: Dictionary, key: String, value: String, source: String) -> void:
	if (_CHOICES[key] as Array).has(value):
		config[key] = value
	else:
		push_warning("Bad %s '%s' (%s); keeping %s" % [source, value, ", ".join(_CHOICES[key]), config[key]])
