extends SceneTree
## NK-7e: a MechanicalAudio rig on the native mechanical core and one on the GDScript reference, both in accepted-tick
## mode and fed the same accepted endpoints and render snapshots, agree bit for bit after every frame: observe
## answers, diagnostics (counters, last targets), every motion and event player (volume, pitch, position, playback,
## stream) and the voices' gains, pitches, offsets, roles, envelopes and pending cues. The run sweeps, reverses and
## stops the surfaces, cycles the retracts, moves the listener near, far and to an invalid position, and covers
## pauses, rewinds, gaps and since_tick intervals, stale render ticks, refused endpoints and two servo/retract
## profiles. Skips (passes) without the verified library.

const Mechanical := preload("res://audio/mechanical_audio.gd")
const FRAMES := 3000
const SURFACES: Array[String] = ["aileron", "elevator", "rudder", "flap"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.audio_listener_enable_3d = true
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_exists(&"OpenRCNativeKernel") \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"mechanical_core_bind"):
		print("NK7E_SKIP no native library with the mechanical core")
		quit(0)
		return
	for config: Dictionary in [{}, {servo_type = "high_torque", retract_type = "pneumatic", servo_level = 0.7}]:
		await _scenario(config)
	print("native mechanical audio core: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _scenario(config: Dictionary) -> void:
	var owner := Node3D.new()
	root.add_child(owner)
	var rigs: Array = []
	for native: bool in [true, false]:
		var rig: Variant = Mechanical.new()
		rig.native_core_enabled = native
		rig.configure(owner, &"Master", config)
		rig.set_accepted_tick_observation(true)
		rigs.append(rig)
	var native: Variant = rigs[0]
	var reference: Variant = rigs[1]
	var label := str(config.get("servo_type", "standard"))
	_check("%s: the native rig binds its core" % label, native._core != null and reference._core == null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var tick := 500
	var mismatched := 0
	var first := ""
	var refused := 0
	for frame: int in FRAMES:
		var paused: bool = frame % 500 >= 460 and frame % 500 < 475
		if frame % 777 == 300:
			tick -= 40 # rewind
		var stalled: bool = frame % 500 >= 300 and frame % 500 < 320 # no accepted tick for 0.33 s: a stale render tick
		var ticks: int = 0 if paused or stalled or frame % 53 == 7 else (4 if frame % 41 != 0 else 70) # 70: a gap
		var use_since: bool = frame % 3 == 0
		var answers: Array = []
		for k: int in maxi(ticks, 1):
			if ticks > 0:
				tick += 1
			if use_since and ticks > 1 and k < ticks - 1:
				continue # observed once at the end of the interval
			var endpoint := _endpoint(frame, tick, paused, use_since, ticks)
			for rig: Variant in rigs:
				answers.append(rig.observe_accepted(endpoint.duplicate(true)))
		refused += int(answers.size() > 1 and answers[1] == false)
		var render := _render(frame, tick, paused, rng)
		var delta: float = [1.0 / 60.0, 1.0 / 30.0, 0.0, 0.3][frame % 4 if frame % 13 == 0 else 0]
		for rig: Variant in rigs:
			rig.update_sound(render.duplicate(true), delta)
		var a := _state(native)
		var b := _state(reference)
		var differ := false
		for i: int in range(0, answers.size(), 2):
			differ = differ or answers[i] != answers[i + 1]
		if differ or var_to_bytes(a) != var_to_bytes(b):
			mismatched += 1
			if first.is_empty():
				first = "frame %d: answers %s; %s" % [frame, answers, _first_difference(a, b, "state")]
	var d: Dictionary = reference.diagnostics()
	print("%s: %d frames, %d differ, %d events played, %d dropped, %d motion voices, %d far-culled updates, %d stale resets, %d refused" % [
		label, FRAMES, mismatched, d.events_played, d.events_dropped, d.motion_voice_count, d.far_culled_motion_updates,
		d.stale_tick_resets, refused])
	_check("%s: every frame matches the reference" % label, mismatched == 0, "%d differ; %s" % [mismatched, first])
	_check("%s: the run exercises events, motion voices, culling, stale ticks and refusals" % label,
		int(d.events_played) > 20 and int(d.motion_voice_count) >= 4 and int(d.far_culled_motion_updates) > 10
		and int(d.stale_tick_resets) > 0 and refused > 3, str(d))
	_check("%s: the native core stays bound" % label, native._core != null)
	owner.queue_free()
	await process_frame


func _angle(frame: int, index: int) -> float:
	# Sweeps, reversals and holds; the flap steps.
	if index == 3:
		return 0.0 if frame % 400 < 200 else 20.0
	if frame % 300 > 220:
		return 5.0 * index # hold: stop events
	return 25.0 * sin(frame * (0.03 + 0.01 * index) + index)


func _gear(frame: int) -> Dictionary:
	var cycle: float = fmod(float(frame) / 600.0, 1.0)
	var down: bool = cycle < 0.5
	var extension: float = clampf(1.0 - (cycle - 0.1) * 4.0, 0.0, 1.0) if down else clampf((cycle - 0.6) * 4.0, 0.0, 1.0)
	return {available = true, extension = extension, target_down = extension > 0.5 if frame % 2 == 0 else down,
		status = "moving" if extension > 0.0 and extension < 1.0 else "locked"}


func _endpoint(frame: int, tick: int, paused: bool, use_since: bool, ticks: int) -> Dictionary:
	var channels: Array[Dictionary] = []
	for i: int in SURFACES.size():
		channels.append({id = SURFACES[i], angle_deg = _angle(frame, i)})
	var endpoint := {tick = tick, tick_rate = 240.0, paused = paused, channels = channels, gear = _gear(frame)}
	if use_since:
		endpoint.since_tick = tick - maxi(ticks, 1)
	if frame % 157 == 9:
		endpoint.tick_rate = 0.5 # refused
	elif frame % 163 == 11:
		endpoint.paused = 1 # refused
	return endpoint


func _render(frame: int, tick: int, paused: bool, rng: RandomNumberGenerator) -> Dictionary:
	var channels: Array[Dictionary] = []
	for i: int in SURFACES.size():
		var row := {id = SURFACES[i], angle_deg = _angle(frame, i), position = Vector3(float(i) - 1.5, 0.2, -0.5)}
		if frame % 97 == i:
			row.erase("position")
		channels.append(row)
	var gear := _gear(frame)
	gear.position = Vector3(0.0, -0.2, 0.0)
	gear.target = 1.0 if gear.target_down else 0.0
	var listener := Vector3(rng.randf_range(-3.0, 3.0), 1.5, rng.randf_range(2.0, 8.0))
	if frame % 600 > 540:
		listener = Vector3(0.0, 1.5, 70.0 + float(frame % 10)) # beyond MAX_DISTANCE_M
	elif frame % 600 > 520:
		listener = Vector3(0.0, 1.5, 45.0) # in the distance fade
	var render := {channels = channels, tick_rate = 240.0, gear = gear, tick = tick, paused = paused,
		listener = listener, engine_mask = rng.randf_range(0.2, 1.0)}
	if frame % 211 == 5:
		render.listener = Vector3(NAN, 0.0, 0.0) # invalid listener
	if frame % 389 == 17:
		render.tick = -1 # no accepted tick
	return render


func _player_state(player: AudioStreamPlayer3D) -> Array:
	return [player.name, player.volume_db, player.pitch_scale, player.global_position, player.playing,
		player.stream.resource_path if player.stream != null else "", player.stream.get_length() if player.stream != null else 0.0]


func _state(rig: Variant) -> Array:
	var motion: Array = []
	for key: Variant in rig._motion_players:
		motion.append(_player_state(rig._motion_players[key].player))
	var events: Array = []
	for player: AudioStreamPlayer3D in rig._event_players:
		events.append(_player_state(player))
	var core: Array = rig._core.mechanical_core_state() if rig._core != null else _reference_core(rig)
	return [motion, events, rig.diagnostics(), core, rig._accepted_events]


## The reference's voices in mechanical_core_state's layout.
func _reference_core(rig: Variant) -> Array:
	var motion: Array = []
	for key: Variant in rig._motion_players:
		var slot: Dictionary = rig._motion_players[key]
		motion.append([str(key), float(slot.get("gain", 0.0)), float(slot.get("pitch", 1.0)), float(slot.get("offset", 0.0))])
	var events: Array = []
	for i: int in rig._event_players.size():
		var pending: Dictionary = rig._pending_events[i]
		events.append([rig._event_roles[i], rig._event_source_ids[i], rig._event_base_gains[i], rig._event_envelopes[i],
			rig._event_releasing[i], str(pending.get("role", "")), str(pending.get("source", ""))])
	return [motion, events, rig._scene_gain, rig._engine_mask, rig._stale_tick_s]


func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if a is Array and b is Array and a.size() == b.size():
		for i: int in a.size():
			var inner := _first_difference(a[i], b[i], "%s[%d]" % [path, i])
			if not inner.is_empty():
				return inner
		return ""
	if a is Dictionary and b is Dictionary and a.keys() == b.keys():
		for key: Variant in a:
			var inner := _first_difference(a[key], b[key], "%s.%s" % [path, key])
			if not inner.is_empty():
				return inner
		return ""
	return "" if var_to_bytes(a) == var_to_bytes(b) else "%s native=%s reference=%s" % [path, a, b]


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
