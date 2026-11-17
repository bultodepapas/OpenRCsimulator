extends SceneTree
## Independent clock/integral oracles. No aircraft/compiler supplies expected values.
const Sim := preload("res://sim/simulation.gd")
const Model := preload("res://sim/vehicle_model.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const RK := preload("res://physics/integrator.gd")
const Event := preload("res://physics/event_step.gd")
const Step := preload("res://sim/electric_contact_step.gd")
const Law := preload("res://physics/slew_trajectory.gd")
var checks := 0
var failures := 0

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL local interval: ",label)

func body() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0,0.0,-10.0),M.v3(0.0,0.0,0.0),M.q_identity(),M.v3(0.0,0.0,0.0))

func _initialize() -> void:
	Engine.physics_ticks_per_second=240
	var h: float="9a9999999999793c".hex_decode().to_float64_array()[0]
	check("counterexample really collapses on absolute time",0.6+h==0.6)
	check("short local RK stages are distinct",Event.stage_clock_resolved(0.0,h))
	var spy := {}
	var v:=Model.new()
	v.callback_protocol=Model.PROTOCOL_JOINT_INTERVAL_LOCAL
	v.state_layout_identity="test-local-clock-body13-extra1"
	v.input_size=1
	v.aux_size=1
	v.modes_size=0
	v.continuous_size=1
	v.pre_tick=func(a: PackedFloat64Array,_i: PackedFloat64Array,_dt: float) -> PackedFloat64Array:return a
	v.stage_interval=func(_b: PackedFloat64Array,_c: PackedFloat64Array,offset: float,x: Dictionary,_piece_origin: float,_piece_end: float) -> Dictionary:
		spy.origin=x.time_s
		if x.kind=="boundary":spy.boundary_offset=offset
		return {loads=PackedFloat64Array([0.0,0.0,0.0,0.0,0.0,0.0]),
			derivative=PackedFloat64Array([2.0*offset/(h*h)]),rotor_momentum=M.v3(0.0,0.0,0.0)}
	v.step_policy_interval=func(s: PackedFloat64Array,at: float,dt: float,f: Callable,first: PackedFloat64Array,x: Dictionary) -> Variant:
		spy.policy_at=at
		var tiny:=RK.rk4_step_at(s,at,h,f,first)
		spy.tiny_integral=tiny[13]
		if spy.get("outside",false):f.call(s,-h)
		if spy.get("mutation",false):x.time_s=99.0
		return RK.rk4_step_at(tiny,h,dt-h,f)
	check("local model contract admitted",Model.validate(v).ok)
	var saved_policy: Callable=v.step_policy_interval
	v.step_policy_interval=Callable()
	check("local model requires an owning policy",not Model.validate(v).ok)
	v.step_policy_interval=saved_policy
	var s:=Sim.new()
	s.set_physics_process(false)
	s.gravity=0.0
	s.inputs=PackedFloat64Array([0.0])
	s.aux=PackedFloat64Array([0.0])
	s.continuous=PackedFloat64Array([0.0])
	check("local model installs",s.set_model(v))
	check("local boundary reset",s.reset(body()) and spy.boundary_offset==0.0)
	s.tick=144
	s.step()
	check("origin and phase travel separately",s.fault_reason.is_empty() and spy.origin==0.6 and spy.policy_at==0.0)
	check("nonautonomous tiny integral is one",absf(spy.tiny_integral-1.0)<1e-15)
	var cp:=s.checkpoint()
	check("checkpoint pins local protocol",cp.callback_protocol==Model.PROTOCOL_JOINT_INTERVAL_LOCAL)
	var old_clock:=cp.duplicate(true)
	old_clock.callback_protocol=Model.PROTOCOL_JOINT_INTERVAL
	check("checkpoint cannot cross clock protocols",not s.can_restore_checkpoint(old_clock))
	var before:=var_to_bytes([s.state,s.continuous,s.aux,s.tick])
	spy.outside=true
	s.step()
	check("negative local stage refuses atomically",not s.fault_reason.is_empty() and var_to_bytes([s.state,s.continuous,s.aux,s.tick])==before)
	spy.erase("outside")
	check("exact local checkpoint restores",s.restore_checkpoint(cp))
	spy.mutation=true
	s.step()
	check("local policy context remains read-only",not s.fault_reason.is_empty() and var_to_bytes([s.state,s.continuous,s.aux,s.tick])==before)
	s.free()
	_tiny_partition(h)
	print("SF_LOCAL_INTERVAL_TEST %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func _tiny_partition(h: float) -> void:
	var state:=body()
	state.append_array(PackedFloat64Array([2.0,1.0,0.0,0.0]))
	var target: float="6fbbac0e8d45e13f".hex_decode().to_float64_array()[0]
	var actual: float="6ebbac0e8d45e13f".hex_decode().to_float64_array()[0]
	var p:=Law.prepare(PackedFloat64Array([actual]),PackedFloat64Array([target]),PackedFloat64Array([5.0]),1.0/240.0)
	check("failed campaign residual is retained as a real cut",p.ok and p.offsets==PackedFloat64Array([h]))
	# A dimensionless ramp -1 -> 0 over h has the analytic integral -h/2.
	var f:=func(_values: PackedFloat64Array,at: float,origin: float=0.0,_end: float=1.0) -> PackedFloat64Array:
		var out:=PackedFloat64Array()
		out.resize(17)
		out[15]=minf((origin+at)/h-1.0,0.0)
		return out
	var project:=func(values: PackedFloat64Array,index: int) -> PackedFloat64Array:
		var out:=values.duplicate()
		out[index]=0.0
		return out
	var original:=state.to_byte_array()
	var absolute:=Step.advance_at_offsets(state,0.6,1.0/240.0,f,PackedFloat64Array(),13,14,project,1,p.offsets)
	check("old absolute contract still refuses this cut",not absolute.ok and state.to_byte_array()==original)
	var local:=Step.advance_at_offsets(state,0.0,1.0/240.0,f,PackedFloat64Array(),13,14,project,1,p.offsets,true)
	check("new local partition retains tiny-piece integral",local.ok and absf(local.state[15]+h/2.0)<1e-32 and state.to_byte_array()==original)
	var cut: float=1.0-1.1102230246251565e-16
	var width: float=1.0-cut
	check("late piece has no tick-local midpoint",cut+width/2.0==1.0 or cut+width/2.0==cut)
	var tail:=func(_values: PackedFloat64Array,_phase: float,origin: float=0.0,_end: float=1.0) -> PackedFloat64Array:
		var out:=PackedFloat64Array()
		out.resize(17)
		out[15]=1.0/width if origin==cut else 0.0
		return out
	var late:=Step.advance_at_offsets(state,0.0,1.0,tail,PackedFloat64Array(),13,14,project,1,PackedFloat64Array([cut]),true)
	check("late piece retains its own clock and full integral",late.ok and absf(late.state[15]-1.0)<1e-15)
	var start: float="b53a2678304f94bf".hex_decode().to_float64_array()[0]
	var wanted: float="00aaf1d24d62503f".hex_decode().to_float64_array()[0]
	var begin_cut: float="4e1be8b4814e3b3f".hex_decode().to_float64_array()[0]
	var dt: float=1.0/240.0
	var endpoint_plan:=Law.prepare(PackedFloat64Array([start]),PackedFloat64Array([wanted]),PackedFloat64Array([5.0]),dt)
	check("arrival is exactly at outer endpoint",endpoint_plan.ok and endpoint_plan.arrivals[0]==dt)
	check("piece k4 retains the exact declared endpoint bits",Law.sample_split(endpoint_plan,begin_cut,dt-begin_cut,dt).to_byte_array()==endpoint_plan.endpoint.to_byte_array())
	check("piece k4 equals next piece k1 at shared boundary",Law.sample_split(endpoint_plan,0.0,begin_cut,begin_cut).to_byte_array()==Law.sample_split(endpoint_plan,begin_cut,0.0,dt).to_byte_array())
	var endpoint_zero:=Law.prepare(PackedFloat64Array([-1.0]),PackedFloat64Array([0.0]),PackedFloat64Array([1.0]),1.0)
	check("interior phase rounding to end stays before arrival",cut+0.75*width==1.0 and Law.sample_split(endpoint_zero,cut,0.75*width,1.0)[0]<0.0)
	var first_phase: float="fca9f1d24d62503f".hex_decode().to_float64_array()[0]
	var next_phase: float="fda9f1d24d62503f".hex_decode().to_float64_array()[0]
	var public_at:=Step.local_event_time(first_phase,0.002,first_phase)
	check("event-pair fixture really loses phase order",first_phase<next_phase and first_phase+first_phase==first_phase+next_phase)
	check("distinct event phases cannot become simultaneous",is_nan(Step.local_event_time(first_phase,0.002,next_phase,first_phase,public_at)))
	check("identical event phases retain shared time",Step.local_event_time(first_phase,0.002,first_phase,first_phase,public_at)==public_at)
	# Four ULPs pass the outer midpoint check, but its one-ULP root refinement
	# cannot represent a midpoint. The locator must reject before calling RK.
	var begin: float=0.002
	var u: float=4.336808689942018e-19
	var calls := {count=0}
	var stiff:=func(_values: PackedFloat64Array,_at: float) -> PackedFloat64Array:
		calls.count+=1
		var out:=PackedFloat64Array()
		out.resize(17)
		out[13]=-1.0/u
		return out
	check("outer clock resolves but root midpoint collapses",Event.stage_clock_resolved(begin,4.0*u) and not Event.stage_clock_resolved(begin,u))
	var initial:=state.duplicate()
	initial[13]=1.0
	var event:=Event.advance(initial,begin,4.0*u,stiff,PackedFloat64Array(),13,project,"rotor_stop",true)
	check("dynamic root refinement refuses an unresolved clock",not event.ok and initial[13]==1.0 and calls.count==4)
	var subnormal: float=PackedByteArray([2,0,0,0,0,0,0,0]).to_float64_array()[0]
	check("subnormal RK weight is refused despite a distinct midpoint",subnormal>0.0 and subnormal/2.0>0.0 and not Event.stage_clock_resolved(0.0,subnormal))
	calls.count=0
	event=Event.advance(initial,0.0,subnormal,stiff,PackedFloat64Array(),13,project,"rotor_stop",true)
	check("subnormal trial refuses before evaluating or publishing",not event.ok and calls.count==0 and initial[13]==1.0)
