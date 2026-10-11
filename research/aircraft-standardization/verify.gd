extends SceneTree

## AS-04 reproducibility probe. Run through verify.py so baseline and candidate use the same engine and input schedule.
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightSession := preload("res://sim/flight_session.gd")

const ELECTRIC_FILES := [
	"res://data/aircraft/synthetic_stik_electric_4s.json",
	"res://data/aircraft/synthetic_stik_electric_6s.json",
	"res://data/aircraft/synthetic_stik_electric_4s_battery.json",
	"res://data/aircraft/synthetic_stik_electric_6s_battery.json",
]
const ELECTRIC_SECONDS := 0.5
const STANDARD_SECONDS := 2.0
const P51_SECONDS := 1.0
const LOAD_VALIDATION_REPEATS := 7
const TICK_WARMUP_TICKS := 20

var _failures := PackedStringArray()
var _previous_checkpoint: Dictionary = {}


func _initialize() -> void:
	var output_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if output_path.is_empty():
		_failures.append("missing --out=<absolute path>")
		printerr("AS-04: missing --out=<absolute path>")
		quit(2)
		return

	var report := {
		"format": "openrc-as04-flight-probe-v2",
		"godot": Engine.get_version_info().string,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"timing": {
			"clock": "Time.get_ticks_usec",
			"load_validation_repeats_per_case": LOAD_VALIDATION_REPEATS,
			"steady_tick_warmup_discarded": TICK_WARMUP_TICKS,
			"steady_tick_scope": "Simulation.step() wall duration; no physics operations added",
		},
		"cases": [],
		"failures": [],
	}
	for spec in _case_specs():
		report.cases.append(_run_case(spec))
	report.failures = Array(_failures)
	var absolute_path := output_path.replace("\\", "/")
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		printerr("AS-04: cannot write report '%s' (error %d)" % [absolute_path, FileAccess.get_open_error()])
		quit(2)
		return
	file.store_string(JSON.stringify(report, "", true, true))
	file.close()
	print("AS-04 probe: %d cases, %d failures -> %s" % [report.cases.size(), _failures.size(), absolute_path])
	quit(1 if not _failures.is_empty() else 0)


func _case_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in Catalog.ENTRIES:
		var duration := P51_SECONDS if entry.id == "p51d-mustang-120" else STANDARD_SECONDS
		out.append({
			"kind": "catalog",
			"key": str(entry.id),
			"selected_id": str(entry.id),
			"path": str(entry.data),
			"duration_s": duration,
		})
	for path: String in ELECTRIC_FILES:
		var fixture_id := path.get_file().trim_suffix(".json")
		out.append({
			"kind": "electric",
			"key": fixture_id,
			"selected_id": fixture_id,
			"path": path,
			"duration_s": ELECTRIC_SECONDS,
		})
	return out


func _run_case(spec: Dictionary) -> Dictionary:
	var key: String = str(spec.key)
	var path: String = str(spec.path)
	var loaded: Dictionary = AircraftData.load_file(path)
	if not loaded.get("ok", false):
		_fail("%s: aircraft data failed to load: %s" % [key, str(loaded.get("errors", []))])
		return {"key": key, "kind": spec.kind, "ok": false, "load_errors": Array(loaded.get("errors", []))}

	var model: Dictionary = loaded.model
	var model_id: String = str(model.get("id", ""))
	var expected_id: String = str(spec.selected_id)
	var result: Dictionary = {
		"key": key,
		"kind": str(spec.kind),
		"path": path,
		"selected_id": expected_id,
		"model_id": model_id,
		"duration_s": float(spec.duration_s),
	"raw_numeric": _numeric_tree(_read_raw(path)),
		"model_numeric": _physics_model_tree(model),
		"model_capabilities": model.get("capabilities", {}),
		"model_convention_id": str(model.get("convention_id", "")),
		"model_data_sha256": str(model.get("data_sha256", "")),
		"model_mass_kg": float(model.get("mass_kg", NAN)),
		"model_cg_le": Array(model.get("cg_le", PackedFloat64Array())),
		"model_inertia": Array(model.get("inertia", PackedFloat64Array())),
		"start_speed_mps": float(model.get("start_speed", NAN)),
		"propulsion_numeric": _numeric_tree(model.get("propulsion", {})),
		"control_numeric": _numeric_tree(model.get("controls", {})),
		"gear_numeric": _numeric_tree(model.get("landing_gear", {})),
		"crash_hull_numeric": _numeric_tree(model.get("crash_hull", PackedFloat64Array())),
	}
	var load_validation_us_samples: Array[int] = []
	for _repeat in range(LOAD_VALIDATION_REPEATS):
		var load_started_us: int = Time.get_ticks_usec()
		var repeated_load: Dictionary = AircraftData.load_file(path)
		load_validation_us_samples.append(Time.get_ticks_usec() - load_started_us)
		if not repeated_load.get("ok", false) or _physics_model_tree(repeated_load.model) != result.model_numeric:
			_fail("%s: repeated validation load changed result or failed" % key)
	result["load_validation_us_samples"] = load_validation_us_samples
	if model_id != expected_id:
		_fail("%s: selected ID '%s' does not match loaded model '%s'" % [key, expected_id, model_id])
		result["ok"] = false
		return result

	var flight := FlightSession.new()
	flight.input_enabled = false
	flight.setup(path)
	if not flight.aircraft.get("ok", false) or not flight.is_flyable():
		_fail("%s: session is not flyable after setup: %s" % [key, flight.pause_reason])
		result["ok"] = false
		result["session_error"] = flight.pause_reason
		flight.free()
		return result
	if flight.aircraft.model.get("id", "") != expected_id:
		_fail("%s: session model ID changed after setup" % key)
		result["ok"] = false
		flight.free()
		return result
	result["session_model_matches_loader"] = _physics_model_tree(flight.aircraft.model) == result["model_numeric"]
	result["session_capabilities_match_loader"] = flight.aircraft.model.get("capabilities", {}) == result["model_capabilities"]
	result["session_convention_id_matches_loader"] = str(flight.aircraft.model.get("convention_id", "")) == result["model_convention_id"]
	if not result["session_model_matches_loader"]:
		_fail("%s: session setup changed normalized numeric model values" % key)
	if not result["session_capabilities_match_loader"] or not result["session_convention_id_matches_loader"]:
		_fail("%s: session setup changed aircraft capability/convention metadata" % key)

	var electric: bool = str(spec.kind) == "electric"
	result["shaft_integrator"] = flight.shaft_integrator()
	result["battery_dynamic"] = flight.battery_is_dynamic()
	result["initial_engine_running"] = flight.engine_running
	result["initial_electrical_state"] = _numeric_tree(flight.electrical_state())
	if electric and flight.shaft_integrator() != "coupled-rk4":
		_fail("%s: electric fixture did not select coupled-rk4" % key)

	var tick_count := maxi(1, roundi(float(spec.duration_s) * float(Engine.physics_ticks_per_second)))
	var checkpoint_tick := maxi(1, int(tick_count / 2))
	var initial_boundary := _simulation_bytes(flight.sim)
	var samples: Array[Dictionary] = [_tick_sample(flight.sim, -1, [0.0, 0.0, 0.0, 0.0])]
	var checkpoint: Dictionary = {}
	var run_failed := false
	var steady_tick_us_samples: Array[int] = []
	for tick in range(tick_count):
		if tick == checkpoint_tick:
			checkpoint = flight.checkpoint()
		var pilot: Array[float] = _manual_input(tick, tick_count)
		flight.commands = {"roll": pilot[0], "pitch": pilot[1], "yaw": pilot[2], "throttle": pilot[3]}
		var flown: Dictionary = flight.flown_commands()
		flight.sim.inputs = PackedFloat64Array([flown.roll, flown.pitch, flown.yaw, flown.throttle])
		var tick_started_us: int = Time.get_ticks_usec()
		flight.sim.step()
		var elapsed_tick_us: int = Time.get_ticks_usec() - tick_started_us
		if tick >= TICK_WARMUP_TICKS:
			steady_tick_us_samples.append(elapsed_tick_us)
		if not flight.sim.fault_reason.is_empty():
			_fail("%s: simulation fault at tick %d: %s" % [key, flight.sim.tick, flight.sim.fault_reason])
			run_failed = true
			break
		if not _finite(flight.sim.state) or not _finite(flight.sim.aux) or not _finite(flight.sim.inputs):
			_fail("%s: nonfinite state/input at tick %d" % [key, flight.sim.tick])
			run_failed = true
			break
		samples.append(_tick_sample(flight.sim, tick, pilot))
	if run_failed:
		result["ok"] = false
		result["samples"] = samples
		result["steady_tick_us_samples"] = steady_tick_us_samples
		flight.free()
		return result
	if checkpoint.is_empty():
		_fail("%s: no valid midpoint checkpoint" % key)
		result["ok"] = false
		flight.free()
		return result

	var first_final := _simulation_bytes(flight.sim)
	result["samples"] = samples
	result["steady_tick_us_samples"] = steady_tick_us_samples
	result["initial_simulation"] = initial_boundary
	result["final_simulation"] = first_final
	result["checkpoint_tick"] = checkpoint.simulation.tick
	flight.reset()
	var after_reset := _simulation_bytes(flight.sim)
	result["reset_matches_initial"] = after_reset == initial_boundary and flight.engine_running == bool(result.initial_engine_running)
	if not result.reset_matches_initial:
		_fail("%s: reset did not reproduce the initial state/aux/input boundary" % key)

	var restored := flight.restore_checkpoint(checkpoint.duplicate(true))
	if not restored:
		_fail("%s: own checkpoint refused after reset" % key)
	else:
		for tick in range(checkpoint_tick, tick_count):
			var pilot: Array[float] = _manual_input(tick, tick_count)
			flight.commands = {"roll": pilot[0], "pitch": pilot[1], "yaw": pilot[2], "throttle": pilot[3]}
			var flown: Dictionary = flight.flown_commands()
			flight.sim.inputs = PackedFloat64Array([flown.roll, flown.pitch, flown.yaw, flown.throttle])
			flight.sim.step()
		result["checkpoint_restore_pauses"] = flight.sim.paused and not flight.input_enabled
		if not result["checkpoint_restore_pauses"]:
			_fail("%s: checkpoint restore did not leave the session paused with live input disabled" % key)
	result["checkpoint_replay_matches"] = restored and _simulation_bytes(flight.sim) == first_final
	if not result.checkpoint_replay_matches:
		_fail("%s: checkpoint replay final boundary differs from the original sequence" % key)

	if not _previous_checkpoint.is_empty():
		var before_cross_restore := _simulation_bytes(flight.sim)
		var cross_restore := flight.restore_checkpoint(_previous_checkpoint.duplicate(true))
		result["prior_checkpoint_rejected_atomically"] = not cross_restore and _simulation_bytes(flight.sim) == before_cross_restore
		if not result.prior_checkpoint_rejected_atomically:
			_fail("%s: prior scenario checkpoint was accepted or changed the current state" % key)
	else:
		result["prior_checkpoint_rejected_atomically"] = null

	_previous_checkpoint = checkpoint.duplicate(true)
	var original_path: String = flight.aircraft_path
	flight.sim.set_paused(false)
	var before_bad_reload := _simulation_bytes(flight.sim)
	var before_bad_model: Variant = _physics_model_tree(flight.aircraft.model)
	var bad_path := "user://as04-malformed-%d.json" % Time.get_ticks_usec()
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	if bad_file == null:
		_fail("%s: could not create malformed reload fixture" % key)
		result["malformed_reload_rollback"] = false
	else:
		bad_file.store_string("{ this is intentionally invalid JSON")
		bad_file.close()
		flight.aircraft_path = bad_path
		var reload_result: String = flight.reload()
		result["malformed_reload_message"] = reload_result
		result["malformed_reload_rollback"] = reload_result.begins_with("reload failed") \
			and _simulation_bytes(flight.sim) == before_bad_reload and _physics_model_tree(flight.aircraft.model) == before_bad_model
		if not result.malformed_reload_rollback:
			_fail("%s: malformed reload changed the active flight or was not refused" % key)
		flight.aircraft_path = original_path
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))

	result["ok"] = true
	flight.free()
	return result


func _manual_input(tick: int, count: int) -> Array[float]:
	var fraction := float(tick) / float(count)
	if fraction < 0.20:
		return [0.0, 0.0, 0.0, 0.0]
	if fraction < 0.45:
		return [0.18, -0.12, 0.08, 0.64]
	if fraction < 0.70:
		return [-0.14, 0.09, -0.06, 0.56]
	return [0.0, 0.0, 0.0, 0.60]


func _tick_sample(sim: Node, tick: int, pilot: Array[float]) -> Dictionary:
	return {
		"tick": tick,
		"pilot_input": pilot,
		"simulation": _simulation_bytes(sim),
	}


func _simulation_bytes(sim: Node) -> Dictionary:
	return {
		"tick": int(sim.tick),
		"time_s": float(sim.time()),
		"state": sim.state.to_byte_array().hex_encode(),
		"aux": sim.aux.to_byte_array().hex_encode(),
		"inputs": sim.inputs.to_byte_array().hex_encode(),
		"continuous": sim.continuous.to_byte_array().hex_encode(),
		"modes": sim.modes.to_byte_array().hex_encode(),
	}


func _read_raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Keep numeric/boolean structure and array widths; omit prose/provenance strings and hashes.
func _numeric_tree(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT:
			return value
		TYPE_FLOAT:
			if is_nan(value):
				return "NaN"
			if is_inf(value):
				return "-Infinity" if value < 0.0 else "Infinity"
			return value
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY:
			var packed: Array = []
			for item in value:
				packed.append(_numeric_tree(item))
			return packed
		TYPE_ARRAY:
			var values: Array = []
			for item in value:
				values.append(_numeric_tree(item))
			return values
		TYPE_DICTIONARY:
			var out := {}
			var keys: Array = value.keys()
			keys.sort()
			for key in keys:
				var child: Variant = _numeric_tree(value[key])
				if child != null:
					out[str(key)] = child
			return out
		_:
			return null


## Capabilities and convention/source IDs are semantic metadata, not physical values.
## Keep them in sibling report fields and retain every other model value (including branch strings).
func _physics_model_tree(model: Dictionary) -> Variant:
	var physics: Dictionary = model.duplicate(true)
	for metadata_key in ["capabilities", "convention_id", "data_sha256"]:
		physics.erase(metadata_key)
	return _model_value_tree(physics)


func _model_value_tree(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			if is_nan(value):
				return "NaN"
			if is_inf(value):
				return "-Infinity" if value < 0.0 else "Infinity"
			return value
		TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_ARRAY:
			var values: Array = []
			for item in value:
				values.append(_model_value_tree(item))
			return values
		TYPE_DICTIONARY:
			var out := {}
			var keys: Array = value.keys()
			keys.sort()
			for key in keys:
				out[str(key)] = _model_value_tree(value[key])
			return out
		_:
			return str(value)


func _finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("AS-04 FAIL: " + message)
