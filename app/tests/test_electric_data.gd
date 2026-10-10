# EL1b: provenance-complete electric aircraft data without changing legacy glow or turbine loading.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const FIXTURE_800 := "res://data/aircraft/synthetic_stik_electric_4s.json"
const FIXTURE_400 := "res://data/aircraft/synthetic_stik_electric_6s.json"
const GLOW_FIXTURE := "res://data/aircraft/jensen_ugly_stik_60.json"
const TURBINE_FIXTURE := "res://data/aircraft/sebart_avanti_s_a200.json"

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _raw(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _rejects(label: String, path: String, mutate: Callable, needle: String) -> void:
	var raw: Dictionary = _raw(path)
	mutate.call(raw)
	var result: Dictionary = AD.validate_and_derive(raw)
	var hit := false
	for error: String in result.errors:
		hit = hit or needle in error
	_check("rejects: " + label, not result.ok and hit, str(result.errors))


func _initialize() -> void:
	_check_fixture(FIXTURE_800, 800.0, 14.8)
	_check_fixture(FIXTURE_400, 400.0, 22.2)
	var glow: Dictionary = AD.load_file(GLOW_FIXTURE)
	_check("legacy missing-kind glow still loads", glow.ok, str(glow.errors))
	if glow.ok:
		_check("legacy glow has no synthetic electric branch", not glow.model.propulsion.has("kind"))
	var turbine: Dictionary = AD.load_file(TURBINE_FIXTURE)
	_check("explicit turbine still loads", turbine.ok, str(turbine.errors))
	if turbine.ok:
		_check("turbine kind remains explicit", turbine.model.propulsion.kind == "turbine")

	_rejects("unknown electric propulsion field", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.extra_controller = {}, "unsupported field")
	_rejects("mixed glow engine field", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.engine = {}, "unsupported field")
	_rejects("unsupported gear ratio", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.gear_ratio = 2.0, "unsupported field")
	_rejects("unknown motor field", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.phase_resistance = 0.08, "unsupported field")
	_rejects("wrong resistance scope", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.resistance_scope = "motor_plus_esc", "resistance_scope")
	_rejects("unsupported variable-voltage battery", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.battery.kind = "ocv_sag", "battery.kind")
	_rejects("unsupported ESC mapping", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.esc.command_mapping = "receiver_pulse", "command_mapping")
	_rejects("wrong motor unit", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.kv_rpm_per_volt.unit = "V/rpm", "kv_rpm_per_volt")
	_rejects("missing I0 context temperature", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.no_load_context.erase("temperature_c"), "temperature_c")
	_rejects("extra electric quantity field", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.no_load_current_a.instrument = "synthetic", "unsupported field")
	_rejects("zero rotating inertia", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.propeller.rotating_inertia.value = 0.0, "inertia must be positive")
	_rejects("rotor inertia leaves a nonpositive carrier", FIXTURE_800,
		func(data: Dictionary) -> void: _collapse_carrier(data), "nonpositive carrier inertia")
	_rejects("negative static Cp", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.propeller.cp_table.value[0][1] = -0.01, "static Cp")
	_rejects("no-load RPM exceeds its Kv voltage reference", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.motor.no_load_context.rpm.value = 15000.0, "Kv × test voltage")
	_rejects("wrong electric selector does not fall through", FIXTURE_800,
		func(data: Dictionary) -> void: data.propulsion.kind = "electric", "propulsion.kind")

	var nonfinite: Dictionary = _raw(FIXTURE_800)
	nonfinite.propulsion.motor.kv_rpm_per_volt.value = INF
	var inf_result: Dictionary = AD.validate_and_derive(nonfinite)
	_check("in-memory INF rejected", not inf_result.ok and _contains(inf_result.errors, "kv_rpm_per_volt"), str(inf_result.errors))
	nonfinite = _raw(FIXTURE_800)
	nonfinite.propulsion.motor.no_load_current_a.value = NAN
	var nan_result: Dictionary = AD.validate_and_derive(nonfinite)
	_check("in-memory NAN rejected", not nan_result.ok and _contains(nan_result.errors, "no_load_current_a"), str(nan_result.errors))
	nonfinite = _raw(FIXTURE_800)
	nonfinite.propulsion.propeller.thrust_angles = {
		value = [INF, 0.0], unit = "deg", kind = "estimated", source = "EL1b nonfinite control",
	}
	var angle_result: Dictionary = AD.validate_and_derive(nonfinite)
	_check("nonfinite thrust angle rejected before axis derivation",
		not angle_result.ok and _contains(angle_result.errors, "thrust_angles"), str(angle_result.errors))
	_check_serialized_overflow()

	if _failures > 0:
		printerr("EL1b electric aircraft data: %d/%d checks failed" % [_failures, _count])
		quit(1)
	else:
		print("EL1b electric aircraft data: %d checks passed" % _count)
		quit(0)


func _check_fixture(path: String, expected_kv: float, expected_voltage: float) -> void:
	var result: Dictionary = AD.load_file(path)
	_check("synthetic fixture loads: " + path.get_file(), result.ok, str(result.errors))
	if not result.ok:
		return
	var prop: Dictionary = result.model.propulsion
	_check("electric kind normalized", prop.get("kind") == "electric_prop")
	var stik: Dictionary = AD.load_file(GLOW_FIXTURE)
	_check("synthetic demo preserves Stik mass, CG, and complete inertia",
		stik.ok and result.model.mass_kg == stik.model.mass_kg
		and result.model.cg_le == stik.model.cg_le and result.model.inertia == stik.model.inertia,
		"demo mass=%s CG=%s inertia=%s; Stik mass=%s CG=%s inertia=%s" % [
			result.model.mass_kg, result.model.cg_le, result.model.inertia,
			stik.model.mass_kg if stik.ok else "invalid", stik.model.cg_le if stik.ok else "invalid",
			stik.model.inertia if stik.ok else "invalid",
		])
	_check("motor constants normalized", prop.motor.kv_rpm_per_volt == expected_kv
		and prop.motor.resistance_ohm > 0.0 and prop.motor.no_load_current_a >= 0.0, str(prop.motor))
	_check("fixed battery and identity ESC normalized",
		prop.battery.kind == "fixed_voltage" and prop.battery.voltage_v == expected_voltage
		and prop.esc.kind == "ideal_motoring" and prop.esc.command_mapping == "identity")
	_check("Kv voltage product is reference RPM only", absf(prop.max_rpm - expected_kv * expected_voltage) < 1e-9)
	_check("shared propeller fields stay flat", prop.has_all(["diameter", "offset", "rotor_inertia", "ct", "cp", "axis"]))
	_check("positive direct-drive inertia", prop.rotor_inertia > 0.0 and prop.axis == PackedFloat64Array([1.0, 0.0, 0.0]))
	_check("no combustion idle or shaft configuration", not prop.has("idle_rpm") and not prop.has("lag") and not prop.has("shaft"))
	if path == FIXTURE_400:
		_check("signed Cp retains windmilling lower bound", prop.get("cp_min", 0.0) == -0.02, str(prop.get("cp_min")))


func _contains(messages: PackedStringArray, needle: String) -> bool:
	for message: String in messages:
		if needle in message:
			return true
	return false


func _collapse_carrier(data: Dictionary) -> void:
	for part: Dictionary in data.inventory:
		part.position.value = [0.1209, 0.0, 0.0]
		part.size = {value = [0.01, 0.01, 0.01], unit = "m", kind = "estimated", source = "EL1b synthetic carrier test"}


func _check_serialized_overflow() -> void:
	var path := "user://electric-data-overflow-%d.json" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("create overflow fixture", false, str(FileAccess.get_open_error()))
		return
	file.store_string("{\"format\":\"openrc-aircraft v1\",\"propulsion\":{\"kind\":\"electric_prop\",\"motor\":{\"kv_rpm_per_volt\":{\"value\":1e999,\"unit\":\"rpm/V\",\"kind\":\"estimated\",\"source\":\"EL1b overflow control\"}}}}")
	file.close()
	var result: Dictionary = AD.load_file(path)
	_check("serialized numeric overflow refused by loader", not result.ok and _contains(result.errors, "kv_rpm_per_volt"), str(result.errors))
	_check("remove overflow fixture", DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
