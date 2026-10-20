## AUD-15: recorded powertrain identity, RPM bands, observer reset and pause behavior.
extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Powertrain = preload("res://audio/powertrain_audio.gd")
const Soundscape = preload("res://audio/soundscape.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	var airplanes: Array = Catalog.airplane_flyable_entries()
	_check("catalog has eight fixed-wing configurations", airplanes.size() == 8, str(airplanes.size()))
	for entry: Dictionary in airplanes:
		var id := str(entry.id)
		var profile: Dictionary = Powertrain.profile_for(id, {})
		_check("profile preserves aircraft identity: " + id, str(profile.get("id", "")) == id)
		_check("profile has usable RPM reference: " + id,
			float(profile.get("max_rpm", 0.0)) > 0.0 and int(profile.get("blades", 0)) >= 2)
	_check("P-51 maps to gasoline bank", Powertrain.profile_for("p51d-mustang-120", {}).family == "gasoline")
	_check("Avanti maps to turbine bank", Powertrain.profile_for("sebart-avanti-s-a200-p100rx", {"kind": "turbine"}).family == "turbine")
	_check("Timber maps to electric bank", Powertrain.profile_for("turbo-lumber-evolution", {"kind": "electric_prop"}).family == "electric")
	_check("X-Cell maps to rotor bank", Powertrain.profile_for("xcell-60-research", {}).family == "rotor")
	_test_imported_banks()

	var bands := Powertrain.band_weights(sqrt(6000.0 * 12000.0), PackedFloat64Array([6000.0, 12000.0]))
	_check("adjacent RPM layers use an equal-power midpoint",
		bands.size() == 2 and absf(bands[0] * bands[0] + bands[1] * bands[1] - 1.0) < 1e-9,
		str(bands))
	_check("distance law is bounded at the source", is_equal_approx(Powertrain.distance_gain(0.0), 8.0 / 3.0))
	_check("distance law reaches silence at its far bound", Powertrain.distance_gain(1500.0) == 0.0)

	# Attach one deterministic looping test layer so behavior is exercised without a particular
	# licensed recording manifest or a live aircraft scene.
	var rig := Powertrain.new()
	rig.profile = {id = "test-rig", family = "gasoline", max_rpm = 12000.0, trim_db = 0.0}
	root.add_child(rig)
	var pcm := PackedByteArray()
	for _i: int in 1024:
		pcm.append(0)
		pcm.append(0)
	var source := AudioStreamWAV.new()
	source.format = AudioStreamWAV.FORMAT_16_BITS
	source.mix_rate = 48000
	source.data = pcm
	var player := AudioStreamPlayer3D.new()
	player.stream = Powertrain.guarded_loop(source)
	rig.add_child(player)
	rig.players.append(player)
	rig.layers.append({rpm = 6000.0, gain = 1.0})
	rig.levels.resize(1)
	var stopped := {rpm = 0.0, max_rpm = 12000.0, running = false, throttle = 0.0, load = 0.0,
		source = Vector3.ZERO, listener = Vector3.ZERO, paused = false}
	rig.update_sound(stopped, 1.0 / 60.0)
	_check("initial stopped snapshot stays silent", rig.last_targets.get("running", true) == false and rig.levels[0] == 0.0)
	var running := stopped.duplicate(true)
	running.rpm = 7200.0
	running.running = true
	running.throttle = 0.6
	running.load = 0.5
	# Starting from an already accepted running snapshot creates only the ordinary smoothed bank level.
	rig.reset_observer()
	rig.update_sound(running, 1.0 / 60.0)
	_check("initial already-running snapshot follows accepted RPM without a fabricated start edge",
		float(rig.last_targets.get("accepted_rpm", -1.0)) == 7200.0 and rig.last_targets.get("running", false)
		and rig.levels[0] >= 0.0 and rig.levels[0] < float(rig.last_targets.get("level", 1.0)))
	var paused := running.duplicate(true)
	paused.paused = true
	rig.update_sound(paused, 1.0 / 60.0, 0.0)
	await process_frame
	_check("paused zero-gain snapshot holds the accepted paused state at the silent floor",
		bool(rig.last_targets.get("paused", false)) and player.volume_db <= -90.0,
		"playing=%s paused=%s volume_db=%s targets=%s" % [player.playing, player.stream_paused, player.volume_db, rig.last_targets])
	rig.reset_observer()
	_check("reset stops and silences every layer", not player.playing and rig.levels[0] == 0.0 and player.volume_db <= -90.0)
	var paused_before_start := running.duplicate(true)
	paused_before_start.paused = true
	rig.update_sound(paused_before_start, 1.0 / 60.0, 0.0)
	_check("initially paused powertrain retains its pending start without playback",
		not player.playing and not bool(rig.get("_started")) and player.volume_db <= -90.0,
		"playing=%s started=%s volume_db=%.2f" % [player.playing, rig.get("_started"), player.volume_db])
	rig.reset_observer()

	await _test_glow_pause()
	await _test_helicopter_audio_read_only()
	# Let the audio mixer retire streams released by the scene before the fast Dummy test quits.
	await create_timer(0.1, true, false, true).timeout

	print("AUD-15 powertrain checks: %d, failed: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_imported_banks() -> void:
	var manifest_path := "res://assets/audio/powertrains/BANKS.json"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) \
		if FileAccess.file_exists(manifest_path) else null
	_check("recorded-bank manifest imports as four named families", manifest is Dictionary
		and ["gasoline", "electric", "turbine", "rotor"].all(func(family: String) -> bool:
			return (manifest as Dictionary).get(family, []) is Array))
	if not manifest is Dictionary:
		return
	var layer_total := 0
	var pcm_valid := true
	for family: String in ["gasoline", "electric", "turbine", "rotor"]:
		var entries: Array = manifest.get(family, [])
		layer_total += entries.size()
		var bank: Node3D = Powertrain.new()
		root.add_child(bank)
		var profile := {id = "test-" + family, family = family, max_rpm = 12000.0, blades = 2, trim_db = 0.0}
		var loaded: bool = bank.configure(profile, &"Master")
		_check("%s recorded family configures from imported WAVs" % family,
			loaded and bank.layers.size() == entries.size() and bank.players.size() == entries.size(),
			"manifest=%d loaded=%d" % [entries.size(), bank.players.size()])
		for index: int in range(mini(entries.size(), bank.players.size())):
			var layer: Dictionary = bank.layers[index]
			var source: AudioStreamWAV = load(Powertrain.ASSET_PATH + str(layer.get("file", ""))) as AudioStreamWAV
			var loop: AudioStreamWAV = bank.players[index].stream as AudioStreamWAV
			if source == null or loop == null:
				pcm_valid = false
				continue
			var stride: int = (2 if source.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if source.stereo else 1)
			var frames: int = source.data.size() / stride
			var guard_frames: int = mini(Powertrain.GUARD_FRAMES, frames)
			var valid: bool = source.format == AudioStreamWAV.FORMAT_16_BITS and source.mix_rate > 0 \
				and frames > 0 and loop.loop_begin == 0 and loop.loop_end == frames \
				and loop.data.size() == source.data.size() + guard_frames * stride \
				and loop.data.slice(0, source.data.size()) == source.data \
				and loop.data.slice(source.data.size()) == source.data.slice(0, guard_frames * stride)
			pcm_valid = pcm_valid and valid
			print("AUD-15 bank layer %s/%s: %d frames at %d Hz, %.3f s, fmt=%d stereo=%s bytes=%d/%d loop_end=%d guarded=%s" % [family,
				str(layer.get("file", "")), frames, source.mix_rate, source.get_length(), source.format,
				source.stereo, source.data.size(), loop.data.size(), loop.loop_end, valid])
		root.remove_child(bank)
		bank.free()
	_check("all six installed bank layers are PCM with exact loop guards", layer_total == 6 and pcm_valid,
		"layers=%d pcm_valid=%s" % [layer_total, pcm_valid])


func _glow_snapshot(paused: bool) -> Dictionary:
	return {
		source = Vector3(8.0, 0.0, 0.0), listener = Vector3.ZERO, paused = paused,
		sound_speed = 343.0, rpm = 6000.0, max_rpm = 12000.0, load = 0.5, throttle = 0.5,
		airspeed = 10.0, wind_speed = 0.0, wind_direction = Vector3.RIGHT, sun_elevation = 35.0,
		running = true, blades = 2,
		glow = {family = "glow_2t", rpm = 6000.0, max_rpm = 12000.0,
			running = true, firing_fraction = 1.0, load = 0.5, throttle = 0.5, blade_count = 2},
	}


func _test_glow_pause() -> void:
	var profile := {id = "stik-glow-61fx-2t", family = "glow_2t", max_rpm = 12000.0, blades = 2, trim_db = 0.0}
	var initially_paused: Node = Soundscape.new()
	root.add_child(initially_paused)
	initially_paused.configure({}, "glow_prop", 4102026, "", profile)
	var idle_paused := _glow_snapshot(true)
	initially_paused.update_sound(idle_paused, 1.0 / 60.0)
	await process_frame
	var initial_player: AudioStreamPlayer3D = initially_paused.get("glow_player")
	var pending_loops_silent := true
	for voice: AudioStreamPlayer3D in initially_paused.get("voices"):
		pending_loops_silent = pending_loops_silent and not voice.playing
	_check("initially paused glow profile does not start playback",
		initial_player != null and not initial_player.playing and bool(initially_paused.get("_glow_pending_start"))
		and pending_loops_silent,
		"playing=%s paused=%s pending=%s" % [initial_player.playing if initial_player != null else false,
			initial_player.stream_paused if initial_player != null else false,
			initially_paused.get("_glow_pending_start")])
	root.remove_child(initially_paused)
	initially_paused.free()

	var glow: Node = Soundscape.new()
	root.add_child(glow)
	glow.configure({}, "glow_prop", 4102026, "", profile)
	var active := _glow_snapshot(false)
	for _step: int in 14:
		glow.update_sound(active, 0.05)
	var player: AudioStreamPlayer3D = glow.get("glow_player")
	_check("glow voice is active before pause fade", player != null and not player.stream_paused
		and player.volume_db > -80.0 and float(glow.get("gain")) > 0.99,
		"player=%s gain=%.4f volume_db=%.2f" % [player != null, float(glow.get("gain")),
			player.volume_db if player != null else -120.0])
	var paused := active.duplicate(true)
	paused.paused = true
	for _step: int in 7:
		glow.update_sound(paused, 0.01)
	_check("glow pause remains unpaused during its audible fade",
		player != null and not player.stream_paused and float(glow.get("gain")) > 0.0 and player.volume_db > -90.0,
		"paused=%s gain=%.4f volume_db=%.2f" % [player.stream_paused if player != null else true,
			float(glow.get("gain")), player.volume_db if player != null else -120.0])
	for _step: int in 4:
		glow.update_sound(paused, 0.01)
	_check("glow pause reaches its silent floor while the generator remains active",
		player != null and float(glow.get("gain")) <= 0.0 and player.volume_db <= -90.0
		and player.playing and player.get_stream_playback() != null
		and float(glow.get("_glow_level")) > 0.0,
		"playing=%s paused=%s playback=%s gain=%.8f volume_db=%.2f" % [player.playing if player != null else false,
			player.stream_paused if player != null else false,
			player.get_stream_playback() if player != null else null,
			float(glow.get("gain")), player.volume_db if player != null else -120.0])
	root.remove_child(glow)
	glow.free()


func _test_helicopter_audio_read_only() -> void:
	var packed: PackedScene = load("res://helicopter_main.tscn") as PackedScene
	_check("production helicopter scene is available for the read-only audio checkpoint", packed != null)
	if packed == null:
		return
	var helicopter: Node3D = packed.instantiate() as Node3D
	helicopter.interactive_start = true
	root.add_child(helicopter)
	await process_frame
	var audio: Node = helicopter.get("_soundscape_audio") as Node
	_check("production helicopter route installs its audio adapter", audio != null)
	if audio == null or not str(helicopter.get("startup_error")).is_empty():
		root.remove_child(helicopter)
		helicopter.free()
		return
	var session: Node = helicopter.get("session") as Node
	var soundscape: Node = audio.get("soundscape") as Node
	var state_before: PackedFloat64Array = session.sim.state.duplicate()
	var continuous_before: PackedFloat64Array = session.sim.continuous.duplicate()
	var tick_before: int = int(session.sim.tick)
	var time_before: float = float(session.sim.time())
	var snapshot_before: Dictionary = audio.call("snapshot")
	var contacts_before: Array = audio.call("contact_snapshot")
	for index: int in 24:
		var accepted: Dictionary = audio.call("snapshot")
		soundscape.call("update_sound", accepted, 1.0 / 60.0)
		if index % 6 == 5:
			soundscape.call("reset_observer")
	var snapshot_after: Dictionary = audio.call("snapshot")
	var contacts_after: Array = audio.call("contact_snapshot")
	_check("repeated helicopter audio updates preserve accepted state and continuous RPM",
		session.sim.state == state_before and session.sim.continuous == continuous_before
		and int(session.sim.tick) == tick_before and is_equal_approx(float(session.sim.time()), time_before),
		"tick=%d→%d time=%.6f→%.6f" % [tick_before, int(session.sim.tick), time_before, float(session.sim.time())])
	_check("helicopter audio snapshot and skid contacts are unchanged by observation and resets",
		snapshot_before == snapshot_after and contacts_before == contacts_after,
		"rpm=%.2f→%.2f contacts=%d→%d" % [float(snapshot_before.get("rpm", -1.0)),
			float(snapshot_after.get("rpm", -1.0)), contacts_before.size(), contacts_after.size()])
	root.remove_child(helicopter)
	helicopter.free()
