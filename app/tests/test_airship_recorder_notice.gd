## A36 G3: an automatic end of the blimp black box (write failure, recording limit, reset) reaches the pilot during
## flight through the real activity: the recorder emits `ended` once, the activity flashes its note and keeps the
## reason on the HUD log line until the next F10; a failed file keeps an inspectable, incomplete prefix.
extends SceneTree

const Activity := preload("res://vehicles/airship/airship_scene.gd")
const Session := preload("res://sim/airship/session.gd")
const AirshipLog := preload("res://sim/airship/flight_log.gd")

class TestActivity extends Activity:
	func _ready() -> void:
		set_physics_process(false)
		set_process(false)

class TestHud extends CanvasLayer:
	var flashes: Array[String] = []
	func flash(message: String) -> void: flashes.append(message)
	func show_menu(_reason: String, _can_resume: bool) -> void: pass
	func hide_menu() -> void: pass

var checks := 0
var failures := 0


func check(label: String, ok: bool, detail: Variant = "") -> void:
	checks += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, str(detail)])
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _fly(activity: Node, ticks: int) -> bool:
	for i in ticks:
		if not activity.session.tick_once(PackedFloat64Array([0.0, 0.0, 0.0, 0.3])):
			return false
	return true


func _run() -> void:
	var activity := TestActivity.new()
	root.add_child(activity)
	activity.session = Session.new()
	root.add_child(activity.session)
	activity.hud = TestHud.new()
	root.add_child(activity.hud)
	activity.field_path = ""
	check("real airship session prepares and resumes", activity.session.prepare({}, {}) and activity.session.resume())
	var ends: Array = []
	# 1. A write failure mid-flight (injected as a nonconsecutive tick, a real recorder failure path).
	activity.toggle_recording()
	var first: RefCounted = activity.flight_log
	first.ended.connect(func(reason: String, failed: bool) -> void: ends.append([reason, failed]))
	check("F10 starts recording and the HUD line shows it", first.recording and activity.log_line().begins_with("Log REC"),
		activity.log_line())
	check("recording flies 300 ticks", _fly(activity, 300))
	var path: String = first.path
	var written: int = first.rows_written
	var before_flashes: int = activity.hud.flashes.size()
	first._ticked(activity.session.sim.tick + 5, 0.0)
	check("the failure ends the recording once and is marked failed", not first.recording and ends.size() == 1
		and bool(ends[0][1]) and str(ends[0][0]).contains("nonconsecutive"), ends)
	check("the pilot is told while flying, without another F10", activity.hud.flashes.size() == before_flashes + 1
		and activity.hud.flashes[-1] == first.note and activity.log_status.begins_with("Log FAILED:"), activity.log_status)
	check("the failure stays on the HUD log line", activity.log_line() == activity.log_status, activity.log_line())
	check("flight continues after a recorder failure", _fly(activity, 10) and activity.session.fault_reason.is_empty())
	check("the reason is still shown after further flight", activity.log_line().begins_with("Log FAILED:"))
	var prefix: Dictionary = AirshipLog.inspect(path)
	check("the failed file keeps an inspectable incomplete prefix", prefix.ok and not prefix.complete
		and prefix.ticks.size() == written and written >= 240 and str(prefix.get("error", "")).contains("incomplete"),
		[prefix.get("error", ""), prefix.ticks.size(), written])
	# 2. The automatic recording limit.
	activity.toggle_recording()
	var second: RefCounted = activity.flight_log
	check("a new F10 replaces the failed status with a new recording", second != first and second.recording
		and activity.log_line().begins_with("Log REC"))
	check("one tick of flight is recorded", _fly(activity, 1))
	second._start_tick = activity.session.sim.tick + 1 - AirshipLog.MAX_TICKS
	check("the limit tick is accepted", _fly(activity, 1))
	check("the recording limit is shown while flying", not second.recording
		and activity.log_status == "Log stopped: recording limit reached"
		and activity.hud.flashes[-1].begins_with("Flight log saved:"), activity.log_status)
	var limited: Dictionary = AirshipLog.inspect(second.path)
	check("the limit closes a complete file", limited.ok and limited.complete)
	# 3. A reset while recording.
	activity.toggle_recording()
	var third: RefCounted = activity.flight_log
	check("third recording runs", third.recording and _fly(activity, 5))
	check("session reset succeeds", activity.session.reset())
	check("the reset end is shown", not third.recording
		and activity.log_status == "Log stopped: session reset or configuration change", activity.log_status)
	for value: String in [first.path, second.path, third.path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(value))
	activity.session.free()
	activity.session = null
	activity.hud.free()
	activity.hud = null
	activity.free()
	print("airship recorder notice: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
