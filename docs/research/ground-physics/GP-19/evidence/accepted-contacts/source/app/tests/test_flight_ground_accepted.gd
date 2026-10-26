## Real legacy-contact drop: read-only accepted audio and checkpoint equality.
## Synthetic initial condition; does not qualify a new contact law or acoustic realism.
extends "res://tests/test_flight_audio_accepted.gd"
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

func drop_session() -> Node:
	var f := make_session(STIK, "jensen-das-ugly-stik-60")
	check("actual Stik identity and physics admitted", f.is_flyable())
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
	check("explicit 0.4m clearance drop reset admitted", f.sim.reset(s))
	return f

func _run() -> void:
	root.audio_listener_enable_3d = true
	var player := drop_session()
	var reference := drop_session()
	check("initial drop checkpoints exact", var_to_bytes(player.checkpoint()) == var_to_bytes(reference.checkpoint()))
	var owner := make_owner(player)
	owner.aircraft_id = "jensen-das-ugly-stik-60"
	var audio := Rig.new()
	owner.add_child(audio)
	audio.configure(owner)
	audio.set_process(false)
	var ground: Node = audio.ground_audio
	check("production observer primes real contacts with no cue or players", ground.accepted_diagnostics().tick == player.sim.tick and ground.accepted_diagnostics().queued == 0 and ground.get_child_count() == 0)
	var first_tick := -1
	var queued := 0
	var observation_usec: Array[int] = []
	for _i in 150:
		step_pair(player, reference, 0.0)
		var before := var_to_bytes(player.checkpoint())
		var begin := Time.get_ticks_usec()
		audio._observe_ground_endpoint()
		observation_usec.append(Time.get_ticks_usec() - begin)
		exact = exact and before == var_to_bytes(player.checkpoint())
		if ground.accepted_diagnostics().queued > 0 and first_tick < 0:
			first_tick = player.sim.tick
		if first_tick >= 0 and player.sim.tick >= first_tick + 12: break
	check("real accepted drop produces contact sound before rendering", first_tick > 35 and ground.accepted_diagnostics().queued > 0, str(ground.accepted_diagnostics()))
	queued = ground.accepted_diagnostics().queued
	check("real flight capture leaves all full checkpoint bytes exact", exact)
	check("accepted-only capture still created no audio players", ground.get_child_count() == 0 and ground.touchdown_events == 0)
	check("actual drop stays accepted without numerical fault", player.sim.fault_reason.is_empty())
	audio._process(1.0 / 60.0)
	check("render consumes actual between-frame touchdown cues", queued > 0 and ground.accepted_diagnostics().queued == 0 and ground.touchdown_events > 0)
	var played: int = ground.touchdown_events
	audio._process(1.0 / 60.0)
	check("second render cannot replay actual touchdown", ground.touchdown_events == played)
	var prior := var_to_bytes(player.checkpoint())
	player.sim.set_paused(true)
	check("pause notification primes ground observer without snapshot force work", ground.accepted_diagnostics().states == 0 and ground.accepted_diagnostics().queued == 0)
	check("pause preserves accepted physical checkpoint", prior == var_to_bytes(player.checkpoint()))
	var accepted_tick: int = ground.accepted_diagnostics().tick
	# A rejected kernel step emits no accepted endpoint and cannot manufacture audio.
	player.sim.mass = -1.0
	player.sim.step()
	check("rejected step emits no new ground history", ground.accepted_diagnostics().tick == accepted_tick and ground.accepted_diagnostics().queued == 0)
	var buses := AudioServer.bus_count
	owner.remove_child(audio)
	check("rig detach clears ground observer history", ground.accepted_diagnostics().tick == -1 and ground.accepted_diagnostics().queued == 0)
	owner.add_child(audio)
	await process_frame
	check("reattach reconnects one shared stepped observer", observer_connections(player.sim.stepped, audio.get_instance_id()) == 1)
	check("reattach keeps bounded bus ownership", AudioServer.bus_count == buses)
	observation_usec.sort()
	print("GROUND_CAPTURE_DIAGNOSTIC ", JSON.stringify({samples = observation_usec.size(),
		median_usec = observation_usec[observation_usec.size()/2], p95_usec = observation_usec[int(.95 * (observation_usec.size()-1))],
		first_touchdown_tick = first_tick, last_tick = reference.sim.tick, queued_before_render = queued,
		scope = "duplicate endpoint capture includes legacy force/material snapshot; shared-host diagnostic, not frame/native qualification"}))
	owner.free()
	player.free()
	reference.free()
	print("Flight ground accepted: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)
