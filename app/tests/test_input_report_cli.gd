# F1 process contract: output, finite duration, errors and conflicting modes. No hardware required.
extends SceneTree

const PATH: String = "user://test_input_report_cli.json"
var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func run_report(args: PackedStringArray) -> Dictionary:
	var command: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"]
	command.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), command, output, true)
	var message: String = "".join(output)
	check("no engine errors: %s" % [args], not "ERROR:" in message)
	return {code = code, output = message}


func _initialize() -> void:
	var result: Dictionary = run_report(["--input-report=" + PATH, "--t=0.01"])
	check("file mode exits successfully", result.code == 0)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check("file is complete versioned JSON", report is Dictionary and report.format == "openrc-input-report v1" and report.complete and report.devices is Array)
	check("duration is real, positive and bounded", report.requested_duration_s == 0.01 and report.observed_duration_s >= 0.01 and report.observed_duration_s < 10.0)
	var stdout_result: Dictionary = run_report(["--input-report", "--t=0.01"])
	check("bare mode prints JSON", stdout_result.code == 0 and '"format": "openrc-input-report v1"' in stdout_result.output and '"complete": true' in stdout_result.output)
	var before: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	for option: String in ["--t=0", "--t=-1", "--t=nan", "--t=inf", "--t=1e309", "--t=3601", "--t", "--trace=unused", "--capture", "--quick-flight"]:
		var invalid: Dictionary = run_report(["--input-report=" + PATH, option])
		check("invalid CLI fails: " + option, invalid.code != 0)
	check("invalid CLI preserves previous report", FileAccess.get_file_as_bytes(PATH) == before)
	var bad_path: Dictionary = run_report(["--input-report=" + ProjectSettings.globalize_path("user://"), "--t=0.001"])
	check("directory output fails clearly", bad_path.code != 0 and "could not be written" in bad_path.output)
	if OS.get_name() == "Linux":
		var full_disk: Dictionary = run_report(["--input-report=/dev/full", "--t=0.001"])
		check("write/flush failure exits nonzero", full_disk.code != 0 and "could not be written" in full_disk.output)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("F1 CLI: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
