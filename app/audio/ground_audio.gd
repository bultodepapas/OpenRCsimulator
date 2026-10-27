## Spatial wheel/skid roll and impact playback. It consumes snapshots only and never owns physics state.
extends Node3D

const Motion := preload("res://audio/ground_audio_motion.gd")
const Soundscape := preload("res://audio/soundscape.gd")
const DistanceModel := preload("res://audio/powertrain_audio.gd")
const HARD_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/hard_roll.wav")
const GRASS_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/grass_roll.wav")
const GRAVEL_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/gravel_roll.wav")
const TOUCHDOWN: AudioStreamWAV = preload("res://assets/audio/landing_gear/touchdown.wav")

const MAX_CONTACTS := 8
const ROLL_SPEED_ON_MPS := 0.35
const TOUCHDOWN_MIN_AIRBORNE_S := Motion.TOUCHDOWN_MIN_AIRBORNE_S
const TOUCHDOWN_MIN_APPROACH_MPS := Motion.TOUCHDOWN_MIN_APPROACH_MPS
const TOUCHDOWN_DEBOUNCE_S := Motion.TOUCHDOWN_DEBOUNCE_S

const MAX_ACCEPTED_EVENTS := 64
const MAX_ACCEPTED_RATE_HZ := 10000.0
const ACCEPTED_OBSERVATION_LAW := "accepted-tick-ground-audio-v1"
const MAX_EVENT_AGE_S := 0.25 # Presentation latency bound; not a landing/event window.
## VQ-01c-R1: longest continuous multi-tick interval one accepted observation may cover.
const MAX_ACCEPTED_INTERVAL_S := 0.25
var _accepted_tick_observation := false
var _accepted_tick := -1
var _accepted_rate := 0.0
var _accepted_paused := true
var _accepted_states: Dictionary = {}
var _accepted_contacts: Array = []
var _accepted_events: Array[Dictionary] = []
var _accepted_observed := 0
var _accepted_drained := 0
var _accepted_discarded := 0
var _accepted_overflowed := 0
var _accepted_refused := 0

var _owner: Node
var _soundscape: Node
var _bus: StringName = &"Master"
var _roll_streams: Array[AudioStreamWAV] = []
var _slots: Array[Dictionary] = []
var _last_tick: int = -1
var _needs_seed: bool = true
var _engine_mask: float = 1.0
var _scene_gain: float = 1.0
var _was_paused: bool = false
var _listener_position := Vector3.ZERO
var touchdown_events: int = 0
var contact_slot_count: int:
	get:
		return _slots.size()


## Direct presentation callers retain render sampling. Production supplies every
## accepted endpoint; capture never creates players, touches buses or plays audio.
func set_accepted_tick_observation(enabled: bool) -> void:
	if enabled == _accepted_tick_observation: return
	_accepted_tick_observation = enabled
	reset()


func observe_accepted(snapshot: Dictionary) -> bool:
	if not _accepted_tick_observation: return false
	if not _valid_accepted_snapshot(snapshot):
		_clear_accepted_observation()
		_accepted_refused += 1
		return false
	var tick: int = snapshot.tick
	var rate: float = snapshot.tick_rate
	if tick == _accepted_tick and rate == _accepted_rate and not snapshot.paused: return true
	# VQ-01c-R1: `since_tick` declares that the caller saw every tick since that observation, so the
	# endpoint continues history across the whole interval. Without it, only the next tick does.
	var since: int = int(snapshot.since_tick) if snapshot.has("since_tick") else tick - 1
	var discontinuity := since < 0 or since != _accepted_tick or tick <= since \
		or (tick - since > 1 and float(tick - since) > MAX_ACCEPTED_INTERVAL_S * rate) or rate != _accepted_rate
	var seed_only: bool = _accepted_tick < 0 or discontinuity or snapshot.paused or _accepted_paused
	if discontinuity or snapshot.paused: _clear_accepted_observation()
	var next_states := {}
	var detached_contacts: Array = []
	for supplied: Dictionary in snapshot.contacts:
		# Retain only the bounded presentation contract, never arbitrary nested
		# input data, physics objects or callers' mutable dictionaries.
		var contact := {id = supplied.id, position = supplied.position,
			normal_force_n = supplied.normal_force_n, reference_load_n = supplied.reference_load_n,
			approach_speed_mps = supplied.approach_speed_mps, rolling_speed_mps = supplied.rolling_speed_mps,
			surface = supplied.surface, roll_enabled = supplied.get("roll_enabled", true)}
		detached_contacts.append(contact)
		var observed := Motion.advance(contact, _accepted_states.get(contact.id, {}),
			0.0 if seed_only else float(tick - since) / rate, seed_only, not seed_only)
		next_states[contact.id] = observed.state
		if observed.impact_approach >= 0.0:
			_accepted_observed += 1
			if _accepted_events.size() == MAX_ACCEPTED_EVENTS:
				_accepted_events.pop_front()
				_accepted_overflowed += 1
				_accepted_discarded += 1
			_accepted_events.append({tick = tick, contact = contact.duplicate(true),
				force = observed.force, reference = observed.reference, approach = observed.impact_approach})
	_accepted_states = next_states
	_accepted_contacts = detached_contacts
	_accepted_tick = tick
	_accepted_rate = rate
	_accepted_paused = snapshot.paused
	return true


## VQ-01c-R1: a cue can fire only when a wheel that was airborne at the last observation loads, so a
## caller may defer observations while every wheel is grounded (or none can load, see GroundAudioModel).
func touchdown_possible() -> bool:
	if _accepted_states.is_empty():
		return true
	for state: Dictionary in _accepted_states.values():
		if not bool(state.get("grounded", false)):
			return true
	return false


## Tick of the last accepted observation, or -1.
func accepted_tick() -> int:
	return _accepted_tick


static func _valid_accepted_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.has("since_tick") and (typeof(snapshot.since_tick) != TYPE_INT or snapshot.since_tick < -1):
		return false
	if typeof(snapshot.get("tick")) != TYPE_INT or snapshot.tick < 0 or snapshot.tick > 9007199254740991 \
		or typeof(snapshot.get("tick_rate")) not in [TYPE_INT, TYPE_FLOAT] \
		or not is_finite(float(snapshot.tick_rate)) or snapshot.tick_rate < 1.0 or snapshot.tick_rate > MAX_ACCEPTED_RATE_HZ \
		or typeof(snapshot.get("paused")) != TYPE_BOOL or not snapshot.get("contacts") is Array \
		or snapshot.contacts.size() > MAX_CONTACTS: return false
	var ids := {}
	for contact: Variant in snapshot.contacts:
		if not contact is Dictionary or typeof(contact.get("id")) != TYPE_STRING \
			or contact.id.is_empty() or contact.id.length() > 128 or ids.has(contact.id): return false
		ids[contact.id] = true
		for key: String in ["normal_force_n", "reference_load_n", "approach_speed_mps", "rolling_speed_mps"]:
			if typeof(contact.get(key)) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(contact[key])) or contact[key] < 0.0: return false
		if not contact.get("position") is Vector3 or not contact.position.is_finite() \
			or typeof(contact.get("surface")) != TYPE_STRING or contact.surface.length() > 64: return false
		for key: String in ["grounded", "roll_enabled"]:
			if contact.has(key) and typeof(contact[key]) != TYPE_BOOL: return false
	return true


func _discard_accepted_events() -> void:
	_accepted_discarded += _accepted_events.size()
	_accepted_events.clear()


func _clear_accepted_observation() -> void:
	_discard_accepted_events()
	_accepted_states.clear()
	_accepted_contacts.clear()
	_accepted_tick = -1
	_accepted_rate = 0.0
	_accepted_paused = true


func _drain_accepted_events(tick: int, rate: float) -> void:
	for event: Dictionary in _accepted_events:
		if tick < event.tick or float(tick - event.tick) / maxf(rate, 1.0) > MAX_EVENT_AGE_S:
			_accepted_discarded += 1
			continue
		var slot := _slot_for(event.contact.id, _slots.size())
		if slot.is_empty():
			_accepted_discarded += 1
			continue
		_play_touchdown(event.contact, event.force, event.reference, event.approach, slot)
		_accepted_drained += 1
	_accepted_events.clear()


func accepted_diagnostics() -> Dictionary:
	return {law = ACCEPTED_OBSERVATION_LAW, tick = _accepted_tick, states = _accepted_states.size(),
		queued = _accepted_events.size(), observed = _accepted_observed, drained = _accepted_drained,
		discarded = _accepted_discarded, overflowed = _accepted_overflowed, refused = _accepted_refused}


## Adds this spatial rig below owner; source distance follows the same bounded manual law as the powertrain.
func configure(owner: Node, bus: StringName) -> void:
	_owner = owner
	if get_parent() == null and owner != null:
		owner.add_child(self)
	_roll_streams = [Soundscape.seamless_loop(HARD_ROLL), Soundscape.seamless_loop(GRASS_ROLL), Soundscape.seamless_loop(GRAVEL_ROLL)]
	rebind(bus)


func bind_soundscape(soundscape: Node) -> void:
	if is_instance_valid(_soundscape):
		var old_callable := Callable(self, "_on_buses_releasing")
		if _soundscape.is_connected("buses_releasing", old_callable):
			_soundscape.disconnect("buses_releasing", old_callable)
	_soundscape = soundscape
	_connect_soundscape()
	if is_instance_valid(_soundscape) and _soundscape.has_method("output_bus"):
		rebind(StringName(_soundscape.call("output_bus")))


func _connect_soundscape() -> void:
	if not is_instance_valid(_soundscape) or not _soundscape.has_signal("buses_releasing"):
		return
	var release_callable := Callable(self, "_on_buses_releasing")
	if not _soundscape.is_connected("buses_releasing", release_callable):
		_soundscape.connect("buses_releasing", release_callable)


## Rebind after Soundscape recreates its scene-local buses on reattachment.
func rebind(bus: StringName) -> void:
	if bus == StringName():
		return
	var changed: bool = bus != _bus
	_bus = bus
	for slot: Dictionary in _slots:
		for player: AudioStreamPlayer3D in slot.get("roll", []):
			player.bus = _bus
		var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
		if impact != null:
			impact.bus = _bus
	if changed:
		_needs_seed = true


## contacts are dictionaries with position, normal_force_n, reference_load_n, approach_speed_mps,
## rolling_speed_mps, surface, and optional roll_enabled. A false roll_enabled keeps touchdown impacts.
func update_contacts(tick: int, paused: bool, contacts: Array, engine_power: float, delta: float,
		listener: Vector3 = Vector3.ZERO, tick_rate_hz: float = 240.0) -> void:
	if tick < _last_tick:
		if _accepted_tick_observation:
			_reset_playback() # Keep legitimate post-rewind cues captured before rendering.
		else:
			reset()
	if _accepted_tick_observation:
		contacts = _accepted_contacts if tick == _accepted_tick else []
		if paused or tick != _accepted_tick: _discard_accepted_events()
	var tick_delta: int = maxi(tick - _last_tick, 0)
	var tick_advanced: bool = tick_delta > 0
	_last_tick = tick
	_listener_position = listener
	if paused:
		if not _was_paused:
			_needs_seed = true
		_was_paused = true
		_scene_gain = maxf(0.0, _scene_gain - clampf(delta, 0.0, 0.1) / 0.08)
		_apply_scene_gain()
		if _scene_gain <= 0.001:
			for slot: Dictionary in _slots:
				for player: AudioStreamPlayer3D in slot.get("roll", []):
					player.stop()
				var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
				if impact != null:
					impact.stop()
		return
	if _was_paused:
		_needs_seed = true
		_was_paused = false
	_scene_gain = minf(1.0, _scene_gain + clampf(delta, 0.0, 0.1) / 0.08)
	if is_instance_valid(_soundscape) and _soundscape.has_method("output_bus"):
		rebind(StringName(_soundscape.call("output_bus")))
	var dt: float = clampf(delta, 0.0, 0.1)
	var state_dt: float = float(tick_delta) / maxf(tick_rate_hz, 1.0)
	var target_mask: float = 1.0 - 0.42 * smoothstep(0.12, 0.9, clampf(engine_power, 0.0, 1.0))
	_engine_mask += (target_mask - _engine_mask) * (1.0 - exp(-dt / 0.25))
	if _accepted_tick_observation: _drain_accepted_events(tick, _accepted_rate)
	var active_ids: Dictionary = {}
	for i: int in range(contacts.size()):
		var contact: Dictionary = contacts[i]
		var identity: String = str(contact.get("id", "contact_%d" % i))
		active_ids[identity] = true
		var slot: Dictionary = _slot_for(identity, i)
		if slot.is_empty():
			continue
		_update_contact(contact, slot, state_dt, _needs_seed, dt, tick_advanced)
	for slot: Dictionary in _slots:
		if active_ids.has(str(slot.get("id", ""))):
			continue
		_set_roll_targets(slot, "hard", 0.0, dt)
		slot["state"] = {}
	_needs_seed = false


func _update_contact(contact: Dictionary, slot: Dictionary, state_delta: float, seed_only: bool,
		visual_delta: float, tick_advanced: bool) -> void:
	var point: Variant = contact.get("position", Vector3.ZERO)
	if point is Vector3:
		for player: AudioStreamPlayer3D in slot.get("roll", []):
			player.global_position = point
	var observed: Dictionary
	if _accepted_tick_observation:
		var identity: String = str(contact.get("id", ""))
		observed = Motion.advance(contact, _accepted_states.get(identity, {}).duplicate(true), 0.0, false, false)
	else:
		observed = Motion.advance(contact, slot.get("state", {}), state_delta, seed_only, tick_advanced)
		if observed.impact_approach >= 0.0:
			_play_touchdown(contact, observed.force, observed.reference, observed.impact_approach, slot)
	var state: Dictionary = observed.state
	# Roll pitch belongs to render smoothing, not accepted physical history.
	if _accepted_tick_observation and slot.get("state", {}).has("roll_pitch"):
		state.roll_pitch = slot.state.roll_pitch
	var force: float = observed.force
	var reference: float = observed.reference
	var force_off: float = observed.force_off
	var load_ratio: float = clampf(force / reference, 0.0, 1.5)
	var rolling_speed: float = maxf(0.0, float(contact.get("rolling_speed_mps", 0.0)))
	var can_roll: bool = bool(contact.get("roll_enabled", true)) and bool(state.get("grounded", false)) \
		and force >= force_off and rolling_speed >= ROLL_SPEED_ON_MPS
	var target: float = 0.0
	if can_roll:
		# A gentle onset, then sublinear energy growth: taxiing must not disappear
		# beneath a quadratic envelope intended for the much faster takeoff roll.
		var speed_mix: float = smoothstep(ROLL_SPEED_ON_MPS, 1.5, rolling_speed) \
			* pow(clampf(rolling_speed / 12.0, 0.0, 1.0), 0.6)
		var load_mix: float = clampf(sqrt(load_ratio), 0.0, 1.0)
		target = 0.42 * speed_mix * load_mix * _engine_mask
	if _accepted_tick_observation: slot["state"] = state
	_set_roll_targets(slot, str(contact.get("surface", "hard")), target, visual_delta, rolling_speed)
	var impact_player: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
	if impact_player != null and impact_player.playing:
		var impact_path: float = DistanceModel.distance_gain(impact_player.global_position.distance_to(_listener_position))
		impact_player.volume_db = linear_to_db(maxf(0.0001, float(slot.get("impact_gain", 0.0)) * _scene_gain * impact_path)) - 12.0
	state["grounded"] = bool(state.get("grounded", false))
	slot["state"] = state


func _set_roll_targets(slot: Dictionary, surface: String, gain: float, delta: float, rolling_speed: float = 0.0) -> void:
	var selected: int = 1 if surface in ["grass", "mown"] else (2 if surface in ["gravel", "rough"] else 0)
	var layers: Array = slot.get("layer_gain", [0.0, 0.0, 0.0])
	var players: Array = slot.get("roll", [])
	var factors: Array[float] = [1.0, 1.35, 0.86]
	var alpha: float = 1.0 - exp(-delta / 0.12) if delta > 0.0 else 0.0
	var state: Dictionary = slot.get("state", {})
	var target_pitch: float = clampf(0.85 + 0.025 * sqrt(maxf(rolling_speed, 0.0)), 0.85, 1.18)
	var old_pitch: float = float(state.get("roll_pitch", target_pitch))
	var pitch: float = lerpf(old_pitch, target_pitch, alpha)
	state["roll_pitch"] = pitch
	slot["state"] = state
	for layer: int in range(3):
		var target: float = gain * factors[layer] if layer == selected else 0.0
		layers[layer] = float(layers[layer]) + (target - float(layers[layer])) * alpha
		var player: AudioStreamPlayer3D = players[layer]
		var audible_gain: float = float(layers[layer]) * _scene_gain * DistanceModel.distance_gain(player.global_position.distance_to(_listener_position))
		player.volume_db = linear_to_db(maxf(audible_gain, 0.0001)) - 12.0
		player.pitch_scale = pitch
		if audible_gain > 0.0001:
			if not player.playing:
				# Separate wheels should not sum the same grains in phase.
				player.play(float(slot.get("roll_offset", 0.0)) * player.stream.get_length())
		else:
			player.stop()
	slot["layer_gain"] = layers


func _play_touchdown(contact: Dictionary, force: float, reference: float, approach: float, slot: Dictionary) -> void:
	var player: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
	if player == null or player.playing:
		return
	var load_mix: float = clampf(force / reference, 0.0, 2.0)
	var impact_mix: float = clampf(0.45 * approach / 4.0 + 0.18 * load_mix, 0.2, 1.0)
	slot["impact_gain"] = 0.22 + 0.34 * impact_mix
	player.pitch_scale = clampf(0.94 + approach * 0.018, 0.94, 1.12)
	var point: Variant = contact.get("position", Vector3.ZERO)
	if point is Vector3:
		player.global_position = point
	var distance_gain: float = DistanceModel.distance_gain(player.global_position.distance_to(_listener_position))
	player.volume_db = linear_to_db(maxf((0.22 + 0.34 * impact_mix) * _scene_gain * distance_gain, 0.0001)) - 12.0
	player.play()
	touchdown_events += 1


func _slot_for(identity: String, fallback_index: int) -> Dictionary:
	for slot: Dictionary in _slots:
		if str(slot.get("id", "")) == identity:
			return slot
	if _slots.size() >= MAX_CONTACTS:
		return {}
	var roll_players: Array[AudioStreamPlayer3D] = []
	for layer: int in range(3):
		var roll_player := AudioStreamPlayer3D.new()
		roll_player.name = "Roll_%d_%d" % [fallback_index, layer]
		roll_player.bus = _bus
		roll_player.stream = _roll_streams[layer] if layer < _roll_streams.size() else null
		roll_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		roll_player.max_distance = 0.0
		roll_player.max_db = 6.0
		roll_player.attenuation_filter_db = 0.0
		roll_player.panning_strength = 0.75
		roll_player.volume_db = -80.0
		add_child(roll_player)
		roll_players.append(roll_player)
	var impact := AudioStreamPlayer3D.new()
	impact.name = "Touchdown_%d" % fallback_index
	impact.bus = _bus
	impact.stream = TOUCHDOWN
	impact.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	impact.max_distance = 0.0
	impact.max_db = 6.0
	impact.attenuation_filter_db = 0.0
	impact.panning_strength = 0.75
	impact.volume_db = -80.0
	add_child(impact)
	var slot := {id = identity, roll = roll_players, impact = impact, roll_offset = fmod(fallback_index * 0.61803398875, 1.0),
		layer_gain = [0.0, 0.0, 0.0], impact_gain = 0.0, state = {}}
	_slots.append(slot)
	return slot


func stop() -> void:
	for slot: Dictionary in _slots:
		for player: AudioStreamPlayer3D in slot.get("roll", []):
			player.stop()
		var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
		if impact != null:
			impact.stop()
		slot["layer_gain"] = [0.0, 0.0, 0.0]
		var state: Dictionary = slot.get("state", {})
		state["roll_pitch"] = 0.85
		slot["state"] = state


func reset() -> void:
	_clear_accepted_observation()
	_accepted_observed = 0
	_accepted_drained = 0
	_accepted_discarded = 0
	_accepted_overflowed = 0
	_accepted_refused = 0
	_reset_playback()


func _reset_playback() -> void:
	stop()
	_last_tick = -1
	_needs_seed = true
	_engine_mask = 1.0
	_scene_gain = 1.0
	_was_paused = false
	touchdown_events = 0
	for slot: Dictionary in _slots:
		slot["state"] = {}


func _on_buses_releasing() -> void:
	_clear_accepted_observation()
	stop()
	_bus = StringName()
	_needs_seed = true


func _apply_scene_gain() -> void:
	for slot: Dictionary in _slots:
		var players: Array = slot.get("roll", [])
		var layers: Array = slot.get("layer_gain", [0.0, 0.0, 0.0])
		for i: int in range(players.size()):
			var player: AudioStreamPlayer3D = players[i]
			var audible_gain: float = float(layers[i]) * _scene_gain * DistanceModel.distance_gain(player.global_position.distance_to(_listener_position))
			player.volume_db = linear_to_db(maxf(audible_gain, 0.0001)) - 12.0
		var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
		if impact != null and impact.playing:
			var impact_gain: float = float(slot.get("impact_gain", 0.0)) * _scene_gain * DistanceModel.distance_gain(impact.global_position.distance_to(_listener_position))
			impact.volume_db = linear_to_db(maxf(impact_gain, 0.0001)) - 12.0


func _enter_tree() -> void:
	_connect_soundscape()


func _exit_tree() -> void:
	# A retained session can advance while this rig is detached. Reattachment must
	# observe its current contact state, not replay a landing from the hidden interval.
	reset()
	if is_instance_valid(_soundscape):
		var release_callable := Callable(self, "_on_buses_releasing")
		if _soundscape.is_connected("buses_releasing", release_callable):
			_soundscape.disconnect("buses_releasing", release_callable)
