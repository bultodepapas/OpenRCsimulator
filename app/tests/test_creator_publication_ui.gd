extends SceneTree
## Stored v4 identity is checked before editor adoption; direct publication obeys UI buffers.
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Store := preload("res://workshop/creator/store.gd")
const Publication := preload("res://workshop/creator/compiled_publication.gd")
const Binding := preload("res://workshop/creator/compile_binding.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const BindingTests := preload("res://tests/test_creator_compile_binding.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var source: RefCounted = Importer.inspect_bytes(Fixture.airplane_glb(), "trainer.glb").value
	var a: RefCounted = BindingTests._populated(source)
	a.set_bindings({format = "openrc-creator-bindings v1", controls = {
		aileron_left = [{node = 3, axis = "z", sign = 1}]}})
	a.set_servo_integration(Definition.ServoLaw.LAW)
	var b := Authoring.new()
	check("B restores A", b.restore(a.snapshot(), source).ok)
	b.set_value("controls/servo_time_s", 0.2)
	var ca: Dictionary = Publication.capture(a, "review_test")
	var cb: Dictionary = Publication.capture(b, "review_test")
	check("two physical revisions capture", ca.ok and cb.ok)
	if not ca.ok or not cb.ok:
		_finish()
		return
	var folder := "user://creator_publication_ui_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	print("Creator publication UI disposable root: ", folder)
	var store: RefCounted = Store.open(folder).value
	check("A and B publish", store.publish_compiled_aircraft(ca.value, 0).ok
		and store.publish_compiled_aircraft(cb.value, 1).ok)
	var va: Dictionary = store.load_aircraft(a.aircraft_uuid(), 1).value
	var vb: Dictionary = store.load_aircraft(a.aircraft_uuid(), 2).value
	var restored := Authoring.new()
	check("stored snapshot independently restores", restored.restore(va.snapshot, source).ok)
	var joined: Dictionary = Publication.match_document(restored, va)
	check("stored revision rejoins before the UI", joined.ok)
	if not joined.ok:
		print("Join diagnostics: ", joined)
		var snapshot: Dictionary = restored.snapshot(va.snapshot.step)
		for key: String in snapshot:
			if snapshot[key] != va.snapshot.get(key):
				print("Snapshot difference: ", key, " restored=", snapshot[key], " stored=", va.snapshot.get(key))
		print("Join components: definition=", restored.definition() == va.definition,
			" placement=", restored.placement() == va.placement, " bindings=", restored.bindings() == va.bindings,
			" paint=", restored.appearance() == va.appearance, " source=", source.file_name() == va.source_file_name)
	store.close()
	var wizard := Creator.new()
	wizard.store_root = folder
	wizard.theme = UiTheme.build()
	root.add_child(wizard)
	for _frame: int in 3:
		await process_frame
	check("actual stored A reopens", wizard._finish_open("aircraft", va, source))
	check("A keeps its explicit law and published revision", wizard._doc.servo_integration() == Definition.ServoLaw.LAW
		and wizard._doc.published_revision == 1 and wizard._doc.definition() == va.definition)
	check("actual stored B reopens", wizard._finish_open("aircraft", vb, source))
	check("B retains its definition without recompilation", wizard._doc.definition() == vb.definition
		and wizard._doc.published_revision == 2)
	var mixed: Dictionary = va.duplicate(true)
	mixed.raw_bytes = vb.raw_bytes
	mixed.raw_sha256 = vb.raw_sha256
	_refuses(wizard, mixed, source, "same UUID/law raw from B cannot enter A")
	mixed = va.duplicate(true)
	mixed.definition = vb.definition
	mixed.definition_sha256 = vb.definition_sha256
	_refuses(wizard, mixed, source, "definition from B cannot enter snapshot A")
	mixed = va.duplicate(true)
	mixed.erase("compile_binding")
	_refuses(wizard, mixed, source, "missing receipt refuses")
	mixed = va.duplicate(true)
	mixed.compile_binding.profile = "future-profile"
	_refuses(wizard, mixed, source, "unknown receipt profile refuses")
	mixed = va.duplicate(true)
	mixed.source_bytes = PackedByteArray([1, 2, 3])
	_refuses(wizard, mixed, source, "different source bytes refuse")
	mixed = va.duplicate(true)
	mixed.name = "Other name"
	_refuses(wizard, mixed, source, "different record name refuses")
	mixed = va.duplicate(true)
	mixed.placement.unit_scale = 2.0
	_refuses(wizard, mixed, source, "different record placement refuses")
	mixed = va.duplicate(true)
	mixed.appearance = {mode = "solid", color = "#cc0011"}
	_refuses(wizard, mixed, source, "different record paint refuses")
	mixed = va.duplicate(true)
	mixed.bindings = {controls = "invalid"}
	mixed.snapshot.bindings = mixed.bindings.duplicate(true)
	_refuses(wizard, mixed, source, "matching invalid bindings still refuse")
	mixed = va.duplicate(true)
	mixed.appearance = {mode = "unsupported"}
	mixed.snapshot.appearance = mixed.appearance.duplicate(true)
	_refuses(wizard, mixed, source, "matching invalid paint still refuses")
	var legacy := Authoring.new()
	check("historical document restores", legacy.restore(a.snapshot(), source).ok and legacy.set_servo_integration(""))
	var old: Dictionary = legacy.compile()
	check("historical physical data compiles", old.ok)
	mixed = va.duplicate(true)
	mixed.snapshot = legacy.snapshot("review_test")
	mixed.definition = Definition.validate_complete(legacy.definition()).value
	mixed.definition_sha256 = old.value.definition_sha256()
	mixed.erase("compile_binding")
	mixed.erase("record_format")
	_refuses(wizard, mixed, source, "old carrier cannot hide selected-law raw")
	mixed = va.duplicate(true)
	mixed.raw_bytes = old.value.raw_bytes()
	mixed.raw_sha256 = old.value.raw_sha256()
	_refuses(wizard, mixed, source, "selected-law carrier cannot use old raw")
	var owned_store: RefCounted = wizard._store
	var generation: int = owned_store.generation()
	wizard._wingspan_problem = "invalid typed wingspan"
	wizard._on_publish_pressed()
	check("direct publish obeys invalid UI-owned text", owned_store.generation() == generation
		and wizard._doc.published_revision == 2)
	wizard._wingspan_problem = ""
	wizard._on_publish_pressed()
	check("editor publishes the captured next version", wizard._doc.published_revision == 3)
	var published: Dictionary = owned_store.load_aircraft(a.aircraft_uuid(), 3)
	check("editor output retains B bytes and its own binding", published.ok and published.value.raw_bytes == vb.raw_bytes
		and published.value.record_format == Binding.REVISION_FORMAT
		and Binding.matches(published.value.compile_binding, published.value.definition_sha256, published.value.raw_sha256))
	var draft: Dictionary = owned_store.load_draft(wizard._doc.draft_id)
	check("v4 draft still reopens through draft route", draft.ok and wizard._finish_open("draft", draft.value, source)
		and wizard._doc.servo_integration() == Definition.ServoLaw.LAW)
	if draft.ok:
		check("v4 recovery still restores without a publication receipt", wizard._finish_open("recovery", draft.value, source)
			and wizard._doc.servo_integration() == Definition.ServoLaw.LAW)
	wizard.queue_free()
	await process_frame
	_finish()


func _refuses(wizard: Control, value: Dictionary, source: RefCounted, label: String) -> void:
	var current: RefCounted = wizard._doc
	var before: Dictionary = current.snapshot()
	var revision: int = current.published_revision
	wizard._wingspan_problem = "retain typed text"
	check(label, not wizard._finish_open("aircraft", value, source) and wizard._doc == current
		and current.snapshot() == before and current.published_revision == revision
		and wizard._wingspan_problem == "retain typed text")
	wizard._wingspan_problem = ""


func _finish() -> void:
	print("Creator publication UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
