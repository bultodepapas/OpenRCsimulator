## PT1h-R6: standalone diagnostic driver, never loaded by the game.
## Invoke through lifecycle_check.py; each run owns a fresh output/settings folder.
extends SceneTree

const Preferences := preload("res://app_state/preferences.gd")
const FORMAT := "openrc-lifecycle-probe v1"
const DETAIL_LIMIT := 20
const ORPHAN_SCAN_LIMIT := 2048

var _config := {scenario = "both", cycles = 3, warmup_cycles = 1, settle_frames = 8, dwell_seconds = 0.25}
var _out_dir := ""
var _app: Node
var _samples: Array[Dictionary] = []
var _failure := ""
var _total_retired_alive := 0
var _baseline_orphans: Dictionary = {}
var _baseline_orphans_complete := false
var _cleanup := {retired_objects_checked = 0, retired_objects_alive = [], complete = false}


func _initialize() -> void:
	_run.call_deferred()


func _options() -> bool:
	var seen := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if not argument.begins_with("--") or pair.size() != 2 or seen.has(pair[0]):
			_failure = "expected unique --name=value options"
			return false
		seen[pair[0]] = true
		var key: String = pair[0].replace("-", "_")
		var value: String = pair[1]
		if key == "out_dir":
			_out_dir = value
		elif key == "scenario":
			if value not in ["flight", "workshop", "both"]:
				_failure = "scenario must be flight, workshop or both"
				return false
			_config[key] = value
		elif key in ["cycles", "warmup_cycles", "settle_frames"]:
			if not value.is_valid_int():
				_failure = "%s must be an integer" % key
				return false
			_config[key] = value.to_int()
		elif key == "dwell_seconds":
			if not value.is_valid_float() or not is_finite(value.to_float()):
				_failure = "dwell-seconds must be finite"
				return false
			_config[key] = value.to_float()
		else:
			_failure = "unknown lifecycle option: %s" % pair[0]
			return false
	if _config.cycles < 2 or _config.cycles > 30 or _config.warmup_cycles < 1 or _config.warmup_cycles > 5 \
		or _config.settle_frames < 3 or _config.settle_frames > 300 \
		or _config.dwell_seconds < 0.0 or _config.dwell_seconds > 10.0:
		_failure = "cycles 2..30, warmup-cycles 1..5, settle-frames 3..300, dwell-seconds 0..10 required"
		return false
	if _out_dir.is_empty() or not _out_dir.is_absolute_path():
		_failure = "out-dir must be an absolute path to a NEW directory with an existing parent"
		return false
	var error: Error = DirAccess.make_dir_absolute(_out_dir)
	if error != OK:
		_failure = "cannot exclusively create output directory (error %d): %s" % [error, _out_dir]
		return false
	return true


func _run() -> void:
	if not _options():
		printerr("lifecycle configuration: ", _failure)
		quit(2)
		return
	if not OS.is_debug_build():
		_failure = "debug engine required: release builds cannot supply trustworthy orphan/memory monitors"
		_finish(false)
		return
	# Save defaults in this run's directory before the shell can load any preferences.
	var settings: Dictionary = Preferences.DEFAULTS.duplicate(true)
	settings.check_updates = false
	settings.first_flight_hint_seen = true
	settings.language = "en"
	var preferences_path: String = _out_dir.path_join("settings.cfg")
	if Preferences.save_to(preferences_path, settings) != OK:
		_failure = "cannot create isolated lifecycle preferences"
		_finish(false)
		return
	root.size = Vector2i(1280, 720)
	_app = load("res://app_root.tscn").instantiate()
	_app.user_args = PackedStringArray()
	_app.preferences_path = preferences_path
	_app.update_check_url = "disabled-for-lifecycle-probe"
	_app.child_entered_tree.connect(_isolate_workshop)
	root.add_child(_app)
	root.size = Vector2i(1280, 720)
	await _settle()
	if not _home_ready():
		_failure = "startup did not reach Home"
		await _close_app()
		_finish(false)
		return
	for cycle in range(_config.warmup_cycles):
		print("lifecycle warmup ", cycle + 1, "/", _config.warmup_cycles)
		await _cycle()
		if not _failure.is_empty():
			break
	if _failure.is_empty():
		_remember_baseline_orphans()
		_samples.append(_snapshot("home_baseline", 0, {retired_objects_checked = 0, retired_objects_alive = []}))
		if not _publish(false):
			_failure = "could not write baseline report"
	for cycle in range(1, _config.cycles + 1):
		if not _failure.is_empty():
			break
		print("lifecycle measured ", cycle, "/", _config.cycles)
		var retired: Dictionary = await _cycle()
		if not _failure.is_empty():
			break
		_samples.append(_snapshot("home_settled", cycle, retired))
		if not _publish(false):
			_failure = "could not write measured report"
	await _close_app()
	_finish(_failure.is_empty() and _samples.size() == int(_config.cycles) + 1)


func _home_ready() -> bool:
	return is_instance_valid(_app) and _app.home != null and _app.flight == null and _app.screens.is_top("home")


func _isolate_workshop(child: Node) -> void:
	# child_entered_tree fires before _ready loads the Workshop library.
	if "variants_root" in child:
		# Store accepts only user:// roots. No library action is invoked; this
		# unique, absent path provides an empty library without reading player variants.
		child.variants_root = "user://lifecycle_probe_%s_%s/aircraft_variants" % [OS.get_process_id(), get_instance_id()]
		child.recovery_enabled = false


func _settle() -> void:
	# Several full frames let queue_free, deferred callbacks and UI work finish.
	for _frame in range(_config.settle_frames):
		await process_frame
	if _config.dwell_seconds > 0.0:
		await create_timer(_config.dwell_seconds).timeout
	await process_frame
	await process_frame


func _identity(object: Object, label: String) -> Dictionary:
	var script: Script = object.get_script() as Script
	return {id = str(object.get_instance_id()), label = label.left(256),
		"class" = object.get_class(), script = script.resource_path.left(512) if script != null else ""}


func _watch(watches: Array[Dictionary], object: Object, label: String) -> void:
	if is_instance_valid(object):
		# Only IDs/strings are retained, never strong references that alter lifetimes.
		watches.append(_identity(object, label))


func _check_retired(watches: Array[Dictionary]) -> Dictionary:
	var alive: Array[Dictionary] = []
	for item in watches:
		if is_instance_id_valid(str(item.id).to_int()):
			_total_retired_alive += 1
			if alive.size() < DETAIL_LIMIT:
				alive.append(item)
	return {retired_objects_checked = watches.size(), retired_objects_alive = alive}


func _cycle() -> Dictionary:
	var watches: Array[Dictionary] = []
	if _config.scenario in ["flight", "both"]:
		_watch(watches, _app.home, "departed Home UI")
		_watch(watches, _app.home_scene, "departed Home backdrop")
		_app.start_flight()
		if not is_instance_valid(_app.flight) or not str(_app.flight.startup_error).is_empty():
			_failure = "flight startup failed or was refused"
			return _check_retired(watches)
		_watch(watches, _app.flight, "retired flight")
		_watch(watches, _app.flight.session, "retired flight session")
		if _app.flight.session != null:
			_watch(watches, _app.flight.session.sim, "retired simulation")
			if _app.flight.session.sim != null and "model" in _app.flight.session.sim:
				_watch(watches, _app.flight.session.sim.model, "retired vehicle model")
		_app.open_pause()
		_watch(watches, _app.pause_menu, "retired pause menu")
		await _settle()
		_app.end_flight()
		await _settle()
		if not _home_ready():
			_failure = "End flight did not return to Home; inspect engine.log for pending recovery or startup errors"
			return _check_retired(watches)
	if _config.scenario in ["workshop", "both"]:
		_app.open_workshop()
		if not _app.screens.is_top("workshop"):
			_failure = "Workshop did not open"
			return _check_retired(watches)
		_watch(watches, _app.screens.get_screen("workshop"), "retired Workshop")
		await _settle()
		_app.close_workshop()
		await _settle()
		if not _home_ready():
			_failure = "Workshop did not return to Home"
	return _check_retired(watches)


func _remember_baseline_orphans() -> void:
	var count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_baseline_orphans_complete = count <= ORPHAN_SCAN_LIMIT
	if _baseline_orphans_complete:
		for id in Node.get_orphan_node_ids():
			_baseline_orphans[id] = true


func _snapshot(phase: String, cycle: int, retired: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var sample := {
		phase = phase, cycle = cycle, monotonic_usec = started,
		node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		orphan_node_count = orphan_count,
		object_count = int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		resource_count = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		static_memory_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		retired_objects_checked = retired.retired_objects_checked,
		retired_objects_alive = retired.retired_objects_alive,
		orphan_details = [], orphan_details_truncated = not _baseline_orphans_complete or orphan_count > ORPHAN_SCAN_LIMIT,
	}
	if not sample.orphan_details_truncated:
		for id in Node.get_orphan_node_ids():
			if _baseline_orphans.has(id):
				continue
			if sample.orphan_details.size() == DETAIL_LIMIT:
				sample.orphan_details_truncated = true
				break
			var object: Object = instance_from_id(id)
			if is_instance_valid(object):
				sample.orphan_details.append(_identity(object, "new orphan since baseline"))
	sample.sample_overhead_usec = Time.get_ticks_usec() - started
	return sample


func _close_app() -> void:
	var watches: Array[Dictionary] = []
	if is_instance_valid(_app):
		_watch(watches, _app, "retired application root")
		_app.queue_free()
		_app = null
		await _settle()
	_cleanup = _check_retired(watches)
	_cleanup.complete = true


func _publish(complete: bool) -> bool:
	var report := {
		format = FORMAT, capture_id = OS.get_environment("OPENRC_DIAGNOSTIC_CAPTURE_ID"),
		complete = complete, failure = _failure, config = _config, debug_build = OS.is_debug_build(),
		godot = Engine.get_version_info().string, samples = _samples, cleanup = _cleanup,
		total_retired_alive = _total_retired_alive,
		scope = "Settled Home checkpoints after warm-up; selected retired object IDs. Static memory is not process RSS or a leak diagnosis.",
	}
	var file := FileAccess.open(_out_dir.path_join("lifecycle.json"), FileAccess.WRITE)
	if file == null:
		printerr("lifecycle report open failed: ", FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		printerr("lifecycle report write failed: ", error)
	return error == OK


func _finish(complete: bool) -> void:
	if not _publish(complete):
		quit(2)
		return
	if not complete:
		printerr("lifecycle incomplete: ", _failure)
	elif _total_retired_alive > 0:
		printerr("lifecycle retained objects: ", _total_retired_alive, "; inspect lifecycle.json and engine.log")
	else:
		print("lifecycle capture complete")
	quit(0 if complete and _total_retired_alive == 0 else 1)
