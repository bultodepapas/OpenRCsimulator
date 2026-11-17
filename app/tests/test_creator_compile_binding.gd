extends SceneTree
## Publication binding: v4 save/reopen and same-UUID, same-law cross-pair refusal.
## Uses a unique disposable user:// root and deliberately leaves it in place for inspection.
const Store := preload("res://workshop/creator/store.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")
const CompiledPublication := preload("res://workshop/creator/compiled_publication.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_run()
	print("Creator compile binding: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


func _run() -> void:
	_receipt_cases()
	check("capture requires an exact Authoring object", not CompiledPublication.capture(null).ok
		and not CompiledPublication.capture({}).ok and not CompiledPublication.is_captured({}))
	var inspected: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "trainer.glb")
	check("ordinary GLB is admitted", inspected.ok)
	if not inspected.ok:
		return
	var source: RefCounted = inspected.value
	var a := _populated(source)
	check("servo choice is explicit", a.set_servo_integration(Definition.ServoLaw.LAW))
	var ca: Dictionary = a.compile()
	check("revision A compiles", ca.ok)
	if not ca.ok:
		print("A diagnostics: ", ca.get("diagnostics", []))
		return
	var b := Authoring.new()
	check("B starts as a copy of A", b.restore(a.snapshot(), source).ok)
	b.set_value("controls/servo_time_s", 0.2)
	var cb: Dictionary = b.compile()
	check("same UUID/law revision B compiles", cb.ok and b.aircraft_uuid() == a.aircraft_uuid()
		and b.servo_integration() == a.servo_integration())
	if not cb.ok:
		print("B diagnostics: ", cb.get("diagnostics", []))
		return
	var raw_a: PackedByteArray = ca.value.raw_bytes()
	var raw_b: PackedByteArray = cb.value.raw_bytes()
	check("same-law revisions are physically distinct", raw_a != raw_b
		and ca.value.definition_sha256() != cb.value.definition_sha256())
	var capture_a: Dictionary = CompiledPublication.capture(a, "review_test")
	var capture_b: Dictionary = CompiledPublication.capture(b, "review_test")
	check("each valid revision produces a captured owner", capture_a.ok and capture_b.ok
		and CompiledPublication.is_captured(capture_a.value) and CompiledPublication.is_captured(capture_b.value))
	if not capture_a.ok or not capture_b.ok:
		print("Capture diagnostics: ", capture_a, " ", capture_b)
		return
	var cap_a: RefCounted = capture_a.value
	var cap_b: RefCounted = capture_b.value
	var value_a: Dictionary = cap_a.publication()
	var value_b: Dictionary = cap_b.publication()
	check("capture takes the corresponding candidate bytes", value_a.raw_bytes == raw_a and value_b.raw_bytes == raw_b
		and Binding.matches(cap_a.binding(), ca.value.definition_sha256(), ca.value.raw_sha256())
		and Binding.matches(cap_b.binding(), cb.value.definition_sha256(), cb.value.raw_sha256()))
	var changed_copy: Dictionary = cap_a.publication()
	var changed_raw: PackedByteArray = changed_copy.raw_bytes
	changed_raw[0] = changed_raw[0] ^ 1
	changed_copy.raw_bytes = changed_raw
	changed_copy.definition.controls.servo_time_s = 0.2
	var changed_binding: Dictionary = cap_a.binding()
	changed_binding.raw_sha256 = "0".repeat(64)
	check("capture accessors return detached copies", cap_a.publication().raw_bytes == raw_a
		and cap_a.publication().definition.controls.servo_time_s != 0.2
		and Binding.matches(cap_a.binding(), ca.value.definition_sha256(), ca.value.raw_sha256()))
	b.set_value("controls/servo_time_s", 0.21)
	check("later document edits do not alter a captured publication", cap_b.publication().raw_bytes == raw_b
		and cap_b.publication().definition.controls.servo_time_s == 0.2)
	var confused := Authoring.new()
	check("cached candidate test document restores A", confused.restore(a.snapshot(), source).ok)
	confused._compiled = cb
	confused._compiled_revision = confused.revision
	check("candidate B injected into document A is refused", not CompiledPublication.capture(confused).ok)
	var bad_presentation := Authoring.new()
	check("presentation fixture restores A", bad_presentation.restore(a.snapshot(), source).ok)
	bad_presentation.set_bindings({"controls": "invalid"})
	check("invalid bindings refuse capture", not CompiledPublication.capture(bad_presentation).ok)
	bad_presentation.set_bindings(a.bindings())
	bad_presentation.set_appearance({"mode": "unsupported"})
	check("invalid appearance refuses capture", not CompiledPublication.capture(bad_presentation).ok)
	_fault_cases(cap_a)
	_clearview_gate()
	_store_cases(a, ca, cb, cap_a, cap_b, source)


static func _populated(source: RefCounted, report: RefCounted = null) -> RefCounted:
	var doc := Authoring.new()
	doc.name = "Bound trainer"
	doc.set_source(source, report)
	var template := Definition.template()
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


func _receipt_cases() -> void:
	var def_sha := "a".repeat(64)
	var raw_sha := "b".repeat(64)
	var good: Dictionary = Binding.make(def_sha, raw_sha)
	check("binding matches its two valid digests", Binding.matches(good, def_sha, raw_sha))
	check("binding refuses malformed make inputs", Binding.make("bad", raw_sha).is_empty()
		and Binding.make(def_sha, "B".repeat(64)).is_empty())
	for bad: Variant in [null, false, 5, "text", [], {}]:
		check("binding requires a closed object", not Binding.matches(bad, def_sha, raw_sha))
	for key: String in Binding.KEYS:
		for bad: Variant in [null, false, 5, [], {}, StringName("value")]:
			var changed: Dictionary = good.duplicate(true)
			changed[key] = bad
			check("binding field type is strict: " + key, not Binding.matches(changed, def_sha, raw_sha))
	var changed: Dictionary = good.duplicate(true)
	changed["extra"] = true
	check("binding rejects extra keys", not Binding.matches(changed, def_sha, raw_sha))
	changed = good.duplicate(true)
	changed.erase("profile")
	check("binding requires all keys", not Binding.matches(changed, def_sha, raw_sha))
	changed = good.duplicate(true)
	changed.format = "future-format"
	check("binding rejects unknown format", not Binding.matches(changed, def_sha, raw_sha))
	changed = good.duplicate(true)
	changed.profile = "future-profile"
	check("binding rejects unknown profile", not Binding.matches(changed, def_sha, raw_sha))
	check("binding rejects wrong digests and digest types", not Binding.matches(good, raw_sha, raw_sha)
		and not Binding.matches(good, def_sha, null) and not Binding.matches(good, def_sha, "B".repeat(64)))


func _clearview_gate() -> void:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\nmodelMass 4.1\nplaneType 0\n"
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Plane/params.txt", params.to_ascii_buffer()],
		["Plane/data/body.ac", CvFixture._ac_fixture().to_ascii_buffer()]]))
	check("ClearView package fixture is admitted", package.ok)
	if not package.ok:
		return
	var converted := Converter.convert(package.value, "Plane")
	check("ClearView source fixture converts", converted.ok)
	if not converted.ok:
		return
	var source: RefCounted = converted.value.source
	var report: Dictionary = Observations.inspect(source)
	if not report.ok:
		check("ClearView report checks", false)
		return
	var doc := _populated(source, report.value)
	doc.set_servo_integration(Definition.ServoLaw.LAW)
	var pending: Dictionary = CompiledPublication.capture(doc)
	check("pending ClearView capture remains unavailable", not pending.ok and pending.diagnostics[0].message == Installation.FLIGHT_UNAVAILABLE)
	check("ClearView installation can still be reviewed for a draft", doc.choose_source_installation(
		doc.source_installation_proposal(), doc.revision, true).ok)
	var installed: Dictionary = CompiledPublication.capture(doc)
	check("reviewed ClearView capture also remains unavailable", not installed.ok
		and installed.diagnostics[0].message == Installation.FLIGHT_UNAVAILABLE)


func _store_cases(a: RefCounted, ca: Dictionary, cb: Dictionary,
		cap_a: RefCounted, cap_b: RefCounted, source: RefCounted) -> void:
	var root := "user://creator_compile_binding_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	print("Creator compile binding disposable root: ", root)
	var opened: Dictionary = Store.open(root)
	check("fresh disposable store opens with writer lock", opened.ok and opened.value.is_writer())
	if not opened.ok:
		return
	var store: RefCounted = opened.value
	if not store.is_writer():
		store.close()
		return
	var uuid: String = a.aircraft_uuid()
	var a_publication: Dictionary = cap_a.publication()
	var b_publication: Dictionary = cap_b.publication()
	var mixed: Dictionary = a_publication.duplicate(true)
	mixed.raw_bytes = b_publication.raw_bytes.duplicate()
	mixed["raw_sha256"] = Bytes.sha256(mixed.raw_bytes)
	mixed["compile_binding"] = Binding.make(ca.value.definition_sha256(), mixed.raw_sha256)
	var generation: int = store.generation()
	check("flat mixed A/B publication with fresh hashes is refused atomically", not store.publish_aircraft(mixed, 0).ok
		and store.generation() == generation and store.list_aircraft().is_empty())
	check("a flat v4 publication cannot be promoted by a caller receipt",
		not store.publish_aircraft(a_publication, 0).ok and store.generation() == generation
		and not store.publish_compiled_aircraft({"publication": a_publication, "binding": cap_a.binding()}, 0).ok
		and not store.publish_compiled_aircraft(CompiledPublication.Captured.new(), 0).ok)
	var legacy := Authoring.new()
	check("legacy comparison starts from the same source and UUID", legacy.restore(a.snapshot(), source).ok
		and legacy.set_servo_integration(""))
	var old: Dictionary = legacy.compile()
	check("legacy comparison compiles", old.ok)
	if not old.ok:
		store.close()
		return
	var old_definition: Dictionary = Definition.validate_complete(legacy.definition()).value
	var flat := {aircraft_uuid = uuid, name = legacy.name, definition = old_definition,
		raw_bytes = old.value.raw_bytes(), source_bytes = source.source_bytes(), source_file_name = source.file_name(),
		placement = legacy.placement(), bindings = legacy.bindings(), appearance = legacy.appearance(),
		snapshot = legacy.snapshot("review_test")}
	var definition_marker: Dictionary = flat.duplicate(true)
	definition_marker.definition.format = Definition.SERVO_FORMAT
	var definition_field: Dictionary = flat.duplicate(true)
	definition_field.definition["servo_integration"] = ""
	var snapshot_marker: Dictionary = flat.duplicate(true)
	snapshot_marker.snapshot["servo_integration"] = ""
	var snapshot_format: Dictionary = flat.duplicate(true)
	snapshot_format.snapshot.format = "openrc-creator-document v4"
	var raw_marker: Dictionary = flat.duplicate(true)
	raw_marker.raw_bytes = ca.value.raw_bytes()
	check("each independent v4/servo marker rejects the flat API", not store.publish_aircraft(definition_marker, 0).ok
		and not store.publish_aircraft(definition_field, 0).ok and not store.publish_aircraft(snapshot_marker, 0).ok
		and not store.publish_aircraft(snapshot_format, 0).ok and not store.publish_aircraft(raw_marker, 0).ok
		and store.generation() == generation and store.list_aircraft().is_empty())
	var historical: Dictionary = store.publish_aircraft(flat, 0)
	check("ordinary legacy flat publication retains v1", historical.ok and historical.value.revision == 1)
	if not historical.ok:
		print("Legacy publication diagnostics: ", historical)
		store.close()
		return
	var old_loaded: Dictionary = store.load_aircraft(uuid, 1)
	check("legacy return shape and physical bytes remain unchanged", old_loaded.ok
		and not old_loaded.value.has("record_format") and not old_loaded.value.has("compile_binding")
		and old_loaded.value.raw_bytes == old.value.raw_bytes())
	generation = store.generation()
	check("stale v2 expected revision refuses without a commit", not store.publish_compiled_aircraft(cap_a, 0).ok
		and store.generation() == generation)
	var pa: Dictionary = store.publish_compiled_aircraft(cap_a, 1)
	check("captured A publishes as revision 2", pa.ok and pa.value.revision == 2)
	if not pa.ok:
		print("A publication diagnostics: ", pa)
		store.close()
		return
	var pb: Dictionary = store.publish_compiled_aircraft(cap_b, 2)
	check("captured B publishes as revision 3", pb.ok and pb.value.revision == 3)
	if not pb.ok:
		print("B publication diagnostics: ", pb)
		store.close()
		return
	var ra := _actual_record(store, uuid, 2)
	var rb := _actual_record(store, uuid, 3)
	check("both actual revision records satisfy the v2 contract", not ra.is_empty() and not rb.is_empty()
		and Store._revision_problem(ra).is_empty() and Store._revision_problem(rb).is_empty())
	if not ra.is_empty() and not rb.is_empty():
		var untouched: Dictionary = ra.duplicate(true)
		var cross: Dictionary = ra.duplicate(true)
		cross.aircraft = rb.aircraft.duplicate(true)
		check("swapping actual same-law raw descriptor is rejected by receipt", not Store._revision_problem(cross).is_empty()
			and ra == untouched and Store._revision_problem(ra).is_empty())
		# Install one orphaned v1 record in this disposable root. It references the already stored
		# v4 blobs, but has no receipt. Bypass the write gate solely to exercise the read gate.
		var unbound: Dictionary = ra.duplicate(true)
		unbound.format = Store.AIRCRAFT_FORMAT
		unbound.erase("compile_binding")
		var unbound_written: Dictionary = Bytes.encode(unbound)
		check("unbound legacy v4 fixture encodes", unbound_written.ok)
		if unbound_written.ok:
			var installed: Dictionary = store._install(unbound_written.value.sha256, unbound_written.value.bytes, false)
			check("unbound v4 fixture is installed only as an orphan", installed.ok)
			if installed.ok:
				var listed := {revision = unbound.revision, created_unix = unbound.created_unix,
					record = Store._blob(unbound_written.value.sha256, unbound_written.value.bytes.size(), Store.MEDIA_REVISION)}
				var before_read: int = store.generation()
				check("legacy v1 with unbound servo bytes fails closed on read",
					not store._load_revision_record(listed, uuid).ok and store.generation() == before_read)
	store.close()
	var reopened: Dictionary = Store.open(root)
	check("store reopens with its writer lock", reopened.ok and reopened.value.is_writer())
	if not reopened.ok:
		return
	store = reopened.value
	var la: Dictionary = store.load_aircraft(uuid, 2)
	var lb: Dictionary = store.load_aircraft(uuid, 3)
	var lv1: Dictionary = store.load_aircraft(uuid, 1)
	check("reopened A keeps exact bytes and internally generated receipt", la.ok
		and la.value.raw_bytes == ca.value.raw_bytes() and la.value.record_sha256 == pa.value.record_sha256
		and la.value.record_format == Binding.REVISION_FORMAT and la.value.compile_binding == cap_a.binding()
		and Binding.matches(la.value.compile_binding, la.value.definition_sha256, la.value.raw_sha256))
	check("reopened B keeps its own exact bytes and receipt", lb.ok
		and lb.value.raw_bytes == cb.value.raw_bytes() and lb.value.record_sha256 == pb.value.record_sha256
		and lb.value.record_format == Binding.REVISION_FORMAT and lb.value.compile_binding == cap_b.binding()
		and Binding.matches(lb.value.compile_binding, lb.value.definition_sha256, lb.value.raw_sha256))
	check("v1 remains byte-stable after v2 revisions and reopening", lv1.ok and old_loaded.ok
		and lv1.value == old_loaded.value and lv1.value.raw_bytes == old.value.raw_bytes()
		and lv1.value.record_sha256 == historical.value.record_sha256 and not lv1.value.has("record_format")
		and not lv1.value.has("compile_binding"))
	store.close()


static func _actual_record(store: RefCounted, uuid: String, revision: int) -> Dictionary:
	var listed: Dictionary = store._index.aircraft[uuid].revisions[revision - 1]
	var blob: Dictionary = store._read_object(listed.record, Limits.DRAFT_BYTES)
	if not blob.ok:
		return {}
	var decoded: Dictionary = Bytes.decode(blob.bytes, Store.AIRCRAFT_INTEGERS, Limits.DRAFT_BYTES)
	return decoded.value.data if decoded.ok else {}


func _fault_cases(captured: RefCounted) -> void:
	for stage: String in [Store.FAULT_MID_CURRENT_REPLACE, Store.FAULT_AFTER_COMMIT]:
		var root := "user://creator_compile_binding_fault_%s_%d_%d" % [stage, OS.get_process_id(), Time.get_ticks_usec()]
		print("Creator compile binding fault root: ", root)
		var opened: Dictionary = Store.open(root)
		check(stage + ": disposable store opens", opened.ok and opened.value.is_writer())
		if not opened.ok:
			continue
		var store: RefCounted = opened.value
		var generation: int = store.generation()
		check(stage + ": injection is armed", store.set_fault_stage(stage))
		var saved: Dictionary = store.publish_compiled_aircraft(captured, 0)
		check(stage + ": interrupted save refuses further writes", not saved.ok and store.needs_reopen())
		store.close()
		var reopened: Dictionary = Store.open(root)
		check(stage + ": interrupted store reopens", reopened.ok and reopened.value.is_writer())
		if not reopened.ok:
			continue
		store = reopened.value
		var publication: Dictionary = captured.publication()
		var loaded: Dictionary = store.load_aircraft(publication.aircraft_uuid)
		if stage == Store.FAULT_AFTER_COMMIT:
			check(stage + ": complete bound revision survives", loaded.ok and store.generation() == generation + 1
				and loaded.value.raw_bytes == publication.raw_bytes and loaded.value.source_bytes == publication.source_bytes
				and loaded.value.definition == publication.definition and loaded.value.compile_binding == captured.binding()
				and loaded.value.record_format == Binding.REVISION_FORMAT)
		else:
			check(stage + ": original state survives without a partial revision", not loaded.ok
				and store.generation() == generation and store.list_aircraft().is_empty() and store.recovered_from_previous())
		store.close()
