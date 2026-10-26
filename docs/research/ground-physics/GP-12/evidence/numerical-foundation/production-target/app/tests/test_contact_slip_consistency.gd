extends SceneTree
const I:=preload("res://physics/aircraft_ground_impulse.gd")
const R:=preload("res://physics/contact_assembly_resolution.gd")
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
	var file:=FileAccess.open("res://tests/fixtures/ground_contact_rest_slip.bin",FileAccess.READ)
	var raw:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	check("frozen input byte identity",FileAccess.get_sha256("res://tests/fixtures/ground_contact_rest_slip.bin")==golden["ground_contact_rest_slip.bin"].input_sha256)
	var frozen:=var_to_bytes(raw)
	var old:Dictionary=golden["ground_contact_rest_slip.bin"].legacy_optin
	check("retained actual tick26 failure remains reproducible",not old.ok)
	var actual:=I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,raw.jacobian,raw.prescribed_slip_bias,
		raw.limits,raw.groups,1024,{},raw.maximum_assembly_resolution_j)
	check("actual tick26 slip difference has a verified operand bound",actual.ok,actual)
	if actual.ok:
		check("same impulse and generalized impulse bytes, no new force or clamp",var_to_bytes(actual.impulse)==var_to_bytes(raw.qp.impulse)
			and var_to_bytes(actual.generalized_impulse)==var_to_bytes(raw.generalized_impulse))
		var delta:PackedFloat64Array=actual.delta_velocity_cm_body.duplicate()
		delta.append_array(actual.delta_omega)
		delta.append_array(actual.delta_spin)
		check("same actual mass-response delta bytes",var_to_bytes(delta)==var_to_bytes(raw.delta))
		check("old measured slip failure stays visible",actual.slip_relative_residual>1e-10
			and actual.slip_roundoff.legacy_relative_residual==actual.slip_relative_residual)
		check("work and mass acceptance remain unchanged",actual.mass_solve_relative_residual<=1e-10
			and absf(actual.energy_balance_residual)<=1e-10*raw.work_scale and actual.dissipated_energy>0.0)
		check("row2 discrepancy is below independently derived absolute bound",actual.slip_roundoff.row_absolute_differences[2]
			<=actual.slip_roundoff.row_absolute_bounds[2])
		check("combined numerical uncertainty fits same per-QP owner ceiling",actual.slip_roundoff.combined_contact_uncertainty_j
			<=raw.maximum_assembly_resolution_j)
		var too_tight:float=actual.slip_roundoff.qp_objective_uncertainty_j+.5*actual.slip_roundoff.work_equivalent_bound_j
		check("separate individually fitting proofs cannot overspend combined ceiling",not I.apply(raw.stage,raw.mass_kg,
			raw.velocity_cm_body,raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups,1024,{},too_tight).ok)
		print("SLIP_PROOF ",JSON.stringify(actual.slip_roundoff,"",true,true))
	check("default absent opt-in keeps strict refusal",not I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,raw.jacobian,
		raw.prescribed_slip_bias,raw.limits,raw.groups).ok)
	check("all actual captured input bytes remain detached",frozen==var_to_bytes(raw))
	var w:int=raw.z.size()
	var mass:=PackedFloat64Array()
	mass.resize(w*w)
	for i in 3:mass[i*w+i]=raw.mass_kg
	for i in w-3:
		for j in w-3:mass[(3+i)*w+3+j]=raw.stage.matrix[i*(w-3)+j]
	var responses:=PackedFloat64Array()
	for row:PackedFloat64Array in raw.responses:responses.append_array(row)
	var bad:PackedFloat64Array=raw.delta.duplicate()
	bad[0]+=1e-6
	check("meaningful incorrect mass response cannot be explained as roundoff",not R.slip_consistency(raw.mobility,raw.free_slip,
		mass,raw.jacobian,raw.z,raw.prescribed_slip_bias,responses,raw.qp.impulse,raw.generalized_impulse,bad,raw.qp.post_slip).ok)
	bad=raw.qp.post_slip.duplicate()
	bad[2]+=1e-6
	check("incorrect algebraic post slip cannot inflate its own tolerance",not R.slip_consistency(raw.mobility,raw.free_slip,
		mass,raw.jacobian,raw.z,raw.prescribed_slip_bias,responses,raw.qp.impulse,raw.generalized_impulse,raw.delta,bad).ok)
	bad=raw.generalized_impulse.duplicate()
	bad[0]+=1e-6
	check("forged generalized impulse refuses exact dot binding",not R.slip_consistency(raw.mobility,raw.free_slip,
		mass,raw.jacobian,raw.z,raw.prescribed_slip_bias,responses,raw.qp.impulse,bad,raw.delta,raw.qp.post_slip).ok)
	bad=raw.delta.duplicate()
	bad[0]=INF
	check("nonfinite response refuses before bound arithmetic",not R.slip_consistency(raw.mobility,raw.free_slip,
		mass,raw.jacobian,raw.z,raw.prescribed_slip_bias,responses,raw.qp.impulse,raw.generalized_impulse,bad,raw.qp.post_slip).ok)
	var original:Dictionary=golden["ground_contact_rest_slip.bin"].strict
	var ordinary:=I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups)
	check("default strict caller complete failure bytes unchanged",var_to_bytes(original)==var_to_bytes(ordinary))
	var shaft:=I.internal_brake(0,raw.stage.axial.size())
	var one:Array=[PackedInt32Array([0])]
	original=golden["ground_contact_rest_slip.bin"].ordinary
	ordinary=I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,shaft.row,PackedFloat64Array([0]),PackedFloat64Array([.001]),one)
	check("default strict caller complete successful output bytes unchanged",original.ok and ordinary.ok
		and var_to_bytes(original)==var_to_bytes(ordinary))
	print("Contact slip consistency: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
