# D11g: re-derive the Stik's ARP-referred Cmq, CLq and Cnr from its own local model.
# The source is the current R02 section-plane / dimensional-wake law at the 15 m/s level trim,
# neutral controls and settled instantaneous wing-wake source. This is model consistency, not flight calibration.
# Human table output is the default; append `-- --json` for a machine-readable report and `-- --check`
# to compare the rounded values plus provenance in the production aircraft JSON. `--report-file <path>`
# writes a pure JSON report without the engine's startup banner; the destination must not already exist.
# Run from the repository root with the current project: Godot --headless --path app --script <this file> -- --json
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Trim := preload("res://physics/trim.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const V := 15.0
const RHO := 1.225
const H := 0.05
const COEFFICIENT_KEYS := ["Cmq", "CLq", "Cnr"]
## Conservative solver inventory: every physics GDScript can be reached through the loader,
## trim/dynamics, or their transitive preloads. The file-backed inputs read during file loading
## are added explicitly; the aircraft JSON itself has a separate normalized input fingerprint.
const SOURCE_INPUT_FILES := [
	"app/data/ground/wheel_profiles.json",
	"app/project.godot",
	"research/aero/d11g/derive_rate_derivatives.gd",
]
const SOURCE_IDENTITY_SCHEME := "sha256-app-physics-gd-recursive-v2"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var json_only := false
	var check_data := false
	var report_file := ""
	var arg_index := 0
	while arg_index < args.size():
		var arg: String = args[arg_index]
		if arg == "--json":
			json_only = true
		elif arg == "--check":
			check_data = true
		elif arg == "--report-file":
			if arg_index + 1 >= args.size():
				push_error("--report-file requires an absolute destination path")
				quit(2)
				return
			report_file = args[arg_index + 1]
			arg_index += 1
		else:
			push_error("Unsupported user argument: %s (use -- --json, --check, and/or --report-file <path>)" % arg)
			quit(2)
			return
		arg_index += 1
	if not report_file.is_empty() and not json_only:
		push_error("--report-file requires --json")
		quit(2)
		return
	if not report_file.is_empty() and not report_file.is_absolute_path():
		push_error("--report-file requires an absolute destination path")
		quit(2)
		return
	var source_before := _source_identity()
	if not bool(source_before.get("ok", false)):
		push_error("Cannot derive D11g rates: source identity failed before load: %s" % str(source_before.get("reason", "unknown")))
		quit(1)
		return
	var loaded: Dictionary = AD.load_file(PATH)
	if not bool(loaded.get("ok", false)):
		push_error("Cannot derive D11g rates: %s" % "; ".join(loaded.get("errors", PackedStringArray())))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var trim := Trim.solve("level", V, model, 9.80665, model.controls.throw_rad)
	if not bool(trim.get("ok", false)):
		push_error("Cannot derive D11g rates: level trim failed: %s" % str(trim.get("message", "unknown trim failure")))
		quit(1)
		return
	if not is_finite(float(trim.get("alpha", NAN))):
		push_error("Cannot derive D11g rates: level trim returned a nonfinite alpha")
		quit(1)
		return
	var alpha: float = trim.alpha
	var at_trim := _derivatives(model, alpha)
	var rx: float = -(float(model.reference.arp_le[0]) - float(model.cg_le[0]))
	var rz: float = -(float(model.reference.arp_le[2]) - float(model.cg_le[2]))
	var cmq_arp: float = at_trim.Cmq - at_trim.CLq * (rx * cos(alpha) + rz * sin(alpha)) / float(model.reference.c)
	var cnr_arp: float = at_trim.Cnr - float(model.aero.CYr) * rx / float(model.reference.b)
	var rounded := {
		"Cmq": _round_significant(cmq_arp),
		"CLq": _round_significant(at_trim.CLq),
		"Cnr": _round_significant(cnr_arp),
	}
	var provenance := _provenance(at_trim, rounded)
	var source_after := _source_identity()
	if not bool(source_after.get("ok", false)):
		push_error("Cannot derive D11g rates: source identity failed after derivation: %s" % str(source_after.get("reason", "unknown")))
		quit(1)
		return
	if source_before.get("scheme") != source_after.get("scheme") or source_before.get("files") != source_after.get("files"):
		push_error("Cannot derive D11g rates: solver or generator source changed during load/derivation")
		quit(1)
		return
	var source_identity: Dictionary = source_after
	var target_bytes: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	if target_bytes.is_empty():
		push_error("Cannot fingerprint D11g inputs: cannot reread aircraft JSON")
		quit(1)
		return
	var target_digest: HashingContext = HashingContext.new()
	target_digest.start(HashingContext.HASH_SHA256)
	target_digest.update(target_bytes)
	if target_digest.finish().hex_encode() != str(loaded.get("input_identity", {}).get("sha256", "")):
		push_error("Cannot fingerprint D11g inputs: aircraft JSON changed after the validated model was loaded")
		quit(1)
		return
	var fingerprint := _normalized_input_fingerprint(target_bytes.get_string_from_utf8())
	if not bool(fingerprint.get("ok", false)):
		push_error("Cannot fingerprint D11g inputs: %s" % str(fingerprint.get("reason", "unknown")))
		quit(1)
		return
	var sensitivity: Array[Dictionary] = []
	for deg in [0.0, 2.0, 4.0, 6.0]:
		var row := _derivatives(model, deg_to_rad(deg))
		sensitivity.append({
			"alpha_deg": deg,
			"Cmq_about_cg": row.Cmq,
			"CLq": row.CLq,
			"Cnr_about_cg": row.Cnr,
		})
	var report := {
		"schema": "d11g-rate-derivatives-v2",
		"aircraft_id": model.id,
		"law": Aero.LOADS_LAW,
		"derivation_identity": {
			"normalized_input": fingerprint,
			"solver_source_scheme": source_identity.scheme,
			"solver_sources": source_identity.files,
		},
		"condition": {
			"speed_mps": V,
			"density_kg_m3": RHO,
			"trim_alpha_rad": alpha,
			"trim_alpha_deg": rad_to_deg(alpha),
			"central_difference_step_rad_s": H,
			"controls": "neutral",
			"wake": "settled instantaneous Aero.wing_wake_velocity output; no ground effect",
		},
		"about_cg": {
			"Cmq": at_trim.Cmq,
			"CLq": at_trim.CLq,
			"Cnr": at_trim.Cnr,
		},
		"about_arp": {
			"Cmq": cmq_arp,
			"CLq": at_trim.CLq,
			"Cnr": cnr_arp,
		},
		"rounded_4_significant_digits": rounded,
		"provenance": provenance,
		"alpha_sensitivity_about_cg": sensitivity,
		"interpretation": "Reproduces this model's rate-derivative contract only; it is not physical validation.",
	}
	var check_issues := PackedStringArray()
	if check_data:
		check_issues = _check_stored_rates(rounded, provenance)
		report["data_check"] = {"passed": check_issues.is_empty(), "issues": check_issues}
	if not report_file.is_empty():
		if FileAccess.file_exists(report_file):
			push_error("Report destination already exists: %s" % report_file)
			quit(2)
			return
		var output := FileAccess.open(report_file, FileAccess.WRITE)
		if output == null:
			push_error("Cannot open report destination: %s" % report_file)
			quit(2)
			return
		output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
		output.close()
	if json_only and report_file.is_empty():
		print(JSON.stringify(report, "", true, true))
	elif not json_only:
		_print_human(report)
		if check_data:
			print("data check: %s" % ("current" if check_issues.is_empty() else "stale"))
			for issue in check_issues:
				push_error(issue)
	quit(1 if check_data and not check_issues.is_empty() else 0)


func _derivatives(model: Dictionary, alpha: float) -> Dictionary:
	var S: float = model.reference.S
	var b: float = model.reference.b
	var c: float = model.reference.c
	var qbar := 0.5 * RHO * V * V
	var qp := _local(model, alpha, 1, H)
	var qm := _local(model, alpha, 1, -H)
	var lift_p: float = qp[0] * sin(alpha) - qp[2] * cos(alpha)
	var lift_m: float = qm[0] * sin(alpha) - qm[2] * cos(alpha)
	var rp := _local(model, alpha, 2, H)
	var rm := _local(model, alpha, 2, -H)
	return {
		"Cmq": (qp[4] - qm[4]) / (2.0 * H) / (qbar * S * c * c / (2.0 * V)),
		"CLq": (lift_p - lift_m) / (2.0 * H) / (qbar * S * c / (2.0 * V)),
		"Cnr": (rp[5] - rm[5]) / (2.0 * H) / (qbar * S * b * b / (2.0 * V)),
	}


func _local(model: Dictionary, alpha: float, axis: int, rate: float) -> PackedFloat64Array:
	var state := PackedFloat64Array([0, 0, -100, V * cos(alpha), 0, V * sin(alpha), 1, 0, 0, 0, 0, 0, 0])
	state[10 + axis] = rate
	var controls := {"elevator": 0.0, "aileron_right": 0.0, "aileron_left": 0.0, "rudder": 0.0}
	var air: Dictionary = Air.compute(state, PackedFloat64Array([0, 0, 0]), RHO)
	var settled_wake: float = Aero.wing_wake_velocity(state, air, controls, model)
	return Aero._local_loads(state, air, controls, model, RHO, settled_wake)


func _check_stored_rates(rounded: Dictionary, provenance: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var text := FileAccess.get_file_as_string(PATH)
	var raw: Variant = JSON.parse_string(text)
	if typeof(raw) != TYPE_DICTIONARY:
		issues.append("aircraft JSON is not a dictionary")
		return issues
	var aero_raw: Dictionary = raw.get("aero", {})
	var coefficients: Dictionary = aero_raw.get("coefficients", {})
	for key in COEFFICIENT_KEYS:
		var entry: Dictionary = coefficients.get(key, {})
		if entry.is_empty():
			issues.append("missing aero.coefficients.%s" % key)
			continue
		if not entry.has("value") or float(entry.get("value", NAN)) != float(rounded[key]):
			issues.append("aero.coefficients.%s.value is %s; expected exact generated value %s" % [key, str(entry.get("value", "missing")), str(rounded[key])])
		if entry.get("unit", "") != "1/rad":
			issues.append("aero.coefficients.%s.unit must remain 1/rad" % key)
		if entry.get("kind", "") != "derived":
			issues.append("aero.coefficients.%s.kind must remain derived" % key)
		if entry.get("source", "") != provenance[key]:
			issues.append("aero.coefficients.%s.source does not match current-law provenance" % key)
	return issues


func _provenance(about_cg: Dictionary, rounded: Dictionary) -> Dictionary:
	var cmq_cg := _format_significant(float(about_cg.Cmq), 5)
	var clq_cg := _format_significant(float(about_cg.CLq), 5)
	var cnr_cg := _format_significant(float(about_cg.Cnr), 5)
	var cmq_arp := _format_significant(float(rounded.Cmq), 4)
	var cnr_arp := _format_significant(float(rounded.Cnr), 4)
	return {
		"Cmq": "research/aero/d11g/derive_rate_derivatives.gd (D11g/R02, ARP-referred since D6e-R1): current section-plane-source-weighted-wake-velocity-v2 local-law central difference at the 15 m/s level trim, controls neutral and dimensional wake settled. About-CG Cmq=%s and CLq=%s; ARP Cmq=%s includes the CLq lift arm. Model-derived, not measured or physically validated." % [cmq_cg, clq_cg, cmq_arp],
		"CLq": "research/aero/d11g/derive_rate_derivatives.gd (D11g/R02, ARP-referred since D6e-R1): current section-plane-source-weighted-wake-velocity-v2 local-law central difference at the 15 m/s level trim, controls neutral and dimensional wake settled. About-CG CLq=%s. Model-derived, not measured or physically validated." % clq_cg,
		"Cnr": "research/aero/d11g/derive_rate_derivatives.gd (D11g/R02, ARP-referred since D6e-R1): current section-plane-source-weighted-wake-velocity-v2 local-law central difference at the 15 m/s level trim, controls neutral and dimensional wake settled. About-CG Cnr=%s; ARP Cnr=%s includes the CYr side-force arm. Model-derived, not measured or physically validated." % [cnr_cg, cnr_arp],
	}


func _source_identity() -> Dictionary:
	var files: Array[Dictionary] = []
	var relative_paths: Array[String] = []
	var inventory_error := _collect_physics_sources("res://physics", "app/physics", relative_paths)
	if not inventory_error.is_empty():
		return {ok = false, reason = inventory_error}
	for relative_path in SOURCE_INPUT_FILES:
		relative_paths.append(relative_path)
	relative_paths.sort()
	for relative_path in relative_paths:
		var resource_path: String = "res://" + relative_path.substr(4) if relative_path.begins_with("app/") \
			else "res://../" + relative_path
		var absolute_path: String = ProjectSettings.globalize_path(resource_path)
		if not FileAccess.file_exists(absolute_path):
			return {ok = false, reason = "missing source file %s (resolved %s)" % [relative_path, absolute_path]}
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(absolute_path)
		if bytes.is_empty():
			return {ok = false, reason = "cannot read source file %s" % relative_path}
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		files.append({path = relative_path, sha256 = digest.finish().hex_encode()})
	return {ok = true, scheme = SOURCE_IDENTITY_SCHEME, files = files}


func _collect_physics_sources(resource_directory: String, report_directory: String,
		out: Array[String]) -> String:
	var directory := DirAccess.open(resource_directory)
	if directory == null:
		return "cannot enumerate solver source directory %s" % resource_directory
	for file_name in directory.get_files():
		if file_name.get_extension().to_lower() == "gd":
			out.append(report_directory.path_join(file_name))
	for child_name in directory.get_directories():
		var child_error := _collect_physics_sources(resource_directory.path_join(child_name),
			report_directory.path_join(child_name), out)
		if not child_error.is_empty():
			return child_error
	return ""


func _normalized_input_fingerprint(text: String) -> Dictionary:
	var root_open := text.find("{")
	if root_open < 0:
		return {ok = false, reason = "input JSON has no object"}
	var root_close := _json_object_end(text, root_open)
	if root_close < 0:
		return {ok = false, reason = "input JSON root object is malformed"}
	var aero_span := _member_object_span(text, root_open, root_close, "aero")
	if not aero_span.ok:
		return {ok = false, reason = str(aero_span.reason)}
	var coeff_span := _member_object_span(text, aero_span.open, aero_span.close, "coefficients")
	if not coeff_span.ok:
		return {ok = false, reason = str(coeff_span.reason)}
	var normalized := text
	for key in COEFFICIENT_KEYS:
		# Recompute all spans after each edit: the sentinel length differs from the output leaf.
		root_open = normalized.find("{")
		root_close = _json_object_end(normalized, root_open)
		aero_span = _member_object_span(normalized, root_open, root_close, "aero")
		coeff_span = _member_object_span(normalized, aero_span.open, aero_span.close, "coefficients")
		var record_span := _member_object_span(normalized, coeff_span.open, coeff_span.close, key)
		if not record_span.ok:
			return {ok = false, reason = str(record_span.reason)}
		var record_text := normalized.substr(record_span.open, record_span.close - record_span.open + 1)
		var value_pattern := RegEx.new()
		var source_pattern := RegEx.new()
		if value_pattern.compile('("value"\\s*:\\s*)(-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?)') != OK:
			return {ok = false, reason = "could not compile value normalizer"}
		if source_pattern.compile('("source"\\s*:\\s*)("(?:\\\\.|[^"\\\\])*")') != OK:
			return {ok = false, reason = "could not compile source normalizer"}
		var value_matches := value_pattern.search_all(record_text)
		var source_matches := source_pattern.search_all(record_text)
		if value_matches.size() != 1 or source_matches.size() != 1:
			return {ok = false, reason = "expected one value/source leaf in aero.coefficients.%s" % key}
		var value_match: RegExMatch = value_matches[0]
		var source_match: RegExMatch = source_matches[0]
		record_text = record_text.substr(0, value_match.get_start(2)) + "\"__D11G_OUTPUT_VALUE__\"" \
			+ record_text.substr(value_match.get_end(2))
		# The value substitution changes later offsets in this object; find the source token again.
		source_matches = source_pattern.search_all(record_text)
		if source_matches.size() != 1:
			return {ok = false, reason = "lost source leaf in aero.coefficients.%s" % key}
		source_match = source_matches[0]
		record_text = record_text.substr(0, source_match.get_start(2)) + "\"__D11G_OUTPUT_SOURCE__\"" \
			+ record_text.substr(source_match.get_end(2))
		normalized = normalized.substr(0, record_span.open) + record_text + normalized.substr(record_span.close + 1)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(normalized.to_utf8_buffer())
	return {
		ok = true,
		scheme = "utf8-source-text-v1",
		sha256 = digest.finish().hex_encode(),
		excluded_leaves = [
			"aero.coefficients.Cmq.value", "aero.coefficients.Cmq.source",
			"aero.coefficients.CLq.value", "aero.coefficients.CLq.source",
			"aero.coefficients.Cnr.value", "aero.coefficients.Cnr.source",
		],
	}


func _member_object_span(text: String, parent_open: int, parent_close: int, key: String) -> Dictionary:
	if parent_open < 0 or parent_close <= parent_open:
		return {ok = false, reason = "invalid parent span while locating %s" % key}
	var body := text.substr(parent_open + 1, parent_close - parent_open - 1)
	var matcher := RegEx.new()
	if matcher.compile('"' + key + '"\\s*:\\s*\\{') != OK:
		return {ok = false, reason = "could not compile JSON member matcher for %s" % key}
	var matches := matcher.search_all(body)
	if matches.size() != 1:
		return {ok = false, reason = "expected one JSON object member %s, found %d" % [key, matches.size()]}
	var open_index: int = parent_open + 1 + matches[0].get_end() - 1
	var close_index := _json_object_end(text, open_index)
	if close_index < 0 or close_index > parent_close:
		return {ok = false, reason = "malformed JSON object member %s" % key}
	return {ok = true, open = open_index, close = close_index}


func _json_object_end(text: String, open_index: int) -> int:
	if open_index < 0 or open_index >= text.length() or text.substr(open_index, 1) != "{":
		return -1
	var depth := 0
	var in_string := false
	var escaped := false
	for index in range(open_index, text.length()):
		var character := text.substr(index, 1)
		if in_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				in_string = false
		elif character == "\"":
			in_string = true
		elif character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index
	return -1


func _round_significant(value: float) -> float:
	return float(_format_significant(value, 4))


func _format_significant(value: float, significant_digits: int) -> String:
	return String.num(value, significant_digits - _digits(value))


func _digits(value: float) -> int:
	return int(floor(log(absf(value)) / log(10.0))) + 1


func _print_human(report: Dictionary) -> void:
	var condition: Dictionary = report.condition
	var cg: Dictionary = report.about_cg
	var arp: Dictionary = report.about_arp
	var rounded: Dictionary = report.rounded_4_significant_digits
	print("15 m/s level trim: α %.3f°; law %s" % [condition.trim_alpha_deg, report.law])
	print("| α° | Cmq about CG | CLq | Cnr about CG |")
	for row in report.alpha_sensitivity_about_cg:
		print("| %.0f | %.4f | %.4f | %.5f |" % [row.alpha_deg, row.Cmq_about_cg, row.CLq, row.Cnr_about_cg])
	print("about CG at trim: Cmq %.5f, CLq %.5f, Cnr %.5f" % [cg.Cmq, cg.CLq, cg.Cnr])
	print("about ARP at trim: Cmq %.5f, CLq %.5f, Cnr %.5f" % [arp.Cmq, arp.CLq, arp.Cnr])
	print("4 significant digits to store: Cmq %s, CLq %s, Cnr %s" % [str(rounded.Cmq), str(rounded.CLq), str(rounded.Cnr)])
	print("This is a model consistency derivation, not physical validation.")
