# SC-BIRD (docs/plans/birds-sky-life.md, D2): Settings → Graphics → Birds offers Off, Few, Normal and Many with Normal
# by default, previews the choice live (presentation_changed), saves it with Keep, reverts with Back and returns to
# Normal with Restore graphics defaults. The live effect on a built bird layer is in test_birds.gd.
# Run: python3 tools/godot/run_checked.py --timeout 60 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_ui_birds_setting.gd
extends SceneTree

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const PREFS := "user://test_ui_birds_setting_display.cfg"

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all Birds setting checks passed" if _failures == 0 else "%d Birds setting check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var store := DisplayPreferences.new(PREFS)
	var settings := SettingsScreen.new(store, "en")
	root.add_child(settings)
	await process_frame
	var picker: OptionButton = settings.find_child("Birds", true, false)
	var texts: Array[String] = []
	if picker != null:
		for i: int in picker.item_count:
			texts.append(picker.get_item_text(i))
	_check("Settings > Graphics shows Birds: Off, Few, Normal, Many, with Normal selected", picker != null
		and texts == ["Off", "Few", "Normal", "Many"] and picker.get_item_metadata(picker.selected) == "normal", str(texts))
	if picker == null:
		return
	var scene_detail: OptionButton = settings.find_child("SceneDetail", true, false)
	_check("Birds sits on the Graphics page with Scene detail", scene_detail != null
		and picker.get_parent().get_parent() == scene_detail.get_parent().get_parent())
	_check("its tooltip explains the choice", picker.tooltip_text.contains("Scene detail"))
	var previews: Array = []
	settings.presentation_changed.connect(func(config: Dictionary) -> void: previews.append(config.get("birds", "")))
	picker.select(1)
	picker.item_selected.emit(1)
	_check("choosing Few previews it at once", previews.back() == "few" if not previews.is_empty() else false, str(previews))
	_check("an unkept choice is not saved yet", DisplayPreferences.load_from(PREFS).birds == "normal")
	settings.keep_changes()
	_check("Keep saves Few", DisplayPreferences.load_from(PREFS).birds == "few")
	picker.select(0)
	picker.item_selected.emit(0)
	settings._revert()
	_check("Back reverts an unkept Off to the kept Few", settings._draft.birds == "few" and previews.back() == "few"
		and picker.get_item_metadata(picker.selected) == "few", str(previews))
	settings._restore_graphics_defaults()
	_check("Restore graphics defaults returns Birds to Normal", settings._draft.birds == "normal"
		and picker.get_item_metadata(picker.selected) == "normal")
	settings.queue_free()
	await process_frame
	var reopened := SettingsScreen.new(DisplayPreferences.new(PREFS), "en")
	root.add_child(reopened)
	await process_frame
	var again: OptionButton = reopened.find_child("Birds", true, false)
	_check("reopening Settings shows the saved Few", again != null and again.get_item_metadata(again.selected) == "few")
	reopened.queue_free()
	await process_frame
