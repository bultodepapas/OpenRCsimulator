# UI-15-UX-05/06 (component): the in-workspace overlay shown while Controls listens for a control, and the in-place
# conflict question that may follow. Capture mode: a title ("Remap Flaps down"), the prompt, a countdown ring, a live
# preview of the detected candidate (a BindingChip) and the cancel hint with glyph chips (Escape, and the profile's
# Back where it cancels). Conflict mode: "This control is already used by Smoke" with Swap / Replace / Cancel, each
# disabled choice with its reason.
# Presentation only. controller_setup.gd owns the capture state machine (ownership, release consumption, generation
# checks, cancellation) and every draft change; this node never reads input, never edits a binding and never takes
# focus during capture (the row's button keeps it). The countdown advances only through advance(), which the host
# calls from its own _process, so timing stays with the state machine and is testable.
extends Control

const UiTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const BindingChip := preload("res://ui/controls/binding_chip.gd")

## The pointer Cancel of capture mode (keys and buttons are routed by the host).
signal cancel_pressed
## The countdown reached zero once; the host cancels the capture.
signal timed_out
## Conflict mode answer: "swap", "replace" or "cancel".
signal choice_made(choice: String)

const DEFAULT_SECONDS := 8.0

var mode := "" # "", "capture" or "conflict"
var card: PanelContainer
var title_label: Label
var prompt_label: Label
var ring: Control
var preview_caption: Label
var preview_chip: BindingChip
var message_label: Label
var conflict_box: VBoxContainer
var conflict_details: Label
var swap_button: Button
var replace_button: Button
var conflict_cancel_button: Button
var conflict_reasons: Label
var cancel_row: HBoxContainer
var cancel_chips: HBoxContainer
var cancel_hint: Label
var cancel_button: Button

var _duration := DEFAULT_SECONDS
var _remaining := DEFAULT_SECONDS
var _paused := false
var _timed_out := false


func _init() -> void:
	name = "CaptureOverlay"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.name = "CaptureCentre"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = PanelContainer.new()
	card.name = "CaptureCard"
	card.custom_minimum_size.x = 560.0
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.CARD
	style.border_color = UiTheme.FOCUS
	style.set_border_width_all(2)
	style.set_corner_radius_all(UiTheme.RADIUS + 3)
	style.set_content_margin_all(22.0)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.name = "CaptureColumn"
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	title_label = _text("CaptureTitle", "CardTitle")
	column.add_child(title_label)
	prompt_label = _text("CapturePrompt", "")
	column.add_child(prompt_label)
	var live := HBoxContainer.new()
	live.name = "CaptureLive"
	live.add_theme_constant_override("separation", 18)
	column.add_child(live)
	ring = CountdownRing.new()
	ring.name = "CaptureCountdown"
	live.add_child(ring)
	var preview := VBoxContainer.new()
	preview.name = "CapturePreview"
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.add_theme_constant_override("separation", 6)
	live.add_child(preview)
	preview_caption = _text("CapturePreviewCaption", "SectionLabel")
	preview.add_child(preview_caption)
	preview_chip = BindingChip.new()
	preview_chip.name = "CapturePreviewChip"
	preview_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview.add_child(preview_chip)
	message_label = _text("CaptureMessage", "SecondaryLabel")
	message_label.visible = false
	column.add_child(message_label)
	conflict_box = VBoxContainer.new()
	conflict_box.name = "ConflictChoices"
	conflict_box.add_theme_constant_override("separation", 10)
	conflict_box.visible = false
	column.add_child(conflict_box)
	conflict_details = _text("ConflictDetails", "SecondaryLabel")
	conflict_box.add_child(conflict_details)
	var choices := HBoxContainer.new()
	choices.name = "ConflictButtons"
	choices.add_theme_constant_override("separation", 10)
	conflict_box.add_child(choices)
	swap_button = Widgets.button("Swap", "PrimaryButton", "ConflictSwap")
	swap_button.pressed.connect(_choose.bind("swap"))
	choices.add_child(swap_button)
	replace_button = Widgets.button("Replace", "", "ConflictReplace")
	replace_button.pressed.connect(_choose.bind("replace"))
	choices.add_child(replace_button)
	conflict_cancel_button = Widgets.button("Cancel", "", "ConflictCancel")
	conflict_cancel_button.pressed.connect(_choose.bind("cancel"))
	choices.add_child(conflict_cancel_button)
	conflict_reasons = _text("ConflictReasons", "SecondaryLabel")
	conflict_reasons.add_theme_color_override("font_color", UiTheme.CAUTION)
	conflict_box.add_child(conflict_reasons)
	cancel_row = HBoxContainer.new()
	cancel_row.name = "CaptureCancelRow"
	cancel_row.add_theme_constant_override("separation", 8)
	column.add_child(cancel_row)
	cancel_chips = HBoxContainer.new()
	cancel_chips.name = "CaptureCancelGlyphs"
	cancel_chips.add_theme_constant_override("separation", 6)
	cancel_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_row.add_child(cancel_chips)
	cancel_hint = _text("CaptureCancelHint", "SecondaryLabel")
	cancel_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	cancel_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_row.add_child(cancel_hint)
	# Pointer only: keyboard and gamepad cancel through Escape/Back (or the timeout) while the row keeps focus.
	cancel_button = Widgets.button("Cancel", "", "CaptureCancel")
	cancel_button.focus_mode = Control.FOCUS_NONE
	cancel_button.pressed.connect(func() -> void: cancel_pressed.emit())
	cancel_row.add_child(cancel_button)


static func _text(node_name: String, variation: String) -> Label:
	var label := Widgets.label("", variation, true, false)
	label.name = node_name
	label.custom_minimum_size.x = 0.0
	return label


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.PANEL, 0.62))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# --- Capture mode -------------------------------------------------------------------------------------------------

## Texts are already translated by the host. `cancel_bindings` are chips for the cancel hint (Escape, Back …);
## `family`, `device` and `profile` render them like the action list does.
func show_capture(title: String, prompt: String, cancel_text: String, cancel_bindings: Array = [],
		family := "auto", device: Dictionary = {}, profile: Dictionary = {}, seconds := DEFAULT_SECONDS) -> void:
	mode = "capture"
	title_label.text = title
	prompt_label.text = prompt
	set_message("")
	clear_preview()
	ring.visible = true
	preview_caption.visible = true
	conflict_box.visible = false
	cancel_row.visible = true
	cancel_hint.text = cancel_text
	cancel_button.text = tr("Cancel")
	for child in cancel_chips.get_children():
		cancel_chips.remove_child(child)
		child.queue_free()
	for binding: Variant in cancel_bindings:
		if binding is Dictionary and str(binding.get("type", "unbound")) != "unbound":
			var chip := BindingChip.new()
			chip.set_binding(binding, family, device, profile)
			chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cancel_chips.add_child(chip)
	restart_countdown(seconds)
	visible = true


func set_prompt(prompt: String) -> void:
	prompt_label.text = prompt


## A note under the prompt; errors use the theme's error colour and keep their words.
func set_message(text: String, is_error := false) -> void:
	message_label.text = text
	message_label.visible = not text.is_empty()
	message_label.add_theme_color_override("font_color", UiTheme.ERROR if is_error else UiTheme.TEXT)


## The control detected so far (before it is accepted); an empty binding shows "Waiting for input…".
func set_preview(binding: Dictionary, label := "", family := "auto", device: Dictionary = {}, profile: Dictionary = {}) -> void:
	if binding.is_empty():
		clear_preview()
		return
	preview_caption.text = tr("Detected")
	preview_chip.visible = true
	preview_chip.set_binding(binding, family, device, profile)
	preview_chip.set_label(label)


func clear_preview() -> void:
	preview_caption.text = tr("Waiting for input…")
	preview_chip.visible = false
	preview_chip.set_binding({})
	preview_chip.set_label("")


func has_preview() -> bool:
	return preview_chip.visible


func restart_countdown(seconds := -1.0) -> void:
	if seconds > 0.0:
		_duration = seconds
	_remaining = _duration
	_paused = false
	_timed_out = false
	(ring as CountdownRing).set_fraction(1.0, ceili(_remaining))


## A paused countdown (for example while a native OFF confirmation is open) neither advances nor times out.
func pause_countdown(paused: bool) -> void:
	_paused = paused


func remaining() -> float:
	return _remaining


func is_capturing() -> bool:
	return visible and mode == "capture"


## Called by the host once per frame while it owns a capture. Emits `timed_out` once.
func advance(delta: float) -> void:
	if not is_capturing() or _paused or _timed_out or not is_finite(delta) or delta <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	(ring as CountdownRing).set_fraction(_remaining / maxf(_duration, 0.001), ceili(_remaining))
	if _remaining <= 0.0:
		_timed_out = true
		timed_out.emit()


# --- Conflict mode ------------------------------------------------------------------------------------------------

## `options`: {title, text, details, binding, label, family, device, profile, swap_reason, replace_reason}; an empty
## reason enables that choice. Focus moves to Cancel (no change is the safe default) and stays inside the choices.
func show_conflict(options: Dictionary) -> void:
	mode = "conflict"
	title_label.text = str(options.get("title", ""))
	prompt_label.text = str(options.get("text", ""))
	set_message("")
	ring.visible = false
	cancel_row.visible = false
	conflict_box.visible = true
	preview_caption.visible = true
	preview_caption.text = tr("Control")
	var binding: Dictionary = options.get("binding", {})
	preview_chip.visible = not binding.is_empty()
	preview_chip.set_binding(binding, str(options.get("family", "auto")), options.get("device", {}), options.get("profile", {}))
	preview_chip.set_label(str(options.get("label", "")))
	conflict_details.text = str(options.get("details", ""))
	conflict_details.visible = not conflict_details.text.is_empty()
	swap_button.text = tr("Swap")
	replace_button.text = tr("Replace")
	conflict_cancel_button.text = tr("Cancel")
	var reasons: Array[String] = []
	for entry: Array in [[swap_button, "swap_reason", "Swap"], [replace_button, "replace_reason", "Replace"]]:
		var button: Button = entry[0]
		var reason := str(options.get(entry[1], ""))
		button.disabled = not reason.is_empty()
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		button.tooltip_text = reason
		button.accessibility_description = reason
		if not reason.is_empty():
			reasons.append(tr("%s is unavailable: %s") % [tr(str(entry[2])), reason])
	conflict_reasons.text = "\n".join(reasons)
	conflict_reasons.visible = not reasons.is_empty()
	_trap_focus()
	visible = true
	if is_inside_tree():
		conflict_cancel_button.grab_focus()


func is_conflict() -> bool:
	return visible and mode == "conflict"


func _choose(choice: String) -> void:
	if not is_conflict():
		return
	if (choice == "swap" and swap_button.disabled) or (choice == "replace" and replace_button.disabled):
		return
	choice_made.emit(choice)


## Left/right (and Tab) cycle the enabled choices; up/down stay on them, so focus cannot leave the question.
func _trap_focus() -> void:
	var enabled: Array[Button] = []
	for button: Button in [swap_button, replace_button, conflict_cancel_button]:
		if not button.disabled:
			enabled.append(button)
	for index in enabled.size():
		var button := enabled[index]
		var next := enabled[(index + 1) % enabled.size()]
		var previous := enabled[(index - 1 + enabled.size()) % enabled.size()]
		button.focus_neighbor_right = button.get_path_to(next)
		button.focus_neighbor_left = button.get_path_to(previous)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_next = button.get_path_to(next)
		button.focus_previous = button.get_path_to(previous)


func hide_overlay() -> void:
	mode = ""
	visible = false
	_paused = false
	_timed_out = false


## Countdown ring: the remaining fraction as an arc from twelve o'clock with the whole seconds left in the middle.
class CountdownRing extends Control:
	var fraction := 1.0
	var seconds := 0

	func _init() -> void:
		custom_minimum_size = Vector2(84.0, 84.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE

	func set_fraction(value: float, whole_seconds: int) -> void:
		var next := clampf(value, 0.0, 1.0)
		if absf(next - fraction) < 0.004 and whole_seconds == seconds:
			return
		fraction = next
		seconds = whole_seconds
		queue_redraw()

	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 6.0
		draw_arc(centre, radius, 0.0, TAU, 64, Color(UiTheme.EDGE, 0.6), 5.0, true)
		if fraction > 0.0:
			draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction, 64, UiTheme.FOCUS, 5.0, true)
		var font := get_theme_font("font", "Label")
		var font_size := get_theme_font_size("font_size", "Label")
		var text := str(seconds)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, centre + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 2.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.TEXT)
