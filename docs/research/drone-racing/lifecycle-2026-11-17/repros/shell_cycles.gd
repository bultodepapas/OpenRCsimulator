# Diagnostic observations for the 2026-11-17 lifecycle audit, not desired-behavior tests.
# AppRoot, the quad, the statistics service, and race persistence are production objects.
# The statistics write failure is injected using an isolated file as a directory. Race
# physics is stepped through the scene's own tick handler with a scripted pilot; synthetic
# root-viewport key events do not establish native window or controller behavior.
extends SceneTree

const FC := preload("res://physics/multirotor/flight_controller.gd")
const RaceModel := preload("res://sim/race/race_model.gd")
const Director := preload("res://sim/race/race_director.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const DT := 1.0 / 240.0


class ProbeApp extends "res://app_root.gd":
	var quit_requests := 0
	func _request_app_quit() -> void:
		quit_requests += 1


var checks := 0
var failures := 0
var ui: RefCounted
var scratch := ""
var pilot_generation := 0
var observations := {
	format = "openrc-lifecycle-shell-observation v1",
	fixture = {statistics_failure = "injected: real statistics store path points to a file",
		input = "synthetic root viewport keys; Cancel uses the dialog's canceled signal",
		race = "scripted pilot; manual calls to the activity's real physics tick",
		race_departure = "terminal projection observation; departure policy is not specified"},
	quit_guard = {},
	race_home = {},
}


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])


func _initialize() -> void:
	_run.call_deferred()


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)


func _neutral_pilot(_tick: int) -> PackedFloat64Array:
	var frame := FC.neutral_input(pilot_generation, true)
	frame[FC.IN_MODE] = float(FC.FLIGHT_ANGLE)
	return frame


func _race_pilot(tick: int) -> PackedFloat64Array:
	var frame := _neutral_pilot(tick)
	frame[FC.IN_ARM] = 1.0 if tick >= 4 else 0.0
	return frame


func _phase(activity: Node) -> int:
	return int(activity.session.sim.modes[RaceModel.MODE_PHASE])


func _race_files(directory: String) -> PackedStringArray:
	var found := PackedStringArray()
	var absolute := ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute):
		for name: String in DirAccess.get_files_at(absolute):
			if name.begins_with("race-") and name.ends_with(".json"):
				found.append(name)
	found.sort()
	return found


## The actual quad scene and the real statistics service are initialized on Home first.
func _make_app() -> ProbeApp:
	var app := ProbeApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = scratch.path_join("settings.cfg")
	app.statistics_path = scratch.path_join("statistics")
	app.update_state_path = scratch.path_join("update-state.json")
	app.update_check_url = "disabled"
	app.flight_loading_enabled = false
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	await ui.settle()
	return app


## A real idle statistics close can fail even though the quad is not a statistics flight.
func _quit_guard(app: ProbeApp, activity: Node, blocker: String) -> bool:
	var session: Node = activity.session
	var stats: Node = app.statistics_service
	var stats_ready: bool = is_instance_valid(stats) and stats.store != null and stats.store.writable
	if stats_ready:
		stats_ready = stats.flush()
	check("real statistics store starts writable", stats_ready)
	if not stats_ready:
		return false
	activity.scripted_pilot = Callable(self, "_neutral_pilot")
	activity.handle_action("resume")
	var tick_at_resume: int = int(session.sim.tick)
	var began: bool = await ui.wait_until(func() -> bool:
		return int(session.sim.tick) >= tick_at_resume + 3, 10000)
	check("quad accepts ticks before the quit request", began and not session.paused and not activity.hud.menu_visible)
	if not began or session.paused:
		return false

	# Positive control: the same synthetic viewport C reaches the activity before a modal.
	var initial_view: int = int(activity.view.view)
	_key(KEY_C)
	await ui.settle()
	var c_before: bool = int(activity.view.view) != initial_view
	check("root viewport C reaches the running quad before the modal", c_before)

	stats._finish_write()
	var original_root: String = stats.store._root_path
	stats.store._root_path = blocker
	# AppRoot defers the WM close before starting its real exit transaction.
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var shown: bool = await ui.wait_until(func() -> bool:
		return is_instance_valid(app._statistics_save_dialog) and app._statistics_save_dialog.visible, 10000)
	var dialog := app._statistics_save_dialog as ConfirmationDialog
	var q: Dictionary = observations.quit_guard
	q.dialog_visible = shown
	q.statistics_note = str(stats.note)
	q.request_active = app._exit_request_active
	q.quit_requests = app.quit_requests
	check("injected statistics write failure opens the real exclusive quit decision", shown and dialog != null and dialog.exclusive
		and app._exit_request_active and app.quit_requests == 0 and not str(stats.note).is_empty())
	if not shown or dialog == null:
		stats.store._root_path = original_root
		return false

	var before_tick: int = int(session.sim.tick)
	var before_view: int = int(activity.view.view)
	q.activity_unhandled_enabled = activity.is_processing_unhandled_input()
	_key(KEY_C)
	await ui.settle()
	q.synthetic_c_changed_view = int(activity.view.view) != before_view
	var advanced: bool = await ui.wait_until(func() -> bool:
		return int(session.sim.tick) >= before_tick + 3, 10000)
	q.tick_before = before_tick
	q.tick_after = int(session.sim.tick)
	q.tick_delta = int(session.sim.tick) - before_tick
	q.paused = bool(session.paused)
	q.menu_visible = bool(activity.hud.menu_visible)
	q.dialog_still_visible = is_instance_valid(dialog) and dialog.visible
	check("diagnostic: the quad advances while the statistics decision remains open", advanced and q.tick_delta > 0
		and not session.paused and q.dialog_still_visible and app._exit_request_active)
	check("diagnostic: quad unhandled input processing was not disabled by the guard", q.activity_unhandled_enabled)
	# The synthetic C observation is recorded without asserting that a particular modal
	# implementation must deliver the key; exclusive-window delivery varies by surface.
	app.quit_app()
	check("a repeated quit retains the same decision", app._statistics_save_dialog == dialog and app.quit_requests == 0)
	dialog.canceled.emit() # Exercise the actual Cancel callback, not native dialog input delivery.
	await ui.settle()
	stats.store._root_path = original_root
	q.cancel_keeps_activity = app.ground_vehicle == activity and is_instance_valid(activity)
	q.cancel_clears_request = not app._exit_request_active and app.quit_requests == 0
	q.cancel_paused = bool(session.paused)
	q.cancel_menu_visible = bool(activity.hud.menu_visible)
	check("Cancel retains the quad and clears the quit transaction", q.cancel_keeps_activity and q.cancel_clears_request)
	check("diagnostic: Cancel leaves this previously running quad running", not q.cancel_paused and not q.cancel_menu_visible)
	var tick_after_cancel: int = int(session.sim.tick)
	var cancel_advanced: bool = await ui.wait_until(func() -> bool:
		return int(session.sim.tick) >= tick_after_cancel + 3, 10000)
	q.cancel_tick_delta = int(session.sim.tick) - tick_after_cancel
	check("diagnostic: accepted ticks continue after Cancel", cancel_advanced and q.cancel_tick_delta > 0)
	return q.cancel_keeps_activity and q.cancel_clears_request and not app._quit_audio_pending


## Start a real course on its pad with ordinary sampled race actions, bounded to 1000 ticks.
func _start_race(activity: Node) -> bool:
	activity.scripted_pilot = Callable(self, "_race_pilot")
	if not activity.restart_on_pad():
		return false
	activity.handle_action("resume")
	if activity.session.paused:
		return false
	for _i in 12:
		activity._physics_process(DT)
	if activity.session.paused or int(activity.session.sim.modes[FC.MODE_MOTOR]) != FC.MOTOR_ARMED:
		return false
	activity.request_race()
	for _i in 1000:
		if _phase(activity) == Director.PHASE_RACING:
			return true
		if activity.session.paused:
			return false
		activity._physics_process(DT)
	return _phase(activity) == Director.PHASE_RACING


func _home_during_race(app: ProbeApp, activity: Node) -> void:
	var session: Node = activity.session
	var directory := scratch.path_join("race-results")
	var directory_ok: bool = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK
	check("isolated race result directory opens", directory_ok)
	if not directory_ok:
		return
	activity.results_directory = directory
	# The real scene may have read its default book during construction; isolate this fixture's book as well as files.
	activity._records = {}
	activity._records_loaded = false
	activity._records_writable = true
	activity.set_physics_process(false)
	var emitted: Array[Dictionary] = []
	session.race_result.connect(func(result: Dictionary) -> void: emitted.append(result.duplicate(true)))
	var control_started := _start_race(activity)
	check("control race reaches RACING using accepted scene ticks", control_started)
	if not control_started:
		observations.race_home.control_phase = _phase(activity)
		return
	activity.request_race()
	activity._physics_process(DT)
	var control_files := _race_files(directory)
	var control_ok: bool = _phase(activity) == Director.PHASE_ABORTED and emitted.size() == 1 \
		and str(emitted[0].get("reason", "")) == "cancelled" and control_files.size() == 1 and session.results.is_empty()
	check("control: G cancel publishes one terminal result to healthy isolated storage", control_ok)
	var second_started := _start_race(activity)
	check("second race reaches RACING before Home", second_started)
	if not control_ok or not second_started:
		return

	var exit_snapshot: Array[Dictionary] = []
	activity.tree_exiting.connect(func() -> void:
		if is_instance_valid(session):
			exit_snapshot.append({phase = int(session.sim.modes[RaceModel.MODE_PHASE]),
				pending_results = session.results.size(), tick = int(session.sim.tick)}))
	_key(KEY_P)
	await ui.settle()
	var menu_open: bool = activity.hud.menu_visible and session.paused
	check("viewport P opens the quad menu without ending the active race", menu_open and _phase(activity) == Director.PHASE_RACING)
	if not menu_open:
		return
	activity.hud.home_button.grab_focus()
	var home_focused: bool = activity.hud.home_button.has_focus()
	check("Home button is focused for viewport activation", home_focused)
	if not home_focused:
		return
	var files_before := _race_files(directory)
	var events_before := emitted.size()
	_key(KEY_ENTER)
	var home_returned: bool = await ui.wait_until(func() -> bool:
		return app.ground_vehicle == null and is_instance_valid(app.home), 10000)
	var files_after := _race_files(directory)
	var r: Dictionary = observations.race_home
	r.control_cancel_results = events_before
	r.control_cancel_files = files_before.size()
	r.second_race_phase = "RACING"
	r.home_returned = home_returned
	r.exit_snapshot = exit_snapshot
	r.terminal_signals_after_home = emitted.size() - events_before
	r.result_files_after_home = files_after.size() - files_before.size()
	var exited_racing: bool = exit_snapshot.size() == 1 and int(exit_snapshot[0].phase) == Director.PHASE_RACING \
		and int(exit_snapshot[0].pending_results) == 0
	check("observation: healthy Home from RACING emits and writes no additional terminal result", home_returned
		and exited_racing and r.terminal_signals_after_home == 0 and r.result_files_after_home == 0)


func _remove_fixture(path: String) -> void:
	var prefix := ProjectSettings.globalize_path("user://lifecycle_shell_")
	if not path.begins_with(prefix):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories():
		_remove_fixture(path.path_join(name))
	directory = null
	DirAccess.remove_absolute(path)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	ui = UiDriver.new(self)
	var initial_auto_accept := auto_accept_quit
	scratch = "user://lifecycle_shell_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var absolute := ProjectSettings.globalize_path(scratch)
	var opened: bool = DirAccess.make_dir_recursive_absolute(absolute) == OK
	check("isolated shell fixture directory opens", opened)
	if not opened:
		_finish()
		return
	var blocker := absolute.path_join("file-blocks-directory")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	check("statistics failure injection file opens", file != null)
	if file == null:
		_remove_fixture(absolute)
		_finish()
		return
	file.store_string("This regular file blocks child paths.")
	file.close()
	var app := await _make_app()
	check("real Home and statistics service initialize", is_instance_valid(app.home) and is_instance_valid(app.statistics_service))
	if is_instance_valid(app.home) and is_instance_valid(app.statistics_service):
		app.start_multirotor()
		var launched: bool = await ui.wait_until(func() -> bool: return is_instance_valid(app.ground_vehicle), 20000)
		check("real AppRoot launches the quad from Home", launched and app.has_home)
		if launched:
			var activity: Node = app.ground_vehicle
			var ready: bool = activity.startup_error.is_empty() and is_instance_valid(activity.session) \
				and activity.session.prepared and activity.session.race != null
			check("quad and its race session are prepared", ready)
			if ready:
				pilot_generation = int(activity.session.options.source_generation)
				var guard_complete: bool = await _quit_guard(app, activity, blocker)
				if guard_complete:
					await _home_during_race(app, activity)
	await ui.close_app(app)
	check("automatic close ownership is restored after cleanup", auto_accept_quit == initial_auto_accept)
	_remove_fixture(absolute)
	_finish()


func _finish() -> void:
	observations.checks = checks
	observations.failures = failures
	print("LIFECYCLE_SHELL_JSON " + JSON.stringify(observations))
	print("LIFECYCLE SHELL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
