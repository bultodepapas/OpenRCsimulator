# FW-MOON-13: the moon choices in the time-of-day controls (Conditions → Time of day, pause → Sky and lighting).
# They start from the given configuration, read back as a validated MoonConfig, enable the phase picker only for
# "Choose a phase", explain the result (phase, light, rise/set, the moved date) and join the focus order; Spanish
# labels come from the catalog.
# Run: godot --headless --path . --script res://tests/test_ui_moon_controls.gd
extends SceneTree

const TimeOfDayControls := preload("res://ui/time_of_day_controls.gd")
const MoonConfig := preload("res://environment/moon_config.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	var saved := MoonConfig.defaults()
	saved.moon = "phase"
	saved.phase = "waning_gibbous"
	saved.size = "large"
	saved.night_look = "camera" # no control yet: must survive a round trip
	var controls: VBoxContainer = TimeOfDayControls.new(null, null, saved)
	root.add_child(controls)
	await process_frame
	_check("starts from the saved choice", controls.moon_picker.selected == 1 and controls.moon_phase_picker.selected == 5
		and controls.moon_size_picker.selected == 1 and controls.moonlight_picker.selected == 0)
	var read: Dictionary = controls.read_moon_config()
	_check("reads back the same configuration", read.ok and read.config == saved, str(read))
	_check("phase picker enabled for a chosen phase", not controls.moon_phase_picker.disabled)
	_check("summary names the phase and the moved date", controls.moon_summary.text.contains("Waning gibbous")
		and controls.moon_summary.text.contains("nearest night"), controls.moon_summary.text)
	_check("moon pickers join the focus order", controls.focus_controls().has(controls.moon_picker)
		and controls.focus_controls().has(controls.moon_phase_picker) and controls.focus_controls().has(controls.moonlight_picker))

	controls.moon_picker.select(0)
	controls.moon_picker.item_selected.emit(0)
	_check("real sky disables the phase picker", controls.moon_phase_picker.disabled)
	_check("the disabled phase picker leaves the focus order", not controls.focus_controls().has(controls.moon_phase_picker))
	_check("real sky summary has light and rise/set", controls.moon_summary.text.contains("% lit")
		and (controls.moon_summary.text.contains("rises") or controls.moon_summary.text.contains("no moonrise")), controls.moon_summary.text)
	controls.moon_picker.select(2)
	controls.moon_picker.item_selected.emit(2)
	_check("no moon explains itself", controls.moon_summary.text.begins_with("No moon"), controls.moon_summary.text)
	controls.moonlight_picker.select(1)
	var off: Dictionary = controls.read_moon_config()
	_check("reads no moon with brighter moonlight", off.ok and off.config.moon == "off" and off.config.moonlight == "bright", str(off))
	_check("labels say the assists are not real", controls.moon_size_picker.get_item_text(1).contains("not real")
		and controls.moonlight_picker.get_item_text(1).contains("not real"))

	TranslationServer.set_locale("es")
	controls.notification(NOTIFICATION_TRANSLATION_CHANGED)
	await process_frame
	_check("Spanish moon choices", controls.moon_picker.get_item_text(0) == "Cielo real" and controls.moon_phase_picker.get_item_text(4) == "Luna llena",
		"%s / %s" % [controls.moon_picker.get_item_text(0), controls.moon_phase_picker.get_item_text(4)])
	TranslationServer.set_locale("en")

	var defaults: VBoxContainer = TimeOfDayControls.new()
	root.add_child(defaults)
	await process_frame
	_check("without a saved choice: the real moon", defaults.read_moon_config().config == MoonConfig.defaults())
	controls.queue_free()
	defaults.queue_free()
	await process_frame
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
