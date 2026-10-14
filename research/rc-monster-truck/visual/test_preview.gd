# RCV-14a: exercise inspector controls through Godot's GUI input routing.
extends "preview.gd"

var checks := 0
var failures := 0


func _build() -> void:
	super._build()
	for i in 3:
		await process_frame
	_check("inspector loaded reviewed GLB", model.ok)
	_check("initial pose and hidden proxies", travel == PackedFloat64Array([0, 0, 0, 0]) and not model.nodes.Collision.visible)
	# Native focused Range controls must consume key events; no direct callback calls.
	sliders[0].grab_focus()
	await _key(KEY_RIGHT)
	_check("keyboard changes only FL suspension", is_equal_approx(travel[0], 0.001) and travel[1] == 0.0 and model.nodes.FL_Suspension.position.y > -0.025)
	steer_slider.grab_focus()
	await _key(KEY_RIGHT)
	_check("keyboard steering reaches visual rig", steer > 0.0 and model.nodes.FL_Steer.basis.z.x > 0.0)
	body_toggle.grab_focus()
	await _key(KEY_SPACE)
	_check("body checkbox hides shell", not model.nodes.Body.visible)
	proxy_toggle.grab_focus()
	await _key(KEY_SPACE)
	_check("proxy checkbox reveals debug geometry", model.nodes.Collision.visible)
	pose_select.grab_focus()
	await _key(KEY_SPACE)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check("preset popup applies compression to all corners", travel == PackedFloat64Array([0.05, 0.05, 0.05, 0.05]))
	spin_toggle.grab_focus()
	await _key(KEY_SPACE)
	for i in 4:
		await process_frame
	_check("opt-in wheel animation advances", phase > 0.0 and model.nodes.FL_Spin.basis.y.z < 0.0)
	spin_toggle.button_pressed = false
	# Resize checks prevent the status line or reset action from being clipped.
	root.size = Vector2i(1000, 720)
	for i in 3:
		await process_frame
	var labels := root.find_children("*", "Label", true, false)
	var visible_status := false
	for node in labels:
		if "Conducción pendiente" in node.text or "Driving is not enabled" in node.text:
			visible_status = node.get_global_rect().end.y <= root.get_visible_rect().end.y
	_check("scope status fits minimum window", visible_status)
	print("MT8 inspector: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
