extends SceneTree

const Settings := preload("res://render/overlays/overlay_settings.gd")
const Preferences := preload("res://app_state/preferences.gd")
const PREFS := "user://test_player_widget_settings.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()
	_reset()
	print("player widget settings checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_check("legacy defaults retain their exact shape", Settings.DEFAULTS == {
		preset = "pilot", visible = ["flight", "transmitter", "warnings", "wind", "controls", "battery"],
		units = "auto", stick_mode = 2, radio_model = "jeti_ds24_ii",
	})
	_check("widget IDs append to the existing overlay IDs", Settings.IDS.slice(Settings.IDS.size() - Settings.PLAYER_IDS.size()) == Settings.PLAYER_IDS
		and Settings.PLAYER_IDS == ["speed", "height", "power", "weather", "fuel", "trims", "engine"] + Settings.CLASSIC_IDS + Settings.NAVIGATION_IDS + Settings.TRAINING_IDS
		and Settings.NAVIGATION_IDS == ["pilot_radar", "wind_track", "cruise_efficiency"]
		and Settings.TRAINING_IDS == ["maneuver", "glide", "flight_summary", "session_stats"]
		and Settings.CLASSIC_IDS == ["airspeed_dial", "attitude", "altimeter", "heading", "variometer"])
	_check("existing presets stay unchanged and navigation and training append", Settings.PRESET_ORDER == ["off", "pilot", "full", "developer", "player", "instruments", "cockpit", "navigation", "training"]
		and Settings.PRESET_ORDER.size() == 9
		and Settings.PRESETS.player == ["warnings", "speed", "height", "power", "weather"]
		and Settings.PRESETS.instruments == ["warnings", "speed", "height", "power", "weather", "fuel", "trims", "engine"]
		and Settings.PRESETS.cockpit == ["warnings", "airspeed_dial", "attitude", "altimeter", "heading", "variometer"]
		and Settings.PRESETS.navigation == ["warnings", "pilot_radar", "wind_track", "cruise_efficiency"]
		and Settings.PRESETS.training == ["warnings", "maneuver", "glide", "flight_summary"]
		and Settings.preset_for(Settings.PRESETS.player) == "player"
		and Settings.preset_for(Settings.PRESETS.instruments) == "instruments"
		and Settings.preset_for(Settings.PRESETS.cockpit) == "cockpit"
		and Settings.preset_for(Settings.PRESETS.navigation) == "navigation"
		and Settings.preset_for(Settings.PRESETS.training) == "training")
	var player: Dictionary = Settings.validate({"preset": "player"})
	_check("player preset validates to the five player overlays", player.preset == "player"
		and player.visible == Settings.PRESETS.player)
	var instruments: Dictionary = Settings.validate({"preset": "instruments"})
	_check("all instruments preset validates to warnings and all seven widgets", instruments.preset == "instruments"
		and instruments.visible == Settings.PRESETS.instruments)
	var cockpit: Dictionary = Settings.validate({"preset": "cockpit"})
	_check("classic cockpit preset validates to warnings and five classic widgets", cockpit.preset == "cockpit"
		and cockpit.visible == Settings.PRESETS.cockpit)
	var navigation: Dictionary = Settings.validate({"preset": "navigation"})
	_check("navigation preset validates to warnings and exactly three navigation widgets", navigation.preset == "navigation"
		and navigation.visible == Settings.PRESETS.navigation and navigation.visible.size() == 4)
	var training: Dictionary = Settings.validate({"preset": "training"})
	_check("training preset validates to warnings and exactly three training widgets", training.preset == "training"
		and training.visible == Settings.PRESETS.training and training.visible.size() == 4 and not training.visible.has("session_stats"))
	_check("legacy settings do not gain optional position keys", not Settings.validate(Settings.DEFAULTS).has("positions")
		and not Settings.validate(Settings.DEFAULTS).has("layout_locked")
		and not Settings.validate(Settings.DEFAULTS).has("widget_size")
		and not Settings.validate(Settings.DEFAULTS).has("widget_opacity")
		and not Settings.validate(Settings.DEFAULTS).has("widget_compact"))
	_check("widget size scales and default opacity remain explicit", Settings.WIDGET_SIZE_SCALES == {"small": 0.85, "normal": 1.0, "large": 1.2}
		and Settings.DEFAULT_WIDGET_OPACITY == 0.94 and Settings.WIDGET_OPACITY_STEPS == [0.80, 0.94, 1.0])

	var widget_options: Dictionary = Settings.validate({"widget_size": "large", "widget_opacity": 1.2, "widget_compact": true})
	_check("widget settings validate and clamp opacity", widget_options.widget_size == "large"
		and widget_options.widget_opacity == 1.0 and widget_options.widget_compact)
	var low_opacity: Dictionary = Settings.validate({"widget_opacity": 0.2})
	_check("widget opacity clamps to its readable lower bound", low_opacity.widget_opacity == 0.80)
	var invalid_widget_options: Dictionary = Settings.validate({
		"widget_size": "huge", "widget_opacity": NAN, "widget_compact": "true",
	})
	_check("invalid widget options are omitted", not invalid_widget_options.has("widget_size")
		and not invalid_widget_options.has("widget_opacity") and not invalid_widget_options.has("widget_compact"))

	var positioned: Dictionary = Settings.validate({
		"preset": "player",
		"positions": {
			"speed": [-2, 1.4],
			"height": [NAN, 0.4],
			"power": [INF, 0.6],
			"weather": ["0.3", 0.5],
			"fuel": [0.44, 0.67],
			"pilot_radar": [0.61, 0.22],
			"wind_track": [0.29, 0.52],
			"cruise_efficiency": [0.8, 0.91],
			"maneuver": [0.14, 0.73],
			"glide": [0.48, 0.33],
			"flight_summary": [0.86, 0.76],
			"warnings": [1.4, -0.2],
			"flight": [0.2, 0.2],
			"unknown": [0.7, 0.8],
			17: [0.5, 0.5],
		},
		"layout_locked": true,
	})
	_check("named presets still validate optional positions and lock state", positioned.preset == "player"
		and positioned.positions == {"speed": [0.0, 1.0], "fuel": [0.44, 0.67], "pilot_radar": [0.61, 0.22], "wind_track": [0.29, 0.52], "cruise_efficiency": [0.8, 0.91], "maneuver": [0.14, 0.73], "glide": [0.48, 0.33], "flight_summary": [0.86, 0.76]} and positioned.layout_locked)
	var wrong_position_type: Dictionary = Settings.validate({"preset": "pilot", "positions": [0.2, 0.3]})
	_check("wrong positions container type is discarded", not wrong_position_type.has("positions"))
	var wrong_lock_type: Dictionary = Settings.validate({"preset": "pilot", "layout_locked": "true"})
	_check("wrong lock type is discarded", not wrong_lock_type.has("layout_locked"))

	var moved: Dictionary = Settings.with_visible(positioned, ["speed", "height"])
	_check("visibility edits preserve positions and the layout lock", moved.positions == positioned.positions
		and moved.layout_locked and moved.visible == ["speed", "height"] and moved.preset == "custom")

	_preferences_round_trip()


func _preferences_round_trip() -> void:
	_reset()
	var initial: Dictionary = Preferences.load_from(PREFS)
	_check("missing preferences use unchanged HUD defaults", initial.hud == Settings.DEFAULTS
		and not initial.hud.has("positions") and not initial.hud.has("layout_locked"))
	_check("legacy HUD preferences save without optional keys", Preferences.save_to(PREFS, initial) == OK)
	var legacy_file := ConfigFile.new()
	_check("legacy HUD preference fixture is readable", legacy_file.load(PREFS) == OK)
	_check("legacy save does not inject optional HUD keys", not legacy_file.has_section_key("hud", "positions")
		and not legacy_file.has_section_key("hud", "layout_locked")
		and not legacy_file.has_section_key("hud", "widget_size")
		and not legacy_file.has_section_key("hud", "widget_opacity")
		and not legacy_file.has_section_key("hud", "widget_compact"))

	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.hud = Settings.validate({
		"preset": "player",
		"positions": {
			"speed": [0.31, 0.77],
			"height": [0.18, 0.26],
			"power": [0.5, 0.45],
			"weather": [0.7, 0.11],
			"fuel": [0.21, 0.37],
			"pilot_radar": [0.61, 0.22],
			"wind_track": [0.29, 0.52],
			"cruise_efficiency": [0.8, 0.91],
			"maneuver": [0.14, 0.73],
			"glide": [0.48, 0.33],
			"flight_summary": [0.86, 0.76],
		},
		"layout_locked": true,
		"widget_size": "large",
		"widget_opacity": 0.88,
		"widget_compact": true,
	})
	_check("player HUD preferences save", Preferences.save_to(PREFS, prefs) == OK)
	var stored := ConfigFile.new()
	_check("saved player HUD preference file is readable", stored.load(PREFS) == OK)
	_check("optional player layout keys are stored under hud", stored.has_section_key("hud", "positions")
		and stored.get_value("hud", "positions", {}) == prefs.hud.positions
		and stored.get_value("hud", "layout_locked", false) == true
		and stored.get_value("hud", "widget_size", "") == "large"
		and is_equal_approx(float(stored.get_value("hud", "widget_opacity", 0.0)), 0.88)
		and stored.get_value("hud", "widget_compact", false) == true)
	var loaded: Dictionary = Preferences.load_from(PREFS)
	_check("positions, lock, widget options and player preset round-trip", loaded.hud == prefs.hud)
	stored.set_value("hud", "widget_size", "huge")
	stored.set_value("hud", "widget_opacity", NAN)
	stored.set_value("hud", "widget_compact", "true")
	_check("invalid optional HUD fixture saves", stored.save(PREFS) == OK)
	var invalid_loaded: Dictionary = Preferences.load_from(PREFS).hud
	_check("invalid persisted widget options are discarded without losing positions", not invalid_loaded.has("widget_size")
		and not invalid_loaded.has("widget_opacity") and not invalid_loaded.has("widget_compact")
		and invalid_loaded.positions == prefs.hud.positions)


func _reset() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		return
	_failures += 1
	push_error("player widget settings: %s" % label)
