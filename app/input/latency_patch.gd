# F6a: optional live-flight marker for external camera measurement, not a software latency estimate.
# CanvasLayer HUD pattern adapted from the Godot skill; containers lay out non-interactive controls.
extends CanvasLayer

const INACTIVE: Color = Color(0.4, 0.4, 0.4)
const SIZE: int = 192
var axis: int = 0
var threshold: float = 0.0 # center = 50% of the raw -1..+1 range
var session: Node
var active: bool = false
var above: bool = false
var sampled_tick: int = -1
var status: String = "waiting for radio"
var marker: ColorRect
var caption: Label


static func options(args: Dictionary) -> Dictionary:
	var out: Dictionary = {ok = true, enabled = args.has("latency-patch"), axis = 0, threshold = 0.0, error = ""}
	if not out.enabled and not args.has("latency-axis") and not args.has("latency-threshold"):
		return out
	out.ok = false
	out.error = "Use --latency-patch [--latency-axis=0..9] [--latency-threshold=raw_value_between_-1_and_1] with live flight only."
	if not out.enabled or typeof(args["latency-patch"]) != TYPE_BOOL or not args["latency-patch"]:
		return out
	for incompatible: String in ["trace", "capture", "scripted", "frametimes", "visual_pose"]:
		if args.has(incompatible):
			return out
	var axis_text: String = str(args.get("latency-axis", "0"))
	var threshold_text: String = str(args.get("latency-threshold", "0"))
	if not axis_text.is_valid_int() or axis_text.length() != 1 or not threshold_text.is_valid_float():
		return out
	out.axis = axis_text.to_int()
	out.threshold = threshold_text.to_float()
	if out.axis < 0 or out.axis >= 10 or not is_finite(out.threshold) or absf(out.threshold) >= 1.0:
		return out
	out.ok = true
	out.error = ""
	return out


func _ready() -> void:
	name = "LatencyPatch"
	layer = 2 # above the flight HUD, below the pause menu
	process_physics_priority = 1 # FlightSession samples at -1, Simulation advances at 0.
	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.offset_left = -16
	margin.offset_right = -16
	margin.offset_top = -50
	margin.offset_bottom = -50
	add_child(margin)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)
	var heading: Label = _label("LATENCY / axis %d\nraw >= %s" % [axis, JSON.stringify(threshold)])
	stack.add_child(heading)
	marker = ColorRect.new()
	marker.name = "Marker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.custom_minimum_size = Vector2(SIZE, SIZE)
	marker.size_flags_horizontal = Control.SIZE_SHRINK_END
	marker.color = INACTIVE
	stack.add_child(marker)
	caption = _label(status)
	stack.add_child(caption)


static func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _physics_process(_delta: float) -> void:
	# Read the actual flight reader after this tick's poll. No Input polling, axis writes or filtering here.
	var reason: String = ""
	if session == null or session.sim == null:
		reason = "no flight"
	elif not session.input_enabled or not session.physics_enabled:
		reason = "input disabled"
	elif session.sim.fault_reason != "":
		reason = "flight fault"
	elif session.calibration != null:
		reason = "calibrating"
	elif not session.holds.is_empty() or session.sim.paused or not session.crash.is_empty():
		reason = "flight paused"
	elif not session.radio.connected:
		reason = "waiting for radio"
	elif not session.radio.has_axis_sample(axis):
		reason = "move selected axis"
	elif not is_finite(session.radio.axes[axis]):
		reason = "invalid axis sample"
	active = reason.is_empty()
	above = active and session.radio.axes[axis] >= threshold
	sampled_tick = session.sim.tick if active else -1
	var next_status: String = "above threshold" if above else "below threshold"
	if not active:
		next_status = reason
	var color: Color = (Color.WHITE if above else Color.BLACK) if active else INACTIVE
	if marker.color != color:
		marker.color = color
	if status != next_status:
		status = next_status
		caption.text = status
