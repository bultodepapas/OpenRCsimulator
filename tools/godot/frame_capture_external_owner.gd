extends SceneTree
## Exercise the external capture-owner failure path with the real live Main node.

const MainScene := preload("res://main.gd")

var _signal_exit_code: int = -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := MainScene.new()
	main.name = "Main"
	main.interactive_start = true
	main.aircraft_id = "jensen-das-ugly-stik-60"
	main.frametimes_auto_quit = false
	main.frametimes_route = "external-owner-test"
	main.frame_time_report_written.connect(_on_report_written)
	root.add_child(main)
	if not main.startup_complete:
		await main.startup_finished
	if not main.startup_error.is_empty() or not main._frametimes_active:
		printerr("FAIL external owner: flight or collector did not start: ", main.startup_error)
		main.queue_free()
		quit(1)
		return
	for _frame in range(240):
		await process_frame
		if not main._frametimes_active:
			break
		var sample: Dictionary = main._frametime_samples.report()
		var endpoints: Dictionary = sample.get("sample_endpoints", {})
		var first: Dictionary = endpoints.get("first", {})
		var last: Dictionary = endpoints.get("last", {})
		if int(sample.frames) >= 2 and float(last.get("sim_tick", 0.0)) > float(first.get("sim_tick", 0.0)):
			break
	var sample: Dictionary = main._frametime_samples.report()
	var endpoints: Dictionary = sample.get("sample_endpoints", {})
	var first: Dictionary = endpoints.get("first", {})
	var last: Dictionary = endpoints.get("last", {})
	if not main._frametimes_active or int(sample.frames) < 2 or float(last.get("sim_tick", 0.0)) <= float(first.get("sim_tick", 0.0)):
		printerr("FAIL external owner: insufficient advancing samples before interruption")
		main.queue_free()
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--fixture-late-report"):
		var output_path := ""
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--frametimes="):
				output_path = argument.trim_prefix("--frametimes=")
		if output_path.is_empty() or FileAccess.file_exists(output_path):
			printerr("FAIL external owner: late report fixture needs a fresh destination")
			main.queue_free()
			quit(1)
			return
		var sentinel := FileAccess.open(output_path, FileAccess.WRITE)
		if sentinel == null:
			printerr("FAIL external owner: cannot create late report sentinel")
			main.queue_free()
			quit(1)
			return
		sentinel.store_string("late-created-sentinel\n")
		sentinel.close()
	main._finish_frame_time(1)
	if _signal_exit_code != 1 or main._frametimes_active:
		printerr("FAIL external owner: failure completion signal or ownership state is wrong")
		main.queue_free()
		quit(1)
		return
	# The external owner is still alive after the failure signal and performs cleanup.
	main.queue_free()
	await process_frame
	print("external owner interrupted the live stream and retained cleanup ownership")
	quit(0)


func _on_report_written(exit_code: int) -> void:
	_signal_exit_code = exit_code
