## Spatial wheel/skid roll and impact playback. It consumes snapshots only and never owns physics state.
extends Node3D

const Soundscape := preload("res://audio/soundscape.gd")
const DistanceModel := preload("res://audio/powertrain_audio.gd")
const HARD_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/hard_roll.wav")
const GRASS_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/grass_roll.wav")
const GRAVEL_ROLL: AudioStreamWAV = preload("res://assets/audio/landing_gear/gravel_roll.wav")
const TOUCHDOWN: AudioStreamWAV = preload("res://assets/audio/landing_gear/touchdown.wav")

const MAX_CONTACTS := 8
const ROLL_SPEED_ON_MPS := 0.35
const TOUCHDOWN_MIN_AIRBORNE_S := 0.14
const TOUCHDOWN_MIN_APPROACH_MPS := 0.2
const TOUCHDOWN_DEBOUNCE_S := 0.65

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
		reset()
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
	var state: Dictionary = slot.get("state", {})
	var force: float = maxf(0.0, float(contact.get("normal_force_n", contact.get("normal_force", 0.0))))
	var reference: float = maxf(1.0, float(contact.get("reference_load_n", maxf(force, 100.0))))
	var force_on: float = maxf(3.0, reference * 0.035)
	var force_off: float = maxf(1.0, reference * 0.018)
	var candidate_grounded: bool = bool(contact.get("grounded", force >= force_on)) if not contact.has("normal_force_n") else force >= force_on
	var approach_now: float = maxf(0.0, float(contact.get("approach_speed_mps", 0.0)))
	var was_grounded: bool = bool(state.get("grounded", false))
	var cooldown: float = maxf(0.0, float(state.get("cooldown_s", 0.0)) - state_delta)
	var airborne: float = float(state.get("airborne_s", 0.0))
	var previous_approach: float = float(state.get("previous_approach_mps", 0.0))
	if seed_only or not bool(state.get("initialized", false)):
		was_grounded = force >= force_on if contact.has("normal_force_n") else candidate_grounded
		state["grounded"] = was_grounded
		state["airborne_s"] = 0.0
		state["previous_approach_mps"] = 0.0
		state["cooldown_s"] = 0.0
		state["initialized"] = true
	else:
		var next_grounded: bool = force >= force_off if was_grounded else candidate_grounded
		if next_grounded and not was_grounded:
			# The accepted contact state may already be rebounding. Retain only the last
			# airborne sample, never a descent peak from an earlier part of the flight.
			var approach: float = maxf(previous_approach, approach_now)
			if tick_advanced and not seed_only and airborne >= TOUCHDOWN_MIN_AIRBORNE_S and cooldown <= 0.0 and approach >= TOUCHDOWN_MIN_APPROACH_MPS:
				_play_touchdown(contact, force, reference, approach, slot)
				cooldown = TOUCHDOWN_DEBOUNCE_S
			airborne = 0.0
			previous_approach = 0.0
		elif not next_grounded:
			airborne += state_delta
			if tick_advanced:
				previous_approach = approach_now
		state["grounded"] = next_grounded
		state["airborne_s"] = airborne
		state["previous_approach_mps"] = previous_approach
		state["cooldown_s"] = cooldown
		state["initialized"] = true
	var load_ratio: float = clampf(force / reference, 0.0, 1.5)
	var rolling_speed: float = maxf(0.0, float(contact.get("rolling_speed_mps", 0.0)))
	var can_roll: bool = bool(contact.get("roll_enabled", true)) and bool(state.get("grounded", false)) \
		and force >= force_off and rolling_speed >= ROLL_SPEED_ON_MPS
	var target: float = 0.0
	if can_roll:
		var speed_mix: float = smoothstep(ROLL_SPEED_ON_MPS, 12.0, rolling_speed)
		var load_mix: float = clampf(sqrt(load_ratio), 0.0, 1.0)
		target = 0.42 * speed_mix * load_mix * _engine_mask
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
	stop()
	if is_instance_valid(_soundscape):
		var release_callable := Callable(self, "_on_buses_releasing")
		if _soundscape.is_connected("buses_releasing", release_callable):
			_soundscape.disconnect("buses_releasing", release_callable)
