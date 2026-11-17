# Observation probe: the real multirotor activity and recorder across reset, F10 and Home.
# The writer failure is deliberately injected at the production packet-writer seam and calls the production
# recorder's _failed(); it is not evidence of an actual disk-full or OS-specific failure. Passing checks describe
# baseline behavior, not a desired-behavior regression. The Home check observes the activity's managed departure
# signal; it does not construct AppRoot or claim a native Home/quit interaction.
extends SceneTree

const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const MultirotorLog := preload("res://sim/multirotor/flight_log.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DT := 1.0 / 240.0
const SENTINEL := "recording diagnostic sentinel"


class InjectedWriteFailure extends "res://sim/multirotor/flight_log.gd":
	const INJECTED := "INJECTED packet-write failure (diagnostic)"
	var inject := false
	var injections := 0

	func _init(session: Node) -> void:
		super(session)

	func _write_packet(value: Dictionary) -> bool:
		if inject and str(value.get("kind", "")) in ["block", "footer"]:
			injections += 1
			# _failed intentionally prints the injection to stderr and closes the file without a footer.
			_failed(INJECTED, ERR_FILE_CANT_WRITE)
			return false
		return super._write_packet(value)


var _checks := 0
var _failures := 0
var _facts := {injection = "explicit packet-writer failure; not a real disk-full observation",
	home_scope = "activity managed-departure signal; AppRoot and native close not exercised"}
var _directory := ""
var _f10_created_path := ""


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])


func _initialize() -> void:
	_run.call_deferred()


func _ticks(activity: Node, count: int) -> bool:
	for _i in count:
		var before: int = int(activity.session.sim.tick)
		activity._physics_process(DT)
		if activity.session.paused or int(activity.session.sim.tick) != before + 1:
			return false
	return true


func _run() -> void:
	# Unique directory and result location; F10 itself uses the production generated user://flight_logs filename.
	_directory = "user://lifecycle-recording-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var made: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_check("unique diagnostic directory created", made == OK)
	if made != OK:
		await _finish(null)
		return

	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.results_directory = _directory.path_join("results")
	activity.scripted_pilot = func(_tick: int) -> PackedFloat64Array:
		return FC.neutral_input(int(activity._flight_generation), true)
	root.add_child(activity)
	activity.set_physics_process(false) # Only explicit calls below advance the real activity.
	var ready: bool = activity.startup_error.is_empty() and activity.session != null and activity.session.prepared
	_check("real activity prepares without world or audio", ready)
	if not ready:
		await _finish(activity)
		return

	var context := {field_path = activity.field_path}
	var healthy_path := _directory.path_join("healthy.orfl")
	var healthy := MultirotorLog.new(activity.session)
	activity.flight_log = healthy
	var healthy_start: bool = healthy.start(context, healthy_path) == OK
	activity.handle_action("resume")
	var healthy_ticks: bool = not activity.session.paused and _ticks(activity, 2)
	var healthy_stop: bool = healthy.stop("diagnostic healthy control") == OK
	var healthy_read: Dictionary = MultirotorLog.inspect(healthy_path)
	var healthy_complete: bool = healthy_start and healthy_ticks and healthy_stop and healthy_read.get("ok", false) \
		and healthy_read.get("complete", false) and (healthy_read.get("ticks", PackedInt64Array()) as PackedInt64Array).size() == 2
	_check("healthy activity recording finalizes and is readable", healthy_complete)
	_facts.healthy_complete = healthy_complete

	# First flush one full block. The later injected failure then leaves a genuinely readable, incomplete prefix.
	var reset_path := _directory.path_join("reset-failure.orfl")
	var reset_log := InjectedWriteFailure.new(activity.session)
	activity.flight_log = reset_log
	var reset_started: bool = reset_log.start(context, reset_path) == OK
	var prefix_ticks: bool = _ticks(activity, MultirotorLog.CHUNK_TICKS)
	var partial_ticks: bool = _ticks(activity, 3)
	_check("reset case has a flushed block and buffered accepted ticks", reset_started and prefix_ticks and partial_ticks \
		and reset_log.recording and reset_log.rows_written == MultirotorLog.CHUNK_TICKS)
	activity.hud.flash(SENTINEL, 60.0)
	reset_log.inject = true
	var reset_ok: bool = activity.restart_on_pad()
	var reset_failed: bool = reset_log.injections == 1 and not reset_log.recording \
		and reset_log.failure == InjectedWriteFailure.INJECTED
	var reset_unreported: bool = activity.hud.message.text == SENTINEL \
		and not activity.hud.menu_reason.text.contains(InjectedWriteFailure.INJECTED)
	var reset_read: Dictionary = MultirotorLog.inspect(reset_path)
	var reset_prefix: bool = reset_read.get("ok", false) and not reset_read.get("complete", true) \
		and (reset_read.get("ticks", PackedInt64Array()) as PackedInt64Array).size() == MultirotorLog.CHUNK_TICKS
	_check("reset succeeds after an injected final-flush failure", reset_ok and reset_failed \
		and activity.session.paused and int(activity.session.sim.tick) == 0)
	_check("reset leaves the previous complete block as an incomplete readable prefix", reset_prefix)
	_check("reset does not replace the HUD sentinel with the failure", reset_unreported)
	_facts.reset = {injected = reset_failed, reset_succeeded = reset_ok, prefix_readable_incomplete = reset_prefix,
		hud_unchanged = reset_unreported}

	# Exercise the real F10 handler after the failed automatic stop. It uses its own unique generated filename.
	activity.toggle_recording()
	var next_log: RefCounted = activity.flight_log
	var f10_started: bool = not is_same(next_log, reset_log) and bool(next_log.recording) \
		and str(next_log.failure).is_empty()
	if f10_started:
		_f10_created_path = str(next_log.path)
	var f10_notice: bool = str(activity.hud.message.text).begins_with("Flight log REC:") \
		and not str(activity.hud.message.text).contains(InjectedWriteFailure.INJECTED)
	_check("F10 replaces the failed recorder and shows the new recording notice", f10_started and f10_notice)
	if f10_started:
		activity.toggle_recording()
	var f10_read: Dictionary = MultirotorLog.inspect(_f10_created_path) if not _f10_created_path.is_empty() else {}
	var f10_closed: bool = f10_read.get("ok", false) and f10_read.get("complete", false)
	_check("the replacement F10 recording can be finalized", f10_closed)
	_facts.new_f10 = {started = f10_started, previous_failure_not_in_notice = f10_notice,
		finalized = f10_closed}

	# A separate injected failure at the Home action: a stand-in managed host counts the actual signal and leaves the
	# activity alive long enough for observation. This is not a simulation of AppRoot's full exit guard.
	activity.handle_action("resume")
	var home_path := _directory.path_join("home-failure.orfl")
	var home_log := InjectedWriteFailure.new(activity.session)
	activity.flight_log = home_log
	var home_started: bool = home_log.start(context, home_path) == OK
	var home_ticks: bool = not activity.session.paused and _ticks(activity, 3)
	var departures := [0]
	activity.home_requested.connect(func() -> void: departures[0] += 1)
	activity.hud.flash(SENTINEL, 60.0)
	home_log.inject = true
	activity.handle_action("home")
	var home_failed: bool = home_log.injections == 1 and not home_log.recording \
		and home_log.failure == InjectedWriteFailure.INJECTED
	var home_unreported: bool = activity.hud.message.text == SENTINEL
	var home_read: Dictionary = MultirotorLog.inspect(home_path)
	var home_incomplete: bool = home_read.get("ok", false) and not home_read.get("complete", true)
	_check("Home was requested after an injected final-flush failure", home_started and home_ticks and home_failed \
		and departures[0] == 1 and activity.session.paused)
	_check("Home failure remains incomplete and is not flashed by the action", home_incomplete and home_unreported)
	_facts.home = {injected = home_failed, departure_signal_count = departures[0],
		incomplete = home_incomplete, hud_unchanged = home_unreported}

	await _finish(activity)


func _finish(activity: Node) -> void:
	if activity != null:
		root.remove_child(activity)
		activity.free()
	if not _f10_created_path.is_empty() and FileAccess.file_exists(_f10_created_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_f10_created_path))
	if not _directory.is_empty() and DirAccess.dir_exists_absolute(_directory):
		for name: String in DirAccess.get_files_at(_directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory.path_join(name)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
	# Drain queued nodes before exit; no user paths or machine-specific identities enter the JSON.
	await process_frame
	await process_frame
	_facts.checks = _checks
	_facts.failures = _failures
	print("LIFECYCLE_RECORDING_JSON " + JSON.stringify(_facts))
	print("LIFECYCLE RECORDING: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
