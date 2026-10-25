# CAM-17/29: camera preferences and orbit controls (docs/plans/camera-views.md).
#   - display.cfg [camera] round trip; a bad value falls back alone; files without the section keep defaults;
#   - a flight's start applies every preference; a change in Settings applies only what changed;
#   - the pilot FOV setting widens/narrows the law's ceiling smoothly; orbit sensitivity, inversion and easing;
#   - Settings' Camera page: every option, a live preview to the flight and Keep to display.cfg.
# Run: godot --headless --path . --script res://tests/test_camera_settings.gd
extends SceneTree

const Spec := preload("res://spec.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")
const OrbitView := preload("res://render/camera/orbit_view.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const SettingsScreen := preload("res://ui/settings_screen.gd")

const SPAN := 1.524

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_validation()
	_file_round_trip()
	_rig_application()
	_orbit_controls()
	await _settings_page()
	print("all %d camera settings checks passed" % _count if _failures == 0 else "%d of %d failed" % [_failures, _count])
	quit(1 if _failures > 0 else 0)


func _validation() -> void:
	_check("defaults validate", CameraSettings.errors(CameraSettings.DEFAULTS).is_empty())
	_check("an empty dictionary means the defaults", CameraSettings.normalized({}) == CameraSettings.DEFAULTS)
	for bad: Dictionary in [{camera_view = "cockpit"}, {camera_fov = 51}, {camera_fov = "50"}, {camera_auto_zoom = 1},
			{camera_chase_distance = 3.0}, {camera_sensitivity = -1.0}, {camera_invert_y = "yes"}]:
		_check("rejects %s" % str(bad), not CameraSettings.errors(bad).is_empty())
	_check("an integer multiplier is accepted (1 = 100 %)", CameraSettings.errors({camera_sensitivity = 1}).is_empty())


func _file_round_trip() -> void:
	var path := "user://test_camera_settings_display.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var store := DisplayPreferences.new(path)
	_check("no file: camera defaults", CameraSettings.normalized(store.config) == CameraSettings.DEFAULTS)
	var draft := store.config.duplicate(true)
	draft.merge({camera_view = "chase", camera_fov = 35, camera_auto_zoom = false, camera_chase_distance = 1.25,
		camera_sensitivity = 0.5, camera_invert_y = true}, true)
	_check("a camera draft saves", store.save(draft) == OK)
	var loaded := DisplayPreferences.load_from(path)
	_check("round trip keeps every camera value", CameraSettings.normalized(loaded) == CameraSettings.normalized(draft), str(CameraSettings.normalized(loaded)))
	var cfg := ConfigFile.new()
	cfg.load(path)
	_check("stored under [camera]", cfg.get_value("camera", "fov") == 35 and cfg.get_value("camera", "view") == "chase")
	cfg.set_value("camera", "fov", 999)
	cfg.save(path)
	loaded = DisplayPreferences.load_from(path)
	_check("one bad camera value falls back alone", loaded.camera_fov == CameraSettings.DEFAULTS.camera_fov
		and loaded.camera_view == "chase" and loaded.camera_sensitivity == 0.5 and "camera fov" in str(loaded.note), str(loaded.note))
	_check("other display settings survive a bad camera value", loaded.window_mode == draft.window_mode and loaded.msaa_3d == draft.msaa_3d)
	cfg.erase_section("camera")
	cfg.save(path)
	_check("a file from before CAM-17 keeps the camera defaults", CameraSettings.normalized(DisplayPreferences.load_from(path)) == CameraSettings.DEFAULTS)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rig_application() -> void:
	var cam := PilotCamera.create(root, { north = 0.0, east = 0.0, down = 0.0, eye_height = 1.7 })
	var rig := CameraRig.new(cam, SPAN)
	var prefs := CameraSettings.normalized({camera_view = "orbit", camera_fov = 35, camera_auto_zoom = false,
		camera_chase_distance = 0.8, camera_sensitivity = 1.5, camera_invert_y = true})
	CameraSettings.apply_at_start(rig, prefs)
	_check("start: first view, auto-zoom, chase distance, FOV and orbit controls", rig.view == "orbit" and not rig.auto_zoom
		and is_equal_approx(rig.chase.zoom, 0.8) and rig.base_fov == 35.0 and rig.orbit.sensitivity == 1.5 and rig.orbit.invert_y)
	# In flight the pilot changes view and turns auto-zoom on; a Settings change of the FOV must not undo either.
	rig.set_view("pilot")
	rig.toggle_auto_zoom()
	var changed := prefs.duplicate()
	changed.camera_fov = 45
	CameraSettings.apply_changes(rig, prefs, changed)
	_check("a live FOV change keeps the pilot's own view and Z state", rig.view == "pilot" and rig.auto_zoom and rig.base_fov == 45.0)
	rig.toggle_auto_zoom() # the pilot turns it off again (Z)
	var zoomed := changed.duplicate()
	zoomed.camera_auto_zoom = true
	CameraSettings.apply_changes(rig, changed, zoomed)
	_check("a live auto-zoom change applies", rig.auto_zoom)
	CameraSettings.apply_changes(rig, zoomed, changed)
	_check("and turning it off in Settings turns it off", not rig.auto_zoom)
	# The FOV ceiling: with auto-zoom off the pilot view shows the base FOV, reached smoothly after a change.
	var target := Vector3(0, 30, -60)
	var airplane := Transform3D(Basis.IDENTITY, target)
	for i in 240:
		rig.update(target, airplane, Basis.IDENTITY, 1.0 / 60.0, false, Callable())
	_check("pilot view shows the 45° setting", absf(cam.fov - 45.0) < 0.01, "%.3f" % cam.fov)
	rig.set_base_fov(30.0)
	rig.update(target, airplane, Basis.IDENTITY, 1.0 / 60.0, false, Callable())
	var first := cam.fov
	for i in 240:
		rig.update(target, airplane, Basis.IDENTITY, 1.0 / 60.0, false, Callable())
	_check("a new FOV setting is reached smoothly (no jump on the first frame)", absf(first - 45.0) < 1.0 and absf(cam.fov - 30.0) < 0.01, "%.3f then %.3f" % [first, cam.fov])
	# With auto-zoom on, the setting is the law's ceiling: a close airplane sees it, a far one the law's narrower FOV.
	rig.auto_zoom = true
	rig.update(target, airplane, Basis.IDENTITY, 1.0 / 60.0, false, Callable())
	_check("auto-zoom never widens past the setting", cam.fov <= 30.0 + 1e-3, "%.3f" % cam.fov)
	var far := Vector3(0, 60, -400)
	rig.update(far, Transform3D(Basis.IDENTITY, far), Basis.IDENTITY, 1.0 / 60.0, false, Callable())
	_check("far airplane: the law narrows below the setting", cam.fov < 30.0 - 5.0, "%.3f" % cam.fov)
	rig.reset_view()
	_check("Backspace keeps the setting (it resets zoom, not the FOV)", rig.base_fov == 30.0)
	cam.free()


func _orbit_controls() -> void:
	var orbit := OrbitView.new()
	orbit.configure(SPAN)
	var start := orbit.elevation_deg
	orbit.rotate(Vector2(0, 10))
	var down := orbit.elevation_deg - start
	orbit.reset()
	orbit.invert_y = true
	orbit.rotate(Vector2(0, 10))
	_check("invert flips the vertical drag", is_equal_approx(orbit.elevation_deg - start, -down) and down != 0.0)
	orbit.reset()
	orbit.invert_y = false
	orbit.sensitivity = 2.0
	orbit.rotate(Vector2(10, 0))
	_check("sensitivity scales the turn", is_equal_approx(orbit.azimuth_deg, -10.0 * OrbitView.DEGREES_PER_PIXEL * 2.0))
	# Easing: a wheel notch moves the camera over a few frames instead of in one jump; 98 % of the move in 0.3 s.
	orbit.reset()
	var target := Vector3(0, 30, 0)
	var before: Vector3 = orbit.update(target, Callable(), 1.0 / 60.0).position
	orbit.dolly(0.5)
	var first: Vector3 = orbit.update(target, Callable(), 1.0 / 60.0).position
	var settled := first
	for i in 17:
		settled = orbit.update(target, Callable(), 1.0 / 60.0).position
	var full := before.distance_to(target) * 0.5
	_check("a dolly eases: the first frame covers a fraction of the move", before.distance_to(first) < 0.3 * full, "%.3f of %.3f" % [before.distance_to(first), full])
	_check("and covers 98 % of it within 0.3 s", absf(settled.distance_to(target) - orbit.distance) < 0.02 * full, "%.3f m left" % absf(settled.distance_to(target) - orbit.distance))
	_check("easing across ±180° turns the short way", _short_way())


func _short_way() -> bool:
	var orbit := OrbitView.new()
	orbit.configure(SPAN)
	orbit.azimuth_deg = 170.0
	orbit.snap()
	orbit.azimuth_deg = -170.0
	var target := Vector3.ZERO
	var placed: Dictionary = orbit.update(target, Callable(), 1.0 / 60.0)
	var heading := rad_to_deg(atan2((placed.position as Vector3).x, -(placed.position as Vector3).z))
	return absf(angle_difference(deg_to_rad(heading), deg_to_rad(170.0))) < deg_to_rad(20.0) and absf(heading) > 160.0


func _settings_page() -> void:
	var path := "user://test_camera_settings_page.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	var store := DisplayPreferences.new(path)
	var screen := SettingsScreen.new(store, "en")
	var previews: Array[Dictionary] = []
	screen.presentation_changed.connect(func(config: Dictionary) -> void: previews.append(config))
	viewport.add_child(screen)
	await process_frame
	screen._show_category(SettingsScreen.CATEGORIES.find("Camera"))
	await process_frame
	var pickers := {"camera_view": screen._camera_view_picker, "camera_fov": screen._camera_fov_picker,
		"camera_chase_distance": screen._camera_chase_picker, "camera_sensitivity": screen._camera_sensitivity_picker}
	var complete := true
	for key: String in pickers:
		var picker: OptionButton = pickers[key]
		complete = complete and picker.is_visible_in_tree() and picker.get_item_metadata(picker.selected) == CameraSettings.DEFAULTS[key]
	_check("Camera page shows every option at its default", complete and screen._camera_auto_zoom_toggle.button_pressed
		and not screen._camera_invert_toggle.button_pressed)
	_check("the default FOV is labelled as the default", screen._camera_fov_picker.get_item_text(screen._camera_fov_picker.selected) == "50° (default)")
	var index := CameraSettings.FOVS.find(35)
	screen._camera_fov_picker.select(index)
	screen._camera_fov_picker.item_selected.emit(index)
	_check("choosing 35° previews it live (no display trial)", not previews.is_empty() and previews.back().camera_fov == 35
		and screen._trial_deadline_msec == 0)
	screen._camera_invert_toggle.button_pressed = true
	screen.keep_changes()
	var saved := DisplayPreferences.load_from(path)
	_check("Keep stores the camera choices", saved.camera_fov == 35 and saved.camera_invert_y)
	screen.queue_free()
	viewport.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
