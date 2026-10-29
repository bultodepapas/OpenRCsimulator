# UI-FS-06: counter reset and history deletion are separate, revision-pinned confirmations.
extends ConfirmationDialog

const UiTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")

signal operation_completed(succeeded: bool)
signal operation_cancelled

var preview_label: Label
var status_label: Label
var scope_check: CheckBox
var _service: Object
var _action := "reset"
var _scope := "session"
var _aircraft_id := ""
var _aircraft_display_name := ""
var _period := "session"
var _pinned_revision := -1
var _preview: Dictionary = {}
var _ready_to_commit := false


func _init() -> void:
	name = "StatisticsResetDialog"
	exclusive = true
	dialog_autowrap = true
	dialog_hide_on_ok = false
	theme = UiTheme.build()
	min_size = Vector2i(520, 260)
	get_ok_button().name = "ConfirmStatisticsChange"
	get_cancel_button().name = "CancelStatisticsChange"
	get_cancel_button().text = tr("Cancel")
	get_cancel_button().theme_type_variation = "QuietButton"
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_cancelled)
	close_requested.connect(_on_cancelled)
	about_to_popup.connect(_focus_cancel)
	_build_body()


func configure(service: Object, action: String, scope: String, aircraft_id: String,
		period: String, preview: Dictionary, aircraft_display_name: String = "") -> void:
	_service = service
	_action = "delete" if action == "delete" else "reset"
	_scope = scope
	_aircraft_id = aircraft_id
	_aircraft_display_name = aircraft_display_name
	_period = period
	_preview = preview.duplicate(true)
	_pinned_revision = int(_preview.get("revision", -1))
	_ready_to_commit = true
	_refresh_text()


func _build_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "StatisticsConfirmationScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(360, 112)
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	preview_label = Widgets.label("", "SecondaryLabel", true, false)
	preview_label.name = "StatisticsPreview"
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(preview_label)
	status_label = Widgets.label("", "ErrorLabel", true, false)
	status_label.name = "StatisticsConfirmationStatus"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(status_label)
	scope_check = CheckBox.new()
	scope_check.name = "ConfirmDeletionScope"
	scope_check.text = tr("I understand this history removal cannot be undone.")
	scope_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope_check.toggled.connect(func(on: bool) -> void:
		if _action == "delete": get_ok_button().disabled = not on
	)
	content.add_child(scope_check)
	get_ok_button().theme_type_variation = "DestructiveButton"
	get_ok_button().disabled = true


func _refresh_text() -> void:
	if _action == "delete":
		title = tr("Delete flight history?")
		ok_button_text = tr("Delete history")
		scope_check.visible = true
		scope_check.set_pressed_no_signal(false)
		get_ok_button().disabled = true
		var target := tr("All aircraft combined") if _aircraft_id.is_empty() else _aircraft_name(_preview, _aircraft_id)
		var include_gaps := _aircraft_id.is_empty()
		var visible_records := _history_count(_preview)
		var types := _history_type_counts(_preview, visible_records, include_gaps)
		var records := visible_records + (int(types.gap) if include_gaps else 0)
		var breakdown_parts := PackedStringArray([
			_typed_count(types.flight, "flight", "flights"),
			_typed_count(types.crash, "crash", "crashes"),
			_typed_count(types.restart, "restart", "restarts"),
		])
		if include_gaps and int(types.gap) > 0:
			breakdown_parts.append(_typed_count(types.gap, "coverage gap", "coverage gaps"))
		var breakdown := " · ".join(breakdown_parts)
		var other_records := maxi(0, records - types.flight - types.crash - types.restart)
		if include_gaps:
			other_records = maxi(0, other_records - int(types.gap))
		if other_records > 0:
			breakdown += " · " + _typed_count(other_records, "other record", "other records")
		var span := _date_span(_preview)
		var text := tr("Remove %d records for %s (%s), covering %s, with %s airborne time.") \
			% [records, target, breakdown, span, _duration(float(_preview.get("airborne_seconds", 0.0)))]
		text += "\n" + tr("This cannot be undone. Preferences, aircraft, Workshop builds, controller profiles and flight recordings stay in place.")
		preview_label.text = text
	else:
		title = tr("Reset counters?")
		ok_button_text = tr("Reset counters")
		scope_check.visible = false
		get_ok_button().disabled = false
		var target := _reset_target()
		var text := tr("Reset counters for %s? This starts a new counter window; saved flight history stays available.") % target
		text += "\n" + tr("Flights %d · Completed %d · Crashes %d · Restarts %d · Airborne %s") % [
			_count(_preview.get("started", 0)), _count(_preview.get("completed", 0)),
			_count(_preview.get("crashes", 0)), _count(_preview.get("restarts", 0)),
			_duration(float(_preview.get("airborne_seconds", 0.0)))
		]
		preview_label.text = text
	get_cancel_button().grab_focus.call_deferred()


func _on_confirmed() -> void:
	if not _ready_to_commit or _service == null or not _service.has_method("can_manage") \
			or not bool(_service.call("can_manage")):
		status_label.text = _service_note(tr("Counters and history cannot be changed right now."))
		return
	var latest: Dictionary = _service.call("query", _aircraft_id, _period)
	var latest_revision := int(latest.get("revision", -1))
	if latest_revision != _pinned_revision:
		_preview = latest.duplicate(true)
		_pinned_revision = latest_revision
		status_label.text = tr("Statistics changed. Review the updated preview and confirm again.")
		_refresh_text()
		status_label.text = tr("Statistics changed. Review the updated preview and confirm again.")
		get_cancel_button().grab_focus.call_deferred()
		return
	if _action == "delete" and not scope_check.button_pressed:
		status_label.text = tr("Confirm that you want to remove the history shown above.")
		get_cancel_button().grab_focus.call_deferred()
		return
	var succeeded := false
	if _action == "delete":
		succeeded = bool(_service.call("delete_history", _aircraft_id))
	else:
		succeeded = bool(_service.call("reset_counters", _scope, _aircraft_id))
	if succeeded:
		_ready_to_commit = false
		operation_completed.emit(true)
		hide()
		return
	status_label.text = _service_note(tr("The change could not be saved. Your statistics are still available."))
	get_cancel_button().grab_focus.call_deferred()


func _on_cancelled() -> void:
	_ready_to_commit = false
	operation_cancelled.emit()
	hide()


func _focus_cancel() -> void:
	get_cancel_button().grab_focus.call_deferred()


func _reset_target() -> String:
	match _scope:
		"session": return tr("This session, all aircraft")
		"aircraft": return _aircraft_name(_preview, _aircraft_id)
		"account", "pilot": return tr("All aircraft combined")
	return tr("This session, all aircraft")


func _service_note(fallback: String) -> String:
	var value: Variant = _service.get("note") if _service != null else null
	if value != null and not str(value).is_empty():
		return tr(str(value))
	return fallback


func _aircraft_name(data: Dictionary, fallback: String) -> String:
	if not _aircraft_display_name.is_empty():
		return _aircraft_display_name
	var name_value := str(data.get("aircraft_name", ""))
	return name_value if not name_value.is_empty() else fallback


func _history_count(data: Dictionary) -> int:
	if data.get("history_record_count") is int or data.get("history_record_count") is float:
		return _count(data.get("history_record_count"))
	if data.get("history_count") is int or data.get("history_count") is float:
		return _count(data.get("history_count"))
	var history: Variant = data.get("history", [])
	if history is Array:
		return history.size()
	return _count(data.get("started", 0)) + _count(data.get("crashes", 0)) + _count(data.get("restarts", 0))


func _history_type_counts(data: Dictionary, record_count: int, include_gaps := false) -> Dictionary:
	var counts := {"flight": 0, "crash": 0, "restart": 0, "gap": 0}
	var source: Variant = data.get("history_counts", {})
	if source is Dictionary and (source.has("flight") or source.has("crash") or source.has("restart")):
		for kind: String in counts:
			counts[kind] = _count(source.get(kind, 0))
		if not include_gaps:
			counts.gap = 0
		return counts
	var history: Variant = data.get("history", [])
	if history is Array and not history.is_empty():
		for record: Variant in history:
			if not record is Dictionary:
				continue
			var kind := str(record.get("kind", ""))
			if kind.is_empty() and (record.has("flight_id") or record.has("outcome")):
				kind = "flight"
			if counts.has(kind):
				counts[kind] = int(counts[kind]) + 1
		if not include_gaps:
			counts.gap = 0
		return counts
	counts.flight = _count(data.get("history_flight_count", data.get("started", 0)))
	counts.crash = _count(data.get("crashes", 0))
	counts.restart = _count(data.get("restarts", 0))
	var history_counts_value: Variant = data.get("history_counts", {})
	counts.gap = _count(history_counts_value.get("gap", 0)) if include_gaps and history_counts_value is Dictionary else 0
	var known := int(counts.flight) + int(counts.crash) + int(counts.restart)
	if known > record_count:
		# Preserve a trustworthy total when older summaries lack per-type history counts.
		counts.flight = mini(int(counts.flight), record_count)
		counts.crash = mini(int(counts.crash), maxi(0, record_count - int(counts.flight)))
		counts.restart = mini(int(counts.restart), maxi(0, record_count - int(counts.flight) - int(counts.crash)))
	return counts


func _typed_count(count: int, singular: String, plural: String) -> String:
	return "%d %s" % [count, tr(singular if count == 1 else plural)]


func _date_span(data: Dictionary) -> String:
	var first := str(data.get("first_history_date", ""))
	var last := str(data.get("last_history_date", ""))
	if not first.is_empty() or not last.is_empty():
		return first if first == last or last.is_empty() else (last if first.is_empty() else "%s – %s" % [first, last])
	var history: Variant = data.get("history", [])
	var earliest := ""
	var latest := ""
	if history is Array:
		for record: Variant in history:
			if not record is Dictionary:
				continue
			var date := str(record.get("utc", record.get("started_at", record.get("timestamp",
				record.get("ended_utc", record.get("ended_at", ""))))))
			if date.is_empty():
				continue
			if earliest.is_empty() or date < earliest: earliest = date
			if latest.is_empty() or date > latest: latest = date
		if not earliest.is_empty():
			return earliest if earliest == latest else "%s – %s" % [earliest, latest]
	return tr("tracked history")


static func _count(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return maxi(0, value)
	if typeof(value) == TYPE_FLOAT and is_finite(value):
		return maxi(0, roundi(value))
	return 0


func _duration(seconds: float) -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "—"
	var total := maxi(0, roundi(seconds))
	if total < 60:
		return tr("<1 min")
	var hours := floori(float(total) / 3600.0)
	var minutes := int((total % 3600) / 60)
	if hours > 0:
		return tr("%d h %02d min") % [hours, minutes]
	return tr("%d min") % minutes
