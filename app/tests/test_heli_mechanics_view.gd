extends SceneTree

const View := preload("res://render/rotor/hx700_mechanics_view.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var view := View.new()
	root.add_child(view)
	view.set_process(false)
	await process_frame
	_check("advanced inspector opens with admitted neutral mechanics", view.rig != null and view.rig.pose.ok)
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
