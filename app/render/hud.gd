# Flight HUD and performance overlay (D7), bottom left. Airspeed, altitude, α, throttle; then fps, frame time p95
# and physics µs/tick, the numbers recorded at every playtest ([F3] toggles the performance line).
extends RefCounted

const FRAMES := 240 # frame-time window for the p95


static func create(parent: Node) -> Label:
	var label := Label.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 12
	label.offset_top = -64
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var layer := CanvasLayer.new()
	layer.add_child(label)
	parent.add_child(layer)
	return label


## The flight line: airspeed (m/s), altitude (m), angle of attack (deg), throttle (0…1).
static func flight_line(airspeed: float, altitude: float, alpha_deg: float, throttle: float) -> String:
	return "airspeed %5.1f m/s   altitude %5.1f m   AoA %+5.1f°   throttle %3d%%" % [airspeed, altitude, alpha_deg, roundi(throttle * 100.0)]


## The performance line from recent frame times (s) and the physics cost per tick (µs).
static func perf_line(frame_times: PackedFloat64Array, physics_usec: float) -> String:
	if frame_times.is_empty():
		return ""
	var mean := 0.0
	for t in frame_times:
		mean += t
	mean /= frame_times.size()
	return "%3d fps   frame p95 %5.1f ms   physics %4d µs/tick  [F3]" % [roundi(1.0 / maxf(mean, 1e-6)), p95(frame_times) * 1000.0, roundi(physics_usec)]


## 95th percentile (nearest rank) of a sample.
static func p95(values: PackedFloat64Array) -> float:
	var s := values.duplicate()
	s.sort()
	return s[clampi(ceili(0.95 * s.size()) - 1, 0, s.size() - 1)]
