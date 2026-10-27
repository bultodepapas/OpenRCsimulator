extends SceneTree
func _initialize() -> void:
	var f := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/mechanism.bin",FileAccess.READ)
	var records: Array = f.get_var()
	var summary: Array = []
	for row: Dictionary in records:
		var out := {duty=row.duty, drive_nm=row.source.internal_drive_torque_nm, bearing_nm=row.source.shaft_friction_capacity_nm,
			static_threshold_duty=1.2*.08/14.8, forcefree_normal=true}
		if row.has("strict"):
			out.strict_error=row.strict.normalized_error; out.quality_error=row.quality.normalized_error
			out.shaft_error_radps=row.shaft_error_radps; out.shaft_bound_radps=row.shaft_error_bound_radps
			out.work_error_j=row.work_error_j;out.heat_error_j=row.heat_error_j
		var paths: Array = []
		for result: Dictionary in row.pair:
			if not result.ok:
				paths.append({status=result.status});continue
			var r: Dictionary = result.integration_receipt
			for load: float in r.sampled_peak_normal_n:
				if load != 0.0: out.forcefree_normal = false
			var records2: Array = r.interval_capacity.pieces
			var first: PackedFloat64Array = records2[0].budget_groups
			var group := first.slice(first.size()-13)
			paths.append({pieces=r.accepted_substeps,end_rpm=result.state[13],first_bearing_budget=group,
				energy_residual_j=r.energy_balance_residual_j,external_work_j=r.external_work_j,heat_j=r.tangent_dissipation_j})
		out.paths=paths;summary.append(out)
	var out := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/mechanism-summary.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(summary,"\t"))
	f = FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/results-main-final.bin",FileAccess.READ)
	var original_status: Array = []
	for row: Dictionary in f.get_var():
		if row.kind == "legacy_step": original_status.append({law=row.law,ok=row.original.ok,status=row.original.status})
	out = FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/original-step-scope.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(original_status,"\t"))
	print("SHAFT_EVIDENCE_SUMMARIZED ",summary.size())
	quit()
