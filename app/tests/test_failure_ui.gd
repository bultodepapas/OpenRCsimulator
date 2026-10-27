extends SceneTree

const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const FailureMenu := preload("res://ui/failures_menu.gd")
const Home := preload("res://ui/home.gd")
const PauseMenu := preload("res://ui/pause_menu.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

const PREFS := "user://test_failure_ui_settings.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _run() -> void:
	TranslationServer.set_locale("en")
	TranslationServer.set_locale("es")
	_check("Spanish failure notices are translated", TranslationServer.translate("Failure: %s") == "Falla: %s")
	_check("Spanish Pause scope hint is translated",
		TranslationServer.translate("Applying changes updates notices in this flight. Probability and catastrophic settings apply to the next flight.")
		== "Al aplicar, los avisos se actualizan en este vuelo. La probabilidad y las fallas catastróficas se aplican al próximo vuelo.")
	_check("Spanish aileron-trim formatting keeps its placeholder",
		TranslationServer.translate("Aileron trim: %+.1f%%") == "Compensación de alerones: %+.1f%%")
	TranslationServer.set_locale("en")
	var defaults: Dictionary = FailureConfig.defaults()
	_check("failure defaults are off, non-catastrophic and visible", defaults == {
		"probability_percent": 0, "include_catastrophic": false, "notify": true,
		"severity": "standard", "onset": "standard", "excluded_ids": [],
	}, str(defaults))
	_check("failure validator accepts the maximum integer percentage", FailureConfig.validate({
		"probability_percent": 100, "include_catastrophic": true, "notify": false,
	}).ok)
	_check("failure validator rejects a percentage outside the range",
		not FailureConfig.validate({"probability_percent": 101, "include_catastrophic": false, "notify": true}).ok)
	_check("failure validator rejects a non-integer percentage",
		not FailureConfig.validate({"probability_percent": 12.5, "include_catastrophic": false, "notify": true}).ok)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var invalid_file := ConfigFile.new()
	invalid_file.set_value("meta", "schema", Preferences.SCHEMA)
	invalid_file.set_value("failures", "config", {
		"probability_percent": "often", "include_catastrophic": false, "notify": true,
	})
	_check("write invalid preference fixture", invalid_file.save(PREFS) == OK)
	var recovered: Dictionary = Preferences.load_from(PREFS)
	_check("invalid failure preference recovers to defaults", recovered.failure_config == defaults
		and "invalid failure settings" in recovered.note)
	var invalid_save := Preferences.DEFAULTS.duplicate(true)
	invalid_save.failure_config = {"probability_percent": -1, "include_catastrophic": false, "notify": true}
	_check("preferences refuse to save invalid failure config", Preferences.save_to(PREFS, invalid_save) == ERR_INVALID_DATA)
	var round_trip := Preferences.DEFAULTS.duplicate(true)
	round_trip.writable = true
	round_trip.failure_config = {"probability_percent": 100, "include_catastrophic": true, "notify": false}
	_check("save valid failure preference", Preferences.save_to(PREFS, round_trip) == OK)
	_check("legacy failure preferences round-trip as their upgraded request",
		Preferences.load_from(PREFS).failure_config == FailureConfig.validate(round_trip.failure_config).config)
	var customized := Preferences.DEFAULTS.duplicate(true)
	customized.writable = true
	customized.failure_config = {
		"probability_percent": 35, "include_catastrophic": false, "notify": true,
		"severity": "severe", "onset": "late", "excluded_ids": ["yaw_jam", "pitch_slow"],
	}
	_check("save customized failure preference", Preferences.save_to(PREFS, customized) == OK)
	var reloaded: Dictionary = Preferences.load_from(PREFS)
	_check("customized failure preferences round-trip",
		reloaded.failure_config == FailureConfig.validate(customized.failure_config).config, str(reloaded.failure_config))

	var home: Control = Home.new()
	home.set_aircraft("xcell-60-research")
	_check("rotorcraft Home disables failure settings", home.failures_button.disabled)
	_check("default-off flight gets no failure debrief", home.failure_debrief_text({
		"active": false, "selected": false, "enabled": false,
	}).is_empty())
	_check("scheduled but unreached failure is reported after End",
		home.failure_debrief_text({"active": false, "selected": true, "enabled": true})
		== "Flight ended before the scheduled failure.")
	_check("enabled flight without a selected event gets an honest debrief",
		home.failure_debrief_text({"active": false, "selected": false, "enabled": true})
		== "No failure was assigned to the last flight.")
	_check("active incident label is reported after End",
		home.failure_debrief_text({"active": true, "selected": true, "enabled": true, "label": "Ailerons jammed."})
		== "Last flight: Ailerons jammed.")
	home.free()

	var menu: CanvasLayer = FailureMenu.new(defaults)
	root.add_child(menu)
	await ui.settle()
	_check("probability slider is editable on integer range 0..100",
		menu.probability_slider.min_value == 0.0 and menu.probability_slider.max_value == 100.0
		and menu.probability_slider.step == 1.0 and menu.probability_slider.editable)
	_check("percentage entry is editable on integer range 0..100",
		menu.probability_spin.min_value == 0.0 and menu.probability_spin.max_value == 100.0
		and menu.probability_spin.step == 1.0 and menu.probability_spin.editable)
	_check("menu uses safe checkbox defaults", not menu.catastrophic_check.button_pressed and menu.notify_check.button_pressed)
	var next_flight_semantics_present := false
	for candidate: Node in menu.find_children("*", "Label", true, false):
		if "never rerolls the current flight" in (candidate as Label).text:
			next_flight_semantics_present = true
	_check("menu explains next-flight settings do not reroll the current flight", next_flight_semantics_present)
	menu.probability_slider.value = 100.0
	_check("slider updates percentage entry", int(menu.probability_spin.value) == 100)
	menu.probability_spin.value = 0.0
	_check("percentage entry updates slider", int(menu.probability_slider.value) == 0)
	var applied: Array[Dictionary] = []
	var cancelled := [false]
	menu.applied.connect(func(config: Dictionary) -> void: applied.append(config))
	menu.cancelled.connect(func() -> void: cancelled[0] = true)
	menu.apply_button.pressed.emit()
	menu.cancel_button.pressed.emit()
	_check("Apply confirms the current draft", applied.size() == 1 and applied[0] == defaults)
	_check("Cancel requests back without applying", cancelled[0])
	menu.queue_free()
	await process_frame
	await _check_type_selection_menu()

	var pause: CanvasLayer = PauseMenu.new()
	var dummy := FakeFailureSession.new()
	var current_text: String = pause.active_failure_text(dummy, true)
	_check("Pause incident summary includes label and hint",
		"Current failure: Ailerons jammed." in current_text and "Hint:" in current_text)
	_check("Pause hides current incident when notices are disabled", pause.active_failure_text(dummy, false).is_empty())
	dummy.free()
	pause.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all standalone failure UI checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


## EM-29: onset/severity pickers, one checkbox per failure type, bulk actions and the empty-pool guard.
func _check_type_selection_menu() -> void:
	var initial := {
		"probability_percent": 50, "include_catastrophic": false, "notify": true,
		"severity": "mild", "onset": "late", "excluded_ids": ["pitch_jam", "throttle_stuck"],
	}
	var eligible: Array[String] = FailureCatalog.failure_ids_v3(true, FailureCatalog.LOGICAL_CONTROLS_PROFILE)
	var menu: CanvasLayer = FailureMenu.new(initial, {"eligible_ids": eligible, "power_loss_supported": false})
	root.add_child(menu)
	await ui.settle()
	_check("onset picker offers three windows", menu.onset_picker.item_count == 3)
	_check("severity picker offers three levels", menu.severity_picker.item_count == 3)
	_check("initial draft reflects the saved request", menu.get_draft_config() == FailureConfig.validate(initial).config,
		str(menu.get_draft_config()))
	_check("one checkbox per known failure type", menu.type_checks.size() == FailureCatalog.KNOWN_IDS.size())
	_check("excluded types start unchecked", not menu.type_checks.pitch_jam.button_pressed
		and not menu.type_checks.throttle_stuck.button_pressed and menu.type_checks.roll_jam.button_pressed)
	_check("radio loss is unavailable until catastrophic failures are included", menu.type_checks.radio_loss.disabled)
	menu.catastrophic_check.button_pressed = true
	_check("including catastrophic failures enables radio loss", not menu.type_checks.radio_loss.disabled)
	_check("glow-only event is marked unavailable on a control-only aircraft",
		menu.find_child("Unavailable_glow_fuel_cut", true, false) != null
		and menu.find_child("Unavailable_roll_jam", true, false) == null)
	_check("count reports the checked types this aircraft can use",
		menu.possible_type_ids().size() == eligible.size() - 2, str(menu.possible_type_ids()))
	menu.severity_picker.select(2)
	menu.onset_picker.select(0)
	menu.type_checks.yaw_slow.button_pressed = false
	var draft: Dictionary = menu.get_draft_config()
	_check("draft carries severity, onset and sorted exclusions", draft.severity == "severe" and draft.onset == "early"
		and draft.excluded_ids == ["pitch_jam", "throttle_stuck", "yaw_slow"], str(draft))
	_check("draft is a valid failure request", FailureConfig.validate(draft).ok)
	menu.clear_all_button.pressed.emit()
	_check("Clear all excludes every type", menu.get_draft_config().excluded_ids.size() == FailureCatalog.KNOWN_IDS.size())
	_check("count explains an empty pool", "No checked failure type" in menu.type_count_label.text, str(menu.type_count_label.text))
	var applied: Array[Dictionary] = []
	menu.applied.connect(func(config: Dictionary) -> void: applied.append(config))
	menu.apply_button.pressed.emit()
	_check("Apply refuses a nonzero probability with no possible type", applied.is_empty() and menu.error_label.visible)
	menu.probability_slider.value = 0.0
	menu.apply_button.pressed.emit()
	_check("Apply accepts an empty selection when failures are off", applied.size() == 1 and applied[0].probability_percent == 0)
	menu.select_all_button.pressed.emit()
	_check("Select all includes every type", menu.get_draft_config().excluded_ids.is_empty())
	menu.queue_free()
	await process_frame


class FakeFailureSession extends Node:
	func failure_status() -> Dictionary:
		return {
			"active": true,
			"label": "Ailerons jammed.",
			"hint": "Keep adequate airspeed. Use gentle rudder inputs if effective; plan a wide approach.",
		}
