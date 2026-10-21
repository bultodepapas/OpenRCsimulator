extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for mode in ["normal", "pause", "resume", "camera"]:
		var app = load("res://app_root.tscn").instantiate()
		app.user_args = PackedStringArray(["--quick-flight", "--start=airborne", "--battery=ideal", "--date=2026-09-26", "--time=18:00", "--time_scale=20"])
		root.add_child(app)
		await process_frame
		if mode in ["pause", "resume"]:
			app.open_pause()
			await process_frame
			if mode == "resume": app.continue_flight()
		elif mode == "camera": app.flight._rig.cycle(1)
		await process_frame
		app.free()
		await process_frame
		await process_frame
		print("lifecycle ", mode, " orphan_count=", Node.get_orphan_node_ids().size())
		Node.print_orphan_nodes()
	print("lifecycle probe complete")
	quit()
