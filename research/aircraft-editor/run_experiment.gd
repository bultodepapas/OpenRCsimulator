extends SceneTree
## Read-only Workshop analysis CLI. The only write is the explicitly selected --out file.

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Trial := preload("res://workshop/trial.gd")
const Bundle := preload("res://workshop/bundle.gd")
const StrictJSON := preload("res://workshop/strict_json.gd")
const Experiments := preload("res://workshop/experiments.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

const REPORT_FORMAT: String = "openrc-aircraft-workshop-analysis"
const REPORT_VERSION: int = 1
const MAX_JSON_BYTES: int = 1048576
const MAX_JSON_DEPTH: int = 32
const MAX_JSON_NODES: int = 20000
const OPTION_KEYS: PackedStringArray = ["aircraft", "bundle", "recipe", "sweep", "out"]
const USAGE: String = "Usage: Godot --headless --path app --script <run_experiment.gd> -- " \
	+ "(--aircraft=<catalog-id> | --bundle=<local-file>) [--recipe=<fixed-tape-json> | --sweep=<sweep-json>] --out=<new-local-json>"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed_options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if not bool(parsed_options.get("ok", false)):
		_fail(str(parsed_options.get("error", "Invalid command line.")))
		return
	var options: Dictionary = parsed_options["options"]
	if options.has("help"):
		print(USAGE)
		quit(0)
		return
	if not options.has("out") or str(options.out).is_empty():
		_fail("--out=<new-local-json> is required.")
		return
	var has_aircraft: bool = options.has("aircraft")
	var has_bundle: bool = options.has("bundle")
	if has_aircraft == has_bundle:
		_fail("Choose exactly one source: --aircraft=<catalog-id> or --bundle=<local-file>.")
		return
	if options.has("recipe") and options.has("sweep"):
		_fail("Choose at most one analysis input: --recipe or --sweep.")
		return
	var output_path: String = _local_path(str(options.out))
	if output_path.is_empty():
		_fail("--out must be a local filesystem path, not a resource URI.")
		return
	if FileAccess.file_exists(output_path):
		_fail("Refusing to overwrite an existing output file: " + output_path)
		return
	var input_paths: Array[String] = []
	var base_id: String = ""
	var base_bytes := PackedByteArray()
	var base: Dictionary = {}
	var physical_recipe: Dictionary = {}
	var freeze_payload: Dictionary = {}
	var bundle_payload: Dictionary = {}
	if has_aircraft:
		base_id = str(options.aircraft)
		if not Catalog.has(base_id) or not Catalog.can_fly(base_id) or Catalog.is_rotorcraft(base_id):
			_fail("Unknown, unavailable, or non-airplane catalog ID: " + base_id)
			return
		var entry: Dictionary = Catalog.entry(base_id)
		var catalog_path: String = str(entry.get("data", ""))
		var catalog_read: Dictionary = _read_file_bytes(catalog_path, Descriptor.MAX_BASE_BYTES)
		if not bool(catalog_read.get("ok", false)):
			_fail("Catalog aircraft source could not be read: " + base_id + ". "
				+ "; ".join(catalog_read.get("errors", [])))
			return
		base_bytes = catalog_read["bytes"]
		input_paths.append(ProjectSettings.globalize_path(catalog_path))
		var parsed_base: Dictionary = _decode_object(base_bytes, Descriptor.MAX_BASE_BYTES, 64, 250000)
		if not bool(parsed_base.get("ok", false)):
			_fail("Catalog aircraft JSON is invalid: " + "; ".join(parsed_base.get("errors", [])))
			return
		base = parsed_base["data"]
		freeze_payload = {"base_id": base_id, "base_bytes": base_bytes, "recipe": {}}
	else:
		var bundle_path: String = _local_path(str(options.bundle))
		if bundle_path.is_empty():
			_fail("--bundle must name a local file path.")
			return
		input_paths.append(bundle_path)
		var bundle_read: Dictionary = Bundle.read_file(bundle_path)
		if not bool(bundle_read.get("ok", false)):
			_fail("Portable variant bundle is invalid: " + "; ".join(bundle_read.get("errors", [])))
			return
		bundle_payload = bundle_read["payload"]
		base_id = str(bundle_payload.get("base_id", ""))
		base_bytes = bundle_payload.get("base_bytes", PackedByteArray())
		base = bundle_payload.get("base", {})
		physical_recipe = bundle_payload.get("recipe", {}).duplicate(true)
		freeze_payload = bundle_payload.duplicate(true)
	if typeof(base) != TYPE_DICTIONARY or base.is_empty() or base_bytes.is_empty():
		_fail("Resolved aircraft source is empty or invalid.")
		return
	for option_key: String in ["recipe", "sweep"]:
		if not options.has(option_key):
			continue
		var input_path: String = _local_path(str(options[option_key]))
		if input_path.is_empty():
			_fail("--%s must name a local JSON file." % option_key)
			return
		input_paths.append(input_path)
	var collision: String = _input_output_collision(output_path, input_paths)
	if not collision.is_empty():
		_fail("Output path would overwrite an input file: " + collision)
		return
	var recipe_value: Dictionary = {}
	var sweep_value: Dictionary = {}
	if options.has("recipe"):
		var recipe_json: Dictionary = _read_json_object(_local_path(str(options.recipe)))
		if not bool(recipe_json.get("ok", false)):
			_fail("Fixed-tape recipe JSON is invalid: " + "; ".join(recipe_json.get("errors", [])))
			return
		recipe_value = recipe_json["data"]
		var checked_recipe: Dictionary = Experiments.validate_recipe(recipe_value)
		if not bool(checked_recipe.get("ok", false)):
			_fail("Fixed-tape recipe is unsupported: " + "; ".join(checked_recipe.get("errors", [])))
			return
		recipe_value = checked_recipe["recipe"]
	if options.has("sweep"):
		var sweep_json: Dictionary = _read_json_object(_local_path(str(options.sweep)))
		if not bool(sweep_json.get("ok", false)):
			_fail("Sweep JSON is invalid: " + "; ".join(sweep_json.get("errors", [])))
			return
		sweep_value = sweep_json["data"]
		if not physical_recipe.is_empty():
			var base_recipe: Dictionary = physical_recipe.duplicate(true)
			base_recipe.merge(sweep_value.get("recipe", {}), true)
			sweep_value["recipe"] = base_recipe
		var checked_sweep: Dictionary = Experiments.validate_sweep(sweep_value)
		if not bool(checked_sweep.get("ok", false)):
			_fail("Sweep specification is unsupported: " + "; ".join(checked_sweep.get("errors", [])))
			return
		sweep_value = checked_sweep["spec"]
	var frozen: Dictionary = Trial.freeze(freeze_payload)
	if not bool(frozen.get("ok", false)):
		_fail("Selected source could not be frozen as a current Workshop Trial: " + "; ".join(frozen.get("errors", [])))
		return
	var analysis_kind: String = "static_report"
	var analysis: Dictionary
	if options.has("recipe"):
		analysis_kind = "fixed_tape"
		analysis = Experiments.run_fixed_tape(frozen, recipe_value)
	elif options.has("sweep"):
		analysis_kind = "sweep"
		analysis = Experiments.sweep(base, sweep_value)
	else:
		analysis = Experiments.static_report(base, physical_recipe)
	var solver_sha256: String = FlightLog.solver_identity()
	var build: Dictionary = BuildInfo.current()
	var analysis_ok: bool = bool(analysis.get("ok", false))
	var report: Dictionary = {
		"format": REPORT_FORMAT,
		"version": REPORT_VERSION,
		"status": "ok" if analysis_ok else "unsupported",
		"analysis_kind": analysis_kind,
		"source": {"kind": "bundle" if has_bundle else "catalog", "aircraft_id": base_id},
		"frozen_trial": {
			"physical_identity": frozen.identity.duplicate(true),
			"presentation_profile": frozen.presentation_profile.duplicate(true),
			"presentation_identity": frozen.presentation_identity.duplicate(true),
			"compiler_version": str(frozen.identity.get("compiler", "")),
			"resolved_model_sha256": str(frozen.identity.get("resolved_model_sha256", "")),
		},
		"source_identity": {"solver_sha256": solver_sha256, "build": build.duplicate(true)},
		"analysis": analysis,
	}
	var write: Dictionary = _write_report(output_path, report)
	if not bool(write.get("ok", false)):
		_fail(str(write.get("error", "Analysis output could not be written.")))
		return
	print("Workshop %s report written: %s" % [analysis_kind, output_path])
	if analysis_ok:
		quit(0)
	else:
		printerr("The frozen trial was recorded as unsupported by this analysis request.")
		quit(3)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options: Dictionary = {}
	for argument: String in arguments:
		if argument == "--help":
			if not options.is_empty():
				return {"ok": false, "error": "--help cannot be combined with other options."}
			options["help"] = true
			continue
		if not argument.begins_with("--"):
			return {"ok": false, "error": "Unexpected positional argument: " + argument}
		var equals: int = argument.find("=")
		if equals < 3:
			return {"ok": false, "error": "Every option must use --name=value syntax."}
		var key: String = argument.substr(2, equals - 2)
		var value: String = argument.substr(equals + 1)
		if not OPTION_KEYS.has(key):
			return {"ok": false, "error": "Unknown option: --" + key}
		if options.has(key):
			return {"ok": false, "error": "Duplicate option: --" + key}
		if value.is_empty():
			return {"ok": false, "error": "Option --%s cannot be empty." % key}
		options[key] = value
	return {"ok": true, "options": options}


func _decode_object(bytes: PackedByteArray, max_bytes: int, max_depth: int, max_nodes: int) -> Dictionary:
	var decoded: Dictionary = StrictJSON.parse(bytes, max_bytes, max_depth, max_nodes)
	if not bool(decoded.get("ok", false)):
		return decoded
	if typeof(decoded.get("data", null)) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["JSON root value must be an object."])}
	return decoded


func _read_json_object(path: String) -> Dictionary:
	var read: Dictionary = _read_file_bytes(path, MAX_JSON_BYTES)
	if not bool(read.get("ok", false)):
		return read
	return _decode_object(read["bytes"], MAX_JSON_BYTES, MAX_JSON_DEPTH, MAX_JSON_NODES)


func _read_file_bytes(path: String, max_bytes: int) -> Dictionary:
	if path.is_empty():
		return {"ok": false, "errors": PackedStringArray(["Local file path is empty."])}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "errors": PackedStringArray(["Local file could not be opened (%d)." % FileAccess.get_open_error()])}
	var length: int = file.get_length()
	if length <= 0 or length > max_bytes:
		file.close()
		return {"ok": false, "errors": PackedStringArray(["Local file is empty or exceeds the %d-byte limit." % max_bytes])}
	var bytes: PackedByteArray = file.get_buffer(length)
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK or bytes.size() != length:
		return {"ok": false, "errors": PackedStringArray(["Local file could not be read completely."])}
	return {"ok": true, "errors": PackedStringArray(), "bytes": bytes}


func _local_path(path: String) -> String:
	if path.is_empty() or path.contains("://") or path.to_utf8_buffer().has(0):
		return ""
	var normalized: String = path.replace("\\", "/")
	if normalized.is_absolute_path():
		return normalized.simplify_path()
	var root_path: String = ProjectSettings.globalize_path("res://")
	return root_path.path_join(normalized).simplify_path()


func _input_output_collision(output_path: String, inputs: Array[String]) -> String:
	for input_path: String in inputs:
		if _same_path(output_path, input_path):
			return input_path
	return ""


func _same_path(left: String, right: String) -> bool:
	var normalized_left: String = left.simplify_path()
	var normalized_right: String = right.simplify_path()
	if OS.get_name() == "Windows":
		return normalized_left.to_lower() == normalized_right.to_lower()
	return normalized_left == normalized_right


func _write_report(path: String, report: Dictionary) -> Dictionary:
	var parent: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		var make_result: Error = DirAccess.make_dir_recursive_absolute(parent)
		if make_result != OK:
			return {"ok": false, "error": "Could not create the selected output directory (%d)." % make_result}
	var text: String = JSON.stringify(report, "\t", true, true) + "\n"
	var bytes: PackedByteArray = text.to_utf8_buffer()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Could not open the selected output file (%d)." % FileAccess.get_open_error()}
	file.store_buffer(bytes)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or not FileAccess.file_exists(path):
		return {"ok": false, "error": "The selected output file was not written completely."}
	return {"ok": true, "bytes": bytes.size()}


func _fail(message: String) -> void:
	printerr(message)
	printerr(USAGE)
	quit(2)
