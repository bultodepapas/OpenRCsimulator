extends SceneTree

## AUD-16 focused software checks. Playback checks use the installed licensed WAVs;
## this script does not generate substitute assets or claim listening acceptance.
const ASSET_DIR: String = "res://assets/audio/mechanical/"
const MOTION_SCRIPT_PATH: String = "res://audio/mechanical_motion.gd"
const AUDIO_SCRIPT_PATH: String = "res://audio/mechanical_audio.gd"
const SERVO_TYPES: Array[String] = ["standard", "high_torque"]
const RETRACT_TYPES: Array[String] = ["electric", "pneumatic"]

var _checks: int = 0
var _failures: int = 0
var _motion_script: Script
var _audio_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_motion_script = load(MOTION_SCRIPT_PATH) as Script
	_audio_script = load(AUDIO_SCRIPT_PATH) as Script
	_check("mechanical motion observer is installed", _motion_script != null)
	_check("mechanical audio runtime is installed", _audio_script != null)
	if _motion_script != null:
		_test_accepted_motion_state_machine()
	if _audio_script != null:
		await _test_real_assets_and_audio_lifecycle()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_accepted_motion_state_machine() -> void:
	var observer: Dictionary = {}
	var result: Dictionary = _motion_script.call("observe", observer, _snapshot(1, 0.0, 0.0, false))
	observer = result.state
	_check("initial accepted sample primes without a cue", result.valid and result.primed and result.events.is_empty())
	result = _motion_script.call("observe", observer, _snapshot(2, 0.0, 0.0, true))
	observer = result.state
	_check("gear target change alone stays silent", result.events.is_empty() and not result.gear.moving)
	result = _motion_script.call("observe", observer, _snapshot(3, 4.0, 0.5, true))
	observer = result.state
	_check("each accepted servo plus retract movement starts once", _event_keys(result.events) == [
		"servo:aileron:start", "servo:elevator:start", "servo:rudder:start", "servo:flap:start", "gear:gear:start"],
		str(_event_keys(result.events)))
	_check("servo rate follows accepted angle and tick delta", is_equal_approx(float(result.channels[0].speed_per_s), 960.0))
	var repeated: Dictionary = _motion_script.call("observe", observer, _snapshot(3, 20.0, 0.8, true))
	_check("repeated render sample cannot retrigger or replace accepted movement", repeated.events.is_empty()
		and is_equal_approx(float(repeated.channels[0].value), 4.0))
	result = _motion_script.call("observe", observer, _snapshot(4, 2.0, 0.2, false))
	observer = result.state
	_check("accepted reversal is detected for each servo and retract", _event_keys(result.events) == [
		"servo:aileron:reverse", "servo:elevator:reverse", "servo:rudder:reverse", "servo:flap:reverse", "gear:gear:reverse"],
		str(_event_keys(result.events)))
	result = _motion_script.call("observe", observer, _snapshot(5, 2.0, 0.2, false))
	observer = result.state
	_check("interrupted motion stops without inventing a lock", _event_keys(result.events) == [
		"servo:aileron:stop", "servo:elevator:stop", "servo:rudder:stop", "servo:flap:stop", "gear:gear:stop"],
		str(_event_keys(result.events)))
	result = _motion_script.call("observe", observer, _snapshot(6, 2.0, 0.0, false))
	observer = result.state
	_check("moving to the requested up endpoint is still motion", _event_keys(result.events) == ["gear:gear:start"],
		str(_event_keys(result.events)))
	result = _motion_script.call("observe", observer, _snapshot(7, 2.0, 0.0, false))
	_check("settled accepted gear endpoint emits one lock cue", _event_keys(result.events) == ["gear:gear:lock"],
		str(_event_keys(result.events)))
	var paused: Dictionary = _motion_script.call("observe", observer,
		_snapshot(8, 18.0, 1.0, true, true, Vector3.ZERO, true))
	observer = paused.state
	_check("pause primes changed actuator state without audio events", paused.primed and paused.events.is_empty())
	var resumed: Dictionary = _motion_script.call("observe", observer, _snapshot(9, 18.0, 1.0, true))
	observer = resumed.state
	_check("resume does not replay paused movement", resumed.events.is_empty())
	var rewound: Dictionary = _motion_script.call("observe", observer, _snapshot(2, -20.0, 0.2, false))
	_check("tick rewind silently primes the new accepted state", rewound.primed and rewound.events.is_empty())


func _test_real_assets_and_audio_lifecycle() -> void:
	var rig := Node3D.new()
	rig.name = "MechanicalAudioTestRig"
	root.add_child(rig)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.5, 4.0)
	rig.add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	var audio: Node = _audio_script.new() as Node
	_check("audio instance is a scene node", audio != null)
	if audio == null:
		root.remove_child(rig)
		rig.free()
		return
	rig.add_child(audio)

	for servo_type: String in SERVO_TYPES:
		for retract_type: String in RETRACT_TYPES:
			var config: Dictionary = {servo_type = servo_type, servo_level = 0.75, retract_type = retract_type}
			_check("real WAV set exists for %s/%s" % [servo_type, retract_type], _real_asset_set_valid(servo_type, retract_type))
			audio.call("configure", rig, &"Master", config)
			var initial: Dictionary = audio.call("diagnostics")
			_check("installed %s/%s profile has no missing required assets" % [servo_type, retract_type],
				initial.get("missing_assets", []).is_empty(), str(initial.get("missing_assets", [])))
			_check("voice pools remain within the declared cap", int(initial.get("motion_voice_count", 0)) <= 6
				and int(initial.get("event_voice_count", 0)) <= 2)
			await _exercise_audio_profile(audio, config)
			if servo_type == "standard" and retract_type == "electric":
				await _test_loop_voice_stability(audio)
				_test_retract_event_interruptions_and_priority(audio)

	var missing: Variant = audio.call("_load_wav", "qa_missing", ASSET_DIR + "__missing_for_qa__.wav", false)
	var after_missing: Dictionary = audio.call("diagnostics")
	_check("missing resource resolves to silent null instead of a substitute", missing == null
		and not after_missing.get("missing_assets", []).is_empty())
	audio.call("configure", rig, &"Master", {servo_type = "standard", servo_level = 0.75, retract_type = "electric"})
	_check("reconfigure clears the transient missing-resource diagnostic",
		audio.call("diagnostics").get("missing_assets", []).is_empty())

	var bus_name: StringName = &"Mechanical Audio QA"
	var bus_before: int = AudioServer.bus_count
	AudioServer.add_bus()
	var test_bus_index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(test_bus_index, bus_name)
	AudioServer.set_bus_send(test_bus_index, &"Master")
	audio.call("reset")
	audio.call("update_sound", _snapshot(100, 0.0, 0.0, false), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(101, 10.0, 0.5, true), 1.0 / 60.0)
	var before_rebind_events: int = int(audio.call("diagnostics").get("events_played", 0))
	audio.call("rebind", bus_name)
	var bus_children_match: bool = true
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer3D:
			bus_children_match = bus_children_match and (child as AudioStreamPlayer3D).bus == bus_name
	_check("rebind moves owned players onto the replacement scene bus", bus_children_match)
	audio.call("update_sound", _snapshot(101, 30.0, 0.9, true), 1.0 / 60.0)
	_check("rebind resets the motion observer before accepting another tick",
		int(audio.call("diagnostics").get("events_played", 0)) == before_rebind_events)
	AudioServer.remove_bus(test_bus_index)
	audio.call("rebind", &"Master")
	_check("bus detach and rebind leave no temporary bus behind", AudioServer.bus_count == bus_before)

	var events_before_detach: int = int(audio.call("diagnostics").get("events_played", 0))
	rig.remove_child(audio)
	await process_frame
	rig.add_child(audio)
	audio.call("configure", rig, &"Master", {servo_type = "high_torque", servo_level = 0.75, retract_type = "pneumatic"})
	audio.call("update_sound", _snapshot(1, 0.0, 0.0, false), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(2, 10.0, 0.5, true), 1.0 / 60.0)
	var reattached: Dictionary = audio.call("diagnostics")
	_check("detach, reattach and configure re-prime before new cue playback", int(reattached.get("events_played", 0)) >= events_before_detach
		and reattached.get("missing_assets", []).is_empty())
	var final_configure_count: int = int(reattached.get("reset_count", 0))
	audio.call("configure", rig, &"Master", {servo_type = "standard", servo_level = 0.0, retract_type = "electric"})
	_check("zero servo level is accepted as configuration and resets voices",
		int(audio.call("diagnostics").get("reset_count", 0)) > final_configure_count)

	var final_report: Dictionary = audio.call("diagnostics")
	_check("final profile remains silent of missing assets", final_report.get("missing_assets", []).is_empty())
	_check("audio instance stayed within motion and event voice caps",
		int(final_report.get("motion_voice_count", 0)) <= 6 and int(final_report.get("event_voice_count", 0)) <= 2)
	rig.remove_child(audio)
	audio.free()
	root.remove_child(rig)
	rig.free()


func _exercise_audio_profile(audio: Node, config: Dictionary) -> void:
	var events_before: int = int(audio.call("diagnostics").get("events_played", 0))
	audio.call("update_sound", _snapshot(1, 0.0, 0.0, false), 1.0 / 60.0)
	var primed: Dictionary = audio.call("diagnostics")
	_check("%s/%s initial sample creates no cue" % [config.servo_type, config.retract_type],
		int(primed.get("events_played", 0)) == events_before)
	audio.call("update_sound", _snapshot(2, 8.0, 0.5, true), 1.0 / 60.0)
	var moving: Dictionary = audio.call("diagnostics")
	_check("%s/%s accepted movement starts real cue playback" % [config.servo_type, config.retract_type],
		int(moving.get("events_played", 0)) > events_before and int(moving.get("active_motion_voices", 0)) > 0)
	_check("simultaneous movement stays within fixed voice pools",
		int(moving.get("motion_voice_count", 0)) <= 6 and int(moving.get("event_voice_count", 0)) <= 2)
	var same_tick_events: int = _event_work_count(moving)
	audio.call("update_sound", _snapshot(2, 25.0, 0.9, true), 1.0 / 60.0)
	_check("same tick render update cannot retrigger motion event", _event_work_count(audio.call("diagnostics")) == same_tick_events,
		str(audio.call("diagnostics")))
	audio.call("update_sound", _snapshot(3, 4.0, 0.25, false), 1.0 / 60.0)
	var reversed: Dictionary = audio.call("diagnostics")
	_check("accepted reversal reaches the bounded event queue", _event_work_count(reversed) > same_tick_events,
		str(reversed))

	var far_listener: Vector3 = Vector3(0.0, 0.0, 100.0)
	audio.call("update_sound", _snapshot(4, 14.0, 0.4, true, false, far_listener), 1.0 / 60.0)
	var culled: Dictionary = audio.call("diagnostics")
	_check("far source is culled while observer keeps ticking", int(culled.get("far_culled_motion_updates", 0)) > 0
		and bool(culled.get("last_targets", {}).get("far_culled", false)))
	audio.call("update_sound", _snapshot(5, 20.0, 0.5, true, false, Vector3.ZERO), 1.0 / 60.0)
	var near: Dictionary = audio.call("diagnostics")
	_check("moving listener back near source restores bounded voice playback",
		int(near.get("last_targets", {}).get("active_motion_voices", 0)) > 0)
	var zero_metre_gain: float = float(audio.call("_distance_gain", 0.0))
	var one_metre_gain: float = float(audio.call("_distance_gain", 1.0))
	_check("near-field attenuation gain is capped at unity", zero_metre_gain <= 1.0 and one_metre_gain <= 1.0
		and is_equal_approx(zero_metre_gain, 1.0) and is_equal_approx(one_metre_gain, 1.0))

	var pause_events: int = int(near.get("events_played", 0))
	audio.call("update_sound", _snapshot(6, 40.0, 0.7, true, true, Vector3.ZERO, true), 1.0 / 60.0)
	_check("pause primes a changed state without cue playback", int(audio.call("diagnostics").get("events_played", 0)) == pause_events)
	audio.call("reset")
	audio.call("update_sound", _snapshot(1, 40.0, 0.7, true), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(0, -5.0, 0.1, false), 1.0 / 60.0)
	_check("reset and tick rewind prime silently", int(audio.call("diagnostics").get("events_played", 0)) == pause_events)
	if config.servo_type == "standard" and config.retract_type == "electric":
		await _test_stale_tick_and_missing_voice_fade(audio)
		_test_event_source_follows_accepted_anchor(audio)


func _test_stale_tick_and_missing_voice_fade(audio: Node) -> void:
	audio.call("reset")
	audio.call("update_sound", _snapshot(100, 0.0, 0.0, false), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(101, 12.0, 0.5, true), 1.0 / 60.0)
	var initial: Dictionary = audio.call("diagnostics")
	_check("voice lifecycle fixture starts installed motion and gear voices",
		int(initial.get("active_motion_voices", 0)) >= 2)
	for _frame: int in 20:
		audio.call("update_sound", _snapshot(101, 12.0, 0.5, true), 1.0 / 60.0)
		await process_frame
	var stale: Dictionary = audio.call("diagnostics")
	_check("stalled accepted tick resets the observer", int(stale.get("stale_tick_resets", 0)) > 0)
	for index: int in 45:
		audio.call("update_sound", {tick = 102 + index, tick_rate = 240.0, paused = false,
			listener = Vector3.ZERO, engine_mask = 1.0, channels = [],
			gear = {available = false}}, 1.0 / 60.0)
		await process_frame
	var faded: Dictionary = audio.call("diagnostics")
	_check("missing control channels and retract gear fade and stop owned motion voices",
		int(faded.get("active_motion_voices", 0)) == 0)
	_check("stopped or culled voice slots remain bounded and reusable",
		int(faded.get("motion_voice_count", 0)) <= 6)


func _test_event_source_follows_accepted_anchor(audio: Node) -> void:
	audio.call("reset")
	var source_one: Vector3 = Vector3(2.0, 1.0, -1.0)
	var source_two: Vector3 = Vector3(12.0, 3.0, 4.0)
	audio.call("update_sound", _single_channel_snapshot(200, 0.0, source_one), 1.0 / 60.0)
	audio.call("update_sound", _single_channel_snapshot(201, 8.0, source_one), 1.0 / 60.0)
	var players: Array = audio.get("_event_players")
	var source_ids: Array = audio.get("_event_source_ids")
	var followed_player: AudioStreamPlayer3D
	for index: int in mini(players.size(), source_ids.size()):
		if str(source_ids[index]) == "aileron":
			followed_player = players[index] as AudioStreamPlayer3D
			break
	_check("servo event is attached to its accepted source identity", followed_player != null
		and followed_player.global_position == source_one)
	if followed_player != null:
		audio.call("update_sound", _single_channel_snapshot(202, 8.0, source_two), 1.0 / 60.0)
		_check("active event voice follows its moved accepted anchor", followed_player.global_position == source_two)
	else:
		_check("active event voice follows its moved accepted anchor", false)


func _real_asset_set_valid(servo_type: String, retract_type: String) -> bool:
	var paths: Array[String] = [
		"servo_%s_loop.wav" % servo_type,
		"servo_%s_start.wav" % servo_type,
		"servo_%s_start_02.wav" % servo_type,
		"servo_%s_stop.wav" % servo_type,
		"servo_%s_stop_02.wav" % servo_type,
		"retract_%s_loop.wav" % retract_type,
	]
	if retract_type == "electric":
		paths.append_array(["retract_electric_start.wav", "retract_electric_lock.wav"])
	else:
		paths.append_array(["retract_pneumatic_hiss.wav", "retract_pneumatic_valve.wav", "retract_pneumatic_lock.wav"])
	for relative_path: String in paths:
		var path: String = ASSET_DIR + relative_path
		if not ResourceLoader.exists(path):
			print("missing expected test asset: " + path)
			return false
		var stream := ResourceLoader.load(path) as AudioStreamWAV
		if stream == null or stream.data.is_empty() or stream.mix_rate <= 0 or stream.format != AudioStreamWAV.FORMAT_16_BITS:
			print("invalid test asset %s: stream=%s format=%d bytes=%d rate=%d" % [path,
				str(stream != null), int(stream.format) if stream != null else -1,
				stream.data.size() if stream != null else 0, stream.mix_rate if stream != null else 0])
			return false
	return true


func _test_loop_voice_stability(audio: Node) -> void:
	audio.call("reset")
	audio.call("update_sound", _single_channel_snapshot(300, 0.0, Vector3.ZERO), 1.0 / 60.0)
	audio.call("update_sound", _single_channel_snapshot(301, 1.0, Vector3.ZERO), 1.0 / 60.0)
	var slots_before: Dictionary = audio.get("_motion_players")
	var first_slot: Dictionary = slots_before.get("servo:aileron", {})
	var first_player: AudioStreamPlayer3D = first_slot.get("player") as AudioStreamPlayer3D
	var prior_gain: float = float(first_slot.get("gain", 0.0))
	_check("servo loop allocates one persistent player on accepted motion", first_player != null
		and prior_gain > 0.0 and first_player.playing)
	var gain_stayed_positive: bool = true
	var player_identity_stable: bool = true
	for index: int in 8:
		audio.call("update_sound", _single_channel_snapshot(302 + index, float(index + 2), Vector3.ZERO), 1.0 / 60.0)
		await process_frame
		var slots_after: Dictionary = audio.get("_motion_players")
		var slot_after: Dictionary = slots_after.get("servo:aileron", {})
		var player_after: AudioStreamPlayer3D = slot_after.get("player") as AudioStreamPlayer3D
		player_identity_stable = player_identity_stable and player_after == first_player
		gain_stayed_positive = gain_stayed_positive and float(slot_after.get("gain", 0.0)) > 0.0
		prior_gain = float(slot_after.get("gain", 0.0))
	_check("moving loop voice retains its player and nonzero envelope across updates",
		player_identity_stable and gain_stayed_positive and first_player != null and first_player.playing)


func _test_retract_event_interruptions_and_priority(audio: Node) -> void:
	audio.call("reset")
	audio.call("update_sound", _gear_only_snapshot(400, 0.0, false), 1.0 / 60.0)
	audio.call("update_sound", _gear_only_snapshot(401, 0.5, true), 1.0 / 60.0)
	var started_roles: Array[String] = _playing_event_roles(audio)
	_check("retract accepted extension plays one real start cue", started_roles.count("gear_start") == 1,
		str(started_roles))
	audio.call("update_sound", _gear_only_snapshot(402, 0.25, false), 1.0 / 60.0)
	await _advance_same_snapshot(audio, _gear_only_snapshot(402, 0.25, false), 4)
	var reversed_roles: Array[String] = _playing_event_roles(audio)
	_check("reversal replaces the canceled source-scoped gear cue", reversed_roles.count("gear_start") == 1,
		str(reversed_roles))
	audio.call("update_sound", _gear_only_snapshot(403, 0.25, false), 1.0 / 60.0)
	await _advance_same_snapshot(audio, _gear_only_snapshot(403, 0.25, false), 4)
	var stopped_roles: Array[String] = _playing_event_roles(audio)
	_check("interrupted gear movement leaves no stale start cue playing", not stopped_roles.has("gear_start"),
		str(stopped_roles))
	_check("stopped gear leaves no pending retract cue", _pending_event_count(audio) == 0,
		str(audio.call("diagnostics")))

	audio.call("reset")
	audio.call("update_sound", _snapshot(500, 0.0, 0.0, false), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(501, 10.0, 0.0, false), 1.0 / 60.0)
	var saturated: Array[String] = _playing_event_roles(audio)
	_check("two event voices are occupied by simultaneous servo starts", saturated.count("servo_start") == 2,
		str(saturated))
	audio.call("update_sound", _snapshot(502, 10.0, 0.5, true), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(503, 10.0, 1.0, true), 1.0 / 60.0)
	audio.call("update_sound", _snapshot(504, 10.0, 1.0, true), 1.0 / 60.0)
	await _advance_same_snapshot(audio, _snapshot(504, 10.0, 1.0, true), 4)
	var lock_priority_roles: Array[String] = _playing_event_roles(audio)
	_check("gear lock receives a voice under a full two-slot event burst",
		lock_priority_roles.has("gear_lock"),
		"roles=%s diagnostics=%s" % [str(lock_priority_roles), str(audio.call("diagnostics"))])
	_check("gear endpoint cue has no duplicate same-source voices",
		_gear_source_voice_count(audio) <= 1, str(_playing_event_sources(audio)))


func _playing_event_roles(audio: Node) -> Array[String]:
	var result: Array[String] = []
	var players: Array = audio.get("_event_players")
	var roles: Array = audio.get("_event_roles")
	for index: int in mini(players.size(), roles.size()):
		var player: AudioStreamPlayer3D = players[index] as AudioStreamPlayer3D
		if player != null and player.playing:
			result.append(str(roles[index]))
	return result


func _playing_event_sources(audio: Node) -> Array[String]:
	var result: Array[String] = []
	var players: Array = audio.get("_event_players")
	var sources: Array = audio.get("_event_source_ids")
	for index: int in mini(players.size(), sources.size()):
		var player: AudioStreamPlayer3D = players[index] as AudioStreamPlayer3D
		if player != null and player.playing:
			result.append(str(sources[index]))
	return result


func _gear_source_voice_count(audio: Node) -> int:
	var players: Array = audio.get("_event_players")
	var sources: Array = audio.get("_event_source_ids")
	var count: int = 0
	for index: int in mini(players.size(), sources.size()):
		var player: AudioStreamPlayer3D = players[index] as AudioStreamPlayer3D
		if player != null and player.playing and str(sources[index]) == "gear":
			count += 1
	return count


func _pending_event_count(audio: Node) -> int:
	var diagnostics: Dictionary = audio.call("diagnostics")
	if diagnostics.has("pending_event_count"):
		return int(diagnostics.pending_event_count)
	var pending: Variant = audio.get("_pending_events")
	return pending.size() if pending is Array else 0


func _event_work_count(diagnostics: Dictionary) -> int:
	return int(diagnostics.get("events_played", 0)) + int(diagnostics.get("events_dropped", 0)) \
		+ int(diagnostics.get("pending_event_count", 0))


func _advance_same_snapshot(audio: Node, snapshot: Dictionary, frames: int) -> void:
	for _frame: int in frames:
		await process_frame
		audio.call("update_sound", snapshot, 1.0 / 60.0)


func _gear_only_snapshot(tick: int, extension: float, target_down: bool) -> Dictionary:
	return {tick = tick, tick_rate = 240.0, paused = false, listener = Vector3.ZERO, engine_mask = 1.0,
		channels = [], gear = {available = true, extension = extension, target_down = target_down,
			status = "down" if extension >= 0.999999 else "up" if extension <= 0.000001 else "moving",
			position = Vector3.ZERO}}


func _snapshot(tick: int, angle: float, extension: float, target_down: bool,
		has_gear: bool = true, listener_position: Vector3 = Vector3.ZERO, paused: bool = false) -> Dictionary:
	var channels: Array[Dictionary] = [
		{id = "aileron", angle_deg = angle, position = Vector3(1.0, 0.0, 0.0)},
		{id = "elevator", angle_deg = -angle * 0.5, position = Vector3(0.0, 1.0, 0.0)},
		{id = "rudder", angle_deg = angle * 0.25, position = Vector3(0.0, 0.0, 1.0)},
		{id = "flap", angle_deg = angle * 0.75, position = Vector3(-1.0, 0.0, 0.0)},
	]
	return {tick = tick, tick_rate = 240.0, paused = paused, listener = listener_position,
		engine_mask = 1.0, channels = channels,
		gear = {available = has_gear, extension = extension, target_down = target_down,
			status = "down" if extension >= 0.999999 else "up" if extension <= 0.000001 else "moving",
			position = Vector3(0.0, 0.0, 0.0)}}


func _single_channel_snapshot(tick: int, angle: float, position: Vector3) -> Dictionary:
	return {tick = tick, tick_rate = 240.0, paused = false, listener = Vector3.ZERO, engine_mask = 1.0,
		channels = [{id = "aileron", angle_deg = angle, position = position}],
		gear = {available = false}}


func _event_keys(events: Array) -> Array[String]:
	var keys: Array[String] = []
	for event: Dictionary in events:
		keys.append("%s:%s:%s" % [event.system, event.id, event.event])
	return keys


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1
