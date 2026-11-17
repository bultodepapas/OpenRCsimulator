extends SceneTree
## Saved trial consistency only. Live flight/start/context admission is separately gated.
const Published := preload("res://workshop/creator/published_trial.gd")
const Resolver := preload("res://workshop/creator/source_resolver.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const RecordLoader := preload("res://workshop/creator/record_loader.gd")
const Candidate := preload("res://workshop/creator/accepted_candidate.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Publication := preload("res://workshop/creator/compiled_publication.gd")
const Store := preload("res://workshop/creator/store.gd")
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
var checks := 0
var failures := 0


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL published trial: ", label)


func _initialize() -> void:
	_run()
	print("Creator published trial: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _run() -> void:
	for bad: Variant in [null, false, {}, Resolver.Resolved.new(), RefCounted.new()]:
		check("only an actual resolved owner can prepare", not Published.prepare(bad).ok)
	var inspected: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "A.glb")
	check("A source admitted", inspected.ok)
	if not inspected.ok:
		return
	var doc: RefCounted = AuthoringFixture.populated(inspected.value)
	doc.name = "Published A"
	check("explicit law selected", doc.set_servo_integration(Definition.ServoLaw.LAW))
	var captured: Dictionary = Publication.capture(doc, "review_test")
	check("A captured", captured.ok)
	if not captured.ok:
		return
	var path := "user://creator_published_trial_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = Store.open(path)
	check("disposable library writer opens", opened.ok and opened.value.is_writer())
	if not opened.ok:
		return
	var store: RefCounted = opened.value
	var saved: Dictionary = store.publish_compiled_aircraft(captured.value, 0)
	check("A publishes", saved.ok)
	if not saved.ok:
		store.close()
		return
	var ref_a: Dictionary = SourceRef.make(doc.aircraft_uuid(), 1, saved.value.record_sha256).value
	var resolved: Dictionary = Resolver.resolve(path, ref_a)
	check("A resolves", resolved.ok)
	if not resolved.ok:
		store.close()
		return
	var owner_a: RefCounted = resolved.value
	var a: Dictionary = Published.prepare(owner_a)
	check("A prepares and verifies exact saved identity", a.ok and Published.verify(a).ok)
	if not a.ok:
		print(a)
		store.close()
		return
	check("saved discriminator stays distinct from unsaved candidate", a.vehicle == Published.VEHICLE and a.vehicle != "creator"
		and a.identity.format == Published.FORMAT and not Candidate.is_accepted(owner_a))
	var generic_identity: Dictionary = JSON.parse_string(JSON.stringify(a.identity, "", true, true))
	var encoded_ref: PackedByteArray = generic_identity.source_ref_json.to_utf8_buffer()
	var restored_ref: Dictionary = SourceRef.from_bytes(encoded_ref)
	check("wire identity retains the integer revision through generic JSON", restored_ref.ok and restored_ref.value == ref_a
		and typeof(restored_ref.value.revision) == TYPE_INT and Bytes.sha256(encoded_ref) == generic_identity.source_ref_sha256)
	check("identity contains no numeric reference alias", not a.identity.has("source_ref") and not a.identity.has("revision"))
	var source_b: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb("1.1"), "B.glb")
	check("B independently admitted", source_b.ok)
	if not source_b.ok:
		store.close()
		return
	doc.set_source(source_b.value)
	doc.set_axis("nose_axis", "+x")
	doc.set_axis("up_axis", "+z")
	doc.set_units("m")
	doc.set_datum([0.01, 0.02, 0.03])
	doc.set_bindings(Fixture.airplane_bindings())
	doc.set_appearance({"mode": "solid", "color": "#336699"})
	doc.set_value("controls/servo_time_s", 0.2)
	doc.name = "Published B"
	captured = Publication.capture(doc, "review_test")
	check("same-UUID B captures independent raw/source/presentation", captured.ok)
	if not captured.ok:
		store.close()
		return
	saved = store.publish_compiled_aircraft(captured.value, 1)
	check("B publishes revision2", saved.ok and saved.value.revision == 2)
	if not saved.ok:
		store.close()
		return
	var ref_b: Dictionary = SourceRef.make(doc.aircraft_uuid(), 2, saved.value.record_sha256).value
	resolved = Resolver.resolve(path, ref_b)
	check("B resolves", resolved.ok)
	if not resolved.ok:
		store.close()
		return
	var b: Dictionary = Published.prepare(resolved.value)
	check("B verifies and has different exact physical bytes", b.ok and Published.verify(b).ok and a.raw_bytes != b.raw_bytes
		and a.identity.source_sha256 != b.identity.source_sha256 and a.identity.presentation_sha256 != b.identity.presentation_sha256)
	if not b.ok:
		store.close()
		return
	_cross_pairs(a, b)
	_shapes(a)
	var detached: Dictionary = Published.prepare(owner_a)
	detached.creator.placement.datum[0] = 123.0
	check("prepared mutable presentation is detached from owner", owner_a.presentation().placement.datum[0] != 123.0 and not Published.verify(detached).ok)
	var inertia: PackedFloat64Array = detached.data.model.inertia
	inertia[0] += 1.0
	detached.data.model.inertia = inertia
	check("prepared packed arrays cannot mutate owner", detached.data.model.inertia != owner_a.data().model.inertia)
	check("A remains valid after B and archive", store.set_archived("aircraft", doc.aircraft_uuid(), true).ok and Published.verify(a).ok)
	_legacy(store, path, inspected.value)
	store.close()
	var current := ProjectSettings.globalize_path(path).path_join(Store.CURRENT_FILE)
	check("only disposable current pointer is removed", DirAccess.remove_absolute(current) == OK)
	check("new lookup refuses unavailable current index", not Resolver.resolve(path, ref_a).ok)
	check("frozen A keeps exact bytes without a new library lookup", Published.verify(a).ok and Published.prepare(owner_a).raw_bytes == a.raw_bytes)
	var start: Dictionary = Published.check_start(a, {id = "default"}, {}, "airborne")
	check("preparation never grants live flight", not start.ok and not start.available and start.reason == Published.FLIGHT_UNAVAILABLE)


func _rehash(trial: Dictionary) -> void:
	trial.identity.raw_sha256 = Bytes.sha256(trial.raw_bytes)
	var presentation := {"placement": trial.creator.placement, "bindings": trial.creator.bindings, "appearance": trial.creator.appearance}
	var encoded: Dictionary = Bytes.encode(presentation)
	if encoded.ok:
		trial.identity.presentation_sha256 = encoded.value.sha256
	var identity: Dictionary = trial.identity.duplicate(true)
	identity.erase("trial_id")
	encoded = Bytes.encode(identity)
	if encoded.ok:
		trial.identity.trial_id = "creator-published-" + encoded.value.sha256


func _cross_pairs(a: Dictionary, b: Dictionary) -> void:
	for field: String in ["raw", "data", "identity", "creator", "owner", "source", "placement", "bindings", "appearance", "name", "provenance", "reference", "display"]:
		var bad: Dictionary = a.duplicate(true)
		match field:
			"raw": bad.raw_bytes = b.raw_bytes
			"data": bad.data = b.data
			"identity": bad.identity = b.identity.duplicate(true)
			"creator": bad.creator = b.creator.duplicate(true)
			"owner": bad.creator.resolved = b.creator.resolved
			"source":
				bad.creator.source = b.creator.source
				bad.identity.source_sha256 = b.identity.source_sha256
			"placement", "bindings", "appearance", "name": bad.creator[field] = b.creator[field]
			"provenance": bad.identity.provenance = Resolver.LEGACY_UNBOUND
			"reference":
				bad.identity.source_ref_json = b.identity.source_ref_json
				bad.identity.source_ref_sha256 = b.identity.source_ref_sha256
			"display": bad.display_context = b.display_context.duplicate(true)
		_rehash(bad)
		check("cross-paired " + field + " refuses after public rehash", not Published.verify(bad).ok)
	check("cross-pair attempts leave both originals intact", Published.verify(a).ok and Published.verify(b).ok)


func _shapes(a: Dictionary) -> void:
	for section: String in ["top", "creator", "identity", "display_context"]:
		for mode: String in ["extra", "missing"]:
			var bad: Dictionary = a.duplicate(true)
			var selected: Dictionary = bad if section == "top" else bad[section]
			if mode == "extra":
				selected["future"] = false
			else:
				selected.erase(selected.keys()[0])
			check("closed " + section + " refuses " + mode + " field", not Published.verify(bad).ok)
	var bad: Dictionary = a.duplicate(true)
	bad.scale = 1
	check("same-value numeric type substitution refuses", not Published.verify(bad).ok)
	bad = a.duplicate(true)
	bad.display_context.revision = float(bad.display_context.revision)
	check("display revision cannot silently change type", not Published.verify(bad).ok)
	bad = a.duplicate(true)
	bad.errors = []
	check("packed carrier type is checked", not Published.verify(bad).ok)
	bad = a.duplicate(true)
	bad.creator.resolved = {}
	check("object-free serialized carrier cannot impersonate an owner", not Published.verify(bad).ok)
	bad = a.duplicate(true)
	bad.vehicle = "creator"
	check("saved payload cannot change discriminator", not Published.verify(bad).ok and not Published.is_trial(bad))


func _legacy(store: RefCounted, path: String, source: RefCounted) -> void:
	var doc: RefCounted = AuthoringFixture.populated(source)
	var compiled: Dictionary = doc.compile()
	check("legacy raw-v2 fixture compiles", compiled.ok)
	if not compiled.ok:
		return
	var publication := {"aircraft_uuid": doc.aircraft_uuid(), "name": "Legacy opaque",
		"definition": {"aircraft_uuid": doc.aircraft_uuid()}, "snapshot": {},
		"raw_bytes": compiled.value.raw_bytes(), "source_bytes": source.source_bytes(), "source_file_name": source.file_name(),
		"placement": doc.placement(), "bindings": {}, "appearance": {"mode": "original"}}
	var saved: Dictionary = store.publish_aircraft(publication, 0)
	check("opaque legacy Store v1 publishes raw v2", saved.ok)
	if not saved.ok:
		return
	var ref: Dictionary = SourceRef.make(doc.aircraft_uuid(), 1, saved.value.record_sha256).value
	var resolved: Dictionary = Resolver.resolve(path, ref)
	check("legacy resolves without compilation", resolved.ok)
	if not resolved.ok:
		return
	var trial: Dictionary = Published.prepare(resolved.value)
	check("legacy raw-v2 prepares exact unbound bytes", trial.ok and Published.verify(trial).ok
		and trial.raw_bytes == compiled.value.raw_bytes() and trial.identity.provenance == Resolver.LEGACY_UNBOUND and not trial.identity.has("qualification"))
	var raw: Dictionary = Bytes.decode(publication.raw_bytes).value.data
	var historical: Dictionary = AircraftData.legacy_v1_input(raw)
	var encoded: Dictionary = Bytes.encode(historical)
	check("explicit research v1 fixture loads", encoded.ok and RecordLoader.load_bytes(encoded.value.bytes, Definition.aircraft_id(doc.aircraft_uuid())).get("ok", false))
	if not encoded.ok:
		return
	publication.raw_bytes = encoded.value.bytes
	saved = store.publish_aircraft(publication, 1)
	check("historical raw v1 is stored as its own exact revision", saved.ok)
	if not saved.ok:
		return
	ref = SourceRef.make(doc.aircraft_uuid(), 2, saved.value.record_sha256).value
	resolved = Resolver.resolve(path, ref)
	check("v1 remains resolvable research data", resolved.ok and resolved.value.data().input_identity.format == AircraftData.LEGACY_FORMAT)
	if resolved.ok:
		check("raw aircraft v1 cannot prepare a product flight", not Published.prepare(resolved.value).ok)
