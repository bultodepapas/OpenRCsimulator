extends SceneTree

const Startup := preload("res://ui/startup.gd")
const Intro := preload("res://ui/brand_intro.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")
const PREFS := "user://test_brand_startup.cfg"
const SceneLoad := preload("res://ui/flight_scene_load.gd")
var failures := 0
var checks := 0
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
	func _presentation_settings_path() -> String:
		return PREFS
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
	checks += 1
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
	var source := Control.new()
	source.name = "StartupTestApp"
	source.process_mode = process_mode
	var fly := Button.new()
	fly.name = "Fly"
	fly.text = "Fly"
	source.add_child(fly)
	fly.owner = source
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
		and startup.intro.status_text == "Unable to load. Please restart."
		and startup.intro.status_label.accessibility_live == 2 and startup.intro.skip_button.disabled
		and root.gui_get_focus_owner() == startup.intro.status_label)
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


func _scale_checks() -> void:
	var display := ConfigFile.new()
	display.set_value("meta", "schema", 1)
	display.set_value("accessibility", "reduced_motion", true)
	for value: Variant in [1, 1.05, 1.5, 2.0, 0.95, 2.05, 1.03, "2", true, NAN, INF, -INF]:
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.ui_scale = value
		var checked: Dictionary = DisplayPreferences.validate(candidate)
		var expected: float = float(value) if checked.ok else 1.0
		check("lightweight scale matches display validator: %s" % str(value),
			is_equal_approx(Startup._validated_ui_scale(value), expected))
	for value: Variant in [1.0, 1.05, 1.5, 2.0, 0.95, 2.05, 1.03, "2", true]:
		display.set_value("display", "ui_scale", value)
		display.save(PREFS + ".display")
		var before := FileAccess.get_sha256(PREFS + ".display")
		var candidate: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
		candidate.ui_scale = value
		var checked: Dictionary = DisplayPreferences.validate(candidate)
		var expected: float = float(value) if checked.ok else 1.0
		var presentation: Dictionary = Startup.read_presentation(PREFS)
		check("saved scale is validated independently: %s" % str(value),
			is_equal_approx(presentation.ui_scale, expected) and presentation.reduced_motion)
		check("startup never rewrites display file: %s" % str(value),
			before == FileAccess.get_sha256(PREFS + ".display"))
	display.set_value("meta", "schema", 9)
	display.set_value("display", "ui_scale", 2.0)
	display.save(PREFS + ".display")
	var future_hash := FileAccess.get_sha256(PREFS + ".display")
	var future: Dictionary = Startup.read_presentation(PREFS)
	check("future display schema reads valid fields without rewriting", future.ui_scale == 2.0
		and future.reduced_motion and future_hash == FileAccess.get_sha256(PREFS + ".display"))
	display.set_value("meta", "schema", 0)
	display.save(PREFS + ".display")
	var invalid_schema: Dictionary = Startup.read_presentation(PREFS)
	check("invalid display schema ignores scale and reduced motion", invalid_schema.ui_scale == 1.0
		and not invalid_schema.reduced_motion)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".display"))


func _semantic_checks() -> void:
	for locale: String in ["en", "es", "zh_Hans"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			root.size = Vector2i(1920, 1080)
			var intro := Intro.new()
			intro.text_scale = scale
			root.add_child(intro)
			await _frames()
			var label: Label = intro.status_label
			var button: Button = intro.skip_button
			var prefix := "%s %.0f%%" % [locale, scale * 100.0]
			check(prefix + " exposes localized polite status and semantic Skip", label != null and button != null
				and label.text == TranslationServer.translate("Loading…") and label.accessibility_name == label.text
				and label.accessibility_live == 1 and button.accessibility_name == TranslationServer.translate("Skip intro")
				and button.focus_mode == Control.FOCUS_ALL and not button.disabled)
			check(prefix + " scales text and keeps footer inside 1080p", label.get_theme_font_size("font_size") == roundi(18.0 * scale)
				and root.get_visible_rect().encloses(label.get_global_rect())
				and root.get_visible_rect().encloses(button.get_global_rect())
				and not label.get_global_rect().intersects(button.get_global_rect()))
			var activations := [0]
			intro.skip_requested.connect(func() -> void: activations[0] += 1)
			button.pressed.emit()
			check(prefix + " semantic button activation emits Skip", activations[0] == 1)
			intro.status_text = "Preparing home…"
			check(prefix + " preparing status updates accessible name", label.text == TranslationServer.translate("Preparing home…")
				and label.accessibility_name == label.text and label.accessibility_live == 1)
			intro.status_text = "Unable to load. Please restart."
			check(prefix + " failure is assertive and disables misleading Skip", label.text == TranslationServer.translate("Unable to load. Please restart.")
				and label.accessibility_name == label.text and label.accessibility_live == 2 and button.disabled
				and root.gui_get_focus_owner() == label)
			await _frames()
			check(prefix + " failure text remains visible within the viewport", root.get_visible_rect().encloses(label.get_global_rect())
				and label.get_visible_line_count() == label.get_line_count())
			intro.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
			intro.seek(2.0)
			check(prefix + " trailer hides footer but preserves logo child", intro._footer.modulate.a == 0.0
				and intro._mark.modulate.a == 1.0)
			root.remove_child(intro)
			intro.free()
			await _frames(1)
	TranslationServer.set_locale("en")


func _skip_event(kind: String, down: bool) -> InputEvent:
	if kind in ["enter", "space", "unrelated"]:
		var event := InputEventKey.new()
		var code: Key = KEY_ENTER if kind == "enter" else (KEY_SPACE if kind == "space" else KEY_X)
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		return event
	if kind == "pad":
		var event := InputEventJoypadButton.new()
		event.device = 15
		event.button_index = JOY_BUTTON_A
		event.pressed = down
		return event
	if kind == "touch":
		var event := InputEventScreenTouch.new()
		event.index = 7
		event.position = Vector2(50, 50)
		event.pressed = down
		return event
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(50, 50)
	event.global_position = event.position
	event.pressed = down
	return event


func _input_handoff_checks() -> void:
	for kind: String in ["enter", "space", "pad", "mouse", "touch", "focus-loss", "disconnect", "accepted-quit"]:
		var startup := _fixture(Node.PROCESS_MODE_PAUSABLE)
		root.add_child(startup)
		startup._reduced_motion = true
		var started := await _wait_started(startup.gate)
		var actual_kind := "pad" if kind == "disconnect" else ("enter" if kind in ["focus-loss", "accepted-quit"] else kind)
		Input.parse_input_event(_skip_event(actual_kind, true))
		await _frames()
		check(kind + " Skip input is captured", started and startup._skip and not startup._held_skip_inputs.is_empty())
		startup.gate.release.post()
		var app: Node
		for _frame in 600:
			app = root.get_node_or_null("StartupTestApp")
			if app != null:
				break
			await process_frame
		check(kind + " creates paused handoff", app != null and app.process_mode == Node.PROCESS_MODE_DISABLED)
		if app == null:
			startup.free()
			continue
		var fly: Button = app.get_node("Fly")
		var hits := [0]
		fly.pressed.connect(func() -> void: hits[0] += 1)
		fly.grab_focus()
		await create_timer(0.22).timeout
		check(kind + " held Skip keeps visible intro and Home disabled", is_instance_valid(startup)
			and is_equal_approx(startup.intro.modulate.a, 1.0) and app.process_mode == Node.PROCESS_MODE_DISABLED and hits[0] == 0)
		if kind == "accepted-quit":
			app.set_script(HandoffQuitState)
			startup.free()
			check("held-input cleanup respects an accepted quit", app.process_mode == Node.PROCESS_MODE_DISABLED)
			Input.parse_input_event(_skip_event(actual_kind, false))
			app.free()
			await _frames()
			continue
		if kind == "focus-loss":
			startup.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
			check("focus loss clears lost release latch", startup._held_skip_inputs.is_empty())
		elif kind == "disconnect":
			startup._joy_connection_changed(15, false)
			check("controller disconnect clears lost release latch", startup._held_skip_inputs.is_empty())
		else:
			Input.parse_input_event(_skip_event(actual_kind, false))
		await create_timer(0.25).timeout
		check(kind + " release completes without activating Fly", not is_instance_valid(startup)
			and app.process_mode == Node.PROCESS_MODE_PAUSABLE and hits[0] == 0)
		if kind in ["focus-loss", "disconnect"]:
			Input.parse_input_event(_skip_event(actual_kind, false))
		app.free()
		await _frames()
	var natural := _fixture()
	root.add_child(natural)
	natural._reduced_motion = true
	await _wait_started(natural.gate)
	Input.parse_input_event(_skip_event("unrelated", true))
	await _frames()
	check("unrelated held key does not latch Skip", not natural._skip and natural._held_skip_inputs.is_empty())
	natural.intro.seek(Intro.DURATION)
	natural.gate.release.post()
	await create_timer(0.25).timeout
	var app: Node = root.get_node_or_null("StartupTestApp")
	check("natural handoff does not wait for an unrelated key", app != null and not is_instance_valid(natural))
	Input.parse_input_event(_skip_event("unrelated", false))
	if app != null:
		app.free()
	await _frames()
	var semantic := _fixture()
	root.add_child(semantic)
	await _wait_started(semantic.gate)
	semantic.intro.skip_button.pressed.emit()
	check("semantic action reaches startup without a physical event", semantic._skip and semantic._held_skip_inputs.is_empty())
	semantic.gate.release.post()
	semantic.free()
	await _frames()


func _saved_startup_checks() -> void:
	root.size = Vector2i(1920, 1080)
	for locale: String in ["en", "es", "zh_Hans"]:
		for scale: float in [1.0, 2.0]:
			for reduced: bool in [false, true]:
				var cfg := ConfigFile.new()
				cfg.set_value("meta", "schema", 1)
				cfg.set_value("ui", "language", locale)
				cfg.save(PREFS)
				var display := ConfigFile.new()
				display.set_value("meta", "schema", 1)
				display.set_value("display", "ui_scale", scale)
				display.set_value("accessibility", "reduced_motion", reduced)
				display.save(PREFS + ".display")
				var prefs_hash := FileAccess.get_sha256(PREFS)
				var display_hash := FileAccess.get_sha256(PREFS + ".display")
				var startup := _fixture()
				root.add_child(startup)
				check("saved %s %.0f%% reduced=%s reaches startup" % [locale, scale * 100.0, reduced],
					startup.intro.text_scale == scale and startup._reduced_motion == reduced
					and startup.intro.status_label.text == TranslationServer.translate("Loading…")
					and (not reduced or (not startup.intro.playing and startup.intro.elapsed == Intro.DURATION))
					and prefs_hash == FileAccess.get_sha256(PREFS) and display_hash == FileAccess.get_sha256(PREFS + ".display"))
				startup.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + ".display"))
	TranslationServer.set_locale("en")


func _late_press_checks() -> void:
	var startup := _fixture(Node.PROCESS_MODE_PAUSABLE)
	root.add_child(startup)
	startup._reduced_motion = true
	await _wait_started(startup.gate)
	startup.intro.skip_button.pressed.emit()
	startup.gate.release.post()
	var app: Node
	for _frame in 600:
		app = root.get_node_or_null("StartupTestApp")
		if app != null:
			break
		await process_frame
	check("late-Skip fixture starts handoff", app != null)
	check("Skip is hidden once Home is being prepared", not startup.intro.skip_button.visible)
	if app == null:
		startup.free()
		return
	var fly: Button = app.get_node("Fly")
	var hits := [0]
	fly.pressed.connect(func() -> void: hits[0] += 1)
	fly.grab_focus()
	await create_timer(0.04).timeout
	Input.parse_input_event(_skip_event("space", true))
	await create_timer(0.22).timeout
	check("Skip pressed during fade restores visible held intro", is_instance_valid(startup)
		and not startup._held_skip_inputs.is_empty() and is_equal_approx(startup.intro.modulate.a, 1.0)
		and app.process_mode == Node.PROCESS_MODE_DISABLED and hits[0] == 0)
	Input.parse_input_event(_skip_event("space", false))
	await create_timer(0.25).timeout
	check("late Skip release completes without activating Fly", not is_instance_valid(startup)
		and app.process_mode == Node.PROCESS_MODE_PAUSABLE and hits[0] == 0)
	app.free()
	await _frames()


func _initial_error_focus_checks() -> void:
	for locale: String in ["en", "ja"]:
		TranslationServer.set_locale(locale)
		for timing: String in ["before add", "immediately after add"]:
			var intro := Intro.new()
			if timing == "before add":
				intro.status_text = "Unable to load. Please restart."
			root.add_child(intro)
			if timing == "immediately after add":
				intro.status_text = "Unable to load. Please restart."
			await _frames()
			check("%s initial error %s retains status focus after deferred call" % [locale, timing],
				intro.skip_button.disabled and intro.status_label.accessibility_live == 2
				and intro.status_label.accessibility_name == TranslationServer.translate("Unable to load. Please restart.")
				and root.gui_get_focus_owner() == intro.status_label)
			root.remove_child(intro)
			intro.free()
			await _frames(1)
		var loading := Intro.new()
		root.add_child(loading)
		await _frames()
		check("%s normal initial focus remains on enabled Skip" % locale,
			not loading.skip_button.disabled and root.gui_get_focus_owner() == loading.skip_button)
		root.remove_child(loading)
		loading.free()
		await _frames(1)
	TranslationServer.set_locale("en")


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
	check("missing preferences use defaults", Startup.read_presentation(PREFS) == {"language": "en", "reduced_motion": false, "ui_scale": 1.0})
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
	await _scale_checks()
	await _saved_startup_checks()
	await _semantic_checks()
	await _initial_error_focus_checks()
	await _input_handoff_checks()
	await _late_press_checks()
	await _loader_checks()
	print("Brand startup detail: %d checks, %d failed" % [checks, failures])
	print("Brand startup: %d failed" % failures)
	quit(1 if failures else 0)
