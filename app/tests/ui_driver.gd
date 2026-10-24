# UI test driver (MENU-PLAN UI-00, research 15): real input events, the way a player produces them.
# - tap(): a fresh InputEventKey with keycode AND physical_keycode (the flight reads physical keys), press + release,
#   then two process frames: parse_input_event is applied at the next frame flush, never inside the same call.
# - joy(): a joypad axis or button event on a fake device, for radio isolation checks.
# Input.action_press() does not move GUI focus and button.pressed.emit() bypasses it: neither is used here.
extends RefCounted

const FAKE_DEVICE := 15 # a device index no real pad uses in CI

var _tree: SceneTree


func _init(tree: SceneTree) -> void:
	_tree = tree


func tap(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await settle()


func joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = FAKE_DEVICE
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await settle()


func joy_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = FAKE_DEVICE
		e.button_index = button
		e.pressed = pressed
		Input.parse_input_event(e)
	await settle()


## Name of the control with GUI focus, or "" when none.
func focus_name() -> String:
	var f := _tree.root.gui_get_focus_owner()
	return f.name if f != null else ""


## Two process frames: queued events are flushed and focus changes are applied.
func settle() -> void:
	await _tree.process_frame
	await _tree.process_frame


func _release_audio_players(node: Node) -> void:
	if node is AudioStreamPlayer3D:
		var player_3d: AudioStreamPlayer3D = node as AudioStreamPlayer3D
		player_3d.set_process(false)
		player_3d.set_physics_process(false)
		player_3d.stop()
		player_3d.stream = null
	elif node is AudioStreamPlayer2D:
		var player_2d: AudioStreamPlayer2D = node as AudioStreamPlayer2D
		player_2d.set_process(false)
		player_2d.set_physics_process(false)
		player_2d.stop()
		player_2d.stream = null
	elif node is AudioStreamPlayer:
		var player: AudioStreamPlayer = node as AudioStreamPlayer
		player.set_process(false)
		player.set_physics_process(false)
		player.stop()
		player.stream = null
	for child: Node in node.get_children():
		_release_audio_players(child)


## Quiesce app-owned audio players, drain one mixer interval, then release the UI scene.
func close_app(app: Node) -> void:
	app.set_process(false)
	app.set_physics_process(false)
	var flight: Node = app.get("flight")
	if flight != null:
		flight.set_process(false)
		flight.set_physics_process(false)
		var audio: Node = flight.get("_soundscape_audio")
		if audio != null:
			audio.set_process(false)
			audio.set_physics_process(false)
	_release_audio_players(app)
	# Mixer playback drains in wall time; a cold frame's simulation delta can
	# consume a SceneTreeTimer immediately, before stopped playback is released.
	var drain_until_usec: int = Time.get_ticks_usec() + 50000
	while Time.get_ticks_usec() < drain_until_usec:
		await _tree.process_frame
	if app.get_parent() == _tree.root:
		_tree.root.remove_child(app)
	app.free()
	await _tree.process_frame
	await _tree.process_frame
