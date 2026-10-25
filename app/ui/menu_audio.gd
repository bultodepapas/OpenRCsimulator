class_name MenuAudio
extends Node

## Small, non-positional sound service for the product shell.
## `cue_requested` records a logical request; it does not claim that an audio device
## produced sound (headless and dummy-driver tests can observe it deterministically).
signal cue_requested(cue: StringName, source_id: int)

const MAX_VOICES := 2
const RANGE_DEBOUNCE_MS := 220
const NAVIGATION_DEBOUNCE_MS := 140
const PRESS_DEBOUNCE_MS := 90
const TAIL_FADE_SECONDS := 0.018

const STREAM_BY_CUE: Dictionary = {
	&"focus": preload("res://assets/ui/audio/navigation.ogg"),
	&"hover": preload("res://assets/ui/audio/navigation.ogg"),
	&"press": preload("res://assets/ui/audio/press.ogg"),
	&"select": preload("res://assets/ui/audio/selection.ogg"),
	&"change": preload("res://assets/ui/audio/range_tick.ogg"),
	&"accept": preload("res://assets/ui/audio/accept.ogg"),
	&"back": preload("res://assets/ui/audio/back.ogg"),
	&"reject": preload("res://assets/ui/audio/reject.ogg"),
	&"open": preload("res://assets/ui/audio/open.ogg"),
	&"pause": preload("res://assets/ui/audio/pause.ogg"),
	&"resume": preload("res://assets/ui/audio/resume.ogg"),
	&"restart": preload("res://assets/ui/audio/restart.ogg"),
	&"exit": preload("res://assets/ui/audio/exit.ogg"),
	&"quit": preload("res://assets/ui/audio/exit.ogg"),
	&"cancel": preload("res://assets/ui/audio/back.ogg"),
	&"saved": preload("res://assets/ui/audio/accept.ogg"),
}

const GAIN_BY_CUE: Dictionary = {
	&"focus": 0.24,
	&"hover": 0.16,
	&"press": 0.38,
	&"select": 0.34,
	&"change": 0.28,
	&"accept": 0.48,
	&"back": 0.40,
	&"reject": 0.28,
	&"open": 0.25,
	&"pause": 0.30,
	&"resume": 0.34,
	&"restart": 0.28,
	&"exit": 0.32,
	&"quit": 0.34,
	&"cancel": 0.28,
	&"saved": 0.32,
}

# Natural wood/soft impacts from Kenney Impact Sounds. Alternate real takes;
# small downward pitch offsets preserve the material instead of making a tune.
const NAVIGATION_STREAMS: Array[AudioStream] = [
	preload("res://assets/ui/audio/navigation.ogg"),
	preload("res://assets/ui/audio/navigation_2.ogg"),
	preload("res://assets/ui/audio/navigation_3.ogg"),
]
const NAVIGATION_PITCHES: Array[float] = [0.96, 0.99, 0.97, 1.0, 0.98]
const PRESS_PITCHES: Array[float] = [1.0, 0.98, 0.96]
const CUE_PITCH: Dictionary = {
	&"select": 1.0,
	&"change": 1.0,
	&"accept": 1.0,
	&"back": 0.96,
	&"reject": 0.92,
	&"open": 1.0,
	&"pause": 1.0,
	&"resume": 1.0,
	&"restart": 0.97,
	&"exit": 1.0,
	&"quit": 0.94,
	&"cancel": 1.0,
	&"saved": 1.0,
}

# A concrete outcome wins over incidental screen mounts in the same action.
# Lower-priority cues in later frames remain valid (e.g. Back after an error).
const SEMANTIC_PRIORITY: Dictionary = {
	&"open": 1, &"pause": 1, &"back": 1,
	&"accept": 2, &"resume": 2, &"cancel": 2, &"saved": 2,
	&"restart": 3, &"exit": 3, &"reject": 4, &"quit": 5,
}

const NAVIGATION_ACTIONS: PackedStringArray = [
	"ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev",
]
const RANGE_ACTIONS: PackedStringArray = [
	"ui_home", "ui_end", "ui_page_up", "ui_page_down",
]
const EXCLUDED_GROUPS: PackedStringArray = ["flight_only", "flight_input"]

var _retiring := false
var _top_screen_provider: Callable
var _volume: float = 0.35
var _voices: Array[AudioStreamPlayer] = []
var _voice_cues: Array[StringName] = []
var _cue_counts: Dictionary = {}
var _dropped_voice_count: int = 0
var _navigation_step := 0
var _press_step := 0
var _voice_started_ms: Array[int] = []
var _voice_fades: Array[Tween] = []

var _observed_screens: Dictionary = {}
var _observed_controls: Dictionary = {}
var _last_automatic_ms: Dictionary = {}
var _last_semantic_frame: int = -1
var _last_semantic_cue: StringName = &""

var _current_input_frame: int = -1
var _current_input_kind: StringName = &""
var _pointer_position: Vector2 = Vector2(-100000.0, -100000.0)
var _left_mouse_down: bool = false


## Adds one persistent service under `host`, returning an existing instance when present.
## `top_screen_provider` must return the current ScreenStack screen root, or null.
static func attach(host: Node, top_screen_provider: Callable) -> MenuAudio:
	if host == null or not is_instance_valid(host):
		return null
	for child: Node in host.get_children():
		if child is MenuAudio:
			(child as MenuAudio).set_top_screen_provider(top_screen_provider)
			return child as MenuAudio
	var service := MenuAudio.new()
	service.set_top_screen_provider(top_screen_provider)
	host.add_child(service)
	return service


func _ready() -> void:
	for voice_index: int in range(MAX_VOICES):
		var player := AudioStreamPlayer.new()
		player.name = "MenuAudioVoice%d" % voice_index
		player.max_polyphony = 1
		add_child(player)
		_voices.append(player)
		_voice_cues.append(&"")
		_voice_started_ms.append(0)
		_voice_fades.append(null)
	set_volume(_volume)


func set_top_screen_provider(provider: Callable) -> void:
	_top_screen_provider = provider


func _exit_tree() -> void:
	retire_playbacks()
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for control_id: int in _observed_controls.keys():
		_on_control_tree_exiting(control_id)
	for screen_id: int in _observed_screens.keys():
		var screen := instance_from_id(screen_id) as Control
		var callback := Callable(self, "_on_screen_tree_exiting").bind(screen_id)
		if screen != null and screen.tree_exiting.is_connected(callback):
			screen.tree_exiting.disconnect(callback)
	_observed_screens.clear()


## Observes a mounted menu, including controls added or reparented later.
## Flight views should not be passed to this method.
func observe(screen: Control) -> int:
	if screen == null or not is_instance_valid(screen) or not screen.is_inside_tree():
		return 0
	var screen_id := screen.get_instance_id()
	_observed_screens[screen_id] = true
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	var exiting := Callable(self, "_on_screen_tree_exiting").bind(screen_id)
	if not screen.tree_exiting.is_connected(exiting):
		screen.tree_exiting.connect(exiting)
	return _observe_subtree(screen, screen)


func _on_node_added(node: Node) -> void:
	if node is Control:
		# node_added precedes _ready: wait until focus/mouse properties are configured.
		_observe_added_control.call_deferred(node.get_instance_id())


func _observe_added_control(control_id: int) -> void:
	if not is_inside_tree():
		return
	var control := instance_from_id(control_id) as Control
	if control == null or not control.is_inside_tree() or control.is_queued_for_deletion():
		return
	var ancestor: Node = control
	while ancestor != null:
		if _observed_screens.has(ancestor.get_instance_id()):
			if not _is_excluded(control, ancestor as Control):
				_connect_control(control, ancestor as Control)
			return
		ancestor = ancestor.get_parent()


## Emits a semantic cue such as `&"accept"`, `&"back"`, or `&"reject"`.
## Calling this from a button action suppresses that button's automatic press cue in the
## same frame, avoiding duplicate accept/open sounds while allowing the screen to close.
func play(cue: StringName, source: Object = null) -> bool:
	if not STREAM_BY_CUE.has(cue):
		return false
	if _is_semantic_cue(cue):
		if _last_semantic_frame == Engine.get_process_frames():
			if _last_semantic_cue == cue or int(SEMANTIC_PRIORITY[_last_semantic_cue]) > int(SEMANTIC_PRIORITY[cue]):
				return false
		_last_semantic_frame = Engine.get_process_frames()
		_last_semantic_cue = cue
	return _request_cue(cue, source)


## Scales the menu effects from 0 (muted) to 1 (service maximum).
func set_volume(normalized: float) -> void:
	if not is_finite(normalized):
		return
	_volume = clampf(normalized, 0.0, 1.0)
	for voice_index: int in range(_voices.size()):
		if _voice_fades[voice_index] == null:
			_update_voice_volume(voice_index)
		if _volume <= 0.0:
			_cancel_fade(voice_index)
			_voices[voice_index].stop()


func get_volume() -> float:
	return _volume


func cue_count(cue: StringName) -> int:
	return int(_cue_counts.get(cue, 0))


func dropped_voice_count() -> int:
	return _dropped_voice_count


## Bounded native tail after a committed Quit. Silent/test routes close immediately.
## Called only after play("quit"), never before the user's save/discard decisions.
func shutdown_delay() -> float:
	var master := AudioServer.get_bus_index(&"Master")
	if _volume <= 0.0 or AudioServer.get_driver_name() == "Dummy" \
		or AudioServer.is_bus_mute(master) or AudioServer.get_bus_volume_db(master) <= -60.0:
		return 0.0
	for index: int in range(_voices.size()):
		if _voice_cues[index] == &"quit" and _voices[index].playing:
			return minf(_voices[index].stream.get_length() / _voices[index].pitch_scale + 0.06, 0.5)
	return 0.0


## Stop bounded voice ownership before final quit, leaving the mixer/main thread time to retire its references.
## Weak observations do not extend playback lifetime; the coordinator reports a finite drain timeout.
func retire_playbacks() -> Array[WeakRef]:
	_retiring = true
	var playbacks: Array[WeakRef] = []
	for index: int in range(_voices.size()):
		_cancel_fade(index)
		var voice := _voices[index]
		if voice.has_stream_playback():
			playbacks.append(weakref(voice.get_stream_playback()))
		voice.stop()
		voice.stream = null
	set_process_input(false)
	return playbacks


func _observe_subtree(node: Node, screen: Control) -> int:
	if _is_excluded(node, screen):
		return 0
	var connected := 0
	if node is Control:
		var control := node as Control
		if _connect_control(control, screen):
			connected += 1
	for child: Node in node.get_children():
		connected += _observe_subtree(child, screen)
	return connected


func _connect_control(control: Control, screen: Control) -> bool:
	var control_id := control.get_instance_id()
	if _observed_controls.has(control_id):
		return false
	var connections: Array[Dictionary] = []
	if control.focus_mode != Control.FOCUS_NONE:
		_connect_control_signal(control, &"focus_entered", &"_on_control_focused", screen, connections)
	var pointer_target := control is BaseButton or control is Range
	if pointer_target and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_connect_control_signal(control, &"mouse_entered", &"_on_control_hovered", screen, connections)
	if control is BaseButton:
		_connect_control_signal(control, &"pressed", &"_on_button_pressed", screen, connections)
	if control is OptionButton:
		_connect_control_signal(control, &"item_selected", &"_on_option_selected", screen, connections)
	if control is Range:
		_connect_control_signal(control, &"value_changed", &"_on_range_changed", screen, connections)
	if connections.is_empty():
		return false
	# Property names are structural; values remain live (e.g. a slider becoming read-only).
	var checks: Array[StringName] = []
	for property_info: Dictionary in control.get_property_list():
		var property_name := StringName(property_info.get("name", ""))
		if property_name == &"editable" or property_name == &"disabled":
			checks.append(property_name)
	var exiting_callback := Callable(self, "_on_control_tree_exiting").bind(control_id)
	control.tree_exiting.connect(exiting_callback)
	connections.append({event_signal = control.tree_exiting, callback = exiting_callback})
	_observed_controls[control_id] = {checks = checks, connections = connections}
	return true


func _connect_control_signal(control: Control, signal_name: StringName, handler: StringName,
		screen: Control, connections: Array[Dictionary]) -> void:
	var callback := Callable(self, handler).bind(control, screen)
	control.connect(signal_name, callback)
	connections.append({event_signal = Signal(control, signal_name), callback = callback})


func _is_excluded(node: Node, screen: Control) -> bool:
	var current: Node = node
	while current != null:
		if current.has_meta("menu_audio_exclude") and bool(current.get_meta("menu_audio_exclude")):
			return true
		for group_name: String in EXCLUDED_GROUPS:
			if current.is_in_group(group_name):
				return true
		if current == screen:
			break
		current = current.get_parent()
	return false


func _on_control_focused(control: Control, screen: Control) -> void:
	if _current_input_frame != Engine.get_process_frames() or _current_input_kind != &"navigation":
		return
	_play_automatic(&"focus", control, screen, NAVIGATION_DEBOUNCE_MS)


func _on_control_hovered(control: Control, screen: Control) -> void:
	if _current_input_frame != Engine.get_process_frames() or _current_input_kind != &"pointer_motion":
		return
	if not control.get_global_rect().has_point(_pointer_position):
		return
	_play_automatic(&"hover", control, screen, NAVIGATION_DEBOUNCE_MS)


func _on_button_pressed(button: BaseButton, screen: Control) -> void:
	var event_frame := Engine.get_process_frames()
	call_deferred("_deferred_button_press", button, screen, event_frame)


func _deferred_button_press(button: Variant, screen: Variant, event_frame: int) -> void:
	if not is_instance_valid(button) or not button is BaseButton:
		return
	if not is_instance_valid(screen) or not screen is Control:
		return
	if event_frame == _last_semantic_frame:
		return
	_play_automatic(&"press", button as Control, screen as Control, PRESS_DEBOUNCE_MS)


func _on_option_selected(_index: int, option: OptionButton, screen: Control) -> void:
	if Engine.get_process_frames() == _last_semantic_frame:
		return
	_play_automatic(&"select", option, screen, PRESS_DEBOUNCE_MS)


func _on_range_changed(_value: float, range_control: Range, screen: Control) -> void:
	if not _range_was_user_adjusted(range_control):
		return
	_play_automatic(&"change", range_control, screen, RANGE_DEBOUNCE_MS)


func _range_was_user_adjusted(range_control: Range) -> bool:
	if _current_input_frame != Engine.get_process_frames():
		return false
	if _current_input_kind == &"pointer_button" or _current_input_kind == &"pointer_drag" or _current_input_kind == &"pointer_wheel":
		return range_control.get_global_rect().has_point(_pointer_position)
	if _current_input_kind != &"navigation" and _current_input_kind != &"range":
		return false
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == null or (focus_owner != range_control and not range_control.is_ancestor_of(focus_owner)):
		return false
	return true


func _play_automatic(cue: StringName, control: Control, screen: Control, debounce_ms: int) -> bool:
	if not _is_eligible(control, screen):
		return false
	if cue == &"press" or cue == &"select" or cue == &"focus" or cue == &"hover":
		if Engine.get_process_frames() == _last_semantic_frame:
			return false
	var source_id := control.get_instance_id()
	var shared_cue := &"navigation" if cue == &"focus" or cue == &"hover" else cue
	var previous: Dictionary = _last_automatic_ms.get(source_id, {})
	var now_ms := Time.get_ticks_msec()
	if now_ms - int(previous.get(shared_cue, -1000000)) < debounce_ms:
		return false
	if not _request_cue(cue, control):
		return false
	previous[shared_cue] = now_ms
	_last_automatic_ms[source_id] = previous
	return true


func _is_eligible(control: Control, screen: Control) -> bool:
	if control == null or screen == null or not is_instance_valid(control) or not is_instance_valid(screen):
		return false
	if not control.is_inside_tree() or not control.is_visible_in_tree() or control.is_queued_for_deletion():
		return false
	if control != screen and not screen.is_ancestor_of(control):
		return false
	if _is_excluded(control, screen):
		return false
	if _top_screen_provider.is_valid():
		var top_screen: Variant = _top_screen_provider.call()
		if not is_instance_valid(top_screen) or top_screen != screen:
			return false
	else:
		return false
	var observed: Dictionary = _observed_controls.get(control.get_instance_id(), {})
	if observed.is_empty():
		return false
	for property_name: StringName in observed.checks:
		if property_name == &"editable" and not bool(control.get(property_name)):
			return false
		if property_name == &"disabled" and bool(control.get(property_name)):
			return false
	return true


func _request_cue(cue: StringName, source: Object = null) -> bool:
	if _retiring:
		return false
	var stream: AudioStream = STREAM_BY_CUE.get(cue)
	if stream == null or _voices.is_empty():
		return false
	# Browsing never talks over the outcome the pilot is trying to understand.
	if not _is_semantic_cue(cue):
		for index: int in range(_voices.size()):
			if _voices[index].playing and _is_semantic_cue(_voice_cues[index]):
				_dropped_voice_count += 1
				return false
	var available_voice := -1
	for voice_index: int in range(_voices.size()):
		if not _voices[voice_index].playing:
			available_voice = voice_index
			break
	if available_voice < 0 and _is_semantic_cue(cue):
		for voice_index: int in range(_voices.size()):
			if not _is_semantic_cue(_voice_cues[voice_index]):
				_voices[voice_index].stop()
				available_voice = voice_index
				break
	# A decision must remain audible even during two rapid transitions. Replace
	# the oldest tail instead of dropping the newest confirmation/error.
	if available_voice < 0 and _is_semantic_cue(cue):
		for voice_index: int in range(_voices.size()):
			if available_voice < 0 or _voice_started_ms[voice_index] < _voice_started_ms[available_voice]:
				available_voice = voice_index
		_voices[available_voice].stop()
	if available_voice < 0:
		_dropped_voice_count += 1
		return false
	var player := _voices[available_voice]
	_cancel_fade(available_voice)
	if _is_semantic_cue(cue):
		for index: int in range(_voices.size()):
			if index != available_voice and _voices[index].playing:
				_retire_voice(index)
	player.stream = NAVIGATION_STREAMS[_navigation_step % NAVIGATION_STREAMS.size()] \
		if cue == &"focus" or cue == &"hover" else stream
	player.pitch_scale = _pitch_for(cue)
	_voice_cues[available_voice] = cue
	_voice_started_ms[available_voice] = Time.get_ticks_msec()
	_update_voice_volume(available_voice)
	var source_id := source.get_instance_id() if source != null and is_instance_valid(source) else 0
	_cue_counts[cue] = int(_cue_counts.get(cue, 0)) + 1
	cue_requested.emit(cue, source_id)
	if _volume > 0.0:
		player.play()
	return true


func _pitch_for(cue: StringName) -> float:
	if cue == &"focus" or cue == &"hover":
		var pitch := NAVIGATION_PITCHES[_navigation_step % NAVIGATION_PITCHES.size()]
		_navigation_step += 1
		return pitch - 0.035 if cue == &"hover" else pitch
	if cue == &"press":
		var pitch := PRESS_PITCHES[_press_step % PRESS_PITCHES.size()]
		_press_step += 1
		return pitch
	return float(CUE_PITCH.get(cue, 1.0))


func _is_semantic_cue(cue: StringName) -> bool:
	return SEMANTIC_PRIORITY.has(cue)


func _cancel_fade(index: int) -> void:
	if _voice_fades[index] != null:
		_voice_fades[index].kill()
		_voice_fades[index] = null


func _retire_voice(index: int) -> void:
	_cancel_fade(index)
	var fade := create_tween()
	fade.set_ignore_time_scale(true)
	_voice_fades[index] = fade
	fade.tween_property(_voices[index], "volume_db", -80.0, TAIL_FADE_SECONDS)
	fade.tween_callback(func() -> void:
		_voices[index].stop()
		_voice_fades[index] = null)


func _update_voice_volume(voice_index: int) -> void:
	if voice_index < 0 or voice_index >= _voices.size():
		return
	var cue: StringName = _voice_cues[voice_index]
	var gain := float(GAIN_BY_CUE.get(cue, 0.0))
	var scaled_volume := _volume * gain
	_voices[voice_index].volume_db = linear_to_db(scaled_volume) if scaled_volume > 0.0 else -80.0


func _input(event: InputEvent) -> void:
	var frame := Engine.get_process_frames()
	if event is InputEventMouseMotion:
		_pointer_position = (event as InputEventMouseMotion).position
		_current_input_frame = frame
		_current_input_kind = &"pointer_drag" if _left_mouse_down else &"pointer_motion"
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		_pointer_position = mouse_event.position
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_left_mouse_down = mouse_event.pressed
			_current_input_kind = &"pointer_button"
		elif mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_current_input_kind = &"pointer_wheel"
		else:
			return
		_current_input_frame = frame
		return
	if _event_matches_actions(event, NAVIGATION_ACTIONS):
		_current_input_frame = frame
		_current_input_kind = &"navigation"
	elif _event_matches_actions(event, RANGE_ACTIONS):
		_current_input_frame = frame
		_current_input_kind = &"range"


func _event_matches_actions(event: InputEvent, actions: PackedStringArray) -> bool:
	for action_name: String in actions:
		if event.is_action_pressed(action_name, false):
			return true
	return false


func _on_screen_tree_exiting(screen_id: int) -> void:
	_observed_screens.erase(screen_id)
	if _observed_screens.is_empty() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_control_tree_exiting(control_id: int) -> void:
	var observed: Dictionary = _observed_controls.get(control_id, {})
	for connection: Dictionary in observed.get("connections", []):
		var control_signal: Signal = connection.event_signal
		if control_signal.is_connected(connection.callback):
			control_signal.disconnect(connection.callback)
	_observed_controls.erase(control_id)
	_last_automatic_ms.erase(control_id)
