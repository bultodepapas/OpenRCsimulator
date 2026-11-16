extends SceneTree
## Generic transport known answer: aux increases at 1/s; continuous integrates aux.
## The integral is t^2/2. No aircraft or actuator implementation supplies the oracle.
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const RK := preload("res://physics/integrator.gd")
const LAYOUT := "test-joint-interval-v1"
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func body() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0,0.0,-10.0),M.v3(0.0,0.0,0.0),M.q_identity(),M.v3(0.0,0.0,0.0))

func response(value: float) -> Dictionary:
	return {loads=PackedFloat64Array([0.0,0.0,0.0,0.0,0.0,0.0]),derivative=PackedFloat64Array([value]),rotor_momentum=M.v3(0.0,0.0,0.0)}

func toy(spy: Dictionary, with_policy:=true) -> Model:
	var v := Model.new()
	v.callback_protocol=Model.PROTOCOL_JOINT_INTERVAL
	v.state_layout_identity=LAYOUT
	v.input_size=1
	v.aux_size=1
	v.modes_size=1
	v.continuous_size=1
	var model_id := v.get_instance_id()
	v.pre_tick=func(a: PackedFloat64Array,input: PackedFloat64Array,dt: float) -> PackedFloat64Array:
		spy.samples=int(spy.get("samples",0))+1
		if spy.get("pre_aux",false):a[0]=99.0
		if spy.get("pre_input",false):input[0]=99.0
		return PackedFloat64Array([a[0]+input[0]*dt])
	v.stage_interval=func(b: PackedFloat64Array,c: PackedFloat64Array,t: float,x: Dictionary) -> Dictionary:
		spy.stages=int(spy.get("stages",0))+1
		var query_times: Array=spy.get("query_times",[])
		query_times.append(t)
		spy.query_times=query_times
		var seen: Array=spy.get("contexts",[])
		seen.append(x.duplicate(true))
		spy.contexts=seen
		spy.retained=x
		if spy.get("body",false):b[0]=99.0
		if spy.get("continuous",false):c[0]=99.0
		for key: String in ["before_aux","after_aux","inputs"]:
			if spy.get(key,false):x[key][0]=99.0
		for key: String in ["before_modes","after_modes"]:
			if spy.get(key,false):x[key][0]=99
		if spy.get("clock",false):x.time_s=99.0
		if spy.has("reenter_stage"):spy.reenter_stage.step()
		var fraction: float=0.0 if x.kind=="boundary" else (t-x.time_s)/x.dt
		return response(x.before_aux[0]+fraction*(x.after_aux[0]-x.before_aux[0]))
	if with_policy:
		v.step_policy_interval=func(s: PackedFloat64Array,t: float,dt: float,f: Callable,first: PackedFloat64Array,x: Dictionary) -> Variant:
			spy.policy_context=x.duplicate(true)
			# Repeated, reversed queries cannot resample controls or alter the outer interval.
			f.call(s,t+dt)
			f.call(s,t)
			f.call(s,t+dt/2.0)
			if spy.get("outside",false):f.call(s,t+2.0*dt)
			if spy.get("just_outside",false):f.call(s,t-5e-10)
			if spy.get("roundoff",false):f.call(s,t+dt+2.220446049250313e-16*absf(t+dt))
			if spy.get("transient_model",false):
				instance_from_id(model_id).identity.trap="changed before delegated derivative"
				f.call(s,t+dt/2.0)
				instance_from_id(model_id).identity.erase("trap")
			if spy.get("mutate_policy_context",false):x.after_aux[0]=99.0
			if spy.get("policy_state",false):s[0]=99.0
			if spy.has("reenter_policy"):
				spy.reenter_policy.step()
				f.call(s,t+dt/2.0)
			if spy.get("bad_policy",false):return null
			var out: PackedFloat64Array=RK.rk4_step_at(s,t,dt,f,first)
			if spy.get("late_event",false):return {state=out,events=[{type="late",time_s=t+2.0*dt}]}
			return out
	return v

func owner(v: Model) -> Sim:
	var s := Sim.new()
	s.set_physics_process(false)
	s.gravity=0.0
	s.inputs=PackedFloat64Array([1.0])
	s.aux=PackedFloat64Array([0.0])
	s.modes=PackedInt64Array([7])
	s.continuous=PackedFloat64Array([0.0])
	check("model installs",s.set_model(v))
	return s

func frame(s: Sim) -> PackedByteArray:
	return var_to_bytes([s.state,s.previous,s.continuous,s.aux,s.modes,s.tick,s.inputs,s.last_loads,s.last_events])

func legacy() -> Model:
	var v := Model.new()
	v.state_layout_identity=LAYOUT
	v.input_size=1
	v.aux_size=1
	v.modes_size=1
	v.continuous_size=1
	v.stage=func(_b: PackedFloat64Array,_c: PackedFloat64Array,_t: float) -> Dictionary:return response(0.0)
	return v

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	var spy := {}
	var v := toy(spy)
	check("explicit interval contract valid",Model.validate(v).ok)
	v.state_layout_identity=""
	check("interval requires layout",not Model.validate(v).ok)
	v.state_layout_identity=LAYOUT
	v.continuous_size=0
	check("interval requires continuous block",not Model.validate(v).ok)
	v.continuous_size=1
	v.stage=func(_b: PackedFloat64Array,_c: PackedFloat64Array,_t: float) -> Dictionary:return response(0.0)
	check("legacy stage cannot coexist",not Model.validate(v).ok)
	v.stage=Callable()
	v.step_policy=func(_s: PackedFloat64Array,_t: float,_dt: float,_f: Callable,_first: PackedFloat64Array) -> Variant:return null
	check("old policy cannot coexist",not Model.validate(v).ok)
	v.step_policy=Callable()
	v.events=[{type="stop",index=13,transition=func(s: PackedFloat64Array,_i: int) -> PackedFloat64Array:return s}]
	check("contextual policy excludes declared locator",not Model.validate(v).ok)
	v.events=[]
	v.callback_protocol=Model.PROTOCOL_LEGACY
	check("interval callbacks cannot hide in legacy model",not Model.validate(v).ok)
	v.callback_protocol=Model.PROTOCOL_FRAMED_SAMPLED
	check("interval callbacks cannot hide in framed v1",not Model.validate(v).ok)
	v.callback_protocol=Model.PROTOCOL_JOINT_INTERVAL
	var valid_policy := v.step_policy_interval
	v.step_policy_interval=Callable(self,"missing_interval_policy")
	check("invalid non-null policy refuses fallback",not Model.validate(v).ok)
	v.step_policy_interval=valid_policy
	v.rotor_momentum=Callable(self,"unused_legacy_rotor")
	check("interval stage owns rotor momentum",Model.validate(v).ok)
	var s := owner(v)
	check("reset evaluates boundary",s.reset(body()))
	var boundary: Dictionary=spy.contexts[0]
	check("boundary is detached, no advance",boundary.size()==9 and boundary.kind=="boundary" and boundary.dt==0.0 and boundary.before_aux==boundary.after_aux and boundary.before_modes==boundary.after_modes and int(spy.get("samples",0))==0)
	spy.contexts=[]
	s.step()
	var same := true
	for x: Dictionary in spy.contexts:same=same and var_to_bytes(x)==var_to_bytes(spy.policy_context)
	check("all repeated and reversed stages share interval",same and spy.contexts.size()==7)
	check("pre_tick advances exactly once",spy.samples==1 and s.aux[0]==s.dt())
	check("continuous known integral",s.fault_reason.is_empty() and absf(s.continuous[0]-0.5*s.dt()*s.dt())<1e-18)
	check("complete interval inputs and clock",spy.policy_context.kind=="interval" and spy.policy_context.before_aux[0]==0.0 and spy.policy_context.after_aux[0]==s.dt() and spy.policy_context.inputs==PackedFloat64Array([1.0]) and spy.policy_context.tick==0 and spy.policy_context.time_s==0.0 and spy.policy_context.dt==s.dt())
	spy.retained.before_aux[0]=99.0
	for _i in 9:s.step()
	check("retained stage copy cannot affect later ticks",s.fault_reason.is_empty() and s.tick==10 and absf(s.continuous[0]-0.5*pow(10.0*s.dt(),2.0))<1e-16)
	var cp := s.checkpoint()
	check("checkpoint pins new protocol",cp.format==Sim.ENDPOINT_CHECKPOINT_FORMAT and cp.callback_protocol==Model.PROTOCOL_JOINT_INTERVAL and s.can_restore_checkpoint(cp))
	var restored_spy := {}
	var restored := owner(toy(restored_spy))
	check("restore works without reset or sampling",restored.restore_checkpoint(cp) and int(restored_spy.get("samples",0))==0)
	s.step()
	restored.step()
	check("restored nonzero tick follows exact same next frame",s.fault_reason.is_empty() and restored.fault_reason.is_empty() and frame(s)==frame(restored) and restored_spy.policy_context.tick==10)
	var wrong := cp.duplicate(true)
	wrong.callback_protocol=Model.PROTOCOL_FRAMED_SAMPLED
	check("ordinary restore rejects different protocol",not restored.can_restore_checkpoint(wrong))
	wrong.erase("callback_protocol")
	check("ordinary restore rejects missing protocol",not restored.can_restore_checkpoint(wrong))
	s.free()
	restored.free()
	spy={}
	s=owner(toy(spy))
	check("invalid policy fixture resets",s.reset(body()))
	var saved := frame(s)
	s.model.step_policy_interval=Callable(self,"missing_interval_policy")
	s.step()
	check("invalid policy cannot silently become RK4",not s.fault_reason.is_empty() and frame(s)==saved and int(spy.get("samples",0))==0)
	s.free()
	# Guard every new callback input; failures preserve the complete accepted frame/events.
	for fault: String in ["pre_aux","pre_input","body","continuous","before_aux","after_aux","inputs","before_modes","after_modes","clock","mutate_policy_context","policy_state","outside","just_outside","transient_model","bad_policy","late_event","reenter_stage","reenter_policy"]:
		spy={}
		s=owner(toy(spy))
		check("fault fixture resets",s.reset(body()))
		var before := frame(s)
		spy[fault]=s if fault.begins_with("reenter") else true
		s.step()
		check("refused interval is atomic: "+fault,not s.fault_reason.is_empty() and frame(s)==before and not s.model.identity.has("trap"))
		s.free()
	spy={roundoff=true}
	s=owner(toy(spy))
	check("roundoff fixture resets",s.reset(body()))
	s.step()
	check("represented boundary roundoff is clamped",s.fault_reason.is_empty() and spy.query_times.min()==0.0 and spy.query_times.max()==s.dt() and absf(s.continuous[0]-0.5*s.dt()*s.dt())<1e-18)
	s.free()
	# Context must sample after the observer input boundary.
	spy={}
	s=owner(toy(spy))
	check("input boundary fixture resets",s.reset(body()))
	s.before_step.connect(func(_tick: int) -> void:s.inputs[0]=2.0)
	s.step()
	check("input observer snapshot precedes pre_tick",s.fault_reason.is_empty() and spy.policy_context.inputs[0]==2.0 and s.aux[0]==2.0*s.dt())
	s.free()
	# Substeps receive read-only copies of k1, including nested arrays.
	for mutate: bool in [false,true]:
		spy={}
		v=toy(spy,false)
		v.substeps_joint=func(_b: PackedFloat64Array,_c: PackedFloat64Array,_t: float,joint: Dictionary) -> int:
			if mutate:joint.loads[0]=99.0
			return 2
		s=owner(v)
		check("substep fixture resets",s.reset(body()))
		var before := frame(s)
		s.step()
		check("substep context guarded: "+str(mutate),(not s.fault_reason.is_empty() and frame(s)==before) if mutate else (s.fault_reason.is_empty() and spy.samples==1 and absf(s.continuous[0]-0.5*s.dt()*s.dt())<1e-18))
		s.free()
	# Protocol changes cannot reinterpret an already accepted layout in either direction.
	for start_interval: bool in [false,true]:
		s=owner(toy({}) if start_interval else legacy())
		check("protocol fixture resets",s.reset(body()))
		var before := frame(s)
		check("alternate model installs",s.set_model(legacy() if start_interval else toy({})))
		check("checkpoint refuses changed protocol",s.checkpoint().is_empty())
		s.step()
		check("step refuses changed protocol",not s.fault_reason.is_empty() and frame(s)==before)
		s.free()
	spy={}
	s=owner(toy(spy))
	check("signal protocol fixture resets",s.reset(body()))
	var before := frame(s)
	s.before_step.connect(func(_tick: int) -> void:s.model.callback_protocol=Model.PROTOCOL_LEGACY)
	s.step()
	check("protocol rechecked after input observer",not s.fault_reason.is_empty() and frame(s)==before and int(spy.get("samples",0))==0)
	s.free()
	for change_clock: bool in [false,true]:
		spy={}
		s=owner(toy(spy))
		check("observer mutation fixture resets",s.reset(body()))
		var kept := frame(s)
		s.before_step.connect(func(_tick: int) -> void:
			if change_clock:s.tick+=1
			else:s.state[0]=99.0)
		s.step()
		check("observer cannot change protected clock/frame",not s.fault_reason.is_empty() and frame(s)==kept and int(spy.get("samples",0))==0)
		s.free()
	spy={}
	s=owner(toy(spy))
	check("observer reentry fixture resets",s.reset(body()))
	var kept := frame(s)
	spy.published=0
	spy.attempted=false
	s.stepped.connect(func(_tick: int,_t: float,_b: PackedFloat64Array,_l: PackedFloat64Array,_i: PackedFloat64Array,_a: PackedFloat64Array) -> void:spy.published+=1)
	s.before_step.connect(func(_tick: int) -> void:
		spy.checkpoint_read=not s.checkpoint().is_empty()
		if not spy.attempted:
			spy.attempted=true
			s.step())
	s.step()
	check("observer reentry cannot publish inner tick",not s.fault_reason.is_empty() and frame(s)==kept and spy.published==0 and spy.checkpoint_read and int(spy.get("samples",0))==0)
	s.free()
	for pause_edit: bool in [false,true]:
		spy={pauses=0,faults=0}
		s=owner(toy(spy))
		check("observer publication fixture resets",s.reset(body()))
		var saved_frame := frame(s)
		s.paused_changed.connect(func(_p: bool) -> void:spy.pauses+=1)
		s.faulted.connect(func(_reason: String) -> void:spy.faults+=1)
		s.before_step.connect(func(_tick: int) -> void:
			if pause_edit:s.set_paused(true)
			else:s.interpolated(NAN))
		s.step()
		check("observer publishes only final refusal",not s.fault_reason.is_empty() and frame(s)==saved_frame and spy.pauses==1 and spy.faults==1)
		s.free()
	for reenter: bool in [false,true]:
		spy={}
		v=toy(spy,false)
		v.stage_interval=func(_b: PackedFloat64Array,c: PackedFloat64Array,_t: float,_x: Dictionary) -> Dictionary:return response(-1.0 if c[0]!=0.0 else 0.0)
		v.events=[{type="located",index=13,transition=func(a: PackedFloat64Array,index: int) -> PackedFloat64Array:
			if reenter:spy.sim.step()
			var out := a.duplicate()
			out[index]=0.0
			return out}]
		s=owner(v)
		spy.sim=s
		s.continuous[0]=0.5/240.0
		check("declared event fixture resets",s.reset(body()))
		var event_frame := frame(s)
		s.step()
		check("declared transition is guarded: "+str(reenter),(not s.fault_reason.is_empty() and frame(s)==event_frame) if reenter else (s.fault_reason.is_empty() and s.last_events.size()==1 and absf(s.last_events[0].time_s-0.5/240.0)<1e-9 and s.continuous[0]==0.0))
		s.free()
	print("JOINT_INTERVAL_TEST %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
