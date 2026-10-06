# Investigation 24 probe (headless): focus-loss notifications, key release, input order with a pause menu on a
# CanvasLayer added after the flight scene, and the AudioStreamPlayer3D pause/restart gap left open by investigation 19.
# It reports behaviour; it asserts nothing. Never run it with --path app (the app's InputMap and autoloads differ).
# Run from the repo root inside a throwaway minimal project, so the engine's built-in ui_* actions apply:
#   D=$(mktemp -d); printf 'config_version=5\n' > "$D/project.godot"
#   cp docs/research/menu-investigations/probes/24-pause-focus-input-probe.gd "$D/"
#   XDG_CONFIG_HOME="$D/cfg" XDG_DATA_HOME="$D/data" .tools/Godot_v4.7.2-stable_linux.x86_64 \
#     --headless --audio-driver Dummy --path "$D" --script res://24-pause-focus-input-probe.gd
extends SceneTree

const LOGGER := """
extends %s
var tag := ""
var log_ref: Array
var handle_keys: Array = []   # physical keycodes this node consumes in _unhandled_input
var input_keys: Array = []    # physical keycodes this node consumes in _input
func _notification(what: int) -> void:
	var names := {2016: "APP_FOCUS_IN", 2017: "APP_FOCUS_OUT", 1004: "WM_WINDOW_FOCUS_IN", 1005: "WM_WINDOW_FOCUS_OUT"}
	if names.has(what):
		log_ref.append("%%s:%%s(up=%%s)" %% [tag, names[what], Input.is_physical_key_pressed(KEY_UP)])
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		log_ref.append("%%s._input" %% tag)
		if e.physical_keycode in input_keys:
			get_viewport().set_input_as_handled()
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey:
		log_ref.append("%%s._unhandled_input%%s" %% [tag, "" if e.pressed else "(up)"])
		if e.physical_keycode in handle_keys:
			get_viewport().set_input_as_handled()
"""

var log: Array = []
var flight: Node3D
var layer: CanvasLayer
var menu: Control
var b_continue: Button
var b_restart: Button


func _initialize() -> void:
	_run()


func _logger(base: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = LOGGER % base
	s.reload()
	return s


func _frames(n := 2) -> void:
	for i in n:
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frames()


func _tap(code: Key) -> Array:
	log.clear()
	await _key(code, true)
	log.append("|release:")
	await _key(code, false)
	return log.duplicate()


func _run() -> void:
	print("engine ", Engine.get_version_info().string, " display=", DisplayServer.get_name())
	# Tree like the plan: flight scene first, then a CanvasLayer with the pause menu (added later).
	flight = Node3D.new()
	flight.name = "Flight"
	flight.set_script(_logger("Node3D"))
	flight.set("tag", "Flight")
	flight.set("log_ref", log)
	var sim := Node.new()
	sim.set_script(_logger("Node"))
	sim.set("tag", "Flight/Sim")
	sim.set("log_ref", log)
	flight.add_child(sim)
	root.add_child(flight)
	layer = CanvasLayer.new()
	root.add_child(layer)
	menu = Control.new()
	menu.set_script(_logger("Control"))
	menu.set("tag", "Menu")
	menu.set("log_ref", log)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var box := VBoxContainer.new()
	menu.add_child(box)
	b_continue = Button.new()
	b_continue.text = "Continuar"
	b_restart = Button.new()
	b_restart.text = "Reiniciar"
	box.add_child(b_continue)
	box.add_child(b_restart)
	b_continue.pressed.connect(func(): log.append("Continuar.pressed"))
	b_restart.pressed.connect(func(): log.append("Reiniciar.pressed"))
	await _frames()

	print("\n== 1. Focus notifications (headless; there is no real window) ==")
	await _key(KEY_UP, true)
	print("UP held: is_physical_key_pressed=", Input.is_physical_key_pressed(KEY_UP), " ui_up action=", Input.is_action_pressed("ui_up"))
	log.clear()
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	print("root.propagate_notification(APP_FOCUS_OUT): order=", log, " -> UP after=", Input.is_physical_key_pressed(KEY_UP))
	log.clear()
	notification(NOTIFICATION_APPLICATION_FOCUS_OUT) # what DisplayServer does: MainLoop (SceneTree) notification
	print("SceneTree.notification(APP_FOCUS_OUT): order=", log)
	print("  after: UP=", Input.is_physical_key_pressed(KEY_UP), " ui_up action=", Input.is_action_pressed("ui_up"))
	log.clear()
	notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	await _frames()
	print("SceneTree.notification(APP_FOCUS_IN): order=", log, " UP still physically held but reads=", Input.is_physical_key_pressed(KEY_UP))
	var echo := InputEventKey.new()
	echo.physical_keycode = KEY_UP
	echo.keycode = KEY_UP
	echo.pressed = true
	echo.echo = true
	Input.parse_input_event(echo)
	await _frames()
	print("after an OS key-repeat (echo=true) press: UP=", Input.is_physical_key_pressed(KEY_UP))
	await _key(KEY_UP, false)
	await _key(KEY_UP, true)
	print("after a real release+press: UP=", Input.is_physical_key_pressed(KEY_UP))
	await _key(KEY_UP, false)
	print("WM_WINDOW_FOCUS_* seen headless during the above: ", "none (only via the DisplayServer window callback)")

	print("\n== 2. Input order, CanvasLayer menu added after Flight, nobody consumes ==")
	b_continue.grab_focus()
	await _frames()
	print("focus owner=", root.gui_get_focus_owner().text)
	for k in [KEY_ESCAPE, KEY_P, KEY_ENTER, KEY_SPACE, KEY_DOWN, KEY_UP, KEY_LEFT]:
		var got := await _tap(k)
		print("%-7s -> %s  (focus now %s)" % [OS.get_keycode_string(k), got, root.gui_get_focus_owner().text if root.gui_get_focus_owner() else "-"])
		b_continue.grab_focus()
		await _frames()
	print("Enter held on focused Continuar: UP-like polling sees it? KEY_ENTER pressed during press = ", await _held(KEY_ENTER))

	print("\n== 3. Menu consumes Escape in _unhandled_input ==")
	menu.set("handle_keys", [KEY_ESCAPE])
	print("ESC -> ", await _tap(KEY_ESCAPE))
	menu.set("handle_keys", [])
	print("\n== 3b. Menu hidden (visible=false): does its _unhandled_input still run? ==")
	menu.visible = false
	await _frames()
	print("focus owner after hide=", root.gui_get_focus_owner())
	print("ESC -> ", await _tap(KEY_ESCAPE))
	print("ENTER -> ", await _tap(KEY_ENTER))
	menu.visible = true
	await _frames()

	print("\n== 3c. Double toggle: Flight opens on ESC, Menu closes on ESC, neither consumes ==")
	flight.set("handle_keys", [])
	# Emulate with the log: both handlers ran for one ESC if both tags appear.
	var got := await _tap(KEY_ESCAPE)
	print("one ESC reached: ", got, " -> a toggle in each handler would close then reopen (or vice versa) in the same event")

	print("\n== 4. GUI consumption does not touch Input polling ==")
	b_continue.grab_focus()
	await _frames()
	log.clear()
	await _key(KEY_DOWN, true)
	print("DOWN pressed (GUI moved focus to ", root.gui_get_focus_owner().text, "): log=", log, " is_physical_key_pressed(DOWN)=", Input.is_physical_key_pressed(KEY_DOWN))
	await _key(KEY_DOWN, false)

	print("\n== 5. AudioStreamPlayer3D + AudioStreamGenerator: stream_paused across stop()+play() ==")
	await _audio()
	print("\nprobe done")
	quit(0)


func _held(code: Key) -> bool:
	await _key(code, true)
	var v := Input.is_physical_key_pressed(code)
	await _key(code, false)
	return v


func _audio() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	var p := AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.15
	p.stream = gen
	p.position = Vector3(0, 0, -2)
	root.add_child(p)
	p.play()
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	_fill(pb)
	print("after play()+fill: stream_paused=", p.stream_paused, " free=", pb.get_frames_available())
	await _wait(0.3, p)
	print("playing 0.3 s (fed each frame): free=", (p.get_stream_playback() as AudioStreamGeneratorPlayback).get_frames_available(), " peak=%.1f dB" % AudioServer.get_bus_peak_volume_left_db(0, 0))
	p.stream_paused = true
	var pb_before := p.get_stream_playback()
	await _wait(0.3, p, false)
	print("stream_paused=true 0.3 s (not fed): stream_paused=", p.stream_paused, " free=", (pb_before as AudioStreamGeneratorPlayback).get_frames_available(), " peak=%.1f dB" % AudioServer.get_bus_peak_volume_left_db(0, 0))
	# State changed during pause (R): restart while still paused, in the same frame.
	p.stop()
	p.play()
	p.stream_paused = true
	var pb2 := p.get_stream_playback() as AudioStreamGeneratorPlayback
	print("stop()+play()+stream_paused=true same frame: new playback=", pb2 != pb_before, " stream_paused reads=", p.stream_paused)
	_fill(pb2)
	await physics_frame
	await physics_frame
	print("  after 2 physics frames: stream_paused=", p.stream_paused, " playing=", p.playing)
	await _wait(0.3, p, false)
	print("  0.3 s later (not fed): free=", pb2.get_frames_available(), " peak=%.1f dB" % AudioServer.get_bus_peak_volume_left_db(0, 0), " skips=", pb2.get_skips())
	# Same, but set stream_paused one physics frame after play().
	p.stop()
	p.play()
	var pb3 := p.get_stream_playback() as AudioStreamGeneratorPlayback
	_fill(pb3)
	await physics_frame
	await physics_frame
	p.stream_paused = true
	print("stop()+play(), 2 physics frames, then stream_paused=true: reads=", p.stream_paused)
	var free_at := pb3.get_frames_available()
	await _wait(0.3, p, false)
	print("  0.3 s later (not fed): free ", free_at, " -> ", pb3.get_frames_available(), " peak=%.1f dB" % AudioServer.get_bus_peak_volume_left_db(0, 0))
	p.stream_paused = false
	await _wait(0.3, p)
	print("resume (stream_paused=false, fed): peak=%.1f dB skips=%d" % [AudioServer.get_bus_peak_volume_left_db(0, 0), pb3.get_skips()])
	p.queue_free()
	cam.queue_free()


var _phase := 0.0


func _fill(pb: AudioStreamGeneratorPlayback) -> void:
	if pb == null:
		return
	var n := pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_phase += TAU * 220.0 / 22050.0
		buf[i] = Vector2.ONE * 0.5 * sin(_phase)
	pb.push_buffer(buf)


func _wait(seconds: float, p: AudioStreamPlayer3D, feed := true) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if feed:
			_fill(p.get_stream_playback() as AudioStreamGeneratorPlayback)
		await process_frame
