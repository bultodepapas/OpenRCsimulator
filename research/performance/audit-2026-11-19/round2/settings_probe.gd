extends SceneTree

const Settings := preload("res://ui/settings_screen.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const Preferences := preload("res://app_state/preferences.gd")
const AutoCalibration := preload("res://render/auto_calibration.gd")
const SceneDetail := preload("res://render/scene_detail.gd")
const InterfaceFont := preload("res://i18n/fonts.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, condition: bool, details: Dictionary) -> void:
	print("PROBE ", label, " ", "PASS" if condition else "FAIL", " ", JSON.stringify(details))
	if not condition:
		failures += 1

func _seed() -> void:
	var saved := AutoCalibration.save_result({"adapter": "fixture adapter", "method": "forward_plus", "level": "high", "complete": true, "scene_offset": -1, "reject_high": true, "pixels": 2073600, "samples": 300})
	SceneDetail.calibration = {"sentinel": true}
	_check("seed", saved and FileAccess.file_exists(AutoCalibration.calibration_path), {"path": ProjectSettings.globalize_path(AutoCalibration.calibration_path)})

func _store(max_fps: int) -> Variant:
	var store := DisplayPreferences.new(Preferences.DEFAULT_PATH + ".display")
	store.config = DisplayPreferences.recommended_defaults()
	store.config.max_fps = max_fps
	return store

func _run() -> void:
	DisplayPreferences.first_run_defaults = {}
	# Sparse checkout has no CJK font binaries; use a built-in font for UI construction.
	InterfaceFont._japanese = ThemeDB.fallback_font
	InterfaceFont._chinese = ThemeDB.fallback_font
	print("DATA_DIR ", ProjectSettings.globalize_path("user://"))
	_seed()
	var settings := Settings.new(_store(60))
	root.add_child(settings)
	await process_frame
	settings._restore_graphics_defaults()
	var restore_dirty: bool = settings._draft != settings._saved
	settings._revert()
	_check("revert_leaves_reset_pending", restore_dirty and settings._draft == settings._saved and settings._calibration_reset_pending and FileAccess.file_exists(AutoCalibration.calibration_path), {"dirty_after_restore": restore_dirty, "pending_after_revert": settings._calibration_reset_pending, "file_exists": FileAccess.file_exists(AutoCalibration.calibration_path)})
	settings._master_volume_changed(0.5)
	settings.keep_changes()
	_check("unrelated_keep_erases_verdict", not FileAccess.file_exists(AutoCalibration.calibration_path) and SceneDetail.calibration.is_empty(), {"saved_max_fps": settings._saved.max_fps, "saved_master_volume": settings._saved.master_volume, "file_exists": FileAccess.file_exists(AutoCalibration.calibration_path), "live_calibration": SceneDetail.calibration})
	settings.queue_free()
	await process_frame

	_seed()
	settings = Settings.new(_store(0))
	root.add_child(settings)
	await process_frame
	settings._restore_graphics_defaults()
	_check("defaults_equal_keep_disabled", settings._draft == settings._saved and settings._calibration_reset_pending and settings._keep_button.disabled and settings._revert_button.disabled and FileAccess.file_exists(AutoCalibration.calibration_path), {"pending": settings._calibration_reset_pending, "keep_disabled": settings._keep_button.disabled, "revert_disabled": settings._revert_button.disabled, "file_exists": FileAccess.file_exists(AutoCalibration.calibration_path)})
	settings.queue_free()
	await process_frame

	settings = Settings.new(_store(60))
	root.add_child(settings)
	await process_frame
	settings._restore_graphics_defaults()
	settings._expire_display_trial()
	_check("expired_trial_keeps_reset_pending", settings._draft == settings._saved and settings._calibration_reset_pending and FileAccess.file_exists(AutoCalibration.calibration_path), {"pending": settings._calibration_reset_pending, "dirty": settings._draft != settings._saved, "file_exists": FileAccess.file_exists(AutoCalibration.calibration_path)})
	settings._master_volume_changed(0.4)
	settings.keep_changes()
	_check("post_expiry_unrelated_keep_erases_verdict", not FileAccess.file_exists(AutoCalibration.calibration_path), {"file_exists": FileAccess.file_exists(AutoCalibration.calibration_path), "saved_master_volume": settings._saved.master_volume})
	settings.queue_free()
	await process_frame
	_seed()
	settings = Settings.new(_store(60))
	root.add_child(settings)
	await process_frame
	settings._restore_graphics_defaults()
	settings.close()
	var file_after_close: bool = FileAccess.file_exists(AutoCalibration.calibration_path)
	settings.queue_free()
	await process_frame
	settings = Settings.new(_store(60))
	root.add_child(settings)
	await process_frame
	var pending_after_reopen: bool = settings._calibration_reset_pending
	settings._master_volume_changed(0.6)
	settings.keep_changes()
	_check("close_reopen_discards_pending_reset", file_after_close and not pending_after_reopen and FileAccess.file_exists(AutoCalibration.calibration_path) and not SceneDetail.calibration.is_empty(), {"file_after_close": file_after_close, "pending_after_reopen": pending_after_reopen, "file_after_later_keep": FileAccess.file_exists(AutoCalibration.calibration_path), "live_calibration": SceneDetail.calibration})
	settings.queue_free()
	await process_frame
	print("PROBE_COMPLETE failures=", failures)
	quit(0 if failures == 0 else 1)
