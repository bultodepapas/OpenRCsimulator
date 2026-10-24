extends SceneTree
## F4U-17: the wing fold on the production flight scene. Refused in the air; on the runway, stopped, the O-key action
## folds both panels over the estimated cycle while the session holds the throttle at idle even with full throttle
## commanded; spreading releases it. Writes checks.json and screenshots to a new directory.
## Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --resolution 1920x1080 --path app \
##   --script <repo>/research/f4u-corsair/F4U-17/fold_check.gd -- --aircraft=f4u-corsair-250 --out=<new dir>
const MainScene := preload("res://main.tscn")
var main: Node
var session: Node
var out := ""
var checks := []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		printerr("F4U-17 fold: pass --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = MainScene.instantiate()
	var args := OS.get_cmdline_user_args()
	args.append("--start=airborne")
	main.set_user_args(args)
	main.crash_effects_enabled = false
	root.add_child(main)
	call_deferred("_run")


func _check(label: String, ok: bool, detail := "") -> void:
	checks.append({ label = label, ok = ok, detail = detail })
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait_until(condition: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame
	return condition.call()


func _run() -> void:
	for i in 20:
		await process_frame
	session = main.session
	session.radio.disconnect_device()
	main._inspect = true
	_check("the Corsair binds two wing folds", main._airplane.get("folds", {}).size() == 2)
	main._toggle_wing_fold()
	_check("folding is refused in the air", main._wing_fold_target == 0.0 and str(main._note).contains("ground"), str(main._note))

	session.start_choice = session.START_RUNWAY
	session.reset()
	for i in 30:
		await process_frame
	_check("runway start: on the wheels and stopped", main._stopped_on_wheels())
	main._toggle_wing_fold()
	session.commands.throttle = 1.0
	var t0 := Time.get_ticks_msec()
	await create_timer(1.0).timeout
	_check("full throttle commanded while folding reaches the solver as idle", session.commands.throttle == 1.0 and session.sim.inputs[3] == 0.0,
		"command %.2f, solver %.2f" % [session.commands.throttle, session.sim.inputs[3]])
	var folded := await _wait_until(func() -> bool: return main._wing_fold >= 1.0, 15.0)
	var fold: Dictionary = main._airplane.folds.wing_fold_left
	_check("both panels fold to 112 deg", folded and absf(fold.degrees - 112.0) < 1e-6, "%.1f deg in %.1f s" % [fold.degrees, (Time.get_ticks_msec() - t0) / 1000.0])
	_check("the airplane stays put with the throttle held", main._stopped_on_wheels())
	_check("the HUD reports the fold and the hold", main._wing_fold_line().contains("folded") and main._wing_fold_line().contains("idle"), main._wing_fold_line())
	await _shot("folded")

	main._toggle_wing_fold()
	var spread := await _wait_until(func() -> bool: return main._wing_fold <= 0.0, 15.0)
	await process_frame
	await process_frame
	_check("spreading returns to 0 deg and releases the throttle", spread and fold.degrees == 0.0 and not session.throttle_holds.has("wing_fold") and session.sim.inputs[3] > 0.5,
		"%.1f deg, solver throttle %.2f" % [fold.degrees, session.sim.inputs[3]])
	await _shot("spread")
	var failed := checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({ format = "F4U-17 fold check v1", checks = checks, failures = failed }, "\t"))
	file.close()
	print("F4U-17 fold: %d checks, %d failures" % [checks.size(), failed])
	quit(1 if failed else 0)
