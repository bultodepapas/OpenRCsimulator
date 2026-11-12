## UI-32 / A14 F13: visible admission, recovery and staged cancellation.
extends SceneTree
const Home = preload("res://ui/home.gd")
const App = preload("res://app_root.gd")
const Weather = preload("res://physics/wind_config.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Preferences = preload("res://app_state/preferences.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
const UiInput = preload("res://ui/ui_input.gd")
const Driver = preload("res://tests/ui_driver.gd")
const PREFS = "user://test_home_launch_conditions.cfg"
# Seed 4 selects Timber, whose cancelled preview exercises material teardown.
const RANDOM_SEED = 4
const RANDOM_AIRCRAFT = "turbo-lumber-evolution"
class Candidate extends Node:
	signal startup_finished
	var startup_error := ""
	var startup_complete := false
	var startup_cancel_requested: Callable
	var recorder: Node
	var session: Node
	func _set(_property: StringName, _value: Variant) -> bool:
		return true
	func _ready() -> void:
		while not startup_cancel_requested.call():
			await get_tree().process_frame
		startup_error = "Flight preparation cancelled."
		startup_complete = true
		startup_finished.emit()
class TestApp extends App:
	var creations := 0
	func _create_flight(_aircraft_id: String = "") -> Node:
		creations += 1
		return Candidate.new()
var checks := 0
var failures := 0
var long_field_notice := ""
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ",label)
	else:
		print("ok   ",label)
func frames(count: int = 5) -> void:
	for _i in count:
		await process_frame

func inside(rect: Rect2, viewport: Rect2) -> bool:
	return rect.size.x > 0 and rect.size.y > 0 and rect.position.x >= viewport.position.x - 0.5 \
		and rect.position.y >= viewport.position.y - 0.5 and rect.end.x <= viewport.end.x + 0.5 \
		and rect.end.y <= viewport.end.y + 0.5

func check_home_layout(h: Control, ui: RefCounted, locale: String, scale: float, page: int, state: String) -> void:
	var blocked := state == "blocked" or state == "blocked_with_save_error"
	var stock_notice := state == "stock_notice" or state == "stock_with_save_error"
	var save_error := state == "save_error" or state == "blocked_with_save_error" or state == "stock_with_save_error"
	h.set_note("")
	h.set_stock_selection_notice("")
	h.set_weather_config(Weather.spatial_defaults() if blocked else Weather.defaults())
	if stock_notice:
		# A retained technical selection can accompany a settings-save error.
		h.set_stock_selection_notice("stik-glow-fs64v-4t")
	if save_error:
		# A settings save can fail while an inadmissible weather selection is retained.
		h.set_note(h.tr("Could not save settings (error %d).") % ERR_CANT_CREATE)
	elif state == "field_errors":
		# set_landscape() reports all field validation errors together.
		h.set_note(long_field_notice)
	elif state == "runtime_error":
		h.fail_start("Flight scene could not be created.")
	await frames(8) # Resize, wrapping, deferred responsive layout and container sorts must settle.
	var viewport: Rect2 = h.get_viewport_rect()
	var expected := Rect2(0, 0, 1920, 1080)
	var case := "%s/%.1f page %d %s" % [locale, scale, page, state]
	var rects := PackedStringArray()
	for control: Control in [h.fly_button, h.review_conditions_button, h.controls_button, h.help_button,
			h.quit_button, h.language_button, h.settings_button, h.launch_warning, h.note_label, h.stock_selection_notice]:
		rects.append("%s=%s visible=%s" % [control.name, str(control.get_global_rect()), control.is_visible_in_tree()])
	print("layout %s root=%s viewport=%s warning=%s note=%s stock=%s %s" % [case, str(root.size), str(viewport),
		h.launch_warning.text if h.launch_warning.is_visible_in_tree() else "<hidden>",
		h.note_label.text if h.note_label.is_visible_in_tree() else "<hidden>",
		h.stock_selection_notice.text if h.stock_selection_notice.is_visible_in_tree() else "<hidden>", "; ".join(rects)])
	check("%s settled viewport is 1920x1080" % case, root.size == Vector2i(1920, 1080) and viewport == expected)
	check("%s admission and messages match the state" % case,
		h.launch_warning.is_visible_in_tree() == blocked and h.review_conditions_button.is_visible_in_tree() == blocked
		and h.fly_button.disabled == blocked and h.note_label.is_visible_in_tree() == (save_error or state == "runtime_error" or state == "field_errors")
		and h.stock_selection_notice.is_visible_in_tree() == stock_notice)
	for control: Control in [h.fly_button, h.controls_button, h.help_button, h.quit_button, h.language_button, h.settings_button]:
		check("%s %s remains fully inside the viewport" % [case, control.name],
			control.is_visible_in_tree() and inside(control.get_global_rect(), viewport))
	if page == 1:
		check("%s aircraft details remain fully inside the viewport" % case,
			h._catalog_detail.is_visible_in_tree() and inside(h._catalog_detail.get_global_rect(), viewport))
		for detail: Label in [h._detail_name_label, h._detail_capability_label, h._detail_summary_label, h._detail_note_label]:
			check("%s aircraft detail %s shows every line" % [case, detail.name],
				detail.get_visible_line_count() == detail.get_line_count())
	for control: Control in [h.review_conditions_button, h.launch_warning, h.note_label, h.stock_selection_notice]:
		if control.is_visible_in_tree():
			if h._scroll.is_ancestor_of(control):
				await check_scroll_notice(h._scroll, control, case)
			else:
				check("%s %s remains fully inside the viewport" % [case, control.name], inside(control.get_global_rect(), viewport))
	if state == "blocked_with_save_error":
		var alternate_blocked: Dictionary = Weather.spatial_defaults()
		alternate_blocked.spatial_wind.identity.seed_u32 += 1
		h.set_weather_config(alternate_blocked)
		await frames(3)
		check("%s another blocked weather selection preserves the notice and recovery action" % case,
			h.launch_warning.visible and h.note_label.visible and h.review_conditions_button.visible)
	if h._scroll.is_ancestor_of(h.note_label) and h._scroll.get_v_scroll_bar().visible:
		root.gui_release_focus()
		h.ensure_focus()
		await frames(2)
		var action: Control = h.review_conditions_button if blocked else h.fly_button
		check("%s initial focus reaches the primary action" % case, action.has_focus())
		await ui.tap(KEY_UP)
		check("%s Up reaches the notices from the primary action" % case,
			h._scroll.has_focus() and h._scroll.scroll_vertical == 0)
		await ui.tap(KEY_PAGEDOWN)
		check("%s notices can be scrolled by keyboard" % case, h._scroll.scroll_vertical > 0)
		await ui.tap(KEY_HOME)
		await ui.tap(KEY_UP)
		var previous: Control = h.start_button if page == 0 else h._page_buttons[page]
		check("%s Up at the first boundary reaches the preceding page control" % case, previous.has_focus())
		if page == 1 and h._scroll.is_ancestor_of(previous):
			await ui.tap(KEY_ENTER)
			await frames(3)
			check("%s selecting a page keeps its focused navigation control visible" % case,
				previous.has_focus() and h._scroll.get_global_rect().encloses(previous.get_global_rect()))
		root.gui_release_focus()
		h.ensure_focus()
		await ui.tap(KEY_UP)
		await ui.tap(KEY_TAB)
		check("%s Tab returns from notices to the action" % case, action.has_focus())
		await ui.tap(KEY_UP)
		await ui.tap(KEY_END)
		await ui.tap(KEY_DOWN)
		check("%s Down at the last boundary returns to the action" % case, action.has_focus())
		UiInput.set_gamepad(Driver.FAKE_DEVICE)
		await ui.joy_button(JOY_BUTTON_DPAD_UP)
		check("%s controller reaches the notices" % case, h._scroll.has_focus())
		await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
		check("%s controller scrolls the notices" % case, h._scroll.has_focus() and h._scroll.scroll_vertical > 0)
		await ui.tap(KEY_HOME)
		await ui.joy_button(JOY_BUTTON_DPAD_UP)
		check("%s controller exits to the preceding page control" % case, previous.has_focus())
		root.gui_release_focus()
		h.ensure_focus()
		await ui.joy_button(JOY_BUTTON_DPAD_UP)
		await ui.tap(KEY_END)
		await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
		check("%s controller exits at the last boundary" % case, action.has_focus())
		if locale == "es" and scale == 2.0 and page == 1 and state == "field_errors":
			UiInput.set_gamepad(Driver.FAKE_DEVICE, {
				"navigate_up": {"type": "button", "button": JOY_BUTTON_Y},
				"navigate_down": {"type": "button", "button": JOY_BUTTON_X},
			})
			await ui.joy_button(JOY_BUTTON_Y)
			check("remapped controller enters the notices", h._scroll.has_focus())
			await ui.joy_button(JOY_BUTTON_X)
			check("remapped controller scrolls the notices", h._scroll.scroll_vertical > 0)
			await ui.tap(KEY_END)
			await ui.joy_button(JOY_BUTTON_X)
			check("remapped controller exits the notices", action.has_focus())
		UiInput.isolate_joypads()
		await ui.tap(KEY_UP)
		h.set_note("")
		h.set_stock_selection_notice("")
		await frames(8)
		check("%s removing notices restores focus to the action" % case, action.has_focus())

func check_scroll_notice(scroll: ScrollContainer, control: Control, case: String) -> void:
	# A notice taller than the body is read in sections; both ends must be reachable without clipping text.
	scroll.scroll_vertical = 0
	await frames(2)
	var area := scroll.get_global_rect()
	var top := control.get_global_rect().position.y - area.position.y
	var maximum := maxi(0, int(ceil(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)))
	scroll.scroll_vertical = clampi(int(floor(top)), 0, maximum)
	await frames(2)
	var first := control.get_global_rect()
	check("%s %s start is reachable in scroll body" % [case, control.name],
		area.size.y > 0 and first.position.y >= area.position.y - 1.0 and first.position.y < area.end.y)
	scroll.scroll_vertical = clampi(int(ceil(top + first.size.y - area.size.y)), 0, maximum)
	await frames(2)
	var last := control.get_global_rect()
	check("%s %s end is reachable without truncated text" % [case, control.name],
		last.end.y <= area.end.y + 1.0 and last.end.y > area.position.y
		and (not control is Label or ((control as Label).text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
			and (control as Label).get_visible_line_count() == (control as Label).get_line_count())))
	scroll.scroll_vertical = 0

func check_tab_cycle(h: Control, ui: RefCounted, page: int, notice: bool, blocked: bool, reverse: bool) -> void:
	h._select_page(page)
	h.set_aircraft("xcell-60-research" if blocked else Catalog.DEFAULT_ID)
	h.set_weather_config(Weather.spatial_defaults() if blocked else Weather.defaults())
	h.set_note("Settings from a newer version are read-only." if notice else "")
	await frames(8)
	root.gui_release_focus()
	h.ensure_focus()
	await frames(2)
	var visited: Array[Control] = []
	for _step in 100:
		var focused := root.gui_get_focus_owner()
		if focused == null or visited.has(focused):
			break
		visited.append(focused)
		if reverse:
			for pressed in [true, false]:
				var event := InputEventKey.new()
				event.keycode = KEY_TAB
				event.physical_keycode = KEY_TAB
				event.shift_pressed = true
				event.pressed = pressed
				Input.parse_input_event(event)
			await ui.settle()
		else:
			await ui.tap(KEY_TAB)
	var expected: Array[Control] = [h.language_button, h.settings_button, h.workshop_button,
		h.controls_button, h.help_button, h.quit_button]
	for button: Control in h._page_buttons:
		expected.append(button)
	match page:
		0:
			expected.append_array([h.previous_button, h.next_button, h.start_button, h.landscape_button,
				h.weather_button, h.time_button, h._details_button])
		1:
			expected.append_array([h._catalog_buttons[0], h._catalog_buttons[-1]])
		2:
			expected.append_array([h.statistics_button, h.natural_random_button, h.failures_button, h.trim_practice_button])
	if notice:
		expected.append(h._scroll)
	var missing := PackedStringArray()
	for control: Control in expected:
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled) and not visited.has(control):
			missing.append(control.name)
	var names := PackedStringArray()
	for control: Control in visited:
		names.append(control.name)
	var label := "%s/%.1f page %d notice=%s blocked=%s %s" % [str(root.size), UiTheme.text_scale, page, notice, blocked, "Shift-Tab" if reverse else "Tab"]
	check("%s reaches visible controls (missing: %s; cycle: %s)" % [label, str(missing), " -> ".join(names)], missing.is_empty())
	if blocked:
		check("%s skips disabled Fly and reaches recovery" % label,
			h.fly_button.disabled and not visited.has(h.fly_button) and visited.has(h.review_conditions_button))


func run() -> void:
	var ui = Driver.new(self)
	TranslationServer.set_locale("en")
	for layout: Array in [[Vector2i(1920, 1080), 1.0], [Vector2i(1280, 600), 1.0], [Vector2i(1920, 1080), 2.0]]:
		root.size = layout[0]
		UiTheme.text_scale = layout[1]
		var focus_home = Home.new()
		focus_home.theme = UiTheme.build()
		root.add_child(focus_home)
		await frames(8)
		for page in range(focus_home._pages.size()):
			for notice in [false, true]:
				await check_tab_cycle(focus_home, ui, page, notice, false, false)
				await check_tab_cycle(focus_home, ui, page, notice, false, true)
		await check_tab_cycle(focus_home, ui, 0, true, true, false)
		await check_tab_cycle(focus_home, ui, 0, true, true, true)
		focus_home.free()
		await frames(1)
	UiTheme.text_scale = 1.0
	var malformed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	for index in 8:
		malformed.surfaces.append({"id": "broken-%d" % index})
	var field_result: Dictionary = FieldLoader.validate(malformed)
	long_field_notice = "; ".join(field_result.errors)
	check("malformed field produces a long multi-error notice", not field_result.ok and field_result.errors.size() >= 8 and long_field_notice.length() > 500)
	root.size = Vector2i(1920,1080)
	await frames(8)
	for locale in ["en","es"]:
		TranslationServer.set_locale(locale)
		for scale in [1.0,2.0]:
			UiTheme.text_scale = scale
			var h = Home.new()
			h.theme = UiTheme.build()
			h.set_aircraft("xcell-60-research")
			root.add_child(h)
			await frames()
			for page in [0,1]:
				h._select_page(page)
				await frames()
				for state in ["clean", "blocked", "save_error", "blocked_with_save_error", "runtime_error", "field_errors", "stock_notice", "stock_with_save_error"]:
					await check_home_layout(h, ui, locale, scale, page, state)
				# The blocked state keeps keyboard access to the corrective action.
				h.set_weather_config(Weather.spatial_defaults())
				await frames()
				h.controls_button.grab_focus()
				await ui.tap(KEY_UP)
				check("%s/%.1f page %d directional navigation reaches corrective action" % [locale, scale, page],h.review_conditions_button.has_focus())
			h.set_weather_config(Weather.defaults())
			h.fail_start("Flight scene could not be created.")
			TranslationServer.set_locale("es" if locale == "en" else "en")
			check("runtime launch outcome follows locale",h.note_label.text == h.tr("Could not start flight: %s") % h.tr("Flight scene could not be created."))
			TranslationServer.set_locale(locale)
			var changed_weather: Dictionary = Weather.defaults()
			changed_weather.speed_mps = float(changed_weather.speed_mps) + 1.0
			h.set_weather_config(changed_weather)
			check("correcting conditions clears launch-owned failure",not h.note_label.visible)
			h.set_note("Independent save failure")
			h.set_aircraft("jensen-das-ugly-stik-60")
			check("aircraft correction preserves independent feedback",h.note_label.text == "Independent save failure")
			check("supported correction enables Fly",not h.fly_button.disabled and not h.launch_warning.visible and not h.review_conditions_button.visible)
			h.cancel_start()
			check("cancel message differs from failure",h.note_label.text == h.tr("Flight preparation cancelled.") and h.fly_button.has_focus())
			# UI-39: with an RC vehicle selected the same pinned action starts it; focus still falls back to it.
			h.set_activity("openrc-fpv5-x1")
			h._select_page(1)
			h.get_viewport().gui_release_focus()
			h.ensure_focus()
			check("a selected RC vehicle keeps visible fallback focus on Fly", h.fly_button.has_focus() and not h.fly_button.disabled
				and not h.launch_warning.visible)
			h.free()
			await frames(1)
	# Long catalog descriptions must also fit when the 200% detail card is widened.
	UiTheme.text_scale = 2.0
	for locale in ["en", "es"]:
		TranslationServer.set_locale(locale)
		var detail_home = Home.new()
		root.add_child(detail_home)
		detail_home._select_page(1)
		for id: String in Catalog.player_ids():
			detail_home.set_aircraft(id)
			await frames(8)
			var details: Rect2 = detail_home._catalog_detail.get_global_rect()
			check("%s %s 200%% aircraft details fit: %s" % [locale, id, str(details)],
				detail_home._catalog_detail.is_visible_in_tree() and inside(details, detail_home.get_viewport_rect()))
		detail_home.free()
		await frames(1)
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	var prefs: Dictionary = Preferences.DEFAULTS.duplicate(true)
	prefs.first_flight_hint_seen = true
	prefs.check_updates = false
	prefs.language = "en"
	prefs.aircraft = "xcell-60-research"
	prefs.weather_config = Weather.spatial_defaults()
	check("save isolated preferences",Preferences.save_to(PREFS,prefs) == OK)
	var app = TestApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	app.home_flight_prefetch_mode = "off"
	app.flight_loading_enabled = true
	app.window_focus_probe = func() -> bool: return true
	app.random_seed_source = func() -> int: return RANDOM_SEED
	root.add_child(app)
	root.size = Vector2i(1920,1080)
	await frames(8)
	var saved: PackedByteArray = FileAccess.get_file_as_bytes(PREFS)
	app.start_flight()
	check("root rejects known conditions before candidate or loading",app.creations == 0 and not app._loading_active and app.flight == null)
	app.home._select_page(1)
	app.home.review_conditions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Review opens Conditions from Aircraft",app.screens.is_top("weather"))
	app.weather_dialog.cancel_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Conditions Cancel returns to invoking action",app.screens.is_top("home") and app.home.review_conditions_button.has_focus() and FileAccess.get_file_as_bytes(PREFS) == saved)
	app.home.review_conditions_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	app.weather_dialog._on_preset_selected(1)
	app.weather_dialog.apply_button.grab_focus()
	await ui.tap(KEY_ENTER)
	await frames()
	check("Conditions Apply restores focus after corrective action disappears",app.screens.is_top("home") and not app.home.review_conditions_button.visible and app.home.fly_button.has_focus())
	var turbulence: Dictionary = Weather.upgrade_atmosphere(Weather.defaults())
	turbulence.turbulence_rms_mps = [0.3,0.2,0.1]
	app.preferences.weather_config = turbulence.duplicate(true)
	app.home.set_weather_config(App.weather_for_aircraft("xcell-60-research",turbulence))
	check("effective rotor weather admitted while saved airplane turbulence survives",not app.home.fly_button.disabled and app.preferences.weather_config == turbulence and not Weather.has_turbulence(app.home.weather_config))
	# Cancel a candidate that exists, then cancel an actual Random briefing candidate.
	for random_route in [false,true]:
		if random_route:
			app.open_natural_random()
			await frames()
			print("Random fixture aircraft=%s error=%s" % [str(app.natural_random_screen._scenario.get("aircraft_id", "")), app.natural_random_screen.error_label.text])
			check("seeded Random cancellation covers Timber preview",str(app.natural_random_screen._scenario.get("aircraft_id","")) == RANDOM_AIRCRAFT)
		if random_route:
			app.natural_random_screen._on_fly()
		else:
			app.home._on_fly()
		for _i in 1500:
			if app.flight != null or not app._loading_active:
				break
			await process_frame
		check("candidate reached before cancellation",app.flight != null and app._loading_active)
		app.cancel_flight_loading()
		for _i in 1500:
			if not app._loading_active:
				break
			await process_frame
		await frames()
		check("candidate cancellation returns without failure wording",app.flight == null and app.last_flight_loading.get("status") == "cancelled" and app.home.note_label.text == app.home.tr("Flight preparation cancelled."))
		if random_route:
			check("Random cancellation keeps briefing usable",app.screens.is_top("natural_random") and not app.natural_random_screen.fly_button.disabled and not app.natural_random_screen.error_label.visible)
			app.close_natural_random()
	await ui.close_app(app)
	for suffix in ["",".display",".controllers",".legacy_rc"]:
		var path: String = ProjectSettings.globalize_path(PREFS+suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Home launch conditions: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
