extends SceneTree
## AC-10: the Aircraft Creator is translated in every interface language.
## Crawls every step of the wizard in Spanish for visible text that has no translation, and checks
## that step titles, statuses, field labels and import diagnostics resolve in all catalogs.
const Creator := preload("res://ui/aircraft_creator.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const R := preload("res://workshop/creator/result.gd")
const Store := preload("res://workshop/creator/store.gd")
const CreatorTrial := preload("res://workshop/creator/trial.gd")
const PartsPanel := preload("res://ui/aircraft_creator_parts.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const Fixtures := preload("res://tests/creator_fixtures.gd")

const LOCALES: PackedStringArray = ["es", "pt_BR", "de", "fr", "it", "ru", "ja", "zh_Hans"]
## Text that is the same in every language: units, formats, axes, numbers and player data.
const _INVARIANT: PackedStringArray = ["m", "kg", "s", "deg", "mm", "cm", "in", "ft", "GLB", "CG",
	"+X", "-X", "+Y", "-Y", "+Z", "-Z", "−X", "−Y", "−Z"]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail := "") -> void:
	if not passed:
		failures += 1
		printerr("FAIL: " + label + " " + detail)


func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, 500, 0], [-40, -700, 0], [40, -700, 0]],
		[[-750, 100, 0], [750, 100, 0], [0, 200, 0]],
		[[0, -700, 0], [0, -620, 0], [0, -700, 120]],
	]
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * triangles.size())
	bytes.encode_u32(80, triangles.size())
	var offset := 84
	for triangle: Array in triangles:
		offset += 12
		for vertex: Array in triangle:
			for component: int in 3:
				bytes.encode_float(offset, float(vertex[component]))
				offset += 4
		offset += 2
	return bytes


func _run() -> void:
	_catalogs()
	await _crawl()
	TranslationServer.set_locale("en")
	print("Creator language: %d failures" % failures)
	quit(1 if failures else 0)


## Messages the wizard shows from the document and the readers resolve in every catalog.
func _catalogs() -> void:
	var messages := PackedStringArray()
	for step: String in Authoring.STEPS:
		messages.append(str(Authoring.STEP_TITLES[step]))
	for entry: Dictionary in Authoring.FIELDS:
		messages.append(str(entry.label))
	messages.append_array([Authoring.STATUS_NOT_STARTED, Authoring.STATUS_IN_PROGRESS, Authoring.STATUS_NEEDS_ATTENTION,
		Authoring.STATUS_COMPLETE, "Create aircraft…", "Leave the Aircraft Creator?", "Estimated value", "Upward",
		"Choose an airborne or hand-launch trial start.",
		"This aircraft has changes that are not saved as a draft. Leave without saving them?", "Leave without saving",
		CreatorTrial.PRESENTATION_REFUSAL, CreatorTrial.CLIMB_OUT_REFUSAL,
		PartsPanel.NOT_BOUND, PartsPanel.STL_NOTE, PartsPanel.SHOW_MOVEMENT, PartsPanel.STOP_MOVEMENT,
		"Open…", "Save draft", "Save aircraft", "All changes saved", "View only", "Saved as version %s",
		"Leave with unsaved changes?", "Save draft and leave", "Recover unsaved work?", "Open the recovered draft", "Discard it",
		"Solid colour", "Paint colour", "Moving parts", "Show archived", "Drafts", "Saved aircraft", "Archive", "Restore"])
	# Every message the library can show (AC-13).
	var constants: Dictionary = (Store as Script).get_script_constant_map()
	for constant: String in constants:
		if constant.begins_with("M_") and typeof(constants[constant]) == TYPE_STRING:
			messages.append(str(constants[constant]))
	# Real refusals of moving-part bindings and paint (AC-15, AC-17).
	var model: Dictionary = Importer.inspect_bytes(Fixtures.airplane_glb(), "plane.glb")
	check("parts fixture admitted", model.ok)
	if model.ok:
		var twice: Dictionary = Fixtures.airplane_bindings()
		twice.controls.rudder[0].node = Fixtures.PROPELLER_NODE
		var missing_part: Dictionary = Fixtures.airplane_bindings()
		missing_part.controls.rudder[0].node = 99
		var whole: Dictionary = Fixtures.airplane_bindings()
		whole.controls.rudder[0].node = 0
		var bad_axis: Dictionary = Fixtures.airplane_bindings()
		bad_axis.controls.rudder[0].axis = "w"
		for refused: Dictionary in [VisualBuilder.validate_bindings(model.value, twice), VisualBuilder.validate_bindings(model.value, missing_part),
				VisualBuilder.validate_bindings(model.value, whole), VisualBuilder.validate_bindings(model.value, bad_axis),
				VisualBuilder.validate_bindings(model.value, {"format": "other"}),
				VisualBuilder.validate_appearance({"mode": "solid", "color": "red"}), VisualBuilder.validate_appearance({"mode": "stripes"})]:
			check("a hostile binding or paint is refused", not refused.ok)
			for entry: Variant in refused.get("diagnostics", []):
				messages.append(str(entry.message))
		var accepted: Dictionary = VisualBuilder.validate_bindings(model.value, Fixtures.airplane_bindings())
		for entry: Variant in accepted.get("diagnostics", []):
			messages.append(str(entry.message))
	# Real refusals from the readers, as the player would meet them.
	for hostile: Array in [[PackedByteArray([1, 2, 3, 4, 5]), "broken.stl"], ["v 0 0 0\n".to_utf8_buffer(), "model.obj"],
			[_plane_stl(), "photo.png"], [PackedByteArray([0x67, 0x6C, 0x54, 0x46, 2, 0, 0, 0]), "short.glb"]]:
		var refused: Dictionary = Importer.inspect_bytes(hostile[0], hostile[1])
		check("fixture %s is refused" % hostile[1], not refused.ok)
		for entry: Variant in refused.get("diagnostics", []):
			messages.append(str(entry.message))
	var document := Authoring.new()
	for entry: Variant in document.issues():
		messages.append(str(entry.message))
	for locale: String in LOCALES:
		TranslationServer.set_locale(locale)
		var missing := PackedStringArray()
		for message: String in messages:
			if not _translated(locale, message):
				missing.append(message)
		check("%s: Creator messages are translated" % locale, missing.is_empty(), str(missing))


## Every step of the wizard in Spanish, empty and filled: no visible English left behind.
func _crawl() -> void:
	TranslationServer.set_locale("es")
	root.size = Vector2i(1920, 1080)
	var wizard := Creator.new() as Control
	wizard.theme = UiTheme.build()
	# A temporary library: this test never opens the player's own.
	var store_root := "user://creator_language_store_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	wizard.set("store_root", store_root)
	root.add_child(wizard)
	for _frame: int in 3:
		await process_frame
	var untranslated := {}
	for step: String in Authoring.STEPS:
		wizard.go_to_step(step)
		for _frame: int in 3:
			await process_frame
		_collect(wizard, untranslated)
	var admitted: Dictionary = Importer.inspect_bytes(_plane_stl(), "plane.stl")
	check("fixture admitted", admitted.ok)
	if admitted.ok:
		var document: RefCounted = wizard.document()
		document.set_source(admitted.value)
		document.set_axis("nose_axis", "+y")
		document.set_axis("up_axis", "+z")
		document.set_units("mm")
		document.set_datum([0.0, 200.0, 0.0])
		document.apply_values(document.starting_values(), true)
		document.propose_inventory()
		document.set_raw("wing/span", "abc")
		for step: String in Authoring.STEPS:
			wizard.go_to_step(step)
			for _frame: int in 3:
				await process_frame
			_collect(wizard, untranslated)
	check("the wizard has no untranslated Spanish text", untranslated.is_empty(), str(untranslated.keys()))
	wizard.free()
	Creator.reap_abandoned_imports()
	for _frame: int in 2:
		await process_frame
	_remove_tree(ProjectSettings.globalize_path(store_root))
	check("the temporary library is removed", not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(store_root)))


func _remove_tree(path: String) -> void:
	for directory: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(directory))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _collect(wizard: Control, untranslated: Dictionary) -> void:
	for node: Node in wizard.find_children("*", "", true, false):
		if not (node is Label or node is Button) or not (node as Control).is_visible_in_tree() or not node.can_auto_translate():
			continue
		var text: String = node.text
		if text.is_empty() or text in _INVARIANT or not _has_letters(text):
			continue
		if node.atr(text) == text and not _translated("es", text):
			untranslated[text] = true


## True when the catalog carries the message, even if its translation equals the English text
## ("Import" in German, "Zoom +" in Spanish).
func _translated(locale: String, message: String) -> bool:
	var catalog: Translation = TranslationServer.get_translation_object(locale)
	return catalog != null and not str(catalog.get_message(message)).is_empty()


func _has_letters(text: String) -> bool:
	for index: int in text.length():
		var code := text.unicode_at(index)
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			return true
	return false
