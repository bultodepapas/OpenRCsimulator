# F1: standalone diagnostic route. It never creates a flight or applies/saves calibration.
extends Node

const ReportData = preload("res://input/input_report_data.gd")
const BuildInfo = preload("res://app_state/build_info.gd")
const FORMAT: String = "openrc-input-report v1"
const DEFAULT_DURATION: float = 10.0
const MAX_DURATION: float = 3600.0

var duration_s: float = DEFAULT_DURATION
var output_path: String = ""
var quit_on_finish: bool = true
var report: Dictionary = {}
var data: ReportData = ReportData.new()
var clock_usec: Callable = func() -> int: return Time.get_ticks_usec()
var connected_devices: Callable = func() -> Array[int]: return Input.get_connected_joypads()
var device_info: Callable = func(id: int) -> Dictionary:
	var info: Dictionary = Input.get_joy_info(id)
	return {guid = Input.get_joy_guid(id), name = Input.get_joy_name(id), raw_name = info.get("raw_name"),
		vendor_id = info.get("vendor_id"), product_id = info.get("product_id"), known = Input.is_joy_known(id)}
var _start_usec: int = 0
var _old_accumulated: bool = true
var _running: bool = false
var _exit_code: int = OK


static func requested(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg == "--input-report" or arg.begins_with("--input-report="):
			return true
	return false


static func options(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {ok = false, error = "Use --input-report[=path.json] [--t=seconds]; no flight options. Duration must be > 0 and <= 3600 s.",
		duration_s = DEFAULT_DURATION, path = ""}
	var seen: Dictionary = {}
	for arg: String in args:
		var key: String = arg.get_slice("=", 0)
		if seen.has(key) or key not in ["--input-report", "--t"]:
			return out
		seen[key] = true
		if key == "--input-report":
			if arg != key:
				out.path = arg.substr(key.length() + 1)
				if out.path.strip_edges().is_empty():
					return out
		else:
			var value: String = arg.trim_prefix("--t=")
			if not value.is_valid_float():
				return out
			out.duration_s = value.to_float()
	if not seen.has("--input-report") or not is_finite(out.duration_s) or out.duration_s <= 0.0 \
		or out.duration_s > MAX_DURATION or roundf(out.duration_s * 1e6) < 1.0:
		return out
	out.ok = true
	out.error = ""
	return out


func _ready() -> void:
	name = "InputReport"
	_old_accumulated = Input.use_accumulated_input
	Input.use_accumulated_input = false
	_start_usec = clock_usec.call()
	_running = true
	Input.joy_connection_changed.connect(_connection_changed)
	for id: int in connected_devices.call():
		_connection_changed(id, true)
	printerr("Input report: move every stick through its full range for %.2f seconds. Event spacing is observed by Godot, not USB report timing. JSON: %s" % [duration_s, output_path if output_path != "" else "stdout"])


func _connection_changed(id: int, connected: bool) -> void:
	if not _running:
		return
	var elapsed: int = int(clock_usec.call()) - _start_usec
	if connected:
		data.connect_device(id, device_info.call(id), elapsed)
	else:
		data.disconnect_device(id, elapsed)


func _input(event: InputEvent) -> void:
	if _running and event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		data.motion(motion.device, motion.axis, motion.axis_value, int(clock_usec.call()) - _start_usec)


func _process(_delta: float) -> void:
	if _running and float(int(clock_usec.call()) - _start_usec) / 1e6 >= duration_s:
		finish()


func finish() -> int:
	if not _running:
		return _exit_code
	_running = false
	set_process(false)
	set_process_input(false)
	report = {format = FORMAT, complete = true, requested_duration_s = duration_s,
		observed_duration_s = float(int(clock_usec.call()) - _start_usec) / 1e6,
		os = OS.get_name(), os_version = OS.get_version(), godot = Engine.get_version_info().string, build = BuildInfo.current(),
		use_accumulated_input = false, ignore_joypad_on_unfocused_application = Input.ignore_joypad_on_unfocused_application,
		timing = "Monotonic callback arrival times per axis; includes zero-spacing batched events. Not USB report interval or end-to-end latency.",
		axis_semantics = "Godot axes after any engine mapping; unseen axes are unknown, not zero or absent.",
		devices = data.snapshot(), rejected_events = data.rejected_events}
	var encoded: String = JSON.stringify(report, "\t") + "\n"
	if output_path != "":
		var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			_exit_code = FileAccess.get_open_error()
		else:
			if not file.store_string(encoded):
				_exit_code = ERR_FILE_CANT_WRITE
			file.flush()
			if file.get_error() != OK:
				_exit_code = file.get_error()
			file.close()
	else:
		print(encoded)
	if _exit_code != OK:
		printerr("Input report could not be written: %s (error %d)" % [output_path, _exit_code])
	_restore_input()
	if quit_on_finish:
		get_tree().quit(_exit_code)
	return _exit_code


func _restore_input() -> void:
	if Input.joy_connection_changed.is_connected(_connection_changed):
		Input.joy_connection_changed.disconnect(_connection_changed)
	Input.use_accumulated_input = _old_accumulated


func _exit_tree() -> void:
	if _running:
		_running = false
		_restore_input()
