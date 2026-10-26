## Accepted synthetic physical failures through the existing single classifier/service bus.
extends "res://tests/test_aircraft_ground_damage.gd"
const Event := preload("res://statistics/flight_event.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Detector := preload("res://statistics/detector.gd")
const Service := preload("res://statistics/service.gd")
const LegacySession := preload("res://sim/flight_session.gd")
const LEGACY_EVENT_SHA := "146fb741db76bce8f3e5db66a6551d88b4ff8722a382e662e1ba11d1fde39830"
const LEGACY_SAMPLE_SHA := "15622bd38ecd3f7bb101b0aa8d5d0c1e220a5da89836b2ab47c04072cb6488f1"
const Rules := preload("res://statistics/rules.gd")

class ObserverOwner:
	extends Node
	const Physical := preload("res://physics/aircraft_ground_damage.gd")
	var sim: Node
	var statistics_generation := "drop-fixture"
	var binding: Dictionary
	var empty_packet: Dictionary
	func damage_observation() -> Dictionary:
		# One binding validation on attach and on actual transition batches only.
		# No force/geometry evaluation or rebuilding on ordinary accepted samples.
		if empty_packet.is_empty() or not sim.last_events.is_empty():
			var packet:=Physical.accepted_observation(binding,sim.modes,sim.continuous.slice(4),sim.last_events,
				{tick=sim.tick,time_s=sim.time(),dt=sim.dt()},statistics_generation)
			if packet.is_empty():return {}
			if sim.last_events.is_empty():empty_packet=packet
			return packet
		var value:=empty_packet.duplicate(true)
		value.tick=sim.tick
		return value

var good_packet: Dictionary
var semantic_profile: Dictionary
var output := ""
var observations: Array[Dictionary] = []

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	output=ProjectSettings.globalize_path("res://../tmp/damage-flight-events-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output)
	_fixture();_bind()
	if failed:quit(1);return
	var initial:=Damage.initial_state(bound.damage_profile)
	var transition:=_transition(initial,_body())
	good_packet=Response.accepted_observation(bound,transition.modes,transition.losses,transition.events,_clock(),"response-fixture")
	check("physical response projects one strict fact",not good_packet.is_empty() and good_packet.events.size()==1)
	semantic_profile={generation_id="activity",activity_id="activity",aircraft_id="synthetic",configuration_hash="fixture",
		landing_available=false,damage_source_generation="response-fixture",damage_response_identity=bound.identity}
	_contracts()
	_classifier()
	_invalid_edges()
	_components()
	_absent_owner()
	_service_bounds()
	_kernel_bridge()
	_asymmetric_kernel_boundary()
	var evidence_file:=FileAccess.open(output.path_join("accepted-batches.json"),FileAccess.WRITE)
	evidence_file.store_string(JSON.stringify(observations,"\t",true,true));evidence_file.close()
	print("Damage flight events: %d checks, %d failed; %s" % [checks,failed,output])
	quit(1 if failed else 0)

func sample(tick: int,packet: Dictionary={},extra: Dictionary={}) -> Dictionary:
	# Technical fixture has no reviewed landing geometry/credit. The accepted
	# failure itself proves physical normal support at that boundary.
	var value: Dictionary={tick=tick,dt=0.01,valid=true,supported=not packet.is_empty(),ground_contact=not packet.is_empty(),
		intended_support=false,stop_support=false,controlled=false,clearance_ok=false,ground_speed_3d=1.0,
		angular_speed=0.0,incident=false,gear_up_contact=false,terminal=false}
	if not packet.is_empty():value.component_failure_observation=packet
	value.merge(extra,true)
	return value

func semantic(events: Array,kind: String="") -> Array:
	var values:=[]
	for item: Dictionary in events:
		if item.get("type")=="semantic" and (kind.is_empty() or item.event.type==kind):values.append(item.event)
	return values

func count(events: Array,kind: String) -> int:
	var result:=0
	for event: Dictionary in events:
		if event.get("type")==kind:result+=1
	return result

func _contracts() -> void:
	var initial:=Damage.initial_state(bound.damage_profile)
	var result:=_transition(initial,_body())
	var source: Dictionary=result.events[0]
	for key: String in source:
		var bad:=source.duplicate(true);bad.erase(key)
		check("source required key "+key,Response.accepted_observation(bound,result.modes,result.losses,[bad],_clock(),"response-fixture").is_empty())
	for key: String in ["type","component_id","law","profile_identity","response_identity","qualification","criterion","sampling","continuation","tick","time_s","normal_load_n","normal_failure_force_n","potential_before_j","transition_loss_j","terminal","support_ids"]:
		var bad:=source.duplicate(true);bad[key]=[]
		check("source primitive guard "+key,Response.accepted_observation(bound,result.modes,result.losses,[bad],_clock(),"response-fixture").is_empty())
	for kind: String in ["generation","binding","loss","load","capacity","clock","mode"]:
		var bad:=source.duplicate(true)
		var modes: PackedInt64Array=result.modes.duplicate()
		match kind:
			"generation":bad.generation_id="stale"
			"binding":bad.response_identity="0".repeat(64)
			"loss":bad.transition_loss_j+=1.0
			"load":bad.normal_load_n=bad.normal_failure_force_n
			"capacity":bad.normal_failure_force_n*=0.5
			"clock":bad.tick=2
			"mode":modes=initial.modes
		check("source rejects "+kind,Response.accepted_observation(bound,modes,result.losses,[bad],_clock(),"response-fixture").is_empty())
	check("source batch duplicate is atomic",Response.accepted_observation(bound,result.modes,result.losses,[source,source],_clock(),"response-fixture").is_empty())
	check("empty initial observation is available",not Response.accepted_observation(bound,initial.modes,initial.losses,[],{tick=0,time_s=0.0,dt=0.01},"response-fixture").is_empty())
	for key: String in good_packet:
		var bad:=good_packet.duplicate(true);bad.erase(key)
		check("packet required key "+key,not Event.valid_damage_observation(bad,1,"response-fixture",bound.identity,0.01))
	for key: String in ["schema","version","tick","generation_id","identity","available","events","reason"]:
		var bad:=good_packet.duplicate(true);bad[key]=null
		check("packet primitive "+key,not Event.valid_damage_observation(bad,1,"response-fixture",bound.identity,0.01))
	for kind: String in ["COMPONENT_DAMAGE","GEAR_FAILURE"]:
		var event:=Event.make_damage(semantic_profile,kind,good_packet.events[0],0,"","","accident")
		check("strict v2 packet "+kind,Event.valid(event) and event.version==2 and not event.terminal
			and event.component_ids==["assembly"] and not event.evidence_coverage.has("damage_unobserved"))
		for key: String in Event.DAMAGE_EVIDENCE:
			var bad:=event.duplicate(true);bad.physical_evidence[key]=[]
			check("v2 evidence primitive "+key,not Event.valid(bad))
		for key: String in Event.DAMAGE_MEASUREMENTS:
			var bad:=event.duplicate(true);bad.measurements[key]=NAN
			check("v2 finite measurement "+key,not Event.valid(bad))
		for key: String in ["accepted_tick","revision","terminal","component_ids","cause","physical_evidence","measurements"]:
			var bad:=event.duplicate(true);bad[key]=[]
			check("v2 outer primitive "+key,not Event.valid(bad))
		var bad:=event.duplicate(true);bad.measurements.speed_mps=2.0
		check("v2 unknown measurements fail closed",not Event.valid(bad))
		bad=event.duplicate(true);bad.measurements.transition_loss_j=-1.0
		check("v2 negative heat fails closed",not Event.valid(bad))
		bad=event.duplicate(true);bad.component_ids=["invented"]
		check("v2 source ID binds component",not Event.valid(bad))
		bad=event.duplicate(true);bad.event_id="tampered"
		check("v2 canonical event identity required",not Event.valid(bad))
		bad=event.duplicate(true);bad.accident_id=""
		check("v2 always annotates an existing accident",not Event.valid(bad))
		bad=event.duplicate(true);bad.cause.classification="mechanical_failure_confirmed"
		check("v2 does not invent root cause",not Event.valid(bad))
		bad=event.duplicate(true);bad.material_id="maintained_turf"
		check("v2 cannot invent unobserved material",not Event.valid(bad))
	var current:=Event.make({generation_id="frozen"},"TOUCHDOWN",3,0,"flight","episode","")
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(current))
	check("v1 frozen historical payload bytes preserved",hash.finish().hex_encode()==LEGACY_EVENT_SHA)

func _classifier() -> void:
	var d:=Detector.new();d.configure(semantic_profile)
	var events:=d.observe(sample(1,good_packet))
	check("one qualified failure is one nonterminal accident",count(events,"crash")==1 and semantic(events,"CRASH").size()==1
		and semantic(events,"COMPONENT_DAMAGE").size()==1 and semantic(events,"GEAR_FAILURE").size()==1)
	var crash: Dictionary=semantic(events,"CRASH")[0]
	check("qualified CRASH reports observed failure without causal certainty",not crash.evidence_coverage.has("damage_unobserved")
		and crash.evidence_coverage.has("component_failure_observed") and crash.cause.classification=="unknown"
		and crash.cause.evidence_ids==[good_packet.events[0].physical_evidence.source_event_id])
	var gear: Dictionary=semantic(events,"GEAR_FAILURE")[0]
	check("factual pair shares source and accident",gear.physical_evidence==semantic(events,"COMPONENT_DAMAGE")[0].physical_evidence
		and gear.accident_id==semantic(events,"CRASH")[0].accident_id and not gear.accident_id.is_empty())
	check("duplicate clock is silent",d.observe(sample(1,good_packet)).is_empty())
	var before:=var_to_bytes(d.snapshot())
	var malformed:=good_packet.duplicate(true);malformed.tick=2
	check("stale source rejects atomically",d.observe(sample(2,malformed)).is_empty() and var_to_bytes(d.snapshot())==before)
	var saved:=d.snapshot();d.observe(sample(2));var after:=var_to_bytes(d.snapshot())
	check("existing snapshot restore preserves damage accident latch",d.restore(saved) and d.observe(sample(1,good_packet)).is_empty())
	d.observe(sample(2));check("snapshot continuation exact",var_to_bytes(d.snapshot())==after)
	var terminal:=d.observe(sample(2,{}, {terminal=true}))
	check("terminal escalation adds no M7 or physical pair",count(terminal,"crash")==0 and semantic(terminal,"CRASH").size()==1
		and semantic(terminal,"CRASH")[0].revision==1 and semantic(terminal,"GEAR_FAILURE").is_empty())
	check("new M7 coverage explicitly versioned",Rules.VERSION=="flight-statistics-rules-v3")
	var broken:=Detector.new();broken.configure(semantic_profile)
	var mixed:=good_packet.duplicate(true);mixed.events.append(mixed.events[0].duplicate(true))
	check("duplicate source batch cannot partially count",broken.observe(sample(1,mixed)).is_empty() and broken.snapshot().last_tick==0)
	for version: int in [1,2,3]:
		var legacy:=Detector.new();legacy.configure({generation_id="historical",landing_available=false})
		var state:=legacy.snapshot();state.version=version
		check("historical snapshot remains readable without fabricated failure "+str(version),legacy.restore(state)
			and not state.profile.has("damage_response_identity") and semantic(legacy.observe(sample(1)),"GEAR_FAILURE").is_empty())
	var malformed_binding:=saved.duplicate(true);malformed_binding.profile.damage_response_identity=[]
	var restored:=Detector.new();restored.configure(semantic_profile)
	var original:=var_to_bytes(restored.snapshot())
	check("malformed persisted optional binding rejects atomically",not restored.restore(malformed_binding) and original==var_to_bytes(restored.snapshot()))
	var exhausted:=Detector.new();exhausted.configure(semantic_profile);exhausted._semantic_sequence=9007199254740991
	original=var_to_bytes(exhausted.snapshot())
	check("pair sequence budget rejects before accident/M7",exhausted.observe(sample(1,good_packet)).is_empty() and original==var_to_bytes(exhausted.snapshot()))
	for tick: Variant in [1.5,NAN,INF,[]]:
		var strict:=Detector.new();strict.configure(semantic_profile)
		var before_tick:=var_to_bytes(strict.snapshot())
		var value:=sample(1,good_packet);value.tick=tick
		check("physical producer tick must be finite integral",strict.observe(value).is_empty() and before_tick==var_to_bytes(strict.snapshot()))

func _invalid_edges() -> void:
	for kind: String in ["invalid","oversize_dt","continuity"]:
		var d:=Detector.new();d.configure(semantic_profile)
		var packet:=good_packet.duplicate(true)
		var value:=sample(1,packet,{terminal=true})
		if kind=="invalid":value.valid=false
		elif kind=="oversize_dt":
			packet.events[0].measurements.sample_interval_s=0.3
			value.dt=0.3
		else:
			d.observe(sample(1,{}, {valid=false}))
			var result:=_transition(Damage.initial_state(bound.damage_profile),_body(),2)
			packet=Response.accepted_observation(bound,result.modes,result.losses,result.events,_clock(2),"response-fixture")
			value=sample(2,packet,{terminal=true})
		var events:=d.observe(value)
		var summaries:=false
		for event: Dictionary in events:summaries=summaries or event.has("damage_summary") or event.get("kind")=="gear_failure"
		check("unaccepted physical edge cannot leak attribution "+kind,not summaries and semantic(events,"GEAR_FAILURE").is_empty()
			and semantic(events,"COMPONENT_DAMAGE").is_empty() and count(events,"crash")==1)

func independent_binding(other_limit: float) -> Dictionary:
	var raw:=authored_damage.duplicate(true)
	var ids: PackedStringArray=bound.damage_profile.installed_support_ids
	raw.damage.components=[{component_id="left",support_ids=[ids[0]],source="Synthetic left leg",normal_failure_force=_q(20.0,"N")},
		{component_id="other",support_ids=[ids[1],ids[2]],source="Synthetic other legs",normal_failure_force=_q(other_limit,"N")}]
	raw.component_axes=[{component_id="left",positive_load_axis_body=_q([0.0,0.0,-1.0],"1")},
		{component_id="other",positive_load_axis_body=_q([0.0,0.0,-1.0],"1")}]
	return Response.prepare(raw,profile,model)

func _components() -> void:
	var binding:=independent_binding(1000.0)
	var first:=_transition(Damage.initial_state(binding.damage_profile),_body(),1,binding)
	var packet:=Response.accepted_observation(binding,first.modes,first.losses,first.events,_clock(),"response-fixture")
	var p:=semantic_profile.duplicate(true);p.damage_response_identity=binding.identity
	var d:=Detector.new();d.configure(p)
	var events:=d.observe(sample(1,packet))
	var accident: String=semantic(events,"CRASH")[0].accident_id
	var second:=_transition({modes=first.modes,losses=first.losses},_body(0.4),2,binding)
	packet=Response.accepted_observation(binding,second.modes,second.losses,second.events,_clock(2),"response-fixture")
	events=d.observe(sample(2,packet))
	check("later new component emits pair in existing accident",semantic(events,"GEAR_FAILURE").size()==1
		and semantic(events,"COMPONENT_DAMAGE").size()==1 and semantic(events,"CRASH").is_empty()
		and count(events,"crash")==0 and semantic(events,"GEAR_FAILURE")[0].accident_id==accident)
	binding=independent_binding(50.0)
	var together:=_transition(Damage.initial_state(binding.damage_profile),_body(),1,binding)
	packet=Response.accepted_observation(binding,together.modes,together.losses,together.events,_clock(),"response-fixture")
	p.damage_response_identity=binding.identity;d=Detector.new();d.configure(p)
	events=d.observe(sample(1,packet))
	check("simultaneous components share one CRASH and M7",semantic(events,"GEAR_FAILURE").size()==2
		and semantic(events,"COMPONENT_DAMAGE").size()==2 and semantic(events,"CRASH").size()==1 and count(events,"crash")==1)
	check("component order and semantic identities deterministic",semantic(events,"GEAR_FAILURE")[0].component_ids==["left"]
		and semantic(events,"GEAR_FAILURE")[1].component_ids==["other"]
		and semantic(events,"GEAR_FAILURE")[0].event_id!=semantic(events,"GEAR_FAILURE")[1].event_id)

func _absent_owner() -> void:
	var session:=LegacySession.new();session.input_enabled=false;session.setup()
	var before:=var_to_bytes(session.checkpoint())
	var adapter:=Adapter.new();adapter.configure(session,"jensen-das-ugly-stik-60",func(_value):pass)
	var value:=adapter.sample()
	check("absent producer preserves sample shape and physics",not value.has("component_failure_observation")
		and not adapter.profile.has("damage_response_identity") and before==var_to_bytes(session.checkpoint()))
	var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(var_to_bytes(value))
	check("absent producer sample matches frozen pre-change bytes",h.finish().hex_encode()==LEGACY_SAMPLE_SHA)
	session.free()

func service_for(p: Dictionary) -> Node:
	var service:=Service.new();service.setup("",false);service._ensure_session()
	service._generation=p.generation_id;service._aircraft_id="synthetic"
	service.detector=Detector.new();service.detector.configure(p)
	return service

func _service_bounds() -> void:
	var service:=service_for(semantic_profile)
	var bus:=[]
	service.flight_events_accepted.connect(func(batch):bus.append_array(batch))
	service._observe(sample(1,good_packet))
	check("one canonical bus and one M7 record",bus.size()==3 and service.data.records.size()==1 and service.data.records[0].kind=="crash")
	check("ground-start first failure retains bounded evidence",service.data.records[0].metadata.component_damage.size()==1
		and service.data.records[0].metadata.component_damage[0].component_id=="assembly")
	check("bus recursively frozen",bus[0].is_read_only() and bus[1].physical_evidence.is_read_only()
		and bus[1].measurements.is_read_only() and bus[1].contact_ids.is_read_only())
	service._lifecycle({success=true,operation_id=1,cause="checkpoint_restore"})
	var records:=var_to_bytes(service.data.records);var count_before:=bus.size()
	service._observe(sample(2,good_packet))
	check("checkpoint experiment remains noncredit/silent",service._branch and records==var_to_bytes(service.data.records) and bus.size()==count_before)
	service.free()
	service=service_for(semantic_profile)
	service._active_record={metadata={events=[]}}
	for i in 128:service._active_record.metadata.events.append({type="fixture"})
	bus=[];service.flight_events_accepted.connect(func(batch):bus.append_array(batch))
	service._observe(sample(1,good_packet))
	check("timeline cap never truncates subscriber packet",service._active_record.metadata.events.size()==128
		and service._active_record.metadata.events_omitted>0 and bus.size()==3)
	service.free()
	service=service_for(semantic_profile)
	var record: Dictionary=good_packet.events[0]
	var wrong:=record.duplicate(true);wrong.measurements.transition_loss_j=-1.0
	var metadata: Dictionary={}
	service._copy_damage_summary(metadata,[record,wrong])
	check("first summary validates all records before appending",metadata.is_empty())
	metadata={padding="x".repeat(65000)}
	service._copy_damage_summary(metadata,[record])
	check("first summary obeys metadata byte budget",metadata.component_damage.is_empty() and metadata.component_damage_omitted==1
		and var_to_bytes(metadata).size()<=64*1024)
	service.free()

func _kernel_bridge() -> void:
	for spec: Array in [["light",1.0,0.8],["heavy",4.0,0.8],["hard",1.0,2.0]]:
		var run:=_simulate(spec[1],spec[2],0)
		var owner:=ObserverOwner.new();owner.sim=run.sim;owner.binding=bound
		var adapter:=Adapter.new();adapter.session=owner;adapter.profile={generation_id="kernel-"+str(spec[0]),landing_available=false}
		adapter._configure_damage_observation()
		check("fixture observer binds current generation",adapter.profile.get("damage_response_identity")==bound.identity)
		var service:=service_for(adapter.profile)
		var bus:=[];service.flight_events_accepted.connect(func(batch):bus.append_array(batch))
		var core: Node=run.sim
		core.stepped.connect(func(tick,_t,_body,_loads,_inputs,_aux):
			var packet:=adapter._damage_observation()
			var value:=sample(tick,packet if not packet.is_empty() and not packet.events.is_empty() else {})
			value.dt=core.dt()
			service._observe(value))
		var healthy: Dictionary=core.checkpoint()
		for i in 48:core.step()
		var expected:=0 if spec[0]=="light" else 1
		check("actual kernel to shared bus "+str(spec[0]),semantic_count(bus,"GEAR_FAILURE")==expected and semantic_count(bus,"COMPONENT_DAMAGE")==expected
			and semantic_count(bus,"CRASH")==expected and service.data.records.size()==expected and core.tick==48 and core.fault_reason.is_empty())
		check("kernel and observer did not stop failed body "+str(spec[0]),not core.paused and (expected==0 or absf(core.state[RB.POS+2]-run.failure_down[0])>0.001))
		if expected>0:
			var shared: Dictionary=bus.filter(func(e):return e.type=="GEAR_FAILURE")[0]
			check("actual source identity and loss preserved "+str(spec[0]),shared.physical_evidence.source_event_id==run.events[0].event_id
				and shared.accepted_tick==run.events[0].tick and shared.measurements.transition_loss_j==run.events[0].transition_loss_j)
		observations.append({scenario=spec[0],accepted_tick=core.tick,source_events=run.events.duplicate(true),shared_events=bus.duplicate(true),
			modes=Array(core.modes),qualification="synthetic_symmetric_kernel_fixture_not_stock_activation"})
		if spec[0]=="heavy":
			var published:=var_to_bytes(bus);var recorded:=var_to_bytes(service.data.records)
			check("actual healthy rewind accepted",core.restore_checkpoint(healthy))
			service._lifecycle({success=true,operation_id=1,cause="checkpoint_restore"})
			for i in 48:core.step()
			check("actual repeated source ID remains noncredit after restore",run.events.size()==2 and run.events[0].event_id==run.events[1].event_id
				and var_to_bytes(bus)==published and var_to_bytes(service.data.records)==recorded)
		service.free();owner.free();core.free()
	var run:=_simulate(1.0,2.0,0)
	var owner:=ObserverOwner.new();owner.sim=run.sim;owner.binding=bound
	var adapter:=Adapter.new();adapter.session=owner;adapter.profile={generation_id="rollback",landing_available=false};adapter._configure_damage_observation()
	var service:=service_for(adapter.profile)
	var bus:=[];service.flight_events_accepted.connect(func(batch):bus.append_array(batch))
	var core: Node=run.sim
	core.stepped.connect(func(tick,_t,_b,_l,_i,_a):service._observe(sample(tick,adapter._damage_observation())))
	core.model.block_aux=func(_v,_a):return PackedFloat64Array([NAN])
	core.step()
	check("rejected final projection publishes no shared damage or M7",core.tick==0 and bus.is_empty() and service.data.records.is_empty()
		and run.events.is_empty() and core.modes==PackedInt64Array([0,-1]))
	service.free();owner.free();core.free()

func _asymmetric_kernel_boundary() -> void:
	var original_binding:=bound
	bound=independent_binding(1000.0)
	var run:=_simulate(1.0,0.0,0)
	var core: Node=run.sim
	check("asymmetric compressed initial state installs",core.reset(_body()))
	var owner:=ObserverOwner.new();owner.sim=core;owner.binding=bound
	var adapter:=Adapter.new();adapter.session=owner;adapter.profile={generation_id="asymmetric",landing_available=false};adapter._configure_damage_observation()
	var service:=service_for(adapter.profile)
	var bus:=[];service.flight_events_accepted.connect(func(batch):bus.append_array(batch))
	core.stepped.connect(func(tick,_t,_b,_l,_i,_a):
		var value:=sample(tick,adapter._damage_observation());value.dt=core.dt();service._observe(value))
	core.step()
	check("first asymmetric physical boundary reaches shared owner",core.tick==1 and core.modes==PackedInt64Array([1,1,0,-1])
		and semantic_count(bus,"GEAR_FAILURE")==1 and semantic_count(bus,"CRASH")==1)
	var count_before:=bus.size();core.step()
	check("unqualified rolled continuation refuses without new events",core.tick==1 and not core.fault_reason.is_empty() and bus.size()==count_before)
	observations.append({scenario="asymmetric_first_boundary",accepted_tick=core.tick,source_events=run.events.duplicate(true),shared_events=bus.duplicate(true),
		modes=Array(core.modes),qualification="first_boundary_only_rolled_continuation_refused",continuation_fault=core.fault_reason})
	service.free();owner.free();core.free();bound=original_binding

func semantic_count(values: Array,kind: String) -> int:
	var total:=0
	for value: Dictionary in values:
		if value.type==kind:total+=1
	return total
