extends SceneTree
const Fleet := preload("../../../research/native-kernel/fleet.gd")
func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var checked := 0
	var failures := []
	for item: Dictionary in data.get("rows", []):
		var row: Dictionary = item.row
		var reference: Dictionary = item.reference
		var native: Dictionary = item.native
		if not Fleet._fleet_expected_refusal_pair(row, reference, native):
			failures.append("observed pair rejected: " + str(row.soft_hull))
		for field: String in ["frame", "config", "outcome", "live_config"]:
			var forged_ref := reference.duplicate(true)
			var forged_nat := native.duplicate(true)
			for result: Dictionary in [forged_ref, forged_nat]:
				var proof: Dictionary = result.startup_proof
				proof[field + "_bytes_hex"] = "00"
				proof[field + "_sha256"] = Fleet._fleet_encoded_sha256(PackedByteArray([0]))
				if field == "frame": proof.before_frame_bytes_hex = "00"
				if field == "live_config": proof.before_live_config_bytes_hex = "00"
			if Fleet._fleet_expected_refusal_pair(row, forged_ref, forged_nat):
				failures.append("coherently forged pair accepted: " + field)
			checked += 1
		var old_ref := reference.duplicate(true)
		var old_nat := native.duplicate(true)
		old_ref.startup_proof.aircraft_sha256 = Fleet.AVANTI_RUNWAY_V4_HISTORICAL.aircraft_sha256
		old_nat.startup_proof.aircraft_sha256 = Fleet.AVANTI_RUNWAY_V4_HISTORICAL.aircraft_sha256
		if Fleet._fleet_expected_refusal_pair(row, old_ref, old_nat):
			failures.append("historical aircraft identity accepted")
		checked += 1
	if data.get("rows", []).size() != 2: failures.append("missing contact configuration")
	for failure: String in failures: printerr(failure)
	print("AVANTI_BOUNDARY_VERIFY verdict=%s pairs=%d negative_checks=%d failures=%d" % ["pass" if failures.is_empty() else "fail", data.get("rows", []).size(), checked, failures.size()])
	quit(0 if failures.is_empty() else 1)
