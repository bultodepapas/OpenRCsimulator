# UI-06: the real direct route defaults Quick Flight to runway, with explicit airborne alternatives.
extends SceneTree
const OUTPUT := "user://test_runway_cli.csv"
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func run_flight(options: PackedStringArray) -> Dictionary:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT))
	var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--audio-driver", "Dummy", "--"]
	args.append_array(options)
	args.append_array(PackedStringArray(["--trace=" + OUTPUT, "--t=0.01", "--soundscape=off"]))
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	check("no engine errors: " + str(options), not "ERROR:" in "".join(output))
	return {code = code, text = FileAccess.get_file_as_string(OUTPUT) if FileAccess.file_exists(OUTPUT) else ""}

func _initialize() -> void:
	var runway := run_flight(["--quick-flight"])
	check("Quick Flight defaults to runway", runway.code == 0 and runway.text.contains("# launch_choice: runway\n"))
	var airborne := run_flight(["--quick-flight", "--start=airborne"])
	check("explicit airborne overrides Quick Flight", airborne.code == 0 and airborne.text.contains("# launch_choice: airborne\n"))
	var technical := run_flight([])
	check("technical reference trace keeps its airborne fixture", technical.code == 0 and technical.text.contains("# launch_choice: airborne\n"))
	var half := run_flight(["--quick-flight", "--start=airborne_half_power"])
	check("explicit half-power operating point remains available", half.code == 0 and half.text.contains("# selected_start_choice: airborne_half_power\n"))
	var invalid := run_flight(["--quick-flight", "--start=bogus"])
	check("invalid start fails without writing a flight", invalid.code != 0 and invalid.text.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT))
	print("Runway CLI: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
