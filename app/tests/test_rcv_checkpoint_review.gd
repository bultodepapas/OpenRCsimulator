extends SceneTree
const Activity = preload("res://vehicles/ground/ground_scene.gd")
const Session = preload("res://sim/ground_vehicle/session.gd")
const Review = preload("res://vehicles/ground/checkpoint_review.gd")
const ThemeTokens = preload("res://ui/ui_theme.gd")
const UiDriver = preload("res://tests/ui_driver.gd")
const KNOBS := {"gravity_scale": 0.5, "grip_scale": 1.0, "spring_scale": 1.0, "damper_scale": 1.0, "ballast_kg": 0.0, "ballast_height_m": 0.15}
class RefusingSession extends "res://sim/ground_vehicle/session.gd":
	var refuse_restore := false
	var export_attempts := 0
	func restore_checkpoint(value: Variant) -> bool:
		return false if refuse_restore else super.restore_checkpoint(value)
	func export_recording(_name: String) -> Dictionary:
		export_attempts += 1
		return {"ok": false, "error": "injected test refusal"}
var checks := 0
var failed := 0
func check(ok: bool, desc: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL: " + desc)
func make_activity(path: String) -> Node:
	var a = Activity.new()
	a.enable_audio = false
	a.enable_course_visual = false
	a.enable_vehicle_effects = false
	a.checkpoint_path = path
	root.add_child(a)
	a.set_process(false)
	a.set_physics_process(false)
	return a
func settle() -> void:
	for i in 4: await process_frame
func position_restore_at_bottom(dashboard: Node) -> void:
	dashboard.menu_scroll.ensure_control_visible(dashboard.restore_button)
	await settle()
	var area: Rect2 = dashboard.menu_scroll.get_global_rect()
	var button: Rect2 = dashboard.restore_button.get_global_rect()
	dashboard.menu_scroll.scroll_vertical += int(round(button.end.y - area.end.y + 2.0))
	dashboard.restore_button.grab_focus()
	await settle()

func notice_visible(dashboard: Node) -> bool:
	var area: Rect2 = dashboard.menu_scroll.get_global_rect()
	var notice: Rect2 = dashboard.checkpoint_notice.get_global_rect()
	return notice.position.y >= area.position.y - 1.0 and notice.end.y <= area.end.y + 1.0

func fragment_visible(label: Label, fragment: String, area: Rect2) -> bool:
	var index := label.text.find(fragment)
	if index < 0: return false
	for character in [index, index + fragment.length() - 1]:
		var bounds := label.get_character_bounds(character)
		bounds.position += label.get_global_rect().position
		if bounds.size.y <= 0.0 or bounds.position.y < area.position.y - 1.0 or bounds.end.y > area.end.y + 1.0:
			return false
	return true

func save_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
func snap(s: Node) -> Dictionary:
	return {"state": s.state_snapshot().to_byte_array(), "tick": s.tick, "tape": s.control_tape_snapshot().to_byte_array(), "damage": s.damage_snapshot().to_byte_array(), "events": s.event_tape_snapshot(), "recording": s.recording, "generation": s.recording_generation}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	var folder := ProjectSettings.globalize_path("res://../tmp/audit6-20261107-garage/test-data-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("checkpoint.json")
	var a := make_activity(path)
	await settle()
	check(a.startup_error.is_empty(), "production activity prepared")
	a._select_mode(2)
	a._experiment(KNOBS)
	check(a.dashboard.lab_result.text.contains("Gravity 0.5") and a.dashboard.lab_result.text.contains("Run restarted"), "accepted experiment reports effective settings and restart")
	a.handle_action("save")
	var saved := FileAccess.get_file_as_bytes(path)
	check(not saved.is_empty(), "saved actual gravity experiment")
	var parsed: Dictionary = JSON.parse_string(saved.get_string_from_utf8())
	a.free()
	var b := make_activity(path)
	await settle()
	var before := snap(b.session)
	b.handle_action("restore")
	check(b.dashboard.checkpoint_notice.text.contains("different") and b.session.state_snapshot().to_byte_array() == before.state, "default reopen refuses mismatch with clear guidance")
	check(FileAccess.get_file_as_bytes(path) == saved and b._checkpoint.is_empty(), "mismatch preserves checkpoint and cache")
	b.dashboard.checkpoint_review_button.grab_focus()
	b.handle_action("review_checkpoint")
	await settle()
	check(b.dashboard.checkpoint_review.visible and b.dashboard.checkpoint_details.text.contains("Gravity 0.5") and b.dashboard.checkpoint_details.text.contains("Grip 1") and b.dashboard.checkpoint_details.text.contains("Height 0.15"), "review presents all validated setup values")
	check(b.dashboard.checkpoint_details.text.contains("Bisonte") and b.dashboard.checkpoint_details.text.contains("Airfield"), "review identifies validated vehicle and course")
	check(snap(b.session) == before and FileAccess.get_file_as_bytes(path) == saved and b._checkpoint.is_empty(), "review is read-only")
	var ui = UiDriver.new(self)
	await ui.tap(KEY_ESCAPE)
	await settle()
	check(not b.dashboard.checkpoint_review.visible and b.dashboard.checkpoint_review_button.has_focus(), "Back closes review and returns focus")
	b._select_mode(2)
	b._experiment(KNOBS)
	check(b.dashboard.checkpoint_notice.text.contains("matches"), "closed review notice refreshes after accepted lab change")
	b.handle_action("restore")
	check(b.dashboard.toast.text.contains("restored") and b.session.paused, "manual matching restores")
	check(FileAccess.get_file_as_bytes(path) == saved, "successful restore preserves primary bytes")
	b.handle_action("review_checkpoint")
	var different := KNOBS.duplicate(true)
	different.gravity_scale = 0.75
	b._experiment(different)
	check(b.dashboard.checkpoint_notice.text.contains("different"), "open review refreshes when active setup changes")
	b.handle_action("save")
	check(b.dashboard.checkpoint_notice.text.contains("matches") and b.dashboard.checkpoint_details.text.contains("Gravity 0.75") and b.dashboard.checkpoint_details.text.contains("memory"), "saving refreshes the visible review and source")
	b.free()
	var empty := make_activity(folder.path_join("missing/absent.json"))
	await settle()
	check(empty.session.start_recording(), "active recording starts")
	var active_before := snap(empty.session)
	await position_restore_at_bottom(empty.dashboard)
	await ui.tap(KEY_ENTER)
	await settle()
	check(empty.dashboard.checkpoint_notice.text == "No saved run was found." and snap(empty.session) == active_before, "empty restore does not finalize recording")
	check(notice_visible(empty.dashboard) and empty.dashboard.restore_button.has_focus(), "missing-save notice is revealed without moving Restore focus")
	empty.handle_action("review_checkpoint")
	check(snap(empty.session) == active_before, "empty review preserves active recording")
	empty.checkpoint_path = folder.path_join("corrupt.json")
	save_text(empty.checkpoint_path, "{broken json")
	empty.handle_action("restore")
	check(empty.dashboard.checkpoint_notice.text.contains("could not be read") and snap(empty.session) == active_before, "malformed JSON is silently diagnosed without stopping recording")
	check(FileAccess.get_file_as_string(empty.checkpoint_path) == "{broken json", "malformed original bytes are preserved")
	empty.free()
	var c := make_activity(folder.path_join("valid.json"))
	await settle()
	c._checkpoint = c.session.checkpoint()
	check(c.session.start_recording(), "compatible checkpoint recording fixture starts")
	var with_recording := snap(c.session)
	c.handle_action("review_checkpoint")
	check(c.dashboard.checkpoint_notice.text.contains("matches") and snap(c.session) == with_recording, "compatible review does not misclassify active recording")
	c.free()
	var bad := parsed.duplicate(true)
	bad.tick = -1

	# Use a fresh prepared scene to hash crafted malformed candidates.
	var d := make_activity(folder.path_join("invalid.json"))
	await settle()
	bad.checkpoint_sha256 = d.session._checkpoint_hash(bad)
	save_text(d.checkpoint_path, JSON.stringify(bad, "", true, true))
	var bad_bytes := FileAccess.get_file_as_bytes(d.checkpoint_path)
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("could not be read") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "bounded invalid tick cannot expose purported metadata")
	check(FileAccess.get_file_as_bytes(d.checkpoint_path) == bad_bytes, "invalid checkpoint remains unchanged")
	bad = parsed.duplicate(true)
	bad.tick = 1000000000000.0
	bad.checkpoint_sha256 = d.session._checkpoint_hash(bad)
	save_text(d.checkpoint_path, JSON.stringify(bad, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("could not be read"), "huge tick cannot bypass bounded tape validation")
	var wrong := parsed.duplicate(true)
	wrong.vehicle_id = "monster-car-2"
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("different") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "wrong vehicle is incompatible without attributing settings")
	wrong = parsed.duplicate(true)
	wrong.course_identity.sha256 = "0".repeat(64)
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("different") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "wrong course is incompatible without attributing settings")
	wrong = parsed.duplicate(true)
	wrong.solver_identity.solver_version = "wrong-solver"
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("different") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "wrong solver does not attribute an experiment mismatch")
	wrong = parsed.duplicate(true)
	wrong.solver_identity.backend_identity.binary_sha256 = "0".repeat(64)
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("different") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "wrong backend identity cannot be attributed to an experiment")
	wrong = parsed.duplicate(true)
	var tampered_settings := KNOBS.duplicate(true)
	tampered_settings.gravity_scale = 0.75
	wrong.model_identity.settings_json = JSON.stringify(tampered_settings, "", true, true)
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("could not be read") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "self-hashed in-range settings cannot be detached from the model identity")
	wrong = parsed.duplicate(true)
	wrong.model_identity.settings_json = "{\"gravity_scale\":2.5}"
	wrong.checkpoint_sha256 = d.session._checkpoint_hash(wrong)
	save_text(d.checkpoint_path, JSON.stringify(wrong, "", true, true))
	d.handle_action("review_checkpoint")
	check(d.dashboard.checkpoint_notice.text.contains("could not be read") and not d.dashboard.checkpoint_details.text.contains("Gravity"), "out-of-range experiment metadata is not trusted")
	d.free()
	var e := make_activity(folder.path_join("recovery.json"))
	await settle()
	var recovered: Dictionary = e.session.checkpoint()
	var backup: String = e.checkpoint_path + ".tmp-123.previous"
	save_text(backup, JSON.stringify(recovered, "", true, true))
	var backup_bytes := FileAccess.get_file_as_bytes(backup)
	e.handle_action("review_checkpoint")
	check(e.dashboard.checkpoint_details.text.contains("recovery backup") and not FileAccess.file_exists(e.checkpoint_path), "missing primary discovers backup without promotion during review")
	check(FileAccess.get_file_as_bytes(backup) == backup_bytes and e._checkpoint.is_empty(), "backup review preserves bytes and cache")
	e.handle_action("restore")
	check(e.dashboard.toast.text.contains("recovery backup") and FileAccess.get_file_as_bytes(e.checkpoint_path) == backup_bytes, "compatible backup restores and preserves prior promotion policy")
	e.free()
	var damaged := make_activity(folder.path_join("damaged-primary.json"))
	await settle()
	var saved_backup: Dictionary = damaged.session.checkpoint()
	var damaged_backup: String = damaged.checkpoint_path + ".tmp-456.previous"
	save_text(damaged_backup, JSON.stringify(saved_backup, "", true, true))
	save_text(damaged.checkpoint_path, "{damaged")
	damaged.handle_action("review_checkpoint")
	check(damaged.dashboard.checkpoint_details.text.contains("recovery backup") and FileAccess.get_file_as_string(damaged.checkpoint_path) == "{damaged", "corrupt primary falls back to validated backup during read-only review")
	damaged.handle_action("restore")
	check(damaged.dashboard.toast.text.contains("recovery backup") and FileAccess.get_file_as_string(damaged.checkpoint_path) == "{damaged" and FileAccess.file_exists(damaged_backup), "backup restore retains corrupt primary and recovery source")
	damaged.free()
	if OS.get_name() == "Windows":
		var upper := folder.path_join("CASE-CHECKPOINT.JSON")
		var lower := folder.path_join("case-checkpoint.json")
		var h := make_activity(lower)
		await settle()
		save_text(upper, JSON.stringify(h.session.checkpoint(), "", true, true))
		h.handle_action("review_checkpoint")
		check(h.dashboard.checkpoint_notice.text.contains("matches"), "Windows primary lookup respects case-insensitive filenames")
		h.free()
	var precise_path := folder.path_join("precise.json")
	var precise := make_activity(precise_path)
	await settle()
	var precise_knobs := KNOBS.duplicate(true)
	precise_knobs.gravity_scale = 0.501234567890123
	precise._experiment(precise_knobs)
	precise.handle_action("save")
	precise.free()
	precise = make_activity(precise_path)
	await settle()
	precise.handle_action("review_checkpoint")
	check(precise.dashboard.checkpoint_details.text.contains(JSON.stringify(precise_knobs.gravity_scale, "", true, true)) and precise.dashboard.checkpoint_details.text.contains("Slider steps"), "non-slider precision is displayed without rounding or claiming applicability")
	precise.free()
	var detached := make_activity(path)
	await settle()
	detached.handle_action("review_checkpoint")
	root.remove_child(detached)
	await settle()
	detached.free()
	check(true, "review followed by immediate detach completes without engine errors")
	var blocked := folder.path_join("occupied")
	save_text(blocked, "not a directory")
	var i := make_activity(blocked.path_join("checkpoint.json"))
	await settle()
	i.handle_action("review_checkpoint")
	check(i.dashboard.checkpoint_notice.text.contains("could not be read"), "occupied parent is not reported as absent")
	i.free()
	var f = RefusingSession.new()
	check(f.prepare_default(), "veto session prepared")
	var fixture = Activity.new()
	var dash = preload("res://vehicles/ground/ground_dashboard.gd").new()
	root.add_child(dash)
	fixture.session = f
	fixture.dashboard = dash
	fixture.add_child(f)
	fixture._checkpoint = f.checkpoint()
	await settle()
	f.refuse_restore = true
	dash.action_requested.connect(fixture.handle_action)
	await position_restore_at_bottom(dash)
	var refusal_before := snap(f)
	var saved_cache: Dictionary = fixture._checkpoint.duplicate(true)
	await ui.tap(KEY_ENTER)
	await settle()
	check(dash.checkpoint_notice.text == "Restore was not completed." and snap(f) == refusal_before and fixture._checkpoint == saved_cache and dash.restore_button.has_focus(), "final authoritative refusal preserves run, cache and focus without success")
	check(notice_visible(dash), "final refusal notice is revealed beneath the real Restore button")
	f.refuse_restore = false
	check(f.start_recording(), "recording veto fixture starts")
	fixture.handle_action("restore")
	check(f.export_attempts == 1 and f.has_unexported_recording() and not dash.toast.text.contains("restored"), "failed export vetoes compatible restore and retains recording")
	fixture._experiment(KNOBS)
	check(f.export_attempts == 2 and f.has_unexported_recording() and dash.lab_result.text == "Experiment was not applied.", "failed recording export vetoes lab restart without success copy")
	fixture.free()
	dash.free()
	var matrix_path := folder.path_join("matrix-05.json")
	var matrix_file := FileAccess.open(matrix_path, FileAccess.WRITE)
	matrix_file.store_buffer(saved)
	matrix_file.close()
	var saw_fitting_review := false
	var saw_long_review := false
	for locale in ["en", "es"]:
		for scale in [1.0, 2.0]:
			TranslationServer.set_locale(locale)
			ThemeTokens.text_scale = scale
			var v := make_activity(matrix_path)
			await settle()
			await position_restore_at_bottom(v.dashboard)
			await ui.tap(KEY_ENTER)
			await settle()
			var scroll_bounds: Rect2 = v.dashboard.menu_scroll.get_global_rect()
			var focused_bounds: Rect2 = v.dashboard.restore_button.get_global_rect()
			check(notice_visible(v.dashboard) and v.dashboard.restore_button.has_focus() and focused_bounds.position.y >= scroll_bounds.position.y and focused_bounds.end.y <= scroll_bounds.end.y, "%s %.1f mismatch notice and Restore focus remain visible" % [locale, scale])
			if locale == "es":
				check(v.dashboard.checkpoint_notice.text != "The saved run needs a different vehicle, course, solver, or experiment. Review the saved setup.", "Spanish diagnostic uses the imported translation at %.1f" % scale)
			v.dashboard.menu_scroll.ensure_control_visible(v.dashboard.checkpoint_review_button)
			await settle()
			v.dashboard.checkpoint_review_button.grab_focus()
			await settle()
			await ui.tap(KEY_ENTER)
			await settle()
			var panel_rect: Rect2 = v.dashboard.panel.get_global_rect()
			var detail_rect: Rect2 = v.dashboard.checkpoint_details.get_global_rect()
			var scroll_rect: Rect2 = v.dashboard.menu_scroll.get_global_rect()
			var review_rect: Rect2 = v.dashboard.checkpoint_review.get_global_rect()
			if review_rect.size.y <= scroll_rect.size.y:
				saw_fitting_review = true
				check(review_rect.position.y >= scroll_rect.position.y - 1.0 and review_rect.end.y <= scroll_rect.end.y + 1.0, "%s %.1f complete review and Close are visible when they fit" % [locale, scale])
			else:
				saw_long_review = true
				check(absf(review_rect.position.y - scroll_rect.position.y) <= 1.0, "%s %.1f long review aligns to top" % [locale, scale])
			var review_focus: Control = root.gui_get_focus_owner()
			var review_focus_rect: Rect2 = review_focus.get_global_rect() if is_instance_valid(review_focus) else Rect2()
			check(is_instance_valid(review_focus) and review_focus_rect.position.y >= scroll_rect.position.y - 1.0 and review_focus_rect.end.y <= scroll_rect.end.y + 1.0, "%s %.1f Review retains a visible focus owner" % [locale, scale])
			var gravity_text: String = (v.dashboard.tr("Gravity %s · Grip %s") % ["0.5", "1"]).get_slice(" · ", 0)
			check(fragment_visible(v.dashboard.checkpoint_details, gravity_text, scroll_rect), "%s %.1f actual Review click reveals saved Gravity 0.5" % [locale, scale])
			check(fragment_visible(v.dashboard.checkpoint_details, "Bisonte MT8", scroll_rect), "%s %.1f actual Review click reveals saved vehicle" % [locale, scale])
			check(panel_rect.position.x >= 0 and panel_rect.end.x <= 1920 and panel_rect.position.y >= 0 and panel_rect.end.y <= 1080, "%s %.1f panel stays in 1080p bounds" % [locale, scale])
			check(detail_rect.position.x >= panel_rect.position.x and detail_rect.end.x <= panel_rect.end.x, "%s %.1f review text fits panel width" % [locale, scale])
			check(v.dashboard.checkpoint_details.get_line_count() >= 4, "%s %.1f review remains wrapped and readable" % [locale, scale])
			v.dashboard.menu_scroll.ensure_control_visible(v.dashboard.close_checkpoint_button)
			await settle()
			v.dashboard.close_checkpoint_button.grab_focus()
			await ui.tap(KEY_ENTER)
			await settle()
			check(not v.dashboard.checkpoint_review.visible and v.dashboard.checkpoint_review_button.has_focus(), "%s %.1f explicit Close returns focus" % [locale, scale])
			await ui.tap(KEY_ENTER)
			await settle()
			v.dashboard.modes.grab_focus()
			await settle()
			var old_scroll: int = v.dashboard.menu_scroll.scroll_vertical
			var refreshed: Dictionary = Review.inspect(v.session, v._checkpoint, v.checkpoint_path)
			v.dashboard.show_checkpoint_inspection(refreshed)
			await settle()
			check(v.dashboard.modes.has_focus() and v.dashboard.menu_scroll.scroll_vertical == old_scroll, "%s %.1f unrelated refresh preserves focus and scroll" % [locale, scale])
			await ui.tap(KEY_ESCAPE)
			await settle()
			check(not v.dashboard.checkpoint_review.visible and v.dashboard.checkpoint_review_button.has_focus(), "%s %.1f Back closes review and restores focus" % [locale, scale])
			v.free()
	check(saw_fitting_review and saw_long_review, "layout exercises both fitting and taller-than-viewport review")
	ThemeTokens.text_scale = 1.0
	TranslationServer.set_locale("en")
	print("RCV checkpoint review: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)
