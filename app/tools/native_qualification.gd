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
const FIXED_WING_MODES := ["session", "stage", "lifecycle", "replay"]

var _harness: Object
var _mode := ""
var _backend := ""
var _output := ""
var _mac_identity := {}
var _experimental_native_macos := false


## Called once after this host is added to the real application's tree.
func start(args: PackedStringArray) -> void:
	var parsed := _parse_options(args, OS.get_name())
	if not parsed.ok:
		_fail(parsed.error)
		return
	_mode = parsed.mode
	_backend = parsed.backend
	_output = parsed.output
	_experimental_native_macos = parsed.experimental_native_macos
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
	if _mode in ["stage", "lifecycle", "replay"]:
		if not _harness.has_method("set_experimental_native_macos"):
			_fail("fixed diagnostic cannot receive Mac native admission")
			return
		_harness.call("set_experimental_native_macos", _experimental_native_macos)
	# Each existing harness schedules its synchronous run via call_deferred.
	# Schedule our finish afterward, and quit the application's tree, not the
	# detached SceneTree object created by the original test harness.
	_harness.call("_initialize")
	call_deferred("_finish")


## Parse without loading a diagnostic, touching the native class or changing session state.
static func _parse_options(args: PackedStringArray, os_name: String) -> Dictionary:
	var options := {}
	for arg: String in args:
		if arg == "--quick-flight":
			if options.has("quick-flight"):
				return {ok = false, error = "duplicate --quick-flight"}
			options["quick-flight"] = true
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if not arg.begins_with("--") or pair.size() != 2 or pair[1].is_empty() or options.has(pair[0]):
			return {ok = false, error = "expected unique --name=value options"}
		options[pair[0]] = pair[1]
	var mode := str(options.get("native-qualification", ""))
	if not SCRIPTS.has(mode):
		return {ok = false, error = "native-qualification must be session, stage, lifecycle, replay, helicopter or helicopter-radio"}
	if os_name == "macOS" and mode not in FIXED_WING_MODES:
		return {ok = false, error = "Mac native qualification does not support helicopter modes"}
	for key: String in options:
		if key in ["quick-flight", "native-qualification"]: continue
		if key == "experimental-native-macos" and mode in FIXED_WING_MODES: continue
		if mode == "session" and key in SESSION_OPTIONS: continue
		return {ok = false, error = "unexpected option: " + key}
	var mac_option := str(options.get("experimental-native-macos", "false"))
	if mac_option not in ["true", "false"]:
		return {ok = false, error = "experimental-native-macos must be true or false"}
	var backend := str(options.get("physics-backend", ""))
	var output := str(options.get("output", ""))
	if mode == "session" and (backend not in ["gdscript_reference", "native"] or output.is_empty()):
		return {ok = false, error = "session requires --physics-backend and a new --output"}
	return {ok = true, mode = mode, backend = backend, output = output, experimental_native_macos = mac_option == "true"}


func _script_path(mode: String) -> String:
	var filename: String = SCRIPTS[mode]
	if OS.has_feature("template_release"):
		if OS.get_name() == "macOS":
			var reference_only := mode == "session" and _backend == "gdscript_reference"
			if not reference_only and not _experimental_native_macos:
				_fail("Mac native qualification requires explicit experimental opt-in")
				return ""
			var mac: Dictionary = NativePackage.mac_reference_identity(OS.get_executable_path(),
				Engine.get_architecture_name(), OS.get_cmdline_args()) if reference_only else \
				NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(), OS.get_cmdline_args())
			var probe := PACKAGE_DIR.path_join(filename)
			var expected: String = str(mac.get("probe_sha256", "")) if reference_only else \
				str(mac.get("manifest", {}).get("qualification_sources", {}).get(filename, ""))
			if not mac.get("ok", false) or not FileAccess.file_exists(probe) \
					or FileAccess.get_sha256(probe) != expected:
				_fail("Mac package or its fixed diagnostic differs from the receipt")
				return ""
			_mac_identity = mac
			return probe
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
		if not _mac_identity.is_empty() and (report_value.get("solver_identity_kind") != _mac_identity.kind \
				or report_value.get("solver_sha256") != _mac_identity.sha256):
			_fail("Mac session did not report the selected bundle identity")
			return
	else:
		if int(_harness.get("checks")) < 1 or int(_harness.get("failures")) != 0 \
				or _harness.get("_native_exercised") != true:
			_fail("diagnostic failed or did not exercise the native backend")
			return
	if not _mac_identity.is_empty():
		var final_mac := NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(), OS.get_cmdline_args()) \
			if _mac_identity.kind == NativePackage.MAC_NATIVE_IDENTITY_KIND else \
			NativePackage.mac_reference_identity(OS.get_executable_path(), Engine.get_architecture_name(), OS.get_cmdline_args())
		if final_mac != _mac_identity:
			_fail("Mac bundle changed during qualification")
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
