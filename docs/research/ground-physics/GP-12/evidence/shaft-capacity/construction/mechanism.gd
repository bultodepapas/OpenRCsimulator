## Diagnostic only: fixed8/16 complete paths, unchanged physical gates measured
## after both outcomes. No runtime operator or capacity rule is changed.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/test_shaft_capacity.gd"
func _initialize() -> void:
	_fixture(); _electric_fixture()
	shaft_context = NewElectric.prepare_capacity(electric, provider, "fixed-voltage-synthetic-owner-no-events-v1")
	var initial := _runtime_initial()
	var sample := func(s,t): return _airborne_point(s,t)
	var records: Array = []
	for command: float in [.002, .004, .02, 1.0]:
		runtime_duty = command; runtime_enabled = true
		var point := _airborne_point(initial,0.0)
		var pair: Array = []
		for count: int in [8,16]:
			var certificate := func(s,t,h,p):
				var r := _shaft_certificate(s,t,h,p)
				r.admitted = r.admitted and h <= 1.0/240.0/count
				return r
			var result := NewStep.advance(initial,0.0,1.0/240.0,_airborne_derivative,PackedFloat64Array(),sample,
				certificate,{operator_law=NewStep.INTEGRATED_CAPACITY_LAW,max_substeps=count})
			pair.append(result)
		var row := {duty=command,source=point.source,pair=pair}
		if pair[0].ok and pair[1].ok:
			row.strict = _runtime_error_gate(pair[0].state,pair[1].state,pair[0].integration_receipt,pair[1].integration_receipt,1.0/240.0)
			row.quality = _runtime_quality_gate(pair[0].state,pair[1].state,pair[0].integration_receipt,pair[1].integration_receipt,1.0/240.0)
			var index: int = RB.SIZE + electric.rotor_index
			row.shaft_error_radps = absf(pair[0].state[index]-pair[1].state[index])*TAU/60.0
			row.shaft_error_bound_radps = 1e-4+1e-5*maxf(absf(pair[0].state[index]*TAU/60.0),absf(pair[1].state[index]*TAU/60.0))
			row.work_error_j = absf(pair[0].integration_receipt.external_work_j-pair[1].integration_receipt.external_work_j)
			row.heat_error_j = absf(pair[0].integration_receipt.tangent_dissipation_j-pair[1].integration_receipt.tangent_dissipation_j)
		print("SHAFT_MECHANISM ",command," drive=",point.source.internal_drive_torque_nm," cap=",point.source.shaft_friction_capacity_nm,
			" statuses=",pair[0].get("status","accepted"),",",pair[1].get("status","accepted")," strict=",row.get("strict",{}),
			" shaft_delta=",row.get("shaft_error_radps")," Jdelta=",row.get("work_error_j")," heatdelta=",row.get("heat_error_j"))
		records.append(row)
	var f := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/mechanism.bin",FileAccess.WRITE)
	f.store_var(records)
	print("SHAFT_MECHANISM_COMPLETE")
	quit()
