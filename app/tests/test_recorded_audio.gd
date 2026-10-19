extends SceneTree

const SoundscapeScript = preload("res://audio/soundscape.gd")
const WindsockAudioScript = preload("res://audio/windsock_audio.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const MIX_RATE: int = 22050
const LOOP_FRAMES: int = 512
const RECORDED_PATH: String = "res://assets/audio/soundscape/recorded/"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + (" — " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _run() -> void:
	var source: AudioStreamWAV = _make_loop()
	var guarded: AudioStreamWAV = SoundscapeScript.seamless_loop(source)
	var guard_bytes: int = SoundscapeScript.LOOP_GUARD_FRAMES * 2
	var guard_ok: bool = guarded.loop_mode == AudioStreamWAV.LOOP_FORWARD \
		and guarded.loop_begin == 0 and guarded.loop_end == LOOP_FRAMES \
		and guarded.data.size() == source.data.size() + guard_bytes \
		and guarded.data.slice(guarded.data.size() - guard_bytes) == source.data.slice(0, guard_bytes)
	_check("recorded loop fixture has the existing 64-frame PCM wrap guard", guard_ok)

	var owner := Node3D.new()
	root.add_child(owner)
	var anchor := Vector3(8.0, 2.0, -5.0)
	var controller = WindsockAudioScript.new()
	_check("controller configures a spatial player on the live environment bus",
		controller.configure(owner, &"Master", guarded, anchor))
	var player: AudioStreamPlayer3D = controller.player
	_check("configure positions the player quietly without starting at the origin",
		player != null and not player.playing and player.volume_db <= -79.9
		and player.global_position.is_equal_approx(anchor))
	_check("player uses bounded local spatial settings and leaves engine Doppler off",
		player.unit_size == 2.0 and player.max_distance == 55.0 and player.panning_strength == 0.75
		and player.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED)

	controller.update({wind_speed = 0.0, windsock_inflation = 0.0}, 1.0 / 60.0, 1.0)
	_check("calm wind keeps the fabric loop silent", not player.playing and player.volume_db <= -79.9)

	var moving_anchor := Vector3(-17.0, 4.0, 11.0)
	var strong: Dictionary = {fabric_source = moving_anchor, wind_speed = 15.0, windsock_inflation = 0.0}
	for _i: int in 180:
		controller.update(strong, 1.0 / 60.0, 1.0)
	var loose_level: float = db_to_linear(player.volume_db)
	_check("strong wind starts the loop only after placing it at the sock", player.playing
		and player.global_position.is_equal_approx(moving_anchor), "playing=%s pos=%s" % [player.playing, player.global_position])
	_check("strong-wind fabric stays within its quiet bounded gain", loose_level > 0.20 and loose_level <= 0.221,
		"linear=%.4f" % loose_level)

	var taut: Dictionary = strong.duplicate()
	taut.windsock_inflation = 1.0
	for _i: int in 180:
		controller.update(taut, 1.0 / 60.0, 1.0)
	var taut_level: float = db_to_linear(player.volume_db)
	_check("loose fabric is slightly louder than full inflation", loose_level > taut_level
		and taut_level > 0.17 and taut_level < loose_level, "loose=%.4f taut=%.4f" % [loose_level, taut_level])

	for _i: int in 180:
		controller.update(taut, 1.0 / 60.0, 0.4)
	var quarter_level: float = db_to_linear(player.volume_db)
	_check("shared soundscape gain scales the fabric level directly", absf(quarter_level - taut_level * 0.4) < 0.001,
		"full=%.4f at 0.4 mix=%.4f" % [taut_level, quarter_level])

	controller.update(taut, 1.0 / 60.0, 0.0)
	var dummy_driver: bool = AudioServer.get_driver_name() == "Dummy"
	_check("zero shared gain mutes the stream and suspends it on native audio drivers",
		player.volume_db <= -79.9 and (dummy_driver or player.stream_paused),
		"driver=%s paused=%s playing=%s volume=%.1f dB"
		% [AudioServer.get_driver_name(), player.stream_paused, player.playing, player.volume_db])
	controller.update(taut, 1.0 / 60.0, 1.0)
	_check("resume unsuspends the same loop", (dummy_driver or not player.stream_paused) and player.playing)

	var bad_position: Dictionary = {fabric_source = "invalid", wind_speed = 15.0, windsock_inflation = 0.0}
	controller.update(bad_position, 1.0 / 60.0, 1.0)
	_check("invalid source positions fall back to the configured anchor", player.global_position.is_equal_approx(anchor))
	var bus_count_before: int = AudioServer.bus_count
	var rebuilt_bus: StringName = StringName("Windsock Test Bus %d" % Time.get_ticks_usec())
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, rebuilt_bus)
	_check("rebind stops playback and moves the player to the rebuilt bus",
		controller.rebind(rebuilt_bus) and not player.playing and player.bus == rebuilt_bus
		and player.volume_db <= -79.9)
	controller.update(strong, 1.0 / 60.0, 1.0)
	_check("the first positioned update after rebind restarts playback", player.playing
		and player.global_position.is_equal_approx(moving_anchor))
	controller.reset()
	_check("reset stops the player and clears its level", not player.playing and player.volume_db <= -79.9)
	controller.update(strong, 1.0 / 60.0, 1.0)
	_check("an active update after reset can start the loop again", player.playing)
	controller.stop()
	_check("stop leaves the stream silent for bus teardown", not player.playing and player.volume_db <= -79.9)
	owner.free()
	AudioServer.remove_bus(AudioServer.get_bus_index(rebuilt_bus))
	_check("test player releases its temporary environment bus", AudioServer.bus_count == bus_count_before,
		"expected=%d actual=%d" % [bus_count_before, AudioServer.bus_count])
	var recorded_sources: Dictionary = _test_recorded_assets()
	if recorded_sources.size() == 3:
		await _test_soundscape_integration(recorded_sources)
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_loop() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(LOOP_FRAMES * 2)
	for frame: int in LOOP_FRAMES:
		var sample: int = roundi(12000.0 * sin(TAU * 17.0 * float(frame) / LOOP_FRAMES))
		data.encode_s16(frame * 2, sample)
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = LOOP_FRAMES
	return wav


func _test_recorded_assets() -> Dictionary:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECORDED_PATH + "manifest.json"))
	var entries: Array = manifest.get("assets", []) if manifest is Dictionary else []
	_check("recorded wind manifest describes all three loops", manifest is Dictionary and entries.size() == 3)
	if entries.size() != 3:
		return {}
	var streams: Dictionary = {}
	var decoded_bytes: int = 0
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var filename: String = str(entry.get("file", ""))
		var stream: AudioStreamWAV = load(RECORDED_PATH + filename) as AudioStreamWAV
		var sample_count: int = int(entry.get("sample_count", 0))
		var expected_duration: float = float(entry.get("duration_s", 0.0))
		var hash_matches: bool = FileAccess.get_sha256(RECORDED_PATH + filename) == str(entry.get("sha256", ""))
		var pcm_ok: bool = stream != null and stream.mix_rate == MIX_RATE and not stream.stereo \
			and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.data.size() == sample_count * 2
		var duration_ok: bool = stream != null and expected_duration >= 18.0 \
			and absf(stream.get_length() - expected_duration) < 0.001
		_check("%s matches its manifest hash and imports as mono 22.05 kHz PCM16" % filename,
			hash_matches and pcm_ok,
			"hash=%s pcm=%s rate=%d bytes=%d expected=%d" % [hash_matches, pcm_ok,
				stream.mix_rate if stream != null else 0, stream.data.size() if stream != null else 0, sample_count * 2])
		_check("%s retains its recorded long-form loop duration" % filename, duration_ok,
			"actual=%.3f s expected=%.3f s" % [stream.get_length() if stream != null else 0.0, expected_duration])
		if stream == null:
			continue
		streams[filename] = stream
		decoded_bytes += stream.data.size()
		var guarded: AudioStreamWAV = SoundscapeScript.seamless_loop(stream)
		_check("%s passes the production 64-frame loop guard" % filename,
			_loop_guard_ok(guarded, stream, sample_count),
			"loop_end=%d frames=%d bytes=%d" % [guarded.loop_end, sample_count, guarded.data.size()])
	_check("recorded manifest PCM total matches loaded source bytes",
		decoded_bytes == int(manifest.get("decoded_pcm_bytes", -1)),
		"loaded=%d manifest=%d" % [decoded_bytes, int(manifest.get("decoded_pcm_bytes", -1))])
	return streams


func _loop_guard_ok(guarded: AudioStreamWAV, source: AudioStreamWAV, expected_frames: int) -> bool:
	var guard_bytes: int = SoundscapeScript.LOOP_GUARD_FRAMES * 2
	return guarded != null and source != null and guarded.format == AudioStreamWAV.FORMAT_16_BITS \
		and guarded.mix_rate == source.mix_rate and not guarded.stereo \
		and guarded.loop_mode == AudioStreamWAV.LOOP_FORWARD and guarded.loop_begin == 0 \
		and guarded.loop_end == expected_frames and guarded.data.size() == source.data.size() + guard_bytes \
		and guarded.data.slice(0, source.data.size()) == source.data \
		and guarded.data.slice(guarded.data.size() - guard_bytes) == source.data.slice(0, guard_bytes)


func _test_soundscape_integration(recorded_sources: Dictionary) -> void:
	var loaded: Dictionary = FieldLoader.load_from()
	_check("default field loads for recorded-audio integration", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		return
	var field: Dictionary = (loaded.get("field", {}) as Dictionary).duplicate(true)
	var windsock_count: int = 0
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.get("type", "") == "windsock":
			windsock_count += 1
	_check("default field has exactly one windsock cue", windsock_count == 1, "count=%d" % windsock_count)

	var bus_count_before: int = AudioServer.bus_count
	var rig: Variant = SoundscapeScript.new()
	root.add_child(rig)
	rig.configure(field, "glow_prop", 94117)
	var fabric: Variant = rig.fabric_audio
	var fabric_player: AudioStreamPlayer3D = fabric.player if fabric != null else null
	var fabric_nodes: Array[Node] = rig.find_children("WindsockFabric", "AudioStreamPlayer3D", true, false)
	var cue_anchor := Vector3.ZERO
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.get("type", "") == "windsock":
			cue_anchor = Vector3(float(cue.east), float(cue.pole_height), -float(cue.north))
			break
	_check("default soundscape creates one fabric player on its environment bus outside the 14-voice pool",
			fabric != null and fabric_player != null and fabric_nodes.size() == 1 and rig.voices.size() == 14
			and fabric_player.bus == rig.environment_bus(),
			"fabric=%s nodes=%d voices=%d bus=%s environment=%s" % [fabric != null, fabric_nodes.size(),
				rig.voices.size(), fabric_player.bus if fabric_player != null else &"", rig.environment_bus()])
	_check("fabric configure anchors quietly before playback, away from origin-pop behavior",
		fabric_player != null and not fabric_player.playing and fabric_player.volume_db <= -79.9
		and fabric_player.global_position.is_equal_approx(cue_anchor),
		"expected=%s actual=%s" % [cue_anchor, fabric_player.global_position if fabric_player != null else Vector3.ZERO])

	var actual_by_file: Dictionary = {
		"wind_low.wav": rig.voices[3].stream as AudioStreamWAV,
		"wind_high.wav": rig.voices[4].stream as AudioStreamWAV,
		"windsock_fabric.wav": fabric_player.stream as AudioStreamWAV if fabric_player != null else null,
	}
	for filename: String in ["wind_low.wav", "wind_high.wav", "windsock_fabric.wav"]:
		var source: AudioStreamWAV = recorded_sources.get(filename) as AudioStreamWAV
		var integrated: AudioStreamWAV = actual_by_file.get(filename) as AudioStreamWAV
		var sample_count: int = roundi(source.get_length() * source.mix_rate) if source != null else 0
		_check("Soundscape uses the recorded, guarded %s stream" % filename,
			_loop_guard_ok(integrated, source, sample_count),
			"source=%s integrated=%s" % [source != null, integrated != null])
	_check("recorded wind loops and fabric share the environment route",
		rig.voices[3].bus == rig.environment_bus() and rig.voices[4].bus == rig.environment_bus()
		and fabric_player != null and fabric_player.bus == rig.environment_bus())

	var calm_snapshot: Dictionary = _sound_snapshot(0.0, Vector3(-21.0, 5.0, 13.0), 0.0)
	for frame: int in 60:
		calm_snapshot.time = float(frame) / 60.0
		rig.update_sound(calm_snapshot, 1.0 / 60.0)
	_check("integrated fabric stays silent in calm wind", fabric_player != null and fabric_player.volume_db <= -79.9
		and not fabric_player.playing)

	var gust_snapshot: Dictionary = _sound_snapshot(15.0, Vector3(73.0, 8.0, -42.0), 1.0)
	for frame: int in 90:
		gust_snapshot.time = 1.0 + float(frame) / 60.0
		rig.update_sound(gust_snapshot, 1.0 / 60.0)
	var gust_level: float = db_to_linear(fabric_player.volume_db) if fabric_player != null else 0.0
	_check("integrated fabric source follows the current snapshot at bounded strong-wind gain",
		fabric_player != null and fabric_player.playing and fabric_player.global_position.is_equal_approx(gust_snapshot.fabric_source)
		and gust_level > 0.0 and gust_level <= 0.221,
		"position=%s expected=%s level=%.4f" % [fabric_player.global_position if fabric_player != null else Vector3.ZERO,
			gust_snapshot.fabric_source, gust_level])
	for frame: int in 180:
		gust_snapshot.time = 2.5 + float(frame) / 60.0
		gust_snapshot.wind_speed = 0.0
		rig.update_sound(gust_snapshot, 1.0 / 60.0)
	_check("integrated fabric fades to silence when the actual wind calms", fabric_player != null and fabric_player.volume_db <= -79.9)

	var gains: Array[float] = []
	for fps: int in [30, 60, 144]:
		rig.reset_observer()
		var snapshot: Dictionary = _sound_snapshot(15.0, Vector3(73.0, 8.0, -42.0), 0.0)
		for frame: int in fps * 2:
			snapshot.time = float(frame) / float(fps)
			rig.update_sound(snapshot, 1.0 / float(fps))
		gains.append(db_to_linear(fabric_player.volume_db))
	var gain_spread: float = float(gains.max()) - float(gains.min()) if gains.size() == 3 else INF
	_check("integrated recorded fabric gain agrees at 30, 60 and 144 updates per second",
		gains.size() == 3 and gains.min() > 0.0 and gain_spread < 0.001,
		"gains=%s spread=%.6f" % [gains, gain_spread])

	var environment_bus: StringName = rig.environment_bus()
	root.remove_child(rig)
	_check("detaching stops fabric and releases its environment bus", not fabric_player.playing
		and AudioServer.get_bus_index(environment_bus) == -1 and AudioServer.bus_count == bus_count_before,
		"bus=%d count=%d expected=%d" % [AudioServer.get_bus_index(environment_bus), AudioServer.bus_count, bus_count_before])
	root.add_child(rig)
	_check("reattaching rebuilds and rebinds the same fabric player", fabric_player.bus == rig.environment_bus()
		and AudioServer.get_bus_index(rig.environment_bus()) > 0 and not fabric_player.playing
		and fabric_player.volume_db <= -79.9, "bus=%s" % fabric_player.bus)
	gust_snapshot.time = 0.0
	gust_snapshot.wind_speed = 15.0
	rig.update_sound(gust_snapshot, 1.0 / 60.0)
	_check("reattached soundscape restarts fabric from the positioned snapshot", fabric_player.playing
		and fabric_player.global_position.is_equal_approx(gust_snapshot.fabric_source))
	rig.queue_free()
	await process_frame
	await process_frame
	_check("integrated soundscape frees its buses after fabric stops", AudioServer.bus_count == bus_count_before,
		"expected=%d actual=%d" % [bus_count_before, AudioServer.bus_count])

	var no_sock_field: Dictionary = field.duplicate(true)
	var retained_cues: Array[Dictionary] = []
	for cue: Dictionary in field.get("flight_cues", []):
		if cue.get("type", "") != "windsock":
			retained_cues.append(cue)
	no_sock_field.flight_cues = retained_cues
	var no_sock_rig: Variant = SoundscapeScript.new()
	root.add_child(no_sock_rig)
	no_sock_rig.configure(no_sock_field, "glow_prop", 94118)
	var no_sock_nodes: Array[Node] = no_sock_rig.find_children("WindsockFabric", "AudioStreamPlayer3D", true, false)
	_check("a field without a windsock creates no fabric source", no_sock_rig.fabric_audio == null and no_sock_nodes.is_empty())
	no_sock_rig.queue_free()
	await process_frame
	await process_frame
	_check("field without a windsock releases all soundscape buses", AudioServer.bus_count == bus_count_before)


func _sound_snapshot(wind_speed: float, fabric_source: Vector3, time_s: float) -> Dictionary:
	return {
		source = Vector3(30.0, 0.0, 0.0), listener = Vector3.ZERO, paused = false,
		sound_speed = 343.0, rpm = 6000.0, max_rpm = 12000.0, load = 0.5, throttle = 0.5,
		airspeed = 35.0, wind_speed = wind_speed, wind_direction = Vector3.RIGHT,
		sun_elevation = 35.0, running = true, time = time_s,
		fabric_source = fabric_source, windsock_inflation = 0.25,
	}
