extends SceneTree
## Exact indexed Creator references and their non-flight resolver.
## Writes only a uniquely named disposable user:// store and leaves it for inspection.
const R := preload("res://workshop/creator/result.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const Resolver := preload("res://workshop/creator/source_resolver.gd")
const Store := preload("res://workshop/creator/store.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Candidate := preload("res://workshop/creator/accepted_candidate.gd")
const Publication := preload("res://workshop/creator/compiled_publication.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")

const UUID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
const SHA := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("Creator source reference: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


func _run() -> void:
	_reference_cases()
	var admitted: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "trainer.glb")
	check("ordinary source is admitted", admitted.ok)
	if not admitted.ok:
		return
	_store_cases(admitted.value)


func _reference_cases() -> void:
	var made: Dictionary = SourceRef.make(UUID, 1, SHA)
	check("factory creates a closed reference", made.ok and made.value == {"format": SourceRef.FORMAT,
		"aircraft_uuid": UUID, "revision": 1, "record_sha256": SHA})
	for bad: Variant in [null, false, 1, "text", [], {}]:
		check("non-reference is refused", not SourceRef.validate(bad).ok)
	for bad: Variant in [null, false, 0, -1, 1.0, "1", Limits.MAX_SAFE_INTEGER + 1]:
		check("revision must be a positive safe integer", not SourceRef.make(UUID, bad, SHA).ok)
	for bad: Variant in [null, false, "", UUID.to_upper(), "aaaaaaaa-aaaa-1aaa-8aaa-aaaaaaaaaaaa",
			"aaaaaaaa-aaaa-4aaa-7aaa-aaaaaaaaaaaa", "x".repeat(36)]:
		check("reference requires a lowercase v4 UUID", not SourceRef.make(bad, 1, SHA).ok)
	for bad: Variant in [null, false, "", "a".repeat(63), "A".repeat(64), "g".repeat(64)]:
		check("reference requires a lowercase SHA-256", not SourceRef.make(UUID, 1, bad).ok)
	var original: Dictionary = made.value.duplicate(true)
	var validated: Dictionary = SourceRef.validate(original)
	original.revision = 2
	check("validation returns a detached reference", validated.ok and validated.value.revision == 1)
	var malformed: Dictionary = made.value.duplicate(true)
	malformed["path"] = "user://elsewhere"
	check("a reference cannot smuggle a path or extra fields", not SourceRef.validate(malformed).ok)
	malformed = made.value.duplicate(true)
	malformed.erase("revision")
	check("missing fields are refused", not SourceRef.validate(malformed).ok)
	malformed = made.value.duplicate(true)
	malformed.format = "openrc-creator-source v2"
	check("unknown versions are refused", not SourceRef.validate(malformed).ok)
	var encoded: Dictionary = Bytes.encode(made.value)
	var decoded: Dictionary = SourceRef.from_bytes(encoded.value.bytes)
	check("exact integer bytes round-trip", encoded.ok and decoded.ok and decoded.value == made.value
		and typeof(decoded.value.revision) == TYPE_INT)
	var fractional := ('{"format":"%s","aircraft_uuid":"%s","revision":1.0,"record_sha256":"%s"}'
		% [SourceRef.FORMAT, UUID, SHA]).to_utf8_buffer()
	check("fractional revision tokens are refused before numeric coercion", not SourceRef.from_bytes(fractional).ok)
	check("resolver refuses forged and unsealed owners", not Resolver.is_resolved({})
		and not Resolver.is_resolved(Resolver.Resolved.new()))


static func _populated(source: RefCounted) -> RefCounted:
	var doc := Authoring.new()
	doc.name = "Reference trainer"
	doc.set_source(source)
	var template: Dictionary = Definition.template()
	var values := {}
	for entry: Dictionary in Authoring.FIELDS:
		values[entry.path] = Authoring._lookup(template, entry.path.split("/"))
	doc.apply_values(values, true)
	doc.propose_inventory()
	doc.set_axis("nose_axis", "+x")
	doc.set_axis("up_axis", "+z")
	doc.set_units("m")
	doc.set_datum([0.0, 0.0, 0.0])
	return doc


func _store_cases(source: RefCounted) -> void:
	var root := "user://creator_source_ref_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	print("Creator source reference disposable root: ", root)
	var missing_root := root + "_missing"
	var missing_absolute := ProjectSettings.globalize_path(missing_root)
	var absent_ref: Dictionary = SourceRef.make(UUID, 1, SHA).value
	check("read-only resolution does not create a missing library", not DirAccess.dir_exists_absolute(missing_absolute)
		and not Resolver.resolve(missing_root, absent_ref).ok and not DirAccess.dir_exists_absolute(missing_absolute))
	var opened: Dictionary = Store.open(root)
	check("fresh disposable library opens for writing", opened.ok and opened.value.is_writer())
	if not opened.ok:
		return
	var store: RefCounted = opened.value
	if not store.is_writer():
		store.close()
		return
	var legacy := _populated(source)
	var legacy_compiled: Dictionary = legacy.compile()
	check("legacy reference fixture compiles", legacy_compiled.ok)
	if not legacy_compiled.ok:
		print("Compile diagnostics: ", R.texts(legacy_compiled))
		store.close()
		return
	# Store v1 intentionally permitted opaque definition and snapshot members. The resolver must
	# not recompile them or invent a v2 receipt, but must still check its raw/source/presentation.
	var opaque_definition := {"aircraft_uuid": legacy.aircraft_uuid(), "historical_note": "opaque definition"}
	var old := {"aircraft_uuid": legacy.aircraft_uuid(), "name": legacy.name,
		"definition": opaque_definition, "raw_bytes": legacy_compiled.value.raw_bytes(),
		"source_bytes": source.source_bytes(), "source_file_name": source.file_name(),
		"placement": legacy.placement(), "bindings": legacy.bindings(), "appearance": legacy.appearance(),
		"snapshot": {"historical_snapshot": "opaque"}}
	check("legacy definition is intentionally not a complete Creator definition", not Definition.validate_complete(opaque_definition).ok)
	var old_save: Dictionary = store.publish_aircraft(old, 0)
	check("legacy opaque record publishes", old_save.ok)
	if not old_save.ok:
		print(old_save)
		store.close()
		return
	var old_ref: Dictionary = SourceRef.make(legacy.aircraft_uuid(), 1, old_save.value.record_sha256).value
	var old_resolution: Dictionary = Resolver.resolve(root, old_ref)
	check("legacy opaque record resolves without compilation or v2 receipt", old_resolution.ok
		and Resolver.is_resolved(old_resolution.value) and not Candidate.is_accepted(old_resolution.value)
		and old_resolution.value.provenance() == Resolver.LEGACY_UNBOUND
		and old_resolution.value.raw_bytes() == legacy_compiled.value.raw_bytes())
	_legacy_presentation_refusals(store, root, old, legacy.aircraft_uuid())
	var doc := _populated(source)
	check("v4 law is explicitly selected", doc.set_servo_integration(Definition.ServoLaw.LAW))
	var ca: Dictionary = doc.compile()
	var cap_a: Dictionary = Publication.capture(doc, "review_test")
	check("A compiles and captures", ca.ok and cap_a.ok)
	if not ca.ok or not cap_a.ok:
		store.close()
		return
	var save_a: Dictionary = store.publish_compiled_aircraft(cap_a.value, 0)
	check("A is indexed as revision 1", save_a.ok and save_a.value.revision == 1)
	if not save_a.ok:
		store.close()
		return
	var uuid: String = doc.aircraft_uuid()
	var ref_a: Dictionary = SourceRef.make(uuid, 1, save_a.value.record_sha256).value
	doc.set_value("controls/servo_time_s", 0.2)
	var cb: Dictionary = doc.compile()
	var cap_b: Dictionary = Publication.capture(doc, "review_test")
	check("same-UUID same-law B compiles to different physical bytes", cb.ok and cap_b.ok
		and ca.value.raw_bytes() != cb.value.raw_bytes())
	if not cb.ok or not cap_b.ok:
		store.close()
		return
	var save_b: Dictionary = store.publish_compiled_aircraft(cap_b.value, 1)
	check("B is indexed as revision 2", save_b.ok and save_b.value.revision == 2)
	if not save_b.ok:
		store.close()
		return
	var ref_b: Dictionary = SourceRef.make(uuid, 2, save_b.value.record_sha256).value
	var mixed: Dictionary = SourceRef.make(uuid, 1, save_b.value.record_sha256).value
	check("same UUID with revision A and B's real record hash is refused", not Resolver.resolve(root, mixed).ok)
	var wrong_hash: Dictionary = SourceRef.make(uuid, 1, "0".repeat(64)).value
	check("valid-looking incorrect record hash is refused", not Resolver.resolve(root, wrong_hash).ok)
	var missing: Dictionary = SourceRef.make(uuid, 3, save_b.value.record_sha256).value
	check("a nonexistent revision never becomes latest", not Resolver.resolve(root, missing).ok)
	_orphan_case(store, root, uuid, save_a.value.record_sha256)
	_mixed_record_case(store, root, uuid)
	var resolved_a: Dictionary = Resolver.resolve(root, ref_a)
	var resolved_b: Dictionary = Resolver.resolve(root, ref_b)
	check("both v2 revisions resolve through a read-only Store while the writer is held", resolved_a.ok and resolved_b.ok)
	if not resolved_a.ok or not resolved_b.ok:
		print("Resolution diagnostics: ", resolved_a, " ", resolved_b)
		store.close()
		return
	var owner: RefCounted = resolved_a.value
	check("A resolves exact raw bytes, reference, source and v2 binding provenance", Resolver.is_resolved(owner)
		and not Candidate.is_accepted(owner) and owner.source_ref() == ref_a and owner.raw_bytes() == ca.value.raw_bytes()
		and owner.raw_sha256() == ca.value.raw_sha256() and owner.definition_sha256() == ca.value.definition_sha256()
		and owner.source().sha256() == source.sha256() and owner.provenance() == Resolver.BOUND_V2)
	check("B resolves its own exact bytes", resolved_b.value.raw_bytes() == cb.value.raw_bytes()
		and resolved_b.value.source_ref() == ref_b and resolved_b.value.provenance() == Resolver.BOUND_V2)
	check("derived model comes from the exact stored bytes", owner.data().get("ok", false)
		and owner.data().input_identity.sha256 == owner.raw_sha256()
		and owner.data().model.id == Definition.aircraft_id(uuid))
	# The saved-owner/unsaved-trial boundary is also retained in the complete consumer fixture.
	_detachment(owner, ref_a, ca.value.raw_bytes())
	check("archive hides but does not revoke the pinned reference", store.set_archived("aircraft", uuid, true).ok
		and store.list_aircraft().all(func(row: Dictionary) -> bool: return row.aircraft_uuid != uuid)
		and Resolver.resolve(root, ref_a).ok)
	_recovery_cases(root, cap_a.value)
	_indexed_mismatch_cases(root, cap_a.value, source)
	_indexed_semantic_pair_case(root, cap_a.value, cap_b.value)
	_blob_failure_cases(root, cap_a.value)
	_warning_case(root, old)
	_clearview_case(store, root)
	store.close()
	var reopened_a: Dictionary = Resolver.resolve(root, ref_a)
	var reopened_old: Dictionary = Resolver.resolve(root, old_ref)
	check("A1 remains exact after A2, archive and Store reopen", reopened_a.ok
		and reopened_a.value.source_ref() == ref_a and reopened_a.value.raw_bytes() == ca.value.raw_bytes())
	check("legacy opaque reference also survives reopen", reopened_old.ok
		and reopened_old.value.raw_bytes() == legacy_compiled.value.raw_bytes()
		and reopened_old.value.provenance() == Resolver.LEGACY_UNBOUND)
	_corrupt_case(root, ref_a, ref_b, owner, ca.value.raw_bytes())


## The legacy writer accepts opaque presentation/source data. Resolution must still re-admit
## each source and validate presentation, without changing the saved historical records.
func _legacy_presentation_refusals(store: RefCounted, root: String, original: Dictionary, uuid: String) -> void:
	var current := 1
	for field: String in ["placement", "bindings", "appearance", "source_bytes"]:
		var bad: Dictionary = original.duplicate(true)
		match field:
			"placement": bad.placement = {"nose_axis": "+x", "up_axis": "+z", "unit_scale": 0.0, "datum": [0.0, 0.0, 0.0]}
			"bindings": bad.bindings = {"controls": "invalid"}
			"appearance": bad.appearance = {"mode": "unsupported"}
			"source_bytes": bad.source_bytes = PackedByteArray([0, 1, 2, 3])
		var saved: Dictionary = store.publish_aircraft(bad, current)
		check("opaque legacy fixture stores invalid " + field, saved.ok)
		if not saved.ok:
			return
		current += 1
		var ref: Dictionary = SourceRef.make(uuid, current, saved.value.record_sha256).value
		check("resolver refuses invalid legacy " + field, not Resolver.resolve(root, ref).ok)


func _detachment(owner: RefCounted, expected_ref: Dictionary, expected_raw: PackedByteArray) -> void:
	var ref: Dictionary = owner.source_ref()
	ref.revision = 999
	var raw: PackedByteArray = owner.raw_bytes()
	raw[0] = raw[0] ^ 1
	var view: Dictionary = owner.presentation()
	view.placement.datum[0] = 123.0
	check("reference, raw bytes and nested presentation are detached", owner.source_ref() == expected_ref
		and owner.raw_bytes() == expected_raw and owner.presentation().placement.datum[0] != 123.0)
	var original: Variant = owner.data().model.get("inertia")
	check("derived inertia is a packed float64 array", typeof(original) == TYPE_PACKED_FLOAT64_ARRAY and not original.is_empty())
	if typeof(original) == TYPE_PACKED_FLOAT64_ARRAY and not original.is_empty():
		var expected: float = original[0]
		var copy: Dictionary = owner.data()
		var inertia: PackedFloat64Array = copy.model.inertia
		inertia[0] = expected + 1.0
		copy.model.inertia = inertia
		check("nested packed model arrays are detached", owner.data().model.inertia[0] == expected)


func _orphan_case(store: RefCounted, root: String, uuid: String, indexed_sha: String) -> void:
	var listed: Dictionary = store._index.aircraft[uuid].revisions[0]
	var object: Dictionary = store._read_object(listed.record, Limits.DRAFT_BYTES)
	check("indexed revision record is readable", object.ok)
	if not object.ok:
		return
	var decoded: Dictionary = Bytes.decode(object.bytes, Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	check("indexed revision record decodes", decoded.ok)
	if not decoded.ok:
		return
	var orphan: Dictionary = decoded.value.data.duplicate(true)
	orphan.name = "Unindexed orphan"
	var encoded: Dictionary = Bytes.encode(orphan, Limits.DRAFT_BYTES)
	if not encoded.ok:
		check("orphan record encodes", false)
		return
	var installed: Dictionary = store._install(encoded.value.sha256, encoded.value.bytes, false)
	check("orphan fixture is installed but not indexed", installed.ok and encoded.value.sha256 != indexed_sha)
	if installed.ok:
		var orphan_ref: Dictionary = SourceRef.make(uuid, 1, encoded.value.sha256).value
		check("an existing but unindexed record cannot resolve", not Resolver.resolve(root, orphan_ref).ok)


## An in-memory cross-pair uses the actual A/B descriptors. A retains its original receipt;
## the malformed revision object is installed only as an orphan in this disposable store.
func _mixed_record_case(store: RefCounted, root: String, uuid: String) -> void:
	var listed_a: Dictionary = store._index.aircraft[uuid].revisions[0]
	var listed_b: Dictionary = store._index.aircraft[uuid].revisions[1]
	var blob_a: Dictionary = store._read_object(listed_a.record, Limits.DRAFT_BYTES)
	var blob_b: Dictionary = store._read_object(listed_b.record, Limits.DRAFT_BYTES)
	check("actual A/B revision records are readable", blob_a.ok and blob_b.ok)
	if not blob_a.ok or not blob_b.ok:
		return
	var read_a: Dictionary = Bytes.decode(blob_a.bytes, Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	var read_b: Dictionary = Bytes.decode(blob_b.bytes, Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	check("actual A/B revision records decode", read_a.ok and read_b.ok)
	if not read_a.ok or not read_b.ok:
		return
	var mixed: Dictionary = read_a.value.data.duplicate(true)
	mixed.aircraft = read_b.value.data.aircraft.duplicate(true)
	check("A receipt refuses the actual B raw descriptor", not Store._revision_problem(mixed).is_empty())
	var encoded: Dictionary = Bytes.encode(mixed, Limits.DRAFT_BYTES)
	if not encoded.ok:
		check("mixed orphan fixture encodes", false)
		return
	var installed: Dictionary = store._install(encoded.value.sha256, encoded.value.bytes, false)
	check("mixed record is installed as an orphan", installed.ok)
	if not installed.ok:
		return
	var listed := {revision = mixed.revision, created_unix = mixed.created_unix,
		record = Store._blob(encoded.value.sha256, encoded.value.bytes.size(), Store.MEDIA_REVISION)}
	check("mixed orphan is refused even by the record reader", not store._load_revision_record(listed, uuid).ok)
	var ref: Dictionary = SourceRef.make(uuid, 1, encoded.value.sha256).value
	check("mixed orphan cannot resolve through the indexed reference", not Resolver.resolve(root, ref).ok)


func _clearview_case(store: RefCounted, root: String) -> void:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\nmodelMass 4.1\nplaneType 0\n"
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Plane/params.txt", params.to_ascii_buffer()],
		["Plane/data/body.ac", CvFixture._ac_fixture().to_ascii_buffer()]]))
	check("ClearView fixture package is admitted", package.ok)
	if not package.ok:
		return
	var converted: Dictionary = Converter.convert(package.value, "Plane")
	check("ClearView fixture converts", converted.ok)
	if not converted.ok:
		return
	var cv_source: RefCounted = converted.value.source
	var definition: Dictionary = Definition.template()
	definition.aircraft_uuid = Authoring.new_uuid()
	var compiled: Dictionary = Compiler.compile_candidate(definition)
	check("ClearView historical physical fixture compiles", compiled.ok)
	if not compiled.ok:
		return
	var publication := {"aircraft_uuid": definition.aircraft_uuid, "name": "Recognized ClearView",
		"definition": {"aircraft_uuid": definition.aircraft_uuid}, "raw_bytes": compiled.value.raw_bytes(),
		"source_bytes": cv_source.source_bytes(), "source_file_name": cv_source.file_name(),
		"placement": {"nose_axis": "+x", "up_axis": "+z", "unit_scale": 1.0, "datum": [0.0, 0.0, 0.0]},
		"bindings": {}, "appearance": {"mode": "original"}, "snapshot": {}}
	var saved: Dictionary = store.publish_aircraft(publication, 0)
	check("historical ClearView fixture is indexed", saved.ok and Installation.required(cv_source))
	if not saved.ok:
		return
	var ref: Dictionary = SourceRef.make(definition.aircraft_uuid, 1, saved.value.record_sha256).value
	var refused: Dictionary = Resolver.resolve(root, ref)
	check("recognized ClearView resolution stays unavailable", not refused.ok
		and refused.diagnostics[0].code == R.UNSUPPORTED_CAPABILITY
		and refused.diagnostics[0].message == Installation.FLIGHT_UNAVAILABLE)


func _corrupt_case(root: String, ref_a: Dictionary, ref_b: Dictionary, retained: RefCounted,
		expected_raw: PackedByteArray) -> void:
	# Deliberate mutation is limited to the unique disposable test root, after all normal checks.
	var raw_sha: String = retained.raw_sha256()
	var absolute := ProjectSettings.globalize_path(root)
	var object_path := absolute.path_join("objects").path_join(raw_sha.substr(0, 2)).path_join(raw_sha)
	var file := FileAccess.open(object_path, FileAccess.READ_WRITE)
	check("disposable raw object can be opened for corruption", file != null)
	if file == null:
		return
	var first := file.get_8()
	file.seek(0)
	file.store_8(first ^ 1)
	file.flush()
	file.close()
	check("corrupt indexed raw object is refused", not Resolver.resolve(root, ref_a).ok)
	check("unrelated revision remains resolvable", Resolver.resolve(root, ref_b).ok)
	check("already resolved owner retains its captured bytes", retained.raw_bytes() == expected_raw)


## Every deliberate mutation below stays within its own newly seeded disposable library.
func _seed(root: String, captured: RefCounted) -> Dictionary:
	var opened: Dictionary = Store.open(root)
	check("boundary fixture opens a fresh writer", opened.ok and opened.value.is_writer())
	if not opened.ok:
		return {}
	var store: RefCounted = opened.value
	var saved: Dictionary = store.publish_compiled_aircraft(captured, 0)
	check("boundary fixture publishes through the captured path", saved.ok)
	if not saved.ok:
		store.close()
		return {}
	var ref: Dictionary = SourceRef.make(saved.value.aircraft_uuid, 1, saved.value.record_sha256).value
	check("untampered exact boundary fixture resolves", Resolver.resolve(root, ref).ok)
	var listed: Dictionary = store._index.aircraft[ref.aircraft_uuid].revisions[0]
	var blob: Dictionary = store._read_object(listed.record, Limits.DRAFT_BYTES)
	var decoded: Dictionary = Bytes.decode(blob.bytes, Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES) if blob.ok else {ok = false}
	check("boundary fixture uses the actual indexed revision", decoded.ok)
	if not decoded.ok:
		store.close()
		return {}
	return {store = store, ref = ref, record = decoded.value.data, listed = listed}


func _pointer_files(root: String) -> Dictionary:
	var values := {}
	for name: String in [Store.CURRENT_FILE, Store.PREVIOUS_FILE]:
		var path := ProjectSettings.globalize_path(root).path_join(name)
		var exists := FileAccess.file_exists(path)
		values[name] = {exists = exists, bytes = FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	return values


func _recovery_cases(root: String, captured: RefCounted) -> void:
	for mode: String in ["missing", "corrupt"]:
		var path := root + "_current_" + mode
		var seed := _seed(path, captured)
		if seed.is_empty():
			return
		var store: RefCounted = seed.store
		check("second real transaction retains selected revision in previous index", store.set_archived("aircraft", seed.ref.aircraft_uuid, true).ok)
		store.close()
		var current := ProjectSettings.globalize_path(path).path_join(Store.CURRENT_FILE)
		if mode == "missing":
			check("remove only disposable current pointer", DirAccess.remove_absolute(current) == OK)
		else:
			var file := FileAccess.open(current, FileAccess.WRITE)
			check("disposable current pointer opens for corruption", file != null)
			if file == null:
				return
			file.store_buffer("bad".to_utf8_buffer())
			file.close()
		var recovered: Dictionary = Store.open(path, {read_only = true})
		check("existing Store explicitly reports previous-index recovery", recovered.ok and recovered.value.recovered_from_previous())
		if not recovered.ok:
			return
		var loaded: Dictionary = recovered.value.load_aircraft(seed.ref.aircraft_uuid, 1)
		check("previous index still contains the exact selected revision", loaded.ok and loaded.value.record_sha256 == seed.ref.record_sha256)
		recovered.value.close()
		var before := _pointer_files(path)
		check("selection refuses implicit previous-index recovery", not Resolver.resolve(path, seed.ref).ok)
		check("read-only refusal preserves both pointer files", _pointer_files(path) == before)


func _commit_indexed_variant(store: RefCounted, ref: Dictionary, record: Dictionary, objects: Array) -> Dictionary:
	check("mismatched v2 record still passes structural Store admission", Store._revision_problem(record).is_empty())
	var encoded: Dictionary = Bytes.encode(record, Limits.DRAFT_BYTES)
	if not encoded.ok:
		check("mismatched indexed record encodes", false)
		return {}
	var next: Dictionary = store._index.duplicate(true)
	next.aircraft[ref.aircraft_uuid].revisions[0].record = Store._blob(encoded.value.sha256, encoded.value.bytes.size(), Store.MEDIA_REVISION)
	next.aircraft[ref.aircraft_uuid].name = record.name
	check("mismatched fixture has a structurally valid index", Store._index_problem(next).is_empty())
	var begun: Dictionary = store._begin()
	if not begun.ok:
		check("mismatched fixture retains real transaction ownership", false)
		return {}
	var installed: Array = [encoded.value]
	installed.append_array(objects)
	var committed: Dictionary = store._commit(next, installed)
	check("mismatched fixture uses the real Store transaction", committed.ok)
	return SourceRef.make(ref.aircraft_uuid, 1, encoded.value.sha256).value if committed.ok else {}


func _indexed_mismatch_cases(root: String, captured: RefCounted, source: RefCounted) -> void:
	var document := Authoring.new()
	var restored: Dictionary = document.restore(captured.publication().snapshot, source, Observations.inspect(source).value)
	check("join oracle restores original captured document", restored.ok)
	if not restored.ok:
		return
	for field: String in ["snapshot", "name", "source", "placement", "bindings", "appearance"]:
		var path := root + "_indexed_" + field
		var seed := _seed(path, captured)
		if seed.is_empty():
			return
		var record: Dictionary = seed.record.duplicate(true)
		var objects: Array = []
		match field:
			"snapshot": record.snapshot["unrecognised_saved_member"] = "must not disappear"
			"name": record.name = "Different indexed name"
			"source":
				var raw := Fixture.airplane_glb("1.1")
				check("different source is independently admitted", Importer.inspect_bytes(raw, "different.glb").ok and Bytes.sha256(raw) != record.source.sha256)
				record.source = Store._blob(Bytes.sha256(raw), raw.size(), Store.MEDIA_SOURCE)
				objects.append({bytes = raw, sha256 = Bytes.sha256(raw)})
			"placement":
				record.placement.datum = [0.1, 0.2, 0.3]
				check("different placement is valid on its own", Placement.resolve(record.placement).ok)
			"bindings":
				record.bindings = Fixture.airplane_bindings()
				check("different bindings are valid on their own", VisualBuilder.validate_bindings(source, record.bindings).ok)
			"appearance":
				record.appearance = {mode = "solid", color = "#336699"}
				check("different appearance is valid on its own", VisualBuilder.validate_appearance(record.appearance).ok)
		var ref := _commit_indexed_variant(seed.store, seed.ref, record, objects)
		seed.store.close()
		if ref.is_empty():
			return
		var opened: Dictionary = Store.open(path, {read_only = true})
		check("mismatched indexed fixture opens its current index", opened.ok and not opened.value.recovered_from_previous())
		if not opened.ok:
			return
		var loaded: Dictionary = opened.value.load_aircraft(ref.aircraft_uuid, 1)
		opened.value.close()
		check("Store loads valid hashes of indexed " + field + " mismatch", loaded.ok and loaded.value.record_sha256 == ref.record_sha256)
		if not loaded.ok:
			return
		check("document join rejects indexed " + field + " mismatch", not Publication.match_document(document, loaded.value).ok)
		check("exact resolver rejects indexed " + field + " mismatch", not Resolver.resolve(path, ref).ok)


## B's real physics with A's real definition, hashes and receipt recomputed, committed through the real
## Store transaction. Structurally valid everywhere; only derivation can refuse it (follow-up 02, §4).
func _indexed_semantic_pair_case(root: String, captured_a: RefCounted, captured_b: RefCounted) -> void:
	var path := root + "_indexed_semantic_pair"
	var seed := _seed(path, captured_a)
	if seed.is_empty():
		return
	var raw_b: PackedByteArray = captured_b.publication().raw_bytes
	var raw_b_sha := Bytes.sha256(raw_b)
	var record: Dictionary = seed.record.duplicate(true)
	record.aircraft = Store._blob(raw_b_sha, raw_b.size(), Store.MEDIA_AIRCRAFT)
	record.compile_binding = Binding.make(record.definition.sha256, raw_b_sha)
	var ref := _commit_indexed_variant(seed.store, seed.ref, record, [{bytes = raw_b, sha256 = raw_b_sha}])
	seed.store.close()
	if ref.is_empty():
		return
	var opened: Dictionary = Store.open(path, {read_only = true})
	check("semantic-pair fixture opens its current index", opened.ok and not opened.value.recovered_from_previous())
	if not opened.ok:
		return
	var loaded: Dictionary = opened.value.load_aircraft(ref.aircraft_uuid, 1)
	opened.value.close()
	check("Store loads the structurally valid recomputed cross-pair", loaded.ok and loaded.value.raw_bytes == raw_b)
	var refused: Dictionary = Resolver.resolve(path, ref)
	check("exact resolver refuses the recomputed cross-pair by derivation", not refused.ok
		and refused.diagnostics[0].field == "saved_aircraft/derivation")


func _blob_failure_cases(root: String, captured: RefCounted) -> void:
	for field: String in ["record", "definition", "source"]:
		for mode: String in ["missing", "corrupt"]:
			var path := root + "_blob_" + field + "_" + mode
			var seed := _seed(path, captured)
			if seed.is_empty():
				return
			var blob: Dictionary = seed.listed.record if field == "record" else seed.record[field]
			seed.store.close()
			var object_path := ProjectSettings.globalize_path(path).path_join("objects").path_join(blob.sha256.substr(0, 2)).path_join(blob.sha256)
			if mode == "missing":
				check("remove only disposable " + field + " blob", DirAccess.remove_absolute(object_path) == OK)
			else:
				var file := FileAccess.open(object_path, FileAccess.READ_WRITE)
				check("disposable " + field + " blob opens for corruption", file != null)
				if file == null:
					return
				var first := file.get_8()
				file.seek(0)
				file.store_8(first ^ 1)
				file.close()
			var opened: Dictionary = Store.open(path, {read_only = true})
			check("blob failure leaves current index intact", opened.ok and not opened.value.recovered_from_previous())
			if not opened.ok:
				return
			check("record loader refuses " + mode + " " + field, not opened.value.load_aircraft(seed.ref.aircraft_uuid, 1).ok)
			opened.value.close()
			check("resolver refuses " + mode + " " + field, not Resolver.resolve(path, seed.ref).ok)


func _warning_case(root: String, original: Dictionary) -> void:
	var warning_bytes := ("solid warning\n"
		+ "facet normal 0 0 0 outer loop vertex 0 0 0 vertex 1 0 1 vertex 0 1 1 endloop endfacet\n"
		+ "facet normal 0 0 0 outer loop vertex 0 0 0 vertex 0 0 0 vertex 1 1 1 endloop endfacet\n"
		+ "endsolid warning\n").to_utf8_buffer()
	var inspected: Dictionary = Importer.inspect_bytes(warning_bytes, "warning.stl")
	check("warning fixture is admitted with a nonempty source warning", inspected.ok and not inspected.diagnostics.is_empty())
	if not inspected.ok:
		return
	var path := root + "_warning"
	var opened: Dictionary = Store.open(path)
	if not opened.ok:
		check("warning library opens", false)
		return
	var publication: Dictionary = original.duplicate(true)
	publication.source_bytes = warning_bytes
	publication.source_file_name = "warning.stl"
	publication.bindings = {}
	var saved: Dictionary = opened.value.publish_aircraft(publication, 0)
	opened.value.close()
	check("warning source publishes in legacy fixture", saved.ok)
	if not saved.ok:
		return
	var resolved: Dictionary = Resolver.resolve(path, SourceRef.make(saved.value.aircraft_uuid, 1, saved.value.record_sha256).value)
	check("warning source resolves with public diagnostics", resolved.ok and not resolved.diagnostics.is_empty())
	if not resolved.ok:
		return
	var original_notes: Array = resolved.value.source().notes()
	var changed := false
	for diagnostic: Dictionary in resolved.diagnostics:
		if diagnostic.code == R.SOURCE_INVALID and diagnostic.severity == R.SEVERITY_WARNING:
			diagnostic.message = "Changed through public result"
			if not diagnostic.arguments.is_empty():
				diagnostic.arguments[0] = "changed"
			changed = true
	check("warning detachment test exercised an actual diagnostic", changed)
	check("public diagnostic mutation cannot change captured source notes", resolved.value.source().notes() == original_notes)
