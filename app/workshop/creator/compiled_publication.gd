extends RefCounted
## Capture a single Creator document and the accepted candidate it compiled. This is an
## in-process ownership convention, not a boundary against arbitrary trusted GDScript.
const R := preload("res://workshop/creator/result.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const AcceptedCandidate := preload("res://workshop/creator/accepted_candidate.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const Source := preload("res://workshop/creator/inspected_source.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")


class Captured extends RefCounted:
	var _sealed := false
	var _publication := {}
	var _binding := {}

	## Only capture() constructs this owner; GDScript privacy is a convention.
	func _seal(publication: Dictionary, binding: Dictionary) -> bool:
		if _sealed or publication.is_empty() or binding.is_empty() \
				or typeof(publication.get("raw_bytes")) != TYPE_PACKED_BYTE_ARRAY \
				or typeof(publication.get("source_bytes")) != TYPE_PACKED_BYTE_ARRAY:
			return false
		_publication = publication.duplicate(true)
		_publication["raw_bytes"] = (publication.raw_bytes as PackedByteArray).duplicate()
		_publication["source_bytes"] = (publication.source_bytes as PackedByteArray).duplicate()
		_binding = binding.duplicate(true)
		_sealed = true
		return true

	func publication() -> Dictionary:
		if not _sealed:
			return {}
		var copied := _publication.duplicate(true)
		copied["raw_bytes"] = (_publication.raw_bytes as PackedByteArray).duplicate()
		copied["source_bytes"] = (_publication.source_bytes as PackedByteArray).duplicate()
		return copied

	func binding() -> Dictionary:
		return _binding.duplicate(true) if _sealed else {}


static func is_captured(value: Variant) -> bool:
	if not (value is Object) or not is_instance_valid(value):
		return false
	return value.get_script() == Captured and bool(value.get("_sealed"))


## Capture uses the exact base Authoring script, not a caller-defined duck type. The captured raw
## bytes only come from that document's accepted candidate, never a publication dictionary.
static func capture(document: Variant, step: String = "") -> Dictionary:
	var authoring: Script = load("res://workshop/creator/authoring.gd")
	if not (document is Object) or not is_instance_valid(document) or document.get_script() != authoring:
		return R.fail(R.RECORD_INVALID, "This aircraft document cannot be captured.")
	var revision: int = document.revision
	var snapshot: Dictionary = document.snapshot(step)
	var source: Source = document.source()
	if source == null or source.get_script() != Source or not source.is_admitted():
		return R.fail(R.SOURCE_MISSING, "Import a model first.", "source", "import")
	# The first milestone does not authorize recognized ClearView sources, even if reviewed.
	if Installation.required(source) or not document.source_installation_proposal().is_empty():
		return R.fail(R.UNSUPPORTED_CAPABILITY, Installation.FLIGHT_UNAVAILABLE, "flight_qualification", "review_test")
	if not document.placement_result().ok:
		return R.fail(R.DATUM_UNRESOLVED, "Confirm the model orientation, size and datum.", "placement", "orient_size")
	var bound: Dictionary = VisualBuilder.validate_bindings(source, document.bindings())
	if not bound.ok:
		return bound
	var paint: Dictionary = VisualBuilder.validate_appearance(document.appearance())
	if not paint.ok:
		return paint
	var checked: Dictionary = Definition.validate_complete(document.definition())
	if not checked.ok:
		return R.fail_all(checked.diagnostics)
	var definition: Dictionary = checked.value
	if definition.get("format") != Definition.SERVO_FORMAT or definition.get("servo_integration") != Definition.ServoLaw.LAW \
			or definition.has("source_observations") or definition.has("source_installation"):
		return R.fail(R.UNSUPPORTED_CAPABILITY, "This publication requires the supported Creator servo law.", "servo_integration", "controls_ground")
	var written: Dictionary = Bytes.encode(definition)
	if not written.ok:
		return written
	var compiled: Dictionary = document.compile()
	if not compiled.ok:
		return compiled
	var candidate: Variant = compiled.get("value")
	if not AcceptedCandidate.is_accepted(candidate):
		return R.fail(R.BUILD_INVALID, "The aircraft was not accepted by the compiler.")
	var raw: PackedByteArray = candidate.raw_bytes()
	var raw_sha := Bytes.sha256(raw)
	var uuid: String = document.aircraft_uuid()
	if candidate.definition_sha256() != written.value.sha256 or candidate.raw_sha256() != raw_sha \
			or candidate.aircraft_id() != Definition.aircraft_id(uuid) or not valid_pair(definition, raw, uuid):
		return _mismatch()
	var source_bytes := source.source_bytes()
	if source_bytes.is_empty() or Bytes.sha256(source_bytes) != source.sha256():
		return _mismatch()
	var publication := {
		"aircraft_uuid": uuid, "name": document.name, "definition": definition.duplicate(true),
		"raw_bytes": raw, "source_bytes": source_bytes, "source_file_name": source.file_name(),
		"placement": document.placement(), "bindings": document.bindings(),
		"appearance": document.appearance(), "snapshot": snapshot,
	}
	var binding := Binding.make(written.value.sha256, raw_sha)
	# A name edit does not increment revision, so compare the complete snapshot as well.
	if document.revision != revision or document.snapshot(step) != snapshot or document.source() != source \
			or document.placement() != publication.placement or document.bindings() != publication.bindings \
			or document.appearance() != publication.appearance or binding.is_empty():
		return _mismatch()
	var captured := Captured.new()
	if not captured._seal(publication, binding):
		return _mismatch()
	return R.ok(captured)


## Read-only validation used both at capture and when a stored v2 pair is reopened. This validates
## structure, scope, UUID and law, not derivation of raw bytes from the definition.
static func valid_pair(definition: Dictionary, raw: PackedByteArray, uuid: String) -> bool:
	var checked: Dictionary = Definition.validate_complete(definition)
	if not checked.ok or checked.value.get("format") != Definition.SERVO_FORMAT \
			or checked.value.get("aircraft_uuid") != uuid or checked.value.get("servo_integration") != Definition.ServoLaw.LAW \
			or checked.value.has("source_observations") or checked.value.has("source_installation"):
		return false
	var canonical: Dictionary = Bytes.encode(checked.value)
	var supplied: Dictionary = Bytes.encode(definition)
	if not canonical.ok or not supplied.ok or canonical.value.bytes != supplied.value.bytes:
		return false
	var decoded: Dictionary = Bytes.decode(raw)
	if not decoded.ok:
		return false
	var record: Variant = decoded.value.data
	if not record is Dictionary or not record.get("controls") is Dictionary or not record.get("capabilities") is Dictionary:
		return false
	var caps: Dictionary = record.capabilities
	if record.get("id") != Definition.aircraft_id(uuid) or record.controls.get("servo_integration") != Definition.ServoLaw.LAW \
			or caps.get("controls") != "conventional" or caps.get("gear") != "locked_up" \
			or caps.get("propulsion_layout") != "single_tractor" or caps.get("energy") != "ocv_resistance" \
			or caps.get("flaps") != "not_simulated" or caps.get("damage") != "terminal_hull" \
			or caps.has("airframe_layout") or record.has("flaps"):
		return false
	if record.has("landing_gear") and (not record.landing_gear is Dictionary or not record.landing_gear.is_empty()):
		return false
	var loaded: Dictionary = RecordLoader.load_bytes(raw, Definition.aircraft_id(uuid))
	return loaded.get("ok", false) and loaded.get("model") is Dictionary \
		and loaded.model.get("id") == Definition.aircraft_id(uuid) and loaded.model.get("controls") is Dictionary \
		and loaded.model.controls.get("servo_integration") == Definition.ServoLaw.LAW


## Semantic check for a revision this process did not capture: the installed compiler must reproduce
## these exact physics bytes from this exact definition. Matching hashes and a receipt only record an
## association; they do not prove derivation (import closeout follow-up 02, finding 4). Compilation is
## deterministic; package data and the loader belong to Binding.PROFILE, so changing them needs a new
## profile. A mismatch means "recompile as a new revision", never silent acceptance.
static func verify_derivation(definition: Dictionary, raw: PackedByteArray, uuid: String) -> Dictionary:
	if not valid_pair(definition, raw, uuid):
		return _mismatch("saved_aircraft/compile_binding")
	var compiler: Script = load("res://workshop/creator/compiler.gd")
	var compiled: Dictionary = compiler.compile_candidate(definition)
	if not compiled.get("ok", false) or not AcceptedCandidate.is_accepted(compiled.value):
		return _mismatch("saved_aircraft/derivation")
	var candidate: Variant = compiled.value
	if candidate.raw_bytes() != raw or candidate.aircraft_id() != Definition.aircraft_id(uuid):
		return _mismatch("saved_aircraft/derivation")
	return R.ok(true)


static func _mismatch(field: String = "saved_aircraft") -> Dictionary:
	return R.fail(R.IDENTITY_MISMATCH, "The compiled aircraft does not match this document.", field, "review_test")


## Rejoin a restored document to the stored revision without recompiling historical raw bytes.
## Store verification precedes this check; the receipt records an in-process association.
static func match_document(document: Variant, value: Dictionary) -> Dictionary:
	var authoring: Script = load("res://workshop/creator/authoring.gd")
	if not (document is Object) or not is_instance_valid(document) or document.get_script() != authoring:
		return _mismatch("saved_aircraft/document")
	var canonical: Dictionary = Definition.validate_complete(document.definition())
	var stored: Variant = value.get("definition")
	if not canonical.ok or not stored is Dictionary or canonical.value != stored:
		return _mismatch("saved_aircraft/definition")
	var encoded: Dictionary = Bytes.encode(canonical.value)
	var raw: Variant = value.get("raw_bytes")
	if not encoded.ok or encoded.value.sha256 != value.get("definition_sha256") \
			or typeof(raw) != TYPE_PACKED_BYTE_ARRAY or raw.is_empty() or Bytes.sha256(raw) != value.get("raw_sha256"):
		return _mismatch("saved_aircraft/hashes")
	var uuid: String = document.aircraft_uuid()
	var loaded: Dictionary = RecordLoader.load_bytes(raw, Definition.aircraft_id(uuid))
	if not loaded.get("ok", false) or not loaded.get("model") is Dictionary \
			or loaded.model.get("id") != Definition.aircraft_id(uuid) or not loaded.model.get("controls") is Dictionary \
			or loaded.model.controls.get("servo_integration", "") != document.servo_integration():
		return _mismatch("saved_aircraft/flight_data")
	var selected: bool = not document.servo_integration().is_empty()
	if not selected:
		if value.get("record_format") == Binding.REVISION_FORMAT or value.has("compile_binding"):
			return _mismatch("saved_aircraft/legacy")
		return R.ok(true)
	if value.get("record_format") != Binding.REVISION_FORMAT \
			or not Binding.matches(value.get("compile_binding"), encoded.value.sha256, value.raw_sha256) \
			or not valid_pair(canonical.value, raw, uuid):
		return _mismatch("saved_aircraft/compile_binding")
	var source: Source = document.source()
	var source_bytes: Variant = value.get("source_bytes")
	var snapshot: Variant = value.get("snapshot")
	if source == null or not source.is_admitted() or typeof(source_bytes) != TYPE_PACKED_BYTE_ARRAY \
			or source_bytes != source.source_bytes() or source.sha256() != value.get("source_sha256") \
			or Bytes.sha256(source_bytes) != source.sha256() or source.file_name() != value.get("source_file_name") \
			or value.get("aircraft_uuid") != uuid or value.get("name") != document.name \
			or not snapshot is Dictionary or typeof(snapshot.get("step")) != TYPE_STRING \
			or not _same_json(document.snapshot(snapshot.step), snapshot) \
			or not _same_json(value.get("placement"), document.placement()) \
			or not _same_json(value.get("bindings"), document.bindings()) \
			or not _same_json(value.get("appearance"), document.appearance()):
		return _mismatch("saved_aircraft/source_presentation")
	var bound: Dictionary = VisualBuilder.validate_bindings(source, document.bindings())
	var paint: Dictionary = VisualBuilder.validate_appearance(document.appearance())
	if not document.placement_result().ok or not bound.ok or not paint.ok:
		return _mismatch("saved_aircraft/presentation")
	return R.ok(true)


static func raw_has_servo_declaration(raw: Variant) -> bool:
	if typeof(raw) != TYPE_PACKED_BYTE_ARRAY:
		return false
	var decoded: Dictionary = Bytes.decode(raw)
	return decoded.ok and decoded.value.data is Dictionary and decoded.value.data.get("controls") is Dictionary \
		and decoded.value.data.controls.has("servo_integration")


## Store's opaque JSON members turn integers into floats. Compare that representation exactly,
## without an epsilon or a JSON encoder/decoder round trip; all other value types stay strict.
static func _same_json(a: Variant, b: Variant) -> bool:
	var at := typeof(a)
	var bt := typeof(b)
	if at in [TYPE_INT, TYPE_FLOAT] and bt in [TYPE_INT, TYPE_FLOAT]:
		if (at == TYPE_INT and (a < -Bytes.Limits.MAX_SAFE_INTEGER or a > Bytes.Limits.MAX_SAFE_INTEGER)) \
				or (bt == TYPE_INT and (b < -Bytes.Limits.MAX_SAFE_INTEGER or b > Bytes.Limits.MAX_SAFE_INTEGER)):
			return false
		return is_finite(float(a)) and is_finite(float(b)) and float(a) == float(b)
	if at != bt:
		return false
	if at == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same_json(a[key], b[key]):
				return false
		return true
	if at == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same_json(a[index], b[index]):
				return false
		return true
	return a == b
