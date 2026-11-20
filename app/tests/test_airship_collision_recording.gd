## CR-AUD-22 regression (collision audit 2026-11-17, promoted probe): changing the airship's collision world on a
## paused, started flight is a recording boundary; every written .orfl replays exactly. Without --out=<dir> the
## recordings go to a fresh folder under user://.
# Draft for the audit lead; no engine run has been performed by the author.
# Run with a fresh absolute --out=<directory>. The production airship recorder
# writes its real .orfl files there. No input checkpoint or world is fabricated.
#
# Diagnostic fixture: the default field's first tall, thin capsule, with the
# public release options used by test_airship_session.gd:119-147. The release
# is deliberately inside that stock pole. The changed-world case begins with
# no scenery collision world for its first accepted tick, then installs the
# real field world while paused. This isolates collision identity and does not
# purport to reproduce a player flying into a pole through the current UI;
# that UI installs the inventory at startup.
extends SceneTree

const Session := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")

var NEUTRAL := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

var output_dir: String = ""
var checks: Array[Dictionary] = []
var failures: int = 0
var observations: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
	if output_dir.is_empty():
		output_dir = OS.get_user_data_dir().path_join("cr-aud-22-%d" % Time.get_ticks_usec())
	_run.call_deferred()


func _check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	if not passed:
		failures += 1


func _finish() -> void:
	print("ROUND3_AIRSHIP_COLLISION_RECORDING_COMPLETE " + JSON.stringify({
		"checks": checks, "check_count": checks.size(), "failures": failures,
		"observations": observations,
	}))
	quit(1 if failures > 0 else 0)


# Preserve the small complete trace and real verifier report in the JSON output;
# the independently readable .orfl file is retained at the reported path.
func _trace(path: String) -> Dictionary:
	var read: Dictionary = AirshipLog.inspect(path)
	var trace: Dictionary = {
		"path": path,
		"inspect_ok": bool(read.get("ok", false)),
		"complete": bool(read.get("complete", false)),
		"inspect_error": str(read.get("error", "")),
	}
	if not bool(read.get("ok", false)) or not bool(read.get("complete", false)):
		return trace
	var header: Dictionary = read.get("header", {})
	var checkpoint: Dictionary = header.get("checkpoint", {})
	var ticks: PackedInt64Array = read.get("ticks", PackedInt64Array())
	var sticks: PackedFloat64Array = read.get("sticks", PackedFloat64Array())
	var states: PackedFloat64Array = read.get("states", PackedFloat64Array())
	var continuous: PackedFloat64Array = read.get("continuous", PackedFloat64Array())
	trace["header_collision_identity"] = str(header.get("collision_identity", ""))
	trace["checkpoint_tick"] = int(checkpoint.get("tick", -1))
	trace["checkpoint_state"] = Array(checkpoint.get("state", PackedFloat64Array()))
	trace["checkpoint_continuous"] = Array(checkpoint.get("continuous", PackedFloat64Array()))
	trace["ticks"] = Array(ticks)
	trace["sticks"] = Array(sticks)
	trace["states"] = Array(states)
	trace["continuous"] = Array(continuous)
	trace["events"] = read.get("events", [])
	trace["footer"] = read.get("footer", {})
	trace["verify"] = AirshipLog.verify(path)
	return trace


func _run_case(name: String, field: Dictionary, options: Dictionary, world: Dictionary, mode: String) -> Dictionary:
	var result: Dictionary = {"case": name, "mode": mode}
	var session: Node = Session.new()
	root.add_child(session)
	var installed_empty: bool = session.set_collision_world({})
	var prepared: bool = session.prepare(field, options)
	result["setup_error"] = str(session.load_error)
	_check(name + ": empty initial world and stock airship prepare", installed_empty and prepared)
	if not installed_empty or not prepared:
		session.free()
		return result

	# A world installed before recording is a valid positive control: the log
	# must describe the new world and replay the actual terminal pole strike.
	if mode == "pre_record_world":
		var pre_installed: bool = session.set_collision_world(world)
		_check(name + ": stock world installs before recording", pre_installed)
		if not pre_installed:
			session.free()
			return result

	var resets: Array[int] = [0]
	session.resetting.connect(func() -> void: resets[0] += 1)
	var log_path: String = output_dir.path_join(name + ".orfl")
	var logger: RefCounted = AirshipLog.new(session)
	var start_error: Error = logger.start({"field_path": FieldLoader.DEFAULT_PATH}, log_path)
	var started: bool = start_error == OK and bool(logger.recording)
	result["log_start_error"] = int(start_error)
	result["identity_at_log_start"] = str(session.collision_identity())
	_check(name + ": real recorder starts", started)
	if not started:
		session.free()
		return result

	var resumed: bool = session.resume(NEUTRAL)
	var first_tick: bool = session.tick_once(NEUTRAL) if resumed else false
	_check(name + ": first tick is accepted", resumed and first_tick and int(session.sim.tick) == 1)
	result["first_tick_crash"] = session.crash.duplicate(true)
	result["first_tick_fault"] = str(session.fault_reason)
	var previous_log: String = ""
	var next_logger: RefCounted = logger
	var mutation_accepted: bool = false
	var writer_open_after_mutation: bool = bool(logger.recording)

	if mode == "pre_record_world":
		_check(name + ": real pre-record world causes an obstacle crash", \
			str(session.crash.get("reason", "")).begins_with("Obstacle strike"))
	else:
		_check(name + ": first tick is clear without the scenery world", session.crash.is_empty() \
			and str(session.fault_reason).is_empty())
		session.pause("controlled pause for collision-world audit")
		var before_identity: String = str(session.collision_identity())
		var requested_world: Dictionary = world if mode == "change_while_recording" else {}
		mutation_accepted = session.set_collision_world(requested_world)
		writer_open_after_mutation = bool(logger.recording)
		var after_identity: String = str(session.collision_identity())
		result["identity_before_update"] = before_identity
		result["identity_after_update"] = after_identity
		result["update_accepted"] = mutation_accepted
		result["writer_open_after_update"] = writer_open_after_mutation
		result["resetting_signal_count"] = resets[0]
		if mode == "change_while_recording":
			# A changed collision owner must either be refused or end this file
			# before any later tick; starting a new file afterward is valid.
			var changed: bool = before_identity != after_identity
			_check(name + ": change is refused or closes the prior recording", \
				not mutation_accepted or not changed or not writer_open_after_mutation)
			if mutation_accepted and changed and not writer_open_after_mutation:
				previous_log = log_path
				log_path = output_dir.path_join(name + "-after-boundary.orfl")
				next_logger = AirshipLog.new(session)
				var restart_error: Error = next_logger.start({"field_path": FieldLoader.DEFAULT_PATH}, log_path)
				_check(name + ": a new file starts with the changed world", \
					restart_error == OK and bool(next_logger.recording))
		else:
			_check(name + ": unchanged world is accepted and keeps the writer", \
				mutation_accepted and before_identity == after_identity and writer_open_after_mutation)

		var second_resumed: bool = session.resume(NEUTRAL)
		var second_tick: bool = session.tick_once(NEUTRAL) if second_resumed else false
		_check(name + ": second tick is accepted", second_resumed and second_tick and int(session.sim.tick) == 2)
		if mode == "change_while_recording" and mutation_accepted:
			_check(name + ": changed stock world produces a real obstacle crash", \
				str(session.crash.get("reason", "")).begins_with("Obstacle strike"))
		else:
			_check(name + ": without an accepted changed world no crash occurs", session.crash.is_empty())

	result["final_tick"] = int(session.sim.tick)
	result["final_crash"] = session.crash.duplicate(true)
	result["final_fault"] = str(session.fault_reason)
	result["final_collision_identity"] = str(session.collision_identity())
	result["stop_error"] = int(next_logger.stop("end of controlled audit"))
	result["writer_recording_after_stop"] = bool(next_logger.recording)
	result["trace"] = _trace(log_path)
	if not previous_log.is_empty():
		result["previous_trace"] = _trace(previous_log)
		var previous_trace: Dictionary = result.previous_trace
		_check(name + ": prior file closes complete and verifies", \
			bool(previous_trace.get("complete", false)) and bool(previous_trace.get("verify", {}).get("ok", false)))
	var trace: Dictionary = result.trace
	var verification: Dictionary = trace.get("verify", {})
	_check(name + ": resulting file is complete and verifies exactly", \
		bool(trace.get("complete", false)) and bool(verification.get("ok", false)) \
		and bool(verification.get("exact", false)))
	_check(name + ": recording stream stops cleanly", not bool(next_logger.recording) \
		and int(result.stop_error) == OK)
	session.free()
	return result


func _run() -> void:
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		_check("fresh absolute --out directory supplied", false)
		_finish()
		return
	for name: String in ["unchanged-world.orfl", "pre-record-world.orfl", \
			"changed-world.orfl", "changed-world-after-boundary.orfl"]:
		if FileAccess.file_exists(output_dir.path_join(name)):
			_check("output files must not already exist", false)
			_finish()
			return
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_dir)
	_check("output directory is writable", mkdir_error == OK)
	if mkdir_error != OK:
		_finish()
		return

	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("stock field loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		observations["field_errors"] = loaded.get("errors", [])
		_finish()
		return
	var field: Dictionary = loaded.field
	var built: Dictionary = CollisionSetup.build(field)
	_check("stock field collision inventory builds", bool(built.get("ok", false)))
	if not bool(built.get("ok", false)):
		observations["world_errors"] = built.get("errors", [])
		_finish()
		return
	var world: Dictionary = built.world
	var pole: Dictionary = {}
	for proxy: Dictionary in world.proxies:
		if proxy.shape == "capsule" and float(proxy.radius) < 0.4 and float(proxy.half_length) > 1.0:
			pole = proxy
			break
	_check("stock tall thin pole from existing test is present", not pole.is_empty())
	if pole.is_empty():
		_finish()
		return
	var pilot: Dictionary = field.pilot
	var top: float = -(float(pole.down) - float(pole.half_length))
	var options: Dictionary = {
		"north_offset_m": float(pole.north) - float(pilot.north),
		"east_offset_m": float(pole.east) - float(pilot.east),
		"altitude_m": maxf(0.5, top * 0.5 - 0.5),
		"start": "air",
	}
	observations["fixture"] = {
		"scope": "public session and recorder API; current activity installs the world at startup",
		"source": "test_airship_session.gd:119-147",
		"pole_id": str(pole.get("id", "")), "pole_kind": str(pole.get("kind", "")),
		"stock_world_identity": str(world.get("identity", "")), "options": options,
	}
	observations["unchanged_world"] = _run_case("unchanged-world", field, options, world, "unchanged")
	observations["pre_record_world"] = _run_case("pre-record-world", field, options, world, "pre_record_world")
	observations["changed_world"] = _run_case("changed-world", field, options, world, "change_while_recording")
	_finish()
