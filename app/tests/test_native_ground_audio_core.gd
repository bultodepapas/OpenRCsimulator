extends SceneTree
## NK-7d: a GroundAudio rig on the native ground core and one on the GDScript reference, both in accepted-tick mode
## and fed the same accepted snapshots and frame updates, agree bit for bit after every call: every observe and
## touchdown-query answer, the diagnostics, touchdown count, each slot's roll and touchdown players (volume, pitch,
## position, playback), roll levels and pitch, and the accepted wheel states. The run covers airborne approach,
## touchdowns, bounces, rolling on each surface with and without roll, liftoff, pauses, rewinds, gaps and since_tick
## intervals, skipped ticks, rate changes, refused snapshots, wheels appearing and leaving, more wheels than slots
## allow and a detach. Skips (passes) without the verified library.

const GroundAudio := preload("res://audio/ground_audio.gd")
const FRAMES := 4000
const SURFACES: Array[String] = ["hard", "grass", "mown", "gravel", "rough", "water"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.audio_listener_enable_3d = true
	var status: Dictionary = load("res://sim/native_stage.gd").library_status()
	if not status.get("ok", false) or not ClassDB.class_exists(&"OpenRCNativeKernel") \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"ground_core_open"):
		print("NK7D_SKIP no native library with the ground core")
		quit(0)
		return
	var owner := Node3D.new()
	root.add_child(owner)
	var rigs: Array = []
	for native: bool in [true, false]:
		var rig: Variant = GroundAudio.new()
		rig.native_core_enabled = native
		rig.configure(owner, &"Master")
		rig.set_accepted_tick_observation(true)
		rigs.append(rig)
	var native: Variant = rigs[0]
	var reference: Variant = rigs[1]
	_check("the native rig binds its core and the reference does not", native._core != null and reference._core == null)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var tick := 1000
	var rate := 240.0
	var mismatched := 0
	var first := ""
	var touchdowns := 0
	var rolling_frames := 0
	var refused := 0
	for frame: int in FRAMES:
		var paused: bool = frame % 600 >= 560 and frame % 600 < 580
		if frame == 2000:
			for rig: Variant in rigs:
				owner.remove_child(rig)
				owner.add_child(rig) # _exit_tree resets
		if frame % 997 == 500:
			tick -= 30 # rewind
		if frame == 1500:
			rate = 120.0
		elif frame == 1700:
			rate = 240.0
		var ticks: int = 0 if paused else (4 if frame % 37 != 0 else 90)
		var answers: Array = []
		for k: int in maxi(ticks, 1):
			if not paused:
				tick += 1
			var use_since: bool = frame % 3 == 0 and ticks > 1
			if use_since and k < ticks - 1:
				# A skipped tick for every wheel, then one observation covering the interval.
				var ids := PackedStringArray(["left", "right", "tail"])
				var approaches := PackedFloat64Array([rng.randf_range(0.0, 3.0), -1.0, rng.randf_range(0.0, 1.0)])
				for rig: Variant in rigs:
					rig.note_skipped_tick(tick, ids, approaches)
				continue
			var snapshot := _snapshot(frame, tick, rate, paused, rng, use_since, ticks)
			for rig: Variant in rigs:
				answers.append(rig.observe_accepted(snapshot.duplicate(true)))
			var compressions := PackedFloat64Array([rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01), -0.02])
			var ids := PackedStringArray(["left", "right", "tail"])
			# Answers go in native/reference pairs.
			for query: int in 3:
				for rig: Variant in rigs:
					answers.append(rig.touchdown_possible() if query == 0
						else (rig.touchdown_possible_at(ids, compressions) if query == 1 else rig.accepted_tick()))
		refused += int(answers.size() > 1 and answers[1] == false)
		var listener := Vector3(rng.randf_range(-20.0, 20.0), 1.7, rng.randf_range(-20.0, 20.0))
		var engine_power: float = rng.randf_range(0.0, 1.0)
		var delta: float = [1.0 / 60.0, 1.0 / 144.0, 0.0, 0.2][frame % 4 if frame % 11 == 0 else 0]
		for rig: Variant in rigs:
			rig.update_contacts(tick, paused, [], engine_power, delta, listener, rate)
		var a := _state(native)
		var b := _state(reference)
		var answers_differ := false
		for i: int in range(0, answers.size(), 2):
			answers_differ = answers_differ or var_to_bytes(answers[i]) != var_to_bytes(answers[i + 1])
		if answers_differ or var_to_bytes(a) != var_to_bytes(b):
			mismatched += 1
			if first.is_empty():
				first = "frame %d: answers %s; %s" % [frame, answers, _first_difference(a, b, "state")]
		touchdowns = reference.touchdown_events
		rolling_frames += int(_any_roll(reference))
	print("ground core: %d frames, %d differ, %d touchdowns at the end, %d rolling frames, %d refused" % [FRAMES,
		mismatched, touchdowns, rolling_frames, refused])
	_check("every frame matches the reference", mismatched == 0, "%d differ; %s" % [mismatched, first])
	_check("the run exercises rolling, touchdowns and refusals", rolling_frames > 200 and refused > 3
		and int(reference.accepted_diagnostics().observed) > 5,
		"rolling=%d refused=%d diagnostics=%s" % [rolling_frames, refused, reference.accepted_diagnostics()])
	_check("the native core stays bound", native._core != null)
	print("native ground audio core: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _snapshot(frame: int, tick: int, rate: float, paused: bool, rng: RandomNumberGenerator, use_since: bool,
		ticks: int) -> Dictionary:
	# A slow cycle: approach, touchdown with bounces, a roll at varying speed and surface, liftoff.
	var phase: float = fmod(float(frame) / 400.0, 1.0)
	var contacts: Array = []
	var wheels: Array[String] = ["left", "right", "tail"]
	if frame % 800 > 700:
		wheels.append("nose") # a wheel appears
	if frame % 900 > 850:
		wheels.erase("tail") # and leaves
	if frame % 1300 == 77:
		for i: int in 7:
			wheels.append("extra%d" % i) # more wheels than slots allow: refused (above MAX_CONTACTS)
	for i: int in wheels.size():
		var loaded: bool = phase > 0.3 and phase < 0.85 and not (phase > 0.32 and phase < 0.34) # a bounce
		var force: float = rng.randf_range(80.0, 400.0) if loaded else rng.randf_range(0.0, 2.0)
		contacts.append({
			id = wheels[i],
			position = Vector3(float(i) - 1.0, 0.1, rng.randf_range(-0.2, 0.2)),
			normal_force_n = force,
			reference_load_n = rng.randf_range(100.0, 300.0),
			approach_speed_mps = rng.randf_range(0.0, 2.5) if phase < 0.31 else rng.randf_range(0.0, 0.3),
			rolling_speed_mps = rng.randf_range(0.0, 25.0) if loaded else 0.0,
			surface = SURFACES[(frame / 50 + i) % SURFACES.size()],
			roll_enabled = not (wheels[i] == "tail" and frame % 400 > 200),
		})
	var snapshot := {tick = tick, tick_rate = rate if frame % 211 != 5 else int(rate), paused = paused, contacts = contacts}
	if use_since:
		snapshot.since_tick = tick - ticks
	if frame % 173 == 11:
		contacts[0].normal_force_n = -1.0 # refused
	elif frame % 181 == 13:
		contacts[0].surface = 3 # refused
	elif frame % 191 == 17:
		snapshot.since_tick = 1.5 # refused
	return snapshot


func _any_roll(rig: Variant) -> bool:
	for slot: Dictionary in rig._slots:
		for player: AudioStreamPlayer3D in slot.roll:
			if player.playing:
				return true
	return false


func _state(rig: Variant) -> Array:
	var players: Array = []
	for slot: Dictionary in rig._slots:
		for player: AudioStreamPlayer3D in slot.roll + [slot.impact]:
			players.append([player.volume_db, player.pitch_scale, player.global_position, player.playing])
	var core: Array = rig._core.ground_core_state() if rig._core != null else _reference_core(rig)
	var slots: Array = core[1]
	for row: Array in slots:
		if not row[5]:
			row[6] = 0.0 # a missing roll pitch has no value to compare
	return [players, rig.touchdown_events, rig.accepted_diagnostics(), rig._was_paused, rig._scene_gain, core,
		rig.contact_slot_count]


## The reference's state in ground_core_state's layout.
func _reference_core(rig: Variant) -> Array:
	var states: Array = []
	for id: String in rig._accepted_states:
		var s: Dictionary = rig._accepted_states[id]
		states.append([id, bool(s.get("initialized", false)), bool(s.get("grounded", false)), float(s.get("airborne_s", 0.0)),
			float(s.get("previous_approach_mps", 0.0)), float(s.get("cooldown_s", 0.0))])
	var slots: Array = []
	for slot: Dictionary in rig._slots:
		var state: Dictionary = slot.get("state", {})
		var layers: Array = slot.layer_gain
		slots.append([slot.id, float(layers[0]), float(layers[1]), float(layers[2]), float(slot.get("impact_gain", 0.0)),
			state.has("roll_pitch"), float(state.get("roll_pitch", 0.0))])
	return [states, slots, rig._engine_mask, rig._last_tick]


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
