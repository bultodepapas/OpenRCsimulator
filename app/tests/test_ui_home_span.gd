# UI-35c (UI-30 SP-5), UI-35b (UI-30 AL-3) and UI-34b (UI-30 HN-3): on super-ultrawide canvases the menus keep a
# centred 2560-wide span, opaque panels reach the sidebar fade, and FLY names what it launches off the Flight page.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_home_span.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const PREFS := "user://test_ui_home_span.cfg"

var _failures := 0
var ui: RefCounted


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _run()
	print("UI home span: %d failed" % _failures)
	quit(1 if _failures else 0)


func _canvas(app: Node, pixels: Vector2i) -> void:
	root.size = pixels # after startup: the shell's resize handler applies the canvas policy
	for frame in 6: await process_frame


func _run() -> void:
	TranslationServer.set_locale("en")
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	var home: Control = app.home
	var rail: Control = home.get_node("HomeRail")
	var header: Control = home.get_node("HeaderActions")

	# --- SP-5: 21:9 keeps the edge layout; 32:9 centres a 2560-wide span.
	await _canvas(app, Vector2i(3440, 1440))
	_check("21:9 keeps the rail at the left inset", home.get_viewport_rect().size.x > 2500.0 and rail.get_global_rect().position.x < 100.0,
		"%s %s" % [home.get_viewport_rect().size, rail.get_global_rect()])
	await _canvas(app, Vector2i(5120, 1440))
	var width := home.get_viewport_rect().size.x
	var margin := (width - 2560.0) * 0.5
	_check("32:9 moves the rail into the centred span", width > 3800.0 and rail.get_global_rect().position.x >= margin,
		"width=%.0f rail=%s" % [width, rail.get_global_rect()])
	_check("32:9 keeps the header actions inside the span", header.get_global_rect().end.x <= width - margin + 1.0,
		"header=%s" % header.get_global_rect())

	# --- HN-3: off the Flight page, the pinned action says which aircraft it flies.
	await _canvas(app, Vector2i(1920, 1080))
	var caption: Label = home.find_child("FlyCaption", true, false)
	_check("Flight page needs no caption above FLY", caption != null and not caption.visible)
	home._select_page(1)
	await ui.settle()
	_check("Aircraft page names the aircraft FLY launches", caption != null and caption.visible
		and caption.text.contains(Catalog.short_name(home.aircraft_id)), caption.text if caption != null else "no caption")
	home._select_page(2)
	await ui.settle()
	_check("Practice page names the aircraft FLY launches", caption != null and caption.visible)
	home._select_page(0)
	await ui.settle()

	# --- SP-5 in Pause: the sidebar follows the same span.
	await _canvas(app, Vector2i(5120, 1440))
	app.start_flight()
	await create_timer(0.3).timeout
	app.open_pause()
	await ui.settle()
	var panel: Control = app.pause_menu.get("_panel")
	_check("32:9 Pause sidebar sits inside the centred span", panel != null and panel.get_global_rect().position.x >= margin - 1.0,
		"panel=%s" % (panel.get_global_rect() if panel != null else Rect2()))
	app.queue_free()
	await ui.settle()

	# --- AL-3: opaque panels reach the sidebar fade that Pause and Natural Random draw.
	UiTheme.opaque_panels = true
	var fade: TextureRect = Widgets.sidebar_fade(100)
	var start: Color = (fade.texture as GradientTexture2D).gradient.get_color(0)
	_check("opaque panels make the sidebar fade start opaque", is_equal_approx(start.a, 1.0), str(start))
	fade.free()
	UiTheme.opaque_panels = false
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
