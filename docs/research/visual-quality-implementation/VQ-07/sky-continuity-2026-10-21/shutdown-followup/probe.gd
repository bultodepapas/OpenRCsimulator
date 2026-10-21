extends SceneTree
var mode := "pause"
func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty(): mode = OS.get_cmdline_user_args()[0]
	_run.call_deferred()
func _run() -> void:
	var app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray(["--quick-flight", "--start=airborne", "--battery=ideal", "--date=2026-09-26", "--time=18:00", "--time_scale=20"])
	root.add_child(app)
	await create_timer(1.0).timeout
	if mode == "pause" or mode == "resume":
		app.open_pause()
		await process_frame
		if mode == "resume": app.continue_flight()
	elif mode == "camera": app.flight._rig.cycle(1)
	await create_timer(0.2).timeout
	print("shutdown probe: ", mode)
	quit()
