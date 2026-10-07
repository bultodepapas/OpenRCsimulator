# F6a: real command-line validation before field/flight or trace creation.
extends SceneTree

var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func run_app(args: PackedStringArray) -> Dictionary:
	var command: PackedStringArray = ["--headless", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "3", "--"]
	command.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), command, output, true)
	var message: String = "".join(output)
	check("no engine errors: %s" % [args], not "ERROR:" in message)
	return {code = code, output = message}


func _initialize() -> void:
	for args: PackedStringArray in [PackedStringArray(["--latency-patch"]), PackedStringArray(["--latency-patch", "--latency-axis=9", "--latency-threshold=0.5"])]:
		check("live marker route exits cleanly: %s" % [args], run_app(args).code == 0)
	for option: String in ["--latency-axis=10", "--latency-axis", "--latency-threshold=nan", "--latency-threshold=1", "--latency-patch=false", "--scripted", "--capture", "--frametimes=unused", "--visual_pose=unused"]:
		var result: Dictionary = run_app(["--latency-patch", option])
		check("refuses invalid or conflicting flag: " + option, result.code != 0 and "Use --latency-patch" in result.output)
	check("axis without marker fails", run_app(["--latency-axis=0"]).code != 0)
	var path: String = "user://test_latency_patch_trace.csv"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("preserve this evidence")
	file.close()
	check("trace combination fails before opening output", run_app(["--latency-patch", "--trace=" + path]).code != 0 and FileAccess.get_file_as_string(path) == "preserve this evidence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("F6a CLI: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
