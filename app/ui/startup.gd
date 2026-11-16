extends Node
## Lightweight entry: the official mark renders before the shell's large preload graph.

const Languages := preload("res://i18n/languages.gd")
const NativePackage := preload("res://app_state/native_package.gd")
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


## Only allocated for the explicitly requested packaged-flight diagnostic.
class PackageFlightWindowReadiness extends Node:
	const STABLE_USEC := 500_000
	const TIMEOUT_USEC := 5_000_000
	var deadline_usec := 0
	var stable_since_usec := -1
	var losses := 0
	var observed_losses := 0

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			losses += 1

	func begin(now_usec: int) -> void:
		deadline_usec = now_usec + TIMEOUT_USEC
		stable_since_usec = -1
		observed_losses = losses

	func observe(now_usec: int, focused: bool, drawable: bool) -> int:
		if now_usec > deadline_usec: return -1
		if losses != observed_losses:
			stable_since_usec = -1
			observed_losses = losses
		if not focused or not drawable:
			stable_since_usec = -1
		elif stable_since_usec < 0:
			stable_since_usec = now_usec
		if stable_since_usec >= 0 and now_usec - stable_since_usec >= STABLE_USEC: return 1
		return -1 if now_usec >= deadline_usec else 0


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
var _package_flight_wait_generation := 0


func _enter_tree() -> void:
	# Pin the process receipt before the intro or deferred application handoff.
	# This is a bounded receipt read only on a macOS release template.
	NativePackage.pin_macos_process_receipt()


func _ready() -> void:
	# A fixed, package-bound release diagnostic may observe the ordinary Home
	# route, but only after proving its private user-data directory. Normal
	# launches do not load the diagnostic or change their startup path.
	if OS.get_environment("OPENRC_PACKAGE_DEFAULT_PROBE") == "1":
		if not _start_package_default_probe():
			printerr("PACKAGE_DEFAULT_PROBE verdict=fail: qualification setup refused")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
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
		if _package_flight_window_wait_requested():
			set_process(false)
			var wait_generation := _package_flight_wait_generation
			var readiness: Dictionary = await _wait_for_package_flight_window(wait_generation)
			if not is_inside_tree() or wait_generation != _package_flight_wait_generation: return
			if not readiness.ok:
				_fail_package_flight_window(readiness.focused, readiness.drawable)
				return
			print("PACKAGE_FLIGHT window=ready focused=true drawable=true")
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


static func _is_package_flight_request(args: PackedStringArray) -> bool:
	for argument: String in args:
		if argument.begins_with("--package-flight-receipt="): return true
	return false


func _package_flight_window_wait_requested() -> bool:
	return _is_package_flight_request(OS.get_cmdline_user_args())


func _fail_package_flight_window(focused: bool, drawable: bool) -> void:
	printerr("PACKAGE_FLIGHT verdict=fail: startup window not ready; focused=", focused,
		" drawable=", drawable)
	get_tree().quit(ERR_CANT_CREATE)


func _package_flight_window_has_focus() -> bool:
	var window := get_window()
	return is_instance_valid(window) and window.has_focus()


func _package_flight_window_can_draw() -> bool:
	var window := get_window()
	return is_instance_valid(window) and window.can_draw()


## The diagnostic waits before AppRoot/Main exist; no session or sampling clock can advance here.
func _wait_for_package_flight_window(wait_generation: int) -> Dictionary:
	var readiness := PackageFlightWindowReadiness.new()
	readiness.name = "_PackageFlightWindowReadiness"
	add_child(readiness)
	readiness.begin(Time.get_ticks_usec())
	while is_inside_tree() and wait_generation == _package_flight_wait_generation:
		var focused := _package_flight_window_has_focus()
		var drawable := _package_flight_window_can_draw()
		var result: int = readiness.observe(Time.get_ticks_usec(), focused, drawable)
		if result != 0:
			readiness.free()
			return {ok = result > 0, focused = focused, drawable = drawable}
		await _owned_frame(get_tree().process_frame)
	if is_instance_valid(readiness): readiness.free()
	return {ok = false, focused = false, drawable = false}


func _start_package_default_probe() -> bool:
	if OS.get_name() != "macOS" or not OS.has_feature("template_release") \
			or Engine.get_architecture_name() != "arm64": return false
	var mode := OS.get_environment("OPENRC_PACKAGE_DEFAULT_PROBE_MODE")
	if mode not in ["missing", "malformed", "candidate", "reference"]: return false
	var args := OS.get_cmdline_user_args()
	var reference_args := PackedStringArray(["--quick-flight", "--physics-backend=gdscript_reference"])
	if (mode == "reference" and args != reference_args) or (mode != "reference" and not args.is_empty()): return false
	var task_home := OS.get_environment("HOME")
	var bundle := OS.get_executable_path().get_base_dir().get_base_dir().get_base_dir()
	var private_parent := bundle.get_base_dir()
	var prefix := "openrc-package-default-probe-"
	var case_id := private_parent.get_file().trim_prefix(prefix)
	if task_home != task_home.simplify_path() or not task_home.is_absolute_path() \
			or not private_parent.get_file().begins_with(prefix) or case_id.length() != 32 \
			or task_home != private_parent.path_join("private-home") or not _probe_path_without_links(task_home):
		return false
	for index: int in case_id.length():
		var code := case_id.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102): return false
	var private_dir := DirAccess.open(task_home)
	if private_dir == null or private_dir.is_link(".openrc-package-default-profile"): return false
	var expected_token := OS.get_environment("OPENRC_PACKAGE_DEFAULT_PROFILE_TOKEN_SHA256")
	if expected_token.length() != 64 or FileAccess.get_sha256(task_home.path_join(".openrc-package-default-profile")) != expected_token:
		return false
	var user_dir := task_home.path_join("Library/Application Support/Godot/app_userdata/OpenRC Simulator")
	if OS.get_user_data_dir() != user_dir or OS.get_environment("OPENRC_PACKAGE_DEFAULT_EXPECT_USER_DIR") != user_dir \
			or not _probe_path_without_links(user_dir):
		return false
	var identity := NativePackage.mac_native_identity(OS.get_executable_path(), Engine.get_architecture_name(),
		OS.get_cmdline_args() + args)
	var path := "res://native/kernel/qualification/package_default_probe.gd"
	if not identity.get("ok", false) or not identity.get("manifest") is Dictionary \
			or not identity.manifest.get("qualification_sources") is Dictionary \
			or FileAccess.get_sha256(path) != identity.manifest.qualification_sources.get("package_default_probe.gd"):
		return false
	var script: Script = load(path)
	if script == null or not script.can_instantiate(): return false
	var observer: Node = script.new()
	if observer == null or not observer.has_method("prepare") or not observer.call("prepare", mode, identity, user_dir):
		if observer != null: observer.free()
		return false
	get_tree().root.add_child.call_deferred(observer)
	return true


static func _probe_path_without_links(path: String) -> bool:
	if not path.is_absolute_path() or not path.begins_with("/") or path != path.simplify_path(): return false
	var current := "/"
	for part: String in path.trim_prefix("/").split("/", false):
		var parent := DirAccess.open(current)
		if parent == null or parent.is_link(part) or not parent.dir_exists(part): return false
		current = current.path_join(part)
	return true


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
	# UI-28-R5b: nothing is left to skip once Home is being prepared; a visible Skip would promise an
	# action that no longer exists. Skip inputs are still held below so Home cannot receive them.
	intro.skip_button.visible = false
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
	intro.subdetail_text = ""
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
	if index >= 0 or intro.detail_text == "":
		intro.detail_text = stage # the stable stage line
		intro.subdetail_text = ""
	else:
		intro.subdetail_text = stage
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
	_package_flight_wait_generation += 1
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
