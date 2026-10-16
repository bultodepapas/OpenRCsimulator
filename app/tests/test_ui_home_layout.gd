# UI-25: Home reflows for every catalog aircraft and both languages. Long content scrolls while Fly and utility
# actions stay pinned and visible, including at 200% text size on the 720p logical canvas.
#
# Layout only: no flight, no settings file.
# Run: godot --headless --path . --script res://tests/test_ui_home_layout.gd
extends SceneTree

const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var worst_720 := 0.0
	var worst_720_case := ""
	for lang in ["en", "es"]:
		TranslationServer.set_locale(lang)
		for id in Catalog.ids():
			for defaults in [false, true]:
				for height in [720, 1080]:
					var m := await _measure(id, defaults, Vector2(1280 if height == 720 else 1920, height))
					var case := "%s %s%s %dp" % [lang, id, " defaults" if defaults else "", height]
					var max_rail_width := 500.0 if m.large_text else 304.0 if height == 720 else 340.0
					_check("%s: Home rail stays bounded at %.0f px or less" % [case, max_rail_width],
						m.rail_w >= 280.0 and m.rail_w <= max_rail_width + 0.5, "%.0f" % m.rail_w)
					var expected_focus := "Fly" if Catalog.can_fly(id) else "NextAircraft" # a preview cannot fly: the arrow takes the focus
					_check("%s: Fly visible above the pinned footer, focus on %s" % [case, expected_focus],
						m.fly_top >= m.primary_top and m.fly_bottom <= m.primary_bottom + 0.5
						and m.primary_bottom <= m.footer_top + 0.5 and m.focus == expected_focus,
						"%s fly %.0f..%.0f primary %.0f..%.0f footer %.0f" % [m.focus, m.fly_top, m.fly_bottom, m.primary_top, m.primary_bottom, m.footer_top])
					_check("%s: Flight page opens at the top with its title visible" % case,
						m.scroll == 0 and m.title_top >= m.scroll_top - 0.5,
						"scroll %d title y %.0f viewport y %.0f" % [m.scroll, m.title_top, m.scroll_top])
					_check("%s: header actions, Help and utilities remain inside the viewport" % case,
						m.footer_top >= m.panel_top and m.help_bottom <= m.panel_bottom
						and m.language_bottom <= m.panel_bottom and m.settings_bottom <= m.panel_bottom,
						"footer %.0f..%.0f viewport %.0f..%.0f" % [m.footer_top, m.footer_bottom, m.panel_top, m.panel_bottom])
					_check("%s: Language and Controls labels cannot ellipsize" % case, m.language_full and m.controls_full,
						"language=%s controls=%s" % [m.language_text, m.controls_text])
					_check("%s: scroll bar tracks actual Flight-page overflow" % case,
						(m.overflow > 0.5) == m.scroll_indicator,
						"overflow %.1f scrollbar=%s" % [m.overflow, str(m.scroll_indicator)])
					if height == 720 and m.overflow > worst_720:
						worst_720 = m.overflow
						worst_720_case = case
					_check("%s: controls legend stays reachable in the scroll viewport" % case,
						m.legend_bottom_scrolled <= m.scroll_bottom + 0.5,
						"%.0f > %.0f" % [m.legend_bottom_scrolled, m.scroll_bottom])
	for lang in ["en", "es"]:
		TranslationServer.set_locale(lang)
		for id in Catalog.ids():
			var m := await _measure(id, false, Vector2(1280, 720), 2.0)
			var case := "%s %s 720p 200%%" % [lang, id]
			_check("%s: pinned Fly and utility footer fit above the bottom edge" % case,
				m.fly_top >= m.primary_top and m.fly_bottom <= m.primary_bottom + 0.5
				and m.primary_bottom <= m.footer_top + 0.5 and m.settings_bottom <= m.panel_bottom,
				"fly %.0f..%.0f primary %.0f..%.0f footer %.0f settings %.0f / panel %.0f" % [m.fly_top, m.fly_bottom, m.primary_top, m.primary_bottom, m.footer_top, m.settings_bottom, m.panel_bottom])
			_check("%s: 200%% text leaves a usable scroll body" % case,
				m.scroll_height > 0.0 and m.scroll_indicator and m.overflow > 0.5,
				"scroll height %.0f, overflow %.0f" % [m.scroll_height, m.overflow])
			_check("%s: utility labels fit without clipping or ellipses" % case,
				m.utility_buttons_fit and m.utility_text_full, m.utility_buttons_detail)
	print("worst 720p overflow: %.0f px (%s)" % [worst_720, worst_720_case])
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	root.size = Vector2i(1280, 720)
	print("all UI home layout checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Builds Home inside a window-sized frame and returns the numbers the checks need.
func _measure(id: String, defaults: bool, window: Vector2, text_scale := 1.0) -> Dictionary:
	UiTheme.text_scale = text_scale
	root.size = Vector2i(window)
	var frame := Control.new()
	frame.size = window
	root.add_child(frame)
	var home: Control = Home.new()
	home.set_anchors_preset(Control.PRESET_FULL_RECT)
	home.set_aircraft(id)
	if defaults:
		home.set_weather_config(Preferences.DEFAULTS.weather_config)
		home.set_time_of_day(Preferences.DEFAULTS.time_of_day)
		home.set_start_choice(Preferences.DEFAULTS.start_choice)
	frame.add_child(home)
	for _frame in 6: # wrapped labels settle over a few layout passes
		await process_frame
	var rail: Control = home.get_node("HomeRail")
	var scroll: ScrollContainer = home.get_node("HomeRail/HomeContentScroll")
	var primary: Control = home.get_node("HomeRail/PrimaryActions")
	var footer: Control = home.get_node("HomeRail/HomeUtilities")
	var page: Control = home._pages[0]
	var legend: Control = home.keys_legend
	var rail_rect := rail.get_global_rect()
	var footer_rect := footer.get_global_rect()
	var scroll_rect := scroll.get_global_rect()
	var screen := Rect2(Vector2.ZERO, window)
	var overflow := page.get_combined_minimum_size().y - scroll.size.y
	var out := {
		rail_w = rail.size.x,
		large_text = text_scale >= 1.5,
		fly_top = home.fly_button.global_position.y,
		fly_bottom = home.fly_button.get_global_rect().end.y,
		primary_top = primary.global_position.y,
		primary_bottom = primary.get_global_rect().end.y,
		focus = root.gui_get_focus_owner().name if root.gui_get_focus_owner() != null else "",
		overflow = overflow,
		scroll_top = scroll_rect.position.y,
		scroll_bottom = scroll_rect.end.y,
		scroll_height = scroll.size.y,
		scroll_indicator = scroll.get_v_scroll_bar().visible,
		footer_top = footer_rect.position.y,
		footer_bottom = footer_rect.end.y,
		help_bottom = home.help_button.get_global_rect().end.y,
		language_bottom = home.language_button.get_global_rect().end.y,
		settings_bottom = home.settings_button.get_global_rect().end.y,
		panel_top = screen.position.y,
		panel_bottom = screen.end.y,
		scroll = scroll.scroll_vertical,
		title_top = (page.get_child(0) as Control).get_global_rect().position.y,
		language_text = home.language_button.text,
		controls_text = home.controls_button.text,
		language_full = not home.language_button.clip_text and home.language_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS,
		controls_full = not home.controls_button.clip_text and home.controls_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS and home.controls_button.get_minimum_size().x <= home.controls_button.size.x,
		utility_buttons_fit = _utility_buttons_fit(home),
		utility_text_full = _utility_text_full(home),
		utility_buttons_detail = _utility_button_detail(home),
	}
	_check("scroll follows the focus once settled (%s)" % id, scroll.follow_focus)
	scroll.scroll_vertical = int(ceil(maxf(overflow, 0.0)))
	await process_frame
	await process_frame
	out.legend_bottom_scrolled = legend.get_global_rect().end.y
	frame.queue_free()
	await process_frame
	return out


static func _utility_buttons_fit(home: Control) -> bool:
	for button: Button in [home.language_button, home.help_button, home.quit_button, home.controls_button, home.settings_button]:
		var minimum := button.get_combined_minimum_size()
		if button.clip_text or minimum.x > button.size.x + 0.5 or minimum.y > button.size.y + 0.5:
			return false
	return true


static func _utility_text_full(home: Control) -> bool:
	for button: Button in [home.language_button, home.help_button, home.quit_button, home.controls_button, home.settings_button]:
		if button.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS or button.text.contains("…") or button.text.contains("..."):
			return false
	return true


static func _utility_button_detail(home: Control) -> String:
	var details := PackedStringArray()
	for button: Button in [home.language_button, home.help_button, home.quit_button, home.controls_button, home.settings_button]:
		var minimum := button.get_combined_minimum_size()
		details.append("%s %.0fx%.0f/%.0fx%.0f" % [button.name, minimum.x, minimum.y, button.size.x, button.size.y])
	return ", ".join(details)
