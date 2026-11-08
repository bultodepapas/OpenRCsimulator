## UI-36 / A18 section 4: saved practice scope and a visible ordinary-flight reminder.
extends SceneTree
const Home := preload("res://ui/home.gd")
const FailureMenu := preload("res://ui/failures_menu.gd")
const FailureConfig := preload("res://failures/config.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Wind := preload("res://physics/wind_config.gd")
const Driver := preload("res://tests/ui_driver.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)
func settle() -> void:
	for _i in 12: await process_frame
func fits(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1920.5 and rect.end.y <= 1080.5
func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var driver := Driver.new(self)
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			var home := Home.new()
			home.theme = UiTheme.build()
			root.add_child(home)
			await settle()
			check("default-off reminder is hidden", not home.failure_launch_notice.visible)
			home.fly_button.grab_focus()
			var config := FailureConfig.defaults()
			config.probability_percent = 35
			home.set_failure_config(config)
			await settle()
			check("enabled reminder does not steal focus", home.fly_button.has_focus())
			for page: int in [0, 1, 2, 3, 0]:
				home._select_page(page)
				home.set_note("Could not save settings (error 13).")
				await settle()
				var label: Label = home.failure_launch_notice
				check("%s %s page%d reminder follows ordinary Fly" % [locale, scale, page], label.is_visible_in_tree() == (page != 3))
				if page != 3:
					check("reminder reports saved probability", label.text == home.tr("Failure practice: %d%%") % 35)
					check("reminder and Fly remain visible with save feedback", fits(label) and fits(home.note_label) and fits(home.fly_button), str(label.get_global_rect()))
				check("utility actions stay inside1080p", fits(home.controls_button) and fits(home.help_button) and fits(home.quit_button))
			var switched := "es" if locale == "en" else "en"
			TranslationServer.set_locale(switched)
			await settle()
			check("reminder follows live locale", home.failure_launch_notice.text == home.tr("Failure practice: %d%%") % 35)
			TranslationServer.set_locale(locale)
			home.set_note("")
			await settle()
			home.fly_button.grab_focus()
			await driver.tap(KEY_UP)
			await settle()
			check("keyboard can reveal the selected airplane beside launch controls", home.start_button.has_focus()
				and home._scroll.get_global_rect().grow(1.0).encloses(home.aircraft_name_label.get_global_rect()))
			home.set_aircraft("xcell-60-research")
			home.set_weather_config(Wind.spatial_defaults())
			await settle()
			check("rotorcraft hides airplane practice and retains weather admission", not home.failure_launch_notice.visible and home.launch_warning.visible and home.review_conditions_button.visible)
			check("weather recovery action and utilities still fit", fits(home.review_conditions_button) and fits(home.quit_button))
			home.set_aircraft("jensen-das-ugly-stik-60")
			await settle()
			check("returning to airplane restores the saved reminder", home.failure_launch_notice.visible and "35%" in home.failure_launch_notice.text)
			config.probability_percent = 0
			home.set_failure_config(config)
			await settle()
			check("turning practice off removes the reminder", not home.failure_launch_notice.visible)
			home.free()
			for current in [false, true]:
				var menu := FailureMenu.new(FailureConfig.defaults())
				menu.current_flight_settings = current
				root.add_child(menu)
				await settle()
				var lifetime: Label = menu.find_child("FailureSettingsLifetime", true, false)
				var restart: Label = menu.find_child("FailureSettingsRestart", true, false)
				check("menu explains reusable settings", lifetime.atr(lifetime.text) == menu.tr("These settings apply to new ordinary airplane flights until you change them."))
				check("menu explains stable Restart and new-Home-flight boundary", restart.atr(restart.text) == menu.tr("Restart repeats the current failure setup and never rerolls the current flight. Start a new flight from Home to use changed settings."))
				check("menu Apply and Cancel remain visible at both scales", fits(menu.apply_button) and fits(menu.cancel_button))
				if current:
					check("current-flight notification change is immediate and distinct", menu.notice_hint_label.text == menu.tr("Applying changes updates notices in this flight immediately. The other settings apply to new ordinary airplane flights."))
				var scroll: ScrollContainer = menu.find_child("FailureSettingsScroll", true, false)
				scroll.ensure_control_visible(restart)
				await settle()
				check("lifetime guidance is reachable by existing scroll", restart.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1 and restart.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1)
				menu.free()
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	print("Failure scope UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
