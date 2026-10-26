# UI-FS-05/06: scoped summaries, touchdown/clean-stop wording, history pagination and guarded changes.
extends SceneTree

const StatisticsScreen := preload("res://ui/statistics_screen.gd")
const OverlayManager := preload("res://render/overlays/overlay_manager.gd")
const OverlaysDialog := preload("res://ui/overlays_dialog.gd")
const ScreenStack := preload("res://ui/screen_stack.gd")
const UiTheme := preload("res://ui/ui_theme.gd")


class FakeStatisticsService extends RefCounted:
	signal changed
	var revision := 7
	var note := ""
	var writable := true
	var query_log: Array = []
	var summary_log: Array = []
	var reset_log: Array = []
	var deletion_log: Array = []
	var values: Dictionary = {}

	func _init() -> void:
		var history: Array = []
		for index in 52:
			var record_kind := "flight" if index < 50 else ("crash" if index == 50 else "restart")
			var record := {
				"id": "ledger-%03d" % index,
				"flight_id": "flight-%03d" % index,
				"kind": record_kind,
				"aircraft_id": "trainer-a",
				"aircraft_name": "Trainer A",
				"utc": "2026-10-25T10:%02d:00Z" % (index % 60),
				"ended_utc": "2026-10-25T10:%02d:35Z" % (index % 60),
				"outcome": "completed",
				"airborne_seconds": 95.0,
				"takeoffs": 1,
				"full_stops": 1,
				"touch_and_go": 0,
				"max_tas_mps": 18.0,
				"partial": false,
				"timeline": ["Fixture-only timeline"],
			}
			if record_kind != "flight":
				for key: String in ["outcome", "airborne_seconds", "takeoffs", "full_stops", "touch_and_go", "max_tas_mps", "partial", "timeline"]:
					record.erase(key)
				record.metadata = {"ground": true} if record_kind == "crash" else {"cause": "manual_restart"}
			if index == 0:
				record.start_kind = "takeoff"
				record.erase("takeoffs")
				record.metadata = {"events": [
					{"type": "started", "start_kind": "takeoff", "tick": 240},
					{"type": "landing", "kind": "full_stop", "outcome": "success", "reason": "stable_support",
						"tick": 430, "first_contact_tick": 400},
					{"type": "closed", "outcome": "completed", "reason": "full_stop", "tick": 500},
				], "events_omitted": 2}
			history.append(record)
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
			"history_record_count": history.size(),
			"history_flight_count": 50,
			"history_counts": {"flight": 50, "crash": 1, "restart": 1, "gap": 0},
			"has_lifetime_history": true,
			"first_history_date": "2026-10-01", "last_history_date": "2026-10-25",
			"period_label": "This session", "revision": revision,
		}

	func query(aircraft_id: String = "", period: String = "session") -> Dictionary:
		query_log.append([aircraft_id, period])
		var result := values.duplicate(true)
		result.revision = revision
		result.period_label = period
		return result

	func summary(aircraft_id: String = "", period: String = "session") -> Dictionary:
		summary_log.append([aircraft_id, period])
		return values.duplicate(true)

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


class LegacyHudStatisticsService extends RefCounted:
	var query_log: Array = []

	func query(aircraft_id: String = "", period: String = "session") -> Dictionary:
		query_log.append([aircraft_id, period])
		return {"airborne_seconds": 125.0, "landings": 2, "crashes": 1, "restarts": 0, "started": 2, "completed": 1}


var _failures := 0
var _checks := 0


func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	UiTheme.text_scale = 1.0
	await _run()
	print("%d checks, %d failed" % [_checks, _failures])
	print("statistics UI history refresh checks complete")
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
	var saved_values := service.values.duplicate(true)
	service.values.available = false
	screen.call("_refresh")
	_check("unavailable storage is distinct from zero", screen.find_child("AirborneValue", true, false).text == "—"
		and screen.find_child("CompletedValue", true, false).text == "—")
	service.values = saved_values.duplicate(true)
	service.values = {"started": 0, "completed": 0, "landings": 0, "crashes": 0, "restarts": 0,
		"history": [], "has_lifetime_history": true, "tracking_started_utc": "2026-10-01T00:00:00Z"}
	screen.call("_refresh")
	_check("an empty session window with lifetime history says no records are in this view",
		"No flight records in this view." in screen._coverage_label.text)
	service.values.has_lifetime_history = false
	screen.call("_refresh")
	_check("authoritative no-history flag wins over an old tracking timestamp",
		"Tracking begins with your next flight." in screen._coverage_label.text)
	service.values.erase("has_lifetime_history")
	screen.call("_refresh")
	_check("legacy tracking timestamp still indicates existing lifetime history",
		"No flight records in this view." in screen._coverage_label.text)
	service.values.erase("tracking_started_utc")
	screen.call("_refresh")
	_check("tracking-begins copy appears only before lifetime history exists",
		"Tracking begins with your next flight." in screen._coverage_label.text)
	service.values = saved_values
	screen.call("_refresh")
	screen.configure(service, "", "imperial")
	_check("configured imperial statistics speed uses mph", screen._speed(22.0) == "49 mph")
	screen.configure(service, "", "si")
	_check("configured SI statistics speed keeps m/s", screen._speed(22.0) == "22.0 m/s")
	screen.configure(service, "", "metric")
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
		and "Maximum horizontal groundspeed" in _all_text(screen._more_box)
		and "79 km/h" in _all_text(screen._more_box))
	screen.call("_on_history_toggled", true)
	_check("history is bounded to 50 rows per page", screen._history_rows.get_child_count() == 50)
	var newest_row := screen._history_rows.get_child(0) as VBoxContainer
	var newest_toggle := newest_row.get_child(0) as Button
	_check("real service timestamps are preferred in the history row", "2026-10-25 10:00Z" in newest_toggle.text)
	newest_toggle.button_pressed = true
	newest_toggle.toggled.emit(true)
	var newest_detail := _all_text(newest_row)
	_check("history renders bounded metadata events and UTC endpoints instead of fixture timeline",
		"Started (UTC)" in newest_detail and "Ended (UTC)" in newest_detail
		and "Takeoff" in newest_detail and "First contact tick: 400" in newest_detail
		and "More events omitted: 2" in newest_detail and "Fixture-only timeline" not in newest_detail, newest_detail)
	_check("actual start_kind derives takeoffs when no legacy count exists", "Takeoffs 1" in newest_detail)
	var air_start_row: VBoxContainer = screen.call("_history_row", {"kind": "flight", "outcome": "completed",
		"start_kind": "air_start", "airborne_seconds": 30.0}, 1)
	_check("airborne-start history records do not count as takeoffs", "Takeoffs 0" in _all_text(air_start_row))
	air_start_row.free()
	screen.call("_set_history_page", 1)
	await process_frame
	_check("next history page retains the filter and shows the remaining rows",
		screen._history_page == 1 and screen._history_rows.get_child_count() == 2)
	var last_row := screen._history_rows.get_child(0) as VBoxContainer
	var history_toggle := last_row.get_child(0) as Button
	history_toggle.button_pressed = true
	history_toggle.toggled.emit(true)
	_check("crash history records show ground context without fake flight metrics",
		"Ground crash" in history_toggle.text and not history_toggle.text.contains("<1 min")
		and not _all_text(last_row).contains("Takeoffs"))
	var restart_entry := screen._history_rows.get_child(1) as VBoxContainer
	var restart_toggle := restart_entry.get_child(0) as Button
	_check("restart history records show the stored cause without a flight duration",
		"Restart: Manual Restart" in restart_toggle.text and not restart_toggle.text.contains("<1 min"))
	_check("history expansion exposes record details", (last_row.get_child(1) as VBoxContainer).visible)
	screen.call("_on_aircraft_selected", 1)
	_check("aircraft filter queries the selected stable ID", service.query_log.back() == ["trainer-a", "session"])
	screen.call("_on_period_selected", 2)
	_check("period filter can select the counter-reset window", service.query_log.back() == ["trainer-a", "counters"])

	var back_events: Array = []
	screen.back_requested.connect(func() -> void: back_events.append(true))
	(screen.find_child("Back", true, false) as Button).pressed.emit()
	_check("Back returns through the ScreenStack signal", back_events.size() == 1)

	# Cancel is a pure close: no service method is called.
	screen.call("_open_reset", "session", "", "session")
	var dialog: ConfirmationDialog = screen.get("_active_dialog")
	await process_frame
	_check("destructive management starts with Cancel focused", dialog.get_cancel_button().has_focus())
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

	screen.call("_open_reset", "account", "", "counters")
	dialog = screen.get("_active_dialog")
	dialog.call("_on_confirmed")
	_check("pilot counter reset advances the combined account window",
		service.reset_log.size() == 3 and service.reset_log[2] == ["account", ""])
	await process_frame

	screen.call("_open_delete", "trainer-a")
	dialog = screen.get("_active_dialog")
	_check("history deletion preview pins its store revision and exact count",
		dialog._pinned_revision == service.revision and "52 records" in dialog.preview_label.text
		and "50 flights" in dialog.preview_label.text and "1 crash" in dialog.preview_label.text
		and "1 restart" in dialog.preview_label.text and "2026-10-01" in dialog.preview_label.text)
	dialog.scope_check.button_pressed = true
	dialog.call("_on_confirmed")
	_check("history deletion requires confirmation and names its aircraft",
		service.deletion_log == ["trainer-a"])
	await process_frame
	service.values.history_counts.gap = 3
	screen.call("_open_delete", "")
	dialog = screen.get("_active_dialog")
	_check("pilot deletion preview counts coverage gaps that the purge removes",
		"55 records" in dialog.preview_label.text and "3 coverage gaps" in dialog.preview_label.text)
	dialog.call("_on_cancelled")
	await process_frame
	service.values.history_counts.gap = 0

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
	var elapsed_label: Label = manager.frames.flight.values.time.get_parent().get_child(
		manager.frames.flight.values.time.get_index() - 1) as Label
	var airborne_label: Label = manager.frames.session_stats.find_child("SessionAirborneTime", true, false) as Label
	_check("HUD summary prefers the service summary and keeps all three counters visible",
		service.summary_log.back() == ["trainer-a", "session"]
		and manager.frames.session_stats.value_label.visible
		and manager.frames.session_stats.left_value.visible
		and manager.frames.session_stats.right_value.visible
		and airborne_label.text.contains("24:10")
		and elapsed_label.text == "Elapsed sim time" and elapsed_label.tooltip_text == "Elapsed simulation time")
	var legacy_service := LegacyHudStatisticsService.new()
	manager.statistics_service = legacy_service
	manager.refresh_numbers({"telemetry": {}, "battery": {}, "mass_sample": {}, "warnings": PackedStringArray()})
	_check("HUD falls back to query for older service fixtures", legacy_service.query_log.back() == ["trainer-a", "session"]
		and airborne_label.text.contains("2:05"))
	manager.statistics_service = service
	manager.set_widget_option("widget_compact", true)
	manager.refresh_numbers({"telemetry": {}, "battery": {}, "mass_sample": {}, "warnings": PackedStringArray()})
	_check("compact HUD retains session time and all three counters", manager.frames.session_stats.value_label.visible
		and manager.frames.session_stats.left_value.visible and manager.frames.session_stats.right_value.visible
		and airborne_label.visible and airborne_label.text.contains("24:10"))

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

	service.writable = true
	TranslationServer.set_locale("es")
	var spanish_screen: CanvasLayer = StatisticsScreen.new()
	spanish_screen.configure(service, "trainer-b", "auto")
	root.add_child(spanish_screen)
	await process_frame
	_check("Spanish localizes the screen and all-aircraft filter",
		(spanish_screen.find_child("StatisticsTitle", true, false) as Label).text == "Estadísticas"
		and spanish_screen._scope_picker.get_item_text(0) == "Todas las aeronaves"
		and spanish_screen._speed(22.0) == "79 km/h")
	var spanish_back: Array = []
	spanish_screen.back_requested.connect(func() -> void: spanish_back.append(true))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	spanish_screen.get("_screen").call("_unhandled_input", escape)
	_check("Escape routes back from the Spanish keyboard screen", spanish_back.size() == 1)
	spanish_screen.call("_open_reset", "account", "", "counters")
	var spanish_dialog: ConfirmationDialog = spanish_screen.get("_active_dialog")
	await process_frame
	_check("Spanish counter confirmation retains a Cancel-first action", spanish_dialog.title == "¿Reiniciar los contadores?"
		and spanish_dialog.get_cancel_button().has_focus())
	spanish_dialog.call("_on_cancelled")
	await process_frame
	var failed_stop_record := {"kind": "flight", "outcome": "failed_stop", "airborne_seconds": 17.0, "metadata": {}}
	var failed_stop_row: VBoxContainer = spanish_screen.call("_history_row", failed_stop_record, 0)
	_check("history labels failed stop as an uncontrolled stop", tr("Uncontrolled stop") in (failed_stop_row.get_child(0) as Button).text)
	_check("failed stops count as ended flights in fallback history", spanish_screen.call("_closed_count", {"history": [failed_stop_record]}) == 1)
	failed_stop_row.free()
	var airborne_crash_row: VBoxContainer = spanish_screen.call("_history_row", {"kind": "crash", "metadata": {"ground": false}}, 1)
	_check("flight crash history localizes the recorded ground/flight context",
		tr("Flight crash") in (airborne_crash_row.get_child(0) as Button).text)
	airborne_crash_row.free()
	spanish_screen.queue_free()
	TranslationServer.set_locale("en")
	await process_frame
	var sequence_order := StatisticsScreen._newest_first_history([
		{"seq": 1, "id": "old"}, {"seq": 3, "id": "new"}, {"seq": 2, "id": "middle"},
	])
	var fixture_order := StatisticsScreen._newest_first_history([{"id": "first"}, {"id": "second"}])
	_check("history sorts real records newest-first but preserves sequence-free fixture order",
		sequence_order[0].id == "new" and sequence_order[1].id == "middle" and sequence_order[2].id == "old"
		and fixture_order[0].id == "first" and fixture_order[1].id == "second")

	var stack := ScreenStack.new(root)
	var focus_anchor := Control.new()
	focus_anchor.name = "StatisticsStackReturnFocus"
	focus_anchor.focus_mode = Control.FOCUS_ALL
	root.add_child(focus_anchor)
	focus_anchor.grab_focus()
	var stacked_screen: CanvasLayer = StatisticsScreen.new()
	stacked_screen.configure(service, "trainer-a")
	var stacked := stack.push("statistics", stacked_screen, focus_anchor)
	await process_frame
	await process_frame
	_check("CanvasLayer statistics screen is accepted by ScreenStack", stacked and stack.get_screen("statistics") == stacked_screen)
	stacked_screen.back_requested.connect(func() -> void: stack.pop())
	stacked_screen.call("_request_back")
	_check("Back pops the statistics layer and restores opener focus", stack.size() == 0 and focus_anchor.has_focus())
	await process_frame
	await _test_history_refresh()


func _test_history_refresh() -> void:
	# Set the real window after initialization; headless startup otherwise replaces
	# the size assigned in _initialize with its 64x64 default.
	root.size = Vector2i(1920, 1080)
	var service := FakeStatisticsService.new()
	var screen: CanvasLayer = StatisticsScreen.new()
	screen.configure(service, "")
	root.add_child(screen)
	var scroll := screen.find_child("StatisticsScroll", true, false) as ScrollContainer
	if scroll == null:
		_check("history refresh fixture has a scroll container", false)
		screen.queue_free()
		await process_frame
		return
	await _settle_ui()
	_check("history refresh uses the full 1080p screen and its normal scroll layout",
		root.size == Vector2i(1920, 1080) and screen.is_ancestor_of(scroll)
		and Rect2(Vector2.ZERO, Vector2(root.size)).encloses(scroll.get_global_rect()))
	screen.call("_on_history_toggled", true)
	await _settle_ui()
	var legacy_flight_id: String = str(screen.call("_history_record_id", {"kind": "flight", "flight_id": "shared-flight"}))
	var legacy_crash_id: String = str(screen.call("_history_record_id", {"kind": "crash", "flight_id": "shared-flight"}))
	_check("legacy records sharing a flight ID remain kind-distinct",
		not legacy_flight_id.is_empty() and not legacy_crash_id.is_empty() and legacy_flight_id != legacy_crash_id
		and str(screen.call("_history_record_id", {"flight_id": "shared-flight"})).is_empty())
	var original_toggle := _find_history_toggle(screen, "ledger-049")
	if original_toggle == null:
		_check("history refresh fixture contains a stable scrolled record", false)
		screen.queue_free()
		await process_frame
		return
	original_toggle.button_pressed = true
	original_toggle.toggled.emit(true)
	original_toggle.grab_focus()
	await _settle_ui()
	var unchanged_scroll := scroll.scroll_vertical
	var initial_scroll_detail := _scroll_visibility_detail(scroll, original_toggle)
	_check("history refresh fixture focuses a visible row after scrolling",
		unchanged_scroll > 0 and _control_fully_visible_in_scroll(scroll, original_toggle), initial_scroll_detail)
	service.changed.emit() # Same revision and records, as after a successful writer completion.
	await _settle_ui()
	var unchanged_toggle := _find_history_toggle(screen, "ledger-049")
	_check("unchanged changed signal keeps the expanded focused row instance",
		is_instance_valid(original_toggle) and unchanged_toggle == original_toggle
		and original_toggle.has_focus() and _history_toggle_expanded(original_toggle))
	_check("unchanged changed signal preserves the scrolled position",
		scroll.scroll_vertical == unchanged_scroll and _control_fully_visible_in_scroll(scroll, original_toggle),
		"before=%d after=%d %s" % [unchanged_scroll, scroll.scroll_vertical, _scroll_visibility_detail(scroll, original_toggle)])

	var reorder_source := _find_history_toggle(screen, "ledger-000")
	if reorder_source != null:
		reorder_source.button_pressed = true
		reorder_source.toggled.emit(true)
		reorder_source.grab_focus()
	await _settle_ui()

	var history: Array = service.values.history.duplicate(true)
	history.insert(0, {"id": "ledger-new", "kind": "flight", "aircraft_id": "trainer-a",
		"aircraft_name": "Trainer A", "utc": "2026-10-26T10:00:00Z", "outcome": "completed",
		"airborne_seconds": 95.0, "start_kind": "takeoff"})
	service.values.history = history
	service.revision += 1
	service.changed.emit()
	await _settle_ui()
	var reordered_toggle := _find_history_toggle(screen, "ledger-000")
	_check("reordered history restores expansion and focus by ledger ID",
		reordered_toggle != null and reordered_toggle != original_toggle
		and reordered_toggle.has_focus() and _history_toggle_expanded(reordered_toggle))
	_check("reordered focused history row remains visible after layout settles",
		reordered_toggle != null and _control_fully_visible_in_scroll(scroll, reordered_toggle),
		_scroll_visibility_detail(scroll, reordered_toggle))

	history = service.values.history.duplicate(true)
	for index in range(history.size()):
		if str(history[index].get("id", "")) == "ledger-000":
			history.remove_at(index)
			break
	service.values.history = history
	service.revision += 1
	service.changed.emit()
	await process_frame
	_check("removed focused history record falls back to the history control",
		_find_history_toggle(screen, "ledger-000") == null and screen._history_button.has_focus())

	var offpage_toggle := _find_history_toggle(screen, "ledger-049")
	if offpage_toggle == null:
		_check("off-page focus fixture has a last row on page one", false)
		screen.queue_free()
		await process_frame
		return
	offpage_toggle.button_pressed = true
	offpage_toggle.toggled.emit(true)
	offpage_toggle.grab_focus()
	history = service.values.history.duplicate(true)
	history.insert(0, {"id": "ledger-newer-1", "kind": "restart", "reason": "manual_restart"})
	history.insert(0, {"id": "ledger-newer-2", "kind": "restart", "reason": "manual_restart"})
	service.values.history = history
	service.revision += 1
	service.changed.emit()
	await process_frame
	_check("off-page focused history record falls back to the history control",
		_find_history_toggle(screen, "ledger-049") == null and screen._history_button.has_focus())
	screen.call("_set_history_page", 1)
	var returned_toggle := _find_history_toggle(screen, "ledger-049")
	_check("off-page expansion remains keyed to its ledger ID",
		returned_toggle != null and _history_toggle_expanded(returned_toggle))

	screen.call("_set_history_page", 0)
	var filter_toggle := _find_history_toggle(screen, "ledger-new")
	if filter_toggle != null:
		filter_toggle.button_pressed = true
		filter_toggle.toggled.emit(true)
	screen.call("_on_aircraft_selected", 1)
	var filtered_toggle := _find_history_toggle(screen, "ledger-new")
	_check("aircraft filter context rebuilds rows even when history values match",
		filter_toggle != null and filtered_toggle != null and filtered_toggle != filter_toggle
		and _history_toggle_expanded(filtered_toggle))
	screen.configure(service, "trainer-a", "imperial")
	var imperial_toggle := _find_history_toggle(screen, "ledger-new")
	_check("unit context rebuilds rows without discarding expansion state",
		imperial_toggle != null and imperial_toggle != filtered_toggle and _history_toggle_expanded(imperial_toggle))
	var locale_toggle := imperial_toggle
	TranslationServer.set_locale("es")
	service.changed.emit()
	await process_frame
	var translated_toggle := _find_history_toggle(screen, "ledger-new")
	_check("locale context rebuilds translated history rows",
		translated_toggle != null and translated_toggle != locale_toggle and _history_toggle_expanded(translated_toggle))
	TranslationServer.set_locale("en")
	screen._period_picker.grab_focus()
	history = service.values.history.duplicate(true)
	for index in range(history.size()):
		if str(history[index].get("id", "")) == "ledger-new":
			history[index].outcome = "in_progress"
			break
	service.values.history = history
	service.revision += 1
	service.changed.emit()
	await process_frame
	_check("changed history refresh does not steal focus from a filter",
		screen._period_picker.has_focus())
	screen.queue_free()
	await process_frame


func _find_history_toggle(screen: CanvasLayer, record_id: String) -> Button:
	for row: Node in screen._history_rows.get_children():
		if str(row.get_meta("statistics_history_id", "")) == record_id and row.get_child_count() > 0:
			return row.get_child(0) as Button
	return null


func _history_toggle_expanded(toggle: Button) -> bool:
	if not is_instance_valid(toggle):
		return false
	var row := toggle.get_parent()
	return row != null and row.get_child_count() > 1 and (row.get_child(1) as Control).visible


func _settle_ui(frames: int = 5) -> void:
	for _frame in frames:
		await process_frame


func _control_fully_visible_in_scroll(scroll: ScrollContainer, control: Control) -> bool:
	if scroll == null or not is_instance_valid(control):
		return false
	var scroll_rect: Rect2 = scroll.get_global_rect()
	var control_rect: Rect2 = control.get_global_rect()
	return control_rect.position.y >= scroll_rect.position.y - 1.0 \
		and control_rect.end.y <= scroll_rect.end.y + 1.0


func _scroll_visibility_detail(scroll: ScrollContainer, control: Control) -> String:
	if scroll == null or not is_instance_valid(control):
		return "scroll or control invalid"
	var bar := scroll.get_v_scroll_bar()
	var ancestors := PackedStringArray()
	var current: Node = scroll
	while current != null:
		if current is Control:
			ancestors.append("%s=%s" % [current.name, (current as Control).get_global_rect()])
		current = current.get_parent()
	return "scroll=%d max=%.1f page=%.1f row=%s ancestors=%s" % [
		scroll.scroll_vertical, bar.max_value, bar.page, control.get_global_rect(), " | ".join(ancestors)]


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
