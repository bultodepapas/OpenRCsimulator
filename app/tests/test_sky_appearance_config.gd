extends SceneTree

const Config = preload("res://environment/sky_appearance_config.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_check_defaults_and_detachment()
	_check_catalog_and_profiles()
	_check_validation()
	_check_cli_arguments()
	_check_identity_and_summary()
	_check_mean_wind()
	print("sky appearance config checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_defaults_and_detachment() -> void:
	var expected := {
		"format": "openrc-sky-appearance v1",
		"preset": "classic",
		"seed": 1253,
		"motion": "legacy",
		"wind_aloft_speed_mps": 0.0,
		"wind_aloft_from_deg": 0.0,
		"flashes": "full",
		"thunder_volume": 0.7,
	}
	_check("DEFAULTS is the exact classic selection", Config.DEFAULTS == expected and Config.defaults() == expected)
	var detached: Dictionary = Config.defaults()
	detached["preset"] = "clear"
	detached["seed"] = 1
	_check("defaults returns a detached dictionary", Config.defaults() == expected)
	var empty_args := Config.from_args({})
	_check("empty arguments validate to exact classic defaults", empty_args.ok and empty_args.config == expected)


func _check_catalog_and_profiles() -> void:
	var entries: Array[Dictionary] = Config.presets()
	var expected_ids := ["classic", "clear", "cirrus", "fair_cumulus", "broken", "overcast", "prestorm", "distant_storm", "electrical_storm"]
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(String(entry.get("id", "")))
	_check("catalog exposes all nine profiles in stable order", ids == expected_ids)
	var layers_by_profile := {}
	for entry: Dictionary in entries:
		_check("profile has UI labels and renderer schema: %s" % entry.get("id", "?"),
			entry.has("name") and entry.has("description") and entry.has("renderer")
			and entry.renderer.has("cloud_cover") and entry.renderer.has("cloud_density")
			and entry.renderer.has("cloud_layers") and entry.renderer.has("zenith_color"))
		layers_by_profile[entry.id] = entry.renderer.cloud_layers.size()
		_check("profile layer count is bounded: %s" % entry.id, entry.renderer.cloud_layers.size() <= 8)
	_check("sky catalog varies between clear, layered, and storm profiles",
		layers_by_profile.clear == 0 and layers_by_profile.cirrus == 1
		and layers_by_profile.broken >= 2 and layers_by_profile.electrical_storm >= 2)
	var clear_profile: Dictionary = Config.presets()[1]
	_check("Clear blue is explicitly cloud-free", clear_profile.name == "Clear blue"
		and clear_profile.description == "A clean blue sky without clouds or cloud shadows."
		and clear_profile.renderer.cloud_cover == 0.0
		and clear_profile.renderer.cloud_density == 0.0
		and clear_profile.renderer.cloud_shadow == 0.0
		and clear_profile.renderer.cloud_layers.is_empty())
	_check("classic preset is labeled as clouds", Config.presets()[0].name == "Classic clouds")
	_check("unknown preset lookup is empty", Config.for_preset("not-a-preset").is_empty())
	_check("classic preset keeps legacy motion", Config.for_preset("classic").motion == "legacy")
	_check("non-classic preset follows wind by default", Config.for_preset("clear").motion == "follow_wind")
	var detached_entries := Config.presets()
	detached_entries[0].renderer.cloud_layers[0].density = 0.0
	var refreshed := Config.presets()
	_check("preset catalog returns detached nested profiles", refreshed[0].renderer.cloud_layers[0].density > 0.0)


func _check_validation() -> void:
	var raw := Config.defaults()
	raw["preset"] = "broken"
	raw["seed"] = 42
	raw["motion"] = "aloft"
	raw["wind_aloft_speed_mps"] = 17.5
	raw["wind_aloft_from_deg"] = 270.0
	var valid := Config.validate(raw)
	_check("valid config returns canonical config and resolved profile",
		valid.ok and valid.config == raw and valid.profile.id == "broken" and valid.errors.is_empty())
	valid.config["preset"] = "clear"
	_check("validation returns detached config", raw.preset == "broken" and valid.config.preset == "clear")
	valid.profile.renderer.cloud_layers[0].density = 0.0
	_check("resolved profile is detached from catalog", Config.for_preset("broken").preset == "broken"
		and Config.presets()[4].renderer.cloud_layers[0].density > 0.0)
	_check_invalid("non-dictionary input", null)
	var missing := raw.duplicate(true)
	missing.erase("seed")
	_check_invalid("missing field", missing)
	var extra := raw.duplicate(true)
	extra["renderer"] = {}
	_check_invalid("unknown field", extra)
	var wrong_version := raw.duplicate(true)
	wrong_version["format"] = "openrc-sky-appearance v2"
	_check_invalid("wrong version", wrong_version)
	var unknown_preset := raw.duplicate(true)
	unknown_preset["preset"] = "unknown"
	_check_invalid("unknown preset", unknown_preset)
	var bool_seed := raw.duplicate(true)
	bool_seed["seed"] = true
	_check_invalid("boolean is not a seed integer", bool_seed)
	var negative_seed := raw.duplicate(true)
	negative_seed["seed"] = -1
	_check_invalid("negative seed", negative_seed)
	var max_seed := raw.duplicate(true)
	max_seed["seed"] = 2147483648
	_check_invalid("seed over max", max_seed)
	var invalid_motion := raw.duplicate(true)
	invalid_motion["motion"] = "followwind"
	_check_invalid("unknown motion token", invalid_motion)
	var bool_speed := raw.duplicate(true)
	bool_speed["wind_aloft_speed_mps"] = true
	_check_invalid("boolean is not a speed", bool_speed)
	var nan_thunder := raw.duplicate(true)
	nan_thunder["thunder_volume"] = NAN
	_check_invalid("non-finite thunder volume", nan_thunder)
	var speed_over := raw.duplicate(true)
	speed_over["wind_aloft_speed_mps"] = 50.01
	_check_invalid("aloft wind over max", speed_over)
	var direction_edge := raw.duplicate(true)
	direction_edge["wind_aloft_from_deg"] = 360.0
	_check_invalid("wind direction excludes 360", direction_edge)
	var flash_bool := raw.duplicate(true)
	flash_bool["flashes"] = true
	_check_invalid("flash mode is an enum", flash_bool)
	var thunder_over := raw.duplicate(true)
	thunder_over["thunder_volume"] = 1.01
	_check_invalid("thunder volume over max", thunder_over)


func _check_cli_arguments() -> void:
	var valid := Config.from_args({
		"sky": "electrical_storm",
		"cloud-motion": "aloft",
		"cloud-seed": "2147483647",
		"cloud-wind-speed": "28.5",
		"cloud-wind-from": "315",
		"storm-flashes": "reduced",
		"thunder-volume": "0.25",
	})
	_check("CLI option values map to validated config fields", valid.ok
		and valid.config.preset == "electrical_storm" and valid.config.motion == "aloft"
		and valid.config.seed == 2147483647 and is_equal_approx(valid.config.wind_aloft_speed_mps, 28.5)
		and valid.config.wind_aloft_from_deg == 315.0 and valid.config.flashes == "reduced"
		and is_equal_approx(valid.config.thunder_volume, 0.25))
	_check_invalid_args("unknown CLI option", {"cloud-drift": "3"})
	var mixed := Config.from_args({"quick-flight": true, "field-lighting": "club", "campfire": "off", "sky": "clear", "capture": true})
	_check("sky flags compose with other CLI namespaces", mixed.ok and mixed.config.preset == "clear")
	_check_invalid_args("flag without a value", {"sky": true})
	_check_invalid_args("unknown preset CLI value", {"sky": "stormy"})
	_check_invalid_args("invalid motion CLI value", {"cloud-motion": "followwind"})
	_check_invalid_args("strict integer rejects decimal seed", {"cloud-seed": "12.0"})
	_check_invalid_args("strict integer rejects signed seed", {"cloud-seed": "-1"})
	_check_invalid_args("strict integer rejects overflow", {"cloud-seed": "2147483648"})
	_check_invalid_args("seed without equals value fails", {"cloud-seed": true})
	_check_invalid_args("speed rejects NaN", {"cloud-wind-speed": "NaN"})
	_check_invalid_args("speed rejects infinity", {"cloud-wind-speed": "inf"})
	_check_invalid_args("speed range is enforced", {"cloud-wind-speed": "50.01"})
	_check_invalid_args("FROM direction excludes 360", {"cloud-wind-from": "360"})
	_check_invalid_args("flash mode is strict", {"storm-flashes": "sometimes"})
	_check_invalid_args("thunder volume range is enforced", {"thunder-volume": "1.01"})
	_check_invalid_args("numeric option without value fails", {"thunder-volume": true})
	var clear := Config.from_args({"sky": "clear"})
	_check("non-classic CLI preset chooses follow_wind", clear.ok and clear.config.motion == "follow_wind")
	var classic_override := Config.from_args({"cloud-seed": "99"})
	_check("overrides without sky retain classic preset", classic_override.ok and classic_override.config.preset == "classic")


func _check_identity_and_summary() -> void:
	var config := Config.defaults()
	var identity: String = Config.identity(config)
	_check("identity is a lowercase SHA-256 digest", identity.length() == 64 and identity == identity.to_lower())
	_check("identity is stable", Config.identity(config) == identity)
	var altered := config.duplicate(true)
	altered["seed"] = 1254
	_check("identity changes with a selection value", Config.identity(altered) != identity)
	_check("summary is a short translatable English preset name", Config.summary(config) == "Classic clouds")
	_check("invalid config has no identity or summary", Config.identity({}) == "" and Config.summary({}) == "")


func _check_mean_wind() -> void:
	_check("empty weather has zero mean wind", Config.mean_wind_ned({}) == [0.0, 0.0, 0.0])
	_check("FROM north points south in NED", _vector_near(Config.mean_wind_ned({"speed_mps": 5.0, "from_deg": 0.0}), [-5.0, 0.0, 0.0]))
	_check("FROM east points west in NED", _vector_near(Config.mean_wind_ned({"speed_mps": 5.0, "from_deg": 90.0}), [0.0, -5.0, 0.0]))
	_check("FROM south points north in NED", _vector_near(Config.mean_wind_ned({"speed_mps": 5.0, "from_deg": 180.0}), [5.0, 0.0, 0.0]))
	_check("FROM west points east in NED", _vector_near(Config.mean_wind_ned({"speed_mps": 5.0, "from_deg": 270.0}), [0.0, 5.0, 0.0]))
	_check("zero speed has exact zero wind", Config.mean_wind_ned({"speed_mps": 0.0, "from_deg": 135.0}) == [0.0, 0.0, 0.0])


func _check_invalid(label: String, value: Variant) -> void:
	var result := Config.validate(value)
	_check("rejects %s" % label, not result.ok and result.config.is_empty() and not result.errors.is_empty())


func _check_invalid_args(label: String, args: Dictionary) -> void:
	var result := Config.from_args(args)
	_check("rejects %s" % label, not result.ok and result.config.is_empty() and not result.errors.is_empty())


func _vector_near(actual: Array[float], expected: Array[float]) -> bool:
	if actual.size() != 3 or expected.size() != 3:
		return false
	for index: int in range(3):
		if not is_equal_approx(actual[index], expected[index]):
			return false
	return true


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("sky appearance: %s" % label)
