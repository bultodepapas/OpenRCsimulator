## Synthetic export-only memory witness; run through tools/godot/run_checked.py.
## No flight simulation, rendering or physical-validation claim.
extends SceneTree

func _initialize() -> void:
	var source := "res://sim/trace.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace-source="):
			source = argument.trim_prefix("--trace-source=")
	var script: Script = load(source)
	var trace: RefCounted = script.new()
	trace.meta = {scenario = "memory-export-witness", dt_s = 1.0 / 240.0}
	var state := PackedFloat64Array([10, -20, -30, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0.125, -0.25, 0, 0.75])
	for tick in 120001:
		trace.record(tick, tick / 240.0, state, loads, inputs)
	var path := "user://test-traces/export-witness-%d.csv" % OS.get_process_id()
	var before := OS.get_static_memory_usage()
	var peak_before := OS.get_static_memory_peak_usage()
	var started := Time.get_ticks_usec()
	var error: Error = trace.save(path)
	var elapsed := Time.get_ticks_usec() - started
	# Read counters before hashing: file-hash buffers are outside this measurement.
	var after := OS.get_static_memory_usage()
	var peak := OS.get_static_memory_peak_usage()
	var result := {rows = trace.row_count(), error = error, export_usec = elapsed,
		static_before_bytes = before, static_after_bytes = after, static_process_peak_bytes = peak,
		static_process_peak_before_bytes = peak_before, source_sha256 = FileAccess.get_sha256(source),
		csv_sha256 = FileAccess.get_sha256(path), engine = Engine.get_version_info().string}
	print(JSON.stringify(result))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("TRACE_EXPORT_PROBE_COMPLETE")
	quit(0 if error == OK and trace.row_count() == 120001 else 1)
