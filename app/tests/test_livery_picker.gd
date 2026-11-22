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
				var shared_theme := UiTheme.build()
				var picker := Picker.new(choices, "carbon", "F4U Corsair", {}, shared_theme)
				var selected: Array[String] = []
				var closed: Array[bool] = []
				picker.selected.connect(func(id: String) -> void: selected.append(id))
				picker.close_requested.connect(func() -> void: closed.append(true))
				root.add_child(picker)
				for frame in 5: await process_frame
				var context := "%s %s %.0f%%" % [locale, viewport_size, scale * 100]
				check(context + " gallery reuses the owner's current theme", picker._screen.theme == shared_theme)
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
	for texture: Texture2D in cache.values():
		check("each thumbnail decodes at its authored resolution", texture != null and texture.get_size() == Vector2(288, 162))
	progressive.free()
	var reopened := Picker.new(choices, "", "Fixture", cache)
	root.add_child(reopened)
	check("reopening reuses textures without a load queue", reopened._pending.is_empty() and reopened._images[0].texture == cache[choices[0].thumbnail])
	reopened.free()
	var cancel_cache := {}
	var cancelled := Picker.new(choices, "", "Fixture", cancel_cache)
	root.add_child(cancelled)
	root.remove_child(cancelled) # ScreenStack removes synchronously, then frees at the frame boundary.
	cancelled.queue_free()
	await driver.settle()
	check("closing cancels pending thumbnail work", cancel_cache.is_empty())
	root.size = Vector2i(1920,1080)
	UiTheme.text_scale = 1.0
	var fallback := Picker.new([{id = "", label = "Original"}, {id = "named", label = "Named paint"}], "named", "Fixture", {}, null, true)
	root.add_child(fallback)
	for frame in 6: await process_frame
	check("text-only skins allocate no image or caption controls", fallback._images.is_empty() and fallback._labels.is_empty()
		and fallback._pending.is_empty() and fallback.buttons[0].get_child_count() == 0)
	check("named list uses a compact panel %s" % fallback.panel.size, fallback.grid.columns == 1 and fallback.panel.size.y < root.size.y * 0.75)
	check("two named skins fit without scrolling (grid %s, scroll %s)" % [fallback.grid.size, fallback.scroll.size],
		not fallback.scroll.get_v_scroll_bar().visible)
	check("current named skin is marked and focused", fallback.buttons[1].has_focus() and fallback.buttons[1].text.contains(tr("Selected")))
	await driver.tap(KEY_UP)
	check("Up reaches the preceding named skin", fallback.buttons[0].has_focus())
	fallback.free()
	var mixed := Picker.new([{id = "named", label = "Named paint"}, choices[1]], "", "Fixture", cache)
	root.add_child(mixed)
	check("mixed gallery binds thumbnails to their original choice", mixed._images.size() == 1
		and mixed._images[1].texture == cache[choices[1].thumbnail] and mixed.buttons[0].text.contains("Named paint"))
	mixed.free()
	var long_list: Array = []
	for index in 15:
		long_list.append({id = str(index), label = "Long personal paint scheme %d" % index})
	TranslationServer.set_locale("de")
	UiTheme.text_scale = 2.0
	var compact_list := Picker.new(long_list, "14", "Fixture", {}, UiTheme.build(), true)
	root.add_child(compact_list)
	root.size = Vector2i(1280, 720)
	for frame in 6: await process_frame
	var frame_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	check("enlarged list scrolls to the active skin (%s in %s)" % [compact_list.buttons.back().get_global_rect(), compact_list.scroll.get_global_rect()], compact_list.buttons.back().has_focus()
		and compact_list.scroll.get_v_scroll_bar().visible and compact_list.scroll.get_global_rect().grow(1).encloses(compact_list.buttons.back().get_global_rect()))
	check("enlarged dialog and all footer actions fit at 720p", frame_rect.encloses(compact_list.panel.get_global_rect())
		and frame_rect.encloses(compact_list.cancel_button.get_global_rect())
		and compact_list._skin_actions.all(func(button: Button) -> bool: return frame_rect.encloses(button.get_global_rect())))
	await driver.tap(KEY_TAB)
	check("keyboard reaches skin tools after the last named skin", compact_list._skin_actions[0].has_focus())
	compact_list.free()
	# Live theme changes replace the owner's theme; existing explicit card fonts
	# must follow the replacement. Crystal decoration must not mutate shared styles.
	root.size = Vector2i(1920,1080)
	UiTheme.text_scale = 1.0
	var original_compact: bool = UiTheme.compact_layout
	var original_opaque: bool = UiTheme.opaque_panels
	UiTheme.compact_layout = false
	UiTheme.opaque_panels = true
	var owner_theme := UiTheme.build()
	var owner_style: StyleBoxFlat = owner_theme.get_stylebox("normal", "PrimaryButton")
	var owner_style_color := owner_style.bg_color
	var live := Picker.new(choices, "carbon", "Fixture", cache, owner_theme)
	root.add_child(live)
	live._screen.open()
	await driver.settle()
	check("decorating shared theme leaves owner styles intact", owner_style.draw_center and owner_style.bg_color == owner_style_color)
	for compact in [false, true]:
		for scale in [2.0, 1.0]:
			UiTheme.compact_layout = compact
			UiTheme.text_scale = scale
			live._screen.theme = UiTheme.build()
			await driver.settle()
			var expected_size: int = live._screen.theme.get_font_size("font_size", "Button")
			var fonts_match := true
			var names_fit := true
			for index in live.buttons.size():
				fonts_match = fonts_match and live.buttons[index].get_theme_font_size("font_size") == expected_size and live._labels[index].get_theme_font_size("font_size") == expected_size
				names_fit = names_fit and live.buttons[index].get_global_rect().grow(1).encloses(live._labels[index].get_global_rect())
			check("live compact=%s scale=%s updates both card fonts" % [compact, scale], fonts_match)
			check("live compact=%s scale=%s keeps names within cards" % [compact, scale], names_fit)
			check("live text scale refreshes keyboard column targets", live.buttons[0].focus_neighbor_bottom == live.buttons[0].get_path_to(live.buttons[live.grid.columns]))
	live.free()
	UiTheme.compact_layout = original_compact
	UiTheme.opaque_panels = original_opaque
	root.size = original_size
	UiTheme.text_scale = original_scale
	TranslationServer.set_locale(original_locale)
	print("Livery picker: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
