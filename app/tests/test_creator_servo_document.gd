extends SceneTree
## Document opt-in for the AC-12 servo law; this test does not grant flight qualification.
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Installation := preload("res://workshop/creator/source_installation.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("Creator servo document: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


func _run() -> void:
	_empty_and_edits()
	var ordinary: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "ordinary.glb")
	var converted := _convert_fixture()
	check("ordinary and ClearView fixtures are admitted", ordinary.ok and converted.ok)
	if not ordinary.ok or not converted.ok:
		return
	var source: RefCounted = converted.value.source
	var observed: Dictionary = Observations.inspect(source)
	check("source observations are independently checked", observed.ok and not observed.value.context().is_empty())
	if not observed.ok:
		return
	var report: RefCounted = observed.value
	var legacy_one := _populated(ordinary.value)
	var legacy_two := _populated(source, report)
	var legacy_three := _populated(source, report)
	check("installation can be explicitly selected", legacy_three.choose_source_installation(
		legacy_three.source_installation_proposal(), legacy_three.revision, true).ok)
	check("fixtures cover all historic document formats", legacy_one.snapshot().format == Authoring.SNAPSHOT_FORMAT
		and legacy_two.snapshot().format == Authoring.SOURCE_SNAPSHOT_FORMAT
		and legacy_three.snapshot().format == Authoring.INSTALLATION_SNAPSHOT_FORMAT)
	_legacy_roundtrip("v1", legacy_one, ordinary.value)
	_legacy_roundtrip("v2", legacy_two, source, report)
	_legacy_roundtrip("v3", legacy_three, source, report)
	_compiler_and_atomic_restore(legacy_one, ordinary.value)
	_pending_and_installed(legacy_two, source, report)
	_source_change(legacy_three, ordinary.value)


static func _convert_fixture() -> Dictionary:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\nmodelMass 4.1\nplaneType 0\n"
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Plane/params.txt", params.to_ascii_buffer()],
		["Plane/data/body.ac", CvFixture._ac_fixture().to_ascii_buffer()]]))
	return Converter.convert(package.value, "Plane") if package.ok else package


static func _populated(source: RefCounted, report: RefCounted = null) -> RefCounted:
	var doc := Authoring.new()
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


func _empty_and_edits() -> void:
	var doc := Authoring.new()
	var rev: int = doc.revision
	var original: Dictionary = doc.snapshot()
	var original_definition: Dictionary = doc.definition()
	var original_fingerprint: String = doc.fingerprint()
	check("blank starts with historical format and no law", not doc.has_unsaved_changes()
		and doc.servo_integration().is_empty() and original.format == Authoring.SNAPSHOT_FORMAT
		and original_definition.format == Definition.FORMAT and not original.has("servo_integration")
		and not original_definition.has("servo_integration"))
	check("empty clear is a no-op", doc.set_servo_integration("") and doc.revision == rev
		and doc.snapshot() == original)
	check("unknown law is refused without an edit", not doc.set_servo_integration("unknown")
		and doc.revision == rev and doc.snapshot() == original)
	for bad: Variant in [null, false, 1, [], {}, StringName(Definition.ServoLaw.LAW)]:
		check("non-string setter input is refused without an edit",
			not doc.set_servo_integration(bad) and doc.revision == rev and doc.snapshot() == original)
	check("explicit choice makes an otherwise empty document dirty", doc.set_servo_integration(Definition.ServoLaw.LAW)
		and doc.revision == rev + 1 and doc.has_unsaved_changes()
		and doc.snapshot().format == Authoring.SERVO_SNAPSHOT_FORMAT
		and doc.snapshot().servo_integration == Definition.ServoLaw.LAW
		and doc.definition().format == Definition.SERVO_FORMAT
		and doc.definition().servo_integration == Definition.ServoLaw.LAW
		and doc.fingerprint() != original_fingerprint)
	rev = doc.revision
	check("reselecting the same law is a no-op", doc.set_servo_integration(Definition.ServoLaw.LAW)
		and doc.revision == rev)
	for bad: Variant in [null, false, 1, [], {}, StringName(Definition.ServoLaw.LAW)]:
		check("non-string setter input cannot clear a selected law", not doc.set_servo_integration(bad)
			and doc.servo_integration() == Definition.ServoLaw.LAW and doc.revision == rev)
	check("explicit clear recovers the historic bytes and empty dirty state", doc.set_servo_integration("")
		and doc.revision == rev + 1 and not doc.has_unsaved_changes() and doc.snapshot() == original
		and doc.definition() == original_definition and doc.fingerprint() == original_fingerprint)
	doc.mark_saved("0".repeat(64))
	check("saved baseline includes the law choice", doc.set_servo_integration(Definition.ServoLaw.LAW)
		and doc.has_unsaved_changes() and doc.set_servo_integration("") and not doc.has_unsaved_changes())
	doc.set_servo_integration(Definition.ServoLaw.LAW)
	doc.mark_saved("3".repeat(64))
	check("clear and reselect tracks a saved opted-in baseline", doc.set_servo_integration("")
		and doc.has_unsaved_changes() and doc.set_servo_integration(Definition.ServoLaw.LAW)
		and not doc.has_unsaved_changes())


func _legacy_roundtrip(label: String, doc: RefCounted, source: RefCounted, report: RefCounted = null) -> void:
	var old_snapshot: Dictionary = doc.snapshot()
	var old_definition: Dictionary = doc.definition()
	var old_snapshot_encoded: Dictionary = Bytes.encode(old_snapshot)
	var old_definition_encoded: Dictionary = Bytes.encode(old_definition)
	var restored := Authoring.new()
	var opened: Dictionary = restored.restore(old_snapshot.duplicate(true), source, report)
	check(label + " historical snapshot restores without selecting a law", opened.ok
		and restored.servo_integration().is_empty() and restored.snapshot() == old_snapshot
		and restored.definition() == old_definition)
	check(label + " historical snapshot and definition bytes stay identical", old_snapshot_encoded.ok
		and old_definition_encoded.ok and Bytes.encode(restored.snapshot()).value.bytes == old_snapshot_encoded.value.bytes
		and Bytes.encode(restored.definition()).value.bytes == old_definition_encoded.value.bytes)
	restored.mark_saved("1".repeat(64))
	check(label + " opt-in then clear returns to the saved historical identity",
		restored.set_servo_integration(Definition.ServoLaw.LAW) and restored.has_unsaved_changes()
		and restored.set_servo_integration("") and not restored.has_unsaved_changes()
		and Bytes.encode(restored.snapshot()).value.bytes == old_snapshot_encoded.value.bytes
		and Bytes.encode(restored.definition()).value.bytes == old_definition_encoded.value.bytes)
	for smuggled: Variant in [null, "", Definition.ServoLaw.LAW]:
		var bad: Dictionary = old_snapshot.duplicate(true)
		bad.servo_integration = smuggled
		var prior: Dictionary = restored.snapshot()
		var prior_revision: int = restored.revision
		check(label + " refuses an unexpected servo member atomically", not restored.restore(bad, source, report).ok
			and restored.snapshot() == prior and restored.revision == prior_revision and not restored.has_unsaved_changes())


func _compiler_and_atomic_restore(doc: RefCounted, source: RefCounted) -> void:
	var legacy: Dictionary = doc.compile()
	check("historical document compiles", legacy.ok)
	if not legacy.ok:
		print("Historical document diagnostics: ",JSON.stringify(legacy.diagnostics))
		return
	var old_bytes: PackedByteArray = legacy.value.raw_bytes()
	var rev: int = doc.revision
	check("law selection is a revisioned edit", doc.set_servo_integration(Definition.ServoLaw.LAW)
		and doc.revision == rev + 1)
	var candidate: Dictionary = doc.compile()
	check("edit invalidates the cached legacy candidate", candidate.ok and candidate.value != legacy.value
		and candidate.value.raw_bytes() != old_bytes)
	if not candidate.ok:
		return
	var aircraft: Dictionary = Bytes.decode(candidate.value.raw_bytes())
	check("compiled record and readout carry exactly the selected law", aircraft.ok
		and aircraft.value.data.controls.servo_integration == Definition.ServoLaw.LAW
		and candidate.value.summary().servo_integration == Definition.ServoLaw.LAW)
	rev = doc.revision
	var same: Dictionary = doc.snapshot()
	var fingerprint: String = doc.fingerprint()
	check("no-op and refused setters preserve revision and cached candidate",
		doc.set_servo_integration(Definition.ServoLaw.LAW) and not doc.set_servo_integration("unrecognized")
		and doc.revision == rev and doc.snapshot() == same and doc.fingerprint() == fingerprint
		and doc.compile().value == candidate.value)
	var reopened := Authoring.new()
	check("v4 source snapshot restores exact state", reopened.restore(same.duplicate(true), source).ok
		and reopened.snapshot() == same and reopened.definition() == doc.definition()
		and reopened.fingerprint() == fingerprint and reopened.compile().ok
		and reopened.compile().value.raw_bytes() == candidate.value.raw_bytes())
	doc.mark_saved("2".repeat(64))
	for bad_value: Variant in [null, false, 1, 1.0, [], {}, "", "unknown", " " + Definition.ServoLaw.LAW,
			StringName(Definition.ServoLaw.LAW)]:
		var bad: Dictionary = same.duplicate(true)
		bad.servo_integration = bad_value
		bad.name = "must not be installed"
		check("bad v4 law refuses atomically", not doc.restore(bad, source).ok and doc.snapshot() == same
			and doc.revision == rev and doc.fingerprint() == fingerprint and not doc.has_unsaved_changes()
			and doc.compile().value == candidate.value)
	var missing: Dictionary = same.duplicate(true)
	missing.erase("servo_integration")
	missing.name = "must not be installed"
	check("missing v4 law refuses atomically", not doc.restore(missing, source).ok and doc.snapshot() == same
		and doc.revision == rev and doc.fingerprint() == fingerprint and not doc.has_unsaved_changes()
		and doc.compile().value == candidate.value)


func _pending_and_installed(doc: RefCounted, source: RefCounted, report: RefCounted) -> void:
	var context: Dictionary = doc.source_observations()
	check("pending v2 has a source-bound configuration gate", doc.needs_source_installation()
		and not doc.compile().ok)
	check("pending observations survive explicit servo selection", doc.set_servo_integration(Definition.ServoLaw.LAW)
		and doc.snapshot().format == Authoring.SERVO_SNAPSHOT_FORMAT
		and doc.snapshot().source_observations == context and not doc.snapshot().has("source_installation")
		and doc.definition().source_observations == context and not doc.definition().has("source_installation")
		and not Definition.validate_complete(doc.definition()).ok and not doc.compile().ok)
	var pending: Dictionary = doc.snapshot()
	var reopened := Authoring.new()
	check("v4 pending source round-trips with checked observations", reopened.restore(pending, source, report).ok
		and reopened.snapshot() == pending and reopened.source_observations() == context
		and reopened.needs_source_installation() and not reopened.compile().ok)
	var prior_revision: int = reopened.revision
	var forged: Dictionary = pending.duplicate(true)
	forged.source_observations.parameters_sha256 = "0".repeat(64)
	check("v4 observations cannot be forged or accepted without a checked report",
		not reopened.restore(forged, source, report).ok and reopened.snapshot() == pending
		and reopened.revision == prior_revision and not reopened.restore(pending, source).ok
		and reopened.snapshot() == pending and reopened.revision == prior_revision)
	check("explicit installation remains separate from servo selection", doc.choose_source_installation(
		doc.source_installation_proposal(), doc.revision, true).ok and doc.servo_integration() == Definition.ServoLaw.LAW
		and not doc.needs_source_installation() and doc.snapshot().format == Authoring.SERVO_SNAPSHOT_FORMAT
		and doc.snapshot().has("source_installation") and Definition.validate_complete(doc.definition()).ok)
	var installed: Dictionary = doc.snapshot()
	var compiled: Dictionary = doc.compile()
	if not compiled.ok:print("Installed document diagnostics: ",JSON.stringify(compiled.diagnostics))
	check("installed v4 compiles and follows the ordinary trial gate", compiled.ok
		and not doc.issues().any(func(d: Dictionary) -> bool: return d.message == Installation.FLIGHT_UNAVAILABLE))
	check("v4 installation and observations restore together", reopened.restore(installed, source, report).ok
		and reopened.snapshot() == installed and reopened.source_installation() == doc.source_installation())
	prior_revision = reopened.revision
	forged = installed.duplicate(true)
	forged.source_installation.report_sha256 = "0".repeat(64)
	check("v4 validates any present installation atomically", not reopened.restore(forged, source, report).ok
		and reopened.snapshot() == installed and reopened.revision == prior_revision)
	forged = installed.duplicate(true)
	forged.erase("source_observations")
	check("v4 cannot detach a report-bound installation from its observations",
		not reopened.restore(forged, source, report).ok and reopened.snapshot() == installed
		and reopened.revision == prior_revision)
	var unavailable := _populated(source)
	check("unavailable report can still be explicitly acknowledged", unavailable.choose_source_installation(
		unavailable.source_installation_proposal(), unavailable.revision, true).ok
		and unavailable.set_servo_integration(Definition.ServoLaw.LAW))
	var unavailable_saved: Dictionary = unavailable.snapshot()
	var refreshed := Authoring.new()
	check("newly available observations do not silently change a saved v4 installation",
		refreshed.restore(unavailable_saved, source, report).ok and refreshed.snapshot() == unavailable_saved
		and refreshed.source_observations().is_empty() and refreshed.review_source_observations() == context
		and refreshed.needs_source_installation() and not refreshed.compile().ok)


func _source_change(doc: RefCounted, replacement: RefCounted) -> void:
	check("source change setup has a reviewed installation", not doc.source_installation().is_empty()
		and doc.placement_result().ok and doc.set_servo_integration(Definition.ServoLaw.LAW))
	doc.set_source(replacement)
	check("new source retains physical-law choice while invalidating old installation and placement",
		doc.servo_integration() == Definition.ServoLaw.LAW and doc.source_installation().is_empty()
		and doc.source_observations().is_empty() and not doc.placement_result().ok
		and doc.snapshot().format == Authoring.SERVO_SNAPSHOT_FORMAT)
