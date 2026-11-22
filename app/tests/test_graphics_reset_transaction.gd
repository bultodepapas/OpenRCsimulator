extends SceneTree
## VQ-07h: Restore owns a pending operation even when its values already equal the saved defaults.

const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const Preferences := preload("res://app_state/preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const RcTrackOption := preload("res://scenery/rc_track_option.gd")
const Field := preload("res://data/field_loader.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const PREFS := "user://test_graphics_reset_display.cfg"
const CALIBRATION := "user://test_graphics_reset_calibration.cfg"
const BLOCKED := "user://test_graphics_reset_directory"


## Exercise production ownership while every actual preference write stays in this test's private file.
class OwnedDisplayPreferences extends DisplayPreferences:
	func _init() -> void:
		super(PREFS)
		path = Preferences.DEFAULT_PATH + ".display"

	func save(candidate: Dictionary) -> Error:
		var owner_path := path
		path = PREFS
		var err := super.save(candidate)
		path = owner_path
		return err


var _checks := 0
var _failures := 0
var _commits := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	AutoCalibration.calibration_path = CALIBRATION
	AutoCalibration.clear()
	var view := SubViewport.new()
	view.size = Vector2i(1920, 1080)
	root.add_child(view)
	var store := OwnedDisplayPreferences.new()
	store.config = DisplayPreferences.recommended_defaults()
	var settings := SettingsScreen.new(store)
	view.add_child(settings)
	settings.presentation_committed.connect(func() -> void: _commits += 1)
	await process_frame
	var delayed := AutoCalibration.current_workload()
	delayed.merge({"adapter": RenderingServer.get_video_adapter_name(), "method": RenderingServer.get_current_rendering_method(),
		"complete": false})
	AutoCalibration.record_attempt(delayed)
	var explanation: String = settings._automatic_graphics_text()
	_check("Settings explains the session cooldown without promising another flight measurement",
		explanation.contains("Not enough GPU timing samples") and not explanation.contains("The next flight measures"))
	AutoCalibration.clear()
	_seed_calibration()
	var original := FileAccess.get_file_as_string(CALIBRATION)
	settings._restore_graphics_defaults()
	_check("Restore is actionable even when defaults already match", settings._draft == settings._saved
		and settings._calibration_reset_pending and not settings._keep_button.disabled and not settings._revert_button.disabled)
	settings._revert()
	_check("Revert cancels the pending reset", not settings._calibration_reset_pending and settings._keep_button.disabled)
	settings._draft.menu_volume = 0.25
	settings.keep_changes()
	_check("an unrelated Keep after Revert preserves calibration", FileAccess.get_file_as_string(CALIBRATION) == original
		and not SceneDetail.calibration.is_empty())
	settings._restore_graphics_defaults()
	store.writable = false
	settings.keep_changes()
	_check("a failed display save preserves the pending reset and evidence", settings._calibration_reset_pending
		and settings._status_state == "save_error" and FileAccess.get_file_as_string(CALIBRATION) == original)
	store.writable = true
	settings._revert()
	settings._restore_graphics_defaults()
	settings._trial_baseline = settings._saved.duplicate(true)
	settings._draft.max_fps = 60
	settings._trial_deadline_msec = Time.get_ticks_msec() + 1000
	settings._expire_display_trial()
	_check("display trial expiry preserves the separate Restore intent", settings._draft.max_fps == settings._saved.max_fps
		and settings._calibration_reset_pending and not settings._keep_button.disabled)
	SceneDetail.apply(view, "auto")
	_check("the pre-reset viewport uses the accepted calibration", is_equal_approx(view.mesh_lod_threshold, 2.0))
	settings.keep_changes()
	_check("a successful Keep deletes calibration and resolves the pending operation", not FileAccess.file_exists(CALIBRATION)
		and SceneDetail.calibration.is_empty() and not settings._calibration_reset_pending and settings._keep_button.disabled)
	_check("clearing calibration also reapplies the viewport LOD", is_equal_approx(view.mesh_lod_threshold, 1.0))
	_seed_calibration()
	store.path = PREFS
	settings._restore_graphics_defaults()
	settings.keep_changes()
	_check("private profiles never clear production calibration", FileAccess.file_exists(CALIBRATION)
		and not SceneDetail.calibration.is_empty() and not settings._calibration_reset_pending)
	store.path = Preferences.DEFAULT_PATH + ".display"
	# A directory at the file path reliably rejects deletion on every OS, without relying on chmod under root.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BLOCKED))
	AutoCalibration.calibration_path = BLOCKED
	settings._draft.menu_volume = 0.5
	settings._restore_graphics_defaults()
	var commits_before := _commits
	settings.keep_changes()
	_check("deletion failure still commits the saved display checkpoint", _commits == commits_before + 1
		and settings._saved == settings._draft and DisplayPreferences.load_from(PREFS).menu_volume == 0.5)
	_check("deletion failure remains retryable and preserves in-memory evidence", settings._calibration_reset_pending
		and not settings._keep_button.disabled and not SceneDetail.calibration.is_empty()
		and settings._status_state == "calibration_reset_error" and settings._status.text.contains("Settings saved, but"))
	AutoCalibration.calibration_path = CALIBRATION
	store.writable = false # the display portion is already committed; an unchanged retry only deletes calibration
	settings.keep_changes()
	_check("retry completes the reset", not settings._calibration_reset_pending and SceneDetail.calibration.is_empty()
		and not FileAccess.file_exists(CALIBRATION) and settings._status_state == "saved")
	store.writable = true
	var field: Dictionary = Field.load_from().field
	for circuit: String in ["on", "off"]:
		settings._draft.rc_track = circuit
		settings.keep_changes()
		RcTrackOption.set_preference(circuit)
		var before := RcTrackOption.resolve(field, true)
		settings._restore_graphics_defaults()
		settings.keep_changes()
		var reloaded := DisplayPreferences.load_from(PREFS)
		RcTrackOption.set_preference(str(reloaded.rc_track))
		var after := RcTrackOption.resolve(field, true)
		_check("Restore preserves circuit %s through Keep and reload" % circuit, reloaded.rc_track == circuit
			and before == after and (after.is_empty() if circuit == "off" else Track.identity(before) == Track.identity(after)))
		_check("the scenario choice is not custom graphics: %s" % circuit, DisplayPreferences.graphics_profile(reloaded) == "current_default")
	settings._draft.msaa_3d = 0
	_check("a rendering change is still custom graphics", DisplayPreferences.graphics_profile(settings._draft) == "custom")
	settings._revert()
	_seed_calibration()
	settings._restore_graphics_defaults()
	settings.close()
	_check("Close cancels an equal-defaults reset without deleting evidence", not settings._calibration_reset_pending
		and FileAccess.file_exists(CALIBRATION))
	view.queue_free()
	await process_frame
	AutoCalibration.clear()
	AutoCalibration.calibration_path = AutoCalibration.CALIBRATION_PATH
	SceneDetail.calibration = {}
	SceneDetail.adapter_override = PackedStringArray()
	SceneDetail.set_preference("")
	RcTrackOption.set_preference("auto")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BLOCKED))
	print("graphics reset transaction: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _seed_calibration() -> void:
	var adapter := "NVIDIA GeForce RTX 3090"
	var method := RenderingServer.get_current_rendering_method()
	SceneDetail.adapter_override = PackedStringArray([adapter, "NVIDIA"])
	AutoCalibration.save_result({"adapter": adapter, "method": method, "complete": true, "level": "high",
		"scene_offset": -1, "pixels": root.size.x * root.size.y})
	SceneDetail.calibration = AutoCalibration.load_result(adapter, method)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: " + label)
