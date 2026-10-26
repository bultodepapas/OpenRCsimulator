extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/owner.gd"
const MassAR:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/contact_assembly_resolution.gd")
const ProfileTiming:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/metrics.gd")
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	var which:="rest6"
	var use_policy:=true
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):which=argument.trim_prefix("--case=")
		if argument=="--no-policy":use_policy=false
	var raw:Dictionary
	if which.begins_with("rest"):
		var suffix:="6s" if which=="rest6" else "10s"
		var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/checkpoint-"+suffix+".bin",FileAccess.READ)
		var cp:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
		var values:PackedFloat64Array=cp.state.duplicate();values.append_array(cp.continuous)
		raw={state=values,time_s=cp.tick*cp.dt,dt=cp.dt,options=_options()}
		lift_ratio=0.0;brake_start=100.0;_bind()
	else:
		raw=_read("ground_unloaded_gentle.bin" if which=="gentle" else "ground_unloaded_hard.bin")
	var at_point:=_sample_policy(raw.state,raw.time_s)
	var angular:PackedFloat64Array=at_point.rotor_stage.matrix
	var w:int=6+at_point.rotor_stage.axial.size()
	var mass:=PackedFloat64Array();mass.resize(w*w)
	for i in 3:mass[i*w+i]=at_point.mass_kg
	for i in w-3:
		for j in w-3:mass[(i+3)*w+j+3]=angular[i*(w-3)+j]
	var prep_started:=Time.get_ticks_usec()
	var prepared_mass:=MassAR.prepare_mass(mass,w)
	var prep_elapsed:=Time.get_ticks_usec()-prep_started
	check("fixed mass proof prepares",prepared_mass.ok,str(prepared_mass))
	ProfileTiming.clear()
	var started:=Time.get_ticks_usec()
	var result:=Candidate.advance(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,raw.options,_gate,_policy if use_policy else Callable(),prepared_mass.proof)
	var elapsed:=Time.get_ticks_usec()-started
	var timings:={mass_prepare_us=prep_elapsed,case=which,policy=use_policy,elapsed_us=elapsed,inclusive_us=ProfileTiming.totals.duplicate(),exclusive_us=ProfileTiming.exclusive.duplicate(),calls=ProfileTiming.counts.duplicate(),serialized_bytes=ProfileTiming.serial_bytes.duplicate(),ok=result.ok,status=result.get("status"),accepted_substeps=result.get("integration_receipt",{}).get("accepted_substeps"),reason=result.get("reason"),note="Diagnostic wrapper timings include overhead; no native or performance qualification"}
	var suffix:=which+("-policy" if use_policy else "-default")
	var f:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/"+suffix+".result.bin",FileAccess.WRITE);f.store_buffer(var_to_bytes(result));f.close()
	f=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/"+suffix+".timings.json",FileAccess.WRITE);f.store_string(JSON.stringify(timings,"\t",true,true));f.close()
	print("PROFILE_RESULT ",JSON.stringify(timings,"",true,true))
	print("Hotspot snapshot completed: %d fixture checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
