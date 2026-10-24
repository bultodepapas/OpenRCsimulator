# O9 Battery (BAT-15, docs/plans/battery-realism.md §6.2): the flight pack as a transmitter's telemetry screen shows
# it. Every number is a BatterySensors reading (sampled volts and amps, used mAh, a mAh-based remaining %), never the
# model's true charge. Compact (one line) in the Pilot preset; detailed with a 60 s V/A sparkline while the Telemetry
# overlay is shown (Full, Developer). The overlay manager hides it when the aircraft has no dynamic battery.
extends "res://render/overlays/overlay_frame.gd"

const Sensors := preload("res://render/overlays/battery_sensors.gd")

const ROW_SIZE := 18
## Fixed text columns: the box keeps its size while the numbers change (no jitter at 10 Hz).
const COLUMN_WIDTH := 108.0
const COMPACT_WIDTH := 312.0
const USED_WIDTH := 150.0
const PERCENT_WIDTH := 52.0
const BAR_SIZE := Vector2(116, 12)
const SPARK_SIZE := Vector2(132, 34)
## Smallest vertical span of a sparkline, so sensor quantization steps never fill the box as noise.
const SPARK_MIN_SPAN_V := 0.5
const SPARK_MIN_SPAN_A := 2.0
const VOLT_COLOR := UiTheme.TEXT
const AMP_COLOR := UiTheme.FOCUS
const CHEMISTRY_NAMES := { lipo = "LiPo", lihv = "LiHV", liion = "Li-ion", lifepo4 = "LiFe", nimh = "NiMH" }
const CAUTION_ALARMS := ["cell_warning", "used_capacity"]
const DANGER_ALARMS := ["exhausted", "cell_critical", "lvc"]

## Detailed layout shown (else the one-line compact layout).
var detailed := false
var compact_label: Label
var detail: VBoxContainer
## Value labels by key: pack_v, cell_avg, cell_min, current, power, temperature, used, percent.
var values := {}
var value_rows: Array[HBoxContainer] = []
var bar: Control
var spark_v: Control
var spark_a: Control
var lvc_chip: PanelContainer
var lvc_label: Label
var _chip_hard := -1 # the LVC chip's style: -1 none yet, 0 soft cut (caution), 1 hard cut (danger)
## The last BatterySensors reading shown.
var reading: Dictionary = Sensors.empty()
var _text_key: Array = []
var _bar_key: Array = []
var _plotted_v := PackedFloat64Array()
var _plotted_a := PackedFloat64Array()


func _init() -> void:
	super("battery", tr("Battery"))
	var header := title_label.get_parent()
	lvc_chip = PanelContainer.new()
	lvc_chip.name = "Lvc"
	lvc_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvc_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvc_label = text_label(tr("LVC"), 12, UiTheme.PANEL)
	lvc_chip.add_child(lvc_label)
	lvc_chip.visible = false
	header.add_child(lvc_chip)
	header.move_child(lvc_chip, close_button.get_index())

	compact_label = text_label("–", VALUE_SIZE, UiTheme.TEXT)
	compact_label.name = "Compact"
	compact_label.custom_minimum_size.x = COMPACT_WIDTH
	body.add_child(compact_label)

	detail = VBoxContainer.new()
	detail.name = "Detail"
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_constant_override("separation", 2)
	body.add_child(detail)
	value_rows.append(_value_row(["pack_v", "cell_avg", "cell_min"]))
	value_rows.append(_value_row(["current", "power", "temperature"]))

	var gauge := _row("Gauge", 8)
	values.used = _value("used", USED_WIDTH)
	gauge.add_child(values.used)
	bar = Control.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = BAR_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.draw.connect(_draw_bar)
	gauge.add_child(bar)
	values.percent = _value("percent", PERCENT_WIDTH)
	values.percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gauge.add_child(values.percent)

	var trend := _row("Trend", 6)
	trend.add_child(text_label("V", LABEL_SIZE, VOLT_COLOR))
	spark_v = _spark("VoltageTrend", "history_v", VOLT_COLOR, SPARK_MIN_SPAN_V)
	trend.add_child(spark_v)
	trend.add_child(text_label("A", LABEL_SIZE, AMP_COLOR))
	spark_a = _spark("CurrentTrend", "history_a", AMP_COLOR, SPARK_MIN_SPAN_A)
	trend.add_child(spark_a)
	var caption := text_label(tr("last 60 s"), 12, UiTheme.TEXT_2)
	caption.name = "TrendCaption"
	detail.add_child(caption)
	set_detailed(false)
	refresh(Sensors.empty(), "metric")


## Compact (Pilot) or detailed (with the Telemetry overlay) layout.
func set_detailed(on: bool) -> void:
	if detailed != on:
		_text_key.clear()
	detailed = on
	compact_label.visible = not on
	detail.visible = on


## r: BatterySensors.update() output; system: a resolved unit system (temperature in °F for imperial, as EdgeTX).
func refresh(r: Dictionary, system: String) -> void:
	reading = r
	if detailed:
		_refresh_graphics()
	var next_text_key: Array = [system, TranslationServer.get_locale(), detailed]
	for field: String in ["valid", "series", "parallel", "chemistry", "capacity_mah", "pack_voltage_v", "cell_avg_v",
			"cell_min_v", "current_a", "power_w", "temperature_c", "used_mah", "remaining_pct", "esc_state"]:
		var value: Variant = r.get(field)
		next_text_key.append(null if typeof(value) == TYPE_FLOAT and not is_finite(value) else value)
	if next_text_key == _text_key:
		return
	_text_key = next_text_key
	title_label.text = title_for(r)
	var esc := str(r.get("esc_state", ""))
	lvc_chip.visible = esc in Sensors.LVC_STATES
	if lvc_chip.visible and _chip_hard != int(esc == "hard_cut"):
		_style_chip(esc == "hard_cut")
	if not r.get("valid", false):
		compact_label.text = "–"
		for key: String in values:
			values[key].text = "–"
	else:
		compact_label.text = compact_text(r)
		if not detailed:
			return
		var cell_avg := float(r.get("cell_avg_v", NAN))
		var cell_min := float(r.get("cell_min_v", NAN))
		var capacity := float(r.get("capacity_mah", NAN))
		var remaining := float(r.get("remaining_pct", NAN))
		values.pack_v.text = _fixed(float(r.get("pack_voltage_v", NAN)), 2, " V")
		values.cell_avg.text = tr("%s V/cell") % ("%.2f" % cell_avg) if is_finite(cell_avg) else ""
		values.cell_min.text = tr("min %s") % ("%.2f V" % cell_min) if is_finite(cell_min) else ""
		values.current.text = _fixed(float(r.get("current_a", NAN)), 1, " A")
		values.power.text = _fixed(float(r.get("power_w", NAN)), 0, " W")
		values.temperature.text = temperature_text(float(r.get("temperature_c", NAN)), system)
		values.used.text = "%d / %d mAh" % [int(r.get("used_mah", 0)), roundi(capacity)] if is_finite(capacity) \
			else "%d mAh" % int(r.get("used_mah", 0))
		values.percent.text = "%d %%" % roundi(remaining) if is_finite(remaining) else ""
	# A missing sensor hides its value, and a row with nothing to show hides entirely.
	for key: String in values:
		values[key].visible = values[key].text != ""
	for row in value_rows:
		row.visible = row.get_children().any(func(label: Control) -> bool: return label.visible)
	bar.visible = is_finite(float(r.get("remaining_pct", NAN)))


## Graphs have independent invalidation; changing temperature or units does not repaint 60 s of history.
func _refresh_graphics() -> void:
	var remaining := float(reading.get("remaining_pct", NAN))
	var next_bar: Array = [clampf(remaining, 0.0, 100.0) if is_finite(remaining) else null,
		alarm_color(reading.get("alarms", []))]
	if next_bar != _bar_key:
		_bar_key = next_bar
		bar.queue_redraw()
	var volts: PackedFloat64Array = reading.get("history_v", PackedFloat64Array())
	var amps: PackedFloat64Array = reading.get("history_a", PackedFloat64Array())
	if not _same_history(volts, _plotted_v):
		_plotted_v = volts.duplicate()
		spark_v.queue_redraw()
	if not _same_history(amps, _plotted_a):
		_plotted_a = amps.duplicate()
		spark_a.queue_redraw()


## Fast native equality for normal samples, with stable missing-value gaps (NaN != NaN).
static func _same_history(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a == b: return true
	if a.size() != b.size(): return false
	for i in a.size():
		if a[i] != b[i] and not (is_nan(a[i]) and is_nan(b[i])): return false
	return true


## "BATTERY · 4S 3200 LiPo": the overlay name and, when the pack says, its short label.
static func title_for(r: Dictionary) -> String:
	var title := TranslationServer.translate("Battery").to_upper()
	var pack := pack_label(r)
	return title if pack.is_empty() else "%s · %s" % [title, pack]


## "4S 3200 LiPo", "4S2P 8400 Li-ion"; "" when the pack gives no cell count.
static func pack_label(r: Dictionary) -> String:
	var series := int(r.get("series", 0))
	if series <= 0:
		return ""
	var parts := PackedStringArray(["%dS%s" % [series, "%dP" % int(r.get("parallel", 0)) if int(r.get("parallel", 0)) > 1 else ""]])
	var capacity := float(r.get("capacity_mah", NAN))
	if is_finite(capacity):
		parts.append("%d" % roundi(capacity))
	var chemistry := str(r.get("chemistry", ""))
	if CHEMISTRY_NAMES.has(chemistry):
		parts.append(CHEMISTRY_NAMES[chemistry])
	return " ".join(parts)


## The Pilot preset's one line: "14.6 V · 38.4 A · 1874 mAh · 41 %"; unknown readings are left out.
static func compact_text(r: Dictionary) -> String:
	if not r.get("valid", false):
		return "–"
	var parts := PackedStringArray()
	var volts := float(r.get("pack_voltage_v", NAN))
	if is_finite(volts):
		parts.append("%.1f V" % volts)
	var amps := float(r.get("current_a", NAN))
	if is_finite(amps):
		parts.append("%.1f A" % amps)
	parts.append("%d mAh" % int(r.get("used_mah", 0)))
	var remaining := float(r.get("remaining_pct", NAN))
	if is_finite(remaining):
		parts.append("%d %%" % roundi(remaining))
	return " · ".join(parts)


## Pack temperature in the overlay's units: °F for imperial (as EdgeTX's imperial setting), °C otherwise.
static func temperature_text(celsius: float, system: String) -> String:
	if not is_finite(celsius):
		return ""
	if system == "imperial":
		return "%d °F" % roundi(celsius * 1.8 + 32.0)
	return "%d °C" % roundi(celsius)


## Developer-only model truth for the Diagnostics overlay, never a pilot overlay: the true state of charge of the
## average and the weakest cell. "" without a modelled SOC.
static func truth_text(state: Dictionary) -> String:
	var soc: Variant = state.get("soc")
	if not state.get("ok", false) or typeof(soc) != TYPE_FLOAT:
		return ""
	var text := TranslationServer.translate("True SOC %s") % ("%.1f %%" % (100.0 * float(soc)))
	var weak: Variant = state.get("soc_weak")
	if typeof(weak) == TYPE_FLOAT:
		text += " · " + TranslationServer.translate("weakest cell %s") % ("%.1f %%" % (100.0 * float(weak)))
	return text


## Sparkline points for `series` (oldest first) in a box: the newest sample at the right edge, 60 s across, scaled
## to the visible range (at least `min_span` tall). Unknown samples are skipped; never more than HISTORY_SIZE points.
static func spark_points(series: PackedFloat64Array, box: Vector2, min_span: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := series.size()
	var start := maxi(0, n - Sensors.HISTORY_SIZE)
	var lo := INF
	var hi := -INF
	for i in range(start, n):
		if is_finite(series[i]):
			lo = minf(lo, series[i])
			hi = maxf(hi, series[i])
	if lo > hi or box.x <= 0.0 or box.y <= 2.0:
		return out
	if hi - lo < min_span:
		var mid := 0.5 * (lo + hi)
		lo = mid - 0.5 * min_span
		hi = mid + 0.5 * min_span
	var dx := box.x / float(Sensors.HISTORY_SIZE - 1)
	for i in range(start, n):
		if not is_finite(series[i]):
			continue
		var y := (box.y - 1.0) - (series[i] - lo) / (hi - lo) * (box.y - 2.0)
		out.append(Vector2(box.x - float(n - 1 - i) * dx, y))
	return out


## `value` with `decimals` places and its unit; "" when the sensor has no reading.
static func _fixed(value: float, decimals: int, unit: String) -> String:
	if not is_finite(value):
		return ""
	match decimals:
		0:
			return "%d%s" % [roundi(value), unit]
		1:
			return "%.1f%s" % [value, unit]
	return "%.2f%s" % [value, unit]


## Colour for the remaining bar: danger, caution or normal from the active alarms (text carries the meaning too).
static func alarm_color(alarms: Array) -> Color:
	if alarms.any(func(a: String) -> bool: return a in DANGER_ALARMS):
		return UiTheme.ERROR
	if alarms.any(func(a: String) -> bool: return a in CAUTION_ALARMS):
		return UiTheme.FOCUS
	return UiTheme.TEXT


func _draw_bar() -> void:
	var box := Rect2(Vector2.ZERO, bar.size)
	bar.draw_rect(box, Color(UiTheme.TEXT_2, 0.25))
	var remaining := float(reading.get("remaining_pct", NAN))
	if is_finite(remaining):
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * clampf(remaining, 0.0, 100.0) / 100.0, bar.size.y)),
			alarm_color(reading.get("alarms", [])))
	bar.draw_rect(box, Color(UiTheme.TEXT_2, 0.6), false, 1.0)


func _draw_spark(canvas: Control, key: String, color: Color, min_span: float) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(UiTheme.TEXT_2, 0.35), false, 1.0)
	var points := spark_points(reading.get(key, PackedFloat64Array()), canvas.size, min_span)
	if points.size() >= 2:
		canvas.draw_polyline(points, color, 1.5, true)


func _style_chip(hard: bool) -> void:
	_chip_hard = int(hard)
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.DANGER.pressed if hard else UiTheme.FOCUS
	box.set_corner_radius_all(4)
	box.content_margin_left = 6
	box.content_margin_right = 6
	lvc_chip.add_theme_stylebox_override("panel", box)
	lvc_label.add_theme_color_override("font_color", UiTheme.TEXT if hard else UiTheme.PANEL)


func _row(node_name: String, separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", separation)
	detail.add_child(row)
	return row


func _value_row(keys: Array) -> HBoxContainer:
	var row := _row("Values%d" % (value_rows.size() + 1), 8)
	for key: String in keys:
		values[key] = _value(key, COLUMN_WIDTH)
		row.add_child(values[key])
	return row


func _value(key: String, width: float) -> Label:
	var label := text_label("–", ROW_SIZE, UiTheme.TEXT)
	label.name = key.capitalize().replace(" ", "")
	label.custom_minimum_size.x = width
	return label


func _spark(node_name: String, key: String, color: Color, min_span: float) -> Control:
	var canvas := Control.new()
	canvas.name = node_name
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.custom_minimum_size = SPARK_SIZE
	canvas.draw.connect(_draw_spark.bind(canvas, key, color, min_span))
	return canvas
