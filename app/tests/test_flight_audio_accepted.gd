## GP-19: accepted actual mechanism endpoints through FlightAudio, Dummy driver
## only. No rendered/native listening claim or aircraft/asset/state changes.
extends SceneTree
const Rig := preload("res://audio/flight_audio.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Motion := preload("res://audio/mechanical_motion.gd")
const Cadence := preload("res://render/presentation_cadence.gd")
const P51 := "res://data/aircraft/p51d_mustang_120.json"
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
var checks := 0
var failed := 0
var exact := true

class Owner extends Node3D:
	var session: Node
	var field := {}
	var aircraft_id := "p51d-mustang-120"
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


func make_session(path := P51, id := "p51d-mustang-120") -> Node:
	var node := Session.new()
	node.input_enabled = false
	node.crash_auto_restart = false
	node.setup(path, id)
	node.set_process(false)
	node.set_physics_process(false)
	return node


func make_owner(session: Node) -> Owner:
	var owner := Owner.new()
	owner.session = session
	owner.field = FieldLoader.load_from().field
	var plane := Node3D.new()
	owner.add_child(plane)
	owner._airplane = {root = plane, model_manifest = {bindings = {controls = {}}}, hinges = {}}
	owner._camera = Camera3D.new()
	owner.add_child(owner._camera)
	root.add_child(owner)
	return owner


func step_pair(player: Node, reference: Node, roll: float, gear := -1.0, flap := -1.0) -> void:
	var inputs: PackedFloat64Array = player.sim.inputs.duplicate()
	inputs[0] = roll
	if gear >= 0.0 and player.gear_is_retractable(): inputs[4] = gear
	if flap >= 0.0 and player.flaps_available(): inputs[player.flap_input_index()] = flap
	player.sim.inputs = inputs
	reference.sim.inputs = inputs.duplicate()
	player.sim.step()
	reference.sim.step()
	exact = exact and var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint())


func gesture(player: Node, reference: Node) -> void:
	for i: int in 2: step_pair(player, reference, 1.0)
	for i: int in 2: step_pair(player, reference, -1.0)
	# Return fully to the physical neutral/trim target, then include its accepted
	# stationary endpoint. No render occurs during this short bounded gesture.
	for i: int in 16: step_pair(player, reference, 0.0)


func events(mechanical: Node, system: String, id: String) -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in mechanical.get("_accepted_events"):
		if event.system == system and event.id == id: result.append(str(event.event))
	return result


func observer_connections(signal_value: Signal, observer_id: int) -> int:
	var count := 0
	for connection: Dictionary in signal_value.get_connections():
		if connection.callable.get_object_id() == observer_id: count += 1
	return count


func _run() -> void:
	# This script pins the per-tick accepted contract (presentation cadence 0); the once-per-frame
	# default is pinned in test_presentation_cadence.gd.
	Cadence.override_every_frames = 0
	root.audio_listener_enable_3d = true
	var player := make_session()
	var reference := make_session()
	check("real P51 sessions initialize identically", player.is_flyable() and reference.is_flyable()
		and var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint()))
	# Runway initialization includes a trim-derived servo endpoint. Let the real
	# neutral command settle in both owners before the observer's first sample.
	for i: int in 32: step_pair(player, reference, 0.0)
	var owner := make_owner(player)
	var audio := Rig.new()
	var audio_id: int = audio.get_instance_id()
	owner.add_child(audio)
	var before := var_to_bytes(player.checkpoint())
	var bus_count := AudioServer.bus_count
	audio.configure(owner)
	audio.set_process(false)
	var mechanical: Node = audio.mechanical_audio
	check("configure enables accepted mode and silently primes", mechanical.diagnostics().accepted_tick_observation
		and mechanical.diagnostics().accepted_tick_samples == 1 and mechanical.diagnostics().accepted_pending_event_count == 0)
	check("configure and current endpoint reads preserve full session checkpoint", before == var_to_bytes(player.checkpoint()))
	check("accepted observer connects exactly once", observer_connections(player.sim.stepped, audio_id) == 1
		and observer_connections(player.sim.paused_changed, audio_id) == 1 and observer_connections(player.resetting, audio_id) == 1)
	var primed := audio.accepted_mechanical_snapshot()
	check("accepted callback payload has no render position or force telemetry", not primed.has("listener")
		and not primed.channels[0].has("position") and not primed.has("loads"))
	var initial_angle: float = primed.channels[0].angle_deg
	gesture(player, reference)
	var final_snapshot := audio.accepted_mechanical_snapshot()
	check("brief real servo returns to its initial accepted angle", absf(final_snapshot.channels[0].angle_deg - initial_angle) < 1e-10,
		str({before = initial_angle, after = final_snapshot.channels[0].angle_deg}))
	check("all between-render start/reverse/stop edges survive", events(mechanical, "servo", "aileron") == ["start", "reverse", "stop"], str(events(mechanical, "servo", "aileron")))
	var legacy := Motion.observe(Motion.observe({}, primed).state, final_snapshot)
	var render_only_edges := []
	for event: Dictionary in legacy.events:
		if event.id == "aileron": render_only_edges.append(event)
	check("the same render-only endpoints miss the completed gesture", render_only_edges.is_empty())
	check("accepted channel values equal actual physical outputs", final_snapshot.channels[0].angle_deg == player.surface_angles_deg().aileron_right)
	var samples: int = mechanical.diagnostics().accepted_tick_samples
	audio._observe_mechanical_endpoint()
	check("duplicate or target-only observation cannot add samples", mechanical.diagnostics().accepted_tick_samples == samples)
	var counts: int = mechanical.diagnostics().accepted_events_observed
	player.sim.inputs[0] = 1.0
	audio._observe_mechanical_endpoint()
	check("target without actual endpoint motion makes no cue", mechanical.diagnostics().accepted_events_observed == counts)
	player.sim.inputs = reference.sim.inputs.duplicate()
	owner._airplane.root.position = Vector3(3.0, 1.0, 0.0)
	audio._process(1.0 / 60.0)
	check("one render drains the captured transitions", mechanical.diagnostics().accepted_pending_event_count == 0
		and mechanical.diagnostics().accepted_events_drained >= 3)
	var drained: int = mechanical.diagnostics().accepted_events_drained
	audio._process(1.0 / 60.0)
	check("rendering twice cannot replay captured transitions", mechanical.diagnostics().accepted_events_drained == drained)
	check("render draining also preserves full session checkpoint", var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint()))
	# Actual flap/gear accepted travel, not requests or render-node rotation.
	step_pair(player, reference, 0.0, 1.0, 1.0)
	step_pair(player, reference, 0.0, 0.0, 0.0)
	step_pair(player, reference, 0.0, 0.0, 0.0)
	check("brief actual retract cycle retains start/reverse/lock", events(mechanical, "gear", "gear") == ["start", "reverse", "lock"], str(events(mechanical, "gear", "gear")))
	var endpoint := audio.accepted_mechanical_snapshot()
	check("flap/gear payload uses physical endpoint state", endpoint.channels[3].angle_deg
		== player.sim.aux[player.flap_aux_index()] * player.aircraft.model.flaps.max_angle_deg
		and endpoint.gear.extension == player.gear_state().extension)
	# Pause is silent, including intentional manual accepted ticks.
	var sample_count: int = mechanical.diagnostics().accepted_tick_samples
	player.sim.set_paused(true)
	reference.sim.set_paused(true)
	check("pause drops queued cues without a fake accepted tick", mechanical.diagnostics().accepted_pending_event_count == 0
		and mechanical.diagnostics().accepted_tick_samples == sample_count)
	var observed: int = mechanical.diagnostics().accepted_events_observed
	var at: int = player.sim.tick
	step_pair(player, reference, 1.0)
	check("manual paused step advances physics but only primes mechanics", player.sim.tick == at + 1
		and audio.accepted_mechanical_snapshot().paused and mechanical.diagnostics().accepted_pending_event_count == 0
		and mechanical.diagnostics().accepted_events_observed == observed)
	player.sim.set_paused(false)
	reference.sim.set_paused(false)
	check("resume cannot replay silent manual motion", mechanical.diagnostics().accepted_pending_event_count == 0)
	# Kernel rewind with no FlightSession resetting signal: do not erase valid
	# post-rewind gestures merely because the next render notices the lower tick.
	var saved: Dictionary = player.sim.checkpoint()
	var saved_reference: Dictionary = reference.sim.checkpoint()
	for i: int in 20: step_pair(player, reference, 0.0)
	audio._process(1.0 / 60.0)
	check("kernel rewind succeeds for both identical owners", player.sim.restore_checkpoint(saved) and reference.sim.restore_checkpoint(saved_reference))
	player.sim.set_paused(false)
	reference.sim.set_paused(false)
	gesture(player, reference)
	var pending: int = mechanical.diagnostics().accepted_pending_event_count
	audio._process(1.0 / 60.0)
	check("render rewind preserves newly captured post-rewind gesture", pending > 0
		and mechanical.diagnostics().accepted_events_drained > drained and mechanical.diagnostics().accepted_pending_event_count == 0)
	var resets: int = mechanical.diagnostics().reset_count
	player.reset()
	reference.reset()
	check("session reset clears and primes exactly once", mechanical.diagnostics().reset_count == resets + 1
		and mechanical.diagnostics().accepted_pending_event_count == 0 and audio._last_tick == -1)
	# Detach disconnects and awaits child bus recreation before priming again.
	owner.remove_child(audio)
	check("detached rig has no accepted callbacks", observer_connections(player.sim.stepped, audio_id) == 0)
	samples = mechanical.diagnostics().accepted_tick_samples
	gesture(player, reference)
	check("detached motion is never retained for replay", mechanical.diagnostics().accepted_tick_samples == samples
		and mechanical.diagnostics().accepted_pending_event_count == 0)
	owner.add_child(audio)
	check("reattach waits for buses before accepted capture", observer_connections(player.sim.stepped, audio_id) == 0)
	await process_frame
	check("reattached buses exist before source priming", observer_connections(player.sim.stepped, audio_id) == 1
		and AudioServer.get_bus_index(mechanical.get("_bus")) >= 0 and mechanical.diagnostics().accepted_pending_event_count == 0)
	gesture(player, reference)
	check("first post-settle gesture is not erased by deferred rebind", not events(mechanical, "servo", "aileron").is_empty())
	var after_settle: int = mechanical.diagnostics().accepted_pending_event_count
	await process_frame
	check("deferred bus work preserves accepted pending gesture", mechanical.diagnostics().accepted_pending_event_count == after_settle)
	check("audio observes every step without changing full physics state", exact
		and var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint()))
	var accepted_before: int = mechanical.diagnostics().accepted_tick_samples
	var events_before: int = mechanical.diagnostics().accepted_events_observed
	var tick_before: int = player.sim.tick
	player.sim.model.post_tick = func(_old, _candidate, _tick): return PackedFloat64Array([NAN])
	reference.sim.model.post_tick = func(_old, _candidate, _tick): return PackedFloat64Array([NAN])
	player.sim.step()
	reference.sim.step()
	check("rejected physical tick appends no accepted sample or cue", player.sim.tick == tick_before
		and not player.sim.fault_reason.is_empty() and mechanical.diagnostics().accepted_tick_samples == accepted_before
		and mechanical.diagnostics().accepted_events_observed == events_before)
	check("rejected paired owners retain exact full checkpoint parity", var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint()))
	# Same-instance configure replaces old source/bus ownership rather than
	# accumulating subscriptions or channel rows across aircraft configurations.
	var second := make_session(STIK, "jensen-das-ugly-stik-60")
	var old_mechanics: WeakRef = weakref(mechanical)
	owner.session = second
	owner.aircraft_id = "jensen-das-ugly-stik-60"
	audio.configure(owner)
	check("reconfigure disposes prior rig and old-session connections", old_mechanics.get_ref() == null
		and observer_connections(player.sim.stepped, audio_id) == 0 and observer_connections(second.sim.stepped, audio_id) == 1
		and observer_connections(second.resetting, audio_id) == 1)
	check("reconfigure rebuilds exactly the installed actuator channels", audio._mechanical_channels.size() == 3
		and audio.accepted_mechanical_snapshot().channels.size() == 3)
	var buses_after: int = AudioServer.bus_count
	audio.configure(owner)
	check("repeat configure has stable bus and callback counts", AudioServer.bus_count == buses_after
		and observer_connections(second.sim.stepped, audio_id) == 1 and observer_connections(second.sim.paused_changed, audio_id) == 1)
	audio.free()
	check("free releases callbacks and scene-local buses", observer_connections(second.sim.stepped, audio_id) == 0
		and observer_connections(second.resetting, audio_id) == 0 and AudioServer.bus_count == bus_count)
	owner.free()
	player.free()
	reference.free()
	second.free()
	print("FlightAudio accepted endpoints: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)
