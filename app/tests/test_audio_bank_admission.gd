extends SceneTree

const Soundscape = preload("res://audio/soundscape.gd")
const Powertrain = preload("res://audio/powertrain_audio.gd")
var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ", label, " ", detail)


func snapshot(running: bool, paused := false) -> Dictionary:
	return {source = Vector3(8.0, 0.0, 0.0), listener = Vector3.ZERO, paused = paused,
		sound_speed = 343.0, rpm = 6000.0, max_rpm = 12000.0, load = 0.5, throttle = 0.5,
		airspeed = 20.0, wind_speed = 0.0, wind_direction = Vector3.RIGHT, sun_elevation = 35.0,
		running = running, blades = 2}


func _run() -> void:
	root.audio_listener_enable_3d = true
	var args := OS.get_cmdline_user_args()
	var scenario := args[0] if not args.is_empty() else "full"
	var expected_layers: int = {full = 2, partial = 1, empty = 0, badfamily = 0,
		badentry = 0, missingfile = 0, invalidjson = 0, no_usable = 0}.get(scenario, -1)
	check("known fixture", expected_layers >= 0, scenario)
	var before := AudioServer.bus_count
	var profile := {id = "fixture", family = "gasoline", max_rpm = 12000.0, blades = 2, trim_db = 0.0}
	var rig: Variant = Soundscape.new()
	root.add_child(rig)
	rig.configure({}, "glow_prop", 78123, "", profile)
	var fallback: Variant = Soundscape.new()
	root.add_child(fallback)
	var absent := profile.duplicate()
	absent.family = "not_installed_fixture"
	fallback.configure({}, "glow_prop", 78123, "", absent)
	var bank: Node = rig.powertrain
	var admitted := bank != null
	check("actual bank admission and layer count", admitted == (expected_layers > 0)
		and (not admitted or bank.players.size() == expected_layers),
		"case=%s actual=%s" % [scenario, bank.players.size() if admitted else 0])
	var labels := ["Motor", "Propeller", "Airframe", "WindLow", "WindHigh", "Foliage0", "Foliage1",
		"Foliage2", "Foliage3", "Bird0", "Bird1", "Bird2", "Crickets0", "Crickets1"]
	var order_ok: bool = rig.voices.size() == labels.size()
	if order_ok:
		for i: int in labels.size(): order_ok = order_ok and rig.voices[i].name == labels[i]
	check("all fourteen indexed voice slots retain order", order_ok)
	var expected_offsets := [1, 2, 3, 4, 5, 6, 7, 8, 12, 13] if admitted else [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13]
	check("pending loop start order and phase are preserved", rig._start_offsets.keys() == expected_offsets
		and rig._start_offsets[1] == 0.0 and (admitted or rig._start_offsets[0] == 0.0), str(rig._start_offsets))
	var offsets_equal: bool = rig.rng.state == fallback.rng.state
	for i: int in [2, 3, 4, 5, 6, 7, 8, 12, 13]:
		offsets_equal = offsets_equal and rig._start_offsets[i] == fallback._start_offsets[i]
	check("bank admission preserves seeded ambience state and offsets", offsets_equal)
	check("gasoline keeps guarded propeller and only keeps motor on fallback",
		rig.voices[1].stream != null and (rig.voices[0].stream == null) == admitted)
	if admitted:
		var bank_loops_match := true
		for index: int in bank.players.size():
			var source: AudioStreamWAV = load(Powertrain.ASSET_PATH + str(bank.layers[index].file)) as AudioStreamWAV
			var loop: AudioStreamWAV = bank.players[index].stream as AudioStreamWAV
			if source == null or loop == null:
				bank_loops_match = false
				continue
			var stride: int = (2 if source.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if source.stereo else 1)
			var frames: int = source.data.size() / stride
			bank_loops_match = bank_loops_match and loop.loop_end == frames and loop.loop_begin == 0 \
				and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD \
				and loop.data.size() == source.data.size() + mini(Powertrain.GUARD_FRAMES, frames) * stride \
				and loop.data.slice(0, source.data.size()) == source.data \
				and loop.data.slice(source.data.size()) == source.data.slice(0, mini(Powertrain.GUARD_FRAMES, frames) * stride)
		check("every admitted bank layer keeps its exact source and guarded PCM bytes", bank_loops_match)
	for index: int in [0, 1]:
		if index == 0 and admitted: continue
		var a: AudioStreamWAV = rig.voices[index].stream
		var b: AudioStreamWAV = fallback.voices[index].stream
		check("retained loop bytes and guard match legacy slot %d" % index,
			a != null and b != null and a.data == b.data and a.loop_begin == b.loop_begin
			and a.loop_end == b.loop_end and a.loop_mode == b.loop_mode)
	if admitted:
		var playing := snapshot(true)
		for i: int in 30: rig.update_sound(playing, 0.05)
		var powered_level: float = rig._levels[1]
		var stopped := snapshot(false)
		for i: int in 30: rig.update_sound(stopped, 0.05)
		var coast_level: float = rig._levels[1]
		var coast_playing: bool = rig.voices[1].playing
		for i: int in 30: rig.update_sound(playing, 0.05)
		check("gasoline cut and restart retain only the propeller coast layer",
			powered_level == 0.0 and coast_level > 0.0 and coast_playing and rig._levels[1] < coast_level * 0.01,
			"powered=%s coast=%s restart=%s" % [powered_level, coast_level, rig._levels[1]])
		var paused := snapshot(true, true)
		for i: int in 5: rig.update_sound(paused, 0.05)
		check("pause reaches the silent mix floor", rig.gain == 0.0)
		root.remove_child(rig)
		root.add_child(rig)
		rig.update_sound(playing, 0.05)
		check("re-entry restarts gasoline coast and bank on live buses", rig.voices[1].playing
			and rig.powertrain.players[0].playing and AudioServer.get_bus_index(rig.voices[1].bus) > 0)
	root.remove_child(rig)
	rig.free()
	root.remove_child(fallback)
	fallback.free()
	if scenario == "full":
		_test_other_families()
	await process_frame
	await process_frame
	check("bank and fallback disposal restore bus count", AudioServer.bus_count == before)
	print("Audio bank admission %s: %d checks, %d failed" % [scenario, checks, failed])
	quit(1 if failed else 0)


func _test_other_families() -> void:
	for family: String in ["electric", "turbine", "rotor"]:
		var propulsion := "electric_prop" if family == "electric" else ("turbine" if family == "turbine" else "glow_prop")
		var profile := {id = "fixture-" + family, family = family, max_rpm = 12000.0, blades = 2, trim_db = 0.0}
		var rig: Variant = Soundscape.new()
		root.add_child(rig)
		rig.configure({}, propulsion, 78123, "", profile)
		var fallback: Variant = Soundscape.new()
		root.add_child(fallback)
		var absent := profile.duplicate()
		absent.family = "not_installed_fixture"
		fallback.configure({}, propulsion, 78123, "", absent)
		var offsets_match: bool = rig.rng.state == fallback.rng.state
		for index: int in [2, 3, 4, 5, 6, 7, 8, 12, 13]:
			offsets_match = offsets_match and rig._start_offsets[index] == fallback._start_offsets[index]
		check(family + " bank omits both legacy streams and retains start order", rig.powertrain != null
			and rig.voices.size() == 14 and rig.voices[0].stream == null and rig.voices[1].stream == null
			and rig._start_offsets.keys() == [2, 3, 4, 5, 6, 7, 8, 12, 13] and offsets_match)
		root.remove_child(rig)
		rig.free()
		root.remove_child(fallback)
		fallback.free()
	var glow: Variant = Soundscape.new()
	root.add_child(glow)
	glow.configure({}, "glow_prop", 78123, "", {family = "glow_2t", max_rpm = 12000.0})
	check("procedural glow retains its player without legacy loops", glow.powertrain == null and glow.glow_player != null
		and glow.voices[0].stream == null and glow.voices[1].stream == null
		and glow._start_offsets.keys() == [2, 3, 4, 5, 6, 7, 8, 12, 13])
	glow.update_sound(snapshot(true, true), 0.05)
	check("initially paused glow keeps its pending start", glow._glow_pending_start and not glow.glow_player.playing)
	root.remove_child(glow)
	root.add_child(glow)
	glow.update_sound(snapshot(true), 0.05)
	check("glow restarts after re-entry", glow.glow_player.playing and AudioServer.get_bus_index(glow.glow_player.bus) > 0)
	root.remove_child(glow)
	glow.free()

