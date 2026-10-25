## Loads source-bound AFC aircraft and field qualification profiles at launch time.
## The result is detached data for session setup; this loader is not a tick-time service.
extends RefCounted

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const FlightLog := preload("res://sim/flight_log.gd")

const AIRCRAFT_FORMAT := "openrc-ai-aircraft v1"
const FIELD_FORMAT := "openrc-ai-field v1"
const IDENTITY_FORMAT := "openrc-ai-profile-identity v1"
const AIRCRAFT_DATA_FORMAT := "openrc-aircraft v2"
const FIELD_DATA_FORMAT := "openrc-field v1"
const QUALIFIED_ENGINE_VERSION := "4.8.beta1.official.4d10419ca"
const QUALIFIED_PHYSICS_HZ := 240
const SOLVER_NORMALIZATION := "utf8-lf"
const SOLVER_SOURCE_DIRECTORIES := ["res://physics", "res://sim", "res://failures"]
const ACCEPTED_AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const AIRCRAFT_DATA_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const PILOT_SOURCE_PATH := "res://ai/companions/pilot.gd"
const CIRCUIT_SOURCE_PATH := "res://ai/companions/circuit_controller.gd"
const CLUB_FIELD_PATH := "res://data/fields/default.json"
const AIRCRAFT_PROFILE_PATHS := {
	ACCEPTED_AIRCRAFT_ID: "res://data/ai/companions/aircraft/jensen-das-ugly-stik-60.json",
}
const FIELD_PROFILE_PATHS := {
	"club-default": "res://data/ai/companions/fields/club-default.json",
}

# These route factors are copied from the source-bound pilot implementation. Its exact
# SHA-256 is checked below, so a controller change cannot silently reuse this geometry.
const ROUTE_RADIUS_LENGTH_FACTOR := 0.8
const ROUTE_RADIUS_WIDTH_FACTOR := 4.0
const ROUTE_CENTER_RADIUS_FACTOR := 2.0
const ROUTE_CENTER_WIDTH_FACTOR := 2.0

const AIRCRAFT_PROFILE_KEYS := [
	"format", "id", "catalog_id", "aircraft_data", "controller", "solver", "engine_version",
	"field_profile_id", "qualification", "performance",
]
const FIELD_PROFILE_KEYS := [
	"format", "id", "field_source", "runway_id", "circuit", "qualification", "static_route_clearance",
]
const QUANTITY_KEYS := ["value", "unit", "kind", "source"]
const EVIDENCE_KINDS := ["measured", "derived", "estimated"]
const ACTIVITY_ALLOWLIST := ["circuits"]
const QUALIFIED_SKILL := "experienced"
const QUALIFIED_START_MODES := ["airborne"]
const UNQUALIFIED_MODES := ["ground", "takeoff", "runway", "landing"]
const EVIDENCE_PATH := "docs/research/engine-upgrade/GDU-03/companions/README.md"
const QUALIFIED_SCENARIOS := ["calm", "gentle-practice"]
const REBIND_HINT := "run python3 tools/companions/rebind.py"

# AFC-02-R3: suites that test companion logic, not its qualification, may accept the current solver identity, so
# a physics/sim edit fails one gate (tests/test_companions_profiles.gd) instead of every companion suite.
static var _accept_current_solver := false


## Test-only: accept the current solver identity instead of the pinned one. Editor builds only; an exported game
## always enforces the pin. Returns whether the override is active.
static func accept_current_solver_for_tests() -> bool:
	_accept_current_solver = OS.has_feature("editor")
	return _accept_current_solver


## Read and validate one profile pair for a launch. `collision_world` is reserved for a
## compatibility only. Manager admission separately validates actual session geometry
## through Airspace; loading source qualifications alone does not prove clearance.
static func load_profile(
	aircraft_id: String,
	aircraft_identity: Dictionary,
	field: Dictionary,
	collision_world: Variant = null
) -> Dictionary:
	if not AIRCRAFT_PROFILE_PATHS.has(aircraft_id):
		return _failure(PackedStringArray(["aircraft_id: no qualified AI profile for '%s'" % aircraft_id]))

	var aircraft_profile_path: String = str(AIRCRAFT_PROFILE_PATHS[aircraft_id])
	var aircraft_file: Dictionary = _read_json_object(aircraft_profile_path)
	if not aircraft_file.get("ok", false):
		return _failure(aircraft_file.get("errors", PackedStringArray()))
	var aircraft_profile: Dictionary = aircraft_file.raw
	var field_profile_id: String = str(aircraft_profile.get("field_profile_id", ""))
	if not FIELD_PROFILE_PATHS.has(field_profile_id):
		return _failure(PackedStringArray(["field_profile_id: no qualified AI field profile for '%s'" % field_profile_id]))

	var field_profile_path: String = str(FIELD_PROFILE_PATHS[field_profile_id])
	var field_file: Dictionary = _read_json_object(field_profile_path)
	if not field_file.get("ok", false):
		return _failure(field_file.get("errors", PackedStringArray()))
	var field_profile: Dictionary = field_file.raw

	var validated: Dictionary = validate_profile_data(
		aircraft_profile, field_profile, aircraft_id, aircraft_identity, field
	)
	if not validated.get("ok", false):
		return validated

	# Collision clearance depends on accepted model, terrain and lake geometry as well
	# as the world. The manager performs that separate check before roster replacement.
	var identity := {
		"format": IDENTITY_FORMAT,
		"aircraft_id": aircraft_id,
		"aircraft_data_path": AIRCRAFT_DATA_PATH,
		"aircraft_data_format": AIRCRAFT_DATA_FORMAT,
		"aircraft_data_sha256": str(aircraft_profile.aircraft_data.sha256),
		"controller_path": PILOT_SOURCE_PATH,
		"controller_sha256": str(aircraft_profile.controller.sha256),
		"controller_dependencies": aircraft_profile.controller.dependencies.duplicate(true),
		"solver_sha256": str(validated.solver_sha256),
		"solver_qualification_sha256": str(validated.solver_qualification_sha256),
		"solver_normalization": SOLVER_NORMALIZATION,
		"engine_version": str(aircraft_profile.engine_version),
		"field_profile_id": field_profile_id,
		"field_data_path": CLUB_FIELD_PATH,
		"field_data_format": FIELD_DATA_FORMAT,
		"field_data_sha256": str(field_profile.field_source.sha256),
		"aircraft_profile_path": aircraft_profile_path,
		"aircraft_profile_sha256": str(aircraft_file.sha256),
		"field_profile_path": field_profile_path,
		"field_profile_sha256": str(field_file.sha256),
	}
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"profile": validated.profile.duplicate(true),
		"field_profile": validated.field_profile.duplicate(true),
		"identity": identity.duplicate(true),
	}


## Exact executable identity, including prerelease status and source revision.
## Numeric 4.8.0 alone cannot distinguish the qualified beta from another build.
static func engine_build_identity(info: Dictionary) -> String:
	var version := "%d.%d" % [int(info.get("major", -1)), int(info.get("minor", -1))]
	var patch: int = int(info.get("patch", -1))
	if patch != 0:
		version += ".%d" % patch
	return "%s.%s.%s.%s" % [version, str(info.get("status", "")),
		str(info.get("build", "")), str(info.get("hash", "")).left(9)]


## Validate caller-owned copies without changing them. Useful to qualify data mutations offline.
static func validate_profile_data(
	aircraft_raw: Variant,
	field_raw: Variant,
	aircraft_id: String,
	aircraft_identity: Dictionary,
	field: Dictionary
) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(aircraft_raw) != TYPE_DICTIONARY:
		return _failure(PackedStringArray(["aircraft profile: expected an object"]))
	if typeof(field_raw) != TYPE_DICTIONARY:
		return _failure(PackedStringArray(["field profile: expected an object"]))

	var profile: Dictionary = aircraft_raw
	var field_profile: Dictionary = field_raw
	_check_keys(errors, "aircraft profile", profile, AIRCRAFT_PROFILE_KEYS, AIRCRAFT_PROFILE_KEYS)
	_check_keys(errors, "field profile", field_profile, FIELD_PROFILE_KEYS, FIELD_PROFILE_KEYS)
	if profile.get("format") != AIRCRAFT_FORMAT:
		errors.append("aircraft profile.format: expected '%s'" % AIRCRAFT_FORMAT)
	if field_profile.get("format") != FIELD_FORMAT:
		errors.append("field profile.format: expected '%s'" % FIELD_FORMAT)

	if aircraft_id != ACCEPTED_AIRCRAFT_ID:
		errors.append("aircraft_id: only the qualified Jensen Das Ugly Stik 60 is accepted")
	var catalog_entry: Dictionary = Catalog.entry(aircraft_id)
	if catalog_entry.is_empty() or not Catalog.can_fly(aircraft_id) or Catalog.is_rotorcraft(aircraft_id):
		errors.append("aircraft_id: selected catalog entry is unavailable for fixed-wing companions")
	if str(catalog_entry.get("data", "")) != AIRCRAFT_DATA_PATH:
		errors.append("aircraft catalog data path no longer matches the qualified source")
	if profile.get("id") != ACCEPTED_AIRCRAFT_ID or profile.get("catalog_id") != ACCEPTED_AIRCRAFT_ID:
		errors.append("aircraft profile id/catalog_id must match the selected catalog identity")

	var aircraft_source: Dictionary = _object(errors, "aircraft_data", profile.get("aircraft_data"))
	_check_keys(errors, "aircraft_data", aircraft_source, ["path", "format", "sha256"], ["path", "format", "sha256"])
	if aircraft_source.get("path") != AIRCRAFT_DATA_PATH:
		errors.append("aircraft_data.path: unsupported source path")
	if aircraft_source.get("format") != AIRCRAFT_DATA_FORMAT:
		errors.append("aircraft_data.format: expected '%s'" % AIRCRAFT_DATA_FORMAT)
	var aircraft_sha: String = _read_sha256(errors, "aircraft_data.sha256", aircraft_source.get("sha256"))
	var expected_aircraft_sha: String = _sha256_file(errors, "aircraft data", AIRCRAFT_DATA_PATH)
	if not aircraft_sha.is_empty() and aircraft_sha != expected_aircraft_sha:
		errors.append("aircraft_data.sha256: current aircraft data does not match this profile")
	_check_keys(errors, "aircraft_identity", aircraft_identity, ["format", "sha256"], ["format", "sha256"])
	if aircraft_identity.size() != 2:
		errors.append("aircraft_identity: expected exactly format and sha256")
	if aircraft_identity.get("format") != AIRCRAFT_DATA_FORMAT:
		errors.append("aircraft_identity.format: expected '%s'" % AIRCRAFT_DATA_FORMAT)
	var runtime_aircraft_sha: String = _read_sha256(errors, "aircraft_identity.sha256", aircraft_identity.get("sha256"))
	if not aircraft_sha.is_empty() and runtime_aircraft_sha != aircraft_sha:
		errors.append("aircraft_identity.sha256: accepted session data does not match this profile")
	if not expected_aircraft_sha.is_empty() and runtime_aircraft_sha != expected_aircraft_sha:
		errors.append("aircraft_identity.sha256: accepted session data is not the current source file")

	var controller: Dictionary = _object(errors, "controller", profile.get("controller"))
	_check_keys(errors, "controller", controller, ["path", "sha256", "dependencies"], ["path", "sha256", "dependencies"])
	if controller.get("path") != PILOT_SOURCE_PATH:
		errors.append("controller.path: unsupported pilot source path")
	var controller_sha: String = _read_sha256(errors, "controller.sha256", controller.get("sha256"))
	var expected_controller_sha: String = _sha256_file(errors, "pilot controller", PILOT_SOURCE_PATH)
	if not controller_sha.is_empty() and controller_sha != expected_controller_sha:
		errors.append("controller.sha256: current pilot source does not match this profile")
	var dependencies: Dictionary = _object(errors, "controller.dependencies", controller.get("dependencies"))
	_check_keys(errors, "controller.dependencies", dependencies, [CIRCUIT_SOURCE_PATH], [CIRCUIT_SOURCE_PATH])
	var base_sha: String = _read_sha256(errors, "controller.dependencies circuit SHA", dependencies.get(CIRCUIT_SOURCE_PATH))
	var actual_base_sha: String = _sha256_file(errors, "circuit controller", CIRCUIT_SOURCE_PATH)
	if not base_sha.is_empty() and base_sha != actual_base_sha:
		errors.append("controller.dependencies: current circuit source does not match this profile")
	# Bind the declared dependency to the script Godot actually resolves, not just
	# a matching unrelated file in the profile's metadata.
	var pilot_script: Script = load(PILOT_SOURCE_PATH) as Script
	if pilot_script == null or pilot_script.get_base_script() == null \
			or pilot_script.get_base_script().resource_path != CIRCUIT_SOURCE_PATH:
		errors.append("controller.dependencies: pilot must inherit the qualified circuit source")

	var solver: Dictionary = _object(errors, "solver", profile.get("solver"))
	_check_keys(errors, "solver", solver, ["sha256", "normalization"], ["sha256", "normalization"])
	if solver.get("normalization") != SOLVER_NORMALIZATION:
		errors.append("solver.normalization: only strict UTF-8 with LF line endings is supported")
	var solver_sha: String = _read_sha256(errors, "solver.sha256", solver.get("sha256"))
	var current_solver_identity: Dictionary = current_solver_qualification_identity()
	if not current_solver_identity.get("ok", false):
		errors.append_array(current_solver_identity.get("errors", PackedStringArray()))
	elif not solver_sha.is_empty() and solver_sha != str(current_solver_identity.get("sha256", "")) \
			and not _accept_current_solver:
		errors.append("solver.sha256: current normalized physics and simulation sources do not match this profile; "
			+ REBIND_HINT)
	var raw_solver_identity: String = FlightLog.solver_identity()
	if raw_solver_identity == "unavailable-export":
		errors.append("solver: raw source identity is unavailable in this export; qualification is open")
	elif not _is_sha256(raw_solver_identity):
		errors.append("solver: raw source identity is unavailable or malformed")

	if profile.get("engine_version") != QUALIFIED_ENGINE_VERSION:
		errors.append("engine_version: profile must pin the qualified Godot %s build" % QUALIFIED_ENGINE_VERSION)
	var current_engine_version: String = engine_build_identity(Engine.get_version_info())
	if current_engine_version != QUALIFIED_ENGINE_VERSION:
		errors.append("engine_version: runtime is %s; qualification requires Godot %s" % [current_engine_version, QUALIFIED_ENGINE_VERSION])
	if Engine.physics_ticks_per_second != QUALIFIED_PHYSICS_HZ:
		errors.append("physics rate: companion qualification requires %d Hz" % QUALIFIED_PHYSICS_HZ)

	_validate_aircraft_qualification(errors, profile)
	_validate_unknown_performance(errors, profile.get("performance"))

	var field_profile_id: String = str(profile.get("field_profile_id", ""))
	if field_profile_id != "club-default" or not FIELD_PROFILE_PATHS.has(field_profile_id):
		errors.append("field_profile_id: only the qualified Club field profile is supported")
	var field_source: Dictionary = _object(errors, "field_source", field_profile.get("field_source"))
	_check_keys(errors, "field_source", field_source, ["path", "format", "sha256", "field_id"], ["path", "format", "sha256", "field_id"])
	if field_source.get("path") != CLUB_FIELD_PATH:
		errors.append("field_source.path: unsupported field source path")
	if field_source.get("format") != FIELD_DATA_FORMAT:
		errors.append("field_source.format: expected '%s'" % FIELD_DATA_FORMAT)
	if field_source.get("field_id") != "default" or field_profile.get("id") != "club-default":
		errors.append("field profile identity must match the default Club field")
	var field_sha: String = _read_sha256(errors, "field_source.sha256", field_source.get("sha256"))
	var expected_field_sha: String = _sha256_file(errors, "Club field data", CLUB_FIELD_PATH)
	if not field_sha.is_empty() and field_sha != expected_field_sha:
		errors.append("field_source.sha256: current field data does not match this profile")

	var loaded_field: Dictionary = FieldLoader.load_from(CLUB_FIELD_PATH)
	if not loaded_field.get("ok", false):
		errors.append_array(loaded_field.get("errors", PackedStringArray()))
	else:
		var normalized_field: Variant = loaded_field.get("field", {})
		if typeof(normalized_field) != TYPE_DICTIONARY or field != normalized_field:
			errors.append("field: supplied normalized geometry differs from the pinned Club field source")

	_validate_field_profile(errors, field_profile, field if loaded_field.get("ok", false) else {})

	if not errors.is_empty():
		return _failure(errors)
	return {
		"ok": true,
		"errors": errors,
		"profile": profile.duplicate(true),
		"field_profile": field_profile.duplicate(true),
		"solver_sha256": raw_solver_identity,
		"solver_qualification_sha256": str(current_solver_identity.sha256),
	}


static func _validate_aircraft_qualification(errors: PackedStringArray, profile: Dictionary) -> void:
	var qualification: Dictionary = _object(errors, "qualification", profile.get("qualification"))
	_check_keys(errors, "qualification", qualification,
		["status", "activities", "skill", "start_modes", "unqualified_modes", "roster_count", "evidence"],
		["status", "activities", "skill", "start_modes", "unqualified_modes", "roster_count", "evidence"])
	if qualification.get("status") != "qualified_for_narrow_scope":
		errors.append("qualification.status: expected the narrow qualified scope")
	_expect_string_array(errors, "qualification.activities", qualification.get("activities"), ACTIVITY_ALLOWLIST)
	if qualification.get("skill") != QUALIFIED_SKILL:
		errors.append("qualification.skill: only the evidenced experienced skill is accepted")
	_expect_string_array(errors, "qualification.start_modes", qualification.get("start_modes"), QUALIFIED_START_MODES)
	_expect_string_array(errors, "qualification.unqualified_modes", qualification.get("unqualified_modes"), UNQUALIFIED_MODES)
	if qualification.get("evidence") != EVIDENCE_PATH:
		errors.append("qualification.evidence: unsupported evidence reference")
	_validate_roster_count(errors, "qualification.roster_count", qualification.get("roster_count"))


static func _validate_unknown_performance(errors: PackedStringArray, raw: Variant) -> void:
	const PERFORMANCE_KEYS := ["stall_speed", "approach_speed", "cruise_speed", "entry_speed"]
	var performance: Dictionary = _object(errors, "performance", raw)
	_check_keys(errors, "performance", performance, PERFORMANCE_KEYS, PERFORMANCE_KEYS)
	for name: String in PERFORMANCE_KEYS:
		var item: Dictionary = _object(errors, "performance." + name, performance.get(name))
		_check_keys(errors, "performance." + name, item, ["status"], ["status"])
		if item.get("status") != "unknown":
			errors.append("performance.%s.status: this profile has no qualified value" % name)


static func _validate_field_profile(errors: PackedStringArray, profile: Dictionary, field: Dictionary) -> void:
	if profile.get("format") != FIELD_FORMAT or profile.get("id") != "club-default":
		return
	if profile.get("runway_id") != "runway":
		errors.append("runway_id: expected the default Club field runway reference")
	if profile.get("static_route_clearance") != "requires_session_check":
		errors.append("static_route_clearance: actual session geometry must be checked at admission")

	var circuit: Dictionary = _object(errors, "circuit", profile.get("circuit"))
	_check_keys(errors, "circuit", circuit,
		["shape", "side", "center_north", "center_east", "radius", "base_agl", "slot_agl_step", "roster_count"],
		["shape", "side", "center_north", "center_east", "radius", "base_agl", "slot_agl_step", "roster_count"])
	if circuit.get("shape") != "circle" or circuit.get("side") != "north":
		errors.append("circuit: only the qualified north-side circular route is supported")
	var center_north: Dictionary = _quantity(errors, "circuit.center_north", circuit.get("center_north"), "m")
	var center_east: Dictionary = _quantity(errors, "circuit.center_east", circuit.get("center_east"), "m")
	var radius: Dictionary = _quantity(errors, "circuit.radius", circuit.get("radius"), "m")
	var base_agl: Dictionary = _quantity(errors, "circuit.base_agl", circuit.get("base_agl"), "m")
	var slot_step: Dictionary = _quantity(errors, "circuit.slot_agl_step", circuit.get("slot_agl_step"), "m")
	_validate_roster_count(errors, "circuit.roster_count", circuit.get("roster_count"))
	if not _quantity_matches(center_north, 199.0):
		errors.append("circuit.center_north: must match the current default-field route geometry")
	if not _quantity_matches(center_east, 0.0):
		errors.append("circuit.center_east: must match the current default-field route geometry")
	if not _quantity_matches(radius, 80.0):
		errors.append("circuit.radius: must match the current default-field route geometry")
	if not _quantity_matches(base_agl, 35.0) or not _quantity_matches(slot_step, 20.0):
		errors.append("circuit altitude bands must match the current qualified Stik controller")
	_validate_circuit_matches_field(errors, circuit, field)

	var qualification: Dictionary = _object(errors, "field qualification", profile.get("qualification"))
	_check_keys(errors, "field qualification", qualification,
		["status", "scenarios", "counts", "duration_s", "observed", "evidence"],
		["status", "scenarios", "counts", "duration_s", "observed", "evidence"])
	if qualification.get("status") != "passed":
		errors.append("field qualification.status: expected the recorded passing matrix")
	_expect_string_array(errors, "field qualification.scenarios", qualification.get("scenarios"), QUALIFIED_SCENARIOS)
	_expect_integer_array(errors, "field qualification.counts", qualification.get("counts"), [1, 2, 3])
	if qualification.get("evidence") != EVIDENCE_PATH:
		errors.append("field qualification.evidence: unsupported evidence reference")
	var duration: Dictionary = _quantity(errors, "field qualification.duration_s", qualification.get("duration_s"), "s")
	if not _quantity_matches(duration, 120.0):
		errors.append("field qualification.duration_s: the matrix must cover 120 simulated seconds")
	_validate_observations(errors, qualification.get("observed"))


static func _validate_circuit_matches_field(errors: PackedStringArray, circuit: Dictionary, field: Dictionary) -> void:
	if typeof(field) != TYPE_DICTIONARY or field.is_empty():
		return
	var runway_id: String = str(field.get("runway", ""))
	var runway: Dictionary = {}
	var surfaces: Variant = field.get("surfaces", [])
	if typeof(surfaces) != TYPE_ARRAY:
		errors.append("field.surfaces: expected normalized surface records")
		return
	for surface_value: Variant in surfaces:
		if typeof(surface_value) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_value
		if str(surface.get("id", "")) == runway_id and str(surface.get("type", "")) == "runway":
			runway = surface
			break
	if runway.is_empty():
		errors.append("field.runway: the qualified runway surface is unavailable")
		return
	var runway_north: float = _finite_number(runway.get("center_north", NAN))
	var runway_east: float = _finite_number(runway.get("center_east", NAN))
	var runway_length: float = _finite_number(runway.get("length_east_west", NAN))
	var runway_width: float = _finite_number(runway.get("width_north_south", NAN))
	if not is_finite(runway_north) or not is_finite(runway_east) or not is_finite(runway_length) \
			or not is_finite(runway_width) or runway_length < 40.0 or runway_width <= 0.0:
		errors.append("field.runway: normalized Club runway dimensions are invalid")
		return
	var expected_radius: float = maxf(runway_length * ROUTE_RADIUS_LENGTH_FACTOR, runway_width * ROUTE_RADIUS_WIDTH_FACTOR)
	var expected_center_north: float = runway_north + ROUTE_CENTER_RADIUS_FACTOR * expected_radius \
		+ ROUTE_CENTER_WIDTH_FACTOR * runway_width
	var expected_center_east: float = runway_east
	if not _quantity_matches(_quantity(errors, "circuit.center_north", circuit.get("center_north"), "m"), expected_center_north):
		errors.append("circuit.center_north: derived center disagrees with the supplied normalized runway")
	if not _quantity_matches(_quantity(errors, "circuit.center_east", circuit.get("center_east"), "m"), expected_center_east):
		errors.append("circuit.center_east: derived center disagrees with the supplied normalized runway")
	if not _quantity_matches(_quantity(errors, "circuit.radius", circuit.get("radius"), "m"), expected_radius):
		errors.append("circuit.radius: derived radius disagrees with the supplied normalized runway")


static func _validate_observations(errors: PackedStringArray, raw: Variant) -> void:
	const OBSERVATION_UNITS := {
		"min_agl": "m", "max_agl": "m", "min_tas": "m/s", "max_tas": "m/s",
		"max_radial_error": "m", "min_player_separation": "m", "min_pair_separation": "m",
	}
	var observed: Dictionary = _object(errors, "field qualification.observed", raw)
	var keys: Array = OBSERVATION_UNITS.keys()
	_check_keys(errors, "field qualification.observed", observed, keys, keys)
	var values: Dictionary = {}
	for key_value: Variant in keys:
		var key: String = str(key_value)
		var result: Dictionary = _quantity(errors, "field qualification.observed." + key, observed.get(key), str(OBSERVATION_UNITS[key]))
		if result.get("ok", false):
			values[key] = float(result.value)
	if values.size() != keys.size():
		return
	if float(values.min_agl) < 20.0 or float(values.min_agl) > float(values.max_agl):
		errors.append("field qualification.observed: clearance values are outside the tested floor")
	if float(values.max_agl) > 75.1:
		errors.append("field qualification.observed.max_agl: exceeds the three-slot tested envelope")
	if float(values.min_tas) < 10.0 or float(values.max_tas) > 25.0 or float(values.min_tas) > float(values.max_tas):
		errors.append("field qualification.observed: TAS values are outside the tested controller range")
	if float(values.max_radial_error) > 40.0:
		errors.append("field qualification.observed.max_radial_error: exceeds the recorded route gate")
	if float(values.min_player_separation) < 30.0 or float(values.min_pair_separation) < 15.0:
		errors.append("field qualification.observed: separation is below the recorded matrix gates")


static func _validate_roster_count(errors: PackedStringArray, path: String, raw: Variant) -> void:
	var roster: Dictionary = _object(errors, path, raw)
	_check_keys(errors, path, roster, ["min", "max"], ["min", "max"])
	if _integer_value(roster.get("min", null)) != 1 or _integer_value(roster.get("max", null)) != 3:
		errors.append("%s: only the qualified one-to-three aircraft count is accepted" % path)


static func _quantity(errors: PackedStringArray, path: String, raw: Variant, expected_unit: String) -> Dictionary:
	var first_error: int = errors.size()
	var value := _object(errors, path, raw)
	_check_keys(errors, path, value, QUANTITY_KEYS, QUANTITY_KEYS)
	var number: Variant = value.get("value")
	var numeric_value: float = 0.0
	if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT:
		errors.append("%s.value: expected a finite number" % path)
	else:
		numeric_value = float(number)
		if not is_finite(numeric_value):
			errors.append("%s.value: expected a finite number" % path)
	if value.get("unit") != expected_unit:
		errors.append("%s.unit: expected '%s'" % [path, expected_unit])
	if not EVIDENCE_KINDS.has(str(value.get("kind", ""))):
		errors.append("%s.kind: expected measured, derived, or estimated provenance" % path)
	var source: Variant = value.get("source")
	if typeof(source) != TYPE_STRING or str(source).strip_edges().is_empty():
		errors.append("%s.source: provenance description is required" % path)
	return {"ok": errors.size() == first_error, "value": numeric_value}


static func _quantity_matches(quantity: Dictionary, expected: float) -> bool:
	return bool(quantity.get("ok", false)) and absf(float(quantity.get("value", 0.0)) - expected) <= 1.0e-9


static func _object(errors: PackedStringArray, path: String, raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: expected an object" % path)
		return {}
	return raw


static func _check_keys(errors: PackedStringArray, path: String, object: Dictionary, allowed: Array, required: Array) -> void:
	for key_value: Variant in object.keys():
		if typeof(key_value) != TYPE_STRING and typeof(key_value) != TYPE_STRING_NAME or not allowed.has(str(key_value)):
			errors.append("%s: unsupported key '%s'" % [path, str(key_value)])
	for key_value: Variant in required:
		if not object.has(key_value):
			errors.append("%s.%s: required value is missing" % [path, str(key_value)])


static func _expect_string_array(errors: PackedStringArray, path: String, raw: Variant, expected: Array) -> void:
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: expected an array" % path)
		return
	for value: Variant in raw:
		if typeof(value) != TYPE_STRING:
			errors.append("%s: every value must be a string" % path)
			return
	if raw != expected:
		errors.append("%s: unsupported selection; expected %s" % [path, expected])


static func _expect_integer_array(errors: PackedStringArray, path: String, raw: Variant, expected: Array) -> void:
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: expected an array" % path)
		return
	var normalized: Array = []
	for value: Variant in raw:
		var integer: int = _integer_value(value)
		if integer < 0:
			errors.append("%s: every value must be an integer" % path)
			return
		normalized.append(integer)
	if normalized != expected:
		errors.append("%s: expected %s" % [path, expected])


static func _integer_value(raw: Variant) -> int:
	if typeof(raw) == TYPE_INT:
		return int(raw)
	if typeof(raw) != TYPE_FLOAT or not is_finite(float(raw)):
		return -1
	var value: float = float(raw)
	if value < 0.0 or absf(value - roundf(value)) > 1.0e-9:
		return -1
	return int(roundf(value))


static func _read_sha256(errors: PackedStringArray, path: String, raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING or not _is_sha256(str(raw)):
		errors.append("%s: expected a lowercase SHA-256" % path)
		return ""
	return str(raw)


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	const HEX := "0123456789abcdef"
	for index: int in range(value.length()):
		if HEX.find(value.substr(index, 1)) < 0:
			return false
	return true


## Fingerprint normalized solver source without changing FlightLog's raw-byte identity.
static func current_solver_qualification_identity() -> Dictionary:
	var paths: Array[String] = []
	for directory: String in SOLVER_SOURCE_DIRECTORIES:
		_append_solver_source_paths(directory, paths)
	if paths.is_empty():
		return _solver_identity_failure("solver: no physics/sim/failures GDScript sources are available; qualification is open")
	paths.sort()
	var source_bytes: Dictionary = {}
	for source_path: String in paths:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source_path)
		if bytes.is_empty():
			return _solver_identity_failure("solver: source file '%s' is missing or empty; qualification is open" % source_path)
		source_bytes[source_path] = bytes
	return canonical_solver_identity(paths, source_bytes)


## Pure helper shared with mutation checks; only newline representation is normalized.
static func canonical_solver_identity(source_paths: Array[String], source_bytes_by_path: Dictionary) -> Dictionary:
	if source_paths.is_empty():
		return _solver_identity_failure("solver: source list is empty; qualification is open")
	if source_bytes_by_path.size() != source_paths.size():
		return _solver_identity_failure("solver: source list and byte map do not match; qualification is open")

	var sorted_paths: Array[String] = source_paths.duplicate()
	sorted_paths.sort()
	var seen_paths: Dictionary = {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for source_path: String in sorted_paths:
		if seen_paths.has(source_path):
			return _solver_identity_failure("solver: duplicate source path '%s'; qualification is open" % source_path)
		seen_paths[source_path] = true
		var supported_path := false
		for directory: String in SOLVER_SOURCE_DIRECTORIES:
			if source_path.begins_with(directory + "/") and source_path.ends_with(".gd"):
				supported_path = true
				break
		if not supported_path:
			return _solver_identity_failure("solver: unsupported source path '%s'; qualification is open" % source_path)
		if not source_bytes_by_path.has(source_path):
			return _solver_identity_failure("solver: source bytes for '%s' are missing; qualification is open" % source_path)
		var raw_bytes: Variant = source_bytes_by_path[source_path]
		if typeof(raw_bytes) != TYPE_PACKED_BYTE_ARRAY:
			return _solver_identity_failure("solver: source '%s' is not a byte array; qualification is open" % source_path)
		var source_bytes: PackedByteArray = raw_bytes
		if source_bytes.is_empty():
			return _solver_identity_failure("solver: source '%s' is empty; qualification is open" % source_path)
		var source_text: String = source_bytes.get_string_from_utf8()
		if source_text.to_utf8_buffer() != source_bytes:
			return _solver_identity_failure("solver: source '%s' is not valid UTF-8; qualification is open" % source_path)
		var normalized_text: String = source_text.replace("\r\n", "\n").replace("\r", "\n")
		digest.update(source_path.to_utf8_buffer())
		digest.update(normalized_text.to_utf8_buffer())
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"sha256": digest.finish().hex_encode(),
		"source_count": sorted_paths.size(),
		"normalization": SOLVER_NORMALIZATION,
	}


static func _append_solver_source_paths(directory: String, paths: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			paths.append(directory.path_join(file))
	for child: String in DirAccess.get_directories_at(directory):
		_append_solver_source_paths(directory.path_join(child), paths)


static func _solver_identity_failure(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message]), "sha256": "", "source_count": 0}


static func _sha256_file(errors: PackedStringArray, label: String, path: String) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		errors.append("%s: cannot read source file '%s'" % [label, path])
		return ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()


static func _read_json_object(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "errors": PackedStringArray(["%s: profile file is missing or empty" % path])}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return {"ok": false, "errors": PackedStringArray(["%s: JSON error at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()]])}
	if typeof(parser.data) != TYPE_DICTIONARY:
		return {"ok": false, "errors": PackedStringArray(["%s: expected a top-level object" % path])}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return {"ok": true, "errors": PackedStringArray(), "raw": parser.data, "sha256": digest.finish().hex_encode()}


static func _finite_number(raw: Variant) -> float:
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return NAN
	var value: float = float(raw)
	return value if is_finite(value) else NAN


static func _failure(errors: PackedStringArray) -> Dictionary:
	return {
		"ok": false,
		"errors": errors.duplicate(),
		"profile": {},
		"field_profile": {},
		"identity": {},
	}
