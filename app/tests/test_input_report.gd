# F1: known-answer event statistics and strict diagnostic CLI options.
extends SceneTree

const Data = preload("res://input/input_report_data.gd")
const Report = preload("res://input/input_report.gd")
var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	check("empty command is not report", not Report.requested([]))
	check("trace command is not report", not Report.requested(["--trace=/tmp/flight.csv"]))
	check("bare report selects route", Report.requested(["--input-report"]))
	check("path report selects route", Report.requested(["--input-report=report.json"]))
	var defaults: Dictionary = Report.options(["--input-report"])
	check("defaults are timed and stdout", defaults.ok and defaults.duration_s == 10.0 and defaults.path == "")
	var options: Dictionary = Report.options(["--t=2.5", "--input-report=a b=c.json"])
	check("path and duration retained", options.ok and options.duration_s == 2.5 and options.path == "a b=c.json")
	for bad: PackedStringArray in [[], ["--t=1"], ["--input-report="], ["--input-report= "],
		["--input-report", "--t"], ["--input-report", "--t=0"], ["--input-report", "--t=-1"],
		["--input-report", "--t=nan"], ["--input-report", "--t=inf"], ["--input-report", "--t=1e309"],
		["--input-report", "--t=1e-12"], ["--input-report", "--t=3601"], ["--input-report", "--t=no"],
		["--input-report", "--t=1", "--t=2"], ["--input-report", "--input-report=x"],
		["--input-report", "--trace=x"], ["--input-report", "--capture"], ["--input-report", "--quick-flight"],
		["--input-report", "--aircraft=no-aircraft"], ["--input-report", "--frametimes=x"]]:
		check("refused options %s" % [bad], not Report.options(bad).ok)

	var data: Data = Data.new()
	check("no devices is a valid empty observation", data.snapshot().is_empty())
	data.connect_device(15, {guid = "fake", name = "Mapped", raw_name = "Raw", vendor_id = "4617", product_id = "20308", known = true}, 0)
	data.connect_device(15, {name = "duplicate notification"}, 1)
	data.connect_device(14, {name = "second"}, 0)
	var initial: Array[Dictionary] = data.snapshot()
	check("duplicate connect does not replace a session", initial.size() == 2 and initial[0].name == "Mapped")
	check("identifiers kept without guessing", initial[0].raw_name == "Raw" and initial[0].vendor_id == 0x1209 and initial[0].product_id == 0x4f54 and initial[0].is_joy_known)
	check("unavailable identifiers remain null", initial[1].vendor_id == null and initial[1].raw_name == null)
	check("integer USB identifiers retained", Data.usb_id(0x1209) == 0x1209 and Data.usb_id(65535) == 65535)
	for invalid_id: Variant in [null, true, 1.5, -1, 65536, "", "unknown", "0x1209", "99999999999999999999999999"]:
		check("invalid USB identifier stays unknown: %s" % [invalid_id], Data.usb_id(invalid_id) == null)
	check("unseen axes are unknown", initial[0].axes_seen.is_empty() and initial[0].axes[0].min == null and initial[0].axes[0].mean_event_spacing_usec == null)
	data.motion(15, 0, 0.5, 1000)
	var first: Dictionary = data.snapshot()[0]
	check("first sample does not invent a zero or movement", first.axes_seen == [0] and first.axes_moved.is_empty() and first.axes[0].min == 0.5 and first.axes[0].max == 0.5)
	check("one event cannot measure spacing", first.axes[0].mean_event_spacing_usec == null)
	data.motion(15, 1, -0.1, 1000)
	data.motion(15, 0, -0.8, 3000)
	data.motion(15, 0, 0.9, 3000)
	data.motion(15, 1, 0.1, 5000)
	var moved: Dictionary = data.snapshot()[0]
	check("range and moved axes", moved.axes_moved == [0, 1] and moved.axes[0].min == -0.8 and moved.axes[0].max == 0.9)
	check("per-axis intervals do not mix interleaved axes", moved.axes[0].mean_event_spacing_usec == 1000.0 and moved.axes[1].mean_event_spacing_usec == 4000.0)
	check("same-timestamp event is counted explicitly", moved.axes[0].events == 3 and moved.axes[0].zero_spacing_events == 1)
	check("second device remains untouched", data.snapshot()[1].axes_seen.is_empty())
	moved.axes[0].min = -999.0
	check("snapshot cannot mutate collection", data.snapshot()[0].axes[0].min == -0.8)
	for bad: Array in [[15, -1, 0.0, 6000], [15, 10, 0.0, 6000], [13, 0, 0.0, 6000],
		[15, 0, NAN, 6000], [15, 0, INF, 6000], [15, 0, 1.01, 6000], [15, 0, 0.0, 2999]]:
		data.motion(bad[0], bad[1], bad[2], bad[3])
	check("invalid events refused without poisoning stats", data.rejected_events == 7 and data.snapshot()[0].axes[0].events == 3)
	data.disconnect_device(15, 7000)
	data.disconnect_device(15, 8000)
	data.motion(15, 0, 0.0, 8000)
	data.connect_device(15, {guid = "replacement", name = "new radio"}, 9000)
	data.motion(15, 9, -1.0, 10000)
	var sessions: Array[Dictionary] = data.snapshot()
	check("disconnect history retained", not sessions[0].connected and sessions[0].disconnected_at_usec == 7000)
	check("reused device ID starts fresh session", sessions.size() == 3 and sessions[2].guid == "replacement" and sessions[2].axes_seen == [9] and sessions[2].axes[0].events == 0)
	check("late disconnected event rejected", data.rejected_events == 8)
	check("JSON round trip retains null and numbers", JSON.parse_string(JSON.stringify(sessions))[0].axes[2].min == null)
	print("F1 data/options: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
