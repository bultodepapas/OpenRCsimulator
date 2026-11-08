## UI3-05: focus follows the camera controls only when their presentation is replaced.
extends SceneTree

const App := preload("res://app_root.gd")
const Preferences := preload("res://app_state/preferences.gd")
const Screen := preload("res://ui/screen.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const PREFS := "user://test_workshop_preview_focus.cfg"

var checks := 0
var failures := 0
var ui: RefCounted


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run.call_deferred()


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("ok ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func settle() -> void:
	for _i in 10:
		await process_frame


func resize(width: int, height: int) -> void:
	root.size = Vector2i(width, height)
	await settle()


func _run() -> void:
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	root.size = Vector2i(1920, 1080)
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	check("isolated preferences saved", Preferences.save_to(PREFS, prefs) == OK)
	var app := App.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	root.add_child(app)
	await settle()
	var observed: Array = [{"id": 15, "name": "Synthetic Xbox", "guid": "synthetic-xbox", "vendor_id": 1118, "product_id": 765, "known": true}]
	app.controllers.enumerate_devices = func() -> Array: return observed
	app.controllers.refresh()
	var selected_device: int = app.controllers.registry.selected_device_id("ui")
	check("synthetic pad selected for menus", selected_device == 15)
	app.open_workshop(app.home.workshop_button)
	await settle()
	var workshop: CanvasLayer = app.screens.top()
	var preview: Control = workshop.get("_preview")
	var front: Button = preview.find_child("ViewFront", true, false)
	var camera: Button = preview.find_child("CameraMenuButton", true, false)
	var menu: PopupMenu = preview.find_child("CameraControlsMenu", true, false)
	var view: Button = workshop.find_child("CompactPreview", true, false)
	check("1080p Workshop shows inline camera actions", app.screens.is_top("workshop")
		and front.is_visible_in_tree() and not camera.is_visible_in_tree())
	front.grab_focus()
	await resize(1900, 1080)
	check("1080p width reflow preserves existing camera focus", front.has_focus())
	await resize(1000, 1080)
	check("compact Workshop shows Preview", view.is_visible_in_tree())
	view.grab_focus()
	await ui.tap(KEY_ENTER)
	await settle()
	check("Preview opens with inline Front", front.is_visible_in_tree() and not camera.is_visible_in_tree())
	front.grab_focus()
	await resize(1000, 390)
	check("390 px collapse transfers Front focus to Camera", camera.is_visible_in_tree() and camera.has_focus(),
		"focus=%s preview=%s" % [ui.focus_name(), preview.size])
	await ui.tap(KEY_ENTER)
	check("focused Camera opens its menu via keyboard", menu.visible)
	await ui.tap(KEY_ESCAPE)
	await settle()
	check("Escape returns from camera menu", not menu.visible and camera.has_focus())
	await ui.joy_button(JOY_BUTTON_A)
	check("selected synthetic menu pad activates Camera", menu.visible)
	await resize(1000, 400)
	check("400 px expansion closes popup and transfers Camera focus to Front", not menu.visible and front.is_visible_in_tree() and front.has_focus(),
		"focus=%s preview=%s" % [ui.focus_name(), preview.size])
	await ui.tap(KEY_TAB)
	check("Tab continues from restored inline action", root.gui_get_focus_owner() != null
		and root.gui_get_focus_owner() != front and workshop.is_ancestor_of(root.gui_get_focus_owner()), ui.focus_name())
	for inline: Button in preview.get("_inline_camera_buttons"):
		inline.grab_focus()
		await resize(1000, 390)
		check("collapse hands off %s" % inline.name, camera.has_focus())
		await resize(1000, 400)
		check("expansion restores an inline action after %s" % inline.name, front.has_focus())
	view.grab_focus()
	await resize(1000, 390)
	check("collapse preserves unrelated visible focus", view.has_focus())
	await resize(1000, 400)
	check("expansion preserves unrelated visible focus", view.has_focus())
	for _i in 3:
		preview.call("_apply_preview_layout")
	await settle()
	check("repeated layout does not grab focus", view.has_focus())
	view.release_focus()
	await resize(1000, 390)
	check("reflow does not invent focus", root.gui_get_focus_owner() == null)
	var cover := CanvasLayer.new()
	var cover_screen := Screen.new()
	cover_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_child(cover_screen)
	var other := Button.new()
	other.text = "Other screen"
	cover_screen.add_child(other)
	check("cover enters the existing screen stack", app.screens.push("focus_test_cover", cover))
	await settle()
	other.grab_focus()
	await resize(1000, 400)
	check("suspended preview cannot steal another screen's focus", other.has_focus()
		and app.screens.is_top("focus_test_cover"))
	app.screens.pop()
	await settle()
	check("screen stack and selected menu device remain intact", app.screens.is_top("workshop")
		and app.controllers.registry.selected_device_id("ui") == selected_device)
	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".legacy_rc"]:
		var path := ProjectSettings.globalize_path(PREFS + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Workshop preview focus: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
