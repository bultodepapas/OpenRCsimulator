extends SceneTree

const Fleet := preload("fleet.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("OPENRC_AUDIT_CAPTURE")
	if out.is_empty() or FileAccess.file_exists(out):
		printerr("FAIL capture output must be a fresh path")
		quit(1)
		return
	var fleet := Fleet.new()
	var report := {format = "ci-audit-fleet-reset-v1", engine = Engine.get_version_info(),
		os = OS.get_name(), cases = []}
	for row: Dictionary in Fleet._fleet_declared_rows():
		if row.get("expected") != "reference-refusal" or not Fleet._fleet_is_runway_boundary(row):
			continue
		var result: Dictionary = fleet._build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
		check("named reference reset refuses", Fleet._fleet_expected_refusal(row, result))
		if result.get("ok", false):
			result.session.free()
			continue
		var proof: Dictionary = result.get("startup_proof", {})
		check("startup proof exists", not proof.is_empty())
		if proof.is_empty():
			continue
		for flag: String in ["before_helper_absent", "after_helper_absent", "model_retained", "callbacks_retained",
				"reference_callbacks_before", "reference_callbacks_after", "kernel_guard_retained", "owner_guard_retained",
				"selection_valid_before", "selection_valid_after", "input_configuration_retained",
				"live_configuration_retained", "outcome_empty"]:
			check("guard " + flag, typeof(proof.get(flag)) == TYPE_BOOL and proof.get(flag))
		for key: String in ["frame", "config", "outcome", "live_config"]:
			var encoded: String = str(proof.get(key + "_bytes_hex", ""))
			check("typed " + key + " hash", not encoded.is_empty() and encoded.is_valid_hex_number()
				and Fleet._fleet_encoded_sha256(encoded.hex_decode()) == proof.get(key + "_sha256"))
		check("frame retained", proof.get("before_frame_bytes_hex") == proof.get("frame_bytes_hex"))
		check("live configuration retained", proof.get("before_live_config_bytes_hex") == proof.get("live_config_bytes_hex"))
		report.cases.append({row = row, reason = result.get("reason"),
			original_pin_matches = Fleet._fleet_start_proof_valid(row, proof, NativeStage.BACKEND_REFERENCE), proof = proof})
	check("eight reference boundaries", report.cases.size() == 8)
	var file := FileAccess.open(out, FileAccess.WRITE)
	check("capture opens", file != null)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
	fleet.free()
	print("CI_AUDIT_FLEET_CAPTURE checks=%d failures=%d cases=%d" % [checks, failures, report.cases.size()])
	quit(1 if failures else 0)
