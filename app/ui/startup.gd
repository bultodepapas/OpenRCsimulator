extends Node
## Lightweight entry: the official mark renders before the shell's large preload graph.

const APP_SCENE := "res://app_root.tscn"
const Intro := preload("res://ui/brand_intro.gd")
const SceneLoad := preload("res://ui/flight_scene_load.gd")
signal _frame_ready

var intro: Control
var _overlay: CanvasLayer
var _requested := false
var _committing := false
var _failed := false
var _skip := false
var _reduced_motion := false
var _scene_job: Node
var _packed_scene: PackedScene
var _closing := false
var _quit_tree: SceneTree
var _owns_quit_policy := false
var _auto_accept_quit_before := true
var _handoff_app: WeakRef
var _handoff_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT


func _ready() -> void:
	# Keep command-line flight, reports and headless contracts free of intro delays.
	if not _animate_requested():
		get_tree().change_scene_to_file.call_deferred(APP_SCENE)
		set_process(false)
		return
	_quit_tree = get_tree()
	_auto_accept_quit_before = _quit_tree.auto_accept_quit
	_owns_quit_policy = true
	_quit_tree.auto_accept_quit = false
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
	await _presentation_frame()
	if _closing or not is_inside_tree():
		return
	# Reuse the dedicated ordinary-load owner: WorkerThreadPool nested script
	# preloads can leak count-zero LoadTokens on the pinned engine, even after get.
	_scene_job = _new_startup_scene_load()
	get_tree().root.add_child(_scene_job)
	var error: Error = _scene_job.start(APP_SCENE)
	_requested = error == OK
	if not _requested:
		_scene_job.abandon()
		_scene_job = null
		_fail()


func _process(_delta: float) -> void:
	if not _requested or _committing or _failed or _closing:
		return
	if is_instance_valid(_scene_job) and _scene_job.complete:
		_packed_scene = _scene_job.take_scene()
		_scene_job = null
		if _packed_scene == null:
			_fail()
			return
	if _packed_scene != null and (_skip or intro.elapsed >= Intro.DURATION):
		_committing = true
		intro.status_text = "Preparing home…"
		_commit.call_deferred()


func _input(event: InputEvent) -> void:
	if intro == null or _closing:
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
	await _presentation_frame()
	if _closing or not is_inside_tree():
		return
	var packed := _packed_scene
	_packed_scene = null
	if packed == null:
		_fail()
		return
	var app := packed.instantiate()
	# AppRoot now captures the original policy and owns every later close request.
	_release_quit_policy()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	_handoff_app = weakref(app)
	_handoff_process_mode = app.process_mode
	app.process_mode = Node.PROCESS_MODE_DISABLED
	await _presentation_frame()
	await _owned_frame(get_tree().process_frame)
	var fade := create_tween()
	fade.tween_property(intro, "modulate:a", 0.0, 0.15 if _reduced_motion else 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await fade.finished
	_release_handoff_pause()
	queue_free()


func _animate_requested() -> bool:
	return should_animate(DisplayServer.get_name(), OS.get_cmdline_user_args())


func _presentation_frame() -> Signal:
	return _owned_frame(RenderingServer.frame_post_draw)


## Await a signal owned by this node: raw free disconnects the relay and cannot resume a dead instance.
func _owned_frame(frame: Signal) -> Signal:
	frame.connect(_on_frame_ready, CONNECT_ONE_SHOT)
	return _frame_ready


func _on_frame_ready() -> void:
	_frame_ready.emit()


func _new_startup_scene_load() -> Node:
	return SceneLoad.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _owns_quit_policy:
		_drain_and_quit()


func _drain_and_quit() -> void:
	if _closing:
		return
	_closing = true
	var job: Node = _scene_job
	while is_instance_valid(job) and not job.complete:
		await _owned_frame(get_tree().process_frame)
		if not is_inside_tree():
			return
	if is_instance_valid(job):
		job.abandon()
	_scene_job = null
	_packed_scene = null
	_request_quit()


func _request_quit() -> void:
	get_tree().quit()


func _release_quit_policy() -> void:
	if _owns_quit_policy and is_instance_valid(_quit_tree):
		_quit_tree.auto_accept_quit = _auto_accept_quit_before
	_owns_quit_policy = false
	_quit_tree = null


func _release_handoff_pause() -> void:
	var app: Node = _handoff_app.get_ref() if _handoff_app != null else null
	_handoff_app = null
	if not is_instance_valid(app) or app.is_queued_for_deletion() or app.process_mode != Node.PROCESS_MODE_DISABLED:
		return
	# The shell may already be draining an accepted Quit while the intro fades.
	for property: Dictionary in app.get_property_list():
		if property.name in ["_quit_audio_pending", "_home_preparation_quit_pending"] and bool(app.get(property.name)):
			return
	app.process_mode = _handoff_process_mode


func _exit_tree() -> void:
	_release_quit_policy()
	_release_handoff_pause()
	_packed_scene = null
	if is_instance_valid(_scene_job):
		_scene_job.abandon()
		_scene_job = null


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
