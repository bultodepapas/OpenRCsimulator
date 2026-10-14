## Exercise the production scene, real keys, marker, reset, close and native capture.
extends SceneTree
const Ui := preload("res://tests/ui_driver.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, value: bool) -> void:
	if not value:
		failures += 1
		printerr("FAIL " + label)


func _run() -> void:
	var ui := Ui.new(self)
	var main: Node = load("res://main.tscn").instantiate()
	main.external_controller_selection = true # deterministic keyboard route, independent of connected hardware
	main.set_user_args(PackedStringArray(["--quick-flight", "--soundscape=off"]))
	root.add_child(main)
	await ui.settle()
	check("ready fixed-wing logger", main.flight_log != null)
	await ui.tap(KEY_P) # explicit resume after the native window's initial focus-loss notification
	await ui.tap(KEY_F10)
	check("F10 records", main.flight_log.recording)
	var path: String = main.flight_log.path
	await create_timer(0.2).timeout
	check("accepted ticks recorded", main.flight_log.seconds() > 0.0)
	await ui.tap(KEY_F11)
	check("recording visible", main._flight_log_label.text.begins_with("REC"))
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../tmp/flight-log-ui.png"))
	await ui.tap(KEY_F10)
	check("F10 stops", not main.flight_log.recording)
	var inspected: Dictionary = Reader.inspect(path)
	check("file complete", inspected.ok)
	if inspected.ok:
		check("marker recorded", inspected.events.any(func(event: Dictionary) -> bool: return event.kind == "marker"))
		var restored: Dictionary = Reader.prepare_replay(inspected.header)
		check("interactive field/scenery checkpoint restores", restored.ok)
		if restored.ok: restored.flight.free()
	await ui.tap(KEY_F10)
	path = main.flight_log.path
	await ui.tap(KEY_R)
	check("restart seals one flight", not main.flight_log.recording and Reader.inspect(path).ok)
	await ui.tap(KEY_F10)
	path = main.flight_log.path
	main.queue_free()
	await ui.settle()
	check("scene close seals file", Reader.inspect(path).ok)
	print("FL-04 production UI: %d failures" % failures)
	quit(1 if failures else 0)
