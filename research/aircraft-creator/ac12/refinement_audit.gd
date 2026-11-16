extends "campaign.gd"
## AC-12 current-source measurement, never a flight-qualification decision. The historical
## cases, tapes, metrics, floors and verdict implementation remain unchanged in campaign.gd.
const Bytes := preload("res://workshop/creator/bytes.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const LogReader := preload("res://tools/flight_log_cli.gd")
const LegacyCampaign := preload("campaign.gd")
const FORMAT := "openrc-ac12-refinement-audit v1"
const ROW_WIDTH := RB.SIZE + 4
const SAMPLE_COUNT := 1440
const CALIBRATION_RATES := [240,480,960,960,1920,1920,3840]
const CELLS := ["C01/pitch_doublet","C02/roll_doublet","C02/throttle_step","C04/roll_doublet","C15/roll_doublet"]
const SOURCE_FILES := ["res://workshop/creator/compiler.gd","res://workshop/creator/definition.gd",
	"res://workshop/creator/packages.gd","res://workshop/creator/record_loader.gd",
	"res://data/creator/airframe-conventional-trainer-estimated-v1.json",
	"res://data/creator/power-electric-4s-800kv-apc12x6-estimated-v1.json"]
var _out := ""
var _first_runs := {}
var _run_number := 0


## Subclasses can select one preregistered cell for an admitted, independent checked job.
func specification() -> Dictionary:
	return {case_id = "C01",tape = "pitch_doublet",calibrate = false}


## An explicitly versioned campaign may choose a different, fixed registration.
## The original audit keeps its five cells and historical compiler inputs.
func registered_cells() -> Array:
	return CELLS.duplicate()


func audited_definition(value: Dictionary) -> Dictionary:
	return value


func candidate_is_admitted(_candidate: RefCounted,_definition: Dictionary) -> bool:
	return true


func session_is_admitted(_session: Node,_candidate: RefCounted) -> bool:
	return true


func baseline_replay_is_admitted(_report: Dictionary) -> bool:
	return true


func _initialize() -> void:
	_run_audit.call_deferred()


func _run_audit() -> void:
	var spec := specification()
	var bad_option := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
		elif argument.begins_with("--case="):
			spec.case_id = argument.trim_prefix("--case=")
		elif argument.begins_with("--tape="):
			spec.tape = argument.trim_prefix("--tape=")
		elif argument == "--calibrate":
			spec.calibrate = true
		else:
			bad_option = true
	if bad_option or not valid_specification(spec,registered_cells()):
		_fail("unknown option or cell outside the registered audit")
		return
	if _out.is_empty():
		_out = "user://ac12-audit/%s-%s" % [spec.case_id,spec.tape]
	_out = ProjectSettings.globalize_path(_out)
	if not valid_output_location(_out,ProjectSettings.globalize_path("res://")):
		_fail("output must be absolute and outside the application source")
		return
	if DirAccess.dir_exists_absolute(_out):
		var existing := DirAccess.open(_out)
		if existing == null or not existing.get_files().is_empty() or not existing.get_directories().is_empty():
			_fail("output must be new or empty")
			return
	if DirAccess.make_dir_recursive_absolute(_out) != OK:
		_fail("cannot create output directory")
		return
	var previous_rate := Engine.physics_ticks_per_second
	Variants = load(_folder().path_join("variants.gd"))
	var definition := {}
	for entry: Array in _cases():
		if entry[0] == spec.case_id:
			definition = entry[2]
	definition = audited_definition(definition)
	var compiled := Compiler.compile_candidate(definition)
	if not compiled.ok:
		_fail("case refused: "+str(R.texts(compiled)))
		return
	var candidate: RefCounted = compiled.value
	if not candidate_is_admitted(candidate,definition):
		_fail("registered candidate admission failed")
		return
	var canonical := Definition.validate_complete(definition)
	var encoded_definition := Bytes.encode(canonical.value) if canonical.ok else {ok = false}
	if not encoded_definition.ok or encoded_definition.value.sha256 != candidate.definition_sha256() \
			or not _write(_out.path_join("definition.json"),encoded_definition.value.bytes) \
			or not _write(_out.path_join("aircraft-record.json"),candidate.raw_bytes()) \
			or FileAccess.get_sha256(_out.path_join("aircraft-record.json")) != candidate.raw_sha256():
		_fail("cannot retain exact compiler inputs/outputs")
		return
	var context := _source_context()
	if not valid_context(context):
		_fail("source identity unavailable")
		return
	var report := {format = FORMAT,flight_qualified = false,complete = false,
		specification = spec,context = context,record_sha256 = candidate.raw_sha256(),
		definition_sha256 = candidate.definition_sha256(),sample_hz = SAMPLE_HZ,duration_s = DURATION_S,
		runs = [],pairs = [],repeats = [],legacy_rule = {},legacy_interpretable = false}
	var rates: Array = CALIBRATION_RATES if spec.calibrate else Array(RATES)
	var complete := true
	var by_rate := {}
	for rate: int in rates:
		var captured := _capture(candidate,str(spec.tape),rate)
		report.runs.append(_run_receipt(captured))
		if not captured.ok:
			complete = false
			break
		if not by_rate.has(rate):
			by_rate[rate] = captured
			_first_runs[rate] = captured
		else:
			var difference := checked_differences(by_rate[rate].samples,captured.samples)
			if not difference.ok:
				complete = false
				break
			report.repeats.append({rate_hz = rate,initial_equal = captured.initial_sha256 == by_rate[rate].initial_sha256,
				samples_equal = captured.samples_sha256 == by_rate[rate].samples_sha256,
				final_equal = captured.final_sha256 == by_rate[rate].final_sha256,
				commands_equal = captured.commands_sha256 == by_rate[rate].commands_sha256,
				differences = difference.metrics})
	if complete:
		var levels: Array = [240,480,960,1920,3840] if spec.calibrate else [240,480,960]
		for index: int in levels.size()-1:
			var a: Dictionary = by_rate[levels[index]]
			var b: Dictionary = by_rate[levels[index+1]]
			var difference := checked_differences(a.samples,b.samples)
			if not difference.ok:
				complete = false
				break
			report.pairs.append({coarse_hz = levels[index],fine_hz = levels[index+1],
				initial_equal = a.initial_sha256 == b.initial_sha256,
				context_equal = a.environment_sha256 == b.environment_sha256,
				commands_equal = a.edges_sha256 == b.edges_sha256,
				differences = difference.metrics})
	if complete:
		# Base _refine calls our cache-only _fly: these are exactly the sampled flights above.
		report.legacy_rule = _refine(candidate,str(spec.tape))
		report.legacy_interpretable = report.pairs.all(func(pair: Dictionary) -> bool:
			return pair.initial_equal and pair.context_equal and pair.commands_equal)
		report.complete = _source_context() == context
	Engine.physics_ticks_per_second = previous_rate
	var encoded := Bytes.encode(report,4*1024*1024)
	if not encoded.ok or not _write(_out.path_join("audit.json"),encoded.value.bytes if encoded.ok else PackedByteArray()):
		_fail("cannot persist audit report")
		return
	print("AC12 audit report: ",_out.path_join("audit.json"))
	print("AC12 audit SHA256: ",encoded.value.sha256)
	print("AC12 audit complete=%s flight_qualified=false" % str(report.complete))
	quit(0 if report.complete else 1)


static func valid_specification(value: Dictionary,allowed: Array = CELLS) -> bool:
	return value.size() == 3 and typeof(value.get("case_id")) == TYPE_STRING \
		and typeof(value.get("tape")) == TYPE_STRING and typeof(value.get("calibrate")) == TYPE_BOOL \
		and (value.case_id+"/"+value.tape) in allowed \
		and (not value.calibrate or (value.case_id+"/"+value.tape) in CELLS)


## Called after resolving user://; relative paths cannot bypass the source-tree check.
static func valid_output_location(path: String,project_path: String) -> bool:
	if not path.is_absolute_path() or not project_path.is_absolute_path():
		return false
	var output := path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")+"/"
	var project := project_path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")+"/"
	return not output.begins_with(project)


## A complete, exactly replayed prefix is still insufficient for this fixed-duration baseline.
static func full_baseline_replay(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field: String in ["rows","first_tick","final_tick"]:
		if typeof(value.get(field)) != TYPE_INT:
			return false
	return value.get("status") == "ok" and value.get("complete") == true \
		and value.get("solver_changed") == false and value.get("mode") == "exact" \
		and value.first_tick == 0 and value.final_tick == SAMPLE_COUNT and value.rows == SAMPLE_COUNT+1


func _folder() -> String:
	var owner: Script = get_script()
	while owner != null and owner.get_base_script() != LegacyCampaign:
		owner = owner.get_base_script()
	return owner.resource_path.get_base_dir() if owner != null else ""


func _source_context() -> Dictionary:
	var sources := {}
	var paths: Array[String] = ["res://project.godot"]
	_collect_sources("res://",paths)
	paths.sort()
	for path: String in paths:
		sources[path] = FileAccess.get_sha256(path)
	for file_name: String in ["campaign.gd","variants.gd","refinement_audit.gd"]:
		sources[file_name] = FileAccess.get_sha256(_folder().path_join(file_name))
	return {engine = Engine.get_version_info().string,os = OS.get_name(),architecture = Engine.get_architecture_name(),
		engine_sha256 = FileAccess.get_sha256(OS.get_executable_path()),
		encoding_probe = PackedFloat64Array([1.0]).to_byte_array().hex_encode(),
		solver_sha256 = FlightLog._solver_identity_uncached(),sources = sources,
		entrypoint_sha256 = FileAccess.get_sha256((get_script() as Script).resource_path),
		legacy_tolerances = TOLERANCES,legacy_floors = FLOORS,legacy_max_ratio = MAX_RATIO,
		sample_encoding = "row-major IEEE754 binary64 little endian; no header",row_width = ROW_WIDTH}


static func valid_context(context: Dictionary) -> bool:
	if not Bytes.is_sha256(context.get("solver_sha256")) or not Bytes.is_sha256(context.get("entrypoint_sha256")) \
			or not Bytes.is_sha256(context.get("engine_sha256")) or context.get("encoding_probe") != "000000000000f03f":
		return false
	if not context.get("sources") is Dictionary:
		return false
	for required: String in SOURCE_FILES+[
		"res://tools/flight_log_cli.gd","res://workshop/creator/accepted_candidate.gd","res://workshop/creator/bytes.gd"]:
		if not context.sources.has(required):
			return false
	for value: Variant in context.sources.values():
		if not Bytes.is_sha256(value):
			return false
	return true


static func _collect_sources(folder: String,paths: Array[String]) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension() in ["gd","json"]:
			paths.append(folder.path_join(file_name))
	for child: String in directory.get_directories():
		if not child.begins_with("."):
			_collect_sources(folder.path_join(child),paths)


## Only the inherited verdict reads this method. No extra, unrecorded flights are permitted.
func _fly(_candidate: RefCounted,_tape_name: String,rate: int) -> Dictionary:
	return _first_runs.get(rate,{ok = false,fault = "audit cache missing",samples = []})


func _capture(candidate: RefCounted,tape_name: String,rate: int) -> Dictionary:
	Engine.physics_ticks_per_second = rate
	var session: Node = Session.new()
	var result := {ok = false,fault = "",rate_hz = rate,samples = [],edges = [],run_index = _run_number}
	_run_number += 1
	if not session.setup_stage_backend("gdscript_reference"):
		result.fault = "reference backend selection failed"
		session.free()
		return result
	session.physics_enabled = true
	session.input_enabled = false
	session.rate_profile = "full"
	session.crash_auto_restart = false
	session.start_choice = Session.START_AIRBORNE
	session.setup("",candidate.aircraft_id(),candidate.flight_data())
	if not session.is_flyable() or session.stage_backend_identity() != {backend = "gdscript_reference"} \
			or session.sim.dt() != 1.0/float(rate) or session.sim.tick != 0 or not session.weather_is_calm() \
			or not session_is_admitted(session,candidate):
		result.fault = "start/backend/clock/calm-weather invariant failed: "+session.start_error
		session.free()
		return result
	result.backend = session.stage_backend_status()
	result.dt_s = session.sim.dt()
	result.shaft_integrator = session.shaft_integrator()
	result.environment_sha256 = Bytes.sha256(var_to_bytes({weather = session.weather_configuration(),
		field = session.ground_field_id,ground = session.ground_surfaces,collision = session.collision_world(),
		lake = session.lake_context(),backend = session.stage_backend_identity(),shaft = session.shaft_integrator()}))
	result.initial_sha256 = _frame_digest(session)
	result.initial_frame = _frame_description(session)
	result.trim_rpm = float(session.start.rpm)
	result.trim_speed = float(session.start.V)
	var trimmed: PackedFloat64Array = session.sim.inputs.duplicate()
	if trimmed.size() != 4 or not _finite(trimmed):
		result.fault = "unexpected trimmed input layout"
		session.free()
		return result
	var command_hash := HashingContext.new()
	command_hash.start(HashingContext.HASH_SHA256)
	var previous_inputs := PackedByteArray()
	var logger: RefCounted = null
	var log_path := _out.path_join("baseline-240.orfl")
	if rate == 240:
		logger = FlightLog.new(session)
		if logger.start(log_path) != OK:
			result.fault = "baseline recording failed"
	for tick: int in int(DURATION_S*rate):
		if not result.fault.is_empty():
			break
		var inputs := super._tape(tape_name,float(tick)/float(rate),trimmed)
		if not _finite(inputs):
			result.fault = "nonfinite command"
			break
		var input_bytes := _pack([inputs])
		if input_bytes != previous_inputs:
			result.edges.append({tick = tick,time_s = float(tick)/float(rate),inputs_hex = _hex(inputs)})
			previous_inputs = input_bytes
		command_hash.update(input_bytes)
		session.sim.inputs = inputs
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or not Session.Sim.state_is_valid(session.sim.state) \
				or session.sim.tick != tick+1 or session.sim.dt() != result.dt_s \
				or absf(session.sim.time()-float(tick+1)/float(rate)) > 1e-12:
			result.fault = "fault or clock mismatch at tick %d: %s" % [tick,session.sim.fault_reason]
			break
		if (tick+1) % int(rate/SAMPLE_HZ) == 0:
			var row: PackedFloat64Array = session.sim.state.duplicate()
			var electric: Dictionary = session.electrical_state()
			row.append(float(session.air_data(session.sim.state).V))
			row.append(float(session.sim.aux[Session.AUX_RPM]))
			row.append(float(electric.get("pack_current_a",electric.get("battery_current_a",NAN))))
			row.append(float(electric.get("consumed_charge_c",NAN)))
			result.samples.append(row)
	result.final_tick = session.sim.tick
	result.final_sha256 = _frame_digest(session)
	result.commands_sha256 = command_hash.finish().hex_encode()
	var canonical_edges := []
	for edge: Dictionary in result.edges:
		canonical_edges.append({time_hex = _hex(PackedFloat64Array([edge.time_s])),inputs_hex = edge.inputs_hex})
	result.edges_sha256 = Bytes.sha256(var_to_bytes(canonical_edges))
	if result.fault.is_empty():
		result.fault = validate_samples(result.samples)
	if logger != null:
		if logger.stop("AC12 baseline") != OK:
			result.fault = "baseline log did not finish"
		logger = null
	# Replay on the same recorded solver, using the existing complete reader/CSV/report path.
	if rate == 240 and result.fault.is_empty():
		var reader := LogReader.new()
		reader.options = {log = log_path,csv = _out.path_join("baseline.csv"),
			report = _out.path_join("baseline-replay.json"),replay = true}
		reader.set("_automatic_native_macos_allowed",false)
		reader.call("_run")
		result.baseline_replay = {}
		for key: String in ["status","complete","solver_changed","mode","rows","first_tick","final_tick","baseline_solver_sha256","current_solver_sha256"]:
			result.baseline_replay[key] = reader.report.get(key)
		result.baseline_replay.report_sha256 = FileAccess.get_sha256(_out.path_join("baseline-replay.json"))
		result.baseline_replay.log_sha256 = FileAccess.get_sha256(log_path)
		result.baseline_replay.csv_sha256 = FileAccess.get_sha256(_out.path_join("baseline.csv"))
		if not full_baseline_replay(reader.report) or not baseline_replay_is_admitted(reader.report):
			result.fault = "baseline exact replay failed"
		for field: String in ["report_sha256","log_sha256","csv_sha256"]:
			if not Bytes.is_sha256(result.baseline_replay[field]):
				result.fault = "baseline evidence missing"
		reader.free()
	var data := _pack(result.samples)
	result.samples_sha256 = Bytes.sha256(data)
	result.samples_file = "samples-%d-%d.f64le" % [rate,result.run_index]
	if not _write(_out.path_join(result.samples_file),data):
		result.fault = "cannot retain exact samples"
	result.ok = result.fault.is_empty()
	session.free()
	return result


static func _frame_digest(session: Node) -> String:
	return Bytes.sha256(var_to_bytes({state = session.sim.state,continuous = session.sim.continuous,
		aux = session.sim.aux,modes = session.sim.modes,inputs = session.sim.inputs,
		mass = session.sim.mass,inertia = session.sim.inertia}))


static func _frame_description(session: Node) -> Dictionary:
	return {body_hex = _hex(session.sim.state),continuous_hex = _hex(session.sim.continuous),
		aux_hex = _hex(session.sim.aux),modes_hex = _integer_hex(session.sim.modes),inputs_hex = _hex(session.sim.inputs),
		mass_hex = _hex(PackedFloat64Array([session.sim.mass])),inertia_hex = _hex(session.sim.inertia)}


static func _hex(values: PackedFloat64Array) -> Array:
	var result := []
	var bytes := values.to_byte_array()
	for index: int in values.size():
		result.append(bytes.slice(8*index,8*index+8).hex_encode())
	return result


static func _integer_hex(values: PackedInt64Array) -> Array:
	var result := []
	for value: int in values:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_s64(0,value)
		result.append(bytes.hex_encode())
	return result


static func _pack(rows: Array) -> PackedByteArray:
	var output := PackedByteArray()
	for row: PackedFloat64Array in rows:
		output.append_array(row.to_byte_array())
	return output


static func _finite(row: PackedFloat64Array) -> bool:
	for value: float in row:
		if not is_finite(value):
			return false
	return true


static func validate_samples(value: Variant,expected := SAMPLE_COUNT) -> String:
	if expected <= 0 or expected > SAMPLE_COUNT or not value is Array or value.size() != expected:
		return "sample count mismatch"
	for row: Variant in value:
		if not row is PackedFloat64Array or row.size() != ROW_WIDTH or not _finite(row):
			return "nonfinite or malformed sample"
	return ""


func checked_differences(a: Variant,b: Variant,expected := SAMPLE_COUNT) -> Dictionary:
	var problem := validate_samples(a,expected)
	if problem.is_empty():
		problem = validate_samples(b,expected)
	if not problem.is_empty():
		return {ok = false,reason = problem,metrics = {}}
	var values := _differences(a,b)
	for metric: String in METRICS:
		if not is_finite(float(values[metric])):
			return {ok = false,reason = "nonfinite difference",metrics = {}}
	return {ok = true,metrics = values}


static func _run_receipt(run: Dictionary) -> Dictionary:
	var receipt := run.duplicate()
	receipt.erase("samples")
	return receipt


static func _write(path: String,bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok and FileAccess.get_file_as_bytes(path) == bytes and FileAccess.get_sha256(path) == Bytes.sha256(bytes)


func _fail(reason: String) -> void:
	printerr("AC12 audit refused: ",reason)
	quit(2)
