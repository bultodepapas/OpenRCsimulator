extends Node3D

## AUD-16: recorded servo and retract cues driven by accepted actuator motion.
## This node only reads detached snapshots; it owns no simulation state.
const Motion := preload("res://audio/mechanical_motion.gd")
const SoundscapeScript := preload("res://audio/soundscape.gd")
const ASSET_PATH: String = "res://assets/audio/mechanical/"
const MAX_MOTION_VOICES: int = 6
const MAX_EVENT_VOICES: int = 2
const MAX_DISTANCE_M: float = 60.0
const DISTANCE_FADE_START_M: float = 39.0
const SERVO_REFERENCE_RATE_DEG_S: float = 180.0
const GEAR_REFERENCE_RATE_FRACTION_S: float = 0.6
const SERVO_BASE_GAIN: float = 0.16
const RETRACT_BASE_GAIN: float = 0.22
const PAUSE_FADE_S: float = 0.08
const STALE_TICK_LIMIT_S: float = 0.2
const EVENT_RELEASE_S: float = 0.02
const SERVO_PROFILE_PITCH: Dictionary = {"standard": 1.0, "high_torque": 0.82}

var _owner: Node
var _soundscape: Node
var _bus: StringName = &"Master"
var _config: Dictionary = {servo_type = "standard", servo_level = 1.0, retract_type = "electric"}
var _motion_state: Dictionary = {}
var _motion_players: Dictionary = {}
var _event_players: Array[AudioStreamPlayer3D] = []
var _event_roles: Array[String] = []
var _event_source_ids: Array[String] = []
var _event_base_gains: Array[float] = []
var _event_envelopes: Array[float] = []
var _event_releasing: Array[bool] = []
var _pending_events: Array[Dictionary] = []
var _event_streams: Dictionary = {}
var _servo_loop: AudioStreamWAV
var _servo_start_takes: Array[AudioStreamWAV] = []
var _servo_stop_takes: Array[AudioStreamWAV] = []
var _gear_loop: AudioStreamWAV
var _gear_move_one_shot: AudioStreamWAV
var _gear_start: AudioStreamWAV
var _gear_lock: AudioStreamWAV
var _missing_assets: Array[String] = []
var _event_take_counters: Dictionary = {}
var _gesture_counters: Dictionary = {}
var _gesture_variations: Dictionary = {}
var _scene_gain: float = 1.0
var _engine_mask: float = 1.0
var _stale_tick_s: float = 0.0
var _last_targets: Dictionary = {}
var _events_played: int = 0
var _events_dropped: int = 0
var _far_culled_events: int = 0
var _far_culled_motion_updates: int = 0
var _stale_tick_resets: int = 0
var _reset_count: int = 0


## Configure with a scene owner, an existing scene-local bus, and a validated profile.
func configure(owner: Node, bus: StringName, config: Dictionary) -> void:
	_dispose_players()
	_owner = owner
	_config = _validated_config(config)
	_bus = bus if not str(bus).is_empty() else &"Master"
	_motion_state.clear()
	_load_profile_assets()
	if is_instance_valid(owner) and get_parent() != owner:
		if get_parent() != null:
			reparent(owner)
		else:
			owner.add_child(self)
	_apply_bus(_bus)
	reset()


## Follow the scene Soundscape bus over Workshop detach/reattach lifecycles.
func bind_soundscape(soundscape: Node) -> void:
	if is_instance_valid(_soundscape) and _soundscape != soundscape:
		_disconnect_soundscape()
	_soundscape = soundscape
	_connect_soundscape()
	if is_instance_valid(_soundscape) and _soundscape.has_method("output_bus"):
		var soundscape_bus: StringName = StringName(_soundscape.call("output_bus"))
		if not str(soundscape_bus).is_empty() and soundscape_bus != _bus:
			rebind(soundscape_bus)


func _connect_soundscape() -> void:
	if not is_instance_valid(_soundscape):
		return
	var release_callable := Callable(self, "_on_buses_releasing")
	if _soundscape.has_signal("buses_releasing") and not _soundscape.is_connected("buses_releasing", release_callable):
		_soundscape.connect("buses_releasing", release_callable)
	var entered_callable := Callable(self, "_on_soundscape_entered")
	if not _soundscape.is_connected("tree_entered", entered_callable):
		_soundscape.tree_entered.connect(entered_callable)


func _disconnect_soundscape() -> void:
	if not is_instance_valid(_soundscape):
		return
	var release_callable := Callable(self, "_on_buses_releasing")
	if _soundscape.has_signal("buses_releasing") and _soundscape.is_connected("buses_releasing", release_callable):
		_soundscape.disconnect("buses_releasing", release_callable)
	var entered_callable := Callable(self, "_on_soundscape_entered")
	if _soundscape.is_connected("tree_entered", entered_callable):
		_soundscape.tree_entered.disconnect(entered_callable)


func _on_soundscape_entered() -> void:
	call_deferred("_refresh_soundscape_bus")


func _refresh_soundscape_bus() -> void:
	if not str(_bus).is_empty():
		return
	if is_instance_valid(_soundscape) and _soundscape.has_method("output_bus"):
		rebind(StringName(_soundscape.call("output_bus")))


## Rebind after a scene-local audio bus is recreated. Observer reset prevents stale transients.
func rebind(bus: StringName) -> void:
	if str(bus).is_empty():
		return
	var changed: bool = bus != _bus
	_bus = bus
	_apply_bus(_bus)
	if changed:
		reset()


func _apply_bus(bus: StringName) -> void:
	var destination: StringName = bus
	if AudioServer.get_bus_index(destination) < 0:
		destination = &"Master"
	for slot: Dictionary in _motion_players.values():
		var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if player != null:
			player.bus = destination
	for player: AudioStreamPlayer3D in _event_players:
		player.bus = destination


## Consume only post-step actuator samples. Repeated render frames do not create new events.
func update_sound(snapshot: Dictionary, delta: float) -> void:
	if not is_inside_tree():
		return
	if str(_bus).is_empty():
		_refresh_soundscape_bus()
	var safe_delta: float = delta if is_finite(delta) and delta > 0.0 else 0.0
	var dt: float = clampf(safe_delta, 0.0, 0.1)
	var paused: bool = bool(snapshot.get("paused", false))
	var incoming_tick: int = int(snapshot.get("tick", -1)) if _integer_tick(snapshot.get("tick", null)) else -1
	if incoming_tick < 0:
		_motion_state.clear()
		_stale_tick_s = 0.0
		_fade_motion(dt, true)
		_stop_event_voices()
		_last_targets = {valid = false, active_motion_voices = 0}
		return
	# Beyond audible range, retain no travel history to replay on return. This avoids
	# building the observer's channel/event dictionaries for distant aircraft.
	if not paused and _all_sources_distant(snapshot):
		_motion_state.clear()
		_stale_tick_s = 0.0
		_engine_mask = _unit(snapshot.get("engine_mask", 1.0), 1.0)
		_fade_motion(dt, false)
		_stop_event_voices()
		_far_culled_motion_updates += 1
		_last_targets = {valid = true, tick = incoming_tick, paused = false, far_culled = true,
			engine_mask = _engine_mask, active_motion_voices = 0, listener = snapshot.get("listener", Vector3.ZERO)}
		return
	if paused or _motion_state.is_empty():
		_stale_tick_s = 0.0
	elif incoming_tick < int(_motion_state.get("tick", -1)):
		_stale_tick_s = 0.0
	elif incoming_tick == int(_motion_state.get("tick", -1)):
		_stale_tick_s += dt
		if _stale_tick_s >= STALE_TICK_LIMIT_S:
			_motion_state.clear()
			_stale_tick_s = 0.0
			_stale_tick_resets += 1
	else:
		_stale_tick_s = 0.0
	var result: Dictionary = Motion.observe(_motion_state, snapshot)
	if not bool(result.get("valid", false)):
		_motion_state.clear()
		_stale_tick_s = 0.0
		_fade_motion(dt, true)
		_stop_event_voices()
		_last_targets = {valid = false, active_motion_voices = 0}
		return
	_motion_state = result.state
	if bool(result.get("tick_advanced", false)) or paused:
		_stale_tick_s = 0.0
	var listener_value: Variant = snapshot.get("listener", null)
	var listener_valid: bool = Motion.finite_vector(listener_value)
	var listener: Vector3 = listener_value if listener_valid else Vector3.ZERO
	_engine_mask = _unit(snapshot.get("engine_mask", 1.0), 1.0)
	var servo_level: float = float(_config.get("servo_level", 1.0))
	if paused:
		_scene_gain = maxf(0.0, _scene_gain - dt / PAUSE_FADE_S)
		# A queued reversal must not start while the old cue fades into pause.
		for index: int in _pending_events.size():
			_pending_events[index] = {}
	else:
		_scene_gain = minf(1.0, _scene_gain + dt / PAUSE_FADE_S)
	var source_positions: Dictionary = _source_positions(result)
	var can_play_events: bool = not paused and not bool(result.get("primed", false)) \
		and bool(result.get("tick_advanced", false)) and listener_valid
	if can_play_events:
		_process_events(result.get("events", []), source_positions, listener, servo_level)
	var targets: Dictionary = {}
	var active: int = 0
	var far_culled: bool = false
	for motion_value: Variant in result.get("channels", []):
		if not motion_value is Dictionary:
			continue
		var motion: Dictionary = motion_value
		var id: String = str(motion.get("id", ""))
		if id.is_empty():
			continue
		var key: String = "servo:" + id
		targets[key] = true
		var source: Variant = motion.get("position", Vector3.ZERO)
		var source_valid: bool = bool(motion.get("position_valid", false)) and Motion.finite_vector(source)
		var distance: float = source.distance_to(listener) if source_valid and listener_valid else INF
		var near: bool = source_valid and listener_valid and distance < MAX_DISTANCE_M
		var target_gain: float = 0.0
		var target_pitch: float = 1.0
		if near and not paused and bool(motion.get("moving", false)):
			target_gain = _servo_gain(float(motion.get("speed_per_s", 0.0)), servo_level) \
				* _engine_mask * _distance_gain(distance)
			target_pitch = _servo_pitch(float(motion.get("speed_per_s", 0.0)))
		elif source_valid and not near:
			far_culled = true
		var player: AudioStreamPlayer3D = null
		if target_gain > 0.0001 or _motion_players.has(key):
			player = _ensure_motion_player(key, _servo_loop)
		if player != null:
			_apply_motion_voice(key, id, player, source if source_valid else Vector3.ZERO,
				target_gain, target_pitch, dt)
			if target_gain > 0.001 and float(_motion_players.get(key, {}).get("gain", 0.0)) > 0.001:
				active += 1
	var gear_motion: Dictionary = result.get("gear", {})
	if not gear_motion.is_empty():
		targets["gear"] = true
		var gear_source: Variant = gear_motion.get("position", Vector3.ZERO)
		var gear_source_valid: bool = bool(gear_motion.get("position_valid", false)) and Motion.finite_vector(gear_source)
		var gear_distance: float = gear_source.distance_to(listener) if gear_source_valid and listener_valid else INF
		var gear_near: bool = gear_source_valid and listener_valid and gear_distance < MAX_DISTANCE_M
		var gear_target: float = 0.0
		var gear_pitch: float = 1.0
		if gear_near and not paused and bool(gear_motion.get("moving", false)) and _gear_loop != null:
			gear_target = _gear_gain(float(gear_motion.get("speed_per_s", 0.0))) \
				* _engine_mask * _distance_gain(gear_distance)
			gear_pitch = _gear_pitch(float(gear_motion.get("speed_per_s", 0.0)))
		elif gear_source_valid and not gear_near:
			far_culled = true
		var gear_player: AudioStreamPlayer3D = null
		if gear_target > 0.0001 or _motion_players.has("gear"):
			gear_player = _ensure_motion_player("gear", _gear_loop)
		if gear_player != null:
			_apply_motion_voice("gear", "gear", gear_player,
				gear_source if gear_source_valid else Vector3.ZERO, gear_target, gear_pitch, dt)
			if gear_target > 0.001 and float(_motion_players.get("gear", {}).get("gain", 0.0)) > 0.001:
				active += 1
	for key_value: Variant in _motion_players.keys():
		var key: String = str(key_value)
		if targets.has(key):
			continue
		var slot: Dictionary = _motion_players.get(key, {})
		var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if player != null:
			_apply_motion_voice(key, key.trim_prefix("servo:") if key.begins_with("servo:") else "gear",
				player, player.global_position, 0.0, float(slot.get("pitch", 1.0)), dt)
	if far_culled:
		_far_culled_motion_updates += 1
	_update_event_voices(source_positions, listener, listener_valid, dt)
	if _scene_gain <= 0.001:
		_stop_event_voices()
	_last_targets = {valid = true, tick = incoming_tick, paused = paused,
		engine_mask = _engine_mask, listener_valid = listener_valid,
		active_motion_voices = active, far_culled = far_culled,
		stale_tick_s = _stale_tick_s, motion_voice_count = _motion_players.size(), listener = listener}


func _all_sources_distant(snapshot: Dictionary) -> bool:
	var listener: Variant = snapshot.get("listener", null)
	if not Motion.finite_vector(listener): return false
	var channels: Variant = snapshot.get("channels", [])
	if channels is Array:
		for channel: Variant in channels:
			if channel is Dictionary:
				var position: Variant = channel.get("position", null)
				if Motion.finite_vector(position) and position.distance_squared_to(listener) < MAX_DISTANCE_M * MAX_DISTANCE_M:
					return false
	var gear: Variant = snapshot.get("gear", {})
	if gear is Dictionary and bool(gear.get("available", true)):
		var position: Variant = gear.get("position", null)
		if Motion.finite_vector(position) and position.distance_squared_to(listener) < MAX_DISTANCE_M * MAX_DISTANCE_M:
			return false
	return true


func reset() -> void:
	_motion_state.clear()
	_scene_gain = 1.0
	_engine_mask = 1.0
	_stale_tick_s = 0.0
	_gesture_counters.clear()
	_gesture_variations.clear()
	_reset_count += 1
	for key_value: Variant in _motion_players.keys():
		var key: String = str(key_value)
		var slot: Dictionary = _motion_players[key]
		var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if player != null:
			player.volume_db = -80.0
			player.stop()
		slot["gain"] = 0.0
		slot["pitch"] = 1.0
	for player: AudioStreamPlayer3D in _event_players:
		player.volume_db = -80.0
		player.stop()
	_clear_event_metadata()
	_last_targets = {valid = false, active_motion_voices = 0}


func diagnostics() -> Dictionary:
	var active: int = 0
	for slot: Dictionary in _motion_players.values():
		var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if player != null and player.playing:
			active += 1
	var playing_events: int = 0
	var pending_count: int = 0
	for pending: Dictionary in _pending_events:
		if not pending.is_empty(): pending_count += 1
	for player: AudioStreamPlayer3D in _event_players:
		if player.playing:
			playing_events += 1
	return {motion_voice_count = _motion_players.size(), motion_voice_limit = MAX_MOTION_VOICES,
		event_voice_count = _event_players.size(), event_voice_limit = MAX_EVENT_VOICES,
		active_motion_voices = active, playing_event_voices = playing_events,
		pending_event_count = pending_count,
		events_played = _events_played, events_dropped = _events_dropped,
		far_culled_events = _far_culled_events, far_culled_motion_updates = _far_culled_motion_updates,
		stale_tick_resets = _stale_tick_resets, missing_assets = _missing_assets.duplicate(),
		last_targets = _last_targets.duplicate(), reset_count = _reset_count}


func _load_profile_assets() -> void:
	_missing_assets.clear()
	_event_take_counters.clear()
	var servo_type: String = str(_config.get("servo_type", "standard"))
	var retract_type: String = str(_config.get("retract_type", "electric"))
	_servo_loop = _load_wav("servo_loop", ASSET_PATH + "servo_" + servo_type + "_loop.wav", true)
	_servo_start_takes = _load_takes("servo_start", servo_type, "start")
	_servo_stop_takes = _load_takes("servo_stop", servo_type, "stop")
	_gear_loop = _load_wav("retract_loop", ASSET_PATH + "retract_" + retract_type + "_loop.wav", true)
	if retract_type == "electric":
		_gear_move_one_shot = _load_wav("retract_move", ASSET_PATH + "retract_electric_move.wav", false, _gear_loop != null)
		_gear_start = _load_wav("retract_start", ASSET_PATH + "retract_electric_start.wav", false)
		_gear_lock = _load_wav("retract_lock", ASSET_PATH + "retract_electric_lock.wav", false)
	else:
		_gear_move_one_shot = _load_wav("retract_hiss", ASSET_PATH + "retract_pneumatic_hiss.wav", false)
		_gear_start = _load_wav("retract_valve", ASSET_PATH + "retract_pneumatic_valve.wav", false)
		_gear_lock = _load_wav("retract_lock", ASSET_PATH + "retract_pneumatic_lock.wav", false)
	_event_streams = {
		"servo_start": _servo_start_takes,
		"servo_stop": _servo_stop_takes,
		"gear_move": _single_take(_gear_move_one_shot),
		"gear_start": _single_take(_gear_start),
		"gear_lock": _single_take(_gear_lock),
	}
	_ensure_event_voices()


func _load_takes(role: String, servo_type: String, gesture: String) -> Array[AudioStreamWAV]:
	var takes: Array[AudioStreamWAV] = []
	var stem: String = ASSET_PATH + "servo_" + servo_type + "_" + gesture
	var primary: AudioStreamWAV = _load_wav(role, stem + ".wav", false)
	if primary != null:
		takes.append(primary)
	var alternate: AudioStreamWAV = _load_wav(role + "_02", stem + "_02.wav", false, true)
	if alternate != null:
		takes.append(alternate)
	return takes


func _load_wav(role: String, path: String, looped: bool, optional: bool = false) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		if not optional:
			_missing_assets.append(role + ":" + path)
		return null
	var resource: Resource = ResourceLoader.load(path)
	var source: AudioStreamWAV = resource as AudioStreamWAV
	if source == null:
		if not optional:
			_missing_assets.append(role + ":not_pcm_wav:" + path)
		return null
	if looped:
		return SoundscapeScript.seamless_loop(source)
	var one_shot: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	one_shot.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return one_shot


func _single_take(stream: AudioStreamWAV) -> Array[AudioStreamWAV]:
	var takes: Array[AudioStreamWAV] = []
	if stream != null:
		takes.append(stream)
	return takes


func _ensure_event_voices() -> void:
	var has_event_asset: bool = false
	for takes_value: Variant in _event_streams.values():
		if takes_value is Array and not takes_value.is_empty():
			has_event_asset = true
			break
	if not has_event_asset:
		return
	while _event_players.size() < MAX_EVENT_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.name = "MechanicalEvent_%d" % _event_players.size()
		_setup_player(player)
		add_child(player)
		_event_players.append(player)
		_event_roles.append("")
		_event_source_ids.append("")
		_event_base_gains.append(0.0)
		_event_envelopes.append(1.0)
		_event_releasing.append(false)
		_pending_events.append({})


func _ensure_motion_player(key: String, stream: AudioStreamWAV) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var existing: Dictionary = _motion_players.get(key, {})
	if not existing.is_empty():
		var found: AudioStreamPlayer3D = existing.get("player") as AudioStreamPlayer3D
		if found != null:
			if found.stream != stream:
				found.volume_db = -80.0
				found.stop()
				found.stream = stream
				existing["gain"] = 0.0
			return found
		_motion_players.erase(key)
	if _motion_players.size() >= MAX_MOTION_VOICES:
		for old_key_value: Variant in _motion_players.keys():
			var old_key: String = str(old_key_value)
			var idle_slot: Dictionary = _motion_players.get(old_key, {})
			var idle_player: AudioStreamPlayer3D = idle_slot.get("player") as AudioStreamPlayer3D
			if idle_player == null or idle_player.playing or float(idle_slot.get("gain", 0.0)) > 0.0002:
				continue
			_motion_players.erase(old_key)
			idle_slot["gain"] = 0.0
			idle_slot["pitch"] = 1.0
			idle_slot["offset"] = 0.0
			idle_player.name = "Mechanical_" + key.replace(":", "_")
			idle_player.stream = stream
			_motion_players[key] = idle_slot
			return idle_player
		return null
	var player := AudioStreamPlayer3D.new()
	player.name = "Mechanical_" + key.replace(":", "_")
	player.stream = stream
	_setup_player(player)
	add_child(player)
	_motion_players[key] = {player = player, gain = 0.0, pitch = 1.0, offset = 0.0}
	return player


func _setup_player(player: AudioStreamPlayer3D) -> void:
	player.bus = _bus if AudioServer.get_bus_index(_bus) >= 0 else &"Master"
	# Manual attenuation avoids Godot's close-range max_db clamp overpowering these quiet sources.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = 0.0
	player.max_db = 0.0
	player.attenuation_filter_db = 0.0
	player.panning_strength = 0.75
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.volume_db = -80.0
	player.autoplay = false
	player.max_polyphony = 1


func _apply_motion_voice(key: String, source_id: String, player: AudioStreamPlayer3D,
		position: Vector3, target_gain: float, target_pitch: float, dt: float) -> void:
	var slot: Dictionary = _motion_players.get(key, {})
	if slot.is_empty():
		return
	player.global_position = position
	var current_gain: float = float(slot.get("gain", 0.0))
	var time_constant: float = 0.035 if target_gain > current_gain else 0.085
	var alpha: float = 1.0 - exp(-dt / time_constant) if dt > 0.0 else 0.0
	current_gain = lerpf(current_gain, clampf(target_gain, 0.0, 1.0), alpha)
	var variation: Dictionary = _gesture_variations.get(source_id, {pitch = 1.0, phase = 0.0})
	var varied_pitch: float = target_pitch * float(variation.get("pitch", 1.0))
	var pitch: float = lerpf(float(slot.get("pitch", 1.0)), varied_pitch,
		1.0 - exp(-dt / 0.04)) if dt > 0.0 else varied_pitch
	slot["gain"] = current_gain
	slot["pitch"] = pitch
	player.volume_db = linear_to_db(maxf(current_gain * _scene_gain, 0.00001))
	player.pitch_scale = pitch
	if target_gain > 0.0001 and not player.playing:
		var length: float = maxf(player.stream.get_length(), 0.001)
		slot["offset"] = length * clampf(float(variation.get("phase", 0.0)), 0.0, 0.999)
		player.play(float(slot.get("offset", 0.0)))
	elif current_gain <= 0.0002 and target_gain <= 0.0001 and player.playing:
		_stop_motion_player(key)


func _process_events(events: Array, source_positions: Dictionary, listener: Vector3,
		servo_level: float) -> void:
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var source_id: String = str(event.get("id", "gear"))
		var source: Dictionary = source_positions.get(source_id, {})
		if source.is_empty() or not bool(source.get("valid", false)):
			continue
		var position: Vector3 = source.get("position", Vector3.ZERO)
		var distance_gain: float = _distance_gain(position.distance_to(listener))
		if distance_gain <= 0.0001:
			_far_culled_events += 1
			continue
		var speed: float = float(event.get("speed_per_s", 0.0))
		var gain: float = 0.0
		var pitch: float = 1.0
		var role: String = ""
		if str(event.get("system", "")) == "servo":
			var event_kind: String = str(event.get("event", ""))
			if event_kind in ["start", "reverse"]:
				_advance_gesture(source_id)
				role = "servo_start"
			elif event_kind == "stop":
				role = "servo_stop"
			gain = _servo_gain(speed, servo_level)
			pitch = _servo_pitch(speed) * float(_gesture_variations.get(source_id, {}).get("pitch", 1.0))
		else:
			var gear_event: String = str(event.get("event", ""))
			if gear_event == "stop":
				_cancel_source_events(source_id)
			gain = _gear_gain(speed)
			pitch = _gear_pitch(speed)
			if gear_event in ["start", "reverse"]:
				_advance_gesture("gear")
				pitch *= float(_gesture_variations.get("gear", {}).get("pitch", 1.0))
				if _gear_loop != null:
					role = "gear_start"
				elif _has_event_take("gear_move"):
					role = "gear_move"
				else:
					role = "gear_start"
			elif gear_event == "lock":
				role = "gear_lock"
		if not role.is_empty():
			_play_event(role, source_id, position, listener, gain, pitch)


func _play_event(role: String, source_id: String, position: Vector3, listener: Vector3,
		gain: float, pitch: float) -> void:
	if _event_players.is_empty() or gain <= 0.0001:
		return
	var effective_gain: float = gain * _engine_mask * _distance_gain(position.distance_to(listener)) * _scene_gain
	if effective_gain <= 0.0001:
		return
	var chosen: int = -1
	for index: int in range(_event_players.size()):
		if str(_pending_events[index].get("source", "")) == source_id or \
				(_pending_events[index].is_empty() and _event_source_ids[index] == source_id):
			chosen = index
			break
	if chosen < 0:
		for index: int in range(_event_players.size()):
			if not _event_players[index].playing:
				chosen = index
				break
	if chosen < 0:
		var lowest_priority: int = _event_priority(role)
		for index: int in range(_event_players.size()):
			var pending_role: String = str(_pending_events[index].get("role", _event_roles[index]))
			var priority: int = _event_priority(pending_role)
			if priority < lowest_priority:
				lowest_priority = priority
				chosen = index
	if chosen < 0:
		_events_dropped += 1
		return
	var stream: AudioStreamWAV = _next_event_take(role)
	if stream == null:
		return
	var cue: Dictionary = {role = role, source = source_id, stream = stream,
		position = position, pitch = pitch, gain = gain}
	if _event_players[chosen].playing:
		# Retire the previous cue before replacing it: bounded voices, no hard waveform cut.
		_pending_events[chosen] = cue
		_event_releasing[chosen] = true
	else:
		_begin_event(chosen, cue, effective_gain)


func _event_priority(role: String) -> int:
	return 3 if role == "gear_lock" else (2 if role.begins_with("gear_") else (1 if role == "servo_start" else 0))


func _cancel_source_events(source_id: String) -> void:
	for index: int in _event_players.size():
		if str(_pending_events[index].get("source", "")) == source_id:
			_pending_events[index] = {}
		if _event_source_ids[index] == source_id:
			_event_releasing[index] = true


func _begin_event(index: int, cue: Dictionary, effective_gain: float) -> void:
	var player: AudioStreamPlayer3D = _event_players[index]
	player.stream = cue.stream
	player.global_position = cue.position
	player.pitch_scale = clampf(float(cue.pitch), 0.55, 1.5)
	player.volume_db = linear_to_db(maxf(effective_gain, 0.00001))
	_event_roles[index] = cue.role
	_event_source_ids[index] = cue.source
	_event_base_gains[index] = cue.gain
	_event_envelopes[index] = 1.0
	_event_releasing[index] = false
	_pending_events[index] = {}
	player.play()
	_events_played += 1


func _update_event_voices(source_positions: Dictionary, listener: Vector3, listener_valid: bool, dt: float) -> void:
	for index: int in range(_event_players.size()):
		var player: AudioStreamPlayer3D = _event_players[index]
		if _event_releasing[index]:
			_event_envelopes[index] = maxf(0.0, _event_envelopes[index] - dt / EVENT_RELEASE_S)
			if _event_envelopes[index] <= 0.0:
				player.volume_db = -80.0
				player.stop()
		if not player.playing and not _pending_events[index].is_empty():
			var cue: Dictionary = _pending_events[index]
			var pending_source: Dictionary = source_positions.get(str(cue.source), {})
			_pending_events[index] = {}
			if listener_valid and bool(pending_source.get("valid", false)) and _scene_gain > 0.001:
				cue.position = pending_source.position
				var pending_gain: float = float(cue.gain) * _engine_mask * _scene_gain * _distance_gain(cue.position.distance_to(listener))
				if pending_gain > 0.0001:
					_begin_event(index, cue, pending_gain)
		if not player.playing:
			_event_roles[index] = ""
			_event_source_ids[index] = ""
			_event_base_gains[index] = 0.0
			player.volume_db = -80.0
			continue
		var source: Dictionary = source_positions.get(_event_source_ids[index], {})
		if not listener_valid or source.is_empty() or not bool(source.get("valid", false)):
			player.volume_db = -80.0
			player.stop()
			_event_roles[index] = ""
			_event_source_ids[index] = ""
			_event_base_gains[index] = 0.0
			continue
		var position: Vector3 = source.get("position", Vector3.ZERO)
		player.global_position = position
		var path_gain: float = _distance_gain(position.distance_to(listener))
		if path_gain <= 0.0001:
			player.volume_db = -80.0
			player.stop()
			_event_roles[index] = ""
			_event_source_ids[index] = ""
			_event_base_gains[index] = 0.0
			continue
		var audible_gain: float = _event_base_gains[index] * _event_envelopes[index] * _engine_mask * path_gain * _scene_gain
		player.volume_db = linear_to_db(maxf(audible_gain, 0.00001))


func _fade_motion(delta: float, immediate: bool) -> void:
	_scene_gain = 0.0 if immediate else maxf(0.0, _scene_gain - clampf(delta, 0.0, 0.1) / PAUSE_FADE_S)
	for key_value: Variant in _motion_players.keys():
		var key: String = str(key_value)
		var slot: Dictionary = _motion_players.get(key, {})
		var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if player == null:
			continue
		var gain: float = 0.0 if immediate else lerpf(float(slot.get("gain", 0.0)), 0.0,
			1.0 - exp(-clampf(delta, 0.0, 0.1) / PAUSE_FADE_S))
		slot["gain"] = gain
		player.volume_db = linear_to_db(maxf(gain * _scene_gain, 0.00001))
		if immediate or gain <= 0.0002:
			_stop_motion_player(key)
	if immediate or _scene_gain <= 0.001:
		_stop_event_voices()


func _stop_motion_player(key: String) -> void:
	var slot: Dictionary = _motion_players.get(key, {})
	if slot.is_empty():
		return
	var player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
	if player != null:
		player.volume_db = -80.0
		player.stop()
	slot["gain"] = 0.0


func _stop_event_voices() -> void:
	for player: AudioStreamPlayer3D in _event_players:
		player.volume_db = -80.0
		player.stop()
	_clear_event_metadata()


func _clear_event_metadata() -> void:
	_event_roles.fill("")
	_event_source_ids.fill("")
	_event_base_gains.fill(0.0)
	_event_envelopes.fill(1.0)
	_event_releasing.fill(false)
	for index: int in _pending_events.size():
		_pending_events[index] = {}


func _dispose_players() -> void:
	for slot: Dictionary in _motion_players.values():
		var motion_player: AudioStreamPlayer3D = slot.get("player") as AudioStreamPlayer3D
		if motion_player == null:
			continue
		motion_player.volume_db = -80.0
		motion_player.stop()
		if motion_player.get_parent() == self:
			remove_child(motion_player)
		motion_player.free()
	for player: AudioStreamPlayer3D in _event_players:
		player.volume_db = -80.0
		player.stop()
		if player.get_parent() == self:
			remove_child(player)
		player.free()
	_event_players.clear()
	_event_roles.clear()
	_event_source_ids.clear()
	_event_base_gains.clear()
	_event_envelopes.clear()
	_event_releasing.clear()
	_pending_events.clear()
	_motion_players.clear()


func _source_positions(result: Dictionary) -> Dictionary:
	var positions: Dictionary = {}
	for motion_value: Variant in result.get("channels", []):
		if not motion_value is Dictionary:
			continue
		var motion: Dictionary = motion_value
		var identity: String = str(motion.get("id", ""))
		if identity.is_empty():
			continue
		var position: Variant = motion.get("position", Vector3.ZERO)
		positions[identity] = {position = position if Motion.finite_vector(position) else Vector3.ZERO,
			valid = bool(motion.get("position_valid", false)) and Motion.finite_vector(position)}
	var gear: Dictionary = result.get("gear", {})
	if not gear.is_empty():
		var gear_position: Variant = gear.get("position", Vector3.ZERO)
		positions["gear"] = {position = gear_position if Motion.finite_vector(gear_position) else Vector3.ZERO,
			valid = bool(gear.get("position_valid", false)) and Motion.finite_vector(gear_position)}
	return positions


func _advance_gesture(identity: String) -> void:
	var serial: int = int(_gesture_counters.get(identity, 0)) + 1
	_gesture_counters[identity] = serial
	var stable_hash: int = int(identity.hash()) & 0x7fffffff
	var pitch_index: int = (stable_hash + serial * 313) % 1001
	var phase_index: int = (stable_hash + serial * 577) % 997
	_gesture_variations[identity] = {
		pitch = 0.98 + 0.04 * float(pitch_index) / 1000.0,
		phase = float(phase_index) / 997.0,
	}


func _next_event_take(role: String) -> AudioStreamWAV:
	var takes_value: Variant = _event_streams.get(role, [])
	if not takes_value is Array or takes_value.is_empty():
		return null
	var takes: Array = takes_value
	var index: int = int(_event_take_counters.get(role, 0))
	_event_take_counters[role] = index + 1
	return takes[index % takes.size()] as AudioStreamWAV


func _has_event_take(role: String) -> bool:
	var takes_value: Variant = _event_streams.get(role, [])
	return takes_value is Array and not takes_value.is_empty()


func _servo_gain(speed: float, servo_level: float) -> float:
	var speed_mix: float = sqrt(clampf(speed / SERVO_REFERENCE_RATE_DEG_S, 0.0, 1.0))
	return SERVO_BASE_GAIN * clampf(servo_level, 0.0, 1.0) * (0.2 + 0.8 * speed_mix)


func _servo_pitch(speed: float) -> float:
	var speed_mix: float = sqrt(clampf(speed / SERVO_REFERENCE_RATE_DEG_S, 0.0, 1.0))
	var profile_pitch: float = float(SERVO_PROFILE_PITCH.get(str(_config.get("servo_type", "standard")), 1.0))
	return clampf((0.78 + 0.48 * speed_mix) * profile_pitch, 0.55, 1.35)


func _gear_gain(speed: float) -> float:
	var speed_mix: float = sqrt(clampf(speed / GEAR_REFERENCE_RATE_FRACTION_S, 0.0, 1.0))
	return RETRACT_BASE_GAIN * (0.25 + 0.75 * speed_mix)


func _gear_pitch(speed: float) -> float:
	var speed_mix: float = sqrt(clampf(speed / GEAR_REFERENCE_RATE_FRACTION_S, 0.0, 1.0))
	return clampf(0.82 + 0.36 * speed_mix, 0.7, 1.35)


func _distance_gain(distance_m: float) -> float:
	if not is_finite(distance_m) or distance_m < 0.0 or distance_m >= MAX_DISTANCE_M:
		return 0.0
	var model_gain: float = 2.0 / maxf(distance_m, 2.0)
	var fade: float = 1.0 - smoothstep(DISTANCE_FADE_START_M, MAX_DISTANCE_M, distance_m)
	return model_gain * fade


func _validated_config(value: Dictionary) -> Dictionary:
	var raw: Dictionary = value
	if raw.get("mechanical_audio", null) is Dictionary:
		raw = raw.mechanical_audio
	var servo_type: String = str(raw.get("servo_type", "standard"))
	if servo_type not in ["standard", "high_torque"]:
		servo_type = "standard"
	var retract_type: String = str(raw.get("retract_type", "electric"))
	if retract_type not in ["electric", "pneumatic"]:
		retract_type = "electric"
	var level: Variant = raw.get("servo_level", 1.0)
	var servo_level: float = clampf(float(level), 0.0, 1.0) if typeof(level) in [TYPE_INT, TYPE_FLOAT] \
		and is_finite(float(level)) else 1.0
	return {servo_type = servo_type, servo_level = servo_level, retract_type = retract_type}


func _unit(value: Variant, fallback: float) -> float:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return fallback
	return clampf(float(value), 0.0, 1.0)


func _integer_tick(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0


func _on_buses_releasing() -> void:
	reset()
	_bus = StringName()


func _enter_tree() -> void:
	_connect_soundscape()
	if str(_bus).is_empty():
		call_deferred("_refresh_soundscape_bus")


func _exit_tree() -> void:
	reset()
	_disconnect_soundscape()
