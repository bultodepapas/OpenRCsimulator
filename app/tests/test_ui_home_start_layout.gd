# UI-06d-R2: launch captions stay inside Home and refresh after a live locale change.
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var script: Script = load("res://ui/home.gd")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--home="): script = load(arg.trim_prefix("--home="))
	var locale := TranslationServer.get_locale()
	var home: Control = script.new()
	root.size = Vector2i(1280, 720)
	home.set_aircraft("xcell-60-research")
	home.start_requested.connect(home.set_start_choice)
	root.add_child(home)
	var driver := UiDriver.new(self)
	for lang in ["en", "es", "en"]:
		TranslationServer.set_locale(lang)
		# No set_aircraft/set_start_choice after this locale change: the notification must refresh it.
		for frame in range(6): await process_frame
		_check("%s pad caption follows live locale" % lang, home.start_button.text == TranslationServer.translate("Start: helicopter pad"))
		_check("%s startup instructions follow live locale" % lang, home.limits_label.text == TranslationServer.translate("Experimental helicopter. On the pad: arm, release hold, wait for RPM, then raise collective."))
		_check("%s launch tooltip follows live locale" % lang, home.start_button.tooltip_text == TranslationServer.translate("Choose a stopped rotor on the pad or a trimmed practice hover."))
		_check_layout(home, lang + " pad")
		home.start_button.grab_focus()
		await driver.tap(KEY_ENTER)
		for frame in range(6): await process_frame
		_check("%s Enter selects hover" % lang, home.start_choice == "airborne" and home.start_button.text == TranslationServer.translate("Start: hover"))
		_check("%s selection retains focus" % lang, home.start_button.has_focus())
		_check_layout(home, lang + " hover")
		await driver.tap(KEY_ENTER)
		for frame in range(6): await process_frame
		_check("%s Enter returns to pad" % lang, home.start_choice == "runway")
	# The same wrapping policy covers the longer half-power airplane launch caption.
	for lang in ["en", "es"]:
		TranslationServer.set_locale(lang)
		home.set_aircraft("jensen-das-ugly-stik-60")
		home.set_start_choice("airborne_half_power")
		for frame in range(6): await process_frame
		_check("%s half-power choice remains selected" % lang, home.start_choice == "airborne_half_power")
		_check_layout(home, lang + " airplane")
	home.free()
	TranslationServer.set_locale(locale)
	print("Home launch layout: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_layout(home: Control, label: String) -> void:
	var sidebar: Control = home.get_node("Sidebar")
	var button: Button = home.start_button
	var card: Control = home.get_node("Sidebar/SidebarContent/Scroll/Column/AircraftCard")
	_check(label + " sidebar remains 440 px", is_equal_approx(sidebar.size.x, 440.0))
	_check(label + " button stays inside its card", button.global_position.x >= card.global_position.x and button.global_position.x + button.size.x <= card.global_position.x + card.size.x)
	_check(label + " full button height fits its content", button.size.y >= button.get_combined_minimum_size().y - 0.5)

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)
