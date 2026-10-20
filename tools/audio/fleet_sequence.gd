## AUD-15: deterministic lifecycle capture through the production audio adapter.
## Fixed-wing portions use the real FlightSession runway route through takeoff/flight. At
## `landing_fixture`, the session is explicitly reset to a trimmed, descending approach;
## landing and wheel contacts then come from the real FlightSession integration. It is not
## one uninterrupted flight. Non-glow engine start/stop are labeled bench latch stimuli.
extends SceneTree

const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Math3D = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Trim = preload("res://physics/trim.gd")

var capture_fps := 60
const FIXED_TIMELINE: Array = [
	[0.0, "off"], [2.0, "start"], [4.0, "idle"], [7.0, "taxi"],
	[10.0, "takeoff"], [22.0, "flight"], [27.0, "landing"],
	[35.0, "rollout"], [39.0, "shutdown"], [42.0, "done"],
]
const ROTOR_TIMELINE: Array = [
	[0.0, "off"], [2.0, "start"], [5.0, "ground_idle"], [8.0, "spinup"],
	[12.0, "takeoff"], [18.0, "flight"], [25.0, "landing"],
	[31.0, "settle"], [34.0, "shutdown"], [37.0, "done"],
]

var args: Dictionary = {}
var frame := 0
var stage := ""
var aircraft_id := ""
var rotorcraft := false
var scene: Node3D
var adapter: Node
var premaster_capture: AudioEffectCapture
var master_capture: AudioEffectCapture
var master_samples := PackedVector2Array()
var premaster_frames := 0
var premaster_peak := 0.0
var premaster_over_unity := 0
var premaster_max_step := 0.0
var premaster_steps_over_08 := 0
var _premaster_previous := Vector2.ZERO
var _premaster_has_previous := false
var master_peak := 0.0
var master_over_unity := 0
var master_max_step := 0.0
var master_steps_over_08 := 0
var master_invalid_sample := false
var _master_previous := Vector2.ZERO
var _master_has_previous := false
var master_discarded_frames := 0
var events: Array[Dictionary] = []
var rows: Array[Dictionary] = []
var bench_rows: Array[Array] = []
var notes: PackedStringArray = []
var takeoff_seen := false
var touchdown_seen := false
var rollout_contact_seen := false
var landing_fixture_ok := false
var landing_fixture_message := "not entered"
var focus_resumes := 0
var previous_grounded := 0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	if args.has("list"):
		var ids := Catalog.airplane_flyable_ids()
		for id: String in ids:
			print("FLEET_AIRCRAFT_ID=", id)
		if Catalog.can_fly("xcell-60-research"):
			print("FLEET_AIRCRAFT_ID=xcell-60-research")
		quit(0)
		return
	if not args.has("out") or not args.has("aircraft"):
		printerr("--out=<absolute prefix> and --aircraft=<catalog ID> are required; --list prints the current fleet")
		quit(1)
		return
	var output_directory := str(args.out).get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(output_directory)
		if mkdir_error != OK:
			printerr("cannot create capture directory: ", output_directory, " error=", mkdir_error)
			quit(1)
			return
	aircraft_id = str(args.aircraft)
	capture_fps = clampi(int(args.get("fps", 60)), 1, 60)
	if args.has("size"):
		var dimensions := str(args.size).split("x")
		if dimensions.size() == 2:
			get_root().size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	if not Catalog.can_fly(aircraft_id):
		printerr("fleet sequence refuses unknown or non-flyable aircraft: ", aircraft_id)
		quit(1)
		return
	rotorcraft = Catalog.is_rotorcraft(aircraft_id)
	if rotorcraft and aircraft_id != "xcell-60-research":
		printerr("fleet sequence has no rotorcraft route for: ", aircraft_id)
		quit(1)
		return
	if rotorcraft:
		scene = load("res://helicopter_main.tscn").instantiate() as Node3D
		scene.aircraft_id = aircraft_id
		scene.start_choice = "ground"
	else:
		scene = load("res://main.tscn").instantiate() as Node3D
		scene.aircraft_id = aircraft_id
		scene.start_choice = "runway"
	root.add_child(scene)
	if not str(scene.get("startup_error")).is_empty():
		printerr("fleet sequence startup refused: ", scene.get("startup_error"))
		quit(1)
		return
	adapter = scene.get("_soundscape_audio") as Node
	if adapter == null:
		printerr("fleet sequence requires the production flight audio adapter")
		quit(1)
		return
	var session: Node = scene.session
	session.read_raw = _controls
	_install_audio_probe()
	if rotorcraft:
		_enter_rotor_off()
	else:
		_enter_engine_off()
		if not _has_runway():
			notes.append("runway launch unavailable; takeoff segment remains a live aircraft-input attempt")
	var timeline: Array = ROTOR_TIMELINE if rotorcraft else FIXED_TIMELINE
	var end_frame := roundi(float(timeline[-1][0]) * capture_fps)
	stage = str(timeline[0][1])
	events.append(_event(stage, "initial production adapter state"))
	while frame < end_frame:
		var t := float(frame) / capture_fps
		var next := _stage_at(timeline, t)
		if next != stage:
			stage = next
			_enter_stage(stage)
		await process_frame
		_drain_audio_probe()
		_resume_focus_pause(session)
		_record_frame(t)
		frame += 1
	_drain_audio_probe()
	var wav_path := str(args.out) + ".wav"
	var wav_error := _save_wav(wav_path)
	if wav_error != OK:
		printerr("could not save master PCM WAV: ", wav_path, " error=", wav_error)
		quit(1)
		return
	var report := _report(timeline)
	var output := FileAccess.open(str(args.out) + ".json", FileAccess.WRITE)
	if output == null:
		printerr("cannot write sequence report: ", args.out)
		quit(1)
		return
	output.store_string(JSON.stringify(report))
	output.close()
	root.remove_child(scene)
	scene.free()
	await process_frame
	quit(0)


func _has_runway() -> bool:
	var field: Dictionary = scene.get("field")
	if field.is_empty():
		return false
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			return true
	return false


func _enter_engine_off() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		if session.engine_running:
			session.glow_cut()
	else:
		var kind := str(prop.get("kind", "glow_prop"))
		if kind != "electric_prop":
			session.engine_running = false
			notes.append("combustion/turbine start and stop use the harness engine_running latch; no installed starter event exists")


func _start_airplane_engine() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		landing_fixture_message = "glow starter accepted" if session.glow_start() else "glow starter refused"
		if landing_fixture_message == "glow starter refused":
			notes.append("physical glow_start() did not accept this start; its engine-running state is reported from session data")
	elif str(prop.get("kind", "glow_prop")) != "electric_prop":
		session.engine_running = true
	else:
		notes.append("electric motor start is represented by its accepted low-power throttle/RPM rise")


func _stop_airplane_engine() -> void:
	var session: Node = scene.session
	var prop: Dictionary = session.aircraft.model.propulsion
	if session.has_method("glow_is_active") and session.glow_is_active():
		if session.engine_running:
			session.glow_cut()
	elif str(prop.get("kind", "glow_prop")) != "electric_prop":
		session.engine_running = false


func _enter_rotor_off() -> void:
	var session: Node = scene.session
	session.set_drive_hold(true)
	if session.power.armed:
		session.toggle_motor_arm()


func _start_rotor() -> void:
	var session: Node = scene.session
	session.commands.throttle = 0.5 # centered collective before the accepted arm transition
	session.set_drive_hold(true)
	if not session.power.armed and not session.toggle_motor_arm():
		notes.append("helicopter motor arm request was refused")
	if session.power.armed and not session.set_drive_hold(false):
		notes.append("helicopter drive-hold release was refused")


func _stop_rotor() -> void:
	var session: Node = scene.session
	session.set_drive_hold(true)
	if session.power.armed:
		session.toggle_motor_arm()


func _enter_stage(next: String) -> void:
	var action := ""
	if rotorcraft:
		match next:
			"start":
				_start_rotor()
				action = "accepted motor arm and drive-hold release requested"
			"landing":
				action = "collective reduced for pad descent; no wheeled rollout"
			"shutdown":
				_stop_rotor()
				action = "drive held and motor disarmed"
			"takeoff": action = "pad lift command; actual liftoff checked from contacts"
			"settle": action = "skid/pad settle; rollout is not applicable"
			_: pass
	else:
		match next:
			"start":
				_start_airplane_engine()
				action = landing_fixture_message
			"landing":
				_stage_landing_fixture()
				action = landing_fixture_message
			"shutdown":
				_stop_airplane_engine()
				action = "engine cut requested; RPM remains session-owned"
			"takeoff": action = "runway throttle/pitch input; accepted liftoff checked from contact state"
			"taxi": action = "low-power runway input; wheel motion/contact are measured, not assumed"
			"rollout": action = "idle input after staged approach; wheel contact is measured"
			_: pass
	events.append(_event(next, action))


func _stage_landing_fixture() -> void:
	var session: Node = scene.session
	var field: Dictionary = scene.field
	var runway: Dictionary = {}
	for surface: Dictionary in field.get("surfaces", []):
		if str(surface.get("id", "")) == str(field.get("runway", "")):
			runway = surface
	if runway.is_empty():
		landing_fixture_message = "staged landing skipped: field runway unavailable"
		notes.append(landing_fixture_message)
		return
	var speed := float(session.start.get("V", 0.0))
	if not is_finite(speed) or speed <= 0.0:
		speed = 20.0
	var trim: Dictionary = session.trim_at(speed)
	if not trim.get("ok", false):
		landing_fixture_message = "staged landing skipped: trim failed at %.2f m/s" % speed
		notes.append(landing_fixture_message)
		return
	var eastbound := true
	var direction := 1.0 if eastbound else -1.0
	var half_length := float(runway.get("length_east_west", 240.0)) * 0.5
	var start_state: PackedFloat64Array = Trim.state_for(speed, float(trim.alpha), 0.0,
		direction * PI * 0.5, Math3D.v3(float(runway.get("center_north", 0.0)),
		float(runway.get("center_east", 0.0)) - direction * (half_length + 76.0), -8.0), float(trim.get("beta", 0.0)))
	var attitude := Math3D.q_from_euler(direction * PI * 0.5, float(trim.alpha), 0.0)
	for index: int in 4:
		start_state[RB.ATT + index] = attitude[index]
	start_state[RB.VEL + 2] += 0.7 # explicit descending approach fixture, then FlightSession owns every tick/contact
	session.start.state = start_state
	session.start_choice = "airborne"
	session.set_start_altitude(8.0)
	session.reset()
	landing_fixture_ok = session.is_flyable()
	landing_fixture_message = "staged descending approach reset; landing physics/contact remain live" if landing_fixture_ok else "staged approach reset refused: " + str(session.pause_reason)
	if not landing_fixture_ok:
		notes.append(landing_fixture_message)


func _controls() -> Dictionary:
	if rotorcraft:
		var collective := 0.5
		match stage:
			"takeoff": collective = 0.68
			"flight": collective = 0.60
			"landing": collective = 0.49
			"settle", "shutdown", "off": collective = 0.5
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = collective}
	var throttle := 0.0
	var pitch := 0.0
	match stage:
		"start", "idle", "landing": throttle = 0.12
		"taxi": throttle = 0.2
		"takeoff":
			throttle = 1.0
			pitch = 0.12
		"flight": throttle = 0.55
		"rollout", "shutdown", "off": throttle = 0.0
	return {roll = 0.0, pitch = pitch, yaw = 0.0, throttle = throttle}


func _event(name: String, action: String) -> Dictionary:
	var session: Node = scene.session
	return {frame = frame, time_s = float(frame) / capture_fps, stage = name, action = action,
		tick = int(session.sim.tick), aircraft = aircraft_id}


func _stage_at(timeline: Array, t: float) -> String:
	var current := str(timeline[0][1])
	for entry: Array in timeline:
		if t >= float(entry[0]):
			current = str(entry[1])
	return current


func _resume_focus_pause(session: Node) -> void:
	if session.sim.paused and session.holds.is_empty() and session.crash.is_empty() \
			and session.pause_reason.is_empty() and session.sim.fault_reason.is_empty():
		session.resume()
		focus_resumes += 1


func _ground_snapshot() -> Dictionary:
	for property: Dictionary in adapter.get_property_list():
		if str(property.get("name", "")) == "ground_snapshot":
			var value: Variant = adapter.get("ground_snapshot")
			return value if value is Dictionary else {}
	if adapter.has_method("ground_snapshot"):
		var value: Variant = adapter.call("ground_snapshot")
		return value if value is Dictionary else {}
	if adapter.has_method("contact_snapshot"):
		var value: Variant = adapter.call("contact_snapshot")
		if value is Dictionary:
			return value
		if value is Array:
			return {contacts = value, tick = int(scene.session.sim.tick)}
	return {}


func _install_audio_probe() -> void:
	var soundscape: Node = adapter.get("soundscape") as Node
	if soundscape == null or not soundscape.has_method("output_bus"):
		notes.append("pre-master probe unavailable: soundscape output bus is not exposed")
		return
	var output_bus := AudioServer.get_bus_index(StringName(soundscape.call("output_bus")))
	if output_bus < 0:
		notes.append("pre-master probe unavailable: soundscape output bus is missing")
		return
	if args.has("engine-only") and soundscape.has_method("environment_bus"):
		var environment_bus := AudioServer.get_bus_index(StringName(soundscape.call("environment_bus")))
		if environment_bus >= 0:
			AudioServer.set_bus_mute(environment_bus, true)
	premaster_capture = AudioEffectCapture.new()
	premaster_capture.buffer_length = maxf(0.5, 2.0 / float(capture_fps))
	AudioServer.add_bus_effect(output_bus, premaster_capture)
	var master_index := AudioServer.get_bus_index(&"Master")
	if master_index < 0:
		notes.append("post-master probe unavailable: Master bus is missing")
		return
	master_capture = AudioEffectCapture.new()
	master_capture.buffer_length = maxf(0.5, 2.0 / float(capture_fps))
	# Appending after the configured Master effects captures the delivered software mix.
	AudioServer.add_bus_effect(master_index, master_capture)


func _drain_audio_probe() -> void:
	if premaster_capture != null:
		var available := premaster_capture.get_frames_available()
		if available > 0:
			var buffer: PackedVector2Array = premaster_capture.get_buffer(available)
			for sample: Vector2 in buffer:
				premaster_frames += 1
				premaster_peak = maxf(premaster_peak, maxf(absf(sample.x), absf(sample.y)))
				if maxf(absf(sample.x), absf(sample.y)) >= 1.0:
					premaster_over_unity += 1
				if _premaster_has_previous:
					var step := maxf(absf(sample.x - _premaster_previous.x), absf(sample.y - _premaster_previous.y))
					premaster_max_step = maxf(premaster_max_step, step)
					if step >= 0.8:
						premaster_steps_over_08 += 1
				_premaster_previous = sample
				_premaster_has_previous = true
	if master_capture != null:
		var master_available := master_capture.get_frames_available()
		if master_available > 0:
			var master_buffer: PackedVector2Array = master_capture.get_buffer(master_available)
			for sample: Vector2 in master_buffer:
				var finite_sample := sample
				if not is_finite(sample.x) or not is_finite(sample.y):
					master_invalid_sample = true
					finite_sample = Vector2.ZERO
				master_samples.append(finite_sample)
				var peak := maxf(absf(finite_sample.x), absf(finite_sample.y))
				master_peak = maxf(master_peak, peak)
				if peak >= 1.0:
					master_over_unity += 1
				if _master_has_previous:
					var step := maxf(absf(finite_sample.x - _master_previous.x), absf(finite_sample.y - _master_previous.y))
					master_max_step = maxf(master_max_step, step)
					if step >= 0.8:
						master_steps_over_08 += 1
				_master_previous = finite_sample
				_master_has_previous = true
			master_discarded_frames = master_capture.get_discarded_frames()


func _save_wav(path: String) -> Error:
	var wav := AudioStreamWAV.new()
	wav.mix_rate = AudioServer.get_mix_rate()
	wav.stereo = true
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var data := PackedByteArray()
	data.resize(master_samples.size() * 4)
	for index: int in master_samples.size():
		data.encode_s16(index * 4, clampi(roundi(master_samples[index].x * 32767.0), -32768, 32767))
		data.encode_s16(index * 4 + 2, clampi(roundi(master_samples[index].y * 32767.0), -32768, 32767))
	wav.data = data
	return wav.save_to_wav(path)


func _contact_summary() -> Dictionary:
	var ground := _ground_snapshot()
	var contacts: Array = ground.get("contacts", [])
	var grounded := 0
	var rolling := 0
	var peak_speed := 0.0
	var peak_normal_force := 0.0
	for contact: Dictionary in contacts:
		if bool(contact.get("grounded", contact.get("touching", false))):
			grounded += 1
		if bool(contact.get("roll_enabled", false)):
			rolling += 1
		var velocity: Variant = contact.get("velocity_mps", Vector3.ZERO)
		if velocity is Vector3:
			peak_speed = maxf(peak_speed, velocity.length())
		peak_normal_force = maxf(peak_normal_force, float(contact.get("normal_force_n", contact.get("normal_load_n", 0.0))))
	if contacts.is_empty() and not rotorcraft:
		var session: Node = scene.session
		var compressions: PackedFloat64Array = session.gear_compressions(session.sim.state)
		for compression: float in compressions:
			if compression > 0.0:
				grounded += 1
	return {count = contacts.size(), grounded = grounded, rolling = rolling,
		peak_contact_speed_mps = peak_speed, peak_normal_force_n = peak_normal_force,
		tick = int(ground.get("tick", -1))}


func _record_frame(t: float) -> void:
	var session: Node = scene.session
	var snapshot: Dictionary = adapter.call("snapshot") if adapter.has_method("snapshot") else {}
	var contacts := _contact_summary()
	var grounded := int(contacts.grounded)
	if not rotorcraft and stage in ["takeoff", "flight"] and grounded == 0 and _height_m() > 1.0:
		takeoff_seen = true
	if stage in ["landing", "rollout", "settle"]:
		if grounded > 0:
			touchdown_seen = true
			if stage in ["rollout", "settle"]:
				rollout_contact_seen = true
	var soundscape: Node = adapter.get("soundscape") as Node
	var source: Vector3 = snapshot.get("source", Vector3.ZERO)
	var listener: Vector3 = snapshot.get("listener", Vector3.ZERO)
	var pitch_scale := 1.0
	var volume_db := -120.0
	if soundscape != null:
		var powertrain: Node = soundscape.get("powertrain") as Node
		if powertrain != null and not powertrain.get("players").is_empty():
			var bank_player: AudioStreamPlayer3D = powertrain.get("players")[0]
			pitch_scale = bank_player.pitch_scale
			volume_db = bank_player.volume_db
		else:
			var glow: AudioStreamPlayer3D = soundscape.get("glow_player") as AudioStreamPlayer3D
			if glow != null:
				pitch_scale = glow.pitch_scale
				volume_db = glow.volume_db
			elif soundscape.get("voices").size() > 0:
				var legacy: AudioStreamPlayer3D = soundscape.get("voices")[0]
				pitch_scale = legacy.pitch_scale
				volume_db = legacy.volume_db
	bench_rows.append([t, float(snapshot.get("rpm", 0.0)), source.distance_to(listener),
		pitch_scale, volume_db, float(soundscape.get("last_doppler")) if soundscape != null else 1.0])
	var telemetry_stride := maxi(1, roundi(float(capture_fps) / 10.0))
	if frame % telemetry_stride != 0:
		return
	var targets: Dictionary = {}
	var powertrain: Node = null
	if soundscape != null:
		powertrain = soundscape.get("powertrain") as Node
		if powertrain != null:
			var value: Variant = powertrain.get("last_targets")
			if value is Dictionary:
				targets = value
	rows.append({frame = frame, t = t, stage = stage, tick = int(session.sim.tick),
		rpm = float(snapshot.get("rpm", 0.0)), running = bool(snapshot.get("running", false)),
		throttle = float(snapshot.get("throttle", 0.0)), speed_mps = _speed_mps(),
		height_m = _height_m(), paused = bool(session.sim.paused),
		fault = str(session.sim.fault_reason), crash = not session.crash.is_empty(),
		contacts = contacts, powertrain = targets, audio_mix = _audio_mix_summary(soundscape)})


func _audio_mix_summary(soundscape: Node) -> Dictionary:
	var engine_level := 0.0
	var mix_engine_level := -100.0
	if soundscape != null:
		var powertrain: Node = soundscape.get("powertrain") as Node
		if powertrain != null:
			var targets: Variant = powertrain.get("last_targets")
			if targets is Dictionary:
				engine_level = float(targets.get("level", 0.0))
			if not powertrain.get("players").is_empty():
				mix_engine_level = (powertrain.get("players")[0] as AudioStreamPlayer3D).volume_db
	var ground_slots := 0
	var ground_roll_gain := 0.0
	var active_impact_count := 0
	var ground_audio: Node = adapter.get("ground_audio") as Node if adapter != null else null
	if ground_audio != null:
		for slot: Dictionary in ground_audio.get("_slots"):
			ground_slots += 1
			for layer_gain: float in slot.get("layer_gain", []):
				ground_roll_gain += layer_gain
			var impact: AudioStreamPlayer3D = slot.get("impact") as AudioStreamPlayer3D
			if impact != null and impact.playing:
				active_impact_count += 1
	return {engine_gain_model: engine_level, engine_player_db: mix_engine_level,
		gear_roll_gain_model_sum: ground_roll_gain, gear_touchdown_players: active_impact_count,
		gear_contact_slots: ground_slots}
	previous_grounded = grounded


func _height_m() -> float:
	var session: Node = scene.session
	var state: PackedFloat64Array = session.sim.state
	if state.size() <= RB.POS + 2:
		return 0.0
	var altitude := -state[RB.POS + 2]
	if not rotorcraft and session.get("environment") != null:
		altitude -= float(session.environment.terrain(state[RB.POS], state[RB.POS + 1])[0])
	return altitude


func _speed_mps() -> float:
	var session: Node = scene.session
	var state: PackedFloat64Array = session.sim.state
	if state.size() < RB.VEL + 3:
		return 0.0
	return Math3D.norm(Math3D.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))


func _audio_source_info() -> Dictionary:
	var soundscape: Node = adapter.get("soundscape") as Node
	if soundscape == null:
		return {source = "none", recorded_layers = 0, fallback = false}
	var powertrain: Node = soundscape.get("powertrain") as Node
	var layer_count := 0
	var bank_family := ""
	if powertrain != null:
		var layers: Variant = powertrain.get("layers")
		if layers is Array:
			layer_count = layers.size()
		var profile: Variant = powertrain.get("profile")
		if profile is Dictionary:
			bank_family = str(profile.get("family", ""))
	var glow_player: Variant = soundscape.get("glow_player")
	var source := "recorded-bank" if layer_count > 0 else ("glow-fallback" if glow_player != null else "procedural-or-legacy")
	return {source = source, recorded_layers = layer_count, bank_family = bank_family,
		fallback = layer_count == 0 and glow_player != null}


func _report(timeline: Array) -> Dictionary:
	var session: Node = scene.session
	var route := "helicopter-ground-lifecycle" if rotorcraft else "runway-plus-staged-approach"
	var source_info := _audio_source_info()
	var source_path := "res://audio/helicopter_audio.gd" if rotorcraft else "res://audio/flight_audio.gd"
	return {
		format = "openrc-audio-fleet-sequence-v1", aircraft = aircraft_id, vehicle = "rotorcraft" if rotorcraft else "fixed-wing",
		godot = Engine.get_version_info().string, fps = capture_fps, mix_rate = AudioServer.get_mix_rate(),
		driver = AudioServer.get_driver_name(), frames = frame, duration_s = float(frame) / capture_fps,
		pcm_wav = {path = str(args.out) + ".wav", sample_format = "signed PCM16 stereo",
			frames = master_samples.size(), seconds = float(master_samples.size()) / float(AudioServer.get_mix_rate()),
			discarded_frames = master_discarded_frames, peak_linear = master_peak,
			peak_dbfs = linear_to_db(maxf(master_peak, 0.0000001)), over_unity_samples = master_over_unity,
			max_sample_step = master_max_step, sample_steps_over_0_8 = master_steps_over_08,
			invalid_sample_seen = master_invalid_sample,
			meaning = "AudioEffectCapture appended after configured Master bus effects; PCM is software output, not acoustic calibration."},
		route = route, staged_landing_fixture = landing_fixture_ok,
		landing_fixture_message = landing_fixture_message, actual_runway_takeoff_observed = takeoff_seen,
		actual_contact_after_landing_stage = touchdown_seen, rollout_or_settle_contact_observed = rollout_contact_seen,
		landing_rollout_not_applicable = rotorcraft, start_state = "accepted session snapshot; non-glow combustion start/stop are bench engine_running latch stimuli",
		start_choice = "ground" if rotorcraft else "runway", initial_stage_schedule = timeline,
		audio_source = source_info, contacts = _contact_summary(), events = events, samples = rows,
		telemetry_rate_hz = float(capture_fps) / float(maxi(1, roundi(float(capture_fps) / 10.0))),
		columns = ["t", "rpm", "distance_m", "motor_pitch_scale", "motor_volume_db", "doppler"],
		rows = bench_rows,
		premaster = {frames = premaster_frames, peak_linear = premaster_peak,
			peak_dbfs = linear_to_db(maxf(premaster_peak, 0.0000001)), over_unity_samples = premaster_over_unity,
			max_sample_step = premaster_max_step, sample_steps_over_0_8 = premaster_steps_over_08,
			meaning = "AudioEffectCapture on the soundscape sum before the Master limiter; sample-step threshold is a screening statistic, not a perceptual click verdict."},
		fault = str(session.sim.fault_reason), crash = not session.crash.is_empty(), focus_resumes = focus_resumes,
		notes = notes, audio_adapter_sha256 = FileAccess.get_sha256(source_path),
		note = "Native WASAPI AudioEffectCapture PCM from the production adapter, with no Movie Maker render. Fixed-wing takeoff/flight is live from runway; the later descending approach is staged by resetting FlightSession, then contacts/rollout use the live physics session. Helicopter lifecycle uses its ground route; no wheel taxi or rollout is claimed. Engine gain and gear roll rows are normalized runtime diagnostics; gear shares the aircraft bus, so no separate gear PCM is claimed. Audio captures are software evidence, not speaker or acoustic validation.",
	}
