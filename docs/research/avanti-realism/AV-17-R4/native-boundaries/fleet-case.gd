extends SceneTree
const Fleet := preload("../../../research/native-kernel/fleet.gd")
func _initialize() -> void:
	var fleet := Fleet.new()
	fleet._report = {fleet = [], components = {}}
	for row: Dictionary in Fleet._fleet_declared_rows():
		if row.aircraft == "sebart-avanti-s-a200-p100rx" and row.battery == "ideal" and row.case == "runway" and row.weather == "crosswind":
			fleet._fleet_case(row, 2, 3)
	var errors := []
	if fleet._report.fleet.size() != 2: errors.append("expected two rows")
	for result: Dictionary in fleet._report.fleet:
		if result.status != "reference-refused" or result.fingerprint_equal != false or result.reference.complete != false or result.native.complete != false:
			errors.append("row not recorded as refusal")
	if not fleet._failures.is_empty(): errors.append_array(fleet._failures)
	var output := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if output == null: errors.append("failed to write results")
	else:
		output.store_string(JSON.stringify({format = "av17-r4-fleet-case v1", rows = fleet._report.fleet, components = fleet._report.components, failures = errors}, "\t", true, true) + "\n")
		output.close()
	fleet.free()
	print("AVANTI_FLEET_CASE verdict=%s rows=%d failures=%d" % ["pass" if errors.is_empty() else "fail", 2, errors.size()])
	quit(0 if errors.is_empty() else 1)
