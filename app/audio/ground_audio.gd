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
## touchdown_possible_at(): compressions this far below zero cannot load a wheel (1 µm).
const TOUCHDOWN_COMPRESSION_MARGIN_M := 1e-6
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
var _skipped_tick := -1
var _skipped_approach: Dictionary = {}

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

## NK-7d: in accepted-tick mode the native ground core (nk_ground_audio_core.hpp) keeps the accepted wheel states,
## queued touchdowns and roll levels, and writes the slots' players. Slots are still made here, in the same order.
## This script's accepted path stays the specification and the fallback; the hook is read when accepted mode turns
## on. While the core runs, only touchdown_events, _was_paused, _scene_gain and _needs_seed are kept here.
var native_core_enabled := true
var _core: Object = null
const _NATIVE_CLASS := &"OpenRCNativeKernel"


## Direct presentation callers retain render sampling. Production supplies every
## accepted endpoint; capture never creates players, touches buses or plays audio.
func set_accepted_tick_observation(enabled: bool) -> void:
	if enabled == _accepted_tick_observation: return
	_accepted_tick_observation = enabled
	reset()
	_core = null
	if enabled and native_core_enabled:
		_bind_core()


func _bind_core() -> void:
	if not ClassDB.class_exists(_NATIVE_CLASS):
		return
	var core: Object = ClassDB.instantiate(_NATIVE_CLASS)
	if core == null or not core.has_method(&"ground_core_open") or not core.ground_core_open():
		return
	for slot: Dictionary in _slots:
		if not _bind_slot(core, slot):
			return
	_core = core


func _bind_slot(core: Object, slot: Dictionary) -> bool:
	var roll: Array = slot.get("roll", [])
	var lengths := PackedFloat64Array()
	for player: AudioStreamPlayer3D in roll:
		lengths.append(player.stream.get_length() if player.stream != null else 0.0)
	return core.ground_core_bind_slot(str(slot.id), roll, slot.get("impact"), float(slot.get("roll_offset", 0.0)), lengths)


func observe_accepted(snapshot: Dictionary) -> bool:
	if not _accepted_tick_observation: return false
	if _core != null:
		return _core.ground_core_observe(snapshot)
	if not _valid_accepted_snapshot(snapshot):
		_clear_accepted_observation()
		_accepted_refused += 1
		return false
	var tick: int = snapshot.tick
	var rate: float = snapshot.tick_rate
	if tick == _accepted_tick and rate == _accepted_rate and not snapshot.paused: return true
	# `since_tick` attests clock continuity, not unobserved wheel state. Airborne
	# onset across a gap receives only the current tick; a previously airborne
	# wheel may continue its interval under the caller's near-ground tick gate.
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
		var previous: Dictionary = _accepted_states.get(contact.id, {})
		# A per-tick observer would have seen this wheel airborne on the skipped tick just before this one; its cue keeps
		# that last airborne sample (note_skipped_tick).
		if not seed_only and _skipped_tick == tick - 1 and _skipped_tick > since and _skipped_approach.has(contact.id) \
				and bool(previous.get("initialized", false)) and not bool(previous.get("grounded", false)):
			previous = previous.duplicate()
			previous["previous_approach_mps"] = float(_skipped_approach[contact.id])
		var observed := Motion.advance(contact, previous,
			0.0 if seed_only else float(tick - since) / rate, seed_only, not seed_only, 1.0 / rate)
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


## A caller may defer observations while every wheel is grounded or no wheel
## can load (see GroundAudioModel). Liftoff age is then a conservative lower
## estimate; the two deferred boundaries can omit at most two cadence gaps.
func touchdown_possible() -> bool:
	if _core != null:
		return _core.ground_core_touchdown_possible()
	if _accepted_states.is_empty():
		return true
	for state: Dictionary in _accepted_states.values():
		if not bool(state.get("grounded", false)):
			return true
	return false


## touchdown_possible() for one endpoint whose wheel compressions are known: `compressions[i]` belongs to the wheel
## `identities[i]`. A wheel that is not grounded can only cue on a tick where it is compressed, because its normal
## force is zero otherwise (GroundAudioModel rows). The tail wheel of a taildragger rolling on its mains, or an
## aircraft resting on its nose, then no longer forces an observation every tick; the touching tick still does, and so
## does a tick where a grounded wheel is uncompressed (its liftoff onset). A small margin keeps a contact whose two
## evaluations round differently. Unknown wheels keep the full answer.
func touchdown_possible_at(identities: PackedStringArray, compressions: PackedFloat64Array) -> bool:
	if _core != null:
		return _core.ground_core_touchdown_possible_at(identities, compressions)
	if _accepted_states.is_empty() or identities.size() != compressions.size():
		return true
	var covered := 0
	for index: int in identities.size():
		if not _accepted_states.has(identities[index]):
			return true
		covered += 1
		var state: Dictionary = _accepted_states[identities[index]]
		if bool(state.get("grounded", false)):
			# An unloaded grounded wheel lifts off on this tick: observe its airborne onset exactly.
			if not (compressions[index] > TOUCHDOWN_COMPRESSION_MARGIN_M):
				return true
		elif not (compressions[index] <= -TOUCHDOWN_COMPRESSION_MARGIN_M):
			return true
	return covered != _accepted_states.size() and touchdown_possible()


## A tick the caller did not observe because touchdown_possible_at() was false: each wheel's approach speed at that
## tick (GroundAudioModel.approach_speeds). Only the latest skipped tick is kept; an observation on the next tick
## gives a wheel that was airborne this sample as its last airborne approach, as a per-tick observer would.
func note_skipped_tick(tick: int, identities: PackedStringArray, approaches: PackedFloat64Array) -> void:
	if _core != null:
		_core.ground_core_note_skipped_tick(tick, identities, approaches)
		return
	_skipped_tick = tick
	_skipped_approach.clear()
	if identities.size() != approaches.size():
		_skipped_tick = -1
		return
	for index: int in identities.size():
		if is_finite(approaches[index]) and approaches[index] >= 0.0:
			_skipped_approach[identities[index]] = approaches[index]


## Tick of the last accepted observation, or -1.
func accepted_tick() -> int:
	return _core.ground_core_accepted_tick() if _core != null else _accepted_tick


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
	_skipped_tick = -1
	_skipped_approach.clear()


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
	if _core != null:
		return _core.ground_core_diagnostics()
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
	if _core != null:
		_update_core(tick, paused, engine_power, delta, listener, tick_rate_hz)
		return
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


## update_contacts through the native core (accepted mode): the bus follows the Soundscape as below, then the core
## asks for the slots this frame would make, and runs the rest.
func _update_core(tick: int, paused: bool, engine_power: float, delta: float, listener: Vector3, tick_rate_hz: float) -> void:
	if not paused and is_instance_valid(_soundscape) and _soundscape.has_method("output_bus"):
		rebind(StringName(_soundscape.call("output_bus")))
	for pending: Array in _core.ground_core_pending_slots(tick, paused):
		var slot := _slot_for(str(pending[0]), int(pending[1]))
		if slot.is_empty() or not _bind_slot(_core, slot):
			push_error("GroundAudio: the native core could not bind a contact slot")
	var out: PackedFloat64Array = _core.ground_core_frame(tick, paused, engine_power, delta, listener, tick_rate_hz,
		_needs_seed)
	_last_tick = tick
	_listener_position = listener
	if out.size() != 4:
		push_error("GroundAudio: a bound player is gone; the native core stops")
		_core = null
		return
	touchdown_events = int(out[0])
	_was_paused = out[1] != 0.0
	_scene_gain = out[2]
	_needs_seed = out[3] != 0.0


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
	if _core != null:
		_core.ground_core_stop()
		return
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
	if _core != null:
		_core.ground_core_reset()
		_last_tick = -1
		_needs_seed = true
		_engine_mask = 1.0
		_scene_gain = 1.0
		_was_paused = false
		touchdown_events = 0
		return
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
	if _core != null:
		_core.ground_core_release_buses()
	else:
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
