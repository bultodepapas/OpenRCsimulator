extends SceneTree

const NEUTRAL := {"throttle":0.0,"steering":0.0,"brake":0.0,"reverse":false,"armed":true}
class AuditedActivity extends "res://vehicles/ground/ground_scene.gd":
	var write_fault := 0
	var move_fault := 0
	func _move_checkpoint_file(from: String, to: String) -> Error:
		if move_fault > 0 and from.contains(".tmp-"):
			if not from.ends_with(".previous") or move_fault == 2:
				return ERR_FILE_CANT_WRITE
		return super._move_checkpoint_file(from, to)
	func _write_checkpoint_temp(path: String, contents: String) -> Error:
		if write_fault == 0:
			return super._write_checkpoint_temp(path, contents)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return FileAccess.get_open_error()
		file.store_string(contents.substr(0, 12))
		file.close()
		# Both a reported failure and an undetected short write must keep the old save.
		return ERR_FILE_CANT_WRITE if write_fault == 1 else OK

var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)
func _new_activity() -> AuditedActivity:
	var scene := AuditedActivity.new()
	scene.enable_audio = false
	scene.enable_course_visual = false
	scene.enable_vehicle_effects = false
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	return scene
func _run() -> void:
	TranslationServer.set_locale("en")
	var scene := _new_activity()
	check(scene.startup_error.is_empty(), "production airfield activity prepares")
	var folder := DirAccess.create_temp("openrc-activity-audit")
	check(folder != null, "isolated save directory exists")
	if folder == null:
		scene.free()
		quit(1)
		return
	scene.checkpoint_path = folder.get_current_dir().path_join("missing/checkpoint.json")
	check(not scene._restore_checkpoint_file(), "first launch with no save directory refuses restore quietly")
	scene.checkpoint_path = folder.get_current_dir().path_join("checkpoint.json")
	check(scene._save_checkpoint(), "first checkpoint saves")
	var original := FileAccess.get_file_as_bytes(scene.checkpoint_path)
	var original_cache: Dictionary = scene._checkpoint.duplicate(true)
	check(not original.is_empty() and scene.session.can_restore_checkpoint(JSON.parse_string(original.get_string_from_utf8())),
		"saved bytes round-trip through strict checkpoint validation")
	check(scene.session.manual_recovery(), "test creates a different valid assisted checkpoint")
	for fault in [1, 2]:
		scene.write_fault = fault
		check(not scene._save_checkpoint(), "partial write is rejected (mode %d)" % fault)
		check(FileAccess.get_file_as_bytes(scene.checkpoint_path) == original and scene._checkpoint == original_cache,
			"partial write preserves previous file and cache (mode %d)" % fault)
		check(DirAccess.get_files_at(folder.get_current_dir()).size() == 1, "failed temp write is cleaned (mode %d)" % fault)
	scene.write_fault = 0
	check(scene._save_checkpoint(), "existing checkpoint is replaced after successful verification")
	check(FileAccess.get_file_as_bytes(scene.checkpoint_path) != original and not scene._checkpoint.run_valid,
		"replacement commits the new assisted state to file and cache")
	var committed := FileAccess.get_file_as_bytes(scene.checkpoint_path)
	var committed_cache: Dictionary = scene._checkpoint.duplicate(true)
	var normal_path := scene.checkpoint_path
	scene.checkpoint_path = normal_path.path_join("impossible.json")
	check(not scene._save_checkpoint() and FileAccess.get_file_as_bytes(normal_path) == committed and scene._checkpoint == committed_cache,
		"directory creation failure preserves the previous file and cache")
	var blocked_path := folder.get_current_dir().path_join("blocked")
	DirAccess.make_dir_absolute(blocked_path)
	var blocker := FileAccess.open(blocked_path.path_join("keep.txt"), FileAccess.WRITE)
	blocker.store_string("keep")
	blocker.close()
	scene.checkpoint_path = blocked_path
	check(not scene._save_checkpoint() and FileAccess.get_file_as_bytes(normal_path) == committed and scene._checkpoint == committed_cache,
		"rename failure preserves the previous file and cache")
	check(FileAccess.get_file_as_string(blocked_path.path_join("keep.txt")) == "keep", "rename failure preserves destination directory")
	DirAccess.remove_absolute(blocked_path.path_join("keep.txt"))
	DirAccess.remove_absolute(blocked_path)
	scene.checkpoint_path = normal_path
	scene.move_fault = 1
	check(not scene._save_checkpoint() and FileAccess.get_file_as_bytes(normal_path) == committed and scene._checkpoint == committed_cache,
		"failed commit after old-file move rolls back file and keeps cache")
	check(DirAccess.get_files_at(folder.get_current_dir()).size() == 1, "successful rollback leaves no temporary files")
	scene.move_fault = 2
	scene.handle_action("save")
	check(not FileAccess.file_exists(normal_path) and scene._checkpoint == committed_cache
		and FileAccess.get_file_as_bytes(scene._checkpoint_backup_path) == committed,
		"failed commit and rollback retain the exact old bytes in a named backup")
	check(scene.dashboard.toast.text.contains(scene._checkpoint_backup_path), "rollback failure exposes the retained file path")
	scene._checkpoint = {}
	scene.handle_action("restore")
	check(not scene.session.run_valid and scene.session.paused, "restore can load retained backup after rollback failure")
	scene.free()
	scene = _new_activity()
	scene.checkpoint_path = normal_path
	check(scene._checkpoint_backup_path.is_empty(), "fresh activity has no remembered backup path")
	scene.handle_action("restore")
	check(not scene.session.run_valid and scene.session.paused and scene._checkpoint == committed_cache,
		"fresh activity discovers and strictly validates the retained backup")
	check(FileAccess.get_file_as_bytes(normal_path) == committed and DirAccess.get_files_at(folder.get_current_dir()).size() == 1,
		"fresh activity returns backup to the missing primary path")
	# A rejected checkpoint must never erase a prior good cache/file.
	var tape: PackedFloat64Array = scene.session._control_tape.duplicate()
	scene.session._control_tape.append(1.0)
	check(not scene._save_checkpoint() and FileAccess.get_file_as_bytes(normal_path) == committed and scene._checkpoint == committed_cache,
		"invalid candidate cannot replace previous checkpoint")
	scene.session._control_tape = tape
	scene._checkpoint = {}
	scene.handle_action("restore")
	check(not scene.session.run_valid and scene.session.paused, "restore loads committed disk state when cache is empty")
	check(scene.session.reset("start"), "new run resets assisted state")
	check(scene.session.start_recording() and scene._save_checkpoint() and scene.session.recording,
		"saving during recording succeeds without interrupting recording")
	scene.session.stop_recording()
	scene.free()
	scene = _new_activity()
	# UI must reflect a rejected start, not claim it is recording.
	var telemetry: Dictionary = scene.session._last_telemetry.duplicate(true)
	scene.session._last_telemetry = {}
	var label: String = scene.dashboard.record_button.text
	scene.handle_action("record")
	check(not scene.session.recording and scene.dashboard.record_button.text == label,
		"rejected recording start preserves button state")
	check(scene.dashboard.toast.text.contains("could not start"), "recording failure is explained")
	scene.session._last_telemetry = telemetry
	scene.handle_action("record")
	check(scene.session.recording and scene.dashboard.record_button.text.contains("Stop"), "successful recording start updates button")
	scene.session.stop_recording()
	# Explicit event-observer fixtures; physical jump traversal is in test_rcv_activity.
	scene._event({"type":"jump","time_s":1.0})
	scene._event({"type":"landing","time_s":1.25})
	check(scene._landing_pending, "landing awaits a settling interval")
	scene._event({"type":"jump","time_s":1.3})
	check(not scene._landing_pending, "new takeoff cancels the previous landing award")
	scene._event({"type":"landing","time_s":1.6})
	scene._landing_tick = scene.session.tick - 120
	scene.session._last_telemetry.airborne = true
	scene.session._last_telemetry.wheel_in_contact = PackedByteArray([0, 0, 0, 0])
	scene._update_landing_award()
	check(scene._best_jump == 0.0, "upright but unsupported vehicle earns no landing award")
	check(not scene.dashboard.toast.text.contains("Rollover"), "unsupported upright vehicle is not mislabeled as rollover")
	scene._event({"type":"jump","time_s":2.0})
	scene._event({"type":"landing","time_s":2.5})
	scene.session._last_telemetry.airborne = false
	scene.session._last_telemetry.wheel_in_contact = PackedByteArray([1, 1, 1, 1])
	scene._update_landing_award()
	check(scene._landing_pending and scene._best_jump == 0.0, "supported landing cannot score before settling interval")
	scene._landing_tick = scene.session.tick - 120
	scene._update_landing_award()
	check(scene._best_jump == 0.5 and scene.dashboard.toast.text.contains("Landed!"), "settled supported valid run earns its landing award")
	scene._event({"type":"jump","time_s":3.0})
	scene._event({"type":"landing","time_s":4.0})
	scene._landing_tick = scene.session.tick - 120
	scene.session.run_valid = false
	scene._update_landing_award()
	check(scene._best_jump == 0.5 and not scene.dashboard.toast.text.contains("Landed!"), "assisted run cannot earn a landing award")
	scene.session._last_telemetry = telemetry
	scene.free()
	for name in DirAccess.get_files_at(folder.get_current_dir()):
		DirAccess.remove_absolute(folder.get_current_dir().path_join(name))
	await process_frame
	print("RCV activity audit: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
