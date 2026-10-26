extends SceneTree

const Startup := preload("res://ui/startup.gd")
const Intro := preload("res://ui/brand_intro.gd")
const PREFS := "user://test_brand_startup.cfg"
const SceneLoad := preload("res://ui/flight_scene_load.gd")
var failures := 0
var handoff_policy: Array[bool] = []


class LoadGate extends RefCounted:
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var result: PackedScene
	func load_scene(_path: String, _hint: String) -> Resource:
		entered.post()
		release.wait()
		return result


class UnavailableLoad extends "res://ui/flight_scene_load.gd":
	func start(_path: String) -> Error:
		complete = true
		return ERR_CANT_CREATE


class HandoffQuitState extends Node:
	var _quit_audio_pending := true


class TestStartup extends "res://ui/startup.gd":
	var gate: LoadGate
	var unavailable := false
	var quit_count := 0
	var failure_count := 0
	func _animate_requested() -> bool:
		return true
	func _presentation_frame() -> Signal:
		return _owned_frame(get_tree().process_frame) # explicit seam; production waits for actual post_draw
	func _new_startup_scene_load() -> Node:
		if unavailable:
			return UnavailableLoad.new()
		var job := SceneLoad.new()
		job.load_resource = gate.load_scene
		return job
	func _request_quit() -> void:
		quit_count += 1
	func _fail() -> void:
		# Expected invalid-load cases must not emit intentional engine errors into the checked runner.
		failure_count += 1
		_failed = true
		intro.status_text = "Unable to load. Please restart."


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	if passed:
		print("ok  ", label)
	else:
		failures += 1
		printerr("FAIL ", label)


func _frames(count := 3) -> void:
	for _frame in count:
		await process_frame


func _wait_started(gate: LoadGate) -> bool:
	for _frame in 300:
		if gate.entered.try_wait():
			return true
		await process_frame
	return false


func _fixture(process_mode := Node.PROCESS_MODE_INHERIT) -> TestStartup:
	var startup := TestStartup.new()
	startup.gate = LoadGate.new()
	var source := Node.new()
	source.name = "StartupTestApp"
	source.process_mode = process_mode
	startup.gate.result = PackedScene.new()
	startup.gate.result.pack(source)
	source.free()
	return startup


func _on_child_entered(child: Node) -> void:
	if child.name == "StartupTestApp":
		handoff_policy.append(auto_accept_quit)


func _handoff_checks() -> void:
	for variant in ["presentation free", "fade free", "changed mode", "accepted quit"]:
		var startup := _fixture(Node.PROCESS_MODE_PAUSABLE)
		root.add_child(startup)
		await _wait_started(startup.gate)
		startup._skip = true
		startup.gate.release.post()
		var app: Node
		for _frame in 300:
			app = root.get_node_or_null("StartupTestApp")
			if app != null:
				break
			await process_frame
		check("handoff app is held before fade: " + variant, app != null and app.process_mode == Node.PROCESS_MODE_DISABLED)
		if app == null:
			startup.free()
			continue
		if variant != "presentation free":
			await _frames()
		if variant == "changed mode":
			app.process_mode = Node.PROCESS_MODE_ALWAYS
		elif variant == "accepted quit":
			app.set_script(HandoffQuitState)
		startup.free()
		var expected := Node.PROCESS_MODE_PAUSABLE
		if variant == "changed mode":
			expected = Node.PROCESS_MODE_ALWAYS
		elif variant == "accepted quit":
			expected = Node.PROCESS_MODE_DISABLED
		check("raw startup free respects prior mode or accepted quit: " + variant, app.process_mode == expected)
		app.free()
		await _frames()


func _loader_checks() -> void:
	var policy_before := auto_accept_quit
	root.child_entered_tree.connect(_on_child_entered)
	var startup := _fixture()
	root.add_child(startup)
	startup._reduced_motion = true
	check("startup waits for its presentation boundary before creating a worker", startup._scene_job == null)
	check("startup owns close requests while its loader is pending", not auto_accept_quit)
	var started := await _wait_started(startup.gate)
	var job_ref: WeakRef = weakref(startup._scene_job)
	var startup_ref: WeakRef = weakref(startup)
	startup._skip = true
	await _frames()
	check("skip cannot commit an unfinished worker", started and not startup._committing and root.get_node_or_null("StartupTestApp") == null)
	startup.gate.release.post()
	for _frame in 300:
		if startup_ref.get_ref() == null:
			break
		await process_frame
	var app: Node = root.get_node_or_null("StartupTestApp")
	check("collected dedicated load preserves skip and fade handoff", app != null and app.process_mode == Node.PROCESS_MODE_INHERIT
		and startup_ref.get_ref() == null and job_ref.get_ref() == null)
	check("AppRoot handoff sees original quit policy", handoff_policy == [policy_before] and auto_accept_quit == policy_before)
	if app != null:
		app.free()
	await _handoff_checks()

	startup = _fixture()
	root.add_child(startup)
	started = await _wait_started(startup.gate)
	job_ref = weakref(startup._scene_job)
	paused = true
	startup.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	startup.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await _frames()
	check("paused close yields while live startup worker drains", started and startup.quit_count == 0 and job_ref.get_ref() != null)
	startup.gate.release.post()
	for _frame in 300:
		if startup.quit_count > 0:
			break
		await process_frame
	await _frames()
	check("duplicate startup close commits once after worker disposal", startup.quit_count == 1 and job_ref.get_ref() == null)
	startup.free()
	paused = false
	check("departing startup restores quit policy", auto_accept_quit == policy_before)

	startup = _fixture()
	root.add_child(startup)
	started = await _wait_started(startup.gate)
	job_ref = weakref(startup._scene_job)
	var gate: LoadGate = startup.gate
	startup.free()
	await _frames()
	check("raw startup free leaves its active worker root owned", started and job_ref.get_ref() != null)
	gate.release.post()
	for _frame in 300:
		if job_ref.get_ref() == null:
			break
		await process_frame
	check("abandoned startup worker drains and frees without a join on main", job_ref.get_ref() == null)

	startup = _fixture()
	startup.unavailable = true
	root.add_child(startup)
	await _frames()
	check("thread-start failure retains the startup error state", startup.failure_count == 1 and startup._scene_job == null
		and startup.intro.status_text == "Unable to load. Please restart.")
	startup.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("failed startup remains closable", startup.quit_count == 1)
	startup.free()

	startup = _fixture()
	startup.gate.result = null
	root.add_child(startup)
	await _wait_started(startup.gate)
	startup.gate.release.post()
	for _frame in 300:
		if startup.failure_count > 0:
			break
		await process_frame
	check("null loaded scene fails without attempting handoff", startup.failure_count == 1 and not startup._committing)
	startup.free()
	await _frames()
	root.child_entered_tree.disconnect(_on_child_entered)


func _run() -> void:
	check("interactive launch animates", Startup.should_animate("Windows", PackedStringArray()))
	check("headless launch bypasses intro", not Startup.should_animate("headless", PackedStringArray()))
	for arg in ["--quick-flight", "--input-report", "--trace=tmp/check.csv", "--vehicle=mt8-bisonte"]:
		check("technical route bypass: " + arg, not Startup.should_animate("Windows", PackedStringArray([arg])))
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema", 5)
	cfg.set_value("ui", "language", "es")
	cfg.save(PREFS)
	var display := ConfigFile.new()
	display.set_value("meta", "schema", 1)
	display.set_value("accessibility", "reduced_motion", true)
	display.save(PREFS + ".display")
	var original_hash := FileAccess.get_sha256(PREFS)
	var choices := Startup.read_presentation(PREFS)
	check("saved Spanish and reduced motion respected", choices.language == "es" and choices.reduced_motion)
	check("intro never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "zh_Hans")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved Simplified Chinese", choices.language == "zh_Hans" and choices.reduced_motion)
	check("Chinese startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "pt_BR")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved Brazilian Portuguese", choices.language == "pt_BR" and choices.reduced_motion)
	check("Portuguese startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "de")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved German", choices.language == "de" and choices.reduced_motion)
	check("German startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "fr")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved French", choices.language == "fr" and choices.reduced_motion)
	check("French startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "it")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved Italian", choices.language == "it" and choices.reduced_motion)
	check("Italian startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "ru")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved Russian", choices.language == "ru" and choices.reduced_motion)
	check("Russian startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", "ja")
	cfg.save(PREFS)
	original_hash = FileAccess.get_sha256(PREFS)
	choices = Startup.read_presentation(PREFS)
	check("startup honors saved Japanese", choices.language == "ja" and choices.reduced_motion)
	check("Japanese startup never rewrites preferences", FileAccess.get_sha256(PREFS) == original_hash)
	cfg.set_value("ui", "language", 123)
	cfg.save(PREFS)
	display.set_value("accessibility", "reduced_motion", "false")
	display.save(PREFS + ".display")
	choices = Startup.read_presentation(PREFS)
	check("malformed values use defaults", choices.language == "en" and not choices.reduced_motion)
	DirAccess.remove_absolute(PREFS)
	DirAccess.remove_absolute(PREFS + ".display")
	check("missing preferences use defaults", Startup.read_presentation(PREFS) == {"language": "en", "reduced_motion": false})
	var intro := Intro.new()
	root.add_child(intro)
	for resolution in [Vector2i(1920, 1080), Vector2i(3840, 2160), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		check("intro fills viewport %s" % resolution, intro.size == Vector2(resolution))
	intro.seek(Intro.DURATION)
	await process_frame
	check("review/reduced motion frame remains still", not intro.playing and intro.elapsed == Intro.DURATION)
	var weak: WeakRef = weakref(intro)
	intro.queue_free()
	await process_frame
	check("presentation nodes released", weak.get_ref() == null)
	await _loader_checks()
	print("Brand startup: %d failed" % failures)
	quit(1 if failures else 0)
