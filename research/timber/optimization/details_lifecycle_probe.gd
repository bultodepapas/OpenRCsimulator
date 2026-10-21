extends SceneTree

const Timber := preload("res://aircraft/timber_model.gd")
const CANDIDATE_PATH := "res://aircraft/timber_visual_details.gd"

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mode := "candidate"
	var cycle_count := 8
	var output_path := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--cycles="):
			cycle_count = maxi(1, int(arg.trim_prefix("--cycles=")))
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")

	var counts_before_helper_load := _object_counts()
	var repo_root := ProjectSettings.globalize_path("res://project.godot").get_base_dir().get_base_dir()
	var baseline_path := repo_root.path_join("research/timber/optimization/details_baseline.gd")
	var helper: Script = null
	var helper_sha := ""
	if mode == "candidate" or mode == "candidate_loaded":
		helper = load(CANDIDATE_PATH) as Script
		helper_sha = FileAccess.get_sha256(CANDIDATE_PATH)
	elif mode == "baseline":
		var baseline := GDScript.new()
		baseline.source_code = FileAccess.get_file_as_string(baseline_path)
		var compile_error := baseline.reload()
		if compile_error != OK:
			_failures.append("baseline helper compile failed: %d" % compile_error)
		else:
			helper = baseline
			helper_sha = FileAccess.get_sha256(baseline_path)
	elif mode != "raw":
		_failures.append("unknown mode: " + mode)

	var report := {
		"schema": "openrc-timber-details-lifecycle-probe v1",
		"mode": mode,
		"cycles": cycle_count,
		"godot": Engine.get_version_info(),
		"renderer": DisplayServer.get_name(),
		"candidate_sha256": FileAccess.get_sha256(CANDIDATE_PATH),
		"baseline_sha256": FileAccess.get_sha256(baseline_path),
		"loaded_helper_sha256": helper_sha,
		"object_counts_before_helper_load": counts_before_helper_load,
		"object_counts_after_helper_load": _object_counts(),
		"object_counts_before": _object_counts(),
		"cycles_result": [],
		"failures": _failures,
	}
	if mode != "candidate_loaded":
		for cycle in cycle_count:
			var before := _object_counts()
			var build_started := Time.get_ticks_usec()
			var model: Dictionary = Timber.build()
			var build_usec := Time.get_ticks_usec() - build_started
			var model_root := model.get("root") as Node3D
			if model_root == null:
				_failures.append("Timber.build failed at cycle %d" % cycle)
				break
			root.add_child(model_root)
			var apply_usec := 0
			if helper != null and mode != "candidate_loaded":
				var apply_started := Time.get_ticks_usec()
				helper.call("apply", model_root)
				apply_usec = Time.get_ticks_usec() - apply_started
			await process_frame
			model.clear()
			model_root.queue_free()
			model_root = null
			await process_frame
			await process_frame
			var after := _object_counts()
			(report.cycles_result as Array).append({
				"cycle": cycle,
				"build_usec": build_usec,
				"apply_usec": apply_usec,
				"object_counts_before": before,
				"object_counts_after_teardown": after,
				"object_delta": _count_delta(before, after),
			})

	# Let local dictionaries and resource references fall out of scope before process exit.
	helper = null
	await process_frame
	report["object_counts_before_exit"] = _object_counts()
	report["failures"] = _failures
	var serialized := JSON.stringify(report, "\t") + "\n"
	if not output_path.is_empty():
		var absolute_output := output_path if output_path.is_absolute_path() else repo_root.path_join(output_path)
		DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
		var output := FileAccess.open(absolute_output, FileAccess.WRITE)
		if output == null:
			_failures.append("could not write report: " + absolute_output)
		else:
			output.store_string(serialized)
	print("LIFECYCLE_RESULT ", serialized.strip_edges())
	quit(1 if not _failures.is_empty() else 0)


func _object_counts() -> Dictionary:
	return {
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"static_memory_bytes": OS.get_static_memory_usage(),
	}


func _count_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta: Dictionary = {}
	for key: String in before:
		delta[key] = int(after.get(key, 0)) - int(before.get(key, 0))
	return delta
