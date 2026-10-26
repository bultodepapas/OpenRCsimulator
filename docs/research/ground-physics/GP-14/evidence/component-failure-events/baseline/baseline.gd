## Baseline bridge audit using the existing actual normal/common-rotor/kernel fixture.
extends "res://tests/test_aircraft_ground_damage.gd"
const FlightEvent := preload("res://statistics/flight_event.gd")
const ContactEvents := preload("res://sim/aircraft_contact_events.gd")
const Detector := preload("res://statistics/detector.gd")
const Service := preload("res://statistics/service.gd")
var observations: Array[Dictionary] = []
var destination := ""

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	destination=ProjectSettings.globalize_path("res://../tmp/damage-events-baseline-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(destination)
	_fixture()
	_bind()
	if failed:quit(1);return
	var heavy: Dictionary
	for spec: Array in [["light",1.0,0.8],["heavy",4.0,0.8],["hard",1.0,2.0]]:
		var run:=_simulate(spec[1],spec[2],48)
		check("accepted fixture ends at48 "+str(spec[0]),run.sim.tick==48 and run.sim.fault_reason.is_empty())
		check("physical failure count "+str(spec[0]),run.events.size()==(0 if spec[0]=="light" else 1))
		observations.append({case=spec[0],tick=run.sim.tick,modes=Array(run.sim.modes),events=run.events.duplicate(true),
			loss_j=run.sim.continuous[4],continued_after_failure=run.events.is_empty() or absf(run.sim.state[RB.POS+2]-run.failure_down[0])>0.001})
		if spec[0]=="heavy":heavy=run
		else:run.sim.free()
	var source: Dictionary=heavy.events[0]
	check("raw accepted event has stable finite physical IDs",source.type=="gear_failure" and not source.event_id.is_empty()
		and source.generation_id=="drop-fixture" and source.tick>0 and not source.terminal)
	check("response explicitly limits qualification and timing",source.qualification=="experimental_unvalidated"
		and source.sampling=="accepted_boundary_only_not_interval_peak" and source.continuation=="authored_weaker_fixed_hub_compliance")
	check("strict contact v1 does not silently accept physical damage",not ContactEvents.validate_events([source],source.tick,{}))
	check("raw physical event is not a shared FlightEvent",not FlightEvent.valid(source))
	check("both shared type tags are reserved",FlightEvent.TYPES.has("COMPONENT_DAMAGE") and FlightEvent.TYPES.has("GEAR_FAILURE"))
	var profile: Dictionary={generation_id="event-audit",aircraft_id="synthetic",configuration_hash="fixture",landing_available=true}
	var placeholder:=FlightEvent.make(profile,"GEAR_FAILURE",source.tick,0,"","","")
	check("existing make only supplies endpoint unknown-damage placeholder",FlightEvent.valid(placeholder)
		and placeholder.evidence_coverage.has("damage_unobserved") and placeholder.component_ids.is_empty())
	check("existing measurements reject actual structural evidence",FlightEvent.make(profile,"GEAR_FAILURE",source.tick,0,"","","",{normal_load_n=source.normal_load_n}).is_empty())
	var detector:=Detector.new()
	detector.configure(profile)
	var detector_events: Array=[]
	for tick in range(1,49):
		detector_events.append_array(detector.observe({tick=tick,dt=1.0/240.0,valid=true,supported=true,ground_contact=true,
			intended_support=true,stop_support=true,controlled=true,clearance_ok=false,ground_speed_3d=0.0,angular_speed=0.0,
			incident=false,gear_up_contact=false,terminal=false,damage_events=[source] if tick==source.tick else []}))
	var seen_damage:=false
	for event: Dictionary in detector_events:
		seen_damage=seen_damage or (event.get("type")=="semantic" and event.event.type in ["COMPONENT_DAMAGE","GEAR_FAILURE"])
	check("existing detector does not consume unregistered source events",not seen_damage)
	var service:=Service.new()
	check("nonpersistent existing service opens",service.setup("",false))
	var publications: Array=[]
	service.flight_events_accepted.connect(func(batch):publications.append_array(batch))
	service._ingest([source])
	check("raw source does not bypass current classifier bus or invent M7",publications.is_empty() and service.data.records.is_empty())
	service.free()
	var checkpoint: Dictionary=heavy.sim.checkpoint()
	for i in 12:heavy.sim.step()
	var continued:=var_to_bytes(heavy.sim.checkpoint())
	var event_count: int=heavy.events.size()
	check("restore failed state clears transient physical events",heavy.sim.restore_checkpoint(checkpoint) and heavy.sim.last_events.is_empty())
	for i in 12:heavy.sim.step()
	check("failed-state replay is exact and emits no repeated failure",var_to_bytes(heavy.sim.checkpoint())==continued and heavy.events.size()==event_count)
	heavy.sim.free()
	var rewind:=_simulate(4.0,0.8,0)
	var healthy: Dictionary=rewind.sim.checkpoint()
	for i in 48:rewind.sim.step()
	var first_id: String=rewind.events[0].event_id
	var once:=var_to_bytes(rewind.sim.checkpoint())
	check("healthy checkpoint can replay the same source generation",rewind.sim.restore_checkpoint(healthy))
	for i in 48:rewind.sim.step()
	check("rewinding healthy physics repeats deterministic source ID",rewind.events.size()==2 and rewind.events[1].event_id==first_id
		and var_to_bytes(rewind.sim.checkpoint())==once)
	observations.append({case="healthy-rewind",raw_event_ids=[first_id,rewind.events[1].event_id],same_checkpoint=true,
		meaning="kernel source identity repeats; service checkpoint branch must suppress credit, not randomize source identity"})
	rewind.sim.free()
	var rollback:=_simulate(1.0,2.0,0)
	var old:=var_to_bytes(rollback.sim.checkpoint())
	rollback.sim.model.block_aux=func(_extra,_sampled):return PackedFloat64Array([NAN])
	rollback.sim.step()
	check("post-transition kernel refusal publishes no failure",rollback.sim.tick==0 and rollback.events.is_empty()
		and rollback.sim.last_events.is_empty() and rollback.sim.modes==PackedInt64Array([0,-1])
		and rollback.sim.continuous[4]==0.0 and not rollback.sim.fault_reason.is_empty())
	observations.append({case="rejected-final-projection",accepted_tick=rollback.sim.tick,event_count=rollback.events.size(),modes=Array(rollback.sim.modes),
		failure_loss_j=rollback.sim.continuous[4],fault=rollback.sim.fault_reason,original_checkpoint_bytes=old.size()})
	rollback.sim.free()
	_asymmetric_boundary()
	var file:=FileAccess.open(destination.path_join("observations.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(observations,"\t",true,true));file.close()
	print("Damage event bridge baseline: %d checks, %d failed; %s" % [checks,failed,destination])
	quit(1 if failed else 0)

func _asymmetric_boundary() -> void:
	# Existing fixture's asymmetric case is a direct physical boundary response,
	# not a full asymmetric dynamic kernel continuation qualification.
	var raw:=authored_damage.duplicate(true)
	var ids: PackedStringArray=bound.damage_profile.installed_support_ids
	raw.damage.components=[{component_id="left",support_ids=[ids[0]],source="Existing independent left fixture leg",normal_failure_force=_q(20.0,"N")},
		{component_id="other",support_ids=[ids[1],ids[2]],source="Existing other supports with unknown strength"}]
	raw.component_axes=[{component_id="left",positive_load_axis_body=_q([0.0,0.0,-1.0],"1")},
		{component_id="other",positive_load_axis_body=_q([0.0,0.0,-1.0],"1")}]
	var independent:=Response.prepare(raw,profile,model)
	check("existing asymmetric response binds",independent.ok)
	var result:=_transition(Damage.initial_state(independent.damage_profile),_body(),1,independent)
	check("asymmetric factual failure has one component and support binding",result.ok and result.events.size()==1
		and result.events[0].component_id=="left" and result.events[0].support_ids.size()==1 and result.modes==PackedInt64Array([1,1,0,-1]))
	observations.append({case="asymmetric-direct-boundary",kernel_committed=false,modes=Array(result.modes),events=result.events,
		normal_force_z_n=result.after_normal.loads[2],roll_moment_nm=result.after_normal.loads[3],meaning="physical direct boundary response only; no accepted dynamic publication claim"})
