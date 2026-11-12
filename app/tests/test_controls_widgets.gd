# UI-15-UX-01: StickGimbalView and ChannelBar geometry, one-ended throttle and redraw-on-change discipline.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_controls_widgets.gd
extends SceneTree

const UiTheme := preload("res://ui/ui_theme.gd")
const GimbalView := preload("res://ui/controls/stick_gimbal_view.gd")
const ChannelBarView := preload("res://ui/controls/channel_bar.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = Vector2(1920, 1080)
	root.add_child(host)
	_gimbal_tests(host)
	_bar_tests(host)
	host.queue_free()
	await process_frame
	print("controls widgets: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _gimbal_tests(host: Control) -> void:
	var box := Rect2(0, 0, 100, 100) # inner area is inset by 8 % on each side: 8 … 92
	_check("centre maps to the box centre", GimbalView.to_local_point(Vector2.ZERO, box).is_equal_approx(Vector2(50, 50)))
	_check("full right/forward maps to the top-right inner corner",
		GimbalView.to_local_point(Vector2(1, -1), box).is_equal_approx(Vector2(92, 8)))
	_check("full left/back maps to the bottom-left inner corner",
		GimbalView.to_local_point(Vector2(-1, 1), box).is_equal_approx(Vector2(8, 92)))
	_check("out-of-range positions clamp to the inner edge",
		GimbalView.to_local_point(Vector2(3, 0), box).is_equal_approx(Vector2(92, 50)))
	_check("throttle LOW is the bottom, FULL the top, half the centre", is_equal_approx(GimbalView.throttle_to_y(0.0), 1.0)
		and is_equal_approx(GimbalView.throttle_to_y(1.0), -1.0) and is_equal_approx(GimbalView.throttle_to_y(0.5), 0.0)
		and is_equal_approx(GimbalView.throttle_to_y(1.7), -1.0))

	var gimbal := GimbalView.new()
	gimbal.side = 200.0
	gimbal.caption = "Throttle · Yaw"
	gimbal.one_ended_y = true
	host.add_child(gimbal)
	_check("gimbal never takes focus or the mouse", gimbal.focus_mode == Control.FOCUS_NONE
		and gimbal.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var minimum := gimbal.get_combined_minimum_size()
	_check("minimum size reserves the square and a caption line", is_equal_approx(minimum.x, 200.0) and minimum.y > 210.0, str(minimum))
	gimbal.size = minimum
	var square := gimbal.box_rect()
	_check("gimbal box is square above the caption", is_equal_approx(square.size.x, square.size.y)
		and is_equal_approx(square.size.x, 200.0) and square.end.y < gimbal.size.y, str(square))
	gimbal.set_stick(Vector2(0.0, GimbalView.throttle_to_y(0.0)), true)
	_check("live throttle LOW dot sits at the bottom centre", gimbal.dot_point().is_equal_approx(Vector2(100.0, 184.0)),
		str(gimbal.dot_point()))
	gimbal.set_stick(Vector2(0.5, -1.0), true)
	_check("dot follows yaw right and throttle FULL", gimbal.dot_point().is_equal_approx(Vector2(142.0, 16.0)), str(gimbal.dot_point()))

	# Redraw discipline: unchanged values cost nothing once the trail has settled.
	for frame in GimbalView.TRAIL_LENGTH + 2:
		gimbal.set_stick(Vector2(0.5, -1.0), true)
	var settled := gimbal.redraw_requests
	for frame in 20:
		gimbal.set_stick(Vector2(0.5, -1.0), true)
	_check("still stick stops redrawing after the trail settles", gimbal.redraw_requests == settled)
	gimbal.set_stick(Vector2(0.5 + GimbalView.EPSILON * 0.5, -1.0), true)
	_check("sub-epsilon jitter does not redraw", gimbal.redraw_requests == settled)
	gimbal.set_stick(Vector2(0.2, -1.0), true)
	_check("a real move redraws", gimbal.redraw_requests == settled + 1)
	gimbal.set_stick(Vector2(0.2, -1.0), false)
	_check("losing the live channel redraws (hollow dot)", gimbal.redraw_requests == settled + 2 and not gimbal.is_live())
	var before := gimbal.redraw_requests
	gimbal.set_envelope(Rect2(-1, -1, 2, 2))
	gimbal.set_envelope(Rect2(-1, -1, 2, 2))
	_check("envelope redraws once per change", gimbal.redraw_requests == before + 1 and gimbal.has_envelope()
		and gimbal.envelope() == Rect2(-1, -1, 2, 2))
	gimbal.clear_envelope()
	gimbal.clear_envelope()
	_check("clearing the envelope redraws once", gimbal.redraw_requests == before + 2 and not gimbal.has_envelope())
	before = gimbal.redraw_requests
	gimbal.set_target(Vector2(1, 0), Vector2.ZERO)
	gimbal.set_target(Vector2(1, 0), Vector2.ZERO)
	gimbal.target_label = "RIGHT"
	gimbal.target_label = "RIGHT"
	_check("target and its label redraw once each", gimbal.redraw_requests == before + 2 and gimbal.has_target()
		and gimbal.target() == Vector2(1, 0))
	gimbal.clear_target()
	_check("clearing the target removes it", not gimbal.has_target() and gimbal.target_label.is_empty())
	before = gimbal.redraw_requests
	gimbal.one_ended_y = true
	gimbal.set_deadzone(0.0)
	_check("unchanged one-ended flag and deadzone do not redraw", gimbal.redraw_requests == before)
	gimbal.set_deadzone(0.1)
	_check("a deadzone ring redraws", gimbal.redraw_requests == before + 1)
	gimbal.free()


func _bar_tests(host: Control) -> void:
	var bar := ChannelBarView.new()
	bar.label = "Axis 3 · Roll"
	bar.track_width = 200.0
	host.add_child(bar)
	bar.size = bar.get_combined_minimum_size()
	_check("bar never takes focus or the mouse", bar.focus_mode == Control.FOCUS_NONE
		and bar.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var track := bar.track_rect()
	_check("bar reserves its label, track and percent", is_equal_approx(track.size.x, 200.0) and track.position.x > 20.0
		and track.end.x < bar.size.x, "%s in %s" % [track, bar.size])
	_check("bidirectional zero is the track centre", is_equal_approx(bar.value_to_x(0.0), track.get_center().x))
	_check("bidirectional ends are the track ends", is_equal_approx(bar.value_to_x(-1.0), track.position.x)
		and is_equal_approx(bar.value_to_x(1.0), track.end.x))
	bar.set_value(0.454)
	_check("bidirectional percent is signed", bar.percent_text() == "+45%", bar.percent_text())
	bar.set_value(-0.3)
	_check("negative percent", bar.percent_text() == "-30%", bar.percent_text())
	bar.set_value(-4.0)
	_check("bidirectional value clamps to -1", is_equal_approx(bar.current_value(), -1.0))
	bar.set_value(NAN)
	_check("non-finite value reads as zero", is_equal_approx(bar.current_value(), 0.0))
	bar.one_ended = true
	_check("one-ended zero is the track start", is_equal_approx(bar.value_to_x(0.0), track.position.x)
		and is_equal_approx(bar.value_to_x(0.5), track.get_center().x))
	bar.set_value(-0.5)
	_check("one-ended value clamps to 0", is_equal_approx(bar.current_value(), 0.0) and bar.percent_text() == "0%")
	bar.set_value(0.62)
	_check("one-ended percent is unsigned", bar.percent_text() == "62%", bar.percent_text())
	bar.one_ended = false
	var before := bar.redraw_requests
	bar.set_value(0.62)
	bar.set_value(0.62 + ChannelBarView.EPSILON * 0.5)
	_check("unchanged or sub-epsilon values do not redraw", bar.redraw_requests == before)
	bar.set_value(0.7)
	_check("a changed value redraws", bar.redraw_requests == before + 1)
	bar.set_endpoints(0.8, -0.6)
	bar.set_endpoints(0.8, -0.6)
	_check("endpoints are ordered and redraw once", bar.endpoints() == Vector2(-0.6, 0.8) and bar.redraw_requests == before + 2)
	bar.clear_endpoints()
	_check("cleared endpoints read as NaN", is_nan(bar.endpoints().x) and bar.redraw_requests == before + 3)
	bar.highlight = ChannelBarView.Highlight.MOVING
	bar.highlight = ChannelBarView.Highlight.MOVING
	bar.label = "Axis 3 · Roll"
	_check("highlight redraws once; an unchanged label does not", bar.redraw_requests == before + 4)
	var narrow := bar.get_combined_minimum_size().x
	UiTheme.text_scale = 2.0
	host.theme = UiTheme.build()
	_check("larger text scale widens the bar's minimum size", bar.get_combined_minimum_size().x > narrow + 40.0,
		"%s → %s" % [narrow, bar.get_combined_minimum_size().x])
	UiTheme.text_scale = 1.0
	host.theme = UiTheme.build()
	bar.free()
