extends RefCounted
## Resolve one exact indexed Creator revision into a detached read-only owner.
## Resolution is not flight admission, a numerical qualification, or source authentication.
const R := preload("res://workshop/creator/result.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const Store := preload("res://workshop/creator/store.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Source := preload("res://workshop/creator/inspected_source.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")
const CompiledPublication := preload("res://workshop/creator/compiled_publication.gd")

const BOUND_V2 := "bound-v2"
const LEGACY_UNBOUND := "legacy-unbound"


class Resolved extends RefCounted:
	var _sealed := false
	var _ref := {}
	var _raw := PackedByteArray()
	var _data := {}
	var _source: RefCounted
	var _presentation := {}
	var _name := ""
	var _provenance := ""
	var _raw_sha256 := ""
	var _definition_sha256 := ""

	## Resolver-only ownership convention: GDScript cannot make the constructor private.
	func _seal(ref: Dictionary, raw: PackedByteArray, data: Dictionary, source: RefCounted,
			presentation: Dictionary, display_name: String, provenance: String,
			raw_sha256: String, definition_sha256: String) -> bool:
		if _sealed or raw.is_empty() or source == null or not _safe(data) or not _safe(presentation) \
				or not _safe(ref) or provenance not in ["bound-v2", "legacy-unbound"]:
			return false
		_ref = _copy(ref)
		_raw = raw.duplicate()
		_data = _copy(data)
		_source = source
		_presentation = _copy(presentation)
		_name = display_name
		_provenance = provenance
		_raw_sha256 = raw_sha256
		_definition_sha256 = definition_sha256
		_sealed = true
		return true

	func source_ref() -> Dictionary:
		return _copy(_ref) if _sealed else {}

	func raw_bytes() -> PackedByteArray:
		return _raw.duplicate() if _sealed else PackedByteArray()

	func data() -> Dictionary:
		return _copy(_data) if _sealed else {}

	## InspectedSource is a sealed in-process owner; its byte/array accessors return copies.
	func source() -> RefCounted:
		return _source if _sealed else null

	func presentation() -> Dictionary:
		return _copy(_presentation) if _sealed else {}

	func display_name() -> String:
		return _name if _sealed else ""

	func provenance() -> String:
		return _provenance if _sealed else ""

	func raw_sha256() -> String:
		return _raw_sha256 if _sealed else ""

	func definition_sha256() -> String:
		return _definition_sha256 if _sealed else ""

	## Reject references to mutable objects or executable values in data returned to consumers.
	static func _safe(value: Variant, depth: int = 0) -> bool:
		if depth > Limits.JSON_DEPTH:
			return false
		var kind := typeof(value)
		if kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]:
			return false
		if kind == TYPE_DICTIONARY:
			for key: Variant in value:
				if not _safe(key, depth + 1) or not _safe(value[key], depth + 1):
					return false
		elif kind == TYPE_ARRAY:
			for item: Variant in value:
				if not _safe(item, depth + 1):
					return false
		return true

	## Array/Dictionary duplicate preserves their typed container metadata. Packed arrays are
	## explicitly duplicated even when nested in a derived model or presentation.
	static func _copy(value: Variant) -> Variant:
		var kind := typeof(value)
		if kind == TYPE_DICTIONARY:
			var copied: Dictionary = value.duplicate()
			for key: Variant in value:
				copied[key] = _copy(value[key])
			return copied
		if kind == TYPE_ARRAY:
			var copied: Array = value.duplicate()
			for index: int in value.size():
				copied[index] = _copy(value[index])
			return copied
		if kind >= TYPE_PACKED_BYTE_ARRAY and kind <= TYPE_PACKED_VECTOR4_ARRAY:
			return value.duplicate()
		return value


static func is_resolved(value: Variant) -> bool:
	if not (value is Object) or not is_instance_valid(value):
		return false
	return value.get_script() == Resolved and bool(value.get("_sealed"))


## `library_root` is supplied by the application, never stored in SourceRef. Each call opens a
## fresh read-only Store and only follows an indexed positive revision, even for archived entries.
## Importer.inspect_bytes has no cancellation argument; callers performing this on a worker must
## invalidate stale results at their own generation boundary before adoption.
static func resolve(library_root: String, reference: Variant) -> Dictionary:
	var checked_ref: Dictionary = SourceRef.validate(reference)
	if not checked_ref.ok:
		return checked_ref
	var ref: Dictionary = checked_ref.value
	var opened: Dictionary = Store.open(library_root, {"read_only": true})
	if not opened.ok:
		return opened
	var store: RefCounted = opened.value
	# Saved selection requires the current accepted index; Store UI recovery remains explicit.
	if store.recovered_from_previous():
		store.close()
		return _invalid("current_index")
	var loaded: Dictionary = store.load_aircraft(ref.aircraft_uuid, ref.revision)
	store.close()
	if not loaded.ok:
		return loaded
	var saved: Dictionary = loaded.value
	if saved.get("aircraft_uuid") != ref.aircraft_uuid or saved.get("revision") != ref.revision \
			or saved.get("record_sha256") != ref.record_sha256:
		return R.fail(R.IDENTITY_MISMATCH, "The saved aircraft revision is not the selected one.", "source_ref")
	var source_bytes: Variant = saved.get("source_bytes")
	if typeof(source_bytes) != TYPE_PACKED_BYTE_ARRAY or source_bytes.is_empty() \
			or Bytes.sha256(source_bytes) != saved.get("source_sha256"):
		return _invalid("source")
	var inspection: Dictionary = Importer.inspect_bytes(source_bytes, str(saved.get("source_file_name", "")))
	if not inspection.ok:
		return inspection
	var source: Source = inspection.value
	if not source.is_admitted() or source.sha256() != saved.get("source_sha256") \
			or source.source_bytes() != source_bytes:
		return _invalid("source")
	# Do not turn a recognised ClearView source into a public capability by resolving it.
	if Installation.required(source):
		return R.fail(R.UNSUPPORTED_CAPABILITY, Installation.FLIGHT_UNAVAILABLE, "flight_qualification", "review_test")
	var placement: Variant = saved.get("placement")
	var bindings: Variant = saved.get("bindings")
	var appearance: Variant = saved.get("appearance")
	if not placement is Dictionary or not bindings is Dictionary or not appearance is Dictionary:
		return _invalid("presentation")
	var positioned: Dictionary = Placement.resolve(placement)
	if not positioned.ok:
		return positioned
	var bound: Dictionary = VisualBuilder.validate_bindings(source, bindings)
	if not bound.ok:
		return bound
	var paint: Dictionary = VisualBuilder.validate_appearance(appearance)
	if not paint.ok:
		return paint
	var raw: Variant = saved.get("raw_bytes")
	if typeof(raw) != TYPE_PACKED_BYTE_ARRAY or raw.is_empty() or Bytes.sha256(raw) != saved.get("raw_sha256") \
			or not Bytes.decode(raw).ok:
		return _invalid("flight_data")
	var aircraft_id := Definition.aircraft_id(ref.aircraft_uuid)
	var data: Dictionary = RecordLoader.load_bytes(raw, aircraft_id)
	if not data.get("ok", false) or not data.get("model") is Dictionary \
			or data.model.get("id") != aircraft_id or not data.get("input_identity") is Dictionary \
			or data.input_identity.get("sha256") != saved.raw_sha256:
		return _invalid("flight_data")
	var provenance := LEGACY_UNBOUND
	if saved.has("record_format"):
		if saved.record_format != Binding.REVISION_FORMAT:
			return _invalid("record_format")
		var authoring: Script = load("res://workshop/creator/authoring.gd")
		var document: RefCounted = authoring.new()
		var report: Dictionary = Observations.inspect(source)
		if not report.ok:
			return report
		var snapshot: Variant = saved.get("snapshot")
		if not snapshot is Dictionary:
			return _invalid("snapshot")
		var restored: Dictionary = document.restore(snapshot, source, report.value)
		if not restored.ok:
			return restored
		var joined: Dictionary = CompiledPublication.match_document(document, saved)
		if not joined.ok:
			return joined
		# A flight-eligible owner requires proven derivation, not only a matching hash pair.
		var derived: Dictionary = CompiledPublication.verify_derivation(saved.definition, raw, ref.aircraft_uuid)
		if not derived.ok:
			return derived
		provenance = BOUND_V2
	elif saved.has("compile_binding") or _legacy_servo_marker(saved):
		return _invalid("legacy_servo")
	var owner := Resolved.new()
	var presentation := {"placement": placement, "bindings": bindings, "appearance": appearance}
	if not owner._seal(ref, raw, data, source, presentation, str(saved.name), provenance,
			str(saved.raw_sha256), str(saved.definition_sha256)):
		return _invalid("resolved_data")
	var notes: Array = []
	notes.append_array(opened.get("diagnostics", []))
	notes.append_array(loaded.get("diagnostics", []))
	notes.append_array(inspection.get("diagnostics", []))
	return R.ok(owner, notes.duplicate(true))


## A v1 revision cannot carry any versioned servo selector, even through a caller-forged value.
static func _legacy_servo_marker(saved: Dictionary) -> bool:
	var definition: Variant = saved.get("definition")
	if definition is Dictionary and (definition.get("format") == Definition.SERVO_FORMAT or definition.has("servo_integration")):
		return true
	var snapshot: Variant = saved.get("snapshot")
	if snapshot is Dictionary and (snapshot.get("format") == "openrc-creator-document v4" or snapshot.has("servo_integration")):
		return true
	return CompiledPublication.raw_has_servo_declaration(saved.get("raw_bytes"))


static func _invalid(field: String) -> Dictionary:
	return R.fail(R.RECORD_INVALID, "The saved aircraft cannot be resolved safely.", "source_ref/" + field)
