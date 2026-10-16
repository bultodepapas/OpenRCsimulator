extends SceneTree

const View := preload("res://render/rotor/hx700_mechanics_view.gd")
const Motion := preload("res://render/rotor/hx700_inspection_motion.gd")
const InspectorLauncher := preload("res://tools/inspect_hx700.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_window_size := root.size
	root.size = Vector2i(1440, 900)
	var view := View.new()
	root.add_child(view)
	view.set_process(false)
	await process_frame
	_check("advanced inspector opens with admitted neutral mechanics", view.rig != null and view.rig.pose.ok)
	_check("native inspector declares a 640x480 minimum", InspectorLauncher.MIN_NATIVE_WINDOW_SIZE == Vector2i(640, 480))
	view._canopy_toggle.set_pressed_no_signal(false)
	view._canopy_toggle.grab_focus()
	var pause_before_key := view.paused
	_key(KEY_SPACE)
	await process_frame
	_check("Space activates a focused visibility checkbox without pausing", view._canopy_toggle.button_pressed and view.paused == pause_before_key)
	_key(KEY_SPACE)
	await process_frame
	view._mode_buttons[1].grab_focus()
	_key(KEY_SPACE)
	await process_frame
	_check("Space activates a focused mode button without pausing", view._elastic_mode and not view.paused)
	view._mode_buttons[0].grab_focus()
	_key(KEY_SPACE)
	await process_frame
	_check("Space switches back to mechanics through the focused mode button", not view._elastic_mode and not view.paused)
	var canopy_before_p := view._canopy_toggle.button_pressed
	_key(KEY_P)
	await process_frame
	_check("P pauses globally while a checkbox is focused", view.paused and view._canopy_toggle.button_pressed == canopy_before_p)
	_key(KEY_P)
	await process_frame
	view._smooth_toggle.button_pressed = false
	for i in 4:
		view._sliders[i].value = [8.0, -6.0, 4.0, -10.0][i]
	view._phase_slider.value = 90
	_check("all five UI controls reach the mechanism with correct units/order", view.rig.pose.inputs == PackedFloat64Array([8, -6, 4, -10, PI / 2]))
	view._speed.value = 6
	var phase_before: float = view.phase
	view._process(1.0 / 60)
	_check("slow inspection rotation advances the source mechanism", view.phase > phase_before and view.rig.pose.inputs[4] == view.phase)
	view._sliders[0].grab_focus()
	_key(KEY_SPACE)
	await process_frame
	phase_before = view.phase
	view._process(1.0 / 60)
	_check("Space freezes the mechanism without losing selected RPM", view.paused and view.speed_rpm == 6 and view.phase == phase_before)
	_key(KEY_R)
	await process_frame
	_check("paused reset queues neutral without moving the frozen pose", view.motion.demand == PackedFloat64Array([0, 0, 0, 0]) and view.rig.pose.inputs[0] == 8 and view.phase == phase_before)
	view._step()
	_check("single step advances exactly 1/60 second and remains paused", view.paused and view.rig.pose.inputs.slice(0, 4) == PackedFloat64Array([0, 0, 0, 0]) and absf(view.phase - phase_before - TAU / 600) < 1e-12)
	view._toggle_pause()
	_check("resume retains the selected rotation speed", not view.paused and view.speed_rpm == 6)
	view._speed.value = 0
	view._smooth_toggle.button_pressed = true
	view._preset("+Colectivo")
	_check("smooth preset starts at the visible pose with a separate demand", view.rig.pose.inputs[0] == 0 and view.motion.demand[0] == 10)
	view._process(0.1)
	_check("collective transition animates while the rotor is stopped", view.rig.pose.inputs[0] > 0 and view.rig.pose.inputs[0] < 10 and view.speed_rpm == 0)
	view._toggle_pause()
	var frozen: PackedFloat64Array = view.rig.pose.inputs.duplicate()
	view._sliders[0].value = -10
	view._process(2)
	_check("pause freezes control transitions even after a new demand", view.rig.pose.inputs == frozen and view.motion.demand[0] == -10)
	view._step()
	_check("single step advances the queued smooth transition", view.rig.pose.inputs != frozen and view.paused)
	view._toggle_pause()
	view.motion.inputs[4] = TAU * 12 + deg_to_rad(359)
	view._advance(0)
	var tail_before: Basis = view.preview.bindings["tail.shaft"].global_basis
	view._phase_slider.value = 1
	_check("UI azimuth scrub preserves whole shaft turns", absf(view.phase - (TAU * 13 + deg_to_rad(1))) < 1e-12 and view.speed_rpm == 0)
	var tail_after: Basis = view.preview.bindings["tail.shaft"].global_basis
	var tail_change := 0.0
	for axis in 3:
		tail_change = maxf(tail_change, tail_before[axis].distance_to(tail_after[axis]))
	_check("actual tail shaft moves continuously across the azimuth seam", tail_change < 0.18)
	view._smooth_toggle.button_pressed = false
	view._preset("Neutro")
	view._toggle_pause()
	view._smooth_toggle.button_pressed = true
	view._preset("+Colectivo")
	view._step()
	_check("selecting smooth mode while paused does not snap queued controls", view.rig.pose.inputs[0] > 0 and view.rig.pose.inputs[0] < 1)
	view._toggle_pause()
	view._speed.value = 6
	var before_rejection: Dictionary = view.motion.capture_state()
	var before_visible: PackedFloat64Array = view.rig.pose.inputs.duplicate()
	# Mutate only this disposable instance's detached linkage copy.
	var correct_length: float = view.rig._linkages[0].length_m
	view.rig._linkages[0].length_m += 0.1
	view._process(0.1)
	_check("rejected animation rolls back hidden state as well as the visible rig", view.paused and view.motion.capture_state() == before_rejection and view.rig.pose.inputs == before_visible and view.inputs == before_visible)
	view._phase_slider.value = 90
	_check("rejected phase seek restores shaft history and requested RPM", view.motion.capture_state() == before_rejection and view.inputs == before_visible and view._speed.value == 6)
	view.rig._linkages[0].length_m = correct_length
	view._canopy_toggle.button_pressed = true
	view._blades_toggle.button_pressed = true
	_check("visibility controls reveal supplied canopy and blades", view.preview.bindings["visual.carenado"].visible and view.preview.bindings["main.blade.a"].visible)
	var accepted: Transform3D = view.preview.bindings["swash.fixed"].transform
	view.inputs[0] = 14
	_check("invalid UI pose reports rejection and retains visible mechanism", not view._apply_pose() and view._status.text.begins_with("Pose rechazada") and view.preview.bindings["swash.fixed"].transform == accepted)
	var before_limited_seek: Dictionary = view.motion.capture_state()
	var limited_state: Dictionary = before_limited_seek.duplicate(true)
	var limited_inputs: PackedFloat64Array = limited_state.inputs
	limited_inputs[4] = Motion.PHASE_LIMIT
	limited_state.inputs = limited_inputs
	view.motion.restore_state(limited_state)
	view.inputs = view.motion.inputs.duplicate()
	view.phase = view.inputs[4]
	var accepted_azimuth := fposmod(rad_to_deg(view.phase), 360.0)
	view._phase_label.text = "Azimut · %.0f°" % accepted_azimuth
	view._phase_slider.set_value_no_signal(accepted_azimuth)
	view._phase_slider.value = fposmod(accepted_azimuth + 90.0, 360.0)
	var expected_slider := roundf(accepted_azimuth)
	_check("rejected azimuth seek restores the accepted slider, label, and state", absf(view._phase_slider.value - expected_slider) < 0.01 and view._phase_label.text == "Azimut · %.0f°" % accepted_azimuth and view.motion.capture_state() == limited_state and view._status.text.begins_with("Azimut fuera"))
	view.motion.restore_state(before_limited_seek)
	view.inputs = view.motion.inputs.duplicate()
	view.phase = view.inputs[4]
	view._apply_pose()
	root.size = Vector2i(640, 480)
	await process_frame
	await process_frame
	var panel_rect: Rect2 = view._panel.get_global_rect()
	_check("640x480 keeps the readable control panel inside the window", absf(panel_rect.size.x - 316.0) < 0.01 and panel_rect.position.x >= 0 and panel_rect.end.x <= root.size.x)
	var hint_rect: Rect2 = view._hint.get_global_rect()
	_check("640x480 hides the title when it would cover the focused geometry", not view._hint.visible and hint_rect.position.x >= 356 and hint_rect.end.x <= 620)
	var scroll := view._panel.get_child(0) as ScrollContainer
	var scroll_rect: Rect2 = scroll.get_global_rect()
	scroll.scroll_vertical = 100000
	await process_frame
	var footer_rect: Rect2 = view._shortcuts.get_global_rect()
	_check("640x480 scroll reaches the bottom help text", scroll.scroll_vertical > 0 and footer_rect.position.y >= scroll_rect.position.y - 1 and footer_rect.end.y <= scroll_rect.end.y + 1)
	scroll.scroll_vertical = 0
	await process_frame
	var first_control_rect: Rect2 = view._sliders[0].get_global_rect()
	_check("640x480 scroll returns to the first mechanical control", first_control_rect.position.y >= scroll_rect.position.y - 1 and first_control_rect.end.y <= scroll_rect.end.y + 1)
	var clear_left := 356.0
	var clear_right := 620.0
	var focus_in_clear_area := true
	for choice in ["Cabeza", "Cola", "Completo", "Patines", "Carenado"]:
		view._camera_preset(choice)
		await process_frame
		var focus_screen: Vector2 = view.camera.unproject_position(view.focus)
		focus_in_clear_area = focus_in_clear_area and focus_screen.x >= clear_left and focus_screen.x <= clear_right and absf(focus_screen.x - (clear_left + clear_right) * 0.5) < 2.0
	_check("all camera presets keep their focus in the visible render region after resize", focus_in_clear_area)
	root.size = Vector2i(800, 600)
	await process_frame
	await process_frame
	var medium_hint_rect: Rect2 = view._hint.get_global_rect()
	_check("800x600 restores the wrapped title within the clear render region", view._hint.visible and medium_hint_rect.position.x >= 356 and medium_hint_rect.end.x <= 780)
	root.size = original_window_size
	await process_frame
	view.queue_free()
	await process_frame
	print("%d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = code
	release.physical_keycode = code
	Input.parse_input_event(release)


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok " if ok else "FAIL ") + label)
