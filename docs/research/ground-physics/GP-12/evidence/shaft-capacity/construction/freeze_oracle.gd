extends SceneTree
func _initialize() -> void:
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/results-main-final.bin",FileAccess.READ)
	var rows: Array = file.get_var()
	var evaluations: Array = []
	var steps: Array = []
	for row: Dictionary in rows:
		if row.kind == "complete_evaluation":
			evaluations.append({down=row.down,enabled=row.enabled,expected=var_to_bytes(row.original)})
		elif row.kind == "legacy_step":
			steps.append({law=row.law,expected=var_to_bytes(row.original)})
	var result := {format="openrc-electric-shaft-original-oracle v1",evaluations=evaluations,steps=steps}
	var out := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-shaft-capacity/ground_contact_shaft_legacy.bin",FileAccess.WRITE)
	out.store_buffer(var_to_bytes(result))
	print("FROZEN_ORIGINAL_SHAFT_ORACLE ",evaluations.size()," evaluations; ",steps.size()," steps; original frozen main hashes required")
	quit()
