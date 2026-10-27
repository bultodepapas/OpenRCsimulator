## VQ-01c-R1: the once-per-frame presentation cadence. Helper contract, multi-tick accepted audio
## intervals, an exact touchdown cue in a real Stik drop against per-tick observation, and the wheel
## spin phase. Dummy audio; no listening, rendering or physical-validation claim.
extends SceneTree

const Cadence := preload("res://render/presentation_cadence.gd")
const Rig := preload("res://audio/flight_audio.gd")
const GroundAudio := preload("res://audio/ground_audio.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"

var checks := 0
var failed := 0


class Owner extends Node3D:
	var session: Node
	var field := {}
	var aircraft_id := "jensen-das-ugly-stik-60"
	var workshop_trial := {}
	var _field_node: Node3D
	var _airplane := {}
	var _lighting := {}
	var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)


func _run() -> void:
	_helper_contract()
	_ground_interval_contract()
	await _flight_audio_drop()
	_wheel_phase()
	Cadence.override_every_frames = -1
	print("Presentation cadence: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func _helper_contract() -> void:
	var c := Cadence.new(1, 240.0)
	check("deferral bound is 0.1 s of ticks", c.max_interval_ticks == 24)
	check("the bound stays below the touchdown cue's minimum airborne time",
		Cadence.MAX_INTERVAL_S < GroundAudio.TOUCHDOWN_MIN_AIRBORNE_S)
	check("first observation runs at once", c.on_tick(0) and c.last_tick == 0 and c.since_tick == -1)
	check("consecutive ticks wait", not c.on_tick(1) and not c.on_tick(2) and c.pending)
	check("the frame observes the waiting ticks as one continuous interval", c.take(2) and c.last_tick == 2
		and c.since_tick == 0 and not c.pending)
	check("a frame without new ticks observes nothing", not c.take(2))
	c.on_tick(3)
	check("a tick gap runs at once without continuity", c.on_tick(10) and c.since_tick == -1 and not c.pending)
	check("a reset to tick zero runs at once", c.on_tick(0) and c.last_tick == 0 and c.since_tick == -1)
	var bounded := 0
	for tick: int in range(1, 24):
		if c.on_tick(tick): bounded += 1
	check("the deferral bound forces a continuous observation", bounded == 0 and c.on_tick(24) and c.since_tick == 0)
	c.on_tick(25)
	check("a tick that moved without a stepped signal is not continuous", c.take(27) and c.since_tick == -1)
	c.on_tick(28)
	c.observe_at(28)
	check("another observation continues waiting ticks", c.last_tick == 28 and c.since_tick == 27 and not c.pending)
	c.observe_at(28)
	check("repeating an observed tick keeps its interval", c.since_tick == 27)
	c.observe_at(40)
	check("observing an unseen tick starts a new history", c.last_tick == 40 and c.since_tick == -1)
	check("the next stepped tick after it continues", not c.on_tick(41) and c.take(41) and c.since_tick == 40)
	var two := Cadence.new(2, 240.0)
	two.on_tick(0)
	two.on_tick(1)
	check("every second frame", not two.take(1) and two.take(1) and two.since_tick == 0)
	var legacy := Cadence.new(0, 240.0)
	legacy.on_tick(5)
	check("cadence 0 observes every accepted tick", legacy.on_tick(6) and legacy.since_tick == 5 and legacy.on_tick(7))
	Cadence.override_every_frames = 3
	check("the configured cadence applies to new gates", Cadence.new().every_frames == 3)
	Cadence.override_every_frames = 9
	check("the configured cadence is clamped", Cadence.configured_every_frames() == Cadence.MAX_EVERY_FRAMES)
	Cadence.override_every_frames = -1
	check("the default is once per rendered frame", Cadence.new().every_frames == Cadence.DEFAULT_EVERY_FRAMES
		or not OS.get_environment(Cadence.ENVIRONMENT_KEY).is_empty())


func _row(force: float, approach: float) -> Dictionary:
	return {id = "main_left", position = Vector3.ZERO, normal_force_n = force, reference_load_n = 20.0,
		approach_speed_mps = approach, rolling_speed_mps = 0.0, surface = "hard"}


func _ground_interval_contract() -> void:
	var g: Node = GroundAudio.new()
	root.add_child(g)
	g.set_accepted_tick_observation(true)
	g.observe_accepted({tick = 0, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 1.0)]})
	check("an unprimed or airborne wheel can cue", g.touchdown_possible())
	g.observe_accepted({tick = 4, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 1.0)], since_tick = 0})
	var state: Dictionary = g.get("_accepted_states").main_left
	check("a continuous interval ages airborne time by every tick it covers", is_equal_approx(float(state.airborne_s), 4.0 / 240.0))
	g.observe_accepted({tick = 40, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 1.2)], since_tick = 4})
	g.observe_accepted({tick = 41, tick_rate = 240.0, paused = false, contacts = [_row(20.0, 0.1)], since_tick = 40})
	var events: Array = g.get("_accepted_events")
	check("touchdown after a long enough interval cues with the last airborne approach", events.size() == 1
		and int(events[0].tick) == 41 and is_equal_approx(float(events[0].approach), 1.2), str(events))
	check("every wheel grounded: no cue is possible before the next observation", not g.touchdown_possible())
	g.observe_accepted({tick = 45, tick_rate = 240.0, paused = false, contacts = [_row(20.0, 0.0)], since_tick = 41})
	check("grounded interval keeps history", g.get("_accepted_states").main_left.grounded and g.accepted_tick() == 45
		and g.get("_accepted_events").size() == 1)
	g.observe_accepted({tick = 49, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 0.0)], since_tick = -1})
	check("a declared discontinuity seeds without history", g.get("_accepted_events").is_empty()
		and float(g.get("_accepted_states").main_left.airborne_s) == 0.0)
	g.observe_accepted({tick = 200, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 0.0)], since_tick = 49})
	check("an interval beyond 0.25 s is a discontinuity", float(g.get("_accepted_states").main_left.airborne_s) == 0.0)
	var refused: int = g.accepted_diagnostics().refused
	g.observe_accepted({tick = 201, tick_rate = 240.0, paused = false, contacts = [_row(0.0, 0.0)], since_tick = 2.5})
	check("a malformed since_tick is refused", g.accepted_diagnostics().refused == refused + 1)
	g.free()


func _drop_session() -> Node:
	var f: Node = Session.new()
	f.input_enabled = false
	f.crash_auto_restart = false
	f.setup(STIK, "jensen-das-ugly-stik-60")
	f.set_process(false)
	f.set_physics_process(false)
	f.soft_hull_contacts = true
	f.engine_running = false
	var s: PackedFloat64Array = f.sim.state.duplicate()
	for i in 3:
		s[RB.VEL + i] = 0.0
		s[RB.RATE + i] = 0.0
	s[RB.VEL] = 3.0
	s[RB.VEL + 2] = 0.2
	for i in 4: s[RB.ATT + i] = 1.0 if i == 0 else 0.0
	var compression: PackedFloat64Array = Ground.compressions(s, f.current_landing_gear())
	var maximum := -INF
	for x: float in compression: maximum = maxf(maximum, x)
	s[RB.POS + 2] += -0.4 - maximum
	f.sim.reset(s)
	return f


func _rig(owner: Owner, every_frames: int) -> Node:
	Cadence.override_every_frames = every_frames
	var audio: Node = Rig.new()
	Cadence.override_every_frames = -1
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	return audio


func _cues(audio: Node) -> Array:
	var out: Array = []
	for event: Dictionary in audio.ground_audio.get("_accepted_events"):
		out.append([event.tick, event.force, event.reference, event.approach, event.contact])
	return out


## Real 0.4 m Stik drop: a per-tick rig and a per-frame rig (frames every 4 ticks, 60 fps) on one session.
func _flight_audio_drop() -> void:
	root.audio_listener_enable_3d = true
	var session := _drop_session()
	var reference := _drop_session()
	check("drop sessions admitted identically", session.is_flyable()
		and var_to_bytes(session.checkpoint()) == var_to_bytes(reference.checkpoint()))
	var owner := Owner.new()
	owner.session = session
	owner.field = FieldLoader.load_from().field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	var per_tick := _rig(owner, 0)
	var per_frame := _rig(owner, 1)
	var observations := {per_tick = 0, per_frame = 0}
	var grounded_waits := 0
	var touchdown_tick := -1
	for i: int in 480:
		session.sim.step()
		reference.sim.step()
		if (i + 1) % 4 == 0: per_frame._observe_due_endpoints()
		if per_tick.ground_audio.accepted_tick() == session.sim.tick: observations.per_tick += 1
		if per_frame.ground_audio.accepted_tick() == session.sim.tick: observations.per_frame += 1
		elif not per_frame.ground_audio.touchdown_possible(): grounded_waits += 1
		if touchdown_tick < 0 and not _cues(per_tick).is_empty(): touchdown_tick = session.sim.tick
	check("drop reaches the ground without a fault", session.sim.fault_reason.is_empty() and touchdown_tick > 35, str(touchdown_tick))
	check("touchdown cues identical to per-tick observation", var_to_bytes(_cues(per_tick)) == var_to_bytes(_cues(per_frame))
		and not _cues(per_tick).is_empty(), "%s vs %s" % [_cues(per_tick), _cues(per_frame)])
	check("grounded wheels wait for the frame", grounded_waits > 200 and observations.per_frame < observations.per_tick - 200,
		str(observations))
	check("observed physics equals an unobserved session's, byte for byte",
		var_to_bytes(session.checkpoint()) == var_to_bytes(reference.checkpoint()))
	check("mechanical endpoints wait for the frame without discontinuities",
		per_frame.mechanical_audio.diagnostics().accepted_tick_samples < per_tick.mechanical_audio.diagnostics().accepted_tick_samples
		and per_frame.mechanical_audio.diagnostics().get("accepted_discontinuities", 0) == 0,
		str(per_frame.mechanical_audio.diagnostics()))
	# Two frames per observation: a frame in between presents the last accepted contacts, never none.
	var held := _rig(owner, 2)
	for i: int in 4:
		session.sim.step()
		reference.sim.step()
	held._process(1.0 / 60.0)
	var ground: Node = held.ground_audio
	check("a frame between observations presents the held accepted contacts", ground.accepted_tick() < session.sim.tick
		and int(ground.get("_last_tick")) == ground.accepted_tick() and not (ground.get("_accepted_contacts") as Array).is_empty(),
		"%d %d %d" % [ground.accepted_tick(), session.sim.tick, int(ground.get("_last_tick"))])
	check("the primed rig continues history into its first interval",
		held.mechanical_audio.diagnostics().accepted_discontinuities == 0)
	for audio: Node in [per_tick, per_frame, held]:
		audio.free()
	owner.free()
	session.free()
	reference.free()
	await process_frame


## Wheel spin phase in a real Stik drop and roll-out: per frame (every 4 ticks) against per tick.
func _wheel_phase() -> void:
	var session := _drop_session()
	root.add_child(session)
	var observers: Array = []
	for every_frames: int in [0, 1]:
		var model := Node3D.new()
		root.add_child(model)
		var gear := {}
		for key: String in ["left", "right", "nose"]:
			var wheel := Node3D.new()
			model.add_child(wheel)
			gear[key] = wheel
		Cadence.override_every_frames = every_frames
		var observer: Node = GroundGear.attach({root = model, gear = gear}, session)
		Cadence.override_every_frames = -1
		observer.set_process(false)
		observers.append(observer)
	var largest := 0.0
	var moved := 0.0
	for i: int in 480:
		session.sim.step()
		if (i + 1) % 4 == 0:
			observers[1]._process(1.0 / 60.0)
			for key: String in ["left", "right", "nose"]:
				var a: float = float(observers[0].get("_angles")[key])
				var b: float = float(observers[1].get("_angles")[key])
				largest = maxf(largest, absf(angle_difference(a, b)))
				moved = maxf(moved, absf(a))
	check("the per-frame wheel phase follows the per-tick phase within 1 mrad", moved > 0.5 and largest < 0.001,
		"moved %.4f rad, largest difference %.6f rad" % [moved, largest])
	session.free()
