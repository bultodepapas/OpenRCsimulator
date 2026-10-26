extends SceneTree
const R:=preload("res://physics/contact_assembly_resolution.gd")
const I:=preload("res://physics/aircraft_ground_impulse.gd")
var checks:=0
var failures:=0
func check(label:String,value:bool,detail:Variant="")->void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL ",label," ",detail)
func _initialize()->void:

	var golden_path:="res://tests/fixtures/ground_contact_default_outputs.bin"
	check("frozen result bytes retain exact identity",FileAccess.get_sha256(golden_path)=="85df6ec77ea772eb55a5d1b9942e4d828ea78fae25fd833b93d6a6af1ece5133")
	var golden_file:=FileAccess.open(golden_path,FileAccess.READ)
	var golden:Dictionary=bytes_to_var(golden_file.get_buffer(golden_file.get_length())).cases
	golden_file.close()
	var file:=FileAccess.open("res://tests/fixtures/ground_contact_rest_work.bin",FileAccess.READ)
	var d:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	check("frozen input byte identity",FileAccess.get_sha256("res://tests/fixtures/ground_contact_rest_work.bin")==golden["ground_contact_rest_work.bin"].input_sha256)
	var frozen:=var_to_bytes(d)
	var p:=R.work_consistency(d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,
		d.flat_responses,d.qp.impulse,d.generalized_impulse,d.delta,d.qp.post_slip,d.stage.affine_momentum,
		d.qp.objective,d.incremental_change,d.closure)
	check("retained tick262 raw work target fails",absf(d.closure)>1e-10*d.work_scale)
	check("actual operands explain closure and independently certify actual-state passivity",p.get("ok",false),p)
	check("reported operands remain detached",var_to_bytes(d)==frozen)
	if p.get("ok",false):
		check("raw actual work difference stays visible",p.raw_closure_j==d.closure and p.closure_absolute_bound_j>=absf(d.closure))
		check("actual updated-state physical work is provably negative",p.actual_relative_work_upper_j<0.0)
		check("arithmetic budget remains much smaller than owner ceiling",p.work_equivalent_bound_j+d.qp.assembly_resolution.assembly_objective_resolution_j<d.maximum_assembly_resolution_j)
		print("WORK_PROOF ",JSON.stringify(p,"",true,true))
	check("fabricated reported closure refuses exact arithmetic binding",not R.work_consistency(d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,
		d.flat_responses,d.qp.impulse,d.generalized_impulse,d.delta,d.qp.post_slip,d.stage.affine_momentum,d.qp.objective,d.incremental_change,d.closure+1e-12).ok)
	check("fabricated QP objective refuses exact arithmetic binding",not R.work_consistency(d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,
		d.flat_responses,d.qp.impulse,d.generalized_impulse,d.delta,d.qp.post_slip,d.stage.affine_momentum,d.qp.objective-1e-12,d.incremental_change,d.closure).ok)
	var bad:PackedFloat64Array=d.delta.duplicate()
	bad[0]+=1e-6
	check("nonphysical common-mass response cannot masquerade as arithmetic work",not R.work_consistency(d.mobility,d.free_slip,d.full_mass,d.jacobian,d.z,d.prescribed_slip_bias,
		d.flat_responses,d.qp.impulse,d.generalized_impulse,bad,d.qp.post_slip,d.stage.affine_momentum,d.qp.objective,d.incremental_change,d.closure).ok)
	var eta:float=R.M.MIN_NORMAL_FLOAT64*R.EPS
	var pairs:Array=[PackedFloat64Array([1.0,R.EPS/2.0,1.0,R.EPS/2.0]),PackedFloat64Array([1.0,-1.0+R.EPS,R.EPS,0.0]),
		PackedFloat64Array([1.0,eta,1.0,eta]),PackedFloat64Array([R.M.MIN_NORMAL_FLOAT64,eta,R.M.MIN_NORMAL_FLOAT64+eta,0.0]),
		PackedFloat64Array([-1.0,-R.EPS/2.0,-1.0,-R.EPS/2.0]),PackedFloat64Array([R.M.MIN_NORMAL_FLOAT64,-R.M.MIN_NORMAL_FLOAT64,0.0,0.0])]
	for i in pairs.size():
		var pair:PackedFloat64Array=pairs[i]
		var sum:=R.two_sum(pair[0],pair[1])
		check("TwoSum exact independent expected high/low "+str(i),sum.size()==2 and sum[0]==pair[2] and sum[1]==pair[3],sum)
	check("TwoSum unsupported overflow/nonfinite refuses",R.two_sum(1.7976931348623157e308,1.7976931348623157e308).is_empty() and R.two_sum(INF,1.0).is_empty())
	var applied:=I.apply(d.stage,d.mass_kg,d.velocity_cm_body,d.jacobian,d.prescribed_slip_bias,d.limits,d.groups,1024,{},d.maximum_assembly_resolution_j)
	check("actual captured work refusal now has explicit arithmetic proof",applied.ok,applied)
	if applied.ok:
		var actual_delta:PackedFloat64Array=applied.delta_velocity_cm_body.duplicate()
		actual_delta.append_array(applied.delta_omega)
		actual_delta.append_array(applied.delta_spin)
		check("same published physical impulse/generalized impulse/delta bytes",var_to_bytes(applied.impulse)==var_to_bytes(d.qp.impulse)
			and var_to_bytes(applied.generalized_impulse)==var_to_bytes(d.generalized_impulse) and var_to_bytes(actual_delta)==var_to_bytes(d.delta))
		check("raw old work refusal remains visible",applied.energy_balance_residual==d.closure and applied.work_roundoff.legacy_work_target_j<absf(d.closure))
		var tight:float=d.qp.assembly_resolution.assembly_objective_resolution_j+.5*applied.work_roundoff.work_equivalent_bound_j
		check("combined QP and actual-state work allowance cannot double spend",not I.apply(d.stage,d.mass_kg,d.velocity_cm_body,d.jacobian,d.prescribed_slip_bias,d.limits,d.groups,1024,{},tight).ok)
	check("strict-default complete refusal bytes remain unchanged",var_to_bytes(I.apply(d.stage,d.mass_kg,d.velocity_cm_body,d.jacobian,d.prescribed_slip_bias,d.limits,d.groups))
		==var_to_bytes(golden["ground_contact_rest_work.bin"].strict))
	# Independent SPD construction: a tiny first-coordinate correction has a
	# free second-coordinate response below one ulp of its unit velocity. The
	# ORIGINAL ideal QP is passive, but rounding the actual state creates genuine
	# positive common-mass work. Arithmetic consistency alone must not accept it.
	var mass:=PackedFloat64Array([1.0,.1,0.0,.1,1.0,0.0,0.0,0.0,1.0])
	var factor:=R.GC.cholesky_factor(mass,3)
	var j:=PackedFloat64Array([1.0,0.0,0.0])
	var response:=R.GC.solve_cholesky(factor.lower,j,3)
	var z:=PackedFloat64Array([-1e-20,1.0,0.0])
	var impulse:=PackedFloat64Array([1e-20/response[0]])
	var g:=PackedFloat64Array([impulse[0],0.0,0.0])
	var delta:=R.GC.solve_cholesky(factor.lower,g,3)
	var a:=PackedFloat64Array([response[0]])
	var v:=PackedFloat64Array([z[0]])
	var post:=PackedFloat64Array([a[0]*impulse[0]+v[0]])
	var objective:float=v[0]*impulse[0]+.5*impulse[0]*(a[0]*impulse[0])
	var incremental:float=R.GC.dot(z,g,3)+.5*R.GC.dot(g,delta,3)
	var proof:=R.work_consistency(a,v,mass,j,z,PackedFloat64Array([0.0]),response,impulse,g,delta,post,PackedFloat64Array(),objective,incremental,incremental-objective)
	check("passive ideal QP cannot hide positive published-state common-mass work",not proof.ok and proof.get("actual_relative_work_j",0.0)>0.0,proof)
	print("Contact work consistency: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
