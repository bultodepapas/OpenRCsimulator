extends SceneTree

## Paired same-process check of v2 session vs the explicitly converted v1 input.
## This does not change the app or its tick implementation.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const ELECTRIC_FILES := [
	"res://data/aircraft/synthetic_stik_electric_4s.json",
	"res://data/aircraft/synthetic_stik_electric_6s.json",
	"res://data/aircraft/synthetic_stik_electric_4s_battery.json",
	"res://data/aircraft/synthetic_stik_electric_6s_battery.json",
]
const DEFAULT_PAIR_COUNT := 6
const TICKS_PER_BATCH := 120
const WARMUP_TICKS := 120

var _failures := PackedStringArray()


func _initialize() -> void:
	var mode := ""
	var output_path := ""
	var selected_case := ""
	var pair_count := DEFAULT_PAIR_COUNT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			selected_case = arg.trim_prefix("--only=")
		elif arg.begins_with("--pairs="):
			pair_count = int(arg.trim_prefix("--pairs="))
	if mode not in ["check", "bench"] or output_path.is_empty():
		printerr("AS-04 paired: usage requires --mode=check|bench --out=<absolute path> [--only=<case>] [--pairs=even 2..24]")
		quit(2)
		return
	if pair_count < 2 or pair_count > 24 or pair_count % 2 != 0:
		printerr("AS-04 paired: --pairs must be an even integer from 2 through 24")
		quit(2)
		return
	var specs: Array[Dictionary] = _case_specs()
	if not selected_case.is_empty():
		var selected_specs: Array[Dictionary] = []
		for spec: Dictionary in specs:
			if str(spec.key) == selected_case:
				selected_specs.append(spec)
		specs = selected_specs
		if specs.is_empty():
			printerr("AS-04 paired: unknown --only case '%s'" % selected_case)
			quit(2)
			return
	var report := {
		"format": "openrc-as04-paired-metadata-v1",
		"mode": mode,
		"godot": Engine.get_version_info().string,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"method": "one process; v2 FlightSession with selected ID guard vs FlightSession loaded from AircraftData.legacy_v1_input(v2 raw); reset outside timed batches; 120 warmup ticks; paired 120-tick batches in ABBA repeated order; exact simulation byte comparison after every batch",
		"timing_scope": "per Simulation.step() call; inputs and reset are outside the timer; timings are descriptive and have no pass/fail threshold",
		"pair_count": pair_count,
		"case_filter": selected_case if not selected_case.is_empty() else "all",
		"ticks_per_batch": TICKS_PER_BATCH,
		"warmup_ticks_per_session": WARMUP_TICKS,
		"cases": [],
		"failures": [],
	}
	for spec: Dictionary in specs:
		report.cases.append(_run_case(spec, mode, pair_count))
	report.failures = Array(_failures)
	var absolute_path := output_path.replace("\\", "/")
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("AS-04 paired: cannot write report '%s' (error %d)" % [absolute_path, FileAccess.get_open_error()])
		quit(2)
		return
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	print("AS-04 paired %s: %d cases, %d failures -> %s" % [mode, report.cases.size(), _failures.size(), absolute_path])
	quit(1 if not _failures.is_empty() else 0)


func _case_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in Catalog.ENTRIES:
		out.append({
			"kind": "catalog",
			"key": str(entry.id),
			"selected_id": str(entry.id),
			"path": str(entry.data),
		})
	for path: String in ELECTRIC_FILES:
		var fixture_id := path.get_file().trim_suffix(".json")
		out.append({
			"kind": "electric",
			"key": fixture_id,
			"selected_id": fixture_id,
			"path": path,
		})
	return out


func _run_case(spec: Dictionary, mode: String, pair_count: int) -> Dictionary:
	var key: String = str(spec.key)
	var v2_path: String = str(spec.path)
	var result := {"key": key, "kind": str(spec.kind), "v2_path": v2_path, "ok": false}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(v2_path))
	if typeof(raw) != TYPE_DICTIONARY:
		_fail("%s: source v2 file did not decode to an object" % key)
		return result
	var v2_loaded: Dictionary = AircraftData.load_file(v2_path)
	if not v2_loaded.get("ok", false):
		_fail("%s: source v2 file failed public loader: %s" % [key, str(v2_loaded.get("errors", []))])
		return result
	var legacy_raw: Dictionary = AircraftData.legacy_v1_input(raw)
	if legacy_raw.get("format", "") != AircraftData.LEGACY_FORMAT:
		_fail("%s: adapter did not produce explicit legacy v1 data" % key)
		return result
	var clone_path := "user://as04-paired-v1-%s.json" % key.replace("/", "_")
	var clone := FileAccess.open(clone_path, FileAccess.WRITE)
	if clone == null:
		_fail("%s: could not write v1 input clone" % key)
		return result
	var clone_text := JSON.stringify(legacy_raw, "", true, true)
	clone.store_string(clone_text)
	clone.close()
	result["legacy_clone_path"] = clone_path
	result["legacy_clone_sha256"] = clone_text.sha256_text()
	result["v2_input_sha256"] = str(v2_loaded.get("input_identity", {}).get("sha256", ""))

	var legacy_loaded: Dictionary = AircraftData.load_file(clone_path)
	if not legacy_loaded.get("ok", false):
		_fail("%s: converted v1 clone failed public loader: %s" % [key, str(legacy_loaded.get("errors", []))])
		_remove_user_file(clone_path)
		return result
	result["legacy_loaded_sha256"] = str(legacy_loaded.get("input_identity", {}).get("sha256", ""))
	result["legacy_clone_bytes_match_loader_identity"] = result.legacy_clone_sha256 == result.legacy_loaded_sha256
	if not result.legacy_clone_bytes_match_loader_identity:
		_fail("%s: loader identity does not match the exact bytes written for the v1 clone" % key)
	var v2_physics: Dictionary = _physics_model(v2_loaded.model)
	var legacy_physics: Dictionary = _physics_model(legacy_loaded.model)
	result["loaded_model_equal"] = v2_physics == legacy_physics
	result["v2_capabilities"] = v2_loaded.model.get("capabilities", {})
	result["legacy_capabilities"] = legacy_loaded.model.get("capabilities", {})
	result["v2_convention_id"] = str(v2_loaded.model.get("convention_id", ""))
	result["legacy_convention_id"] = str(legacy_loaded.model.get("convention_id", ""))
	if not result.loaded_model_equal:
		_fail("%s: v2 and explicit legacy loader produced different non-metadata model values" % key)

	var expected_id: String = str(spec.selected_id)
	var v2_flight: Variant = _create_flight(v2_path, expected_id, key + "/v2")
	var legacy_flight: Variant = _create_flight(clone_path, "", key + "/legacy")
	if v2_flight == null or legacy_flight == null:
		if v2_flight != null:
			v2_flight.free()
		if legacy_flight != null:
			legacy_flight.free()
		_remove_user_file(clone_path)
		return result
	result["v2_identity_guard"] = v2_flight.expected_aircraft_id == expected_id \
		and str(v2_flight.aircraft.get("input_identity", {}).get("format", "")) == AircraftData.FORMAT \
		and str(v2_flight.aircraft.model.get("id", "")) == expected_id
	result["legacy_explicit_format"] = str(legacy_flight.aircraft.get("input_identity", {}).get("format", "")) == AircraftData.LEGACY_FORMAT
	result["session_model_equal"] = _physics_model(v2_flight.aircraft.model) == _physics_model(legacy_flight.aircraft.model)
	var initial_v2 := _simulation_bytes(v2_flight.sim)
	var initial_legacy := _simulation_bytes(legacy_flight.sim)
	result["initial_state_equal"] = initial_v2 == initial_legacy
	if not result.v2_identity_guard:
		_fail("%s: v2 session did not retain selected-ID and v2-format checks" % key)
	if not result.legacy_explicit_format:
		_fail("%s: benchmark legacy session was not loaded through explicit v1 format" % key)
	if not result.session_model_equal or not result.initial_state_equal:
		_fail("%s: session model or initial simulation bytes differ before timing" % key)

	if mode == "bench" and result.loaded_model_equal and result.session_model_equal and result.initial_state_equal:
		var v2_warmup: Dictionary = _run_ticks(v2_flight, WARMUP_TICKS, false)
		var legacy_warmup: Dictionary = _run_ticks(legacy_flight, WARMUP_TICKS, false)
		result["warmup_ticks"] = WARMUP_TICKS
		result["warmup_state_equal"] = bool(v2_warmup.get("ok", false)) and bool(legacy_warmup.get("ok", false)) \
			and v2_warmup.get("simulation", {}) == legacy_warmup.get("simulation", {})
		if not result.warmup_state_equal:
			_fail("%s: v2 and legacy warmup states differ or fault" % key)
		else:
			var pairs: Array[Dictionary] = []
			for pair_index in range(pair_count):
				# Each pair starts from the same reset boundary; pair ordering is A/B, B/A repeated.
				v2_flight.reset()
				legacy_flight.reset()
				var start_v2 := _simulation_bytes(v2_flight.sim)
				var start_legacy := _simulation_bytes(legacy_flight.sim)
				var pair: Dictionary = {"pair": pair_index + 1, "start_state_equal": start_v2 == start_legacy}
				if not pair.start_state_equal:
					_fail("%s: reset boundary mismatch before pair %d" % [key, pair_index + 1])
				var first_is_v2: bool = pair_index % 2 == 0
				var first: Dictionary = _run_ticks(v2_flight if first_is_v2 else legacy_flight, TICKS_PER_BATCH, true)
				var second: Dictionary = _run_ticks(legacy_flight if first_is_v2 else v2_flight, TICKS_PER_BATCH, true)
				var v2_batch: Dictionary = first if first_is_v2 else second
				var legacy_batch: Dictionary = second if first_is_v2 else first
				pair["order"] = ["v2", "legacy_v1"] if first_is_v2 else ["legacy_v1", "v2"]
				pair["v2"] = v2_batch
				pair["legacy_v1"] = legacy_batch
				pair["state_equal_after_batch"] = bool(v2_batch.get("ok", false)) and bool(legacy_batch.get("ok", false)) \
					and v2_batch.get("simulation", {}) == legacy_batch.get("simulation", {})
				if not pair.state_equal_after_batch:
					_fail("%s: simulation bytes differ after timed pair %d" % [key, pair_index + 1])
				pairs.append(pair)
			result["pairs"] = pairs
		result["reset_after_measurement_v2"] = _reset_matches(v2_flight, initial_v2)
		result["reset_after_measurement_legacy"] = _reset_matches(legacy_flight, initial_legacy)
		if not result.reset_after_measurement_v2 or not result.reset_after_measurement_legacy:
			_fail("%s: final reset did not restore the initial simulation bytes" % key)
	result["ok"] = result.loaded_model_equal and result.v2_identity_guard and result.legacy_explicit_format \
		and result.legacy_clone_bytes_match_loader_identity and result.session_model_equal and result.initial_state_equal
	if mode == "bench":
		result["ok"] = result.ok and result.get("warmup_state_equal", false) \
			and result.get("reset_after_measurement_v2", false) and result.get("reset_after_measurement_legacy", false)
		for pair in result.get("pairs", []):
			result["ok"] = result.ok and bool(pair.get("state_equal_after_batch", false)) and bool(pair.get("start_state_equal", false))
	v2_flight.free()
	legacy_flight.free()
	_remove_user_file(clone_path)
	if not result.ok:
		_fail("%s: paired metadata case did not satisfy its state/model checks" % key)
	return result


func _create_flight(path: String, expected_id: String, label: String) -> Variant:
	var flight := FlightSession.new()
	flight.input_enabled = false
	flight.setup(path, expected_id)
	if not flight.aircraft.get("ok", false) or not flight.is_flyable():
		_fail("%s: session setup did not produce a flyable aircraft (%s)" % [label, str(flight.pause_reason)])
		flight.free()
		return null
	flight.sim.set_paused(false)
	return flight


func _run_ticks(flight: Variant, ticks: int, measure: bool) -> Dictionary:
	var samples: Array[int] = []
	var failure := ""
	var start_tick: int = int(flight.sim.tick)
	for tick in range(ticks):
		var pilot: Array[float] = _manual_input(tick, ticks)
		flight.commands = {"roll": pilot[0], "pitch": pilot[1], "yaw": pilot[2], "throttle": pilot[3]}
		var flown: Dictionary = flight.flown_commands()
		flight.sim.inputs = PackedFloat64Array([flown.roll, flown.pitch, flown.yaw, flown.throttle])
		var elapsed := 0
		if measure:
			var started: int = Time.get_ticks_usec()
			flight.sim.step()
			elapsed = Time.get_ticks_usec() - started
			samples.append(elapsed)
		else:
			flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			failure = "simulation fault at tick %d: %s" % [flight.sim.tick, flight.sim.fault_reason]
			break
		if not _finite(flight.sim.state) or not _finite(flight.sim.aux) or not _finite(flight.sim.inputs):
			failure = "nonfinite simulation array at tick %d" % flight.sim.tick
			break
	if not failure.is_empty():
		_fail("%s" % failure)
	return {
		"ok": failure.is_empty() and int(flight.sim.tick) - start_tick == ticks,
		"ticks": ticks,
		"ticks_advanced": int(flight.sim.tick) - start_tick,
		"tick_us_samples": samples,
		"tick_us": _timing_summary(samples) if measure else {},
		"simulation": _simulation_bytes(flight.sim),
		"failure": failure,
	}


func _manual_input(tick: int, count: int) -> Array[float]:
	var fraction := float(tick) / float(count)
	if fraction < 0.20:
		return [0.0, 0.0, 0.0, 0.0]
	if fraction < 0.45:
		return [0.18, -0.12, 0.08, 0.64]
	if fraction < 0.70:
		return [-0.14, 0.09, -0.06, 0.56]
	return [0.0, 0.0, 0.0, 0.60]


func _physics_model(model: Dictionary) -> Dictionary:
	var result: Dictionary = model.duplicate(true)
	for key in ["capabilities", "convention_id", "data_sha256"]:
		result.erase(key)
	return result


func _simulation_bytes(sim: Variant) -> Dictionary:
	return {
		"tick": int(sim.tick),
		"time_s": float(sim.time()),
		"state": sim.state.to_byte_array().hex_encode(),
		"aux": sim.aux.to_byte_array().hex_encode(),
		"inputs": sim.inputs.to_byte_array().hex_encode(),
		"continuous": sim.continuous.to_byte_array().hex_encode(),
		"modes": sim.modes.to_byte_array().hex_encode(),
	}


func _timing_summary(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"sample_count": 0, "p50_us": null, "p95_us": null, "mean_us": null, "min_us": null, "max_us": null}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var sum := 0.0
	for value in values:
		sum += float(value)
	var middle := int(sorted.size() / 2)
	var p50 := float(sorted[middle]) if sorted.size() % 2 == 1 else (float(sorted[middle - 1]) + float(sorted[middle])) / 2.0
	var p95_index := mini(sorted.size() - 1, maxi(0, ceili(0.95 * float(sorted.size())) - 1))
	return {
		"sample_count": values.size(),
		"p50_us": p50,
		"p95_us": sorted[p95_index],
		"mean_us": sum / float(values.size()),
		"min_us": sorted[0],
		"max_us": sorted[-1],
	}


func _reset_matches(flight: Variant, expected: Dictionary) -> bool:
	flight.reset()
	return _simulation_bytes(flight.sim) == expected


func _remove_user_file(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("AS-04 paired FAIL: " + message)
