extends Node
## Lightweight entry: the official mark renders before the shell's large preload graph.

const Languages := preload("res://i18n/languages.gd")
const APP_SCENE := "res://app_root.tscn"
const Intro := preload("res://ui/brand_intro.gd")
const SceneLoad := preload("res://ui/flight_scene_load.gd")
## UI-28-R5: the staged first Home reports these top-level stages in order (World.build_staged, then
## the aircraft). The bar position counts completed milestones: the shell scene load and each stage;
## Home ready fills it. Other stage names are sub-stages and only advance within the current segment.
const HOME_STAGES := ["Preparing world", "Building landscape", "Preparing sky", "Preparing field lighting",
	"Finalizing world", "Preparing aircraft"]
const MILESTONES := 7.0 # scene load + HOME_STAGES
signal _frame_ready

var intro: Control
var _overlay: CanvasLayer
var _requested := false
var _committing := false
var _failed := false
var _skip := false
var _held_skip_inputs: Dictionary = {}
var _reduced_motion := false
var _scene_job: Node
var _packed_scene: PackedScene
var _closing := false
var _quit_tree: SceneTree
var _owns_quit_policy := false
var _auto_accept_quit_before := true
var _handoff_app: WeakRef
var _handoff_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _home_milestone := 0
var _home_stage := ""


func _ready() -> void:
	# GOD-04: opt-in source/debug observer survives the Startup -> AppRoot handoff.
	# Environment activation preserves the normal no-user-arguments Home route.
	if OS.is_debug_build() and not OS.get_environment("OPENRC_GODTEST_CONFIG").is_empty():
		var godtest_script: Script = load("res://debug/godtest_driver.gd")
		if godtest_script != null:
			var observer: Node = godtest_script.new()
			if observer.prepare_startup():
				get_tree().root.add_child.call_deferred(observer)
			else:
				observer.free()
	# Keep command-line flight, reports and headless contracts free of intro delays.
	if not _animate_requested():
		get_tree().change_scene_to_file.call_deferred(APP_SCENE)
		set_process(false)
		return
	_quit_tree = get_tree()
	_auto_accept_quit_before = _quit_tree.auto_accept_quit
	_owns_quit_policy = true
	_quit_tree.auto_accept_quit = false
	Input.joy_connection_changed.connect(_joy_connection_changed)
	var presentation := read_presentation(_presentation_settings_path())
	TranslationServer.set_locale(presentation.language)
	_reduced_motion = presentation.reduced_motion
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	intro = Intro.new()
	intro.name = "BrandIntro"
	intro.text_scale = presentation.ui_scale
	intro.skip_requested.connect(_request_skip)
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
		intro.progress = 1.0 / MILESTONES
	if _packed_scene != null and (_skip or intro.elapsed >= Intro.DURATION):
		_committing = true
		intro.status_text = "Preparing home…"
		_commit.call_deferred()


func _input(event: InputEvent) -> void:
	if intro == null or _closing:
		return
	if event is InputEventKey:
		var code: Key = event.keycode if event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] else event.physical_keycode
		if code in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_track_skip_input("key:%d" % code, event.pressed, event.echo)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_track_skip_input("mouse:left", event.pressed)
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		_track_skip_input("joy:%d" % event.device, event.pressed)
	elif event is InputEventScreenTouch:
		_track_skip_input("touch:%d" % event.index, event.pressed)
	# No skip event can activate a newly focused Home button during the transition.
	get_viewport().set_input_as_handled()


func _request_skip() -> void:
	if not _closing and not _failed:
		_skip = true


func _track_skip_input(id: String, pressed: bool, echo := false) -> void:
	if pressed and not echo and not _failed:
		_held_skip_inputs[id] = true
		_request_skip()
	elif not pressed:
		_held_skip_inputs.erase(id)


func _joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_held_skip_inputs.erase("joy:%d" % device)


func _commit() -> void:
	# Resolve the lockup. UI-28-R5: the atmosphere, logo sweep and bar keep moving while Home is
	# prepared; reduced motion keeps its still frame.
	if _reduced_motion or not intro.playing:
		intro.seek(maxf(intro.elapsed, Intro.DURATION))
	else:
		intro.settle()
	await _presentation_frame()
	if _closing or not is_inside_tree():
		return
	var packed := _packed_scene
	_packed_scene = null
	if packed == null:
		_fail()
		return
	var app := packed.instantiate()
	# UI-28-R5: an AppRoot that supports it builds the first Home in stages under this intro.
	var staged_home := app.get("startup_progress") is Callable
	if staged_home:
		app.set("startup_progress", _on_home_stage)
	# AppRoot now captures the original policy and owns every later close request.
	_release_quit_policy()
	get_tree().root.add_child(app)
	get_tree().current_scene = app
	_handoff_app = weakref(app)
	_handoff_process_mode = app.process_mode
	app.process_mode = Node.PROCESS_MODE_DISABLED
	# AppRoot handles a close request itself; it cancels the build at its next checkpoint.
	while staged_home and is_instance_valid(app) and bool(app.get("home_build_pending")) and is_inside_tree():
		await _owned_frame(get_tree().process_frame)
	if _closing or not is_inside_tree():
		return
	intro.detail_text = ""
	intro.progress = 1.0
	await _presentation_frame()
	await _owned_frame(get_tree().process_frame)
	while true:
		# Keep the resolved mark visible until Skip is released; Home stays disabled.
		while not _held_skip_inputs.is_empty() and not _closing and is_inside_tree():
			await _owned_frame(get_tree().process_frame)
		if _closing or not is_inside_tree():
			return
		var fade := create_tween()
		fade.tween_property(intro, "modulate:a", 0.0, 0.15 if _reduced_motion else 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		await fade.finished
		if _closing or not is_inside_tree():
			return
		if _held_skip_inputs.is_empty():
			break
		# A new Skip press during the fade must also finish before Home receives input.
		intro.modulate.a = 1.0
	_release_handoff_pause()
	queue_free()


## Synchronous stage report from the staged first Home (UI-28-R5). Each sub-stage report is one real
## chunk of work; repeated top-level reports (the aircraft-model wait) are ignored.
func _on_home_stage(stage: String) -> void:
	var index := HOME_STAGES.find(stage)
	if intro == null or (index >= 0 and stage == _home_stage):
		return
	_home_stage = stage
	intro.detail_text = stage
	if index >= _home_milestone:
		_home_milestone = index + 1
		intro.progress = (1.0 + index) / MILESTONES
	elif index < 0:
		# A sub-stage: part of the way toward the end of the current segment, never reaching it.
		var limit := (2.0 + maxi(_home_milestone - 1, 0)) / MILESTONES
		intro.progress = intro.progress + (limit - intro.progress) * 0.08


func _animate_requested() -> bool:
	return should_animate(DisplayServer.get_name(), OS.get_cmdline_user_args())


func _presentation_settings_path() -> String:
	return "user://settings.cfg"


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
	elif what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		# A release sent to another app will not arrive here.
		_held_skip_inputs.clear()


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


## Read only presentation keys before the shell loads. Never migrate/write settings here.
## Paths/keys mirror Preferences and AppRoot's display companion file without their preload graph.
static func read_presentation(path: String) -> Dictionary:
	var result := {"language": "en", "reduced_motion": false, "ui_scale": 1.0}
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		var schema: Variant = cfg.get_value("meta", "schema", -1)
		var language: Variant = cfg.get_value("ui", "language", "en")
		if typeof(schema) == TYPE_INT and schema >= 1 and typeof(language) == TYPE_STRING and Languages.NAMES.has(language):
			result.language = language
	var display := ConfigFile.new()
	if display.load(path + ".display") == OK:
		var schema: Variant = display.get_value("meta", "schema", -1)
		var reduced: Variant = display.get_value("accessibility", "reduced_motion", false)
		if typeof(schema) == TYPE_INT and schema >= 1:
			if typeof(reduced) == TYPE_BOOL:
				result.reduced_motion = reduced
			result.ui_scale = _validated_ui_scale(display.get_value("display", "ui_scale", 1.0))
	return result


## Mirrors DisplayPreferences without loading its camera/shadow dependencies.
static func _validated_ui_scale(scale: Variant) -> float:
	if typeof(scale) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(scale)) \
			and float(scale) >= 1.0 and float(scale) <= 2.0 \
			and is_equal_approx((float(scale) - 1.0) * 20.0, round((float(scale) - 1.0) * 20.0)):
		return float(scale)
	return 1.0
