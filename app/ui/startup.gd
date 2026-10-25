extends Node
## Lightweight entry: the official mark renders before the shell's large preload graph.

const APP_SCENE := "res://app_root.tscn"
const Intro := preload("res://ui/brand_intro.gd")

var intro: Control
var _overlay: CanvasLayer
var _requested := false
var _committing := false
var _failed := false
var _skip := false
var _reduced_motion := false


func _ready() -> void:
	# Keep command-line flight, reports and headless contracts free of intro delays.
	if not should_animate(DisplayServer.get_name(), OS.get_cmdline_user_args()):
		get_tree().change_scene_to_file.call_deferred(APP_SCENE)
		set_process(false)
		return
	var presentation := read_presentation("user://settings.cfg")
	TranslationServer.set_locale(presentation.language)
	_reduced_motion = presentation.reduced_motion
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	intro = Intro.new()
	intro.name = "BrandIntro"
	_overlay.add_child(intro)
	if _reduced_motion:
		intro.seek(Intro.DURATION)
	# Submit only after the first branded frame has been presented.
	await RenderingServer.frame_post_draw
	var error := ResourceLoader.load_threaded_request(APP_SCENE, "PackedScene")
	_requested = error == OK
	if not _requested:
		_fail()


func _process(_delta: float) -> void:
	if not _requested or _committing or _failed:
		return
	var status := ResourceLoader.load_threaded_get_status(APP_SCENE)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_fail()
	elif status == ResourceLoader.THREAD_LOAD_LOADED and (_skip or intro.elapsed >= Intro.DURATION):
		_committing = true
		intro.status_text = "Preparing home…"
		_commit.call_deferred()


func _input(event: InputEvent) -> void:
	if intro == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_SPACE]:
			_skip = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_skip = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		_skip = true
	# No skip event can activate a newly focused Home button during the transition.
	get_viewport().set_input_as_handled()


func _commit() -> void:
	# Freeze at the resolved lockup while synchronous Home scene construction runs.
	intro.seek(maxf(intro.elapsed, Intro.DURATION))
	await RenderingServer.frame_post_draw
	var packed := ResourceLoader.load_threaded_get(APP_SCENE) as PackedScene
	if packed == null:
		_fail()
		return
	var app := packed.instantiate()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	app.process_mode = Node.PROCESS_MODE_DISABLED
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(intro, "modulate:a", 0.0, 0.15 if _reduced_motion else 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await fade.finished
	app.process_mode = Node.PROCESS_MODE_INHERIT
	queue_free()


func _fail() -> void:
	_failed = true
	intro.status_text = "Unable to load. Please restart."
	push_error("Startup could not load " + APP_SCENE)


static func should_animate(display: String, args: PackedStringArray) -> bool:
	return display != "headless" and args.is_empty()


## Read only the two presentation keys before the shell loads. Never migrate/write settings here.
## Paths/keys mirror Preferences and AppRoot's display companion file without their preload graph.
static func read_presentation(path: String) -> Dictionary:
	var result := {"language": "en", "reduced_motion": false}
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var schema: Variant = cfg.get_value("meta", "schema", -1)
		var language: Variant = cfg.get_value("ui", "language", "en")
		if typeof(schema) == TYPE_INT and schema >= 1 and typeof(language) == TYPE_STRING and language in ["en", "es"]:
			result.language = language
	var display := ConfigFile.new()
	if display.load(path + ".display") == OK:
		var schema: Variant = display.get_value("meta", "schema", -1)
		var reduced: Variant = display.get_value("accessibility", "reduced_motion", false)
		if typeof(schema) == TYPE_INT and schema >= 1 and typeof(reduced) == TYPE_BOOL:
			result.reduced_motion = reduced
	return result
