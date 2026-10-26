extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/composition.gd"
const CandidateStep:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/screened_step.gd")
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/metrics.gd")
func _initialize()->void:
	_fixture()
	_prepare_composition()
	_prepare_quality()
	var sag:float=live.mass_kg*GRAVITY/4500.0
	var sim:=_new_sim(_initial(-.2+sag,0.0,0.0,0.0))
	sim.model.step_policy=func(s,t,h,f,k1):return CandidateStep.advance(s,t,h,f,k1,_snapshot,_certificate,_options(),_error_gate)
	var file:=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-slip-proof/last-rest-checkpoint.bin",FileAccess.READ)
	var cp:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	check("exact accepted tick240 checkpoint restores",sim.restore_checkpoint(cp))
	Timing.clear()
	var started:=Time.get_ticks_usec()
	sim.step()
	var elapsed:=Time.get_ticks_usec()-started
	var result:={elapsed_us=elapsed,timings_us=Timing.totals.duplicate(),calls=Timing.counts.duplicate(),tick=sim.tick,
		fault=sim.fault_reason,accepted_substeps=sim.aux[4],error=sim.aux[6],note="nested inclusive diagnostic timings, not production qualification"}
	file=FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t",true,true))
	file.close()
	print("TICK_PROFILE ",JSON.stringify(result,"",true,true))
	check("exact one tick accepts",sim.tick==241 and sim.fault_reason.is_empty())
	sim.free()
	print("Exact tick profile: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
