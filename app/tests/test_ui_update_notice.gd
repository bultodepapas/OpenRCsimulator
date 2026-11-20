# UI-16: the update notice on Home with real key events: the card and its texts in both languages, contrast,
# Download and Hide; then the interactive route end to end (app_root, the checker and a local fake of the API):
# the notice appears over Home without moving the focus, survives Home → Fly → End flight, Hide remembers the
# version, [updates] check=false asks nothing, and a development run checks nothing by default.
# Run: godot --headless --path . --script res://tests/test_ui_update_notice.gd
extends SceneTree

const Home := preload("res://ui/home.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UpdateCheck := preload("res://app_state/update_check.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const FakeReleases := preload("res://tests/fake_releases.gd")

const FIXTURE := "res://tests/fixtures/github_releases.json"
const PREFS := "user://test_ui_update_notice_settings.cfg"
const STATE := "user://test_ui_update_notice_cache.cfg"
const RC8 := { tag = "v0.1.0-rc8", version = "0.1.0-rc8", url = UpdateCheck.RELEASES_PAGE + "/tag/v0.1.0-rc8", published = "" }

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
	_run()


func _run() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	await ui.settle()
	await _card()
	await _route()
	for path in [PREFS, PREFS + ".bad", STATE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("all UI update notice checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


## The card on a standalone Home.
func _card() -> void:
	TranslationServer.set_locale("en")
	var home: Control = Home.new()
	root.add_child(home)
	await ui.settle()
	_check("no card until a release is known", home.update_notice == null and home.find_child("UpdateNotice", true, false) == null)
	home.show_update(RC8)
	await ui.settle()
	var notice: PanelContainer = home.update_notice
	_check("card shown, in English", notice != null and notice.visible and notice.label.text == "Update available: 0.1.0-rc8", str(notice))
	_check("Fly keeps the focus", ui.focus_name() == "Fly", ui.focus_name())
	# The notice sits below the global actions and does not cover the flight rail.
	var right_edge := notice.position.x + notice.size.x
	_check("hangs from the top-right corner, outside the column: nothing on Home moved", notice.get_parent() == home
		and notice.anchor_left == 1.0 and notice.anchor_right == 1.0 and notice.grow_horizontal == Control.GROW_DIRECTION_BEGIN
		and notice.position.y >= home.settings_button.get_global_rect().end.y
		and absf(right_edge - (home.size.x - 24)) < 1.0
		and home.size.x - 24 - notice.size.x + 1280 - home.size.x > Home.SIDEBAR_WIDTH,
		"%s %s in %s" % [notice.position, notice.size, home.size])
	var bg: Color = notice.get_theme_stylebox("panel").bg_color
	var r := UiTheme.contrast(notice.label.get_theme_color("font_color"), bg)
	_check("contrast: notice text on its card %.2f:1 >= 4.5" % r, r >= 4.5)
	for b: Button in [notice.download_button, notice.later_button, notice.hide_button]:
		var rb := UiTheme.contrast(b.get_theme_color("font_color"), b.get_theme_stylebox("normal").bg_color)
		_check("contrast: %s %.2f:1 >= 4.5" % [b.name, rb], rb >= 4.5)
	TranslationServer.set_locale("es")
	await ui.settle()
	_check("Spanish", notice.label.text == "Nueva versión disponible: 0.1.0-rc8"
		and notice.download_button.atr(notice.download_button.text) == "Descargar" and notice.hide_button.atr(notice.hide_button.text) == "Omitir esta versión"
		and notice.later_button.atr(notice.later_button.text) == "Más tarde"
		and notice.download_button.tooltip_text == "Abre la página de la versión en tu navegador.", notice.label.text)
	TranslationServer.set_locale("en")
	await ui.settle()
	var opened: Array[String] = []
	var hidden: Array[String] = []
	home.update_download_requested.connect(func(url: String) -> void: opened.append(url))
	home.update_hidden.connect(func(tag: String) -> void: hidden.append(tag))
	notice.download_button.grab_focus()
	await ui.settle()
	await ui.tap(KEY_ENTER)
	_check("Enter on Download asks for the release page", opened == [RC8.url] and notice.visible, str(opened))
	await ui.tap(KEY_RIGHT)
	_check("Right reaches Later", ui.focus_name() == "Later", ui.focus_name())
	await ui.tap(KEY_RIGHT)
	_check("Right again reaches Skip this version", ui.focus_name() == "SkipVersion", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("Enter on Skip this version hides the card and names the version", hidden == ["v0.1.0-rc8"] and not notice.visible, str(hidden))
	_check("Skip gives the keyboard back to Fly", ui.focus_name() == "Fly", ui.focus_name())
	var later: Array[String] = []
	home.update_later.connect(func(tag: String) -> void: later.append(tag))
	home.show_update(RC8)
	await ui.settle()
	notice.later_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Later hides the card, names the version, skips nothing and returns the keyboard to Fly", later == ["v0.1.0-rc8"]
		and hidden == ["v0.1.0-rc8"] and not notice.visible and ui.focus_name() == "Fly", str(later))
	_check("no size line without a known package size", not notice.detail.visible)
	home.show_update({ tag = "v0.2.9", version = "0.2.9", url = RC8.url, published = "", size = 1501341464 })
	await ui.settle()
	_check("the download size is shown when the package is known", notice.detail.visible and notice.detail.text == "Download: 1.50 GB",
		notice.detail.text)
	var card_right := notice.position.x + notice.size.x
	_check("with the size line and three buttons the card still clears the sidebar at 1280x720",
		card_right - notice.size.x > Home.SIDEBAR_WIDTH and absf(card_right - (home.size.x - 24)) < 1.0, "%s %s" % [notice.position, notice.size])
	TranslationServer.set_locale("es")
	await ui.settle()
	_check("size line in Spanish", notice.detail.text == "Descarga: 1.50 GB", notice.detail.text)
	TranslationServer.set_locale("en")
	await ui.settle()
	home.show_update({ tag = "v0.1.0-rc9", version = "0.1.0-rc9", url = RC8.url, published = "" })
	await ui.settle()
	_check("a newer release shows the same card again", notice.visible and notice.label.text == "Update available: 0.1.0-rc9")
	home.queue_free()
	await ui.settle()


## The interactive route with the checker.
func _route() -> void:
	OS.set_environment("OPENRC_UPDATE_URL", "")
	TranslationServer.set_locale("en")
	for path in [PREFS, STATE]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A development run (no build_info.json, no OPENRC_UPDATE_URL) checks nothing: tests and developers never call GitHub.
	var plain: Node = _new_app()
	root.add_child(plain)
	await ui.settle()
	_check("development run: no checker, no request", plain.update_checker == null and plain.find_child("UpdateChecker", true, false) == null)
	await ui.close_app(plain)

	var server := FakeReleases.new()
	if not server.start(FileAccess.get_file_as_string(FIXTURE)):
		_check("fake releases server listens", false)
		return
	var opened: Array[String] = []
	var app: Node = _new_app()
	app.update_check_url = server.url()
	app.update_running_version = "0.1.0-rc6"
	app.open_url = func(url: String) -> Error:
		opened.append(url)
		return OK
	root.add_child(app)
	await ui.settle()
	_check("checker added under the interactive route", app.update_checker != null and app.home != null)
	var notice: Control = await _wait_notice(app, server)
	_check("the fake API's rc7 shows over Home", notice != null and notice.visible and notice.label.text == "Update available: 0.1.0-rc7"
		and server.requests.size() == 1, str(server.requests.size()))
	_check("Fly keeps the focus while the notice appears", ui.focus_name() == "Fly", ui.focus_name())
	if notice == null:
		server.stop()
		await ui.close_app(app)
		return
	notice.download_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Download opens the release page through app_root", opened == ["https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7"], str(opened))
	app.open_url = func(_url: String) -> Error: return ERR_CANT_OPEN
	notice.download_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("a browser that cannot open is reported on Home", app.home.note_label.visible
		and app.home.note_label.text == "Could not open the browser (error %d)." % ERR_CANT_OPEN, app.home.note_label.text)
	app.home.set_note("")
	# A fresh answer with nothing newer withdraws the card; a later announcement shows it again (app_root wiring).
	var info: Dictionary = { tag = "v0.1.0-rc7", version = "0.1.0-rc7", url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7", published = "" }
	app.update_checker.update_withdrawn.emit()
	await ui.settle()
	_check("withdrawn: card hidden and forgotten", not notice.visible and app._update_info.is_empty())
	app.update_checker.update_available.emit(info)
	await ui.settle()
	_check("announced again: card back", notice.visible and app._update_info == info)
	# Fly, then End flight: Home is rebuilt and the notice comes back.
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("Fly started the flight", app.flight != null and app.home == null)
	app.end_flight()
	await ui.settle()
	_check("after End flight the new Home shows the notice again", app.home != null and app.home.update_notice != null
		and app.home.update_notice.visible and server.requests.size() == 1)
	_check("Fly has the focus on the rebuilt Home", ui.focus_name() == "Fly", ui.focus_name())
	app.home.update_notice.hide_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Hide: card gone, version remembered in the cache", not app.home.update_notice.visible
		and UpdateCheck.load_state(STATE).hidden_tag == "v0.1.0-rc7")
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	app.end_flight()
	await ui.settle()
	_check("after hiding, the rebuilt Home has no card", app.home != null and app.home.update_notice == null)
	# DT-UPD-04a: Later puts a release off for this session only; one checker serves every rebuilt Home.
	var rc9 := { tag = "v0.1.0-rc9", version = "0.1.0-rc9", url = RC8.url, published = "", size = 39598648 }
	var checker: Node = app.update_checker
	checker.update_available.emit(rc9)
	await ui.settle()
	_check("a newer release shows with its size", app.home.update_notice != null and app.home.update_notice.visible
		and app.home.update_notice.detail.text == "Download: 39.6 MB")
	app.home.update_notice.later_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Later: card gone, nothing skipped in the cache", not app.home.update_notice.visible
		and UpdateCheck.load_state(STATE).hidden_tag == "v0.1.0-rc7" and app._update_info.is_empty())
	checker.update_available.emit(rc9)
	await ui.settle()
	_check("the same release is not shown again this session", not app.home.update_notice.visible)
	app.home.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	app.end_flight()
	await ui.settle()
	_check("after Later and a flight: no card, the same checker, no new request", app.home.update_notice == null
		and app.update_checker == checker and app.find_children("UpdateChecker", "", true, false).size() == 1
		and server.requests.size() == 1, str(app.find_children("UpdateChecker", "", true, false).size()))
	# Settings: the Updates rows reflect the checker and save at once.
	app.open_settings(app.home.settings_button)
	await ui.settle()
	var settings: Node = app.screens.get_screen("settings")
	var status_label: Label = settings.find_child("UpdateStatus", true, false)
	var auto_toggle: CheckButton = settings.find_child("CheckUpdates", true, false)
	var channel_picker: OptionButton = settings.find_child("UpdateChannel", true, false)
	var check_button: Button = settings.find_child("CheckUpdatesNow", true, false)
	_check("Settings shows the Updates rows: automatic on, preview (the rc build's channel), rc7 available with its size",
		status_label != null and auto_toggle.button_pressed and channel_picker.get_item_metadata(channel_picker.selected) == "preview"
		and status_label.text.begins_with("Version 0.1.0-rc7 is available (") and status_label.text.ends_with(" MB download).")
		and not check_button.disabled, status_label.text if status_label != null else "no status")
	checker.cooldown_s = 3600.0 # the launch request counts: Check now must wait
	settings._show_category(1) # Interface
	await ui.settle()
	check_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Check now right after the launch check: refused by the cooldown, said so", server.requests.size() == 1
		and status_label.text.ends_with("Wait a moment before checking again."), status_label.text)
	checker.cooldown_s = 0.0
	channel_picker.select(0)
	channel_picker.item_selected.emit(0)
	await ui.settle()
	var saved: Dictionary = Preferences.load_from(PREFS)
	_check("choosing Stable saves it and asks for stable releases", saved.update_channel == "stable" and saved.check_updates
		and checker.channel == "stable" and checker.is_checking(), str(saved.get("update_channel")))
	await _wait_idle(app, server)
	_check("stable answer: nothing offered, current on this channel", server.requests.size() == 2
		and status_label.text.begins_with("You're using the latest version on this channel."), status_label.text)
	auto_toggle.button_pressed = false
	await ui.settle()
	_check("turning automatic checks off is saved at once", Preferences.load_from(PREFS).check_updates == false and not checker.automatic)
	settings.close()
	await ui.settle()
	await ui.close_app(app)
	# Opt-out in the settings file: no checker at all.
	var prefs: Dictionary = Preferences.load_from(PREFS)
	prefs.check_updates = false
	_check("preference saved", Preferences.save_to(PREFS, prefs) == OK and Preferences.load_from(PREFS).check_updates == false)
	var requests_before := server.requests.size()
	var quiet: Node = _new_app()
	quiet.update_check_url = server.url()
	quiet.update_running_version = "0.1.0-rc6"
	root.add_child(quiet)
	await ui.settle()
	await ui.settle()
	_check("[updates] check=false: no checker, no request, no card", quiet.update_checker == null
		and server.requests.size() == requests_before and quiet.home.update_notice == null)
	# DT-UPD-04a: with automatic checks off, Check now from Settings still asks (and only then).
	quiet.check_updates_now()
	_check("automatic off: Check now creates a manual checker and asks once", quiet.update_checker != null
		and not quiet.update_checker.automatic and quiet.update_checker.is_checking())
	await _wait_idle(quiet, server)
	_check("automatic off: the manual answer arrives", server.requests.size() == requests_before + 1
		and quiet.update_checker.status().kind != UpdateCheck.STATUS_NOT_CHECKED, str(quiet.update_checker.status()))
	await ui.close_app(quiet)
	server.stop()


func _new_app() -> Node:
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.update_state_path = STATE
	return app


## Serves the fake API until the checker's request finishes (or 15 s of wall clock pass).
func _wait_idle(app: Node, server: FakeReleases) -> void:
	var started := Time.get_ticks_msec()
	while app.update_checker.is_checking() and Time.get_ticks_msec() - started < 15000:
		server.poll()
		await process_frame
	await ui.settle()


## Serves the fake API until Home shows the card (or 15 s of wall clock pass).
func _wait_notice(app: Node, server: FakeReleases) -> Control:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 15000:
		server.poll()
		await process_frame
		if app.home != null and app.home.update_notice != null and app.home.update_notice.visible:
			await ui.settle()
			return app.home.update_notice
	return null
