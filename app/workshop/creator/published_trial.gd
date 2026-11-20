extends RefCounted
## Prepare a saved revision without compilation, library lookup, authentication or flight admission.
const Bytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const Resolver := preload("res://workshop/creator/source_resolver.gd")
const Source := preload("res://workshop/creator/inspected_source.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const VEHICLE := "creator_published"
const FORMAT := "openrc-creator-published-trial v1"
const CHECK_FORMAT := "openrc-creator-published-start-check v1"
const TRIAL_KEYS := ["ok", "errors", "vehicle", "data", "scale", "raw_bytes", "identity", "creator", "display_context"]
const CREATOR_KEYS := ["resolved", "source", "placement", "bindings", "appearance", "name"]
const PRESENTATION_KEYS := ["placement", "bindings", "appearance"]
const FLIGHT_UNAVAILABLE := "Published Creator flight is unavailable until its numerical and flight-context gates are qualified."


static func is_trial(value: Variant) -> bool:
	return value is Dictionary and typeof(value.get("vehicle")) == TYPE_STRING and value.vehicle == VEHICLE


## Mutable fields are detached from a branded Resolved owner. No later Store revision is consulted.
static func prepare(resolved: Variant) -> Dictionary:
	if not Resolver.is_resolved(resolved):
		return _refused("The published aircraft has not been resolved.")
	var reference: Dictionary = resolved.source_ref()
	var checked_ref: Dictionary = SourceRef.validate(reference)
	if not checked_ref.ok or not _same(reference, checked_ref.value):
		return _refused("The published aircraft reference is invalid.")
	var encoded_ref: Dictionary = Bytes.encode(reference, SourceRef.MAX_BYTES)
	if not encoded_ref.ok:
		return _refused("The published aircraft reference cannot be encoded.")
	var ref_bytes: PackedByteArray = encoded_ref.value.bytes
	var decoded_ref: Dictionary = SourceRef.from_bytes(ref_bytes)
	if not decoded_ref.ok or not _same(decoded_ref.value, reference):
		return _refused("The published aircraft reference cannot round-trip.")
	# Keep the integer revision inside canonical JSON text across generic ORFL JSON readers.
	var ref_json: String = ref_bytes.get_string_from_utf8()
	if ref_json.to_utf8_buffer() != ref_bytes:
		return _refused("The published aircraft reference is not valid UTF-8.")
	var source_value: Variant = resolved.source()
	if not (source_value is Object) or not is_instance_valid(source_value) or source_value.get_script() != Source:
		return _refused("The saved model source is not admitted.")
	var source: Source = source_value
	if not source.is_admitted() or Installation.required(source):
		return _refused(Installation.flight_unavailable(source))
	var source_bytes: PackedByteArray = source.source_bytes()
	var source_sha: String = source.sha256()
	if source_bytes.is_empty() or not Bytes.is_sha256(source_sha) or Bytes.sha256(source_bytes) != source_sha:
		return _refused("The saved model source does not match its bytes.")
	var raw: PackedByteArray = resolved.raw_bytes()
	var raw_sha: String = resolved.raw_sha256()
	if raw.is_empty() or not Bytes.is_sha256(raw_sha) or Bytes.sha256(raw) != raw_sha or not Bytes.decode(raw).ok:
		return _refused("The saved aircraft does not match its exact bytes.")
	var definition_sha: String = resolved.definition_sha256()
	if not Bytes.is_sha256(definition_sha):
		return _refused("The saved definition identity is invalid.")
	var provenance: String = resolved.provenance()
	if provenance not in [Resolver.BOUND_V2, Resolver.LEGACY_UNBOUND]:
		return _refused("The saved aircraft provenance is unsupported.")
	var aircraft_id: String = Definition.aircraft_id(reference.aircraft_uuid)
	var data: Dictionary = resolved.data()
	var model: Variant = data.get("model")
	var input_identity: Variant = data.get("input_identity")
	if not data.get("ok", false) or not model is Dictionary or not input_identity is Dictionary \
			or typeof(input_identity.get("format")) != TYPE_STRING or input_identity.format != AircraftData.FORMAT \
			or input_identity.get("sha256") != raw_sha or model.get("id") != aircraft_id:
		return _refused("The saved aircraft is not a matching aircraft v2 record.")
	var loaded: Dictionary = RecordLoader.load_bytes(raw, aircraft_id)
	if not loaded.get("ok", false) or not _same(loaded, data):
		return _refused("The saved model is not what its exact bytes load to.")
	var controls: Variant = model.get("controls")
	if not controls is Dictionary:
		return _refused("The saved aircraft controls are invalid.")
	if provenance == Resolver.BOUND_V2:
		if controls.get("servo_integration") != Definition.ServoLaw.LAW:
			return _refused("The saved compile binding has an unsupported law.")
	elif controls.has("servo_integration"):
		return _refused("The legacy aircraft has an unbound servo law.")
	var presentation: Dictionary = resolved.presentation()
	if not _closed(presentation, PRESENTATION_KEYS) or not presentation.placement is Dictionary \
			or not presentation.bindings is Dictionary or not presentation.appearance is Dictionary:
		return _refused("The saved presentation is invalid.")
	if not Placement.resolve(presentation.placement).ok or not VisualBuilder.validate_bindings(source, presentation.bindings).ok \
			or not VisualBuilder.validate_appearance(presentation.appearance).ok:
		return _refused("The saved placement, moving parts or paint is invalid.")
	var encoded_presentation: Dictionary = Bytes.encode(presentation, Limits.DRAFT_BYTES)
	if not encoded_presentation.ok:
		return _refused("The saved presentation cannot be identified.")
	var display_name: String = resolved.display_name()
	var identity := {"format": FORMAT, "aircraft_id": aircraft_id,
		"source_ref_json": ref_json, "source_ref_sha256": encoded_ref.value.sha256,
		"raw_sha256": raw_sha, "definition_sha256": definition_sha, "source_sha256": source_sha,
		"source_file_name": source.file_name(), "presentation_sha256": encoded_presentation.value.sha256,
		"provenance": provenance, "name": display_name, "experimental": true}
	var encoded_identity: Dictionary = Bytes.encode(identity)
	if not encoded_identity.ok:
		return _refused("The saved trial identity cannot be encoded.")
	identity["trial_id"] = "creator-published-" + encoded_identity.value.sha256
	return {"ok": true, "errors": PackedStringArray(), "vehicle": VEHICLE, "data": data,
		"scale": 1.0, "raw_bytes": raw, "identity": identity,
		"creator": {"resolved": resolved, "source": source, "placement": presentation.placement,
			"bindings": presentation.bindings, "appearance": presentation.appearance, "name": display_name},
		"display_context": {"state": "saved", "name": display_name, "saved_name": display_name, "revision": reference.revision}}


## Reconstruct every field from the retained owner; serialized dictionaries cannot impersonate it.
static func verify(value: Variant) -> Dictionary:
	if not _closed(value, TRIAL_KEYS) or not is_trial(value):
		return _refused("This is not a saved Creator trial.")
	var creator: Variant = value.get("creator")
	if not _closed(creator, CREATOR_KEYS):
		return _refused("The saved Creator trial payload is invalid.")
	var resolved: Variant = creator.get("resolved")
	if not Resolver.is_resolved(resolved):
		return _refused("The saved Creator trial has no resolved owner.")
	var expected: Dictionary = prepare(resolved)
	if not expected.get("ok", false):
		return expected
	if not _same(expected, value):
		return _refused("The saved Creator trial does not match its resolved owner.")
	return {"ok": true, "errors": PackedStringArray(), "aircraft_id": expected.identity.aircraft_id}


## Numerical, live start, environment and contact admission are independent and remain unavailable.
static func check_start(_trial: Variant, normalized_field: Dictionary, _weather_config: Dictionary, start_choice: String) -> Dictionary:
	return {"ok": false, "available": false, "reason": FLIGHT_UNAVAILABLE, "start_choice": start_choice,
		"field_id": str(normalized_field.get("id", "")), "diagnostics": {"format": CHECK_FORMAT}, "duration_ms": 0.0}


static func _closed(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or key not in keys:
			return false
	return true


## Dictionary order is irrelevant; key/scalar types, packed bits and object identities are exact.
static func _same(a: Variant, b: Variant, depth: int = 0) -> bool:
	if depth > Limits.JSON_DEPTH + 8 or typeof(a) != typeof(b):
		return false
	var kind := typeof(a)
	if kind == TYPE_OBJECT:
		return is_instance_valid(a) and is_instance_valid(b) and a == b
	if kind in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
		return false
	if kind == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			var found := false
			for other: Variant in b:
				if _same(key, other, depth + 1):
					if not _same(a[key], b[other], depth + 1):
						return false
					found = true
					break
			if not found:
				return false
		return true
	if kind == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same(a[index], b[index], depth + 1):
				return false
		return true
	if kind in [TYPE_STRING, TYPE_STRING_NAME]:
		return a == b
	if kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY and a.size() != b.size():
		return false
	return var_to_bytes(a) == var_to_bytes(b)


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([reason])}
