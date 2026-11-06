extends SceneTree

const Activity := preload("res://vehicles/ground/ground_scene.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}


class ExportFixture extends "res://sim/ground_vehicle/session.gd":
	var export_attempts := 0
	var allow_export := false

	func export_recording(_name: String) -> Dictionary:
		export_attempts += 1
		if not allow_export:
			return {"ok": false, "error": "injected export failure"}
		# Exercise the scene and adapter without writing to the user's recording folder.
		_recording_exported = true
		return {"ok": true, "csv_path": "memory://recording.csv", "metadata_path": "memory://recording.json"}


class DashboardFixture extends CanvasLayer:
	var record_button := Button.new()
	var menu_visible := false
	var last_message := ""

	func _init() -> void:
		add_child(record_button)

	func set_menu(value: bool) -> void:
		menu_visible = value

	func words(english: String, _spanish: String) -> String:
		return english

	func message(english: String, _spanish: String) -> void:
		last_message = english


var checks := 0
var failures := 0


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: ", label)


func _snapshot(session) -> Dictionary:
	return {
		"tick": session.tick,
		"state": session.state_snapshot().to_byte_array(),
		"controls": session.control_tape_snapshot().to_byte_array(),
		"events": session.event_tape_snapshot(),
		"recovery": session.recovery_actions_snapshot(),
		"damage": session.damage_snapshot().to_byte_array(),
		"paused": session.paused,
		"holds": session.pause_holds(),
		"run_valid": session.run_valid,
		"fault": session.fault_reason,
		"model_identity": session._model_identity.duplicate(true),
		"course_identity": session._course_identity.duplicate(true),
	}


func _initialize() -> void:
	var scene := Activity.new()
	var session := ExportFixture.new()
	var dashboard := DashboardFixture.new()
	scene.session = session
	scene.dashboard = dashboard
	scene.add_child(session)
	scene.add_child(dashboard)
	_check("an unprepared session rejects recording without advancing its generation",
		not session.start_recording() and session.recording_generation == 0)
	_check("the real ground session prepares", session.prepare_default())
	if not session.prepared:
		scene.free()
		quit(1)
		return
	_check("neutral input allows driving", session.tick_once(NEUTRAL) and session.resume())
	_check("the session advances a tick", session.tick_once(NEUTRAL) and session.tick > 0)
	session.add_pause_hold("independent")
	scene.begin_exit_guard()
	_check("exit guard opens the garage and preserves another hold", dashboard.menu_visible and session.paused
		and "independent" in session.pause_holds() and "garage" in session.pause_holds()
		and "exit_guard" in session.pause_holds())
	scene.end_exit_guard()
	_check("ending the guard removes only its hold and never resumes", session.paused
		and "independent" in session.pause_holds() and "garage" in session.pause_holds()
		and "exit_guard" not in session.pause_holds())

	var recorder = scene.get_departure_recorder()
	_check("the scene returns one adapter", recorder == scene.get_departure_recorder())
	_check("a recording has its own generation", session.start_recording() and recorder.recording
		and recorder.recording_generation == 1 and recorder.has_unsaved_recording())
	var active_samples := session._record_samples.to_byte_array()
	_check("an active recording cannot be discarded or restarted", not recorder.discard_unsaved(1)
		and not session.start_recording() and session.recording_generation == 1
		and session._record_samples.to_byte_array() == active_samples)
	var home_requests := [0]
	scene.home_requested.connect(func() -> void: home_requests[0] += 1)
	scene.departure_managed = true
	scene.handle_action("home")
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("managed Home and close leave recording to the host", home_requests[0] == 1
		and session.recording and session.export_attempts == 0)

	scene.departure_managed = false
	scene.handle_action("home")
	_check("standalone Home vetoes a failed export", home_requests[0] == 1 and not session.recording
		and session.export_attempts == 1 and recorder.has_unsaved_recording()
		and recorder.note == "injected export failure" and session._record_samples.to_byte_array() == active_samples)
	scene._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	_check("standalone close retries and vetoes a failed export", session.export_attempts == 2
		and recorder.has_unsaved_recording() and session._record_samples.to_byte_array() == active_samples)
	var before_discard := _snapshot(session)
	_check("a mismatched generation cannot discard the stopped recording", not recorder.discard_unsaved(2)
		and recorder.has_unsaved_recording() and session._record_samples.to_byte_array() == active_samples
		and _snapshot(session) == before_discard)
	_check("discard clears only the selected recording", recorder.discard_unsaved(1)
		and not recorder.has_unsaved_recording() and session._record_samples.is_empty()
		and recorder.recording_generation == 1 and _snapshot(session) == before_discard
		and dashboard.record_button.text == "Record telemetry")

	_check("a new recording advances the generation", session.start_recording() and recorder.recording_generation == 2)
	_check("failed adapter save retains its data", recorder.stop() == ERR_CANT_CREATE
		and not recorder.recording and recorder.has_unsaved_recording())
	var second_samples := session._record_samples.to_byte_array()
	_check("discard of an older generation cannot affect a new stopped recording", not recorder.discard_unsaved(1)
		and session._record_samples.to_byte_array() == second_samples and recorder.has_unsaved_recording())
	session.allow_export = true
	_check("a later manual retry resolves the same generation", recorder.stop() == OK
		and not recorder.has_unsaved_recording() and recorder.recording_generation == 2)
	_check("successful manual save allows a third recording", session.start_recording() and recorder.recording_generation == 3)
	_check("a session stopped outside the scene remains discoverable", session.stop_recording()
		and not recorder.recording and recorder.has_unsaved_recording())
	_check("the stopped recording can be explicitly discarded", recorder.discard_unsaved(3)
		and not recorder.has_unsaved_recording())
	_check("reset preserves the generation counter", session.reset() and session.recording_generation == 3)
	_check("a recording after reset gets a new generation", session.start_recording() and session.recording_generation == 4)
	_check("cleanup discards that recording", session.stop_recording() and recorder.discard_unsaved(4))

	scene.free()
	_check("the adapter does not retain a freed scene", not recorder.recording and not recorder.has_unsaved_recording()
		and recorder.recording_generation == -1 and recorder.stop() == ERR_UNAVAILABLE)
	print("Ground departure: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
