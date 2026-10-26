## Real Session/accepted-contact path with Dummy audio. No calibrated sound claim.
extends SceneTree
const S = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/flight_session.gd")
const D = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/director.gd")
const C = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/presentation_context.gd")
const H = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp19-hull-scrape/draft/hull_contact.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Field = preload("res://data/field_loader.gd")
const Lake = preload("res://data/lake_loader.gd")
const Impact = preload("res://physics/impact_snapshot.gd")
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const GLOW := "res://data/aircraft/stik_glow_61fx_2t.json"
var checks := 0
var failed := 0
func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok: failed += 1; printerr("FAIL ",label," ",detail)
func _initialize() -> void: call_deferred("_run")
func session(path := STIK) -> Node:
	var f := S.new()
	f.input_enabled=false
	f.crash_auto_restart=false
	f.soft_hull_contacts=true
	f.setup(path)
	f.set_process(false)
	f.set_physics_process(false)
	f.engine_running=false
	return f
func body(f: Node) -> PackedFloat64Array:
	var q := M.q_from_euler(0.0,0.0,deg_to_rad(40.0))
	var extent := -INF
	for i in range(0,f.aircraft.model.crash_hull.size(),3):
		extent=maxf(extent,M.q_rotate(q,f.aircraft.model.crash_hull.slice(i,i+3))[2])
	return RB.make_state(M.v3(0,0,.001-extent),M.q_rotate(M.q_conj(q),M.v3(5,0,0)),q,M.v3(0,0,0))
func director(f: Node, enabled := true) -> Node:
	var aircraft := Node3D.new()
	aircraft.name="airplane"
	root.add_child(aircraft)
	var bindings := C.ModelBindings.new()
	bindings.root=aircraft;bindings.empty=false
	var context := C.new()
	context.session=f;context.model_bindings=bindings
	context.field=Field.load_from().field
	context.aircraft_id="jensen-das-ugly-stik-60"
	context.aircraft_data_path=STIK
	context.pose_provider=func() -> Dictionary: return {basis=Basis.IDENTITY,pos=Vector3.ZERO}
	context.wind_provider=func(_t: float) -> Vector3: return Vector3.ZERO
	var d := D.new()
	root.add_child(d)
	check("explicit Director configures once",d.configure(context,enabled) and not d.configure(context,enabled))
	return d
func count(signal_value: Signal, id: int) -> int:
	var n:=0
	for connection: Dictionary in signal_value.get_connections():
		if connection.callable.get_object_id()==id:n+=1
	return n
func cleanup(d: Node) -> void:
	var source: Node=d.context.model_bindings.root
	d.free();source.free()
func _run() -> void:
	root.audio_listener_enable_3d=true
	var f:=session()
	var reference:=session()
	check("real sessions admitted",f.is_flyable() and reference.is_flyable())
	check("field installation succeeds",f.set_field(Field.load_from().field) and reference.set_field(Field.load_from().field))
	var initial:=body(f)
	check("identical explicit wingtip contact starts",f.sim.reset(initial) and reference.sim.reset(initial))
	f.sim.set_paused(false);reference.sim.set_paused(false)
	var d:=director(f)
	var silent:=director(reference,false)
	await process_frame
	check("accepted observer primed after child bus setup",d._hull_capture_ready and d.audio.hull_scrape_diagnostics().tick==0)
	check("connections once after existing Session handler",count(f.sim.stepped,d.get_instance_id())==1 and count(f.sim.paused_changed,d.get_instance_id())==1 and count(f.statistics_lifecycle,d.get_instance_id())==1)
	var exact:=true
	var loaded:=false
	var bound:=true
	var packet: Dictionary={}
	for _i in 18:
		f.sim.step();reference.sim.step()
		var before:=var_to_bytes(f.checkpoint())
		packet=f.hull_scrape_observation()
		loaded=loaded or not packet.contacts.is_empty()
		for row: Dictionary in packet.contacts:
			bound=bound and f._contact_bindings.hull_probes.any(func(p): return p.id==row.contact_id) and row.size()==7
		exact=exact and before==var_to_bytes(f.checkpoint()) and before==var_to_bytes(reference.checkpoint())
	check("real accepted force rows carry source hull IDs",loaded and bound and packet.size()==9)
	check("full observer on/off checkpoints remain exact",exact)
	check("accepted contact queued before any render",d.audio.hull_scrape_diagnostics().queued>0,str(d.audio.hull_scrape_diagnostics()))
	var queued: int=d.audio.hull_scrape_diagnostics().queued
	var rng: int=d.audio._rng.state
	# Legacy speed-based sliding branch is exclusive: direct visual feedback cannot
	# consume audio RNG while accepted grains still wait for update/drain.
	d._touch_feedback()
	check("legacy sliding audio suppressed without suppressing visual feedback",d.audio._rng.state==rng and d.audio.hull_scrape_diagnostics().queued==queued)
	d.update(1./60.)
	check("live render drains actual pre-render accepted scrape once",d.audio.hull_scrape_diagnostics().emitted==queued and d.audio.hull_scrape_diagnostics().queued==0)
	var emitted: int=d.audio.hull_scrape_diagnostics().emitted
	d.update(1./144.)
	check("repeated frame cannot replay grain",d.audio.hull_scrape_diagnostics().emitted==emitted)
	var saved: Dictionary=f.checkpoint()
	packet=f.hull_scrape_observation()
	if not packet.contacts.is_empty():packet.contacts[0].friction_power_w=-1.0
	check("public packet detached from cache",f.hull_scrape_observation().contacts.all(func(row): return row.friction_power_w>=0.0))
	var before_pause:=var_to_bytes(f.checkpoint())
	f.sim.set_paused(true)
	check("pause leaves exact physical checkpoint and clears pending grains",before_pause==var_to_bytes(f.checkpoint()) and d.audio.hull_scrape_diagnostics().queued==0)
	f.sim.step()
	check("manual paused accepted step stays silent",d.audio.hull_scrape_diagnostics().queued==0)
	f.sim.set_paused(false)
	check("resume does not replay manual step",d.audio.hull_scrape_diagnostics().queued==0)
	check("restore uses existing exact physical owner",f.restore_checkpoint(saved))
	check("restore generation primes without replay",d.audio.hull_scrape_diagnostics().queued==0 and d.audio.hull_scrape_diagnostics().tick==f.sim.tick and d.audio.hull_scrape_diagnostics().generation==f.statistics_generation)
	var tick: int=d.audio.hull_scrape_diagnostics().tick
	f.sim.mass=-1.0;f.sim.step()
	check("rejected candidate publishes no new accepted audio",d.audio.hull_scrape_diagnostics().tick==tick and d.audio.hull_scrape_diagnostics().queued==0)
	check("restore recovers disposable invalid mass",f.restore_checkpoint(saved))
	var bus_count:=AudioServer.bus_count
	var id:=d.get_instance_id()
	root.remove_child(d)
	check("detach disconnects accepted signals and releases one bus",count(f.sim.stepped,id)==0 and count(f.sim.paused_changed,id)==0 and count(f.statistics_lifecycle,id)==0 and AudioServer.bus_count==bus_count-1)
	root.add_child(d)
	await process_frame
	check("reattach settles one prime and bounded bus/pool",count(f.sim.stepped,id)==1 and AudioServer.bus_count==bus_count and d.audio.voice_count()==8 and d.audio.hull_scrape_diagnostics().tick==f.sim.tick and d.audio.hull_scrape_diagnostics().queued==0)
	check("configured Director rejects reconfiguration without duplicate observers",not d.configure(d.context,true) and count(f.sim.stepped,id)==1)
	f.reset()
	check("reset lifecycle clears grains and pins new generation",d.audio.hull_scrape_diagnostics().queued==0 and d.audio.hull_scrape_diagnostics().generation==f.statistics_generation)
	# Pending source layout must return before any finite-fuel properties/layout query.
	var ready_before:=var_to_bytes(f.checkpoint())
	f._shaft_pending_reset=true
	check("pending configuration observation explicitly unavailable",not f.hull_scrape_observation().available and f.hull_scrape_observation().reason=="flight_not_ready")
	f._shaft_pending_reset=false
	check("pending observation has no physical side effects",ready_before==var_to_bytes(f.checkpoint()))
	cleanup(d);cleanup(silent);f.free();reference.free()
	# Real finite-fuel owner, half tank and actual nonzero CG: diagnostics forwarded
	# through the same live-property law rather than constant-build stiffness.
	var fuel:=session(GLOW)
	check("finite-fuel source admitted",fuel.is_flyable() and fuel.finite_fuel_is_active())
	fuel.sim.continuous[1]*=.5
	check("finite-fuel accepted body reset",fuel.sim.reset(body(fuel)))
	var properties: Dictionary=fuel.mass_properties()
	var rows: Array=[]
	var expected:=H.loads_at_properties(fuel.sim.state,fuel._hull_contact,properties,rows)
	var before_fuel:=var_to_bytes(fuel.checkpoint())
	var observed: Dictionary=fuel.hull_scrape_observation()
	check("actual half-tank contact observation uses live mass/CG",properties.ok and properties.finite_fuel and properties.cg_body_m[0]!=0.0 and expected.ok and rows.size()>0 and observed.available and observed.contacts.size()==rows.size())
	var same:=true
	for i in rows.size():same=same and rows[i].normal_force_n==observed.contacts[i].normal_force_n and rows[i].friction_power_w==observed.contacts[i].friction_power_w
	check("finite-fuel force diagnostics equal existing actual law exactly",same and before_fuel==var_to_bytes(fuel.checkpoint()))
	var wet: float=observed.contacts[0].normal_force_n
	fuel.sim.continuous[1]=fuel.aircraft.model.propulsion.glow.initial_fuel_kg
	var full: Dictionary=fuel.hull_scrape_observation()
	check("same-tick fuel epoch invalidates derived cache",full.available and full.contacts[0].normal_force_n!=wet)
	var fuel_reference:=session(GLOW)
	check("paired live-fuel contact starts exact",fuel.sim.reset(body(fuel)) and fuel_reference.sim.reset(body(fuel_reference)) and var_to_bytes(fuel.checkpoint())==var_to_bytes(fuel_reference.checkpoint()))
	var fuel_exact:=true
	for _i in 24:
		fuel.sim.step();fuel_reference.sim.step()
		var accepted:=var_to_bytes(fuel.checkpoint())
		fuel.hull_scrape_observation()
		fuel_exact=fuel_exact and accepted==var_to_bytes(fuel.checkpoint()) and accepted==var_to_bytes(fuel_reference.checkpoint())
	check("finite-fuel accepted-tick observer on/off preserves all checkpoint bytes",fuel_exact and fuel.sim.fault_reason.is_empty())
	fuel.free();fuel_reference.free()
	# Lake is deliberately outside the qualified exact flat-force observation domain.
	var lake_flight:=session()
	var loaded_lake:=Lake.load_from()
	check("lake fixture loads",loaded_lake.ok)
	if loaded_lake.ok:
		check("lake context installs on accepted tick0",lake_flight.set_lake_context(loaded_lake.lake))
		check("lake observation refuses without guessed power/material",not lake_flight.hull_scrape_observation().available and lake_flight.hull_scrape_observation().reason=="flat_solid_scope_lake_unavailable")
		var water_director:=director(lake_flight)
		await process_frame
		# Cancellation fixture injects an old queued grain/tag, without playback on
		# Dummy. The real Director water handoff must cancel both before splash.
		water_director.audio._scrape_queue.append({tick=0,point_ned=M.v3(0,0,0),power_w=1.0})
		water_director.audio._scrape_tags[0]=1
		water_director.audio._voices[0].stream=water_director.audio._streams.scrape
		var impact:=Impact.Snapshot.new()
		impact.trigger="water";impact.tick=1;impact.detected_state=lake_flight.sim.state.duplicate()
		impact.has_kinematics=true;impact.point_ned=M.v3(110.,125.,.8);impact.velocity_ned=M.v3(0,0,2)
		impact.speed_mps=2.0;impact.down_speed_mps=2.0
		lake_flight.crash={impact=impact,why="synthetic water handoff",ticks_left=20}
		var before_water:=var_to_bytes(lake_flight.checkpoint())
		water_director.update(1./60.)
		check("water handoff cancels continuing scrape pool/queue exclusively",water_director._water_active and water_director.audio.hull_scrape_diagnostics().queued==0 and water_director.audio.hull_scrape_diagnostics().tagged_voices==0 and not water_director.audio._primary_played)
		check("water visual/audio handoff preserves all physical checkpoint bytes",before_water==var_to_bytes(lake_flight.checkpoint()))
		cleanup(water_director)
	lake_flight.free()
	print("Hull scrape Session: %d checks, %d failed"%[checks,failed])
	print("Hull scrape Session complete")
	quit(1 if failed else 0)
