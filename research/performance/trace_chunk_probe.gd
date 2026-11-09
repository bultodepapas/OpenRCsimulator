## Controlled raw-storage witness, not real-time scheduling or frame qualification.
extends SceneTree

func _initialize() -> void:
	var source := "res://sim/trace.gd"
	var chunks := false
	var parent := "user://trace-chunk-witness/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for arg in OS.get_cmdline_user_args():
		if arg == "--chunks": chunks = true
		elif arg.begins_with("--trace-source="): source = arg.trim_prefix("--trace-source=")
	var script: Script = load(source)
	var trace: RefCounted = script.new()
	trace.meta = {scenario = "memory-export-witness", dt_s = 1.0 / 240.0}
	if chunks: trace.enable_chunk_storage(parent)
	var body := PackedFloat64Array([10, -20, -30, 15, 0, 0, 1, 0, 0, 0, 0, 0, 0])
	var loads := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var inputs := PackedFloat64Array([0.125, -0.25, 0, 0.75])
	var initial := OS.get_static_memory_usage()
	var peak_raw := 0
	var error: Error = OK
	for tick in 120001:
		trace.record(tick, tick / 240.0, body, loads, inputs)
		if chunks:
			error = trace.storage_error()
			if error != OK: break
			var store: RefCounted = trace._chunk_store
			peak_raw = maxi(peak_raw, trace._rows.size() * 8 + (store.buffered_bytes() if store != null else 0))
			# This synthetic producer runs faster than real time. Drain at fixed batch
			# boundaries to measure storage, not manufacture scheduler/backpressure failures.
			if tick % 1024 == 0 and store != null:
				error = store.drain()
				if error != OK: break
	var retained := OS.get_static_memory_usage()
	if not chunks: peak_raw = trace._rows.size() * 8
	var output := parent.path_join("witness.csv")
	if error == OK: error = trace.save(output)
	var peak := OS.get_static_memory_peak_usage()
	var result := {rows = trace.row_count(), chunks = chunks, error = error,
		static_initial_bytes = initial, static_recorded_bytes = retained,
		static_process_peak_bytes = peak, peak_sampled_retained_raw_bytes = peak_raw,
		source_sha256 = FileAccess.get_sha256(source), csv_sha256 = FileAccess.get_sha256(output),
		engine = Engine.get_version_info().string, pacing = "forced drain every 1024 synthetic rows"}
	print(JSON.stringify(result))
	var valid: bool = error == OK and trace.row_count() == 120001 and (not chunks or peak_raw <= 4 * 1024 * 1024)
	trace.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(parent))
	print("TRACE_CHUNK_PROBE_COMPLETE")
	quit(0 if valid else 1)
