# VQ-04b: additive shadow preferences and reversible settings previews.
extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const ShadowSettings := preload("res://render/shadow_settings.gd")
const PREFS := "user://test_shadow_settings_ui.cfg"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	await _run()
	_remove_fixture()
	TranslationServer.set_locale("en")
	print("shadow settings checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_remove_fixture()
	_preference_cases()
	_remove_fixture()
	await _settings_cases()


func _preference_cases() -> void:
	var missing := DisplayPreferences.load_from(PREFS)
	for key: String in DisplayPreferences.SHADOW_FILE_KEYS:
		_check("missing file uses the existing shadow behavior for " + key,
			missing[key] == ShadowSettings.DEFAULTS[key])
	var old_caller: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	for key: String in DisplayPreferences.SHADOW_FILE_KEYS:
		old_caller.erase(key)
	var normalized := DisplayPreferences.validate(old_caller)
	_check("old callers receive additive shadow defaults", normalized.ok
		and normalized.config.shadow_quality == "current" and normalized.config.shadow_technique == "auto"
		and normalized.config.shadow_aircraft_cue == "auto" and normalized.config.shadow_distance == "auto"
		and normalized.config.shadow_softness == "auto")
	var old_file := ConfigFile.new()
	old_file.set_value("meta", "schema", 1)
	old_file.set_value("graphics", "scene_detail", "high")
	_check("schema-1 fixture saves", old_file.save(PREFS) == OK)
	var migrated := DisplayPreferences.load_from(PREFS)
	_check("old file keeps its choices and receives shadow defaults", migrated.scene_detail == "high"
		and migrated.shadow_quality == "current" and migrated.shadow_technique == "auto"
		and migrated.shadow_aircraft_cue == "auto" and migrated.shadow_distance == "auto"
		and migrated.shadow_softness == "auto" and migrated.writable)

	var selected: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	selected.merge({"shadow_quality": "high", "shadow_technique": "native", "shadow_aircraft_cue": "vertical",
		"shadow_distance": "far", "shadow_softness": "hard", "scene_detail": "low"}, true)
	_check("supported shadow values save", DisplayPreferences.save_to(PREFS, selected) == OK)
	var saved := ConfigFile.new()
	_check("shadow choices are stored in their own section", saved.load(PREFS) == OK
		and saved.get_value("shadows", "quality") == "high"
		and saved.get_value("shadows", "technique") == "native"
		and saved.get_value("shadows", "aircraft_cue") == "vertical"
		and saved.get_value("shadows", "distance") == "far"
		and saved.get_value("shadows", "softness") == "hard")
	var reloaded := DisplayPreferences.new(PREFS)
	_check("shadow values round-trip alongside other graphics", reloaded.config == selected)
	var choices := {"shadow_quality": ShadowSettings.QUALITY, "shadow_technique": ShadowSettings.TECHNIQUES,
		"shadow_aircraft_cue": ShadowSettings.AIRCRAFT_CUES, "shadow_distance": ShadowSettings.DISTANCES,
		"shadow_softness": ShadowSettings.SOFTNESS}
	for key: String in choices:
		for option: String in choices[key]:
			var candidate: Dictionary = selected.duplicate(true)
			candidate[key] = option
			_check("supported %s value round-trips: %s" % [key, option],
				DisplayPreferences.save_to(PREFS, candidate) == OK and DisplayPreferences.new(PREFS).config == candidate)
	for key: String in DisplayPreferences.SHADOW_FILE_KEYS:
		for invalid: Variant in ["unknown", true, 42, NAN]:
			var bad_candidate := selected.duplicate(true)
			bad_candidate[key] = invalid
			_check("invalid %s is rejected: %s" % [key, str(invalid)],
				not DisplayPreferences.validate(bad_candidate).ok)
		_check("write baseline before recovering " + key, DisplayPreferences.save_to(PREFS, selected) == OK)
		var malformed := ConfigFile.new()
		malformed.load(PREFS)
		malformed.set_value("shadows", DisplayPreferences.SHADOW_FILE_KEYS[key], "unknown")
		_check("write malformed " + key, malformed.save(PREFS) == OK)
		var recovered := DisplayPreferences.new(PREFS)
		var expected := selected.duplicate(true)
		expected[key] = DisplayPreferences.DEFAULTS[key]
		_check("only malformed " + key + " falls back", recovered.config == expected
			and recovered.note.contains("invalid shadow") and recovered.writable)
		_check("recovered " + key + " can be saved", recovered.save(recovered.config) == OK
			and DisplayPreferences.new(PREFS).config == expected)
	var future := ConfigFile.new()
	future.set_value("meta", "schema", DisplayPreferences.SCHEMA + 1)
	future.set_value("shadows", "technique", "native")
	_check("future fixture saves", future.save(PREFS) == OK)
	var protected := DisplayPreferences.new(PREFS)
	_check("future file is readable but cannot be overwritten", not protected.writable
		and protected.config.shadow_technique == "native" and protected.save(selected) == ERR_FILE_NO_PERMISSION)


func _settings_cases() -> void:
	var store := DisplayPreferences.new(PREFS)
	ShadowSettings.apply(store.config)
	var settings := SettingsScreen.new(store, "en")
	root.add_child(settings)
	await process_frame
	settings._show_category(3)
	var group: VBoxContainer = settings.find_child("ShadowGroup", true, false)
	var group_button: Button = settings.find_child("ShadowGroupToggle", true, false)
	_check("Graphics contains a collapsed Shadows group", group != null and group_button != null and not group.visible)
	if group == null or group_button == null:
		settings.queue_free()
		return
	group_button.button_pressed = true
	_check("group opens with the toggle", group.visible)
	var controls := {
		"shadow_quality": "ShadowQuality", "shadow_technique": "ShadowTechnique",
		"shadow_aircraft_cue": "ShadowAircraftCue", "shadow_distance": "ShadowDistance",
		"shadow_softness": "ShadowSoftness",
	}
	var previews: Array = []
	settings.presentation_changed.connect(func(config: Dictionary) -> void:
		ShadowSettings.apply(config)
		previews.append(config.duplicate(true)))
	for key: String in controls:
		var picker: OptionButton = settings.find_child(controls[key], true, false)
		_check("picker exists for " + key, picker != null)
		if picker == null:
			settings.queue_free()
			return
		_check("picker starts at saved value for " + key, picker.get_item_metadata(picker.selected) == store.config[key])
	_select(settings, "ShadowQuality", "high")
	_select(settings, "ShadowTechnique", "native")
	_select(settings, "ShadowAircraftCue", "vertical")
	_select(settings, "ShadowDistance", "far")
	_select(settings, "ShadowSoftness", "hard")
	_check("five selections preview without the display safety timer", previews.size() == 5
		and settings._trial_deadline_msec == 0 and ShadowSettings.describe().requested.shadow_technique == "native")
	_check("preview is not persisted", DisplayPreferences.load_from(PREFS).shadow_technique == "auto")
	var info: Label = settings.find_child("ShadowInfo", true, false)
	var effective: Dictionary = ShadowSettings.describe().effective
	var expected_technique := "Native" if effective.technique == "native" else "Projected"
	_check("receipt distinguishes the active technique from the configured cue", info != null
		and info.text.contains("Active technique: " + expected_technique) and info.text.contains("Configured cue: Vertical"))
	var technique_picker: OptionButton = settings.find_child("ShadowTechnique", true, false)
	var distance_picker: OptionButton = settings.find_child("ShadowDistance", true, false)
	_check("Native option explains its experimental coverage", technique_picker.get_item_tooltip(1) ==
		"Native shadow coverage is experimental; some objects do not cast shadows.")
	_check("distance tooltip explains activity-specific limits", distance_picker.tooltip_text == "Activities may use a shorter range.")
	if bool(effective.native):
		_check("native receipt explains limited coverage and shorter activity ranges",
			info.text.contains("Native shadow coverage is experimental; some objects do not cast shadows.")
			and info.text.contains("Activities may use a shorter range."))
	settings.keep_changes()
	var kept := DisplayPreferences.load_from(PREFS)
	_check("Keep persists every shadow setting", kept.shadow_quality == "high" and kept.shadow_technique == "native"
		and kept.shadow_aircraft_cue == "vertical" and kept.shadow_distance == "far" and kept.shadow_softness == "hard")
	_select(settings, "ShadowTechnique", "projected")
	_check("projected mode marks native-only options inactive", info.text.contains("Quality: Not active")
		and info.text.contains("Distance limit: Not active") and info.text.contains("Softness: Not active"))
	settings._revert()
	_check("Revert restores the saved choice and active receipt", settings._draft.shadow_technique == "native"
		and ShadowSettings.describe().requested.shadow_technique == "native"
		and info.text.contains("Active technique: " + expected_technique))
	settings._draft.scene_detail = "low"
	settings._draft.camera_fov = 60
	settings._draft.nvidia_reflex = "off"
	settings._draft.aircraft_lighting_quality = "high"
	settings._draft.master_volume = 0.4
	settings._restore_shadow_defaults()
	_check("shadow-only restore previews defaults", settings._draft.shadow_quality == "current"
		and settings._draft.shadow_technique == "auto" and settings._draft.shadow_aircraft_cue == "auto"
		and settings._draft.shadow_distance == "auto" and settings._draft.shadow_softness == "auto"
		and ShadowSettings.describe().requested.shadow_technique == "auto")
	_check("shadow-only restore preserves other drafts", settings._draft.scene_detail == "low"
		and settings._draft.camera_fov == 60 and settings._draft.nvidia_reflex == "off"
		and settings._draft.aircraft_lighting_quality == "high" and settings._draft.master_volume == 0.4)
	settings.close()
	_check("closing discards the unkept shadow restore", ShadowSettings.describe().requested.shadow_technique == "native"
		and DisplayPreferences.load_from(PREFS).shadow_technique == "native")
	settings.queue_free()
	await process_frame
	TranslationServer.set_locale("es")
	var reopened := SettingsScreen.new(DisplayPreferences.new(PREFS), "es")
	root.add_child(reopened)
	await process_frame
	var technique: OptionButton = reopened.find_child("ShadowTechnique", true, false)
	var toggle: Button = reopened.find_child("ShadowGroupToggle", true, false)
	_check("reopened settings retain the saved selection in Spanish", technique != null
		and technique.get_item_metadata(technique.selected) == "native" and technique.get_item_text(2) == "Proyectada"
		and toggle.text.begins_with("Sombras") and technique.get_item_tooltip(1).contains("experimental"))
	TranslationServer.set_locale("en")
	await process_frame
	_check("open shadow controls follow language changes without losing the selection",
		technique.get_item_metadata(technique.selected) == "native" and technique.get_item_text(2) == "Projected"
		and toggle.text.begins_with("Shadows") and technique.get_item_tooltip(1) ==
		"Native shadow coverage is experimental; some objects do not cast shadows.")
	reopened.queue_free()
	await process_frame


func _select(settings: CanvasLayer, name: String, value: String) -> void:
	var picker: OptionButton = settings.find_child(name, true, false)
	for index: int in picker.item_count:
		if picker.get_item_metadata(index) == value:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	_check("choice exists for " + name + ": " + value, false)


func _remove_fixture() -> void:
	for path: String in [PREFS, PREFS + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("shadow settings: " + label)
