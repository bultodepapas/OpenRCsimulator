extends SceneTree
## Boundary observation: a local association receipt does not prove external derivation.
const Importer := preload("res://workshop/creator/source_importer.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Publication := preload("res://workshop/creator/compiled_publication.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")


func _initialize() -> void:
	var inspected: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "audit-trainer.glb")
	if not inspected.ok:
		printerr("Probe setup could not admit ordinary source: ", inspected)
		quit(1)
		return
	var a: RefCounted = AuthoringFixture.populated(inspected.value)
	a.set_servo_integration(Definition.ServoLaw.LAW)
	var ca: Dictionary = a.compile()
	var b := Authoring.new()
	var restored: Dictionary = b.restore(a.snapshot(), inspected.value)
	if not restored.ok:
		printerr("Probe setup could not restore B: ", restored)
		quit(1)
		return
	b.set_value("controls/servo_time_s", 0.2)
	var cb: Dictionary = b.compile()
	var captured: Dictionary = Publication.capture(a, "review_test")
	if not ca.ok or not cb.ok or not captured.ok:
		printerr("Probe setup could not compile/capture: ", ca, cb, captured)
		quit(1)
		return
	var raw_a: PackedByteArray = ca.value.raw_bytes()
	var raw_b: PackedByteArray = cb.value.raw_bytes()
	var definition_a: Dictionary = a.definition()
	var definition_bytes: Dictionary = Bytes.encode(definition_a)
	var raw_b_sha := Bytes.sha256(raw_b)
	var rebound := Binding.make(definition_bytes.value.sha256, raw_b_sha)
	# Construct a received association, not a Captured owner or a Store write.
	var received: Dictionary = captured.value.publication()
	received.raw_bytes = raw_b
	received.raw_sha256 = raw_b_sha
	received.definition_sha256 = definition_bytes.value.sha256
	received.source_sha256 = Bytes.sha256(received.source_bytes)
	received.record_format = Binding.REVISION_FORMAT
	received.compile_binding = rebound
	var joined: Dictionary = Publication.match_document(a, received)
	var report := {base_commit = "08f948265d40d83fbb4726a302b9e1c9490ccfce",
		same_uuid = a.aircraft_uuid() == b.aircraft_uuid(), same_law = a.servo_integration() == b.servo_integration(),
		servo_time_a = a.value("controls/servo_time_s"), servo_time_b = b.value("controls/servo_time_s"),
		definition_a_sha256 = definition_bytes.value.sha256,
		raw_a_sha256 = Bytes.sha256(raw_a), raw_b_sha256 = raw_b_sha,
		compiled_bytes_differ = raw_a != raw_b,
		cross_pair_valid_pair = Publication.valid_pair(definition_a, raw_b, a.aircraft_uuid()),
		recomputed_binding_matches = Binding.matches(rebound, definition_bytes.value.sha256, raw_b_sha),
		cross_pair_match_document_ok = joined.ok, cross_pair_match_document_diagnostics = joined.diagnostics,
		trusted_capture_keeps_corresponding_bytes = captured.value.publication().raw_bytes == raw_a,
		scope = "Read-only helpers; no Store publication, external bundle admission or flight was performed."}
	print("AUDIT_SEMANTIC_PAIR_JSON: ", JSON.stringify(report, "", true, true))
	print("AUDIT_SEMANTIC_PAIR_COMPLETE")
	quit(0)
