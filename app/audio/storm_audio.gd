## FW-84. Bounded thunder queue on the existing AUD environment mix.
extends Node3D

const THUNDER_CLIP_PATH: String = "res://assets/audio/storm/thunder_01.ogg"
const ENVIRONMENT_BUS: StringName = &"OpenRC Environment"
const MAX_PENDING: int = 12
const MAX_VOICES: int = 3
const MAX_AUDIBLE_DISTANCE_M: float = 30000.0
const MAX_LISTENER_SPEED_MPS: float = 150.0
const CAMERA_CUT_CROSSFADE_S: float = 0.18
const FALLBACK_SOUND_SPEED_MPS: float = 343.0

var _players: Array[AudioStreamPlayer3D] = []
var _player_started_at: Array[float] = []
var _player_cut_at: Array[float] = []
var _player_gain: Array[float] = []
var _pending: Array[Dictionary] = []
var _seen: Dictionary = {}
var _last_listener: Vector3 = Vector3.ZERO
var _last_sim_time_s: float = -1.0
var _sound_speed_mps: float = FALLBACK_SOUND_SPEED_MPS
var _listener_primed: bool = false
var _volume: float = 0.7
var _enabled: bool = false
var _audio_allowed: bool = true


func configure(config: Dictionary) -> void:
	_enabled = str(config.get("preset", "classic")) == "electrical_storm"
	_volume = clampf(float(config.get("thunder_volume", 0.7)), 0.0, 1.0)
	if not _enabled or not _audio_allowed or _volume <= 0.0:
		_pending.clear()
		_stop_players()


func reset() -> void:
	_pending.clear()
	_seen.clear()
	_listener_primed = false
	_last_sim_time_s = -1.0
	_stop_players()


func set_sound_speed(value: float) -> void:
	# FlightAudio supplies its read-only temperature-derived sound speed.
	_sound_speed_mps = clampf(value, 300.0, 380.0)


func set_audio_enabled(enabled_value: bool) -> void:
	if _audio_allowed == enabled_value:
		return
	_audio_allowed = enabled_value
	if not _audio_allowed:
		reset()


func update_at(sim_time_s: float, listener_position: Vector3, paused: bool,
		sound_speed_mps: float = FALLBACK_SOUND_SPEED_MPS, new_events: Array[Dictionary] = []) -> void:
	if not _enabled or not _audio_allowed or _volume <= 0.0:
		return
	_ensure_players()
	_refresh_bus()
	var now_s: float = maxf(sim_time_s, 0.0)
	_sound_speed_mps = clampf(sound_speed_mps, 300.0, 380.0)
	for event: Dictionary in new_events:
		_queue_event(event, now_s, listener_position, _sound_speed_mps)
	if paused:
		for player: AudioStreamPlayer3D in _players:
			player.stream_paused = true
		_last_listener = listener_position
		_listener_primed = true
		_last_sim_time_s = now_s
		return
	for player: AudioStreamPlayer3D in _players:
		player.stream_paused = false
	if _last_sim_time_s >= 0.0 and now_s < _last_sim_time_s:
		reset()
		_last_sim_time_s = now_s
		_last_listener = listener_position
		_listener_primed = true
		return
	var elapsed_s: float = maxf(now_s - _last_sim_time_s, 1.0 / float(Engine.physics_ticks_per_second))
	var camera_cut: bool = _listener_primed and listener_position.distance_to(_last_listener) > MAX_LISTENER_SPEED_MPS * elapsed_s
	if camera_cut:
		for index: int in _players.size():
			if _players[index].playing:
				_player_cut_at[index] = now_s
		_recompute_pending_arrivals(now_s, listener_position, sound_speed_mps)
	_last_listener = listener_position
	_listener_primed = true
	_last_sim_time_s = now_s
	_update_active_fades(now_s)
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.arrival_time_s) < float(b.arrival_time_s))
	while not _pending.is_empty() and float(_pending[0].arrival_time_s) <= now_s:
		var pending_event: Dictionary = _pending.pop_front()
		_start_voice(pending_event, now_s)


func _queue_event(event: Dictionary, now_s: float, listener_position: Vector3, sound_speed_mps: float) -> void:
	var event_id: String = str(event.get("event_id", ""))
	if event_id.is_empty() or _seen.has(event_id):
		return
	var channel: Vector3 = _as_vector3(event.get("channel_world", PackedFloat64Array()))
	var emission_s: float = float(event.get("start_time_s", 0.0))
	var speed: float = clampf(sound_speed_mps, 300.0, 380.0)
	var distance_m: float = listener_position.distance_to(channel)
	if distance_m > MAX_AUDIBLE_DISTANCE_M:
		return
	var arrival_s: float = emission_s + distance_m / speed
	if arrival_s <= now_s:
		return # A late frame or camera cut must not replay thunder whose arrival has passed.
	_seen[event_id] = true
	if _seen.size() > 256:
		_seen.clear()
		_seen[event_id] = true
	_pending.append({
		"event_id": event_id,
		"emission_time_s": emission_s,
		"arrival_time_s": arrival_s,
		"channel_world": channel,
		"intensity": float(event.get("intensity", 1.0)),
	})
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.arrival_time_s) < float(b.arrival_time_s))
	while _pending.size() > MAX_PENDING:
		_pending.pop_back()


func _recompute_pending_arrivals(now_s: float, listener_position: Vector3, sound_speed_mps: float) -> void:
	var speed: float = clampf(sound_speed_mps, 300.0, 380.0)
	var remaining: Array[Dictionary] = []
	for event: Dictionary in _pending:
		var distance_m: float = listener_position.distance_to(event.channel_world)
		if distance_m > MAX_AUDIBLE_DISTANCE_M:
			continue
		var arrival_s: float = float(event.emission_time_s) + distance_m / speed
		if arrival_s > now_s:
			event.arrival_time_s = arrival_s
			remaining.append(event)
	_pending = remaining


func _start_voice(event: Dictionary, now_s: float) -> void:
	var chosen: int = -1
	for index: int in _players.size():
		if not _players[index].playing:
			chosen = index
			break
	if chosen < 0:
		var oldest_age: float = -1.0
		for index: int in _players.size():
			var age: float = now_s - _player_started_at[index]
			if age > oldest_age:
				oldest_age = age
				chosen = index
		if oldest_age < 0.35:
			return # Reserve headroom; a nearly simultaneous strike does not cut off the first crack.
	var player: AudioStreamPlayer3D = _players[chosen]
	player.stop()
	player.global_position = event.channel_world
	_player_gain[chosen] = maxf(0.001, _volume * clampf(float(event.intensity), 0.0, 1.0))
	player.volume_db = linear_to_db(_player_gain[chosen])
	player.stream_paused = false
	player.play()
	_player_started_at[chosen] = now_s
	_player_cut_at[chosen] = -1.0


func _update_active_fades(now_s: float) -> void:
	for index: int in _players.size():
		if _player_cut_at[index] < 0.0 or not _players[index].playing:
			continue
		var fade: float = 1.0 - smoothstep(0.0, CAMERA_CUT_CROSSFADE_S, now_s - _player_cut_at[index])
		if fade <= 0.001:
			_players[index].stop()
			_player_cut_at[index] = -1.0
		else:
			_players[index].volume_db = linear_to_db(maxf(0.001, _player_gain[index] * fade))


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	var bus: StringName = ENVIRONMENT_BUS if AudioServer.get_bus_index(ENVIRONMENT_BUS) >= 0 else &"Master"
	for index: int in MAX_VOICES:
		var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		player.name = "ThunderVoice%d" % index
		player.stream = load(THUNDER_CLIP_PATH) as AudioStream
		player.bus = bus
		player.max_db = 0.0
		player.unit_size = 1800.0
		player.max_distance = MAX_AUDIBLE_DISTANCE_M
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.volume_db = -80.0
		add_child(player)
		_players.append(player)
		_player_started_at.append(-1.0)
		_player_cut_at.append(-1.0)
		_player_gain.append(0.0)


func _refresh_bus() -> void:
	if AudioServer.get_bus_index(ENVIRONMENT_BUS) < 0:
		return
	for player: AudioStreamPlayer3D in _players:
		if player.bus != ENVIRONMENT_BUS:
			player.bus = ENVIRONMENT_BUS


func _stop_players() -> void:
	for player: AudioStreamPlayer3D in _players:
		player.stop()
		player.stream_paused = false
		player.volume_db = -80.0
	for index: int in _player_cut_at.size():
		_player_cut_at[index] = -1.0


static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
