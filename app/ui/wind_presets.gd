# UI-40q: Home's one-step wind presets. Choosing one gives exactly the weather that Conditions would apply after
# selecting the same preset and pressing Apply with nothing else edited: the wind and turbulence come from the preset,
# the air stays as it was (test_wind_presets.gd checks this against the dialog). Air and spatial presets stay in
# Conditions, where their extra choices are visible.
extends RefCounted

const WeatherSettings := preload("res://physics/wind_config.gd")

## Mild to strong. "turbulent" has no qualified rotorcraft model, so helicopters skip it.
const QUICK_IDS: Array[String] = ["calm", "gentle-practice", "steady", "crosswind", "gusty", "updraft", "turbulent"]
const ROTORCRAFT_SKIPPED: Array[String] = ["turbulent"]
## The cycle's last stop when the player's own wind was kept for the session (AppRoot.set_wind_preset).
const CUSTOM_ID := "custom"


static func ids(rotorcraft := false) -> Array[String]:
	var out: Array[String] = []
	for id: String in QUICK_IDS:
		if not (rotorcraft and ROTORCRAFT_SKIPPED.has(id)):
			out.append(id)
	return out


static func label(id: String) -> String:
	var entry := _entry(id)
	return str(entry.get("label", "Custom"))


## Home's row has room for one or two words: the same preset, shorter where its full name is long.
static func row_label(id: String) -> String:
	return "Turbulence" if id == "turbulent" else label(id)


## The validated weather after applying preset `id` to `current`, or {} for an unknown id or invalid result.
static func apply(current: Variant, id: String) -> Dictionary:
	var entry := _entry(id)
	if entry.is_empty() or entry.get("changes_atmosphere", false):
		return {}
	var checked_base: Dictionary = WeatherSettings.validate(current)
	var base: Dictionary = checked_base.config if checked_base.ok else WeatherSettings.defaults()
	var source_format := str(base.get("format", ""))
	var result: Dictionary = (entry.config as Dictionary).duplicate(true)
	if source_format in [WeatherSettings.COLUMN_FORMAT, WeatherSettings.SPATIAL_FORMAT]:
		result = WeatherSettings.upgrade_column(result)
	elif source_format == WeatherSettings.ATMOSPHERE_FORMAT:
		result = WeatherSettings.upgrade_atmosphere(result)
	if result.get("format") in [WeatherSettings.ATMOSPHERE_FORMAT, WeatherSettings.COLUMN_FORMAT, WeatherSettings.SPATIAL_FORMAT]:
		var air: Dictionary = base if source_format in [WeatherSettings.ATMOSPHERE_FORMAT, WeatherSettings.COLUMN_FORMAT] \
			else WeatherSettings.upgrade_atmosphere(base)
		for key: String in WeatherSettings.ATMOSPHERE_KEYS:
			result[key] = air[key]
	var checked: Dictionary = WeatherSettings.validate(result)
	return checked.config.duplicate(true) if checked.ok else {}


## The quick preset that `current` already is ("" for custom wind), judged by the weather it flies: a v2 file with no
## turbulence is still Steady breeze, and rotorcraft weather is compared with its turbulence removed, as Home shows it.
static func current_id(current: Variant, rotorcraft := false) -> String:
	var checked: Dictionary = WeatherSettings.validate(current)
	if not checked.ok:
		return ""
	var flown := _effective(for_aircraft(checked.config, rotorcraft))
	for id: String in ids(rotorcraft):
		var candidate := apply(checked.config, id)
		if not candidate.is_empty() and _effective(for_aircraft(candidate, rotorcraft)) == flown:
			return id
	return ""


## The next stop of Home's Wind row. With `custom_available`, the player's own wind is the stop after the strongest
## preset, so cycling never loses it for the session.
static func next_id(current: Variant, rotorcraft := false, step := 1, custom_available := false) -> String:
	var order := ids(rotorcraft)
	if custom_available:
		order.append(CUSTOM_ID)
	var id := current_id(current, rotorcraft)
	var index := order.find(id if not id.is_empty() else CUSTOM_ID)
	if index < 0:
		return order[0] if step > 0 else order[order.size() - 1]
	return order[posmod(index + step, order.size())]


## The same rotorcraft rule as AppRoot.weather_for_aircraft(), returned in validated form.
static func for_aircraft(config: Dictionary, rotorcraft: bool) -> Dictionary:
	var result := config.duplicate(true)
	if rotorcraft and WeatherSettings.has_turbulence(result):
		result.turbulence_rms_mps = [0.0, 0.0, 0.0]
	var checked: Dictionary = WeatherSettings.validate(result)
	return checked.config if checked.ok else result


## What a validated weather does in flight, without its storage format: unused turbulence timing and the values of
## the fixed reference air do not change the flight.
static func _effective(config: Dictionary) -> Dictionary:
	var out := {}
	for key: String in WeatherSettings.REQUIRED_KEYS:
		if key != "format":
			out[key] = config.get(key)
	var rms: Array = config.get("turbulence_rms_mps", [0.0, 0.0, 0.0])
	out.rms = [float(rms[0]), float(rms[1]), float(rms[2])]
	if WeatherSettings.has_turbulence(config):
		out.tau = config.get("turbulence_tau_s")
		out.seed = config.get("turbulence_seed")
	out.atmosphere_mode = str(config.get("atmosphere_mode", "reference"))
	if out.atmosphere_mode != "reference":
		for key: String in ["field_elevation_m", "temperature_c", "qnh_hpa", "relative_humidity_pct"]:
			out[key] = config.get(key)
	if config.get("format") == WeatherSettings.SPATIAL_FORMAT:
		out.spatial_wind = config.get("spatial_wind")
	return out


static func _entry(id: String) -> Dictionary:
	for entry: Dictionary in WeatherSettings.presets():
		if entry.id == id:
			return entry
	return {}
