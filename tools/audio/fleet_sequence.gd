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

const FPS := 60
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
var events: Array[Dictionary] = []
var rows: Array[Dictionary] = []
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
	aircraft_id = str(args.aircraft)
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
	if rotorcraft:
		_enter_rotor_off()
	else:
		_enter_engine_off()
		if not _has_runway():
			notes.append("runway launch unavailable; takeoff segment remains a live aircraft-input attempt")
	var timeline: Array = ROTOR_TIMELINE if rotorcraft else FIXED_TIMELINE
	var end_frame := roundi(float(timeline[-1][0]) * FPS)
	stage = str(timeline[0][1])
	events.append(_event("sequence_start", "production adapter attached"))
	while frame < end_frame:
		var t := float(frame) / FPS
		var next := _stage_at(timeline, t)
		if next != stage:
			stage = next
			_enter_stage(stage)
		await process_frame
		_resume_focus_pause(session)
		_record_frame(t)
		frame += 1
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
	return {frame = frame, time_s = float(frame) / FPS, stage = name, action = action,
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
	return {}


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
	if frame % 6 != 0:
		return
	var targets: Dictionary = {}
	var powertrain: Node = null
	var soundscape: Node = adapter.get("soundscape") as Node
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
		contacts = contacts, powertrain = targets})
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
		godot = Engine.get_version_info().string, fps = FPS, mix_rate = AudioServer.get_mix_rate(),
		driver = AudioServer.get_driver_name(), frames = frame, duration_s = float(frame) / FPS,
		route = route, staged_landing_fixture = landing_fixture_ok,
		landing_fixture_message = landing_fixture_message, actual_runway_takeoff_observed = takeoff_seen,
		actual_contact_after_landing_stage = touchdown_seen, rollout_or_settle_contact_observed = rollout_contact_seen,
		landing_rollout_not_applicable = rotorcraft, start_state = "accepted session snapshot; non-glow combustion start/stop are bench engine_running latch stimuli",
		start_choice = "ground" if rotorcraft else "runway", initial_stage_schedule = timeline,
		audio_source = source_info, contacts = _contact_summary(), events = events, samples_10_hz = rows,
		fault = str(session.sim.fault_reason), crash = not session.crash.is_empty(), focus_resumes = focus_resumes,
		notes = notes, audio_adapter_sha256 = FileAccess.get_sha256(source_path),
		note = "Movie Maker PCM from the production adapter. Fixed-wing takeoff/flight is live from runway; the later descending approach is staged by resetting FlightSession, then contacts/rollout use the live physics session. Helicopter lifecycle uses its ground route; no wheel taxi or rollout is claimed. Audio captures are software evidence, not speaker or acoustic validation.",
	}
