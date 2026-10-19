extends SceneTree
## Native recovery-dialog review with a deterministic failed manual recorder.
const AppRoot := preload("res://app_root.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const Driver := preload("res://tests/ui_driver.gd")

class FailedRecorder extends RefCounted:
	var recording := true
	var note := ""
	func stop(_path := "") -> Error:
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE
		return ERR_CANT_CREATE
	func detach() -> void: recording = false
	func seconds() -> float: return 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := "user://trace-recovery-es-200.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	root.size = Vector2i(1280, 720)
	var policy := UiScale.apply(root)
	UiTheme.compact_layout = bool(policy.compact)
	UiTheme.text_scale = 2.0
	TranslationServer.set_locale("es")
	var app := AppRoot.new()
	app.user_args = PackedStringArray(["--quick-flight"])
	app.preferences_path = "user://ae_trace_recovery_capture.cfg"
	root.add_child(app)
	for frame in 4: await process_frame
	if app.flight == null:
		printerr("Trace capture: flight startup failed")
		quit(1)
		return
	app.flight.recorder = FailedRecorder.new()
	app.quit_app()
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	var error := ERR_DOES_NOT_EXIST
	if dialog != null:
		error = root.get_texture().get_image().save_png(output)
		var rect := Rect2(Vector2(dialog.position), Vector2(dialog.size))
		if not Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(rect): error = ERR_INVALID_DATA
		print("Trace capture: ", output, " bounds=", rect, " error=", error)
	else:
		printerr("Trace capture: recovery dialog missing")
	await Driver.new(self).close_app(app)
	quit(error)
