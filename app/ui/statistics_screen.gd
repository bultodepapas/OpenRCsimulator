# UI-FS-05/06: player-facing statistics, scoped rollups, bounded history pages and safe management entry points.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const ResetDialog := preload("res://ui/statistics_reset_dialog.gd")

signal back_requested

const PERIODS := ["session", "lifetime", "counters"]
const PERIOD_LABELS := ["This session", "Lifetime history", "Since counter reset"]
const HISTORY_PAGE_SIZE := 50

var _service: Object
var _screen: Control
var _panel: PanelContainer
var _filter_row: BoxContainer
var _body_grid: GridContainer
var _scope_picker: OptionButton
var _period_picker: OptionButton
var _metadata_label: Label
var _coverage_label: Label
var _touchdown_label: Label
var _clean_stop_label: Label
var _more_button: Button
var _more_box: VBoxContainer
var _history_button: Button
var _history_box: VBoxContainer
var _history_rows: VBoxContainer
var _history_page_label: Label
var _previous_page: Button
var _next_page: Button
var _manage_note: Label
var _session_reset_button: Button
var _aircraft_reset_button: Button
var _pilot_reset_button: Button
var _aircraft_delete_button: Button
var _pilot_delete_button: Button
var _history: Array = []
var _stats: Dictionary = {}
var _aircraft_ids: Array[String] = [""]
var _aircraft_names: Array[String] = ["All aircraft"]
var _selected_aircraft := ""
var _period := "session"
var _history_page := 0
var _more_open := false
var _history_open := false
var _refreshing := false
var _active_dialog: ConfirmationDialog


func _init() -> void:
	name = "StatisticsScreen"
	var surface := Screen.mount(self, "StatisticsSurface")
	_screen = surface
	surface.escape_before_gui = true
	surface.dismiss_option_popup_first = true
	surface.close_requested.connect(_request_back)
	surface.dim(0.56, "StatisticsDim")
	var center: CenterContainer = surface.center(18.0)
	_panel = PanelContainer.new()
	_panel.name = "StatisticsPanel"
	_panel.theme_type_variation = "Sidebar"
	center.add_child(_panel)
	_build()
	surface.resized.connect(_resize_layout)
	surface.theme_changed.connect(_resize_layout)


func configure(statistics_service: Object, initial_aircraft: String = "") -> void:
	_service = statistics_service
	_selected_aircraft = initial_aircraft
	_build_aircraft_choices()
	_select_aircraft(initial_aircraft)
	_refresh()


func _build() -> void:
	var shell := VBoxContainer.new()
	shell.name = "StatisticsShell"
	shell.add_theme_constant_override("separation", 12)
	_panel.add_child(shell)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	shell.add_child(header)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	header.add_child(title_column)
	var title := Widgets.label(tr("Statistics"), "TitleLabel", true, false)
	title.name = "StatisticsTitle"
	title_column.add_child(title)
	_metadata_label = Widgets.label("", "SecondaryLabel", true, false)
	_metadata_label.name = "StatisticsMetadata"
	title_column.add_child(_metadata_label)
	var back := Widgets.button(tr("Back"), "QuietButton", "Back")
	back.custom_minimum_size.x = 140
	back.pressed.connect(_request_back)
	header.add_child(back)

	_filter_row = BoxContainer.new()
	_filter_row.name = "StatisticsFilters"
	_filter_row.add_theme_constant_override("separation", 18)
	shell.add_child(_filter_row)
	var scope_column := VBoxContainer.new()
	scope_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scope_column.add_child(Widgets.label(tr("Aircraft scope"), "SecondaryLabel", false, false))
	_scope_picker = OptionButton.new()
	_scope_picker.name = "AircraftScope"
	_scope_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scope_picker.item_selected.connect(_on_aircraft_selected)
	scope_column.add_child(_scope_picker)
	_filter_row.add_child(scope_column)
	var period_column := VBoxContainer.new()
	period_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	period_column.add_child(Widgets.label(tr("Statistics period"), "SecondaryLabel", false, false))
	_period_picker = OptionButton.new()
	_period_picker.name = "StatisticsPeriod"
	_period_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for period_label: String in PERIOD_LABELS:
		_period_picker.add_item(tr(period_label))
	_period_picker.item_selected.connect(_on_period_selected)
	period_column.add_child(_period_picker)
	_filter_row.add_child(period_column)

	var scroll := ScrollContainer.new()
	scroll.name = "StatisticsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_ALL
	shell.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "StatisticsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	_body_grid = GridContainer.new()
	_body_grid.name = "SummaryCards"
	_body_grid.columns = 3
	_body_grid.add_theme_constant_override("h_separation", 12)
	_body_grid.add_theme_constant_override("v_separation", 12)
	_body_grid.add_child(_summary_card("Airborne time", "AirborneValue", ""))
	_body_grid.add_child(_summary_card("Completed flights", "CompletedValue", ""))
	_body_grid.add_child(_summary_card("Successful landings", "LandingsValue", ""))
	content.add_child(_body_grid)

	var outcome_section := _section(content, "Landing outcomes")
	_touchdown_label = Widgets.label("", "BodyLabel", true, false)
	_touchdown_label.name = "TouchdownSuccess"
	outcome_section.add_child(_touchdown_label)
	_clean_stop_label = Widgets.label("", "BodyLabel", true, false)
	_clean_stop_label.name = "CleanStopFlights"
	outcome_section.add_child(_clean_stop_label)
	_coverage_label = Widgets.label("", "SecondaryLabel", true, false)
	_coverage_label.name = "StatisticsCoverage"
	outcome_section.add_child(_coverage_label)

	var more_section := _section(content, "More statistics")
	_more_button = Widgets.button(tr("More statistics"), "", "MoreStatistics")
	_more_button.toggle_mode = true
	_more_button.toggled.connect(_on_more_toggled)
	more_section.add_child(_more_button)
	_more_box = VBoxContainer.new()
	_more_box.name = "MoreStatisticsDetails"
	_more_box.add_theme_constant_override("separation", 4)
	_more_box.visible = false
	more_section.add_child(_more_box)

	var history_section := _section(content, "Flight history")
	_history_button = Widgets.button(tr("Flight history"), "", "FlightHistory")
	_history_button.toggle_mode = true
	_history_button.toggled.connect(_on_history_toggled)
	history_section.add_child(_history_button)
	_history_box = VBoxContainer.new()
	_history_box.name = "FlightHistoryDetails"
	_history_box.visible = false
	_history_box.add_theme_constant_override("separation", 8)
	history_section.add_child(_history_box)
	_history_rows = VBoxContainer.new()
	_history_rows.name = "FlightHistoryRows"
	_history_rows.add_theme_constant_override("separation", 6)
	_history_box.add_child(_history_rows)
	var page_controls := HBoxContainer.new()
	page_controls.add_theme_constant_override("separation", 12)
	_previous_page = Widgets.button(tr("Previous"), "QuietButton", "PreviousHistoryPage")
	_previous_page.pressed.connect(func() -> void: _set_history_page(_history_page - 1))
	page_controls.add_child(_previous_page)
	_history_page_label = Widgets.label("", "SecondaryLabel", false, false)
	_history_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_controls.add_child(_history_page_label)
	_next_page = Widgets.button(tr("Next"), "QuietButton", "NextHistoryPage")
	_next_page.pressed.connect(func() -> void: _set_history_page(_history_page + 1))
	page_controls.add_child(_next_page)
	_history_box.add_child(page_controls)

	var management := _section(content, "Manage statistics")
	_manage_note = Widgets.label("", "SecondaryLabel", true, false)
	_manage_note.name = "StatisticsManagementStatus"
	management.add_child(_manage_note)
	var counter_heading := Widgets.label(tr("Manage counters"), "SectionLabel", false, false)
	management.add_child(counter_heading)
	_session_reset_button = Widgets.button(tr("Reset session counters…"), "QuietButton", "ResetSessionCounters")
	_session_reset_button.pressed.connect(func() -> void: _open_reset("session", "", "session"))
	management.add_child(_session_reset_button)
	_aircraft_reset_button = Widgets.button(tr("Reset this aircraft's counters…"), "QuietButton", "ResetAircraftCounters")
	_aircraft_reset_button.pressed.connect(func() -> void: _open_reset("aircraft", _selected_aircraft, "counters"))
	management.add_child(_aircraft_reset_button)
	_pilot_reset_button = Widgets.button(tr("Reset pilot counters…"), "QuietButton", "ResetPilotCounters")
	_pilot_reset_button.pressed.connect(func() -> void: _open_reset("account", "", "counters"))
	management.add_child(_pilot_reset_button)
	var history_heading := Widgets.label(tr("Manage history"), "SectionLabel", false, false)
	management.add_child(history_heading)
	_aircraft_delete_button = Widgets.button(tr("Delete this aircraft's history…"), "DestructiveButton", "DeleteAircraftHistory")
	_aircraft_delete_button.pressed.connect(func() -> void: _open_delete(_selected_aircraft))
	management.add_child(_aircraft_delete_button)
	_pilot_delete_button = Widgets.button(tr("Delete all pilot history…"), "DestructiveButton", "DeletePilotHistory")
	_pilot_delete_button.pressed.connect(func() -> void: _open_delete(""))
	management.add_child(_pilot_delete_button)
	_refresh_manage_controls()


func _summary_card(caption: String, value_name: String, note: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = value_name + "Card"
	card.theme_type_variation = "Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(220, 112)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	card.add_child(column)
	column.add_child(Widgets.label(tr(caption), "SectionLabel", true, false))
	var value := Widgets.label("—", "CardTitleLabel", true, false)
	value.name = value_name
	column.add_child(value)
	if not note.is_empty():
		column.add_child(Widgets.label(tr(note), "SecondaryLabel", true, false))
	return card


func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 5)
	section.add_child(Widgets.label(tr(title), "SectionLabel", false, false))
	parent.add_child(section)
	return section


func _ready() -> void:
	_build_aircraft_choices()
	_refresh()
	_resize_layout()
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		_scope_picker.get_popup().force_native = true
		_period_picker.get_popup().force_native = true
	_scope_picker.grab_focus.call_deferred()


func _resize_layout() -> void:
	if not is_inside_tree():
		return
	var available := _screen.size - Vector2(36.0, 36.0)
	_panel.custom_minimum_size = Vector2(minf(1500.0, available.x), minf(1040.0, available.y))
	var stacked := available.x < 820.0 or UiTheme.text_scale > 1.25
	_filter_row.vertical = stacked
	_body_grid.columns = 1 if stacked else 3
	for child: Control in _body_grid.get_children():
		child.custom_minimum_size.x = 0 if stacked else minf(220.0, (available.x - 80.0) / 3.0)


func _build_aircraft_choices() -> void:
	if _scope_picker == null:
		return
	_scope_picker.clear()
	_aircraft_ids = [""]
	_aircraft_names = [tr("All aircraft")]
	_scope_picker.add_item(tr("All aircraft"))
	if _service != null and _service.has_method("aircraft_choices"):
		var choices: Variant = _service.call("aircraft_choices")
		if choices is Array:
			for choice: Variant in choices:
				if not choice is Dictionary:
					continue
				var id := str(choice.get("id", ""))
				if id.is_empty() or _aircraft_ids.has(id):
					continue
				var display_name := str(choice.get("name", id))
				_aircraft_ids.append(id)
				_aircraft_names.append(display_name)
				_scope_picker.add_item(display_name)
	if not _selected_aircraft.is_empty() and not _aircraft_ids.has(_selected_aircraft):
		_aircraft_ids.append(_selected_aircraft)
		_aircraft_names.append(_selected_aircraft)
		_scope_picker.add_item(_selected_aircraft)
	_select_aircraft(_selected_aircraft)


func _select_aircraft(id: String) -> void:
	_selected_aircraft = id if _aircraft_ids.has(id) else ""
	var index := _aircraft_ids.find(_selected_aircraft)
	if _scope_picker != null and index >= 0:
		_scope_picker.select(index)


func _on_aircraft_selected(index: int) -> void:
	if index < 0 or index >= _aircraft_ids.size():
		return
	_selected_aircraft = _aircraft_ids[index]
	_history_page = 0
	_refresh()


func _on_period_selected(index: int) -> void:
	if index < 0 or index >= PERIODS.size():
		return
	_period = PERIODS[index]
	_history_page = 0
	_refresh()


func _on_more_toggled(open: bool) -> void:
	_more_open = open
	_more_box.visible = open
	_more_button.text = tr("Fewer statistics") if open else tr("More statistics")
	if open:
		_fill_more_statistics()


func _on_history_toggled(open: bool) -> void:
	_history_open = open
	_history_box.visible = open
	_history_button.text = tr("Hide flight history") if open else tr("Flight history")
	if open:
		_render_history()


func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	if _service != null and _service.has_method("query"):
		var result: Variant = _service.call("query", _selected_aircraft, _period)
		_stats = result if result is Dictionary else {}
	else:
		_stats = {}
	_history = _stats.get("history", []) if _stats.get("history", []) is Array else []
	if _period_picker != null:
		_period_picker.select(PERIODS.find(_period))
	_update_summary()
	if _more_open:
		_fill_more_statistics()
	if _history_open:
		_render_history()
	_refresh_manage_controls()
	_refreshing = false


func _update_summary() -> void:
	var aircraft_text := tr("All aircraft") if _selected_aircraft.is_empty() else _selected_aircraft_name()
	var period_text := tr(str(_stats.get("period_label", tr(PERIOD_LABELS[PERIODS.find(_period)]))))
	_metadata_label.text = "%s · %s · %s" % [tr("Local pilot"), aircraft_text, period_text]
	_metadata_label.tooltip_text = tr("Lifetime history remains available after counter resets.")
	var airborne := _number(_stats.get("airborne_seconds", 0.0))
	var started := _count(_stats.get("started", 0))
	var completed := _count(_stats.get("completed", 0))
	var landings := _count(_stats.get("landings", 0))
	var card_values := {
		"AirborneValue": _duration(airborne),
		"CompletedValue": str(completed),
		"LandingsValue": "%d (%d %s · %d %s)" % [landings, _count(_stats.get("full_stops", 0)), tr("stops"),
			_count(_stats.get("touch_and_go", 0)), tr("touch-and-go")],
	}
	for key: String in card_values:
		var label := _panel.find_child(key, true, false) as Label
		if label != null:
			label.text = card_values[key]
	var resolved := landings + _count(_stats.get("failed_landings", 0))
	var rate := float(_stats.get("landing_rate", -1.0))
	if resolved > 0 and is_finite(rate) and rate >= 0.0:
		_touchdown_label.text = tr("Touchdown success: %d / %d resolved touchdowns · %d%%") % [landings, resolved, roundi(rate * 100.0)]
	else:
		_touchdown_label.text = tr("Touchdown success: no resolved touchdowns yet")
	var closed := _closed_count(_stats)
	if closed >= 0:
		_clean_stop_label.text = tr("Flights brought to a clean stop: %d / %d ended flights") % [completed, closed]
	else:
		_clean_stop_label.text = tr("Flights brought to a clean stop: %d · ended-flight total unavailable") % completed
	var current_streak := _count(_stats.get("current_streak", 0))
	var best_streak := _count(_stats.get("best_streak", 0))
	var crash_free := _duration(_number(_stats.get("current_clean_seconds", 0.0)))
	var best_crash_free := _duration(_number(_stats.get("best_clean_seconds", 0.0)))
	var empty := started == 0 and completed == 0 and landings == 0 and _count(_stats.get("crashes", 0)) == 0 \
		and _count(_stats.get("restarts", 0)) == 0 and _history.is_empty()
	var coverage := _coverage_text(_stats)
	if empty:
		coverage = tr("Tracking begins with your next flight.")
	elif coverage.is_empty():
		coverage = tr("Completed in a row: %d · best %d · crash-free airborne time: %s · best %s") \
			% [current_streak, best_streak, crash_free, best_crash_free]
	else:
		coverage += "\n" + tr("Completed in a row: %d · best %d · crash-free airborne time: %s · best %s") \
			% [current_streak, best_streak, crash_free, best_crash_free]
	var note := str(_service.get("note")) if _service != null else ""
	if not note.is_empty():
		coverage += "\n" + tr(note)
	_coverage_label.text = coverage
	

func _fill_more_statistics() -> void:
	for child: Node in _more_box.get_children():
		child.queue_free()
	var average := float(_stats.get("average_seconds", -1.0))
	var average_count := _count(_stats.get("average_count", 0))
	_add_detail(_more_box, tr("Flights started"), str(_count(_stats.get("started", 0))))
	_add_detail(_more_box, tr("Average airborne duration"), _duration(average) if average >= 0.0 else "—")
	_add_detail(_more_box, tr("Average duration includes %d closed flights") % average_count, "")
	_add_detail(_more_box, tr("Maximum valid airspeed (TAS)"), _speed(_stats.get("max_tas_mps", NAN)))
	_add_detail(_more_box, tr("Maximum horizontal groundspeed"), _speed(_stats.get("max_groundspeed_mps", NAN)))
	_add_detail(_more_box, tr("Full-stop landings"), str(_count(_stats.get("full_stops", 0))))
	_add_detail(_more_box, tr("Touch-and-go landings"), str(_count(_stats.get("touch_and_go", 0))))
	_add_detail(_more_box, tr("Failed touchdown episodes"), str(_count(_stats.get("failed_landings", 0))))
	_add_detail(_more_box, tr("Unknown touchdown episodes"), str(_count(_stats.get("unknown_landings", 0))))
	_add_detail(_more_box, tr("Crashes"), str(_count(_stats.get("crashes", 0))))
	_add_detail(_more_box, tr("Restarts"), str(_count(_stats.get("restarts", 0))))
	_add_detail(_more_box, tr("Active flights"), _active_text(_stats.get("active", 0)))
	_add_detail(_more_box, tr("Partial records"), _partial_text(_stats.get("partial", 0)))
	_add_detail(_more_box, tr("Touchdown success counts resolved surface contacts; the clean-stop fraction includes the end of each flight."), "")


func _add_detail(parent: VBoxContainer, caption: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Widgets.label(caption, "SecondaryLabel", true, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if not value.is_empty():
		var value_label := Widgets.label(value, "BodyLabel", true, false)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
	parent.add_child(row)


func _render_history() -> void:
	if _history_rows == null:
		return
	for child: Node in _history_rows.get_children():
		child.queue_free()
	var page_count := maxi(1, ceili(float(_history.size()) / float(HISTORY_PAGE_SIZE)))
	_history_page = clampi(_history_page, 0, page_count - 1)
	var start := _history_page * HISTORY_PAGE_SIZE
	var finish := mini(_history.size(), start + HISTORY_PAGE_SIZE)
	if _history.is_empty():
		_history_rows.add_child(Widgets.label(tr("No flight records in this view."), "SecondaryLabel", true, false))
	else:
		for index in range(start, finish):
			var record: Variant = _history[index]
			if record is Dictionary:
				_history_rows.add_child(_history_row(record, index))
	_history_page_label.text = tr("Page %d of %d · %d records") % [_history_page + 1, page_count, _history.size()]
	_previous_page.disabled = _history_page <= 0
	_next_page.disabled = _history_page >= page_count - 1


func _history_row(record: Dictionary, index: int) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var outcome := str(record.get("outcome", record.get("status", "Unknown"))).replace("_", " ").capitalize()
	var date := _record_date(record)
	if date.is_empty(): date = tr("Flight %d") % (index + 1)
	var aircraft := str(record.get("aircraft_name", record.get("aircraft_id", _selected_aircraft_name())))
	var duration := _duration(_number(record.get("airborne_seconds", NAN)))
	var toggle := Widgets.button("%s · %s · %s · %s" % [date, aircraft, duration, tr(outcome)], "QuietButton", "HistoryRow%d" % index)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.toggle_mode = true
	row.add_child(toggle)
	var detail := VBoxContainer.new()
	detail.visible = false
	detail.add_theme_constant_override("separation", 2)
	row.add_child(detail)
	var breakdown := tr("Takeoffs %d · Full stops %d · Touch-and-go %d") % [
		_count(record.get("takeoffs", 0)), _count(record.get("full_stops", 0)), _count(record.get("touch_and_go", 0))
	]
	_add_detail(detail, breakdown, "")
	_add_detail(detail, tr("Max valid airspeed (TAS)"), _speed(record.get("max_tas_mps", NAN)))
	_add_detail(detail, tr("Coverage"), _coverage_text(record))
	var scenario := str(record.get("scenario", ""))
	if not scenario.is_empty(): _add_detail(detail, tr("Scenario"), tr(scenario))
	var events: Variant = record.get("timeline", record.get("events", []))
	if events is Array and not events.is_empty():
		var timeline := " · ".join(PackedStringArray(events.map(func(event: Variant) -> String: return tr(str(event)))))
		_add_detail(detail, tr("Events"), timeline)
	toggle.toggled.connect(func(open: bool) -> void:
		detail.visible = open
		toggle.text = ("⌄ " if open else "› ") + "%s · %s · %s · %s" % [date, aircraft, duration, tr(outcome)]
	)
	return row


func _set_history_page(page: int) -> void:
	var page_count := maxi(1, ceili(float(_history.size()) / float(HISTORY_PAGE_SIZE)))
	_history_page = clampi(page, 0, page_count - 1)
	_render_history()


func _refresh_manage_controls() -> void:
	if _session_reset_button == null:
		return
	var can_manage := _service != null and _service.has_method("can_manage") and bool(_service.call("can_manage"))
	var has_aircraft := not _selected_aircraft.is_empty()
	for button: Button in [_session_reset_button, _pilot_reset_button, _pilot_delete_button]:
		button.disabled = not can_manage
	for button: Button in [_aircraft_reset_button, _aircraft_delete_button]:
		button.disabled = not can_manage or not has_aircraft
	if can_manage:
		_manage_note.text = tr("Counters and history management are available while no flight is active.")
	else:
		var note := str(_service.get("note")) if _service != null else ""
		_manage_note.text = tr(note) if not note.is_empty() else tr("End the active flight before changing counters or history.")
	

func _open_reset(scope: String, aircraft_id: String, period: String) -> void:
	_open_management_dialog("reset", scope, aircraft_id, period)


func _open_delete(aircraft_id: String) -> void:
	_open_management_dialog("delete", "history", aircraft_id, "lifetime")


func _open_management_dialog(action: String, scope: String, aircraft_id: String, period: String) -> void:
	if _service == null or not _service.has_method("can_manage") or not bool(_service.call("can_manage")):
		_refresh_manage_controls()
		return
	var preview: Dictionary = _service.call("query", aircraft_id, period)
	_active_dialog = ResetDialog.new()
	_active_dialog.theme = _screen.theme
	add_child(_active_dialog)
	_active_dialog.connect("operation_completed", func(_succeeded: bool) -> void:
		_active_dialog.queue_free()
		_active_dialog = null
		_build_aircraft_choices()
		_refresh()
	)
	_active_dialog.connect("operation_cancelled", func() -> void:
		if is_instance_valid(_active_dialog):
			_active_dialog.queue_free()
		_active_dialog = null
	)
	_active_dialog.call("configure", _service, action, scope, aircraft_id, period, preview)
	_active_dialog.popup_centered()


func _request_back() -> void:
	back_requested.emit()


func _selected_aircraft_name() -> String:
	var index := _aircraft_ids.find(_selected_aircraft)
	return _aircraft_names[index] if index >= 0 and index < _aircraft_names.size() else _selected_aircraft


func _record_date(record: Dictionary) -> String:
	for key: String in ["started_at", "timestamp", "ended_at", "date"]:
		var value := str(record.get(key, ""))
		if not value.is_empty(): return value
	return ""


func _closed_count(data: Dictionary) -> int:
	var value: Variant = data.get("closed", null)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return _count(value)
	var history: Variant = data.get("history", [])
	if not history is Array:
		return -1
	var closed := 0
	for record: Variant in history:
		if not record is Dictionary: continue
		var outcome := str(record.get("outcome", record.get("status", ""))).to_lower()
		if outcome in ["completed", "crashed", "restarted", "abandoned", "damaged_stop", "interrupted"]:
			closed += 1
	return closed


func _coverage_text(data: Dictionary) -> String:
	var partial := _partial_text(data.get("partial", 0))
	var active := _active_text(data.get("active", 0))
	var pieces: PackedStringArray = []
	if not partial.is_empty(): pieces.append(partial)
	if not active.is_empty(): pieces.append(active)
	return " · ".join(pieces)


func _partial_text(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return tr("Some records are partial.") if value else ""
	var count := _count(value)
	return tr("Partial records: %d") % count if count > 0 else ""


func _active_text(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return tr("A flight is in progress.") if value else ""
	var count := _count(value)
	return tr("Flights in progress: %d") % count if count > 0 else ""


func _speed(value: Variant) -> String:
	var speed := _number(value)
	return "—" if speed < 0.0 else "%.1f m/s" % speed


func _duration(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "—"
	var total := maxi(0, roundi(seconds))
	if total < 60: return tr("<1 min")
	var hours := floori(float(total) / 3600.0)
	var minutes := int((total % 3600) / 60)
	if hours > 0: return tr("%d h %02d min") % [hours, minutes]
	return tr("%d min") % minutes


func _number(value: Variant) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var number := float(value)
		return number if is_finite(number) else -1.0
	return -1.0


func _count(value: Variant) -> int:
	var number := _number(value)
	return maxi(0, roundi(number)) if number >= 0.0 else 0
