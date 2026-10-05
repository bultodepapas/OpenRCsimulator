"""Detailed clearance report for the actual built Ugly Stik meshes.

Run from the repository root with:
  app/get-godot.sh --headless --path app --script ../research/ugly-stik/model-v3/verify_clearance.gd

The reusable checker is app/aircraft/model_clearance.gd. This research runner
enables detailed inside-both sampling and stores geometry provenance with the
report. It exits 1 when any unpermitted moving-part penetration is found.
"""
extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const ClearanceChecker := preload("res://aircraft/model_clearance.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane := AirplaneBuilder.build()
	root.add_child(airplane.root)
	var report: Dictionary = ClearanceChecker.new().run(airplane, true)
	report["geometry_source_sha256"] = _sha256("res://../assets/aircraft/ugly-stik-60/geometry.json")
	report["model_builder_sha256"] = _sha256("res://aircraft/ugly_stik_model.gd")
	report["clearance_checker_sha256"] = _sha256("res://aircraft/model_clearance.gd")
	var output_path := "/home/bulto/OpenRCsimulator/research/ugly-stik/model-v3/clearance-current.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	var absolute_output_path := ProjectSettings.globalize_path(output_path) if output_path.begins_with("res://") else output_path
	var output_directory := absolute_output_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		printerr("Could not create clearance report directory: %s" % output_directory)
		quit(1)
		return
	var file := FileAccess.open(absolute_output_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write clearance report: %s" % absolute_output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("clearance result: ok=%s; tail overlaps=%d; aileron overlaps=%d; failures=%d" % [report.ok, report.overlap_pair_pose_count, report.aileron_overlap_pair_pose_count, report.failures.size()])
	for failure in report.failures:
		printerr(failure)
	print("wrote %s" % absolute_output_path)
	airplane.root.queue_free()
	quit(0 if report.ok else 1)


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "unavailable"
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	file.close()
	return context.finish().hex_encode()
