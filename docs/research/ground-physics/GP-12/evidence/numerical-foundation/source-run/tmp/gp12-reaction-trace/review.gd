extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/composition.gd"
const TracedStep:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-reaction-trace/step.gd")
const CurrentStep:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/screened_step.gd")
func _momenta(state:PackedFloat64Array,point:Dictionary)->Dictionary:
	var q:=M.q_normalized(state.slice(RB.ATT,RB.ATT+4))
	var cmv:=M.add(state.slice(RB.VEL,RB.VEL+3),M.cross(state.slice(RB.RATE,RB.RATE+3),live.cg_body_m))
	var stage:Dictionary=point.rotor_stage
	var p:=GC.matrix_vector(stage.matrix,stage.velocity,stage.velocity.size())
	for i in p.size():p[i]+=stage.affine_momentum[i]
	return {linear=M.scale(M.q_rotate(q,cmv),live.mass_kg),angular=M.q_rotate(q,p.slice(0,3))}
func _initialize()->void:
	_fixture()
	_prepare_composition()
	_prepare_quality()
	var suffix:="6s"
	if OS.get_cmdline_user_args().has("--final"):suffix="10s"
	var file:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/checkpoint-"+suffix+".bin",FileAccess.READ)
	var cp:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	var state:PackedFloat64Array=cp.state.duplicate()
	state.append_array(cp.continuous)
	var at:float=cp.tick*cp.dt
	var point:=_snapshot(state,at)
	var exact:=CurrentStep.advance(state,at,cp.dt,_derivative,PackedFloat64Array(),_snapshot,_certificate,_options(),_error_gate)
	var traced:=TracedStep.advance(state,at,cp.dt,_derivative,PackedFloat64Array(),_snapshot,_certificate,_options(),_error_gate)
	check("bounded checkpoint reaction trace accepts",exact.ok and traced.ok,str(traced))
	if not exact.ok or not traced.ok:quit(1);return
	check("trace preserves published state exactly",var_to_bytes(exact.state)==var_to_bytes(traced.state))
	var trace:Dictionary=traced.integration_receipt.reaction_trace
	var stripped:Dictionary=traced.integration_receipt.duplicate(true)
	stripped.erase("reaction_trace")
	check("trace preserves every original receipt byte",var_to_bytes(stripped)==var_to_bytes(exact.integration_receipt))
	var p0:=_momenta(state,point)
	var p1:=_momenta(traced.state,_snapshot(traced.state,at+cp.dt))
	var reaction:PackedFloat64Array=trace.normal_impulse_ned.duplicate()
	for i in 6:reaction[i]+=trace.tangent_impulse_ned[i]
	var force:=M.scale(reaction.slice(0,3),1.0/cp.dt)
	force[2]+=live.mass_kg*GRAVITY
	var moment:=M.scale(reaction.slice(3,6),1.0/cp.dt)
	var expected_linear:=M.scale(force,cp.dt)
	var expected_angular:=M.scale(moment,cp.dt)
	var actual_linear:=M.sub(p1.linear,p0.linear)
	var actual_angular:=M.sub(p1.angular,p0.angular)
	var result:={tick=cp.tick,time_s=at,dt=cp.dt,accepted_substeps=traced.integration_receipt.accepted_substeps,
		normal_force_average_ned=M.scale(trace.normal_impulse_ned.slice(0,3),1.0/cp.dt),normal_moment_average_ned=M.scale(trace.normal_impulse_ned.slice(3,6),1.0/cp.dt),
		tangent_force_average_ned=M.scale(trace.tangent_impulse_ned.slice(0,3),1.0/cp.dt),tangent_moment_average_ned=M.scale(trace.tangent_impulse_ned.slice(3,6),1.0/cp.dt),
		total_force_residual_n=M.norm(force),total_moment_residual_nm=M.norm(moment),
		actual_linear_momentum_change=actual_linear,integrated_external_linear_impulse=expected_linear,
		actual_angular_momentum_change=actual_angular,integrated_external_angular_impulse=expected_angular,
		linear_momentum_closure=M.norm(M.sub(actual_linear,expected_linear)),angular_momentum_closure=M.norm(M.sub(actual_angular,expected_angular)),
		internal_shaft_source_nm=0.0,prescribed_carrier_work_j=traced.integration_receipt.prescribed_contact_work_j,
		qp_count=trace.solves.size(),maximum_actual_work_upper_j=-INF,positive_actual_work_upper_count=0,
		maximum_actual_work_point_j=-INF,positive_actual_work_point_count=0,actual_work_audit_count=0,
		tangent_loss_j=traced.integration_receipt.tangent_dissipation_j,energy_residual_j=traced.integration_receipt.energy_balance_residual_j,
		numerical_allowance=traced.integration_receipt.assembly_resolution}
	for solve:Dictionary in trace.solves:
		check("original QP objective remains passive",solve.objective_j<=0.0)
		if solve.audit_work.has("actual_relative_work_upper_j"):
			result.actual_work_audit_count+=1
			result.maximum_actual_work_upper_j=maxf(result.maximum_actual_work_upper_j,solve.audit_work.actual_relative_work_upper_j)
			result.maximum_actual_work_point_j=maxf(result.maximum_actual_work_point_j,solve.audit_work.actual_relative_work_j)
			if solve.audit_work.actual_relative_work_upper_j>0.0:result.positive_actual_work_upper_count+=1
			if solve.audit_work.actual_relative_work_j>0.0:result.positive_actual_work_point_count+=1
	check("complete static reaction meets unchanged force and moment scales",result.total_force_residual_n<1e-6*live.mass_kg*GRAVITY
		and result.total_moment_residual_nm<1e-6*live.mass_kg*GRAVITY*.9,str(result))
	check("independent complete linear/angular momentum closes",result.linear_momentum_closure<1e-6*live.mass_kg*GRAVITY*cp.dt
		and result.angular_momentum_closure<1e-6*live.mass_kg*GRAVITY*.9*cp.dt)
	file=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-reaction-trace/trace-"+suffix+".bin",FileAccess.WRITE)
	file.store_buffer(var_to_bytes({result=result,trace=trace,checkpoint=cp,output=traced}))
	file.close()
	file=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-reaction-trace/trace-"+suffix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t",true,true))
	file.close()
	print("REACTION_TRACE ",JSON.stringify(result,"",true,true))
	print("Reaction checkpoint review: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
