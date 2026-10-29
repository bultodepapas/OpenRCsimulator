extends SceneTree
const SkinTools = preload("res://ui/skin_tools.gd")
const Picker = preload("res://ui/livery_picker.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Languages = preload("res://i18n/languages.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _run() -> void:
	var original_size := root.size
	var original_locale := TranslationServer.get_locale()
	var original_scale := UiTheme.text_scale
	for locale in Languages.NAMES:
		TranslationServer.set_locale(locale)
		for scale in [1.0, 2.0]:
			root.size = Vector2i(1920, 1080)
			UiTheme.text_scale = scale
			var dialog := SkinTools.new("skywalker-x8", UiTheme.build())
			root.add_child(dialog)
			for frame in 4: await process_frame
			var labels := dialog._scroll.find_children("*", "Label", true, false)
			check("MoonRunner X99 skin heading in %s" % locale, labels.any(func(label): return label.atr(label.text) == "MoonRunner X99 · PNG → .orskin"))
			var frame_rect := Rect2(Vector2.ZERO, Vector2(root.size))
			check("template action fits 1080p %s %s" % [locale, scale], frame_rect.encloses(dialog._first.get_global_rect()))
			dialog._scroll.ensure_control_visible(dialog._status)
			await process_frame
			check("status is reachable at 1080p", frame_rect.encloses(dialog._status.get_global_rect()))
			dialog._scroll.ensure_control_visible(dialog._first)
			await process_frame
			dialog.choose_skin()
			check("imports only .orskin", dialog._picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE and dialog._picker.filters[0].begins_with("*.orskin"))
			dialog._picker.hide()
			dialog.save_template()
			check("template saves ZIP", dialog._picker.file_mode == FileDialog.FILE_MODE_SAVE_FILE and dialog._picker.current_file == "skywalker-x8.zip")
			dialog._picker.hide()
			var imported_ids: Array[String] = []
			dialog.imported.connect(func(id: String) -> void: imported_ids.append(id))
			dialog._saving = false
			dialog._file_selected("user://missing.orskin")
			check("invalid skin stays in dialog with actionable error", imported_ids.is_empty() and not dialog._status.text.is_empty())
			dialog.free()
			await process_frame
	var guide_path := "user://skin-tool-guide-test.html"
	for locale in Languages.NAMES:
		check("guide written for " + locale, SkinTools._write_guide(guide_path, locale))
		var source := FileAccess.get_file_as_string(guide_path)
		check("guide follows app locale " + locale, source.contains('data-default-locale="' + locale + '"') and source.contains('id="' + locale + '"'))
	check("unknown guide locale falls back to English", SkinTools._write_guide(guide_path, "xx") and FileAccess.get_file_as_string(guide_path).contains('data-default-locale="en"'))
	DirAccess.remove_absolute(guide_path)
	var output := "user://skin-tool-copy-test.zip"
	check("bundled template can be saved", SkinTools._copy_resource(SkinTools.CustomSkin.kit_path("skywalker-x8"), output))
	check("template copy is byte exact", FileAccess.get_sha256(output) == FileAccess.get_sha256(SkinTools.CustomSkin.kit_path("skywalker-x8")))
	DirAccess.remove_absolute(output)
	for aircraft: String in SkinTools.Catalog.ids():
		var dialog := SkinTools.new(aircraft, UiTheme.build())
		root.add_child(dialog)
		await process_frame
		dialog.save_template()
		check("correct template filename for " + aircraft, dialog._picker.current_file == SkinTools.CustomSkin.kit_path(aircraft).get_file())
		dialog._picker.hide()
		dialog._file_selected(output)
		check("selected model template saves exactly " + aircraft, FileAccess.get_sha256(output) == FileAccess.get_sha256(SkinTools.CustomSkin.kit_path(aircraft)))
		DirAccess.remove_absolute(output)
		check("selected model is included in guide " + aircraft, SkinTools._write_guide(guide_path, "es", aircraft) and FileAccess.get_file_as_string(guide_path).contains('data-aircraft-id="' + SkinTools.CustomSkin.family(aircraft) + '"'))
		DirAccess.remove_absolute(guide_path)
		dialog.free()
		await process_frame
	var choices := [{id = "abisal", label = "Abisal"}, {id = "bolido", label = "Bolido"}]
	var picker := Picker.new(choices, "", "X8", {}, UiTheme.build(), true)
	root.add_child(picker)
	for frame in 4: await process_frame
	check("supported gallery offers two skin actions", picker._skin_actions.size() == 2)
	check("keyboard reaches skin actions", picker.buttons.back().focus_next == picker.buttons.back().get_path_to(picker._skin_actions[0]))
	picker.free()
	var stock := Picker.new(choices)
	check("other aircraft keep stock gallery", stock._skin_actions.is_empty())
	stock.free()
	root.size = original_size
	UiTheme.text_scale = original_scale
	TranslationServer.set_locale(original_locale)
	print("Skin tools: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
