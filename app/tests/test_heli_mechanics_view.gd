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
	_check("Space stops rotation even after a slider gains focus", view.speed_rpm == 0 and view.phase == phase_before)
	_key(KEY_R)
	await process_frame
	_check("R resets all control demands without resetting shaft history", view.rig.pose.inputs == PackedFloat64Array([0, 0, 0, 0, phase_before]))
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
