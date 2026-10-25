# UI-FS-05/06: scoped summaries, touchdown/clean-stop wording, history pagination and guarded changes.
extends SceneTree

const StatisticsScreen := preload("res://ui/statistics_screen.gd")
const OverlayManager := preload("res://render/overlays/overlay_manager.gd")
const OverlaysDialog := preload("res://ui/overlays_dialog.gd")
const UiTheme := preload("res://ui/ui_theme.gd")


class FakeStatisticsService extends RefCounted:
	var revision := 7
	var note := ""
	var writable := true
	var query_log: Array = []
	var reset_log: Array = []
	var deletion_log: Array = []
	var values: Dictionary = {}

	func _init() -> void:
		var history: Array = []
		for index in 52:
			history.append({
				"flight_id": "flight-%03d" % index,
				"aircraft_id": "trainer-a",
				"aircraft_name": "Trainer A",
				"started_at": "2026-10-25T10:%02d:00Z" % (index % 60),
				"outcome": "completed",
				"airborne_seconds": 95.0,
				"takeoffs": 1,
				"full_stops": 1,
				"touch_and_go": 0,
				"max_tas_mps": 18.0,
				"partial": false,
				"timeline": ["Takeoff", "Full stop"],
			})
		values = {
			"started": 5, "completed": 4, "airborne_seconds": 1450.0,
			"average_seconds": 290.0, "average_count": 5,
			"landings": 6, "touch_and_go": 2, "full_stops": 4,
			"failed_landings": 1, "unknown_landings": 1,
			"crashes": 1, "restarts": 2,
			"max_tas_mps": 22.0, "max_groundspeed_mps": 24.0,
			"landing_rate": 6.0 / 7.0,
			"current_streak": 2, "best_streak": 3,
			"current_clean_seconds": 1200.0, "best_clean_seconds": 2400.0,
			"closed": 5, "active": 0, "partial": 0,
			"history": history, "history_count": history.size(),
			"first_history_date": "2026-10-01", "last_history_date": "2026-10-25",
			"period_label": "This session", "revision": revision,
		}

	func query(aircraft_id: String = "", period: String = "session") -> Dictionary:
		query_log.append([aircraft_id, period])
		var result := values.duplicate(true)
		result.revision = revision
		result.period_label = period
		return result

	func aircraft_choices() -> Array:
		return [{"id": "trainer-a", "name": "Trainer A"}, {"id": "trainer-b", "name": "Trainer B"}]

	func can_manage() -> bool:
		return writable

	func reset_counters(scope: String, aircraft_id: String = "") -> bool:
		reset_log.append([scope, aircraft_id])
		revision += 1
		return true

	func delete_history(aircraft_id: String = "") -> bool:
		deletion_log.append(aircraft_id)
		revision += 1
		return true


var _failures := 0
var _checks := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	UiTheme.text_scale = 1.0
	await _run()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	var service := FakeStatisticsService.new()
	var screen: CanvasLayer = StatisticsScreen.new()
	screen.configure(service, "")
	root.add_child(screen)
	await process_frame
	await process_frame
	_check("default filters show all aircraft and this session",
		screen._scope_picker.selected == 0 and screen._period_picker.selected == 0)
	_check("touchdown success shows the resolved-contact denominator",
		"6 / 7" in screen._touchdown_label.text and "Touchdown success" in screen._touchdown_label.text,
		screen._touchdown_label.text)
	_check("clean stops are shown separately from touchdown success",
		"4 / 5 ended flights" in screen._clean_stop_label.text and screen._touchdown_label != screen._clean_stop_label)
	_check("summary cards show airborne time, completions and landings",
		screen.find_child("AirborneValue", true, false).text == "24 min"
		and screen.find_child("CompletedValue", true, false).text == "4"
		and screen.find_child("LandingsValue", true, false).text.contains("6"))

	screen.call("_on_more_toggled", true)
	_check("expanded details show separate TAS and groundspeed",
		"Maximum valid airspeed (TAS)" in _all_text(screen._more_box)
		and "Maximum horizontal groundspeed" in _all_text(screen._more_box))
	screen.call("_on_history_toggled", true)
	_check("history is bounded to 50 rows per page", screen._history_rows.get_child_count() == 50)
	screen.call("_set_history_page", 1)
	_check("next history page retains the filter and shows the remaining rows",
		screen._history_page == 1 and screen._history_rows.get_child_count() == 2)
	var last_row := screen._history_rows.get_child(0) as VBoxContainer
	var history_toggle := last_row.get_child(0) as Button
	history_toggle.button_pressed = true
	history_toggle.toggled.emit(true)
	_check("history expansion exposes flight details", (last_row.get_child(1) as VBoxContainer).visible)
	screen.call("_on_aircraft_selected", 1)
	_check("aircraft filter queries the selected stable ID", service.query_log.back() == ["trainer-a", "session"])
	screen.call("_on_period_selected", 2)
	_check("period filter can select the counter-reset window", service.query_log.back() == ["trainer-a", "counters"])

	var back_count := 0
	screen.back_requested.connect(func() -> void: back_count += 1)
	(screen.find_child("Back", true, false) as Button).pressed.emit()
	_check("Back returns through the ScreenStack signal", back_count == 1)

	# Cancel is a pure close: no service method is called.
	screen.call("_open_reset", "session", "", "session")
	var dialog: ConfirmationDialog = screen.get("_active_dialog")
	dialog.call("_on_cancelled")
	_check("cancelling a counter reset does not mutate the service", service.reset_log.is_empty())
	await process_frame

	# A stale confirmation is replaced with a fresh preview and needs another confirmation.
	screen.call("_open_reset", "session", "", "session")
	dialog = screen.get("_active_dialog")
	service.revision += 1
	dialog.call("_on_confirmed")
	_check("changed revisions block the old confirmation", service.reset_log.is_empty()
		and dialog._pinned_revision == service.revision
		and "Review the updated preview" in dialog.status_label.text)
	dialog.call("_on_confirmed")
	_check("a current preview can reset only the selected counter scope",
		service.reset_log.size() == 1 and service.reset_log[0] == ["session", ""])
	await process_frame

	screen.call("_open_reset", "aircraft", "trainer-a", "counters")
	dialog = screen.get("_active_dialog")
	dialog.call("_on_confirmed")
	_check("aircraft counter reset remains aircraft-scoped",
		service.reset_log.size() == 2 and service.reset_log[1] == ["aircraft", "trainer-a"])
	await process_frame

	screen.call("_open_delete", "trainer-a")
	dialog = screen.get("_active_dialog")
	_check("history deletion preview pins its store revision and exact count",
		dialog._pinned_revision == service.revision and "52 flight records" in dialog.preview_label.text
		and "2026-10-01" in dialog.preview_label.text)
	dialog.scope_check.button_pressed = true
	dialog.call("_on_confirmed")
	_check("history deletion requires confirmation and names its aircraft",
		service.deletion_log == ["trainer-a"])
	await process_frame

	service.writable = false
	screen.call("_refresh_manage_controls")
	_check("management controls disable when the service is read-only",
		screen._session_reset_button.disabled and screen._pilot_delete_button.disabled)

	# The existing overlay settings path remains opt-in and supports an aircraft-specific view.
	var manager: CanvasLayer = OverlayManager.new({"preset": "custom", "visible": ["session_stats"]}, "en")
	manager.statistics_service = service
	manager.statistics_aircraft_id = "trainer-a"
	root.add_child(manager)
	var overlays_dialog: CanvasLayer = OverlaysDialog.new(manager)
	root.add_child(overlays_dialog)
	await process_frame
	_check("session statistics switch is in the existing training section",
		overlays_dialog.switches.has("session_stats") and overlays_dialog._training_grid.get_child_count() >= 4)
	manager.set_widget_option("session_stats_scope", "aircraft")
	_check("overlay scope preference validates and persists", manager.settings.get("session_stats_scope") == "aircraft")
	manager.refresh_numbers({"telemetry": {}, "battery": {}, "mass_sample": {}, "warnings": PackedStringArray()})
	_check("HUD queries the selected aircraft and keeps all three counters visible",
		service.query_log.back() == ["trainer-a", "session"]
		and manager.frames.session_stats.value_label.visible
		and manager.frames.session_stats.left_value.visible
		and manager.frames.session_stats.right_value.visible)
	manager.set_widget_option("widget_compact", true)
	manager.refresh_numbers({"telemetry": {}, "battery": {}, "mass_sample": {}, "warnings": PackedStringArray()})
	_check("compact HUD retains landings, crashes and restarts", manager.frames.session_stats.value_label.visible
		and manager.frames.session_stats.left_value.visible and manager.frames.session_stats.right_value.visible)

	UiTheme.text_scale = 2.0
	screen.call("_resize_layout")
	_check("200% text stacks filters and summary cards without hiding them",
		screen._filter_row.vertical and screen._body_grid.columns == 1
		and screen._scope_picker.is_visible_in_tree() and screen._period_picker.is_visible_in_tree())
	UiTheme.text_scale = 1.0
	if is_instance_valid(overlays_dialog): overlays_dialog.queue_free()
	if is_instance_valid(manager): manager.queue_free()
	if is_instance_valid(screen): screen.queue_free()
	await process_frame


func _all_text(node: Node) -> String:
	var result := ""
	if node is Label: result += (node as Label).text + "\n"
	for child: Node in node.get_children(): result += _all_text(child)
	return result


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
