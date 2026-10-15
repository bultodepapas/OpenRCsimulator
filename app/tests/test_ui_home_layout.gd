# UI-25: Home reflows inside its fixed-width panel for every catalog aircraft and both languages. Long content may
# scroll, but Fly stays visible in the scroll viewport and the language/utility footer remains pinned on screen.
#
# Layout only: no flight, no settings file.
# Run: godot --headless --path . --script res://tests/test_ui_home_layout.gd
extends SceneTree

const Home := preload("res://ui/home.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")

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
					_check("%s: sidebar exactly %d px wide" % [case, Home.SIDEBAR_WIDTH], is_equal_approx(m.sidebar_w, Home.SIDEBAR_WIDTH), "%.0f" % m.sidebar_w)
					var expected_focus := "Fly" if Catalog.can_fly(id) else "NextAircraft" # a preview cannot fly: the arrow takes the focus
					_check("%s: Fly visible above the pinned footer, focus on %s" % [case, expected_focus],
						m.fly_top >= m.scroll_top and m.fly_bottom <= m.scroll_bottom + 0.5 and m.focus == expected_focus,
						"%s fly %.0f..%.0f scroll %.0f..%.0f" % [m.focus, m.fly_top, m.fly_bottom, m.scroll_top, m.scroll_bottom])
					_check("%s: opens at the top, title visible" % case, m.scroll == 0 and m.title_top >= 0.0, "scroll %d title y %.0f" % [m.scroll, m.title_top])
					_check("%s: pinned Language, Help and Settings remain visible" % case,
						m.footer_top >= m.panel_top and m.help_bottom <= m.panel_bottom
						and m.settings_bottom <= m.panel_bottom, "footer %.0f..%.0f panel %.0f..%.0f" % [m.footer_top, m.footer_bottom, m.panel_top, m.panel_bottom])
					_check("%s: Language and Controls labels cannot ellipsize" % case, m.language_full and m.controls_full,
						"language=%s controls=%s" % [m.language_text, m.controls_text])
					_check("%s: scroll indicator stays visible" % case, m.scroll_indicator)
					if m.overflow > 0.5:
						_check("%s: overflow remains scrollable" % case, m.scroll_indicator)
					if height == 720 and m.overflow > worst_720:
						worst_720 = m.overflow
						worst_720_case = case
					_check("%s: controls legend stays reachable in the scroll viewport" % case,
						m.legend_bottom_scrolled <= m.scroll_bottom + 0.5,
						"%.0f > %.0f" % [m.legend_bottom_scrolled, m.scroll_bottom])
	print("worst 720p overflow: %.0f px (%s)" % [worst_720, worst_720_case])
	TranslationServer.set_locale("en")
	print("all UI home layout checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Builds Home inside a window-sized frame and returns the numbers the checks need.
func _measure(id: String, defaults: bool, window: Vector2) -> Dictionary:
	var frame := Control.new()
	frame.size = window
	root.add_child(frame)
	var home: Control = Home.new()
	home.set_aircraft(id)
	if defaults:
		home.set_weather_config(Preferences.DEFAULTS.weather_config)
		home.set_time_of_day(Preferences.DEFAULTS.time_of_day)
		home.set_start_choice(Preferences.DEFAULTS.start_choice)
	frame.add_child(home)
	for i in range(6): # wrapped labels settle over a few layout passes
		await process_frame
	var sidebar: Control = home.get_node("Sidebar")
	var content: Control = sidebar.get_node("SidebarContent")
	var scroll: ScrollContainer = content.get_node("Scroll")
	var footer: Control = content.get_node("UtilityFooter")
	var column: Control = scroll.get_node("Column")
	var panel_style: StyleBox = sidebar.get_theme_stylebox("panel")
	var panel_top: float = sidebar.global_position.y + panel_style.content_margin_top
	var panel_bottom: float = window.y - panel_style.content_margin_bottom
	var legend: Control = home.keys_legend
	var out := {
		sidebar_w = sidebar.size.x,
		fly_top = home.fly_button.global_position.y,
		fly_bottom = home.fly_button.global_position.y + home.fly_button.size.y,
		focus = root.gui_get_focus_owner().name if root.gui_get_focus_owner() != null else "",
		overflow = column.get_combined_minimum_size().y - scroll.size.y,
		scroll_top = scroll.global_position.y,
		scroll_bottom = scroll.global_position.y + scroll.size.y,
		scroll_indicator = scroll.get_v_scroll_bar().visible,
		footer_top = footer.global_position.y,
		footer_bottom = footer.global_position.y + footer.size.y,
		help_bottom = home.help_button.get_global_rect().end.y,
		settings_bottom = home.settings_button.get_global_rect().end.y,
		panel_top = panel_top,
		panel_bottom = panel_bottom,
		scroll = scroll.scroll_vertical,
		title_top = (column.get_child(0) as Control).global_position.y,
		language_text = home.language_button.text,
		controls_text = home.controls_button.text,
		language_full = not home.language_button.clip_text and home.language_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS,
		controls_full = not home.controls_button.clip_text and home.controls_button.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS and home.controls_button.get_minimum_size().x <= home.controls_button.size.x,
	}
	_check("scroll follows the focus once settled (%s)" % id, scroll.follow_focus)
	scroll.scroll_vertical = int(ceil(maxf(out.overflow, 0.0)))
	await process_frame
	await process_frame
	out.legend_bottom_scrolled = legend.global_position.y + legend.size.y
	frame.queue_free()
	await process_frame
	return out
