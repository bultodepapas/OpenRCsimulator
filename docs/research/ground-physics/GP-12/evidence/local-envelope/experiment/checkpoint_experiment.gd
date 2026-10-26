extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/composition.gd"
const FrozenStep := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/capture_step.gd")
const TICKS_PER_ROUTE := 4


func _initialize() -> void:
	_fixture()
	_prepare_composition()
	_prepare_quality()
	if failed:
		quit(1)
		return
	var experiments: Array = []
	for second: int in [6, 10]:
		var path := "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-local-reuse/checkpoint-%ds.bin" % second
		var file := FileAccess.open(path, FileAccess.READ)
		var cp: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
		file.close()
		var original := var_to_bytes(cp)
		var baseline := _run_checkpoint(cp, false)
		var local := _run_checkpoint(cp, true)
		check("frozen checkpoint is read-only", original == var_to_bytes(cp))
		var comparison := {}
		if baseline.ok and local.ok:
			var a: PackedFloat64Array = baseline.state
			var b: PackedFloat64Array = local.state
			var max_rim := 0.0
			for i in range(14, 17): max_rim = maxf(max_rim, absf(a[i]-b[i]))
			comparison = {position_difference_m = M.norm(M.sub(a.slice(0,3),b.slice(0,3))),
				body_velocity_difference_mps = M.norm(M.sub(a.slice(3,6),b.slice(3,6))),
				body_rate_difference_radps = M.norm(M.sub(a.slice(10,13),b.slice(10,13))),
				shaft_difference_radps = absf(a[13]-b[13])*TAU/60.0, maximum_rim_difference_mps=max_rim}
		baseline.erase("state")
		local.erase("state")
		experiments.append({checkpoint_s=second, baseline=baseline, interval=local, comparison=comparison})
		print("LOCAL_ENVELOPE_CHECKPOINT ",JSON.stringify(experiments[-1],"",true,true))
	var output := {scope="four ticks per route from each unchanged frozen checkpoint; no full tape rerun or performance claim",
		motion_envelope="same conditional GAP_SPEED_MAX3 OMEGA_MAX5 CM_NORMAL_SPEED_MAX3 X_MAX.18; complete paired-path gate unchanged",
		experiments=experiments, checks=checks, failures=failed}
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/checkpoint-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t",true,true))
	file.close()
	print("Local envelope checkpoint experiment: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)


func _new_sim(initial: PackedFloat64Array) -> Node:
	var sim := super._new_sim(initial)
	sim.model.step_policy = func(s,t,h,f,k1): return FrozenStep.advance(s,t,h,f,k1,_snapshot,_certificate,_options(),_error_gate)
	return sim


func _run_checkpoint(cp: Dictionary, interval: bool) -> Dictionary:
	use_local_interval = interval
	var sim := _new_sim(_initial(-.2+live.mass_kg*GRAVITY/4500.0,0.0,0.0,0.0))
	var restored: bool = sim.restore_checkpoint(cp.duplicate(true))
	check("retained checkpoint restores for selected envelope",restored)
	if not restored:
		sim.free()
		return {ok=false,reason="checkpoint restore refused"}
	var start_tick: int = sim.tick
	var initial_energy: float = _energy(sim)+sim.aux[0]+sim.aux[1]-sim.aux[2]
	var pieces := PackedFloat64Array()
	var gates := PackedFloat64Array()
	var worst_energy := 0.0
	for _i in TICKS_PER_ROUTE:
		sim.step()
		if not sim.fault_reason.is_empty(): break
		pieces.append(sim.aux[4])
		gates.append(sim.aux[6])
		worst_energy = maxf(worst_energy,absf(_energy(sim)+sim.aux[0]+sim.aux[1]-sim.aux[2]-initial_energy))
	var complete: bool = sim.tick == start_tick+TICKS_PER_ROUTE and sim.fault_reason.is_empty()
	check("bounded checkpoint continuation completes unchanged raw accuracy gate",complete,str(sim.fault_reason))
	var result := {ok=complete,starting_tick=start_tick,ending_tick=sim.tick,accepted_substeps=pieces,normalized_errors=gates,
		maximum_incremental_accounted_energy_drift_j=worst_energy, fault=sim.fault_reason,state=_combined(sim)}
	sim.free()
	return result
