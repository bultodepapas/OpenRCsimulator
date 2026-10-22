extends SceneTree

const Loader := preload("res://ai/companions/profile_loader.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FlightLog := preload("res://sim/flight_log.gd")

const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const AIRCRAFT_PROFILE_PATH := "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json"
const FIELD_PROFILE_PATH := "res://data/ai/companions/fields/club-default.json"
const AIRCRAFT_DATA_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _checks: int = 0
var _failures: int = 0
var _aircraft_identity: Dictionary = {}
var _normalized_field: Dictionary = {}


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var aircraft: Dictionary = AircraftData.load_file(AIRCRAFT_DATA_PATH)
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("qualified source aircraft loads with exact input identity", aircraft.get("ok", false), str(aircraft.get("errors", [])))
	_check("pinned Club field loads", loaded_field.get("ok", false), str(loaded_field.get("errors", [])))
	if not aircraft.get("ok", false) or not loaded_field.get("ok", false):
		quit(1)
		return
	_aircraft_identity = aircraft.input_identity.duplicate(true)
	_normalized_field = loaded_field.field.duplicate(true)

	var result: Dictionary = Loader.load_profile(AIRCRAFT_ID, aircraft.input_identity, loaded_field.field)
	_check("current Stik and Club profiles validate", result.get("ok", false), str(result.get("errors", [])))
	if not result.get("ok", false):
		quit(1)
		return
	_check("only the evidenced circuits activity is qualified", result.profile.qualification.activities == ["circuits"])
	_check("stall, approach, cruise, and entry speeds remain explicitly unknown",
		result.profile.performance.stall_speed.status == "unknown" \
		and result.profile.performance.approach_speed.status == "unknown" \
		and result.profile.performance.cruise_speed.status == "unknown" \
		and result.profile.performance.entry_speed.status == "unknown" \
		and not result.profile.performance.stall_speed.has("value"))
	_check("field profile records the current 80 m north-side circuit",
		is_equal_approx(float(result.field_profile.circuit.radius.value), 80.0) \
		and is_equal_approx(float(result.field_profile.circuit.center_north.value), 199.0) \
		and result.field_profile.static_route_clearance == "requires_session_check")
	_check("identity carries accepted aircraft, field, controller, and profile hashes",
		result.identity.aircraft_data_sha256 == aircraft.input_identity.sha256 \
		and result.identity.field_data_sha256 == result.field_profile.field_source.sha256 \
		and result.identity.controller_sha256 == result.profile.controller.sha256 \
		and result.identity.controller_dependencies == result.profile.controller.dependencies \
		and result.identity.solver_sha256 == FlightLog.solver_identity() \
		and result.identity.solver_qualification_sha256 == result.profile.solver.sha256 \
		and result.identity.engine_version == "4.7.2" \
		and result.identity.aircraft_profile_sha256.length() == 64 \
		and result.identity.field_profile_sha256.length() == 64)
	var solver_identity: Dictionary = Loader.current_solver_qualification_identity()
	_check("solver qualification pins strict UTF-8/LF identity separately from FlightLog raw identity",
		solver_identity.get("ok", false) \
		and solver_identity.get("source_count", 0) == 133 \
		and solver_identity.get("sha256", "") == "29ac7fe98862745b038de64f69111634f310885bea61ea2da1c76759bb75a047" \
		and result.profile.solver.normalization == "utf8-lf" \
		and result.identity.solver_normalization == "utf8-lf" \
		and result.identity.solver_qualification_sha256 == solver_identity.sha256 \
		and result.identity.solver_sha256 == FlightLog.solver_identity())

	var profile_copy: Dictionary = _profile(AIRCRAFT_PROFILE_PATH)
	var field_profile_copy: Dictionary = _profile(FIELD_PROFILE_PATH)

	var bad_aircraft: Dictionary = profile_copy.duplicate(true)
	bad_aircraft.format = "openrc-ai-aircraft v2"
	_check("unknown aircraft profile versions fail closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.qualification.activities = ["circuits", "landing"]
	_check("unsupported activities fail closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.performance.stall_speed.value = 18.0
	_check("an unqualified stall-speed claim fails closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.controller.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
	_check("controller source drift fails closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))
	for dependencies: Variant in [null, {}, {"res://unrelated.gd": "0".repeat(64)},
			{Loader.CIRCUIT_SOURCE_PATH: "0".repeat(64)}, {Loader.CIRCUIT_SOURCE_PATH: 42}]:
		bad_aircraft = profile_copy.duplicate(true)
		bad_aircraft.controller.dependencies = dependencies
		_check("missing/malformed/wrong circuit dependency refuses", not _validate(bad_aircraft, field_profile_copy).get("ok", false))
	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.controller.erase("dependencies")
	_check("legacy unbound controller profile refuses", not _validate(bad_aircraft, field_profile_copy).get("ok", false))
	var loaded_pilot: Script = load(Loader.PILOT_SOURCE_PATH)
	_check("actual pilot inheritance is source bound", loaded_pilot.get_base_script().resource_path == Loader.CIRCUIT_SOURCE_PATH
		and FileAccess.get_sha256(Loader.CIRCUIT_SOURCE_PATH) == profile_copy.controller.dependencies[Loader.CIRCUIT_SOURCE_PATH])

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.solver.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
	_check("physics and simulation source drift fails closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.solver.normalization = "utf8"
	_check("unknown solver normalization fails closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))
	var solver_paths: Array[String] = _solver_paths()
	var lf_solver_bytes: Dictionary = _solver_bytes_by_path(solver_paths, false)
	var crlf_solver_bytes: Dictionary = _solver_bytes_by_path(solver_paths, true)
	var lf_solver_identity: Dictionary = Loader.canonical_solver_identity(solver_paths, lf_solver_bytes)
	var crlf_solver_identity: Dictionary = Loader.canonical_solver_identity(solver_paths, crlf_solver_bytes)
	_check("LF and CRLF checkouts produce the same canonical qualification identity",
		lf_solver_identity.get("ok", false) and crlf_solver_identity.get("ok", false) \
		and lf_solver_identity.get("sha256", "") == solver_identity.get("sha256", "") \
		and crlf_solver_identity.get("sha256", "") == solver_identity.get("sha256", ""))
	var empty_solver_identity: Dictionary = Loader.canonical_solver_identity([], {})
	_check("empty solver source sets fail closed", not empty_solver_identity.get("ok", false))
	var missing_solver_bytes: Dictionary = lf_solver_bytes.duplicate(true)
	missing_solver_bytes.erase(solver_paths[0])
	var missing_solver_identity: Dictionary = Loader.canonical_solver_identity(solver_paths, missing_solver_bytes)
	_check("missing solver source bytes fail closed", not missing_solver_identity.get("ok", false))
	var drift_solver_bytes: Dictionary = lf_solver_bytes.duplicate(true)
	var drift_bytes: PackedByteArray = drift_solver_bytes[solver_paths[0]]
	drift_bytes.append_array("# AFC-02 source drift mutation\n".to_utf8_buffer())
	drift_solver_bytes[solver_paths[0]] = drift_bytes
	var drift_solver_identity: Dictionary = Loader.canonical_solver_identity(solver_paths, drift_solver_bytes)
	var drifted_profile: Dictionary = profile_copy.duplicate(true)
	drifted_profile.solver.sha256 = str(drift_solver_identity.get("sha256", ""))
	_check("code drift changes the canonical hash and is refused against the pinned source set",
		drift_solver_identity.get("ok", false) \
		and drift_solver_identity.sha256 != solver_identity.get("sha256", "") \
		and not _validate(drifted_profile, field_profile_copy).get("ok", false))

	bad_aircraft = profile_copy.duplicate(true)
	bad_aircraft.engine_version = "4.7.3"
	_check("an unqualified engine version fails closed", not _validate(bad_aircraft, field_profile_copy).get("ok", false))
	var original_physics_hz: int = Engine.physics_ticks_per_second
	var rates_refused := true
	for hz: int in [120, 480]:
		Engine.physics_ticks_per_second = hz
		rates_refused = rates_refused and not _validate(profile_copy, field_profile_copy).get("ok", false)
	Engine.physics_ticks_per_second = original_physics_hz
	_check("changed physics rates cannot reuse the 240 Hz pilot qualification", rates_refused)

	var wrong_identity: Dictionary = aircraft.input_identity.duplicate(true)
	wrong_identity.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
	_check("accepted aircraft data identity drift fails closed", not _validate(profile_copy, field_profile_copy, wrong_identity).get("ok", false))

	wrong_identity = aircraft.input_identity.duplicate(true)
	wrong_identity["extra"] = "untrusted"
	_check("unexpected input identity fields fail closed", not _validate(profile_copy, field_profile_copy, wrong_identity).get("ok", false))

	var bad_field_profile: Dictionary = field_profile_copy.duplicate(true)
	bad_field_profile.format = "openrc-ai-field v2"
	_check("unknown field profile versions fail closed", not _validate(profile_copy, bad_field_profile).get("ok", false))

	bad_field_profile = field_profile_copy.duplicate(true)
	bad_field_profile.circuit.center_north.value = 200.0
	_check("field route geometry drift fails closed", not _validate(profile_copy, bad_field_profile).get("ok", false))

	bad_field_profile = field_profile_copy.duplicate(true)
	bad_field_profile.circuit.radius.value = NAN
	_check("non-finite dimensional values fail closed", not _validate(profile_copy, bad_field_profile).get("ok", false))

	bad_field_profile = field_profile_copy.duplicate(true)
	bad_field_profile.static_route_clearance = "passed"
	_check("unproven static route clearance cannot be claimed", not _validate(profile_copy, bad_field_profile).get("ok", false))

	bad_field_profile = field_profile_copy.duplicate(true)
	bad_field_profile.qualification.observed.max_radial_error.value = 400.0
	_check("observations outside their qualification gate fail closed", not _validate(profile_copy, bad_field_profile).get("ok", false))

	var changed_field: Dictionary = loaded_field.field.duplicate(true)
	var changed_surfaces: Array = changed_field.surfaces
	for surface_value: Variant in changed_surfaces:
		if typeof(surface_value) == TYPE_DICTIONARY and str(surface_value.get("id", "")) == "runway":
			surface_value.center_north = float(surface_value.center_north) + 1.0
			break
	_check("custom geometry with the same field id is refused", not _validate(profile_copy, field_profile_copy, aircraft.input_identity, changed_field).get("ok", false))

	var unknown_aircraft: Dictionary = Loader.load_profile("unknown-aircraft", aircraft.input_identity, loaded_field.field)
	_check("unknown aircraft IDs are refused without fallback", not unknown_aircraft.get("ok", false))

	result.profile.qualification.activities.append("landing")
	var second_result: Dictionary = Loader.load_profile(AIRCRAFT_ID, aircraft.input_identity, loaded_field.field)
	_check("returned profile dictionaries are detached from later loads",
		second_result.get("ok", false) and second_result.profile.qualification.activities == ["circuits"])

	print("AFC-02 companion profile validation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _profile(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _validate(profile: Dictionary, field_profile: Dictionary, identity: Dictionary = {}, field: Dictionary = {}) -> Dictionary:
	var selected_identity: Dictionary = identity if not identity.is_empty() else _aircraft_identity
	var selected_field: Dictionary = field if not field.is_empty() else _normalized_field
	return Loader.validate_profile_data(profile, field_profile, AIRCRAFT_ID, selected_identity, selected_field)


func _solver_paths() -> Array[String]:
	var paths: Array[String] = []
	for directory: String in Loader.SOLVER_SOURCE_DIRECTORIES:
		Loader._append_solver_source_paths(directory, paths)
	paths.sort()
	return paths


func _solver_bytes_by_path(paths: Array[String], crlf: bool) -> Dictionary:
	var result: Dictionary = {}
	for path: String in paths:
		var source_text: String = FileAccess.get_file_as_string(path)
		source_text = source_text.replace("\r\n", "\n").replace("\r", "\n")
		if crlf:
			source_text = source_text.replace("\n", "\r\n")
		result[path] = source_text.to_utf8_buffer()
	return result
