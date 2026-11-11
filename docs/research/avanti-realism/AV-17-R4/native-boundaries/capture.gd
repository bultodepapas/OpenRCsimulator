extends SceneTree

const Fleet := preload("../../../research/native-kernel/fleet.gd")
const AIRCRAFT := "sebart-avanti-s-a200-p100rx"
const REFUSAL := "reset failed: runway start: idle support pose unresolved: bounded line search found no feasible descent step"

func _initialize() -> void:
	var fleet := Fleet.new()
	var selected := []
	var failures := []
	for row: Dictionary in Fleet._fleet_declared_rows():
		if row.aircraft == AIRCRAFT and row.battery == "ideal" and row.case == "runway" and row.weather == "crosswind":
			var reference: Dictionary = fleet._build_fleet_session(row, "gdscript_reference")
			var native: Dictionary = fleet._build_fleet_session(row, "native")
			selected.append({row = row, reference = reference, native = native})
			for result: Dictionary in [reference, native]:
				if result.get("ok", false):
					result.session.free()
					failures.append("unexpected successful start")
					continue
				if result.get("phase") != "reset" or result.get("reason") != REFUSAL:
					failures.append("reset refusal differs")
				var proof: Dictionary = result.get("startup_proof", {})
				for key: String in ["before_helper_absent", "after_helper_absent", "model_retained", "callbacks_retained", "reference_callbacks_before", "reference_callbacks_after", "kernel_guard_retained", "owner_guard_retained", "selection_valid_before", "selection_valid_after", "input_configuration_retained", "live_configuration_retained", "outcome_empty"]:
					if typeof(proof.get(key)) != TYPE_BOOL or not proof[key]:
						failures.append("missing retained invariant: " + key)
				if proof.get("before_frame_bytes_hex") != proof.get("frame_bytes_hex") or proof.get("before_live_config_bytes_hex") != proof.get("live_config_bytes_hex"):
					failures.append("before/after bytes differ")
				if proof.get("outcome_dictionary_empty") != false or proof.get("outcome_status") != "numerical_unresolved" or proof.get("outcome_ok") != false or proof.get("outcome_message") != REFUSAL.trim_prefix("reset failed: "):
					failures.append("unexpected runway outcome")
				for field: String in ["frame", "config", "outcome", "live_config"]:
					var encoded: String = proof.get(field + "_bytes_hex", "")
					if encoded.is_empty() or Fleet._fleet_encoded_sha256(encoded.hex_decode()) != proof.get(field + "_sha256"):
						failures.append("invalid typed digest: " + field)
			var ref: Dictionary = reference.get("startup_proof", {})
			var nat: Dictionary = native.get("startup_proof", {})
			for field: String in ["aircraft_sha256", "frame_bytes_hex", "config_bytes_hex", "outcome_bytes_hex", "live_config_bytes_hex"]:
				if ref.get(field) != nat.get(field): failures.append("paired request differs: " + field)
			print("AVANTI_BOUNDARY hull=%s reference=%s native=%s pins_match=%s" % [row.soft_hull, reference.get("reason"), native.get("reason"), Fleet._fleet_start_proof_valid(row, ref, "gdscript_reference")])
	if selected.size() != 2:
		failures.append("expected exactly two contact configurations")
	var output := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if output == null:
		failures.append("could not write evidence")
	else:
		output.store_string(JSON.stringify({format = "av17-r4-paired-start-observation v1", rows = selected, failures = failures}, "\t", true, true) + "\n")
		output.close()
	fleet.free()
	print("AVANTI_BOUNDARY_CAPTURE verdict=%s rows=%d failures=%d" % ["pass" if failures.is_empty() else "fail", selected.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
