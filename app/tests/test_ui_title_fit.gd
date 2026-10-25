extends SceneTree
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(description: String, condition: bool) -> void:
	print(("ok   " if condition else "FAIL ") + description)
	if not condition: failures += 1

func settle() -> void:
	for frame in 5: await process_frame

func run() -> void:
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	var column := VBoxContainer.new()
	column.size = Vector2(400, 100)
	root.add_child(column)
	var title := Widgets.label("Aircraft Workshop", "CardTitle")
	column.add_child(title)
	for factor: float in [1.0, 2.0]:
		UiTheme.text_scale = factor
		column.theme = UiTheme.build()
		Widgets.fit_title(title, UiTheme._font_size(UiTheme.SIZE.body))
		title.text = "Short"
		await settle()
		check("short title uses preferred size at scale %.1f" % factor, title.get_rendered_font_size() == roundi(28 * factor))
		title.text = "Ávión experimental de entrenamiento con nombre muy largo"
		await settle()
		check("long title fits to the readable body minimum at scale %.1f" % factor, title.get_rendered_font_size() == roundi(26 * factor))
		check("overflow stays inside allocated column", title.size.x <= column.size.x and title.clip_text)
		var stable_size := title.size
		var stable_font := title.get_rendered_font_size()
		await settle()
		check("layout converges without resize feedback", title.size == stable_size and title.get_rendered_font_size() == stable_font)
		# A width that fits at 26 but not 28 must actually exercise the native fitter.
		title.text = "Aircraft Workshop"
		column.size.x = ceilf(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(27 * factor)).x)
		await settle()
		check("native fitting chooses an intermediate size", title.get_rendered_font_size() < roundi(28 * factor) and title.get_rendered_font_size() >= roundi(26 * factor))
		column.size.x = 400
	UiTheme.text_scale = 1.0
	column.free()
	print("UI title fit: %d failures" % failures)
	quit(1 if failures else 0)
