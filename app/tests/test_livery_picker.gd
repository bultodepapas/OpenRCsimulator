extends SceneTree
const Picker = preload("res://ui/livery_picker.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const Driver = preload("res://tests/ui_driver.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft_models/f4u-corsair-250.json"))
	var choices: Array = []
	for record: Dictionary in manifest.liveries:
		var path := "res://assets/ui/liveries/f4u-corsair-250/%s-%s.png" % [record.id, record.sha256]
		check(record.id + " thumbnail is available", ResourceLoader.exists(path))
		choices.append({id = record.id, label = record.label, thumbnail = path})
	var original_size := root.size
	var original_scale: float = UiTheme.text_scale
	var original_locale := TranslationServer.get_locale()
	var driver := Driver.new(self)
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for viewport_size in [Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160), Vector2i(1280,720)]:
			for scale in [1.0, 2.0]:
				root.size = viewport_size
				UiTheme.text_scale = scale
				var picker := Picker.new(choices, "carbon", "F4U Corsair")
				var selected: Array[String] = []
				var closed: Array[bool] = []
				picker.selected.connect(func(id: String) -> void: selected.append(id))
				picker.close_requested.connect(func() -> void: closed.append(true))
				root.add_child(picker)
				for frame in 5: await process_frame
				var context := "%s %s %.0f%%" % [locale, viewport_size, scale * 100]
				check(context + " all thirteen named choices", picker.buttons.size() == 13)
				check(context + " selected paint receives focus", picker.buttons[12].has_focus())
				check(context + " selected paint is marked", picker.buttons[12].text.contains(tr("Selected")))
				check(context + " dialog fits viewport", Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(picker.panel.get_global_rect()))
				check(context + " cards do not overflow horizontally", picker.grid.size.x <= picker.scroll.size.x + 0.5)
				var labels_fit := true
				for button: Button in picker.buttons:
					var content: VBoxContainer = button.get_child(0)
					labels_fit = labels_fit and button.get_global_rect().grow(1).encloses(content.get_child(1).get_global_rect())
				check(context + " names fit their cards without clipping", labels_fit)
				if viewport_size == Vector2i(1920,1080) and scale == 1.0:
					check(context + " all paints visible without scrolling", picker.grid.size.y <= picker.scroll.size.y + 1)
				check(context + " selection scrolled into view: %s within %s" % [picker.buttons[12].get_global_rect(), picker.scroll.get_global_rect()], picker.scroll.get_global_rect().grow(1).encloses(picker.buttons[12].get_global_rect()))
				check(context + " Back stays visible", Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(picker.cancel_button.get_global_rect()))
				await driver.tap(KEY_UP)
				check(context + " arrow navigates grid", picker.buttons[12 - picker.grid.columns].has_focus())
				check(context + " navigating never selects", selected.is_empty())
				await driver.tap(KEY_ESCAPE)
				check(context + " Escape cancels without selecting", closed.size() == 1 and selected.is_empty())
				picker.buttons[0].grab_focus()
				await driver.settle()
				await driver.tap(KEY_ENTER)
				picker.buttons[6].pressed.emit()
				check(context + " direct activation emits exactly one choice", selected == ["midnight"])
				picker.free()
				await process_frame
	for record: Dictionary in manifest.liveries:
		check(record.id + " gallery never loaded its GLB", not ResourceLoader.has_cached(record.path))
	var cache := {}
	var progressive := Picker.new(choices, "", "Fixture", cache)
	check("construction does not synchronously load thumbnails", cache.is_empty())
	root.add_child(progressive)
	for frame in 18:
		var before := cache.size()
		await process_frame
		check("at most one thumbnail loads per frame", cache.size() <= before + 1)
	check("thumbnail cache is bounded to the thirteen choices", cache.size() == 13)
	progressive.free()
	var reopened := Picker.new(choices, "", "Fixture", cache)
	root.add_child(reopened)
	check("reopening reuses textures without a load queue", reopened._pending.is_empty() and reopened._images[0].texture == cache[choices[0].thumbnail])
	reopened.free()
	var cancel_cache := {}
	var cancelled := Picker.new(choices, "", "Fixture", cancel_cache)
	root.add_child(cancelled)
	cancelled.free()
	await driver.settle()
	check("closing cancels pending thumbnail work", cancel_cache.is_empty())
	var fallback := Picker.new([{id = "named", label = "Named paint"}], "", "Fixture")
	check("missing preview retains an accessible named choice", fallback._images[0].texture == null and fallback.buttons[0].text.contains("Named paint"))
	fallback.free()
	root.size = original_size
	UiTheme.text_scale = original_scale
	TranslationServer.set_locale(original_locale)
	print("Livery picker: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
