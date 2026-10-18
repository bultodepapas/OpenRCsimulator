## AUD-06: deterministic audio bench. Flies the real flight scene under Godot Movie Maker
## (--write-movie, --fixed-fps 60), so frame i maps exactly to mixer samples [i·rate/60, (i+1)·rate/60).
## Writes <out>.json with per-frame telemetry; Movie Maker writes the Master mix beside the frames.
## Usage: see tools/audio/bench.sh. Read-only: it drives inputs like a player and never edits the simulation.
extends SceneTree

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const FPS: int = 60
var args: Dictionary = {}
var scene: Node3D
var adapter: Node
var frame: int = 0
var stage: String = ""
var rows: Array = []
var events: Array[Dictionary] = []
var focus_resumes: int = 0

# Scenario timelines: [start_s, stage]. Throttle stages are keyboard-rate commands (+1 up, -1 down, 0 hold).
const SCENARIOS: Dictionary = {
	sweep = [[0.0, "trim"], [3.0, "up"], [6.0, "full"], [11.0, "down"], [14.0, "idle"], [19.0, "end"]],
	runway = [[0.0, "idle"], [2.0, "inspect_on"], [2.5, "idle"], [3.0, "inspect_off"], [3.5, "idle"],
		[4.0, "inspect_on"], [4.5, "idle"], [5.0, "inspect_off"], [5.5, "up"], [8.5, "full"], [14.0, "end"]],
	# The pilot station moves 250 m ahead of the start, 30 m to the right: approach, pass, recede.
	flyby = [[0.0, "up"], [2.0, "approach"], [4.0, "passing"], [7.0, "recede"], [11.0, "end"]],
	# AUD-12: full-power dive into the ground; the crash hold keeps rendering, so impact and aftermath sound mix.
	crash = [[0.0, "up"], [1.5, "dive"], [10.0, "end"]],
}
const THROTTLE: Dictionary = {up = 1.0, down = -1.0, approach = 1.0, passing = 1.0, recede = 1.0, dive = 1.0}
const PITCH: Dictionary = {dive = -1.0}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	_run.call_deferred()


func _run() -> void:
	var scenario: String = str(args.get("scenario", "sweep"))
	if not args.has("out") or not SCENARIOS.has(scenario):
		printerr("--out=<absolute prefix> and --scenario=", "|".join(SCENARIOS.keys()), " are required")
		quit(1)
		return
	scene = load("res://main.tscn").instantiate()
	if scenario == "runway":
		scene.start_choice = "runway"
	root.add_child(scene)
	adapter = scene.get("_soundscape_audio")
	if adapter == null:
		printerr("bench requires soundscape=on and a physics flight")
		quit(1)
		return
	scene.session.read_raw = _controls
	if scenario == "flyby":
		_place_station_ahead(250.0, 30.0)
	if args.has("engine-only"):
		# Calibration aid: silence the environment bus (wind, foliage, wildlife) so levels are the aircraft alone.
		AudioServer.set_bus_mute(AudioServer.get_bus_index(adapter.soundscape._bus_names[2]), true)
	var timeline: Array = SCENARIOS[scenario]
	var end_frame: int = roundi(float(timeline[-1][0]) * FPS)
	while frame < end_frame:
		var t: float = float(frame) / FPS
		var next: String = _stage_at(timeline, t)
		if next != stage:
			stage = next
			if stage.begins_with("inspect"):
				var key: InputEventKey = InputEventKey.new()
				key.keycode = KEY_C
				key.physical_keycode = KEY_C
				key.pressed = true
				scene._unhandled_input(key)
			events.append({frame = frame, t = t, stage = stage})
		await process_frame
		# Headless windows can lose focus; resume only a plain focus pause, never a fault, crash or hold.
		var session: Node = scene.session
		if session.sim.paused and session.holds.is_empty() and session.crash.is_empty() \
				and session.pause_reason.is_empty() and session.sim.fault_reason.is_empty():
			session.resume()
			focus_resumes += 1
		_record(t)
		frame += 1
	var report: Dictionary = {
		format = "openrc-audio-bench-v1", godot = Engine.get_version_info().string, scenario = scenario,
		arguments = args, aircraft = scene.aircraft_id, fps = FPS, mix_rate = AudioServer.get_mix_rate(),
		driver = AudioServer.get_driver_name(), frames = frame, events = events, focus_resumes = focus_resumes,
		columns = ["t", "rpm", "throttle", "distance_m", "doppler", "motor_gain", "motor_pitch", "prop_gain", "prop_pitch",
			"motor_volume_db", "motor_pitch_scale", "listener_x", "listener_y", "listener_z", "paused", "crash", "exhaust_angle_deg",
			"delay_s", "absorption_hz"],
		rows = rows,
		audio_sources_sha256 = {
			adapter = FileAccess.get_sha256("res://audio/flight_audio.gd"),
			mixer = FileAccess.get_sha256("res://audio/soundscape.gd"),
			model = FileAccess.get_sha256("res://audio/soundscape_model.gd"),
		},
		note = "Movie Maker mixer capture of the real flight. Not speaker listening or acoustic validation.",
	}
	var file: FileAccess = FileAccess.open(str(args.out) + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	root.remove_child(scene)
	scene.free()
	await process_frame
	quit(0)


## Presentation only: relocates the pilot camera's station along the accepted start velocity (NED).
func _place_station_ahead(ahead_m: float, right_m: float) -> void:
	var state: PackedFloat64Array = scene.session.sim.state
	var attitude: PackedFloat64Array = M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var velocity: PackedFloat64Array = M.q_rotate(attitude, M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))
	var heading := Vector2(velocity[0], velocity[1]).normalized()
	var right := Vector2(-heading.y, heading.x)
	var station: Array = scene._camera.get_meta("pilot_station", [0.0, 0.0, 0.0])
	var target := Vector2(state[RB.POS], state[RB.POS + 1]) + heading * ahead_m + right * right_m
	scene._camera.set_meta("pilot_station", [target.x, target.y, float(station[2])])
	events.append({frame = 0, t = 0.0, stage = "station", north = target.x, east = target.y})


func _record(t: float) -> void:
	var session: Node = scene.session
	var mix: Node = adapter.soundscape
	var targets: Dictionary = mix.last_targets
	var listener: Vector3 = scene._camera.global_position
	rows.append([t, session.sim.aux[0], session.sim.inputs[3],
		scene._airplane.root.global_position.distance_to(listener), mix.last_doppler,
		float(targets.get("motor_gain", 0.0)), float(targets.get("motor_pitch", 0.0)),
		float(targets.get("prop_gain", 0.0)), float(targets.get("prop_pitch", 0.0)),
		mix.voices[0].volume_db, mix.voices[0].pitch_scale, listener.x, listener.y, listener.z,
		session.sim.paused, not session.crash.is_empty(), float(targets.get("exhaust_angle_deg", -1.0)),
		float(mix.last_delay_s), float(mix.last_absorption_cutoff_hz)])


func _stage_at(timeline: Array, t: float) -> String:
	var current: String = str(timeline[0][1])
	for entry: Array in timeline:
		if t >= float(entry[0]):
			current = str(entry[1])
	return current


func _controls() -> Dictionary:
	return {roll = 0.0, pitch = float(PITCH.get(stage, 0.0)), yaw = 0.0, throttle = float(THROTTLE.get(stage, 0.0))}
