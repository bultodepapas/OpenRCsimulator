# NR-05: the Natural Random briefing translates static headings, stays readable at menu sizes and recovers after failure.
# Run: godot --headless --path . --script res://tests/test_natural_random_screen.gd
extends SceneTree

const NaturalRandomScreen := preload("res://ui/natural_random_screen.gd")
const WeatherSettings := preload("res://physics/wind_config.gd")
const TimeOfDay := preload("res://environment/time_of_day_config.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _failures: int = 0
var ui: RefCounted
var screen: CanvasLayer
var _fly_scenario: Dictionary = {}
var _reroll_count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	root.size = Vector2i(1280, 720)
	TranslationServer.set_locale("en")
	await _run()


func _run() -> void:
	screen = NaturalRandomScreen.new(_scenario()) as CanvasLayer
	root.add_child(screen)
	screen.fly_requested.connect(_on_fly_requested)
	screen.reroll_requested.connect(_on_reroll_requested)
	screen.set_repeat_available(true)
	await ui.settle()
	_test_english_and_static_translation_modes()
	await _test_spanish()
	await _test_layout(Vector2i(1024, 576))
	await _test_layout(Vector2i(1280, 720))
	await _test_error_recovery()
	screen.queue_free()
	await process_frame
	print("all Natural Random screen checks passed" if _failures == 0 else "%d Natural Random screen checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_english_and_static_translation_modes() -> void:
	_check("English briefing title and actions", screen.title_label.text == "NATURAL RANDOM"
		and screen.fly_button.text == "FLY" and screen.reroll_button.text == "Another flight"
		and screen.repeat_button.text == "Repeat last flight" and screen.back_button.text == "Back")
	var headings: Dictionary = {
		"StockAirplaneHeading": "Stock airplane",
		"ModelStatusHeading": "Model status",
		"FlightConditionsHeading": "Conditions",
		"FlightDetailsHeading": "Flight details",
	}
	for node_name: String in headings:
		var label: Label = screen.find_child(node_name, true, false) as Label
		_check("%s exists and inherits auto-translation" % node_name,
			label != null and label.can_auto_translate(), "missing or disabled: %s" % node_name)
		if label != null:
			_check("%s has its English source text" % node_name, label.text == headings[node_name], label.text)
	_check("dynamic title remains explicitly translated", not screen.title_label.can_auto_translate())


func _test_spanish() -> void:
	TranslationServer.set_locale("es")
	await ui.settle()
	var translations: Dictionary = {
		"StockAirplaneHeading": "Avión de serie",
		"ModelStatusHeading": "Estado del modelo",
		"FlightConditionsHeading": "Condiciones de vuelo",
		"FlightDetailsHeading": "Detalles del vuelo",
	}
	for node_name: String in translations:
		var label: Label = screen.find_child(node_name, true, false) as Label
		if label == null:
			_check("%s Spanish translation" % node_name, false, "label missing")
			continue
		_check("%s Spanish translation" % node_name, label.can_auto_translate()
			and label.atr(label.text) == translations[node_name], label.text)
	_check("dynamic title and actions rebuild in Spanish",
		screen.title_label.text == "ALEATORIO NATURAL" and screen.fly_button.text == "VOLAR"
		and screen.reroll_button.text == "Otro vuelo" and screen.repeat_button.text == "Repetir último vuelo"
		and screen.back_button.text == "Volver", screen.title_label.text)

	screen.details_button.pressed.emit()
	await ui.settle()
	_check("details expand and label updates in Spanish", screen.details_panel.visible
		and screen.details_button.text == "Ocultar detalles")
	_check("flight seed and atmosphere detail are shown",
		screen.seed_label.text == "Semilla del vuelo: 4242"
		and "densidad" in screen.atmosphere_label.text, screen.atmosphere_label.text)


func _test_layout(size: Vector2i) -> void:
	root.size = size
	await ui.settle()
	var bounds := Rect2(Vector2.ZERO, Vector2(size))
	var sidebar_rect: Rect2 = screen.sidebar.get_global_rect()
	var scroll: ScrollContainer = screen.find_child("BriefingScroll", true, false) as ScrollContainer
	var actions: VBoxContainer = screen.find_child("BriefingActions", true, false) as VBoxContainer
	var scroll_rect: Rect2 = scroll.get_global_rect()
	var actions_rect: Rect2 = actions.get_global_rect()
	_check("briefing sidebar fits %d×%d" % [size.x, size.y], _inside(sidebar_rect, bounds), str(sidebar_rect))
	var sidebar_style: StyleBoxFlat = screen.sidebar.get_theme_stylebox("panel") as StyleBoxFlat
	_check("briefing preserves theme gutters at %d×%d" % [size.x, size.y],
		actions_rect.position.x >= sidebar_rect.position.x + sidebar_style.content_margin_left
		and actions_rect.end.x <= sidebar_rect.end.x - sidebar_style.content_margin_right
		and scroll_rect.position.y >= sidebar_rect.position.y + sidebar_style.content_margin_top, str(actions_rect))
	_check("briefing sidebar background is opaque at %d×%d" % [size.x, size.y],
		sidebar_style != null and is_equal_approx(sidebar_style.bg_color.a, 1.0), str(sidebar_style.bg_color.a if sidebar_style != null else -1.0))
	_check("opaque sidebar leaves the field backdrop area uncovered at %d×%d" % [size.x, size.y],
		sidebar_rect.end.x < bounds.end.x and screen.sidebar_fade.visible)
	_check("fixed actions fit below the scroll area at %d×%d" % [size.x, size.y],
		_inside(actions_rect, bounds) and scroll_rect.end.y <= actions_rect.position.y + 1.0,
		"scroll=%s actions=%s" % [str(scroll_rect), str(actions_rect)])
	_check("expanded details scroll at %d×%d" % [size.x, size.y], screen.details_panel.visible
		and scroll.get_v_scroll_bar().max_value > 0.0)
	_check("repeat action is visible and inside sidebar at %d×%d" % [size.x, size.y],
		screen.repeat_button.visible and _inside(screen.repeat_button.get_global_rect(), sidebar_rect),
		str(screen.repeat_button.get_global_rect()))
	_check("Fly, Another flight and Back stay inside sidebar at %d×%d" % [size.x, size.y],
		_inside(screen.fly_button.get_global_rect(), sidebar_rect)
		and _inside(screen.reroll_button.get_global_rect(), sidebar_rect)
		and _inside(screen.back_button.get_global_rect(), sidebar_rect))


func _test_error_recovery() -> void:
	screen.set_busy(true)
	_check("preparation holds duplicate actions but leaves Back enabled", screen.fly_button.disabled
		and screen.reroll_button.disabled and screen.repeat_button.disabled and not screen.back_button.disabled)
	screen.show_error("Could not prepare random flight: candidate rejected")
	await ui.settle()
	_check("error clears busy and keeps Fly disabled", screen.error_label.visible and not screen.busy_label.visible
		and screen.fly_button.disabled)
	_check("error leaves Another, Repeat and Back enabled", not screen.reroll_button.disabled
		and not screen.repeat_button.disabled and not screen.back_button.disabled)
	_check("error moves focus from disabled Fly to recovery action", ui.focus_name() == "AnotherFlight", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("focused recovery action activates Another flight", _reroll_count == 1, str(_reroll_count))

	var candidate: Dictionary = _scenario()
	screen.set_busy(true)
	screen.set_scenario(candidate)
	screen.set_busy(false)
	_check("a freshly prepared scenario re-enables Fly", not screen.fly_button.disabled)
	screen.fly_button.grab_focus()
	await ui.tap(KEY_ENTER)
	_check("Fly emits the exact displayed scenario and enters busy state",
		_fly_scenario == candidate and screen.busy_label.visible and screen.fly_button.disabled)


func _scenario() -> Dictionary:
	var weather: Dictionary = WeatherSettings.upgrade_atmosphere(WeatherSettings.GENTLE_PRACTICE, {
		atmosphere_mode = "custom",
		field_elevation_m = 1200.0,
		temperature_c = 20.0,
		qnh_hpa = 1011.0,
		relative_humidity_pct = 45.0,
	})
	var lighting: Dictionary = TimeOfDay.defaults()
	lighting.mode = "astronomical"
	lighting.local_seconds = 8 * 3600
	return {
		aircraft_id = "jensen-das-ugly-stik-60",
		weather_config = weather,
		lighting_config = lighting,
		start_choice = "airborne",
		recipe_id = "gentle_breeze",
		daylight_id = "morning",
		provenance = "generated",
		seed = 4242,
	}


func _on_fly_requested(candidate: Dictionary) -> void:
	_fly_scenario = candidate.duplicate(true)


func _on_reroll_requested() -> void:
	_reroll_count += 1


static func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 \
		and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0
