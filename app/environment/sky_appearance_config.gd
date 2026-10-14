extends RefCounted
class_name SkyConfig

const FORMAT := "openrc-sky-appearance v1"
const PRESET_FORMAT := "openrc-sky-weather-presets v1"
const PRESET_PATH := "res://data/sky/weather_presets.json"

const CONFIG_KEYS := [
	"format", "preset", "seed", "motion", "wind_aloft_speed_mps",
	"wind_aloft_from_deg", "flashes", "thunder_volume",
]
const ARG_KEYS := [
	"sky", "cloud-motion", "cloud-seed", "cloud-wind-speed", "cloud-wind-from",
	"storm-flashes", "thunder-volume",
]
const EXPECTED_PRESET_IDS := [
	"classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast",
	"prestorm", "distant_storm", "electrical_storm",
]
const MOTION_MODES := ["legacy", "still", "follow_wind", "aloft"]
const FLASH_MODES := ["full", "reduced", "off"]
const CLOUD_LAYER_TYPES := [
	"cirrus", "fair_cumulus", "cumulus", "stratocumulus", "stratus", "cumulonimbus", "anvil",
]
const RENDERER_KEYS := [
	"cloud_cover", "cloud_density", "cloud_layers", "zenith_color", "horizon_color",
	"cloud_color", "sun_color", "ambient_color", "sun_intensity", "ambient_intensity",
	"haze", "cloud_shadow",
]
const LAYER_KEYS := ["type", "altitude_m", "coverage", "density", "scale_m", "drift_multiplier"]

const DEFAULTS: Dictionary = {
	"format": FORMAT,
	"preset": "classic",
	"seed": 1253,
	"motion": "legacy",
	"wind_aloft_speed_mps": 0.0,
	"wind_aloft_from_deg": 0.0,
	"flashes": "full",
	"thunder_volume": 0.7,
}

static var _catalog_cache: Dictionary = {}


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


static func for_preset(id: String) -> Dictionary:
	var state := _catalog_state()
	if not state.ok or not state.by_id.has(id):
		return {}
	var config := defaults()
	config["preset"] = id
	if id != "classic":
		config["motion"] = "follow_wind"
	return config


static func presets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var state := _catalog_state()
	if not state.ok:
		return entries
	for profile: Dictionary in state.profiles:
		entries.append(profile.duplicate(true))
	return entries


static func validate(raw: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure(PackedStringArray(["sky appearance must be a dictionary"]))
	var candidate: Dictionary = raw
	if not _has_exact_keys(candidate, CONFIG_KEYS):
		for key: String in CONFIG_KEYS:
			if not candidate.has(key):
				errors.append("missing sky appearance field: %s" % key)
		for key: Variant in candidate.keys():
			if typeof(key) != TYPE_STRING or not key in CONFIG_KEYS:
				errors.append("unknown sky appearance field: %s" % str(key))
	if typeof(candidate.get("format")) != TYPE_STRING or candidate.get("format") != FORMAT:
		errors.append("format must be %s" % FORMAT)
	if typeof(candidate.get("preset")) != TYPE_STRING or String(candidate.get("preset", "")).is_empty():
		errors.append("preset must be a non-empty catalog ID")
	if typeof(candidate.get("seed")) != TYPE_INT:
		errors.append("seed must be an integer")
	else:
		var seed_value: int = candidate["seed"]
		if seed_value < 0 or seed_value > 2147483647:
			errors.append("seed must be between 0 and 2147483647")
	if typeof(candidate.get("motion")) != TYPE_STRING or not candidate.get("motion") in MOTION_MODES:
		errors.append("motion must be legacy, still, follow_wind, or aloft")
	if not _in_range(candidate.get("wind_aloft_speed_mps"), 0.0, 50.0):
		errors.append("wind_aloft_speed_mps must be a finite number from 0 to 50")
	if not _in_range(candidate.get("wind_aloft_from_deg"), 0.0, 360.0, false):
		errors.append("wind_aloft_from_deg must be a finite number from 0 inclusive to 360 exclusive")
	if typeof(candidate.get("flashes")) != TYPE_STRING or not candidate.get("flashes") in FLASH_MODES:
		errors.append("flashes must be full, reduced, or off")
	if not _in_range(candidate.get("thunder_volume"), 0.0, 1.0):
		errors.append("thunder_volume must be a finite number from 0 to 1")
	if not errors.is_empty():
		return _failure(errors)

	var state := _catalog_state()
	if not state.ok:
		return _failure(state.errors)
	var preset_id: String = candidate["preset"]
	if not state.by_id.has(preset_id):
		return _failure(PackedStringArray(["unknown sky preset: %s" % preset_id]))
	var config := {
		"format": FORMAT,
		"preset": preset_id,
		"seed": int(candidate["seed"]),
		"motion": String(candidate["motion"]),
		"wind_aloft_speed_mps": float(candidate["wind_aloft_speed_mps"]),
		"wind_aloft_from_deg": float(candidate["wind_aloft_from_deg"]),
		"flashes": String(candidate["flashes"]),
		"thunder_volume": float(candidate["thunder_volume"]),
	}
	return {
		"ok": true,
		"config": config,
		"profile": state.by_id[preset_id].duplicate(true),
		"errors": PackedStringArray(),
	}


static func from_args(args: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	for key: Variant in args.keys():
		if typeof(key) != TYPE_STRING:
			errors.append("unknown sky option --%s" % str(key))
		elif not key in ARG_KEYS and (key.begins_with("sky-") or key.begins_with("cloud-") \
				or key.begins_with("storm-") or key.begins_with("thunder-")):
			errors.append("unknown sky option --%s" % str(key))
	if not errors.is_empty():
		return _failure(errors)

	var config := defaults()
	if args.has("sky"):
		if typeof(args["sky"]) != TYPE_STRING:
			return _failure(PackedStringArray(["--sky requires a preset ID value" ]))
		config = for_preset(String(args["sky"]))
		if config.is_empty():
			return _failure(PackedStringArray(["unknown sky preset: %s" % str(args["sky"])]))
	if args.has("cloud-motion"):
		if typeof(args["cloud-motion"]) != TYPE_STRING:
			return _failure(PackedStringArray(["--cloud-motion requires a value" ]))
		config["motion"] = args["cloud-motion"]
	if args.has("cloud-seed"):
		var seed_result := _parse_seed_arg(args["cloud-seed"])
		if not seed_result.ok:
			return _failure(PackedStringArray([seed_result.error]))
		config["seed"] = seed_result.value
	if args.has("cloud-wind-speed"):
		var speed_result := _parse_float_arg(args["cloud-wind-speed"], "--cloud-wind-speed")
		if not speed_result.ok:
			return _failure(PackedStringArray([speed_result.error]))
		config["wind_aloft_speed_mps"] = speed_result.value
	if args.has("cloud-wind-from"):
		var direction_result := _parse_float_arg(args["cloud-wind-from"], "--cloud-wind-from")
		if not direction_result.ok:
			return _failure(PackedStringArray([direction_result.error]))
		config["wind_aloft_from_deg"] = direction_result.value
	if args.has("storm-flashes"):
		if typeof(args["storm-flashes"]) != TYPE_STRING:
			return _failure(PackedStringArray(["--storm-flashes requires a value" ]))
		config["flashes"] = args["storm-flashes"]
	if args.has("thunder-volume"):
		var thunder_result := _parse_float_arg(args["thunder-volume"], "--thunder-volume")
		if not thunder_result.ok:
			return _failure(PackedStringArray([thunder_result.error]))
		config["thunder_volume"] = thunder_result.value
	return validate(config)


static func summary(config: Dictionary) -> String:
	var checked := validate(config)
	if not checked.ok:
		return ""
	var profile: Dictionary = checked.profile
	return str(profile.name)


static func identity(config: Dictionary) -> String:
	var checked := validate(config)
	if not checked.ok:
		return ""
	var canonical_json := JSON.stringify(checked.config, "", true, true)
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hasher.update(canonical_json.to_utf8_buffer())
	return hasher.finish().hex_encode()


static func mean_wind_ned(weather: Dictionary) -> Array[float]:
	if weather.is_empty():
		return [0.0, 0.0, 0.0]
	var speed_value: Variant = weather.get("speed_mps", NAN)
	var from_value: Variant = weather.get("from_deg", NAN)
	if not _is_finite_number(speed_value) or not _is_finite_number(from_value):
		return [0.0, 0.0, 0.0]
	var speed := float(speed_value)
	var from_deg := float(from_value)
	if speed <= 0.0:
		return [0.0, 0.0, 0.0]
	if from_deg < 0.0 or from_deg >= 360.0:
		return [0.0, 0.0, 0.0]
	var bearing := deg_to_rad(from_deg)
	return [-speed * cos(bearing), -speed * sin(bearing), 0.0]


static func _parse_seed_arg(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "error": "--cloud-seed requires a decimal integer"}
	var text_value: String = value
	if text_value.is_empty():
		return {"ok": false, "error": "--cloud-seed requires a decimal integer"}
	for index: int in range(text_value.length()):
		var codepoint := text_value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return {"ok": false, "error": "--cloud-seed requires a decimal integer"}
	var significant := text_value.trim_prefix("0")
	while significant.length() > 1 and significant.begins_with("0"):
		significant = significant.trim_prefix("0")
	if significant.is_empty():
		significant = "0"
	if significant.length() > 10 or (significant.length() == 10 and significant > "2147483647"):
		return {"ok": false, "error": "--cloud-seed must be between 0 and 2147483647"}
	return {"ok": true, "value": significant.to_int()}


static func _parse_float_arg(value: Variant, option_name: String) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "error": "%s requires a finite number" % option_name}
	var text_value: String = value
	if text_value.is_empty() or text_value != text_value.strip_edges() or not text_value.is_valid_float():
		return {"ok": false, "error": "%s requires a finite number" % option_name}
	var parsed := text_value.to_float()
	if not is_finite(parsed):
		return {"ok": false, "error": "%s requires a finite number" % option_name}
	return {"ok": true, "value": parsed}


static func _catalog_state() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache.duplicate(true)
	if not FileAccess.file_exists(PRESET_PATH):
		return {"ok": false, "errors": PackedStringArray(["weather preset catalog is missing: %s" % PRESET_PATH])}
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(PRESET_PATH))
	if parse_error != OK:
		return {"ok": false, "errors": PackedStringArray(["weather preset catalog JSON error: %s" % parser.get_error_message()])}
	var data: Variant = parser.data
	var errors := PackedStringArray()
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["weather preset catalog must be an object"])}
	if not _has_exact_keys(data, ["format", "presets"]):
		errors.append("weather preset catalog must contain only format and presets")
	if data.get("format") != PRESET_FORMAT:
		errors.append("weather preset catalog format must be %s" % PRESET_FORMAT)
	if typeof(data.get("presets")) != TYPE_ARRAY:
		errors.append("weather preset catalog presets must be an array")
		return {"ok": false, "errors": errors}
	var source_profiles: Array = data["presets"]
	if source_profiles.size() != EXPECTED_PRESET_IDS.size():
		errors.append("weather preset catalog must contain exactly %d presets" % EXPECTED_PRESET_IDS.size())
	var profiles: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for index: int in range(source_profiles.size()):
		var profile: Variant = source_profiles[index]
		if typeof(profile) != TYPE_DICTIONARY:
			errors.append("weather preset at index %d must be an object" % index)
			continue
		var profile_errors := _validate_profile(profile)
		for message: String in profile_errors:
			errors.append(message)
		if typeof(profile.get("id")) != TYPE_STRING:
			continue
		var profile_id: String = profile["id"]
		if by_id.has(profile_id):
			errors.append("duplicate weather preset ID: %s" % profile_id)
			continue
		if index < EXPECTED_PRESET_IDS.size() and profile_id != EXPECTED_PRESET_IDS[index]:
			errors.append("weather preset index %d must be %s" % [index, EXPECTED_PRESET_IDS[index]])
		if not profile_id in EXPECTED_PRESET_IDS:
			errors.append("unknown weather preset ID: %s" % profile_id)
		profiles.append(profile.duplicate(true))
		by_id[profile_id] = profile.duplicate(true)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	_catalog_cache = {"ok": true, "profiles": profiles, "by_id": by_id, "errors": PackedStringArray()}
	return _catalog_cache.duplicate(true)


static func _validate_profile(profile: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _has_exact_keys(profile, ["id", "name", "description", "renderer"]):
		errors.append("weather profile must contain only id, name, description, and renderer")
	for key: String in ["id", "name", "description"]:
		if typeof(profile.get(key)) != TYPE_STRING or String(profile.get(key, "")).is_empty():
			errors.append("weather profile %s must be a non-empty string" % key)
	if typeof(profile.get("renderer")) != TYPE_DICTIONARY:
		errors.append("weather profile renderer must be an object")
		return errors
	var renderer: Dictionary = profile["renderer"]
	if not _has_exact_keys(renderer, RENDERER_KEYS):
		errors.append("weather renderer must contain the complete versioned appearance schema")
	for scalar_key: String in ["cloud_cover", "cloud_density", "haze", "cloud_shadow"]:
		if not _in_range(renderer.get(scalar_key), 0.0, 1.0):
			errors.append("weather renderer %s must be from 0 to 1" % scalar_key)
	for scalar_key: String in ["sun_intensity", "ambient_intensity"]:
		if not _in_range(renderer.get(scalar_key), 0.0, 2.0):
			errors.append("weather renderer %s must be from 0 to 2" % scalar_key)
	for color_key: String in ["zenith_color", "horizon_color", "cloud_color", "sun_color", "ambient_color"]:
		if not _valid_color(renderer.get(color_key)):
			errors.append("weather renderer %s must be three RGB values from 0 to 1" % color_key)
	if typeof(renderer.get("cloud_layers")) != TYPE_ARRAY:
		errors.append("weather renderer cloud_layers must be an array")
		return errors
	var layers: Array = renderer["cloud_layers"]
	if layers.size() > 8:
		errors.append("weather renderer may contain no more than 8 cloud layers")
	for index: int in range(layers.size()):
		var layer: Variant = layers[index]
		if typeof(layer) != TYPE_DICTIONARY:
			errors.append("weather cloud layer %d must be an object" % index)
			continue
		if not _has_exact_keys(layer, LAYER_KEYS):
			errors.append("weather cloud layer %d must contain the complete layer schema" % index)
		if typeof(layer.get("type")) != TYPE_STRING or not layer.get("type") in CLOUD_LAYER_TYPES:
			errors.append("weather cloud layer %d has an unsupported type" % index)
		for range_spec: Array in [
			["altitude_m", 0.0, 20000.0],
			["coverage", 0.0, 1.0],
			["density", 0.0, 1.0],
			["scale_m", 100.0, 50000.0],
			["drift_multiplier", 0.0, 4.0],
		]:
			var field_name: String = range_spec[0]
			if not _in_range(layer.get(field_name), range_spec[1], range_spec[2]):
				errors.append("weather cloud layer %d %s is out of range" % [index, field_name])
	return errors


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true


static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))


static func _in_range(value: Variant, minimum: float, maximum: float, maximum_inclusive: bool = true) -> bool:
	if not _is_finite_number(value):
		return false
	var numeric := float(value)
	if numeric < minimum:
		return false
	return numeric <= maximum if maximum_inclusive else numeric < maximum


static func _valid_color(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return false
	for component: Variant in value:
		if not _in_range(component, 0.0, 1.0):
			return false
	return true


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {"ok": false, "config": {}, "profile": {}, "errors": errors.duplicate()}
