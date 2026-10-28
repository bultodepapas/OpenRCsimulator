## NK-3: run the existing fixed diagnostics inside the actual release executable.
## This host never accepts a script path and never bypasses native admission.
extends Node

const NativePackage := preload("res://app_state/native_package.gd")
const PACKAGE_DIR := "res://native/kernel/qualification"
const SCRIPTS := {
	"session": "session_probe.gd",
	"stage": "test_native_stage.gd",
	"lifecycle": "test_native_session.gd",
	"replay": "test_native_replay.gd",
	"helicopter": "test_native_helicopter_session.gd",
	"helicopter-radio": "test_heli_restore_radio.gd",
}
const SESSION_OPTIONS := ["output", "aircraft", "case", "warmup-ticks", "sample-ticks", "observer", "physics-backend"]

var _harness: Object
var _mode := ""
var _backend := ""
var _output := ""


## Called once after this host is added to the real application's tree.
func start(args: PackedStringArray) -> void:
	var options := {}
	for arg: String in args:
		if arg == "--quick-flight":
			if options.has("quick-flight"):
				_fail("duplicate --quick-flight")
				return
			options["quick-flight"] = true
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if not arg.begins_with("--") or pair.size() != 2 or pair[1].is_empty() or options.has(pair[0]):
			_fail("expected unique --name=value options")
			return
		options[pair[0]] = pair[1]
	_mode = str(options.get("native-qualification", ""))
	if not SCRIPTS.has(_mode):
		_fail("native-qualification must be session, stage, lifecycle, replay, helicopter or helicopter-radio")
		return
	for key: String in options:
		if key not in ["quick-flight", "native-qualification"] and (_mode != "session" or key not in SESSION_OPTIONS):
			_fail("unexpected option: " + key)
			return
	if _mode == "session":
		_backend = str(options.get("physics-backend", ""))
		_output = str(options.get("output", ""))
		if _backend not in ["gdscript_reference", "native"] or _output.is_empty():
			_fail("session requires --physics-backend and a new --output")
			return
	if ClassDB.class_exists("OpenRCNativeKernel"):
		_fail("native class was initialized before admission")
		return
	print("NATIVE_QUALIFICATION preloaded=false")
	var path := _script_path(_mode)
	if path.is_empty():
		return # _script_path already refused the package or source.
	var script: Script = load(path)
	if script == null or not script.can_instantiate():
		_fail("cannot load the fixed diagnostic: " + path)
		return
	_harness = script.new()
	if _harness == null or not _harness.has_method("_initialize"):
		_fail("fixed diagnostic cannot initialize")
		return
	# Each existing harness schedules its synchronous run via call_deferred.
	# Schedule our finish afterward, and quit the application's tree, not the
	# detached SceneTree object created by the original test harness.
	_harness.call("_initialize")
	call_deferred("_finish")


func _script_path(mode: String) -> String:
	var filename: String = SCRIPTS[mode]
	if OS.has_feature("template_release"):
		var package: Dictionary = NativePackage.identity()
		if not package.get("ok", false):
			_fail("package identity refused: " + str(package.get("reason", "unknown")))
			return ""
		var sources: Dictionary = package.manifest.qualification_sources
		var digest: Variant = sources.get(filename)
		var path := PACKAGE_DIR.path_join(filename)
		if typeof(digest) != TYPE_STRING or digest.length() != 64 or not digest.is_valid_hex_number() \
				or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != digest:
			_fail("fixed packaged diagnostic differs from its manifest: " + filename)
			return ""
		return path
	# These source paths are fixed: caller arguments never select a script.
	if mode == "session":
		return ProjectSettings.globalize_path("res://../research/performance/session_probe.gd").simplify_path()
	return "res://tests/" + filename


func _finish() -> void:
	if _harness == null:
		_fail("diagnostic did not start")
		return
	if _harness.get("_finished") != true:
		_fail("diagnostic did not complete")
		return
	if _mode == "session":
		var failure := str(_harness.get("_failure"))
		var report_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(_output)) if FileAccess.file_exists(_output) else null
		if not failure.is_empty() or not report_value is Dictionary or report_value.get("complete") != true \
				or not report_value.get("backend") is Dictionary \
				or report_value.backend.get("requested") != _backend \
				or not report_value.backend.get("actual") is Dictionary \
				or report_value.backend.actual.get("backend") != _backend:
			_fail("session probe failed or the requested backend was not installed: " + failure)
			return
	else:
		if int(_harness.get("checks")) < 1 or int(_harness.get("failures")) != 0 \
				or _harness.get("_native_exercised") != true:
			_fail("diagnostic failed or did not exercise the native backend")
			return
	print("NATIVE_QUALIFICATION mode=%s verdict=pass" % _mode)
	_harness.free()
	_harness = null
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("NATIVE_QUALIFICATION mode=%s verdict=fail: %s" % [_mode, reason])
	if _harness != null:
		_harness.free()
		_harness = null
	get_tree().quit(1)
