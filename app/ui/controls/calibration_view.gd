# UI-15-UX-01: the shared radio calibration presentation, hosted by the preflight modal (radio_calibration_setup.gd)
# and the in-flight card (calibration_card.gd). It reads the wizard (rc_calibration.gd) and the latest raw axes the
# host passes in; it never owns or advances the wizard. Stick mode is presentation only and never saved.
# Every node ignores the mouse and never takes focus, so the in-flight card keeps the flight's input.
extends VBoxContainer

const UiTheme := preload("res://ui/ui_theme.gd")
const RcInput := preload("res://input/rc_input.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")
const ChannelBarView := preload("res://ui/controls/channel_bar.gd")

## Progress strip: the wizard's steps followed by the host's throttle verification.
const STRIP_STEPS := ["rest", "throttle", "roll", "pitch", "yaw", "verify"]
const STRIP_NAMES := {
	rest = "Rest", throttle = "Throttle", roll = "Roll", pitch = "Pitch", yaw = "Yaw", verify = "Verify",
}
const FUNCTION_NAMES := { throttle = "Throttle", roll = "Roll", pitch = "Pitch", yaw = "Yaw" }
const FUNCTION_KEYS := ["throttle", "roll", "pitch", "yaw"]
## Target-zone words, translated once per locale.
const TARGET_WORDS := {
	right = "RIGHT", left = "LEFT", back = "BACK", forward = "FORWARD", full = "FULL", low = "LOW", centre = "CENTRE",
}
const CHECKLIST_LINES := [
	"EdgeTX/OpenTX: select USB Joystick (Classic) on the model, turn RF off, calibrate the sticks on the radio first, and use expo either on the radio or in the simulator, not both.",
	"JETI: use USB joystick mode and check the stick mode.",
]
## Presentation only (the wizard decides acceptance): once a sweep has travelled at least this far and the stick
## comes back by RETURN_MARGIN, the target moves on (throttle FULL → LOW, opposite endpoint → centre).
const PRESENTED_SWEEP := 0.25
const RETURN_MARGIN := 0.1
## Raw travel of a full throttle sweep before calibration (−1 … +1).
const RAW_THROTTLE_SPAN := 2.0

var title_label: Label
var device_label: Label
var step_label: Label
var instruction_label: Label
var detected_label: Label
var error_label: Label
var error_banner: PanelContainer
var result_label: Label
var checklist: PanelContainer
var verify_panel: VBoxContainer
var verify_bar: ChannelBarView
var left_gimbal: GimbalView
var right_gimbal: GimbalView
var strip: StepStrip
var channel_bars: Array[ChannelBarView] = []

## Presentation mode: 2 (default) puts throttle/yaw on the left stick; 1 swaps throttle and pitch.
var stick_mode := 2:
	set(value):
		var mode := 1 if value == 1 else 2
		if stick_mode != mode:
			stick_mode = mode
			_apply_layout()
			_invalidate()

var _left_column: VBoxContainer
var _full_check: CheckRow
var _low_check: CheckRow
var _verify_full_seen := false
var _verify_low_after_full := false
var _baseline := PackedFloat64Array()
var _have_baseline := false
var _moving_axis := -1
# Inputs of the last shown texts; texts are rebuilt only when one changes (or the locale/theme changes).
var _shown_step := -2
var _shown_phase := ""
var _shown_error := "\u0001"
var _shown_detected := -2
var _bar_functions := PackedStringArray()
var _compact := false
var _words := {}
# One function's reading from the last _read() (filled without allocation).
var _reading_value := 0.0
var _reading_live := false
var _reading_axis := -1
var _envelope_lo := 0.0
var _envelope_hi := 0.0
var _envelope_known := false


func _init() -> void:
	name = "CalibrationView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 16)
	add_child(header)
	title_label = _label("TitleLabel", "Title")
	title_label.text = "Radio calibration"
	title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	header.add_child(title_label)
	device_label = _label("SecondaryLabel", "Device")
	device_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	device_label.size_flags_vertical = Control.SIZE_SHRINK_END
	device_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	device_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	device_label.clip_text = true
	header.add_child(device_label)
	strip = StepStrip.new()
	strip.name = "Progress"
	add_child(strip)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 28)
	add_child(body)
	_left_column = VBoxContainer.new()
	_left_column.name = "Transmitter"
	_left_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_theme_constant_override("separation", 8)
	body.add_child(_left_column)
	var gimbal_row := HBoxContainer.new()
	gimbal_row.name = "Gimbals"
	gimbal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gimbal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gimbal_row.add_theme_constant_override("separation", 28)
	_left_column.add_child(gimbal_row)
	left_gimbal = GimbalView.new()
	left_gimbal.name = "LeftGimbal"
	gimbal_row.add_child(left_gimbal)
	right_gimbal = GimbalView.new()
	right_gimbal.name = "RightGimbal"
	gimbal_row.add_child(right_gimbal)
	step_label = _label("SectionLabel", "Step")
	_left_column.add_child(step_label)
	instruction_label = _label("", "Prompt")
	instruction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_left_column.add_child(instruction_label)
	detected_label = _label("SecondaryLabel", "Detected")
	detected_label.visible = false
	_left_column.add_child(detected_label)
	error_banner = PanelContainer.new()
	error_banner.name = "ErrorBanner"
	error_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	error_banner.add_theme_stylebox_override("panel", _banner_style())
	error_banner.visible = false
	_left_column.add_child(error_banner)
	error_label = _label("ErrorLabel", "Error")
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	error_banner.add_child(error_label)
	verify_panel = VBoxContainer.new()
	verify_panel.name = "Verify"
	verify_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	verify_panel.add_theme_constant_override("separation", 6)
	verify_panel.visible = false
	_left_column.add_child(verify_panel)
	verify_bar = ChannelBarView.new()
	verify_bar.name = "VerifyThrottle"
	verify_bar.one_ended = true
	verify_bar.highlight = ChannelBarView.Highlight.ASSIGNED
	verify_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verify_panel.add_child(verify_bar)
	var checks := HBoxContainer.new()
	checks.name = "VerifyChecks"
	checks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checks.add_theme_constant_override("separation", 24)
	verify_panel.add_child(checks)
	_full_check = CheckRow.new()
	_full_check.name = "ReachedFull"
	checks.add_child(_full_check)
	_low_check = CheckRow.new()
	_low_check.name = "BackToLow"
	checks.add_child(_low_check)
	result_label = _label("SecondaryLabel", "Result")
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.visible = false
	_left_column.add_child(result_label)
	checklist = PanelContainer.new()
	checklist.name = "Checklist"
	checklist.theme_type_variation = "Notice"
	checklist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_column.add_child(checklist)
	var checklist_column := VBoxContainer.new()
	checklist_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	checklist_column.add_theme_constant_override("separation", 4)
	checklist.add_child(checklist_column)
	var checklist_title := _label("SectionLabel", "ChecklistTitle")
	checklist_title.text = "Before you start"
	checklist_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	checklist_column.add_child(checklist_title)
	for index in CHECKLIST_LINES.size():
		var line := _label("SecondaryLabel", "ChecklistLine%d" % index)
		line.text = CHECKLIST_LINES[index]
		line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		checklist_column.add_child(line)

	var monitor := VBoxContainer.new()
	monitor.name = "ChannelMonitor"
	monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	monitor.add_theme_constant_override("separation", 4)
	body.add_child(monitor)
	var monitor_title := _label("SectionLabel", "ChannelMonitorTitle")
	monitor_title.text = "Channel monitor"
	monitor_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	monitor.add_child(monitor_title)
	for axis in RcInput.AXES:
		var bar := ChannelBarView.new()
		bar.name = "Channel%d" % axis
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		monitor.add_child(bar)
		channel_bars.append(bar)
	_bar_functions.resize(RcInput.AXES)
	_bar_functions.fill("\u0001")
	_baseline.resize(RcInput.AXES)
	_apply_layout()


## Gimbal functions per stick mode, as [[left x, left y], [right x, right y]].
static func gimbal_functions(mode: int) -> Array:
	if mode == 1:
		return [["yaw", "pitch"], ["roll", "throttle"]]
	return [["yaw", "throttle"], ["roll", "pitch"]]


## The pilot's saved overlay stick mode, read-only, from the flight (`overlay_settings`) or the shell
## (`preferences.hud`) above `node`; Mode 2 when neither is found. Calibration never writes it.
static func presentation_stick_mode(node: Node) -> int:
	var current := node.get_parent() if node != null else null
	while current != null:
		var settings: Variant = current.get("overlay_settings")
		if typeof(settings) != TYPE_DICTIONARY:
			var preferences: Variant = current.get("preferences")
			settings = preferences.get("hud") if typeof(preferences) == TYPE_DICTIONARY else null
		if typeof(settings) == TYPE_DICTIONARY and typeof(settings.get("stick_mode")) in [TYPE_INT, TYPE_FLOAT]:
			return 1 if int(settings.stick_mode) == 1 else 2
		current = current.get_parent()
	return 2


## The axis with the largest deviation from `reference`, if at least `threshold`; otherwise −1.
static func moving_axis(axes: PackedFloat64Array, reference: PackedFloat64Array, threshold: float) -> int:
	var best := -1
	var best_delta := threshold
	for axis in mini(axes.size(), reference.size()):
		var delta := absf(axes[axis] - reference[axis])
		if is_finite(delta) and delta >= best_delta:
			best = axis
			best_delta = delta
	return best


func set_device_name(text: String) -> void:
	device_label.text = text


## Host-owned throttle FULL → LOW verification after the wizard finished.
func set_verify_state(full_seen: bool, low_after_full: bool) -> void:
	_verify_full_seen = full_seen
	_verify_low_after_full = low_after_full


func set_result(text: String) -> void:
	result_label.text = text
	result_label.visible = not text.is_empty()


func current_moving_axis() -> int:
	return _moving_axis


## Refresh every widget from the wizard and the latest raw axes (RcInput.AXES values, −1…+1).
func update(wizard: Variant, axes: PackedFloat64Array) -> void:
	if wizard == null:
		return
	var complete := bool(wizard.done())
	var have_axes := axes.size() == RcInput.AXES
	# Moving-axis reference: the rest sample once taken, else the first reading of this wizard.
	if bool(wizard.has_rest()):
		for axis in RcInput.AXES:
			_baseline[axis] = float(wizard.rest_value(axis))
		_have_baseline = true
	elif not _have_baseline and have_axes:
		for axis in RcInput.AXES:
			_baseline[axis] = axes[axis]
		_have_baseline = true
	_moving_axis = moving_axis(axes, _baseline, Calibration.DIRECTION_THRESHOLD) if have_axes and _have_baseline else -1
	var target: Dictionary = wizard.requested_target()
	_update_gimbals(wizard, axes, complete, target)
	_update_channels(wizard, axes)
	_update_verify(wizard, axes, complete)
	_sync_texts(wizard, axes, complete, target)
	strip.set_state(STRIP_STEPS.size() - 1 if complete else int(wizard.step), complete and _verify_low_after_full)


func _update_gimbals(wizard: Variant, axes: PackedFloat64Array, complete: bool, target: Dictionary) -> void:
	var layout := gimbal_functions(stick_mode)
	var phase := str(target.get("phase", ""))
	var function := str(target.get("function", ""))
	var direction := str(target.get("direction", ""))
	for index in 2:
		var gimbal: GimbalView = left_gimbal if index == 0 else right_gimbal
		var x_function: String = layout[index][0]
		var y_function: String = layout[index][1]
		var y_throttle := y_function == "throttle"
		_read(wizard, x_function, axes)
		var x := _reading_value
		var live := _reading_live
		var x_lo := _envelope_lo
		var x_hi := _envelope_hi
		var x_known := _envelope_known
		_read(wizard, y_function, axes)
		var y := GimbalView.throttle_to_y(_reading_value) if y_throttle else _reading_value
		live = live or _reading_live
		var y_lo := _envelope_lo
		var y_hi := _envelope_hi
		var y_known := _envelope_known
		if y_throttle:
			y_lo = GimbalView.throttle_to_y(_envelope_hi)
			y_hi = GimbalView.throttle_to_y(_envelope_lo)
		gimbal.set_stick(Vector2(x, y), live)
		if x_known or y_known:
			if not x_known:
				x_lo = x
				x_hi = x
			if not y_known:
				y_lo = y
				y_hi = y
			gimbal.set_envelope(Rect2(x_lo, y_lo, x_hi - x_lo, y_hi - y_lo))
		else:
			gimbal.clear_envelope()
		_place_target(gimbal, wizard, phase, function, direction, x_function, y_function, axes, complete)


## The requested zone for this gimbal, or none when the step concerns the other stick.
func _place_target(gimbal: GimbalView, wizard: Variant, phase: String, function: String, direction: String,
		x_function: String, y_function: String, axes: PackedFloat64Array, complete: bool) -> void:
	var y_throttle := y_function == "throttle"
	var rest_y := 1.0 if y_throttle else 0.0
	var no_point := GimbalView.NO_TARGET
	if complete:
		if not y_throttle or _verify_low_after_full:
			gimbal.clear_target()
			return
		var full_first := not _verify_full_seen
		gimbal.set_target(Vector2(0.0, -1.0 if full_first else 1.0), Vector2(0.0, 1.0 if full_first else -1.0))
		gimbal.target_label = _word("full" if full_first else "low")
		return
	if phase == "rest":
		gimbal.set_target(Vector2(0.0, rest_y), no_point)
		gimbal.target_label = _word("low" if y_throttle else "centre")
		return
	if function != x_function and function != y_function:
		gimbal.clear_target()
		return
	if function == "throttle":
		_read(wizard, "throttle", axes)
		var returning := _envelope_known and _swept_and_returning(_envelope_hi, _reading_value)
		gimbal.set_target(Vector2(0.0, 1.0 if returning else -1.0), Vector2(0.0, -1.0 if returning else 1.0))
		gimbal.target_label = _word("low" if returning else "full")
		return
	if phase == "opposite":
		_read(wizard, function, axes)
		if _envelope_known and _swept_and_returning(-_envelope_lo, -_reading_value):
			# Opposite endpoint reached and leaving it: the wizard now wants the stick back at centre.
			gimbal.set_target(Vector2(0.0, rest_y) if function == x_function else Vector2.ZERO, no_point)
			gimbal.target_label = _word("centre")
			return
	var side_sign := 1.0 if direction == "right" or direction == "back" else -1.0
	var point := Vector2(side_sign, rest_y) if function == x_function else Vector2(0.0, side_sign)
	gimbal.set_target(point, Vector2(0.0, rest_y) if function == x_function else Vector2.ZERO)
	gimbal.target_label = _word(direction)


## True once a sweep reached at least PRESENTED_SWEEP and the stick has come back from its furthest point.
static func _swept_and_returning(furthest: float, now: float) -> bool:
	return furthest >= PRESENTED_SWEEP and now <= furthest - RETURN_MARGIN


func _word(key: String) -> String:
	return str(_words.get(key, ""))


## Reads one function into the _reading_* and _envelope_* fields: assigned channels through their calibration,
## the current step's channel as raw travel from rest, others at their rest position (not live).
func _read(wizard: Variant, function: String, axes: PackedFloat64Array) -> void:
	var throttle := function == "throttle"
	_reading_value = 0.0
	_reading_live = false
	_reading_axis = -1
	_envelope_known = false
	_envelope_lo = 0.0
	_envelope_hi = 0.0
	if axes.size() != RcInput.AXES or function.is_empty() or function == "rest":
		return
	var axis := int(wizard.assigned_axis(function))
	if axis >= 0:
		var channel: Dictionary = wizard.profile[function]
		_reading_value = RcInput.normalize_throttle(axes[axis], channel) if throttle else RcInput.normalize(axes[axis], channel)
		_reading_live = true
		_reading_axis = axis
		_envelope_known = true
		_envelope_lo = 0.0 if throttle else -1.0
		_envelope_hi = 1.0
		return
	if not bool(wizard.has_rest()) or str(wizard.current_function()) != function:
		return
	if throttle:
		axis = _throttle_candidate(wizard, axes)
		if axis < 0:
			return
		var rest := float(wizard.rest_value(axis))
		_reading_value = clampf(absf(axes[axis] - rest) / RAW_THROTTLE_SPAN, 0.0, 1.0)
		_reading_live = true
		_reading_axis = axis
		_envelope_known = true
		_envelope_lo = 0.0
		_envelope_hi = clampf(maxf(absf(float(wizard.sweep_min(axis)) - rest), absf(float(wizard.sweep_max(axis)) - rest))
			/ RAW_THROTTLE_SPAN, 0.0, 1.0)
		return
	axis = int(wizard.held_axis())
	if axis >= 0:
		var rest := float(wizard.rest_value(axis))
		var held := float(wizard.held_sign())
		_reading_value = clampf((axes[axis] - rest) * held, -1.0, 1.0)
		_reading_live = true
		_reading_axis = axis
		var a := clampf((float(wizard.sweep_min(axis)) - rest) * held, -1.0, 1.0)
		var b := clampf((float(wizard.sweep_max(axis)) - rest) * held, -1.0, 1.0)
		_envelope_known = true
		_envelope_lo = minf(a, b)
		_envelope_hi = maxf(a, b)
		return
	# Before the held direction is confirmed, the largest unassigned deflection previews toward the requested side:
	# the wizard defines the held direction as positive.
	axis = _unassigned_candidate(wizard, axes)
	if axis >= 0:
		_reading_value = clampf(absf(axes[axis] - float(wizard.rest_value(axis))), 0.0, 1.0)
		_reading_live = true
		_reading_axis = axis


func _throttle_candidate(wizard: Variant, axes: PackedFloat64Array) -> int:
	var best := -1
	var best_score := Calibration.DIRECTION_THRESHOLD
	for axis in RcInput.AXES:
		if not _function_of(wizard, axis).is_empty():
			continue
		var rest := float(wizard.rest_value(axis))
		var score := maxf(float(wizard.sweep_max(axis)) - float(wizard.sweep_min(axis)), absf(axes[axis] - rest))
		if score >= best_score:
			best = axis
			best_score = score
	return best


func _unassigned_candidate(wizard: Variant, axes: PackedFloat64Array) -> int:
	var best := -1
	var best_delta := Calibration.DIRECTION_THRESHOLD
	for axis in RcInput.AXES:
		if not _function_of(wizard, axis).is_empty():
			continue
		var delta := absf(axes[axis] - float(wizard.rest_value(axis)))
		if delta >= best_delta:
			best = axis
			best_delta = delta
	return best


## The function an axis is assigned to, or "".
static func _function_of(wizard: Variant, axis: int) -> String:
	for function: String in FUNCTION_KEYS:
		if int(wizard.assigned_axis(function)) == axis:
			return function
	return ""


func _update_channels(wizard: Variant, axes: PackedFloat64Array) -> void:
	var have_axes := axes.size() == RcInput.AXES
	var sweeping := bool(wizard.has_rest()) and not bool(wizard.done())
	for axis in RcInput.AXES:
		var bar: ChannelBarView = channel_bars[axis]
		var function := _function_of(wizard, axis)
		if function != _bar_functions[axis]:
			_bar_functions[axis] = function
			bar.label = tr("Axis %d") % axis if function.is_empty() else "%s · %s" % [tr("Axis %d") % axis, tr(FUNCTION_NAMES[function])]
		bar.set_value(axes[axis] if have_axes else 0.0)
		if axis == _moving_axis:
			bar.highlight = ChannelBarView.Highlight.MOVING
		elif not function.is_empty():
			bar.highlight = ChannelBarView.Highlight.ASSIGNED
		else:
			bar.highlight = ChannelBarView.Highlight.IDLE
		if not function.is_empty():
			var channel: Dictionary = wizard.profile[function]
			bar.set_endpoints(float(channel.min), float(channel.max))
		elif sweeping and float(wizard.sweep_max(axis)) - float(wizard.sweep_min(axis)) > 0.02:
			bar.set_endpoints(float(wizard.sweep_min(axis)), float(wizard.sweep_max(axis)))
		else:
			bar.clear_endpoints()


func _update_verify(wizard: Variant, axes: PackedFloat64Array, complete: bool) -> void:
	verify_panel.visible = complete
	if not complete:
		return
	var axis := int(wizard.assigned_axis("throttle"))
	if axis >= 0 and axes.size() == RcInput.AXES:
		verify_bar.set_value(RcInput.normalize_throttle(axes[axis], wizard.profile.throttle))
	_full_check.set_checked(_verify_full_seen)
	_low_check.set_checked(_verify_low_after_full)


func _sync_texts(wizard: Variant, axes: PackedFloat64Array, complete: bool, target: Dictionary) -> void:
	var step := int(wizard.step)
	var phase := str(target.get("phase", ""))
	if step != _shown_step or phase != _shown_phase:
		_shown_step = step
		_shown_phase = phase
		if complete:
			step_label.text = tr("Calibration complete")
		else:
			step_label.text = tr("Step %d of %d") % [step + 1, Calibration.STEPS.size()]
			instruction_label.text = tr(str(wizard.instruction()))
		checklist.visible = step == 0 and not complete
	var error := str(wizard.error)
	if error != _shown_error:
		_shown_error = error
		error_label.text = tr(error) if not error.is_empty() else ""
		error_label.visible = not error.is_empty()
		error_banner.visible = error_label.visible
	var detected := -1
	if not complete and bool(wizard.has_rest()):
		_read(wizard, str(target.get("function", "")), axes)
		detected = _reading_axis
	if detected != _shown_detected:
		_shown_detected = detected
		detected_label.visible = detected >= 0
		if detected >= 0:
			detected_label.text = tr("Detected: axis %d") % detected


func _apply_layout() -> void:
	_compact = UiTheme.compact_layout
	var side := 130.0 if _compact else 240.0
	var layout := gimbal_functions(stick_mode)
	for index in 2:
		var gimbal: GimbalView = left_gimbal if index == 0 else right_gimbal
		gimbal.side = side
		var y_function: String = layout[index][1]
		gimbal.one_ended_y = y_function == "throttle"
	# A wide guidance column keeps the checklist short enough for 720p; 1080p has room for larger gimbals.
	var column_width := maxf(2.0 * side + 28.0, 640.0 if _compact else 600.0)
	_left_column.custom_minimum_size.x = column_width
	instruction_label.custom_minimum_size.x = column_width
	result_label.custom_minimum_size.x = column_width
	error_label.custom_minimum_size.x = column_width - 24.0
	for bar: ChannelBarView in channel_bars:
		bar.track_width = 110.0 if _compact else 150.0
	verify_bar.track_width = 160.0 if _compact else 240.0
	_retranslate()


## Rebuilds every translated text drawn by the widgets; the next update refreshes the live labels.
func _retranslate() -> void:
	_words.clear()
	for key: String in TARGET_WORDS:
		_words[key] = tr(TARGET_WORDS[key])
	var layout := gimbal_functions(stick_mode)
	for index in 2:
		var gimbal: GimbalView = left_gimbal if index == 0 else right_gimbal
		var x_function: String = layout[index][0]
		var y_function: String = layout[index][1]
		gimbal.caption = "%s · %s" % [tr(FUNCTION_NAMES[y_function]), tr(FUNCTION_NAMES[x_function])]
		gimbal.end_labels = PackedStringArray([_word("full"), _word("low")]) if y_function == "throttle" else PackedStringArray()
		gimbal.queue_redraw()
	var names := PackedStringArray()
	for step: String in STRIP_STEPS:
		names.append(tr(STRIP_NAMES[step]))
	strip.names = names
	verify_bar.label = tr("Throttle")
	_full_check.text = tr("Reached FULL")
	_low_check.text = tr("Back to LOW")
	# Align the monitor's labels on its longest possible label.
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "SecondaryLabel")
	var widest := 0.0
	for function: String in FUNCTION_KEYS:
		var sample := "%s · %s" % [tr("Axis %d") % (RcInput.AXES - 1), tr(FUNCTION_NAMES[function])]
		widest = maxf(widest, font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	for bar: ChannelBarView in channel_bars:
		bar.label_width = widest


func _invalidate() -> void:
	_shown_step = -2
	_shown_phase = ""
	_shown_error = "\u0001"
	_shown_detected = -2
	_bar_functions.fill("\u0001")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSLATION_CHANGED:
			if is_node_ready():
				_retranslate()
				_invalidate()
		NOTIFICATION_THEME_CHANGED:
			if error_banner != null:
				error_banner.add_theme_stylebox_override("panel", _banner_style())
				if _compact != UiTheme.compact_layout:
					_apply_layout()
				else:
					_retranslate()


static func _banner_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.ERROR, 0.12)
	style.border_color = Color(UiTheme.ERROR, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UiTheme.RADIUS)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _label(variation: String, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	if not variation.is_empty():
		label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # live texts are built with tr()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The progress strip: one chip per step, done (check), current (accent outline) or pending (muted).
class StepStrip extends Control:
	var names := PackedStringArray():
		set(value):
			if names != value:
				names = value
				update_minimum_size()
				queue_redraw()
	var current := 0
	var all_done := false
	var _chip := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		_chip.set_corner_radius_all(UiTheme.RADIUS)

	func set_state(index: int, finished: bool) -> void:
		if index != current or finished != all_done:
			current = index
			all_done = finished
			queue_redraw()

	## "done", "current" or "pending" for one chip.
	func chip_state(index: int) -> String:
		if all_done or index < current:
			return "done"
		return "current" if index == current else "pending"

	func _get_minimum_size() -> Vector2:
		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "SectionLabel")
		var width := 0.0
		for text in names:
			width += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 48.0
		return Vector2(width + 8.0 * maxf(0.0, names.size() - 1), font.get_height(font_size) + 14.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			update_minimum_size()
			queue_redraw()

	func _draw() -> void:
		if names.is_empty():
			return
		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "SectionLabel")
		var gap := 8.0
		var width := (size.x - gap * (names.size() - 1)) / names.size()
		var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
		for index in names.size():
			var rect := Rect2(Vector2(index * (width + gap), 0.0), Vector2(width, size.y))
			var state := chip_state(index)
			_chip.bg_color = Color(UiTheme.PRIMARY.normal) if state == "done" else Color(UiTheme.BUTTON.normal, 0.85)
			_chip.border_color = UiTheme.FOCUS if state == "current" else (Color(UiTheme.GLASS_EMISSION, 0.5) if state == "done" else UiTheme.EDGE)
			_chip.set_border_width_all(2 if state == "current" else 1)
			draw_style_box(_chip, rect)
			var color := UiTheme.TEXT if state == "current" else (UiTheme.PRIMARY_TEXT if state == "done" else UiTheme.DISABLED_TEXT)
			var text_width := font.get_string_size(names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var mark := 18.0 if state == "done" else 0.0
			var start := rect.position.x + (rect.size.x - text_width - mark) * 0.5
			if state == "done":
				var c := Vector2(start + 6.0, size.y * 0.5)
				draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(6, -5)]), UiTheme.FOCUS, 2.0, true)
			draw_string(font, Vector2(start + mark, baseline), names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## One verification item: a drawn check box and its text.
class CheckRow extends Control:
	var text := "":
		set(value):
			if text != value:
				text = value
				update_minimum_size()
				queue_redraw()
	var checked := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	func set_checked(value: bool) -> void:
		if checked != value:
			checked = value
			queue_redraw()

	func _get_minimum_size() -> Vector2:
		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "SecondaryLabel")
		var height := font.get_height(font_size)
		return Vector2(height + 8.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, height + 4.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			update_minimum_size()
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "SecondaryLabel")
		var box_side := font.get_height(font_size) * 0.8
		var box := Rect2(Vector2(0.0, (size.y - box_side) * 0.5), Vector2(box_side, box_side))
		draw_rect(box, Color(UiTheme.FOCUS, 0.2) if checked else Color(UiTheme.BUTTON.normal), true)
		draw_rect(box, UiTheme.FOCUS if checked else UiTheme.EDGE, false, 1.5)
		if checked:
			var a := box.position + Vector2(box_side * 0.2, box_side * 0.52)
			var b := box.position + Vector2(box_side * 0.42, box_side * 0.74)
			var c := box.position + Vector2(box_side * 0.82, box_side * 0.26)
			draw_polyline(PackedVector2Array([a, b, c]), UiTheme.FOCUS, 2.5, true)
		var baseline := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
		draw_string(font, Vector2(box_side + 8.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			UiTheme.TEXT if checked else get_theme_color("font_color", "SecondaryLabel"))
