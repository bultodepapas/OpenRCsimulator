extends SceneTree
## Dated observation, not a regression test asserting the desired future behavior.
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Store := preload("res://workshop/creator/store.gd")
const ITEM := "item_wing_airframe"
var report := {base_commit = "08f948265d40d83fbb4726a302b9e1c9490ccfce", cases = []}


func _initialize() -> void:
	_run.call_deferred()


func _settle() -> void:
	for _index: int in 3:
		await process_frame


func _item(doc: RefCounted) -> Dictionary:
	for entry: Dictionary in doc.inventory():
		if entry.id == ITEM:
			return entry
	return {}


func _state(wizard: Control) -> Dictionary:
	var doc: RefCounted = wizard.document()
	var edit := wizard.find_child("ItemMassItemWingAirframe", true, false) as LineEdit
	var local: Array = wizard._local_issues()
	return {revision = doc.revision, fingerprint = doc.fingerprint(),
		dirty = wizard.has_unsaved_changes(), mass = _item(doc).get("mass"),
		visible_text = edit.text if edit != null else "CONTROL_MISSING", local_issues = local,
		invalid_inventory_fields = wizard.get("_item_invalid").duplicate(true)}


func _remove_tree(path: String) -> void:
	for directory: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var inspected: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "audit-trainer.glb")
	if not inspected.ok:
		printerr("Probe setup refused source: ", inspected)
		quit(1)
		return
	var doc: RefCounted = AuthoringFixture.populated(inspected.value)
	var path := "user://followup-inventory-%d" % Time.get_ticks_usec()
	var wizard := Creator.new() as Control
	wizard.set("store_root", path)
	wizard.theme = UiTheme.build()
	root.add_child(wizard)
	await _settle()
	# Install a valid test document; this does not exercise asynchronous source re-admission.
	wizard._adopt_document(doc, "weight_balance")
	await _settle()
	if not wizard._save_draft():
		printerr("Probe setup could not save initial draft: ", wizard.save_state())
		wizard.free()
		quit(1)
		return
	await _settle()
	var before := _state(wizard)
	var edit := wizard.find_child("ItemMassItemWingAirframe", true, false) as LineEdit
	if edit == null:
		printerr("Probe setup could not find the real inventory mass control")
		wizard.free()
		quit(1)
		return
	edit.grab_focus()
	edit.text = "not-a-number"
	edit.text_changed.emit(edit.text)
	edit.text_submitted.emit(edit.text)
	await _settle()
	var after_edit := _state(wizard)
	wizard._write_backup(true)
	var view: Dictionary = Store.open(path, {read_only = true})
	if not view.ok:
		printerr("Probe could not inspect isolated store: ", view)
		wizard.free()
		quit(1)
		return
	var store: RefCounted = view.value
	var recovery_count: int = store.list_recovery().size()
	var saved: bool = wizard._save_draft()
	var loaded: Dictionary = store.load_draft(doc.draft_id)
	store.close()
	if not loaded.ok:
		printerr("Probe could not read saved draft: ", loaded)
		wizard.free()
		quit(1)
		return
	var stored_invalid_text := JSON.stringify(loaded.value.snapshot).contains("not-a-number")
	var reopened: bool = wizard._finish_open("draft", loaded.value, inspected.value)
	await _settle()
	var after_reopen := _state(wizard)
	report.cases.append({case_name = "invalid_inventory_mass_save_reopen", before = before,
		after_edit = after_edit, forced_backup_entry_count = recovery_count, save_ok = saved,
		stored_snapshot_contains_invalid_text = stored_invalid_text, reopen_ok = reopened,
		after_reopen = after_reopen})
	# Separate documented policy: Estimated items are replaced by Propose.
	var proposal_doc: RefCounted = AuthoringFixture.populated(inspected.value)
	var proposed := _item(proposal_doc)
	var accepted: bool = proposal_doc.set_item_raw(ITEM, "mass", "0.75")
	var edited := _item(proposal_doc)
	proposal_doc.propose_inventory()
	var reproposed := _item(proposal_doc)
	report.cases.append({case_name = "documented_estimated_item_reproposal_policy",
		initial = proposed, accepted_edit = accepted, edited = edited, reproposed = reproposed})
	wizard.free()
	await _settle()
	Creator.reap_abandoned_imports()
	_remove_tree(ProjectSettings.globalize_path(path))
	report.isolated_store_removed = not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))
	print("AUDIT_INVENTORY_JSON: ", JSON.stringify(report, "", true, true))
	print("AUDIT_INVENTORY_COMPLETE")
	quit(0)
