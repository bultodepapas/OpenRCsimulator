extends SceneTree

const Writer := preload("res://tools/flight_log_cli.gd")

var failures: int = 0


func _initialize() -> void:
	var output_dir: String = ProjectSettings.globalize_path("res://../tmp/flight-log-report-writer-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path: String = output_dir.path_join("report.json")
	var encoded: String = JSON.stringify({status = "ok", rows = 1}, "\t", true, true) + "\n"
	var write_error: Error = Writer.write_report_file(output_path, encoded)
	_check("regular report write succeeds", write_error == OK)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(output_path))
	_check("regular report is complete JSON", report is Dictionary and report.get("status") == "ok" and report.get("rows") == 1)
	_check("directory destination reports open failure", Writer.write_report_file(output_dir, encoded) != OK)
	if OS.get_name() == "Linux" and FileAccess.file_exists("/dev/full"):
		_check("full device reports short-write failure", Writer.write_report_file("/dev/full", encoded) != OK)
	var blocker_path: String = output_dir.path_join("blocker")
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	_check("CLI failure fixture blocker created", blocker != null)
	if blocker != null:
		blocker.store_string("parent path is a file")
		blocker.close()
		var cli_output: Array = []
		var arguments := PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", output_dir.path_join("cli-engine.log"),
			"--script", "res://tools/flight_log_cli.gd", "--",
			"--log=" + output_dir.path_join("missing.orfl"),
			"--csv=" + output_dir.path_join("cli.csv"),
			"--report=" + blocker_path.path_join("report.json")
		])
		var cli_exit: int = OS.execute(OS.get_executable_path(), arguments, cli_output, true)
		var cli_text := ""
		for line: Variant in cli_output:
			cli_text += str(line) + "\n"
		_check("CLI exits nonzero when its report cannot be written", cli_exit != 0)
		_check("CLI reports the report-write failure", "Cannot write report" in cli_text)
		_check("CLI suppresses success output after report failure", not "rows verified." in cli_text)
		# Exercise the successful-analysis branch independently of flight generation:
		# only the final report destination fails. The subclass is a disposable fixture.
		var probe_path: String = output_dir.path_join("finish_probe.gd")
		var probe := FileAccess.open(probe_path, FileAccess.WRITE)
		_check("finish fixture created", probe != null)
		if probe != null:
			probe.store_string("extends \"res://tools/flight_log_cli.gd\"\nfunc _initialize():\n\toptions = {report = OS.get_cmdline_user_args()[0]}\n\treport = {mode = \"export\", rows = 1}\n\t_finish(\"\")\n")
			probe.close()
			cli_output.clear()
			cli_exit = OS.execute(OS.get_executable_path(), PackedStringArray([
				"--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--log-file", output_dir.path_join("finish-engine.log"),
				"--script", probe_path, "--", blocker_path.path_join("report.json")
			]), cli_output, true)
			cli_text = ""
			for line: Variant in cli_output:
				cli_text += str(line) + "\n"
			_check("successful analysis becomes exit 1 on report failure", cli_exit == 1)
			_check("successful analysis identifies report failure", "Cannot write report" in cli_text)
			_check("successful analysis cannot announce success after report failure", not "rows verified." in cli_text)
		DirAccess.remove_absolute(probe_path)
		DirAccess.remove_absolute(output_dir.path_join("finish-engine.log"))
	DirAccess.remove_absolute(output_path)
	# An empty candidate must fail before inspecting a log or selecting a backend.
	# A nonempty path reaches log inspection instead, preserving candidate mode.
	for candidate: String in ["", output_dir.path_join("candidate.json")]:
		var stem: String = "empty-candidate" if candidate.is_empty() else "candidate-path"
		var candidate_report: String = output_dir.path_join(stem + ".json")
		var candidate_csv: String = output_dir.path_join(stem + ".csv")
		var candidate_output: Array = []
		var candidate_exit: int = OS.execute(OS.get_executable_path(), PackedStringArray([
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--log-file", output_dir.path_join(stem + "-engine.log"),
			"--script", "res://tools/flight_log_cli.gd", "--",
			"--log=" + output_dir.path_join("missing.orfl"), "--csv=" + candidate_csv,
			"--report=" + candidate_report, "--replay", "--candidate=" + candidate
		]), candidate_output, true)
		var candidate_result: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_report))
		_check(stem + " exits nonzero", candidate_exit != 0)
		_check(stem + " cannot create replay CSV", not FileAccess.file_exists(candidate_csv))
		_check(stem + " reports refusal", candidate_result is Dictionary and candidate_result.get("status") == "error")
		if candidate_result is Dictionary:
			var expected_error: String = "--candidate requires --replay and a JSON path." if candidate.is_empty() else "Cannot open flight log."
			_check(stem + " distinguishes candidate validation from log inspection",
				str(candidate_result.get("error", "")) == expected_error)
		DirAccess.remove_absolute(candidate_report)
		DirAccess.remove_absolute(output_dir.path_join(stem + "-engine.log"))
	DirAccess.remove_absolute(blocker_path)
	DirAccess.remove_absolute(output_dir.path_join("cli-engine.log"))
	DirAccess.remove_absolute(output_dir)
	print("flight-log report writer: %d failures" % failures)
	quit(1 if failures else 0)


func _check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL " + label)
