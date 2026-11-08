extends SceneTree
const Screen := preload("res://ui/statistics_screen.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const NaturalRandom := preload("res://scenarios/natural_random.gd")
const FailureConfig := preload("res://failures/config.gd")
const FailureCatalog := preload("res://failures/catalog.gd")
const RecordView := preload("res://statistics/record_view.gd")

class FakeService extends RefCounted:
	signal changed
	var note := ""
	var record: Dictionary = {}
	func query(_aircraft: String = "", _period: String = "session") -> Dictionary:
		return {available = true, revision = 1, history = [record], history_count = 1,
			started = 1, completed = 1, airborne_seconds = 93.125, landings = 1, full_stops = 1,
			max_tas_mps = 20.0, max_groundspeed_mps = 22.0, crashes = 0, restarts = 0}
	func aircraft_choices() -> Array: return []
	func can_manage() -> bool: return true

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if ok: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)
func settle() -> void:
	for _i in 12: await process_frame
func detail_row(parent: Node, caption: String) -> HBoxContainer:
	for child: Node in parent.get_children():
		if child is HBoxContainer and child.get_child_count() == 2 and child.get_child(0) is Label \
				and child.get_child(0).text == caption:
			return child as HBoxContainer
	return null
func inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.end.x <= outer.end.x + 1.0 \
		and inner.position.y >= outer.position.y - 1.0 and inner.end.y <= outer.end.y + 1.0
func check_pair(label: String, row: HBoxContainer, short_value: bool) -> void:
	if row == null:
		check(label + " row exists", false)
		return
	var caption: Label = row.get_child(0)
	var value: Label = row.get_child(1)
	var box := row.get_global_rect()
	var left := caption.get_global_rect()
	var right := value.get_global_rect()
	var font := value.get_theme_font("font")
	var font_size := value.get_theme_font_size("font_size")
	var text_width := font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var detail := "row=%s caption=%s value=%s text_width=%.1f lines=%d" % [box, left, right, text_width, value.get_line_count()]
	check(label + " both columns have useful width and do not overlap", inside(left, box) and inside(right, box)
		and left.end.x <= right.position.x + 1.0 and left.size.x >= box.size.x * 0.30 and right.size.x >= box.size.x * 0.30, detail)
	if short_value:
		check(label + " short value fits on one line", right.size.x + 1.0 >= text_width and value.get_line_count() == 1, detail)
	else:
		var expected_lines := ceili(text_width / maxf(1.0, right.size.x))
		check(label + " long value wraps without clipping or character stacking", right.size.x >= 240.0
			and value.get_line_count() <= expected_lines * 2 + 2 and right.size.y + 1.0 >= font.get_height(font_size) * value.get_line_count(), detail)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	UiScale.apply(root)
	var generated := NaturalRandom.generate(4294967295)
	check("layout scenario fixture is valid", generated.ok)
	if not generated.ok: quit(1); return
	var scenario: Dictionary = generated.scenario
	var practice := FailureConfig.defaults()
	practice.probability_percent = 100
	practice.excluded_ids = FailureCatalog.KNOWN_IDS.duplicate()
	var long_reason := "unrecognized_event_context_with_a_long_description_that_must_wrap_without_becoming_one_character_per_line_".repeat(2)
	var record := {id = "layout-flight", kind = "flight", aircraft_id = scenario.aircraft_id,
		aircraft_name = "Layout fixture", utc = "2026-11-07T12:00:00Z", ended_utc = "2026-11-07T12:02:00Z",
		outcome = "completed", airborne_seconds = 93.125, start_kind = "air_start", full_stops = 1,
		touch_and_go = 0, max_tas_mps = 20.0, config_hash = scenario.aircraft_identity,
		metadata = {launch_context_format = RecordView.CONTEXT_FORMAT, scenario = scenario,
			failure_config = practice, failure_seed = 4294967295,
			events = [{type = "unrecognized", reason = long_reason, tick = 1200}]}}
	for locale: String in ["en", "es"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 2.0]:
			UiTheme.text_scale = scale
			var service := FakeService.new()
			service.record = record.duplicate(true)
			var screen := Screen.new()
			screen.configure(service)
			root.add_child(screen)
			await settle()
			screen.call("_on_more_toggled", true)
			screen.call("_on_history_toggled", true)
			var row: VBoxContainer = screen.get("_history_rows").get_child(0)
			(row.get_child(0) as Button).button_pressed = true
			await settle()
			var detail: VBoxContainer = row.get_child(1)
			var context := "%s %d%%" % [locale, int(scale * 100.0)]
			var panel_rect: Rect2 = screen.get("_panel").get_global_rect()
			check(context + " panel stays within the 1080p viewport", inside(panel_rect, root.get_visible_rect()), str(panel_rect))
			check_pair(context + " More statistics", detail_row(screen.get("_more_box"), TranslationServer.translate("Maximum valid airspeed (TAS)")), true)
			check_pair(context + " airborne seconds", detail_row(detail, TranslationServer.translate("Airborne seconds")), true)
			check_pair(context + " Natural Random", detail_row(detail, TranslationServer.translate("Launch scenario")), true)
			check_pair(context + " ten-digit seed", detail_row(detail, TranslationServer.translate("Scenario seed")), true)
			check_pair(context + " excluded failures", detail_row(detail, TranslationServer.translate("Excluded failure types")), false)
			var event := detail_row(detail, TranslationServer.translate("Events"))
			check_pair(context + " unknown event", event, false)
			var scroll := screen.find_child("StatisticsScroll", true, false) as ScrollContainer
			if event != null:
				scroll.ensure_control_visible(event)
				await settle()
				var event_rect := event.get_global_rect()
				var scroll_rect := scroll.get_global_rect()
				check(context + " long detail start is reachable", scroll.scroll_vertical > 0 and event_rect.position.y >= scroll_rect.position.y - 1.0 and event_rect.position.y < scroll_rect.end.y, str(event_rect) + " in " + str(scroll_rect))
				if event_rect.size.y > scroll_rect.size.y:
					scroll.scroll_vertical += ceili(event_rect.size.y - scroll_rect.size.y)
					await settle()
				event_rect = event.get_global_rect()
				check(context + " long detail end is reachable", event_rect.end.y <= scroll_rect.end.y + 1.0 and event_rect.end.y > scroll_rect.position.y, str(event_rect) + " in " + str(scroll_rect))
			screen.free()
			await settle()
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	print("Statistics detail layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
