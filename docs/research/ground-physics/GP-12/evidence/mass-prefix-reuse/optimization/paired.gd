extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/baseline/owner.gd"
const Optimized:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_step.gd")
const MassAR:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/contact_assembly_resolution.gd")
func _measure_advance(raw:Dictionary,proof:RefCounted,optimized:bool)->Dictionary:
	var start:=Time.get_ticks_usec()
	var result:Dictionary
	if optimized:result=Optimized.advance(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,raw.options,_gate,_policy,proof)
	else:result=Candidate.advance(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,raw.options,_gate,_policy)
	return {elapsed_us=Time.get_ticks_usec()-start,result=result}
func _case(which:String)->Dictionary:
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/checkpoint-"+("6s" if which=="rest6" else "10s")+".bin",FileAccess.READ)
	var cp:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
	var state:PackedFloat64Array=cp.state.duplicate();state.append_array(cp.continuous)
	var raw:={state=state,time_s=cp.tick*cp.dt,dt=cp.dt,options=_options()}
	lift_ratio=0.0;brake_start=100.0;_bind()
	var point:=_sample_policy(state,raw.time_s)
	var w:int=6+point.rotor_stage.axial.size()
	var mass:=PackedFloat64Array();mass.resize(w*w)
	for i in 3:mass[i*w+i]=point.mass_kg
	for i in w-3:
		for j in w-3:mass[(i+3)*w+j+3]=point.rotor_stage.matrix[i*(w-3)+j]
	var started:=Time.get_ticks_usec()
	var prepared_mass:=MassAR.prepare_mass(mass,w)
	var prepare_us:=Time.get_ticks_usec()-started
	check("paired mass preparation",prepared_mass.ok)
	var warm_a:=_measure_advance(raw,prepared_mass.proof,false)
	var warm_b:=_measure_advance(raw,prepared_mass.proof,true)
	check("warm exact complete result parity",var_to_bytes(warm_a.result)==var_to_bytes(warm_b.result))
	var expected:=var_to_bytes(warm_a.result)
	var pairs:Array=[]
	for i in 5:
		var a:Dictionary;var b:Dictionary
		if i%2==0:a=_measure_advance(raw,prepared_mass.proof,false);b=_measure_advance(raw,prepared_mass.proof,true)
		else:b=_measure_advance(raw,prepared_mass.proof,true);a=_measure_advance(raw,prepared_mass.proof,false)
		check("paired complete baseline bytes stable",expected==var_to_bytes(a.result))
		check("paired complete optimized bytes identical",expected==var_to_bytes(b.result))
		pairs.append({baseline_us=a.elapsed_us,optimized_us=b.elapsed_us,baseline_first=i%2==0,ratio=float(b.elapsed_us)/a.elapsed_us})
	return {case=which,mass_prepare_us=prepare_us,warmup_baseline_us=warm_a.elapsed_us,warmup_optimized_us=warm_b.elapsed_us,pairs=pairs,result_hex_sha256=expected.hex_encode().sha256_text(),accepted_substeps=warm_a.result.integration_receipt.accepted_substeps}
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	var result:={cases=[_case("rest6"),_case("rest10")],checks=checks,failed=failed,note="Five warmed interleaved pairs in one process; shared-host headless diagnostic, no native or statistical qualification"}
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/paired-results.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t",true,true));f.close()
	print("MASS_PAIRED ",JSON.stringify(result,"",true,true))
	print("Prepared mass paired: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
