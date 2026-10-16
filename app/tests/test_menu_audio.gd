# Menu audio observes only active, user-driven menu controls; cue requests are deterministic
# under the headless Dummy driver and do not claim physical playback.
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_menu_audio.gd
extends SceneTree

const MenuAudioService := preload("res://ui/menu_audio.gd")

var _failures: int = 0
var _top_surface: Control
var _requested_cues: Array[StringName] = []


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	await _run()
	quit(1 if _failures > 0 else 0)


func _surface() -> Control:
	return _top_surface


func _record_cue(cue: StringName, _source_id: int) -> void:
	_requested_cues.append(cue)


func _run() -> void:
	var host := Node.new()
	host.name = "MenuAudioHost"
	root.add_child(host)
	var screen_a := Control.new()
	screen_a.name = "SurfaceA"
	screen_a.size = Vector2(800.0, 600.0)
	host.add_child(screen_a)
	var screen_b := Control.new()
	screen_b.name = "SurfaceB"
	screen_b.size = Vector2(800.0, 600.0)
	host.add_child(screen_b)
	_top_surface = screen_a

	var button := Button.new()
	button.name = "ActionButton"
	button.position = Vector2(20.0, 20.0)
	button.size = Vector2(160.0, 40.0)
	button.focus_mode = Control.FOCUS_ALL
	screen_a.add_child(button)
	var option := OptionButton.new()
	option.name = "Selection"
	option.position = Vector2(20.0, 80.0)
	option.size = Vector2(180.0, 36.0)
	option.focus_mode = Control.FOCUS_ALL
	option.add_item("One")
	option.add_item("Two")
	screen_a.add_child(option)
	var slider := HSlider.new()
	slider.name = "Range"
	slider.position = Vector2(20.0, 140.0)
	slider.size = Vector2(260.0, 36.0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.focus_mode = Control.FOCUS_ALL
	screen_a.add_child(slider)
	var flight_button := Button.new()
	flight_button.name = "FlightControl"
	flight_button.add_to_group("flight_input")
	screen_a.add_child(flight_button)
	await process_frame

	var service := MenuAudioService.attach(host, Callable(self, "_surface"))
	service.set_volume(0.0)
	service.cue_requested.connect(Callable(self, "_record_cue"))
	var observed_count := service.observe(screen_a)
	_check("menu surface observes eligible controls once", observed_count >= 3, str(observed_count))
	_check("re-observing a surface does not add duplicate signal connections", service.observe(screen_a) == 0)
	_check("flight-only controls are outside the observed menu input set",
		not service._observed_controls.has(flight_button.get_instance_id()))
	_check("two non-positional voices are allocated", service._voices.size() == 2, str(service._voices.size()))

	button.grab_focus()
	slider.value = 12.0
	_check("programmatic initial focus and range values stay silent",
		service.cue_count(&"focus") == 0 and service.cue_count(&"change") == 0)

	var pointer_press := InputEventMouseButton.new()
	pointer_press.button_index = MOUSE_BUTTON_LEFT
	pointer_press.pressed = true
	pointer_press.position = slider.get_global_rect().get_center()
	service._input(pointer_press)
	slider.value = 24.0
	_check("direct user range adjustment requests one change cue", service.cue_count(&"change") == 1)

	await process_frame
	slider.value = 30.0
	_check("programmatic range changes outside input remain silent", service.cue_count(&"change") == 1)

	var pointer_release := InputEventMouseButton.new()
	pointer_release.button_index = MOUSE_BUTTON_LEFT
	pointer_release.pressed = false
	pointer_release.position = slider.get_global_rect().get_center()
	service._input(pointer_release)
	var pointer_motion := InputEventMouseMotion.new()
	pointer_motion.position = button.get_global_rect().get_center()
	service._input(pointer_motion)
	button.mouse_entered.emit()
	button.mouse_entered.emit()
	_check("hover duplicates on the same target are debounced", service.cue_count(&"hover") == 1,
		"count=%d rect=%s position=%s" % [service.cue_count(&"hover"), str(button.get_global_rect()), str(pointer_motion.position)])

	var navigation := InputEventAction.new()
	navigation.action = &"ui_down"
	navigation.pressed = true
	service._input(navigation)
	option.grab_focus()
	_check("user navigation can request focus audio", service.cue_count(&"focus") == 1)
	option.item_selected.emit(1)
	_check("OptionButton selection requests a selection cue", service.cue_count(&"select") == 1)

	var press_count_before := service.cue_count(&"press")
	button.pressed.emit()
	_check("semantic accept cue is callable", service.play(&"accept", button))
	await process_frame
	_check("semantic accept suppresses its same-frame automatic press duplicate",
		service.cue_count(&"press") == press_count_before and service.cue_count(&"accept") == 1)
	_check("cue request signal exposes deterministic observations",
		_requested_cues.has(&"change") and _requested_cues.has(&"hover") and _requested_cues.has(&"focus")
		and _requested_cues.has(&"select") and _requested_cues.has(&"accept"))

	_top_surface = screen_b
	button.pressed.emit()
	await process_frame
	_check("controls below the active ScreenStack surface cannot sound",
		service.cue_count(&"press") == press_count_before)

	_top_surface = screen_a
	button.disabled = true
	button.pressed.emit()
	await process_frame
	button.disabled = false
	button.hide()
	button.pressed.emit()
	await process_frame
	_check("disabled and hidden controls cannot request press audio",
		service.cue_count(&"press") == press_count_before)
	button.show()
	button.pressed.emit()
	await process_frame
	_check("an eligible active button requests press audio", service.cue_count(&"press") == press_count_before + 1)
	press_count_before = service.cue_count(&"press")

	host.remove_child(screen_a)
	host.add_child(screen_a)
	_top_surface = screen_a
	var reobserved_count := service.observe(screen_a)
	_check("a detached and reattached menu surface can be observed again", reobserved_count >= 3,
		str(reobserved_count))
	await create_timer(0.11).timeout
	button.pressed.emit()
	await process_frame
	_check("reattached controls retain one press connection", service.cue_count(&"press") == press_count_before + 1,
		"presses=%d before=%d" % [service.cue_count(&"press"), press_count_before])
	press_count_before = service.cue_count(&"press")

	button.pressed.emit()
	_check("semantic back cue is callable while a route is closing", service.play(&"back", button))
	_top_surface = screen_b
	button.queue_free()
	screen_a.queue_free()
	await process_frame
	_check("host-owned audio service survives the source screen closing",
		is_instance_valid(service) and service.get_parent() == host)
	_check("semantic cues remain observable after route closure", service.play(&"reject"))
	_check("semantic cue counters reflect logical requests", service.cue_count(&"back") == 1
		and service.cue_count(&"reject") == 1)
	var accepts_before: int = service.cue_count(&"accept")
	service.play(&"accept")
	service.play(&"accept") # an accepted launch can mount a controller-readiness Pause in the same frame
	_check("one transition produces one acceptance cue", service.cue_count(&"accept") == accepts_before + 1)

	service.set_volume(2.0)
	_check("normalized volume is clamped to its public range", service.get_volume() == 1.0)
	service.set_volume(-1.0)
	_check("negative normalized volume is clamped to mute", service.get_volume() == 0.0)
	service.set_volume(0.35)
	service.play(&"focus")
	service.set_volume(0.0)
	_check("muting stops an already playing cue", service._voices.all(func(voice: AudioStreamPlayer) -> bool: return not voice.playing))

	host.queue_free()
	await create_timer(0.1).timeout # allow the audio mixer to release the stopped playback before process teardown
