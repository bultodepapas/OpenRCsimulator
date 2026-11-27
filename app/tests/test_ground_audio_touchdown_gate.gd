## VQ-01c-R1 / F1: near the ground, flight audio forces a per-tick ground observation only while a wheel that is not
## grounded is compressed (touchdown_possible_at). A raised tail wheel on the takeoff roll, or a nose-over, made every
## tick pay a full observation (about 0.5 ms). Real Corsair sessions with and without the gate: the gate observes far
## less often, and the touchdown cues of a drop onto the wheels are identical.
extends SceneTree

const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const GroundAudio := preload("res://audio/ground_audio.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")
const Cadence := preload("res://render/presentation_cadence.gd")
const RB := preload("res://physics/rigid_body.gd")
const CORSAIR := "f4u-corsair-250"

var checks := 0
var failed := 0
var field: Dictionary
var lake: Dictionary


class Owner extends Node3D:
	var session: Node
	var field := {}
	var aircraft_id := CORSAIR
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


func _row(id: String, force: float) -> Dictionary:
	return {id = id, position = Vector3.ZERO, normal_force_n = force, reference_load_n = 20.0,
		approach_speed_mps = 0.5, rolling_speed_mps = 0.0, surface = "hard"}


func _unit_checks() -> void:
	var g: Node = GroundAudio.new()
	root.add_child(g)
	g.set_accepted_tick_observation(true)
	var ids := PackedStringArray(["main_left", "main_right", "tail"])
	check("an unprimed rig can always cue", g.touchdown_possible_at(ids, PackedFloat64Array([-1.0, -1.0, -1.0])))
	g.observe_accepted({tick = 1, tick_rate = 240.0, paused = false,
		contacts = [_row("main_left", 20.0), _row("main_right", 20.0), _row("tail", 0.0)]})
	check("the tail wheel is up", g.touchdown_possible())
	check("a raised wheel clear of the ground cannot cue on this tick",
		not g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02, -0.08])))
	check("a raised wheel that is compressed can cue", g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02, 0.0001])))
	check("a compression within the rounding margin keeps the per-tick answer",
		g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02, -1e-7])))
	check("an unmeasured compression keeps the per-tick answer",
		g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02, NAN])))
	check("an unloaded grounded wheel forces its liftoff tick",
		g.touchdown_possible_at(ids, PackedFloat64Array([0.0, 0.02, -0.08])))
	check("an uncovered raised wheel keeps the full answer",
		g.touchdown_possible_at(PackedStringArray(["main_left", "main_right"]), PackedFloat64Array([0.02, 0.02])))
	check("an unknown wheel keeps the full answer",
		g.touchdown_possible_at(PackedStringArray(["main_left", "main_right", "skid"]), PackedFloat64Array([0.02, 0.02, -1.0])))
	check("mismatched sizes keep the full answer", g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02])))
	g.observe_accepted({tick = 2, tick_rate = 240.0, paused = false, since_tick = 1,
		contacts = [_row("main_left", 20.0), _row("main_right", 20.0), _row("tail", 20.0)]})
	check("every wheel grounded: no cue on any tick",
		not g.touchdown_possible_at(ids, PackedFloat64Array([0.02, 0.02, 0.02])))
	g.free()


func _session() -> Node:
	var node := Session.new()
	node.input_enabled = false
	node.crash_auto_restart = false
	node.soft_hull_contacts = true
	node.start_choice = Session.START_RUNWAY
	node.setup(Catalog.data_for(CORSAIR, Catalog.default_battery_mode(CORSAIR)), CORSAIR)
	node.set_field(field)
	node.set_lake_context(lake)
	node.reset()
	node.set_process(false)
	node.set_physics_process(false)
	return node


func _rig(session: Node, gate: bool) -> Node:
	var owner := Owner.new()
	owner.session = session
	owner.field = field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	var audio := Rig.new()
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	audio.touchdown_gate_enabled = gate
	return audio


## Steps both sessions with the same inputs. A "frame" every two ticks takes the due cadence observation.
## Returns how many ticks each rig observed the ground on.
func _fly(pair: Array, ticks: int, throttle: float, raise_m := 0.0) -> Array:
	var observed := [0, 0]
	for index in 2:
		var session: Node = pair[index].flight.session
		if raise_m != 0.0:
			var state: PackedFloat64Array = session.sim.state.duplicate()
			state[RB.POS + 2] -= raise_m
			session.sim.state = state
	for tick in ticks:
		for index in 2:
			var audio: Node = pair[index]
			var session: Node = audio.flight.session
			var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
			inputs[3] = throttle
			session.sim.inputs = inputs
			session.sim.step()
			if tick % 2 == 1:
				audio._observe_due_endpoints()
			if audio.ground_audio.accepted_tick() == session.sim.tick:
				observed[index] += 1
		if tick % 7 == 0:
			_compare_approaches(pair[0].flight.session)
	return observed


var approach_samples := 0
var approach_mismatches := 0


## approach_speeds() is the near-ground rows' approach_speed_mps, bit for bit, with the same identities.
func _compare_approaches(session: Node) -> void:
	var identities := PackedStringArray()
	var approaches := GroundAudioModel.approach_speeds(session, identities)
	if approaches.is_empty():
		return
	var rows: Array[Dictionary] = GroundAudioModel.snapshot_contacts(session, field)
	approach_samples += 1
	if rows.size() != approaches.size():
		approach_mismatches += 1
		return
	for index in rows.size():
		if str(rows[index].id) != identities[index] \
				or var_to_bytes(float(rows[index].approach_speed_mps)) != var_to_bytes(approaches[index]):
			approach_mismatches += 1


func _run() -> void:
	Cadence.override_every_frames = -1 # the shipped once-per-frame cadence
	field = FieldLoader.load_from().field
	lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	_unit_checks()
	var gated := _rig(_session(), true)
	var full := _rig(_session(), false)
	var pair := [gated, full]
	check("both rigs observe the ground on accepted ticks", gated._accepted_ground_mode and full._accepted_ground_mode)
	# Full power on the runway: the Corsair's tail rises while the mains roll.
	var roll := _fly(pair, 1200, 1.0)
	var same_state: bool = var_to_bytes(gated.flight.session.sim.state) == var_to_bytes(full.flight.session.sim.state)
	check("audio observation never changes the flight", same_state)
	# 1,200 ticks are 600 frames. Without the gate the raised tail wheel forced most ticks.
	check("without the gate most rolling ticks were observed", roll[1] >= 900, str(roll))
	check("the gate observes about once per frame on the takeoff roll", roll[0] >= 600 - 2 and roll[0] <= 620, str(roll))
	# A drop onto the wheels from rest: every wheel descends and touches; the cues must be identical.
	for audio: Node in pair:
		audio.flight.session.reset()
		audio._on_mechanical_pause_changed(false)
	_fly(pair, 240, 0.0) # settle on the runway
	for audio: Node in pair:
		audio.ground_audio.get("_accepted_events").clear()
	var drop := _fly(pair, 480, 0.0, 0.35)
	var cues_gated: Array = gated.ground_audio.get("_accepted_events")
	var cues_full: Array = full.ground_audio.get("_accepted_events")
	check("the drop produces touchdown cues", not cues_full.is_empty(), str(drop))
	check("the gate keeps every touchdown cue, tick and strength", var_to_bytes(cues_gated) == var_to_bytes(cues_full),
		str([cues_gated.map(func(e: Dictionary) -> Array: return [e.tick, e.approach]),
			cues_full.map(func(e: Dictionary) -> Array: return [e.tick, e.approach])]))
	check("the skipped-tick approach equals the rows' approach", approach_samples > 100 and approach_mismatches == 0,
		str([approach_samples, approach_mismatches]))
	print("%d checks, %d failed" % [checks, failed])
	quit(1 if failed > 0 else 0)
