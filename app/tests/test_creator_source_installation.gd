extends SceneTree
const Installation := preload("res://workshop/creator/source_installation.gd")
const Observations := preload("res://workshop/creator/clearview/observations.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Compiler := preload("res://workshop/creator/compiler.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Trial := preload("res://workshop/creator/trial.gd")
const Bytes := preload("res://workshop/creator/bytes.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const CvFixture := preload("res://tests/test_creator_clearview_readers.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Package := preload("res://workshop/creator/clearview/package.gd")
const ChoicePanel := preload("res://ui/aircraft_creator_installation.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String,good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

static func convert_fixture() -> Dictionary:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\nmodelMass 4.1\nplaneType 0\n"
	var package := Package.inspect_bytes(CvFixture._zip_bytes([["Plane/params.txt",params.to_ascii_buffer()],
		["Plane/data/body.ac",CvFixture._ac_fixture().to_ascii_buffer()]]))
	return Converter.convert(package.value,"Plane")

static func retag(bytes: PackedByteArray,value: Variant,node_only := false) -> Dictionary:
	var at := 20+bytes.decode_u32(12)
	var document: Dictionary = JSON.parse_string(bytes.slice(20,at).get_string_from_utf8())
	if node_only:
		document.nodes[0].extras = {openrc_clearview = value}
	else:
		document.asset.extras = {openrc_clearview = value}
	return Importer.inspect_bytes(Fixture.glb(document,bytes.slice(at+8,at+8+bytes.decode_u32(at))), "tag.glb")

static func populated(source: RefCounted,report: RefCounted = null) -> RefCounted:
	var doc := Authoring.new()
	doc.set_source(source,report)
	var template := Definition.template()
	var values := {}
	for entry: Dictionary in Authoring.FIELDS:
		values[entry.path] = Authoring._lookup(template,entry.path.split("/"))
	doc.apply_values(values,true)
	doc.propose_inventory()
	doc.set_axis("nose_axis","+x")
	doc.set_axis("up_axis","+z")
	doc.set_units("m")
	doc.set_datum([0.0,0.0,0.0])
	return doc

func _run() -> void:
	var ordinary := Importer.inspect_bytes(Fixture.airplane_glb(),"ordinary.glb")
	check("ordinary GLB does not declare ClearView",ordinary.ok and not Installation.required(ordinary.value))
	for value: Variant in [null,false,[],"legacy",{format = "future"},{format = "openrc-clearview-visual-v1",parameters_omitted = "metadata_limit"}]:
		var tagged := retag(Fixture.airplane_glb(),value)
		check("namespace presence requires a choice regardless of its value",tagged.ok and Installation.required(tagged.value))
		var doc := populated(tagged.value)
		check("unavailable observations cannot bypass the authoring gate",doc.needs_source_installation() and not doc.compile().ok and doc.source_installation_proposal().report_state == "unavailable")
	var node_only := retag(Fixture.airplane_glb(),false,true)
	check("node extras do not declare asset origin",node_only.ok and not Installation.required(node_only.value))
	var converted := convert_fixture()
	check("current ZIP converts with a recognized namespace",converted.ok and Installation.required(converted.value.source))
	if not converted.ok:
		quit(1)
		return
	var source: RefCounted = converted.value.source
	var inspected := Observations.inspect(source)
	var context: Dictionary = inspected.value.context()
	var unavailable := populated(source)
	check("unavailable report can be explicitly acknowledged",unavailable.choose_source_installation(unavailable.source_installation_proposal(),unavailable.revision,true).ok and unavailable.definition().source_installation.report_state == "unavailable")
	var unavailable_saved: Dictionary = unavailable.snapshot()
	var renewed := Authoring.new()
	check("a newly available report cannot silently update a saved declaration",renewed.restore(unavailable_saved,source,inspected.value).ok and renewed.snapshot() == unavailable_saved and renewed.needs_source_installation() and not renewed.compile().ok)
	check("fresh references are reviewable before changing historical identity",renewed.source_observations().is_empty() and renewed.review_source_observations() == context)
	check("a fresh choice binds the newly available report",renewed.choose_source_installation(renewed.source_installation_proposal(),renewed.revision,true).ok and renewed.source_installation().report_state == "available")
	var doc := populated(source,inspected.value)
	var legacy_snapshot: Dictionary = doc.snapshot()
	var legacy_definition: Dictionary = doc.definition()
	check("v2 remains structurally readable",legacy_snapshot.format == Authoring.SOURCE_SNAPSHOT_FORMAT and Definition.validate_complete(legacy_definition).ok)
	check("direct v2 compilation cannot select an implicit package",not Compiler.compile_candidate(legacy_definition).ok)
	check("choice diagnostic exists before a complete aircraft",populated(source).issues().any(func(d: Dictionary) -> bool: return d.message == Installation.REQUIRED))
	var before: Dictionary = doc.snapshot()
	check("unreviewed choice preserves all work",not doc.choose_source_installation(doc.source_installation_proposal(),doc.revision,false).ok and doc.snapshot() == before)
	var stale: Dictionary = doc.source_installation_proposal()
	var revision: int = doc.revision
	doc.apply_values({"wing/span":1.6},true)
	before = doc.snapshot()
	check("queued confirmation cannot approve later edits",not doc.choose_source_installation(stale,revision,true).ok and doc.snapshot() == before)
	doc.apply_values({"wing/span":1.5},true)
	check("reviewed explicit declaration succeeds",doc.choose_source_installation(doc.source_installation_proposal(),doc.revision,true).ok and not doc.needs_source_installation())
	check("v3 stores exact source, report and package association",doc.snapshot().format == Authoring.INSTALLATION_SNAPSHOT_FORMAT and doc.definition().format == Definition.INSTALLATION_FORMAT and doc.source_installation().source_sha256 == source.sha256() and doc.source_installation().report_sha256 == Observations.digest(context))
	var candidate: Dictionary = doc.compile()
	check("independent installation compiles for review and storage",candidate.ok)
	var plain: Dictionary = doc.definition()
	plain.erase("source_observations")
	plain.erase("source_installation")
	plain.format = Definition.FORMAT
	var plain_candidate := Compiler.compile_candidate(plain)
	check("choice changes definition identity without changing physical bytes",candidate.ok and plain_candidate.ok and candidate.value.raw_bytes() == plain_candidate.value.raw_bytes() and candidate.value.definition_sha256() != plain_candidate.value.definition_sha256())
	if not candidate.ok or not plain_candidate.ok:
		printerr(candidate.get("diagnostics",[]),plain_candidate.get("diagnostics",[]))
		quit(1)
		return
	check("a confirmed installation follows the ordinary trial gate",not doc.issues().any(func(d: Dictionary) -> bool:
		return d.message in [Installation.FLIGHT_UNAVAILABLE,Installation.REQUIRED]))
	var reopened := Authoring.new()
	var saved: Dictionary = Bytes.decode(Bytes.encode(doc.snapshot()).value.bytes).value.data
	check("v3 survives exact persisted roundtrip",reopened.restore(saved,source,Observations.inspect(source).value).ok and reopened.snapshot() == doc.snapshot() and reopened.source_installation() == doc.source_installation())
	for field: String in Installation.KEYS:
		for wrong: Variant in [null,false,[],{},2.0,"unknown"]:
			var bad: Dictionary = doc.definition()
			bad.source_installation[field] = wrong
			check("invalid declaration is rejected: "+field,not Compiler.compile_candidate(bad).ok)
	var mismatch: Dictionary = doc.definition()
	mismatch.source_installation.source_sha256 = "0".repeat(64)
	check("report and source must agree",not Compiler.compile_candidate(mismatch).ok)
	var legacy_doc := Authoring.new()
	check("historical v2 restores without a hidden migration",legacy_doc.restore(legacy_snapshot,source,Observations.inspect(source).value).ok and legacy_doc.snapshot() == legacy_snapshot and legacy_doc.definition() == legacy_definition and legacy_doc.needs_source_installation())
	var old_v1: Dictionary = legacy_snapshot.duplicate(true)
	old_v1.format = Authoring.SNAPSHOT_FORMAT
	old_v1.erase("source_observations")
	check("historical v1 recognized source also requires a choice",legacy_doc.restore(old_v1,source,Observations.inspect(source).value).ok and legacy_doc.needs_source_installation() and legacy_doc.snapshot().format == Authoring.SNAPSHOT_FORMAT)
	var measured: String = doc.inventory()[0].id
	doc.set_item_kind(measured,"measured")
	var retained: Array = doc.inventory()
	doc.set_source(retag(Fixture.airplane_glb(),null).value)
	check("source replacement clears choice and preserves reviewed work",doc.needs_source_installation() and doc.source_installation().is_empty() and doc.inventory() == retained and doc.inventory()[0].kind == "measured")
	_pairing(candidate.value,plain_candidate.value,source,ordinary.value)
	var regular := populated(ordinary.value)
	check("ordinary source retains v1 compilation",regular.snapshot().format == Authoring.SNAPSHOT_FORMAT and regular.compile().ok and regular.source_installation_proposal().is_empty())
	check("ordinary completed power step keeps its status",regular.step_status("power_mount") == Authoring.STATUS_COMPLETE)
	var panel := ChoicePanel.new()
	root.add_child(panel)
	panel.show_state(source.get_instance_id(),reopened.revision,reopened.source_installation_proposal(),false,false)
	check("choice cannot be made before review",panel._choose.disabled)
	panel._review.button_pressed = true
	check("review enables explicit choice",not panel._choose.disabled)
	panel.show_state(source.get_instance_id(),reopened.revision+1,reopened.source_installation_proposal(),false,false)
	check("editing resets pending review",panel._choose.disabled and not panel._review.button_pressed)
	panel._review.button_pressed = true
	panel.show_state(source.get_instance_id(),reopened.revision+1,reopened.source_installation_proposal(),false,true)
	check("opening or importing disables confirmation",panel._choose.disabled)
	panel.queue_free()
	await process_frame
	print("Creator source installation: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _pairing(candidate: RefCounted,plain: RefCounted,source: RefCounted,ordinary: RefCounted) -> void:
	var request := {creator_candidate = candidate,creator_source = source,creator_placement = {nose_axis = "+x",up_axis = "+z",unit_scale = 1.0,datum = [0.0,0.0,0.0]}}
	var confirmed := Trial.freeze(request)
	check("confirmed installation grants the experimental test flight",confirmed.ok and Trial.verify(confirmed).ok
		and confirmed.identity.experimental and confirmed.identity.source_installation.source_sha256 == source.sha256())
	if confirmed.ok:
		var unpinned: Dictionary = confirmed.duplicate(true)
		unpinned.identity.erase("source_installation")
		var bare: Dictionary = unpinned.identity.duplicate(true)
		bare.erase("trial_id")
		bare.erase("experimental")
		unpinned.identity.trial_id = Trial._trial_id(bare)
		var stripped := Trial.verify(unpinned)
		check("a ClearView trial without its pinned installation is refused",not stripped.ok and stripped.errors[0] == Installation.REQUIRED)
	request.creator_candidate = plain
	check("ordinary candidate cannot bypass a recognized source",not Trial.freeze(request).ok)
	request.creator_candidate = candidate
	request.creator_source = ordinary
	check("bound candidate cannot be paired with an ordinary different source",not Trial.freeze(request).ok)
	request.creator_source = retag(Fixture.airplane_glb(),false).value
	check("bound candidate cannot be paired with a different recognized source",not Trial.freeze(request).ok)
	request.creator_source = ordinary
	request.creator_candidate = plain
	var trial := Trial.freeze(request)
	check("ordinary v1 source pairing is preserved",trial.ok and Trial.verify(trial).ok)
	if trial.ok:
		trial.creator.source = source
		trial.identity.source_sha256 = source.sha256()
		var pinned: Dictionary = trial.identity.duplicate(true)
		pinned.erase("trial_id")
		pinned.erase("experimental")
		trial.identity.trial_id = Trial._trial_id(pinned)
		var historical := Trial.verify(trial)
		check("a relabelled ordinary trial cannot fly a ClearView source",not historical.ok and historical.errors[0] == Installation.REQUIRED)
