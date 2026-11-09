extends SceneTree

const Loader := preload("res://ai/companions/profile_loader.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Config := preload("res://ai/companions/config.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Session := preload("res://sim/flight_session.gd")

var checks := 0
var failures := 0


func _check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, " ", str(detail))


func _initialize() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(Loader.BEHAVIOR_MANIFEST_PATH))
	_check("versioned manifest is a JSON object", manifest is Dictionary)
	if not manifest is Dictionary:
		quit(1)
		return
	var parsed: Dictionary = Loader.parse_behavior_manifest(FileAccess.get_file_as_bytes(Loader.BEHAVIOR_MANIFEST_PATH))
	_check("actual manifest bytes parse strictly", parsed.ok and parsed.raw == manifest)
	var duplicate := '{"format":"one","format":"two","sources":{}}'.to_utf8_buffer()
	var duplicate_result: Dictionary = Loader.parse_behavior_manifest(duplicate)
	_check("duplicate manifest keys reject before decoding", not duplicate_result.ok
		and str(duplicate_result.errors).contains("Duplicate object key"), duplicate_result.errors)
	var alias := '{"sources":{"pilot":"one","\\u0070ilot":"two"}}'.to_utf8_buffer()
	var alias_result: Dictionary = Loader.parse_behavior_manifest(alias)
	_check("escaped duplicate source keys reject before decoding", not alias_result.ok
		and str(alias_result.errors).contains("Duplicate object key"), alias_result.errors)
	var overlong := PackedByteArray()
	overlong.resize(Loader.BEHAVIOR_MANIFEST_MAX_BYTES + 1)
	_check("oversized manifest bytes reject before parsing", not Loader.parse_behavior_manifest(overlong).ok)
	var sources: Dictionary = {}
	for path: String in Loader.BEHAVIOR_SOURCE_PATHS:
		sources[path] = FileAccess.get_file_as_bytes(path)
	var expected_failure: bool = OS.get_environment("OPENRC_BEHAVIOR_EXPECT_REFUSAL") == "1"
	var valid: Dictionary = Loader.validate_behavior_manifest(manifest, sources)
	_check("current source set matches the expected admission outcome", not valid.ok if expected_failure else valid.ok, valid.errors)
	var aircraft: Dictionary = AircraftData.load_file(Loader.AIRCRAFT_DATA_PATH)
	var field: Dictionary = FieldLoader.load_from()
	var admission: Dictionary = Loader.load_profile(Loader.ACCEPTED_AIRCRAFT_ID, aircraft.input_identity, field.field)
	_check("actual profile admission enforces the manifest", not admission.get("ok", true) if expected_failure else admission.get("ok", false), admission.get("errors", []))
	if expected_failure:
		var mentions_source := false
		for error: String in admission.get("errors", []):
			mentions_source = mentions_source or error.contains("behavior source")
		_check("source mutation refusal identifies behavior source", mentions_source, admission.get("errors", []))
		print("companion behavior manifest: %d checks, %d failed" % [checks, failures])
		quit(1 if failures else 0)
		return
	_check("returned identity is versioned and binds the exact manifest", admission.identity.format == Loader.IDENTITY_FORMAT
		and admission.identity.behavior_manifest_sha256 == admission.profile.behavior_manifest.sha256)
	var player := Session.new()
	player.input_enabled = false
	player.setup()
	var first: Dictionary = Config.defaults()
	first.enabled = true
	first.engine_volume = 0.0
	first.show_labels = false
	first.label_distance_m = 50.0
	var second: Dictionary = first.duplicate(true)
	second.engine_volume = 1.0
	second.show_labels = true
	second.label_distance_m = 500.0
	var first_check: Dictionary = Manager.validate_context(player, field.field, "club_field", first)
	var second_check: Dictionary = Manager.validate_context(player, field.field, "club_field", second)
	_check("presentation settings do not change admission or behavior identity", first_check.get("ok", false)
		and second_check.get("ok", false) and first_check.qualification.identity == second_check.qualification.identity,
		{first = first_check.get("errors", []), second = second_check.get("errors", [])})
	player.free()
	_check("manifest includes required flight and admission owners", Loader.BEHAVIOR_SOURCE_PATHS.has("res://main.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://app_root.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://data/field_loader.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://data/lake_loader.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://scenery/collision_world.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://workshop/strict_json.gd")
		and Loader.BEHAVIOR_SOURCE_PATHS.has("res://ai/companions/seed_allocator.gd"))
	var crlf: Dictionary = {}
	for path: String in Loader.BEHAVIOR_SOURCE_PATHS:
		var text: String = sources[path].get_string_from_utf8().replace("\r\n", "\n")
		crlf[path] = text.replace("\n", "\r\n").to_utf8_buffer()
	_check("behavior source hashes normalize CRLF", Loader.validate_behavior_manifest(manifest, crlf).ok)
	for path: String in Loader.BEHAVIOR_SOURCE_PATHS:
		var changed: Dictionary = sources.duplicate()
		var bytes: PackedByteArray = sources[path].duplicate()
		bytes.append_array("\n# intentional source drift\n".to_utf8_buffer())
		changed[path] = bytes
		_check("each behavior source mutation rejects: " + path,
			not Loader.validate_behavior_manifest(manifest, changed).ok)
	var changed_manifest: Dictionary = manifest.duplicate(true)
	changed_manifest.sources.erase(Loader.BEHAVIOR_SOURCE_PATHS[0])
	_check("manifest missing a required source rejects", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.sources["res://render/engine_sound.gd"] = "0".repeat(64)
	_check("manifest cannot silently grow its source set", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.sources["res://ai/companions/../pilot.gd"] = "0".repeat(64)
	_check("path aliases cannot enter the manifest", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.sources[Loader.BEHAVIOR_SOURCE_PATHS[0]] = "A".repeat(64)
	_check("digest spelling must be lowercase SHA-256", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.format = "openrc-ai-behavior-manifest v2"
	_check("unknown manifest version rejects", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.normalization = "whitespace-stripped"
	_check("unknown normalization rejects", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	changed_manifest = manifest.duplicate(true)
	changed_manifest.extra = true
	_check("unknown manifest metadata rejects", not Loader.validate_behavior_manifest(changed_manifest, sources).ok)
	var missing: Dictionary = sources.duplicate()
	missing.erase(Loader.BEHAVIOR_SOURCE_PATHS[0])
	_check("missing source bytes reject", not Loader.validate_behavior_manifest(manifest, missing).ok)
	var extra: Dictionary = sources.duplicate()
	extra["res://render/engine_sound.gd"] = "x".to_utf8_buffer()
	_check("extra declared bytes reject", not Loader.validate_behavior_manifest(manifest, extra).ok)
	var empty: Dictionary = sources.duplicate()
	empty[Loader.BEHAVIOR_SOURCE_PATHS[0]] = PackedByteArray()
	_check("empty behavior source rejects", not Loader.validate_behavior_manifest(manifest, empty).ok)
	var bare_cr: Dictionary = sources.duplicate()
	bare_cr[Loader.BEHAVIOR_SOURCE_PATHS[0]] = "extends Node\r# stray CR\n".to_utf8_buffer()
	_check("ambiguous bare CR rejects", not Loader.validate_behavior_manifest(manifest, bare_cr).ok)
	var invalid_utf8: Dictionary = sources.duplicate()
	invalid_utf8[Loader.BEHAVIOR_SOURCE_PATHS[0]] = PackedByteArray([0xc0, 0xaf])
	_check("invalid UTF-8 rejects", not Loader.validate_behavior_manifest(manifest, invalid_utf8).ok)
	print("companion behavior manifest: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
