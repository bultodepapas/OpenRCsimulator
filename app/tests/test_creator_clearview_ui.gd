extends SceneTree
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Fixture := preload("res://tests/test_creator_clearview_readers.gd")
const Converter := preload("res://workshop/creator/clearview/converter.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
var failures := 0
var checks := 0
var _directory := "user://clearview-ui-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ",label)

func _settle(count := 3) -> void:
	for index: int in count:
		await process_frame

func _wait(wizard: Control) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while (wizard.import_state().state == "inspecting" or wizard.save_state().opening) and Time.get_ticks_msec() < deadline:
		await process_frame
	check("worker completed", wizard.import_state().state != "inspecting" and not wizard.save_state().opening)
	await _settle()

func _wizard() -> Control:
	var wizard := Creator.new()
	wizard.store_root = _directory + "/library"
	wizard.theme = UiTheme.build()
	root.add_child(wizard)
	return wizard

func _write(name: String, bytes: PackedByteArray) -> String:
	var path := _directory + "/" + name
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path

func _zip(two := false) -> PackedByteArray:
	var params := "verNumber 5\nmodelType 1\nmodelName body.ac\nmodelMass 4.1\ngravity 11.1\n".to_ascii_buffer()
	var files: Array = [["One/params.txt",params],["One/data/body.ac",Fixture._ac_fixture().to_ascii_buffer()]]
	if two:
		files.append_array([["Two/params.txt",params],["Two/data/body.ac",Fixture._ac_fixture().to_ascii_buffer()]])
	return Fixture._zip_bytes(files,true)

func _run() -> void:
	root.size = Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	var one := _write("one.zip",_zip())
	var pack := _write("pack.zip",_zip(true))
	var bad := _write("broken.zip",PackedByteArray([80,75,1,2]))
	var wizard := _wizard()
	await _settle()
	wizard.request_import(one)
	await _wait(wizard)
	check("single ZIP automatically selects its model", wizard.import_state().state == "imported")
	var source: RefCounted = wizard.document().source()
	check("converted source is an admitted GLB", source != null and source.format() == "glb")
	check("source physics remains unimported", source != null and not Converter.source_notes(source).is_empty())
	if source == null:
		wizard.queue_free()
		await _settle()
		_finish()
		return
	var original: String = source.sha256()
	var observations: Dictionary = wizard.document().source_observations()
	check("worker derives source declarations",not observations.is_empty() and observations.observations.size() == 2)
	var report: Control = wizard.find_child("SourceDeclarations",true,false)
	var toggle: Button = wizard.find_child("InspectSourceDeclarations",true,false)
	var details: Control = wizard.find_child("SourceDeclarationDetails",true,false)
	check("declarations are available and initially collapsed",report.visible and not details.visible)
	toggle.button_pressed = true
	await _settle()
	check("declarations expand on import page",details.visible)
	wizard.document().name = "ClearView draft"
	check("normalized source can be saved as a draft", wizard.call("_save_draft"))
	var draft: String = wizard.document().draft_id
	wizard.call("_start_import",bad)
	await _wait(wizard)
	check("failed ZIP preserves current source", wizard.document().source().sha256() == original)
	wizard.call("_start_import",pack)
	await _wait(wizard)
	check("pack opens model picker", wizard.import_state().state == "choosing")
	var picker: ConfirmationDialog = wizard.find_child("ClearViewModelPicker",true,false)
	var list: ItemList = wizard.find_child("ClearViewModels",true,false)
	check("picker is visible and contains both models", picker.visible and list.item_count == 2)
	var explanation: Label = wizard.find_child("ClearViewExplanation",true,false)
	check("picker instructions never overlap its rows", explanation.get_global_rect().end.y <= list.get_global_rect().position.y)
	check("pending model selection is guarded", wizard.has_unsaved_changes() and not wizard.call("_save_draft"))
	check("pending selection cannot test fly", (wizard.find_child("TestFly",true,false) as Button).disabled)
	wizard.cancel_import()
	check("cancel preserves source and closes picker", wizard.document().source().sha256() == original and not picker.visible)
	wizard.call("_start_import",pack)
	await _wait(wizard)
	list.select(1)
	picker.confirmed.emit()
	await _wait(wizard)
	check("explicit pack selection imports its exact model", wizard.import_state().state == "imported" and wizard.document().source().file_name() == "Two.glb")
	# Cancelled inspection must never adopt a stale result over the current source.
	var selected: String = wizard.document().source().sha256()
	wizard.call("_start_import",one)
	wizard.cancel_import()
	await _settle(6)
	check("cancelled worker cannot replace the model", wizard.document().source().sha256() == selected)
	var deadline := Time.get_ticks_msec() + 5000
	while Creator.reap_abandoned_imports() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	# Existing dirty work survives a backup timer expiring while a ZIP is pending.
	wizard.document().name = "Dirty work"
	wizard.call("_start_import",pack)
	wizard.call("_write_backup")
	var timer: Timer = wizard.get("_backup_timer")
	check("backup is rearmed while import is pending", not timer.is_stopped())
	wizard.cancel_import()
	wizard.call("_write_backup")
	var store: RefCounted = wizard.get("_store")
	var recovery: Dictionary = store.load_recovery(wizard.document().draft_id)
	check("dirty source remains recoverable after cancellation", recovery.ok and recovery.value.source_bytes == wizard.document().source().source_bytes())
	wizard.queue_free()
	await _settle(6)
	wizard = _wizard()
	await _settle()
	# Skip the backup question only to exercise the saved draft's public library path.
	wizard.dismiss_modal_for_exit()
	wizard.call("_on_library_open","draft",draft)
	await _wait(wizard)
	check("saved converted source reopens", wizard.document().source() != null and wizard.document().source().sha256() == original)
	check("source declarations survive draft save and worker reopen",wizard.document().source_observations() == observations)
	var notes: VBoxContainer = wizard.find_child("ImportNotes",true,false)
	check("ClearView provenance warning survives reopen", notes.get_child_count() >= 2)
	# Hold adoption on the main thread so a fast worker cannot hide an edit/open race.
	store = wizard.get("_store")
	var loaded: Dictionary = store.load_draft(draft)
	wizard.call("_begin_open","draft",loaded.value)
	wizard.set_process(false)
	wizard.document().name = "Edited while opening"
	await _settle(3)
	wizard.set_process(true)
	await _wait(wizard)
	check("opening never discards intervening edits", wizard.document().name == "Edited while opening")
	wizard.call("_on_add_item_pressed")
	wizard.go_to_step("weight_balance")
	var item: Dictionary = wizard.document().inventory().back()
	var rows: Dictionary = wizard.get("_item_rows")
	var mass: LineEdit = rows[item.id].mass
	wizard.call("_begin_open","draft",loaded.value)
	wizard.set_process(false)
	mass.text = "invalid mass"
	mass.text_changed.emit(mass.text)
	mass.text_submitted.emit(mass.text)
	wizard.set_process(true)
	await _wait(wizard)
	check("opening preserves UI-owned invalid inventory text", wizard.get("_item_texts").get(item.id + "/mass","") == "invalid mass")
	wizard.go_to_step("import")
	wizard.call("_begin_open","draft",loaded.value)
	wizard.set_process(false)
	wizard.go_to_step("weight_balance")
	wizard.go_to_step("orient_size")
	wizard.set_process(true)
	await _wait(wizard)
	check("navigation alone does not prevent opening", wizard.document().name == "ClearView draft")
	await _revision(wizard)
	wizard.queue_free()
	await _settle(6)
	deadline = Time.get_ticks_msec() + 5000
	while Creator.reap_abandoned_imports() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_finish()

func _revision(wizard: Control) -> void:
	var doc: RefCounted = wizard.document()
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
	var compiled: Dictionary = doc.compile()
	check("explicit trainer configuration compiles independently of declarations",compiled.ok)
	if not compiled.ok:
		printerr(compiled.diagnostics)
		return
	var context: Dictionary = doc.source_observations()
	wizard.call("_on_publish_pressed")
	check("versioned definition publishes through existing store",doc.published_revision == 1)
	var store: RefCounted = wizard.get("_store")
	var saved: Dictionary = store.load_aircraft(doc.aircraft_uuid())
	check("saved revision retains versioned context",saved.ok and saved.value.definition.format == Definition.SOURCE_FORMAT and saved.value.definition.source_observations == context)
	if not saved.ok:
		return
	wizard.call("_begin_open","aircraft",saved.value)
	await _wait(wizard)
	check("saved aircraft reopens with exact review context",wizard.document().published_revision == 1 and wizard.document().source_observations() == context)
	var forged: Dictionary = saved.value.duplicate(true)
	forged.definition.source_observations.parameters_sha256 = "0".repeat(64)
	var before: Dictionary = wizard.document().snapshot()
	wizard.call("_begin_open","aircraft",forged)
	await _wait(wizard)
	check("revision definition cannot disagree with restored source context",wizard.document().snapshot() == before)
	check("failed source comparison restores import controls",not (wizard.get("_choose_button") as Button).disabled)

func _finish() -> void:
	_remove_test_tree(ProjectSettings.globalize_path(_directory))
	print("ClearView UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _remove_test_tree(path: String) -> void:
	# Only this test's freshly allocated user:// directory is removed.
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child: String in directory.get_directories():
		_remove_test_tree(path.path_join(child))
	for child: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)
