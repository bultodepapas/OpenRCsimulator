extends SceneTree
## Standalone synthetic two-mass quarter-car experiment. This output is a
## numerical bench, not measured truck data or a full-vehicle validation.

const QuarterCar := preload("res://physics/ground_vehicle/quarter_car.gd")
const BenchData := preload("res://physics/ground_vehicle/suspension_bench_data.gd")

const DEFAULT_DURATION_S := 2.0
const MAX_DURATION_S := 30.0
const SCENARIOS := ["release", "drop", "bump"]
const FREQUENCIES_HZ := [240, 480, 960, 1920]
const CSV_HEADER := "time_s,road_height_m,z_s_m,z_u_m,v_s_m_per_s,v_u_m_per_s,suspension_force_n,tire_force_n,tire_compression_m,suspension_compression_m,dissipation_w,energy_j,in_contact"


func _initialize() -> void:
	var parsed := _parse_options(OS.get_cmdline_user_args())
	if not parsed.ok:
		_fail(parsed.error)
		return
	var options: Dictionary = parsed.options
	var profile_path: String = str(options.profile)
	if profile_path.is_empty():
		profile_path = ProjectSettings.globalize_path("res://").path_join(
			"../research/rc-monster-truck/suspension_bench.json"
		)
	else:
		profile_path = _resolve_path(profile_path)
	var profile_bytes_result := _read_bytes(profile_path)
	if not profile_bytes_result.ok:
		_fail(profile_bytes_result.error)
		return
	var profile_bytes: PackedByteArray = profile_bytes_result.bytes
	# Validate the exact byte snapshot whose hash is recorded, not a second read.
	var loaded: Dictionary = BenchData.parse_text(profile_bytes.get_string_from_utf8())
	if not loaded.ok:
		_fail("profile rejected: " + str(loaded.errors))
		return
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		_fail("could not initialize profile SHA-256")
		return
	hash_context.update(profile_bytes)
	var profile_sha256: String = hash_context.finish().hex_encode()
	var output_path: String = _resolve_path(str(options.out))
	if output_path.get_extension().to_lower() != "csv":
		_fail("--out must end in .csv")
		return
	var summary_path := output_path.get_basename() + ".json"
	if output_path.simplify_path().to_lower() == profile_path.simplify_path().to_lower() or summary_path.simplify_path().to_lower() == profile_path.simplify_path().to_lower():
		_fail("output paths must not replace the input profile")
		return
	if not _run_bench(options, loaded, profile_path, profile_sha256, output_path):
		return
	quit(0)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var options := {
		"scenario": "release",
		"hz": 240,
		"duration": DEFAULT_DURATION_S,
		"out": "",
		"profile": "",
	}
	var seen := {}
	for arg in args:
		if not arg.begins_with("--"):
			return {"ok": false, "error": "unexpected argument: " + arg}
		var equals_at: int = arg.find("=")
		if equals_at < 3:
			return {"ok": false, "error": "options must use --name=value syntax: " + arg}
		var name: String = arg.substr(2, equals_at - 2)
		var value: String = arg.substr(equals_at + 1)
		if not name in options:
			return {"ok": false, "error": "unknown option: --" + name}
		if seen.has(name):
			return {"ok": false, "error": "duplicate option: --" + name}
		seen[name] = true
		if name == "scenario":
			if not value in SCENARIOS:
				return {"ok": false, "error": "--scenario must be release, drop, or bump"}
			options.scenario = value
		elif name == "hz":
			if not value.is_valid_int():
				return {"ok": false, "error": "--hz must be one of 240, 480, 960, or 1920"}
			var hz: int = value.to_int()
			if not hz in FREQUENCIES_HZ:
				return {"ok": false, "error": "--hz must be one of 240, 480, 960, or 1920"}
			options.hz = hz
		elif name == "duration":
			if not value.is_valid_float():
				return {"ok": false, "error": "--duration must be a finite number of seconds"}
			var duration_s: float = value.to_float()
			if not is_finite(duration_s) or duration_s <= 0.0 or duration_s > MAX_DURATION_S:
				return {"ok": false, "error": "--duration must be > 0 and <= 30 seconds"}
			options.duration = duration_s
		elif name == "out":
			if value.strip_edges().is_empty():
				return {"ok": false, "error": "--out is required and must be nonempty"}
			options.out = value
		elif name == "profile":
			if value.strip_edges().is_empty():
				return {"ok": false, "error": "--profile must be nonempty when supplied"}
			options.profile = value
	if str(options.out).is_empty():
		return {"ok": false, "error": "missing required --out=<csv>"}
	var final_ticks: float = float(options.duration) * float(options.hz)
	if final_ticks < 1.0 - 1e-9 or absf(final_ticks - roundf(final_ticks)) > 1e-9:
		return {"ok": false, "error": "duration * hz must be an integer number of ticks"}
	return {"ok": true, "options": options}


func _run_bench(
	options: Dictionary,
	loaded: Dictionary,
	profile_path: String,
	profile_sha256: String,
	output_path: String,
) -> bool:
	var parameters: Dictionary = loaded.parameters
	var scenario: String = str(options.scenario)
	var hz: int = int(options.hz)
	var duration_s: float = float(options.duration)
	var total_ticks: int = roundi(duration_s * float(hz))
	var dt: float = 1.0 / float(hz)
	var road := Callable(self, "_road_height").bind(scenario)
	var state: PackedFloat64Array = QuarterCar.equilibrium(parameters, 0.0)
	if scenario == "release":
		state[QuarterCar.Z_SPRUNG] += 0.01
	elif scenario == "drop":
		state[QuarterCar.Z_SPRUNG] += 0.05
		state[QuarterCar.Z_UNSPRUNG] += 0.05
	var csv := FileAccess.open(output_path, FileAccess.WRITE)
	if csv == null:
		_fail("cannot open CSV output %s (error %d)" % [output_path, FileAccess.get_open_error()])
		return false
	csv.store_line(CSV_HEADER)
	if csv.get_error() != OK:
		csv.close()
		_fail("could not write CSV header to " + output_path)
		return false
	var ranges := _new_ranges()
	var sample_count := 0
	var contact_sample_count := 0
	var contact_tire_force_min := INF
	var contact_tire_force_max := -INF
	for tick in range(total_ticks + 1):
		var time_s: float = float(tick) / float(hz)
		var road_height: float = _road_height(time_s, scenario)
		if not _finite_state(state):
			csv.close()
			_fail("non-finite state at sample %d (t=%.9f s)" % [tick, time_s])
			return false
		var loads: Dictionary = QuarterCar.loads(state, parameters, road_height)
		var energy_j: float = QuarterCar.energy(state, parameters, road_height)
		if not _finite_loads(loads) or not is_finite(energy_j):
			csv.close()
			_fail("non-finite loads or energy at sample %d (t=%.9f s)" % [tick, time_s])
			return false
		var contact: bool = bool(loads.in_contact)
		var row := PackedStringArray([
			_num(time_s),
			_num(road_height),
			_num(state[QuarterCar.Z_SPRUNG]),
			_num(state[QuarterCar.Z_UNSPRUNG]),
			_num(state[QuarterCar.V_SPRUNG]),
			_num(state[QuarterCar.V_UNSPRUNG]),
			_num(float(loads.suspension_force_n)),
			_num(float(loads.tire_force_n)),
			_num(float(loads.tire_compression_m)),
			_num(float(loads.suspension_compression_m)),
			_num(float(loads.dissipation_w)),
			_num(energy_j),
			"true" if contact else "false",
		])
		csv.store_line(",".join(row))
		if csv.get_error() != OK:
			csv.close()
			_fail("could not write CSV sample %d to %s" % [tick, output_path])
			return false
		_update_ranges(ranges, time_s, road_height, state, loads, energy_j)
		if contact:
			contact_sample_count += 1
			contact_tire_force_min = minf(contact_tire_force_min, float(loads.tire_force_n))
			contact_tire_force_max = maxf(contact_tire_force_max, float(loads.tire_force_n))
		sample_count += 1
		if tick < total_ticks:
			state = QuarterCar.step(state, parameters, time_s, dt, road)
			if not _finite_state(state):
				csv.close()
				_fail("non-finite state after step %d (t=%.9f s)" % [tick, time_s + dt])
				return false
	csv.flush()
	var csv_error: Error = csv.get_error()
	csv.close()
	if csv_error != OK:
		_fail("CSV output ended with error %d: %s" % [csv_error, output_path])
		return false
	var contact_force_range: Variant = null
	if contact_sample_count > 0:
		contact_force_range = {"min": contact_tire_force_min, "max": contact_tire_force_max}
	var csv_sha256: String = _sha256_file(output_path)
	if csv_sha256.is_empty():
		_fail("could not calculate CSV SHA-256: " + output_path)
		return false
	var summary_path: String = output_path.get_basename() + ".json"
	var summary := {
		"format": "openrc-suspension-bench-run",
		"version": 1,
		"model": "quarter-car-linear-unilateral-tire-v1",
		"complete": true,
		"status": "complete",
		"scope": "Synthetic two-mass quarter-car numerical bench only; not measured truck calibration or full-vehicle validation.",
		"scenario": scenario,
		"hz": hz,
		"substeps_per_tick": int(QuarterCar.SUBSTEPS_PER_TICK),
		"duration_s": duration_s,
		"ticks": total_ticks,
		"sample_count": sample_count,
		"finite_sample_count": sample_count,
		"contact_sample_count": contact_sample_count,
		"profile_id": str(loaded.id),
		"profile_path": profile_path,
		"profile_sha256": profile_sha256,
		"csv_path": output_path,
		"csv_sha256": csv_sha256,
		"ranges": ranges,
		"contact_tire_force_n": contact_force_range,
	}
	var summary_file := FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		_fail("cannot open JSON summary %s (error %d)" % [summary_path, FileAccess.get_open_error()])
		return false
	summary_file.store_string(JSON.stringify(summary, "  ") + "\n")
	summary_file.flush()
	var summary_error: Error = summary_file.get_error()
	summary_file.close()
	if summary_error != OK:
		_fail("could not write JSON summary %s (error %d)" % [summary_path, summary_error])
		return false
	print("suspension bench complete: %s, %d/%d finite samples, %d Hz, %s" % [
		output_path, sample_count, total_ticks + 1, hz, summary_path,
	])
	return true


func _road_height(time_s: float, scenario: String) -> float:
	if scenario != "bump" or time_s < 0.25 or time_s > 0.45:
		return 0.0
	var phase: float = PI * (time_s - 0.25) / 0.20
	var bump_shape: float = sin(phase)
	return 0.005 * bump_shape * bump_shape


func _finite_state(state: PackedFloat64Array) -> bool:
	if state.size() != QuarterCar.STATE_SIZE:
		return false
	for value in state:
		if not is_finite(value):
			return false
	return true


func _finite_loads(loads: Dictionary) -> bool:
	for key in [
		"suspension_force_n",
		"tire_force_n",
		"suspension_compression_m",
		"tire_compression_m",
		"dissipation_w",
	]:
		if not loads.has(key) or not is_finite(float(loads[key])):
			return false
	return loads.has("in_contact") and typeof(loads.in_contact) == TYPE_BOOL


func _new_ranges() -> Dictionary:
	var names := [
		"time_s", "road_height_m", "z_s_m", "z_u_m", "v_s_m_per_s", "v_u_m_per_s",
		"suspension_force_n", "tire_force_n", "tire_compression_m", "suspension_compression_m",
		"dissipation_w", "energy_j",
	]
	var ranges := {}
	for name in names:
		ranges[name] = {"min": INF, "max": -INF}
	return ranges


func _update_ranges(
	ranges: Dictionary,
	time_s: float,
	road_height: float,
	state: PackedFloat64Array,
	loads: Dictionary,
	energy_j: float,
) -> void:
	_range(ranges, "time_s", time_s)
	_range(ranges, "road_height_m", road_height)
	_range(ranges, "z_s_m", state[QuarterCar.Z_SPRUNG])
	_range(ranges, "z_u_m", state[QuarterCar.Z_UNSPRUNG])
	_range(ranges, "v_s_m_per_s", state[QuarterCar.V_SPRUNG])
	_range(ranges, "v_u_m_per_s", state[QuarterCar.V_UNSPRUNG])
	_range(ranges, "suspension_force_n", float(loads.suspension_force_n))
	_range(ranges, "tire_force_n", float(loads.tire_force_n))
	_range(ranges, "tire_compression_m", float(loads.tire_compression_m))
	_range(ranges, "suspension_compression_m", float(loads.suspension_compression_m))
	_range(ranges, "dissipation_w", float(loads.dissipation_w))
	_range(ranges, "energy_j", energy_j)


func _range(ranges: Dictionary, key: String, value: float) -> void:
	var result: Dictionary = ranges[key]
	result.min = minf(float(result.min), value)
	result.max = maxf(float(result.max), value)
	ranges[key] = result


func _num(value: float) -> String:
	return String.num(value, 17)


func _read_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot read profile %s (error %d)" % [path, FileAccess.get_open_error()]}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"ok": false, "error": "could not read profile %s (error %d)" % [path, read_error]}
	return {"ok": true, "bytes": bytes}


func _sha256_file(path: String) -> String:
	var content: Dictionary = _read_bytes(path)
	if not content.ok:
		return ""
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hash_context.update(content.bytes)
	return hash_context.finish().hex_encode()


func _resolve_path(path: String) -> String:
	path = path.replace("\\", "/")
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.begins_with("/"):
		return path.simplify_path()
	if path.length() >= 3 and path.substr(1, 1) == ":":
		return path.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(path).simplify_path()


func _fail(message: String) -> void:
	printerr("ERROR: " + message)
	quit(1)
