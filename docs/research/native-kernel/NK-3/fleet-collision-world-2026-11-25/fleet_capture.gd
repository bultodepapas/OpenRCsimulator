extends SceneTree
## Scratch: capture the eight bounded runway reference reset observations (format of
## docs/research/project-audit-2026-11-09/remediation/compare_fleet.gd). Environment:
## OPENRC_FLEET_SCRIPT = absolute path of research/native-kernel/fleet.gd, OPENRC_AUDIT_CAPTURE = fresh output path.

const NativeStage := preload("res://sim/native_stage.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fleet_script: Script = load(OS.get_environment("OPENRC_FLEET_SCRIPT"))
	var output_path := OS.get_environment("OPENRC_AUDIT_CAPTURE")
	if fleet_script == null or output_path.is_empty() or FileAccess.file_exists(output_path):
		printerr("FAIL capture needs OPENRC_FLEET_SCRIPT and a fresh OPENRC_AUDIT_CAPTURE")
		quit(1)
		return
	var fleet: Object = fleet_script.new()
	var cases: Array = []
	for row: Dictionary in fleet_script._fleet_declared_rows():
		if row.get("expected") != "reference-refusal" or row.get("aircraft") in fleet_script.STIK_RUNWAY_REFUSAL_AIRCRAFT \
				or not fleet_script._fleet_is_runway_boundary(row):
			continue
		var observed: Dictionary = fleet._build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
		var proof: Variant = observed.get("startup_proof", {})
		var pins_match: bool = fleet_script._fleet_expected_refusal(row, observed) \
			and fleet_script._fleet_start_proof_valid(row, proof, NativeStage.BACKEND_REFERENCE)
		cases.append({row = row, reason = observed.get("reason", ""), original_pin_matches = pins_match, proof = proof})
		print("CASE %s battery=%s soft=%s pins_match=%s live=%s frame=%s config=%s outcome=%s" % [row.aircraft,
			row.battery, row.soft_hull, pins_match, str(proof.get("live_config_sha256", "")).left(12),
			str(proof.get("frame_sha256", "")).left(12), str(proof.get("config_sha256", "")).left(12),
			str(proof.get("outcome_sha256", "")).left(12)])
		if observed.get("ok", false):
			observed.session.free()
	var capture := {format = "ci-audit-fleet-reset-v1", engine = Engine.get_version_info(), os = OS.get_name(),
		cases = cases}
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(capture, "  "))
	file.close()
	print("FLEET_CAPTURE cases=%d" % cases.size())
	if fleet is Node:
		(fleet as Node).free()
	quit(0 if cases.size() == 8 else 1)
