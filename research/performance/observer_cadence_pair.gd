## VQ-01c-R1: accepted-audio fidelity of the presentation cadence. Real Stik descents (GP-19f cases plus a
## 0.4 m drop) with scripted aileron pulses; one FlightAudio rig per cadence observes the same session:
## per tick (reference), once per 1-4 frames at 60 fps (a frame every 4 ticks) and once per frame at
## 30 fps (8 ticks) and 144 fps (5 frames per 12 ticks). Frames are simulated by calling the rig's
## per-frame flush. Reports observation counts, touchdown cues (tick, approach, force) and servo
## transition counts against the reference, and checks a rig-free lockstep session for exact physics.
## Research-only; see research/performance/README.md#observer-cadence-vq-01c-r1.
extends SceneTree

const Cadence := preload("res://render/presentation_cadence.gd")
const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const TICKS := 2880
## [label, every_frames, frame boundaries per 12 ticks]: 60 fps = 3, 30 fps = 1.5 (as 12/8), 144 fps = 7.2.
const VARIANTS := [["per_tick", 0, 60.0], ["60fps_x1", 1, 60.0], ["60fps_x2", 2, 60.0], ["60fps_x3", 3, 60.0],
	["60fps_x4", 4, 60.0], ["30fps_x1", 1, 30.0], ["144fps_x1", 1, 144.0]]

var _failures := 0


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


func _run() -> void:
	root.audio_listener_enable_3d = true
	var report := {}
	for case: Array in [["glide-in", 18.0, 14.0, 1.6], ["firm", 6.0, 12.0, 2.8], ["steep", 25.0, 18.0, 4.0],
			["drop-0.4m", -0.4, 3.0, 0.2]]:
		report[case[0]] = await _case(case[1], case[2], case[3])
	print("OBSERVER_CADENCE_PAIR ", JSON.stringify(report))
	print("OBSERVER CADENCE PAIR failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _session(height_m: float, forward_mps: float, sink_mps: float) -> Node:
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup(STIK, "jensen-das-ugly-stik-60")
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.set_field(Field.load_from().field)
	session.engine_running = false
	session.soft_hull_contacts = true
	var start := RB.make_state(M.v3(0.0, -40.0, -absf(height_m)), M.v3(forward_mps, 0.0, sink_mps),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	if height_m < 0.0:
		# Clearance from the lowest wheel instead of CG height.
		var compression: PackedFloat64Array = Ground.compressions(start, session.current_landing_gear())
		var maximum := -INF
		for x: float in compression: maximum = maxf(maximum, x)
		start[RB.POS + 2] += height_m - maximum
	session.sim.reset(start)
	session.sim.set_paused(false)
	return session


func _case(height_m: float, forward_mps: float, sink_mps: float) -> Dictionary:
	var session := _session(height_m, forward_mps, sink_mps)
	var lockstep := _session(height_m, forward_mps, sink_mps)
	var owner := Owner.new()
	owner.session = session
	owner.field = Field.load_from().field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	var rigs: Array = []
	var rows: Dictionary = {}
	for variant: Array in VARIANTS:
		Cadence.override_every_frames = variant[1]
		var rig: Node = Rig.new()
		Cadence.override_every_frames = -1
		owner.add_child(rig)
		rig.configure(owner)
		rig.set_process(false)
		rigs.append(rig)
		rows[variant[0]] = {ground_observations = 0, mechanical_observations = 0, cues = [], servo = {}, frame_clock = 0.0}
	var ticks := 0
	for i: int in TICKS:
		# Aileron pulses: 0.3 for 6 ticks every 60 ticks, alternating sign (servo start/stop cues).
		var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
		inputs[0] = (0.3 if (i / 60) % 2 == 0 else -0.3) if i % 60 < 6 else 0.0
		session.sim.inputs = inputs
		lockstep.sim.inputs = inputs.duplicate()
		session.sim.step()
		lockstep.sim.step()
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
			break
		ticks += 1
		for index: int in rigs.size():
			var rig: Node = rigs[index]
			var row: Dictionary = rows[VARIANTS[index][0]]
			# Frame boundaries at the variant's rate on the 240 Hz clock.
			row.frame_clock += float(VARIANTS[index][2]) / 240.0
			while row.frame_clock >= 1.0 - 1e-9:
				row.frame_clock -= 1.0
				rig._observe_due_endpoints()
			if rig.ground_audio.accepted_tick() == session.sim.tick and row.get("_ground_seen", -1) != session.sim.tick:
				row.ground_observations += 1
				row._ground_seen = session.sim.tick
			var mechanical_tick: int = int(rig.mechanical_audio.get("_accepted_motion_state").get("tick", -1))
			if mechanical_tick == session.sim.tick and row.get("_mechanical_seen", -1) != session.sim.tick:
				row.mechanical_observations += 1
				row._mechanical_seen = session.sim.tick
			var ground_events: Array = rig.ground_audio.get("_accepted_events")
			for event: Dictionary in ground_events:
				row.cues.append({tick = event.tick, id = event.contact.id, approach = event.approach, force = event.force})
			ground_events.clear()
			var servo_events: Array = rig.mechanical_audio.get("_accepted_events")
			for event: Dictionary in servo_events:
				var key := "%s:%s" % [event.id, event.event]
				row.servo[key] = int(row.servo.get(key, 0)) + 1
			servo_events.clear()
	var physics_exact: bool = var_to_bytes(session.checkpoint()) == var_to_bytes(lockstep.checkpoint())
	_check("lockstep physics identical with %d observing rigs" % rigs.size(), physics_exact)
	var reference: Dictionary = rows.per_tick
	var result := {ticks = ticks, physics_exact = physics_exact, variants = {}}
	for variant: Array in VARIANTS:
		var row: Dictionary = rows[variant[0]]
		var delays: Array = []
		var approach_error := 0.0
		var force_error := 0.0
		var matched: bool = row.cues.size() == reference.cues.size()
		if matched:
			for k: int in row.cues.size():
				var a: Dictionary = reference.cues[k]
				var b: Dictionary = row.cues[k]
				matched = matched and a.id == b.id
				delays.append(int(b.tick) - int(a.tick))
				approach_error = maxf(approach_error, absf(float(b.approach) - float(a.approach)))
				force_error = maxf(force_error, absf(float(b.force) - float(a.force)))
		result.variants[variant[0]] = {ground_observations = row.ground_observations,
			mechanical_observations = row.mechanical_observations, cues = row.cues.size(),
			cues_match_reference = matched, cue_delay_ticks = delays, max_approach_error_mps = approach_error,
			max_force_error_n = force_error, servo = row.servo}
		if variant[1] > 0:
			_check("%s: touchdown cues identical to per tick" % variant[0], matched and delays.max() == 0 \
				and approach_error == 0.0 and force_error == 0.0 if not delays.is_empty() else matched,
				str(result.variants[variant[0]]))
		print("%-10s ground_obs=%5d mech_obs=%5d cues=%d delays=%s servo=%s" % [variant[0], row.ground_observations,
			row.mechanical_observations, row.cues.size(), str(delays), str(row.servo)])
	for rig: Node in rigs:
		rig.free()
	owner.free()
	session.free()
	lockstep.free()
	await process_frame
	return result


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok   ", label)
