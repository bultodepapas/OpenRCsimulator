## Original complete initial-condition tapes; no coefficient or quality changes.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-unloaded-policy/self_contained_test.gd"
func _energy(sim:Node)->float:
	var point:=_snapshot(_combined(sim),sim.time())
	var velocity_cm:=M.add(sim.state.slice(RB.VEL,RB.VEL+3),M.cross(sim.state.slice(RB.RATE),live.cg_body_m))
	return .5*live.mass_kg*M.dot(velocity_cm,velocity_cm)+Rotor._stage_energy(point.rotor_stage,point.rotor_stage.velocity)+point.potential_j
func _new_sim(initial:PackedFloat64Array)->Node:
	_bind()
	var sim:=super._new_sim(initial)
	sim.model.step_policy=func(state,at,h,f,k1):return Candidate.advance(state,at,h,f,k1,_sample_policy,_certificate,_options(),_gate,_policy)
	sim.model.state_layout_identity+="/normal-loss:"+binding.identity
	check("drop opt-in policy layout resets",sim.reset(initial.slice(0,RB.SIZE)))
	return sim
func _run_case(speed:float,ticks:int)->Dictionary:
	lift_ratio=0.0;brake_start=100.0
	var initial:=_initial(-.28,3.0,speed,0.0)
	var sim:=_new_sim(initial)
	var start_ms:=Time.get_ticks_msec()
	var initial_energy:float=_energy(sim)
	var maximum_compression:=0.0
	var seen:Array=[]
	var rebounded:=false
	sim.events_located.connect(func(_tick,events):
		for event:Dictionary in events:seen.append(event.type))
	for i in ticks:
		sim.step()
		if not sim.fault_reason.is_empty():break
		var point:=_snapshot(_combined(sim),sim.time())
		for contact:Dictionary in point.physical.ground.contacts:
			if contact.geometry_evaluated:maximum_compression=maxf(maximum_compression,-contact.gap_m)
		rebounded=rebounded or (sim.modes[1]==1 and sim.state[RB.VEL+2]<-.1)
		if sim.tick%30==0:print("DROP_PROGRESS speed=",speed," tick=",sim.tick," elapsed_ms=",Time.get_ticks_msec()-start_ms)
	var state:=_combined(sim)
	var refused:Dictionary={}
	if not sim.fault_reason.is_empty():refused=Candidate.advance(state,sim.time(),sim.dt(),_derivative,PackedFloat64Array(),_sample_policy,_certificate,_options(),_gate,_policy)
	var balance:float=_energy(sim)+sim.aux[0]+sim.aux[1]-sim.aux[2]-initial_energy
	var data:={speed=speed,target_ticks=ticks,accepted_ticks=sim.tick,fault=sim.fault_reason,state=state,aux=sim.aux,modes=sim.modes,
		initial_state=initial,initial_energy_j=initial_energy,mechanical_balance_j=balance,xpeak_m=maximum_compression,
		rebounded=rebounded,events=seen,elapsed_ms=Time.get_ticks_msec()-start_ms,refusal=refused,
		time_s=sim.time(),dt=sim.dt(),quality=quality,options=_options(),lift_start=lift_start,lift_duration=lift_duration,
		lift_ratio=lift_ratio,brake_start=brake_start,binding_identity=binding.identity}
	check("full original drop accepts every tick",sim.tick==ticks and sim.fault_reason.is_empty(),str({speed=speed,tick=sim.tick,fault=sim.fault_reason}))
	check("all three wheels touch/spin naturally",sim.aux[7]==3.0 and sim.continuous[1]>.1 and sim.continuous[2]>.1 and sim.continuous[3]>.1)
	check("normal rebound stays in original compression domain",seen.has("composition_touchdown") and rebounded and maximum_compression>.01 and maximum_compression<X_MAX)
	check("original independent complete mechanical work target",absf(balance)<2e-4,str(balance))
	check("original bounded raw path quality retained",sim.aux[8]<=16.0 and sim.aux[8]>=4.0 and sim.aux[6]<=1.0)
	var stem:="C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-unloaded-policy/drop-"+str(speed)
	var f:=FileAccess.open(stem+".bin",FileAccess.WRITE);f.store_buffer(var_to_bytes(data));f.close()
	f=FileAccess.open(stem+".json",FileAccess.WRITE);f.store_string(JSON.stringify(data,"\t",true,true));f.close()
	print("DROP_FINAL ",JSON.stringify(data,"",true,true))
	sim.free()
	return data
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	_run_case(.25,180)
	_run_case(1.2,180)
	print("Opt-in full drops: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
