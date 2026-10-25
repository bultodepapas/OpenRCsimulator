extends SceneTree
## F4U-21: the canopy and tailhook on the production flight scene. The U and Y keys open the canopy and lower the
## hook over their estimated cycles, in the air and on the ground; the HUD reports them; pressing again reverses them;
## the flight is unaffected; restart closes and stows both; on the runway the lowered hook rests on the ground.
## Writes checks.json and screenshots to a new directory.
## Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --resolution 1920x1080 --path app \
##   --script <repo>/research/f4u-corsair/F4U-21/mechanism_check.gd -- --aircraft=f4u-corsair-250 --out=<new dir>
const MainScene := preload("res://main.tscn")
const RB := preload("res://physics/rigid_body.gd")
var main: Node
var session: Node
var out := ""
var checks := []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		printerr("F4U-21 mechanisms: pass --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = MainScene.instantiate()
	var args := OS.get_cmdline_user_args()
	args.append("--start=airborne")
	main.set_user_args(args)
	main.crash_effects_enabled = false
	root.add_child(main)
	call_deferred("_run")


func _check(label: String, ok: bool, detail := "") -> void:
	checks.append({ label = label, ok = ok, detail = detail })
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _wait_until(condition: Callable, seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < seconds * 1000.0:
		await process_frame
	return condition.call()


func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _turned(part: Dictionary, member: Dictionary, q: float) -> Transform3D:
	return Transform3D(Basis(), part.pivot) * Transform3D(Basis(part.axis, deg_to_rad(part.max_deg * q)), Vector3.ZERO) \
		* Transform3D(Basis(), -part.pivot) * member.rest


func _altitude() -> float:
	return -float(session.sim.state[RB.POS + 2])


func _state(key: String) -> float:
	return float(main._mechanisms.get(key, 0.0))


func _run() -> void:
	for i in 20:
		await process_frame
	session = main.session
	session.radio.disconnect_device()
	main._inspect = true
	var mechanisms: Dictionary = main._airplane.get("mechanisms", {})
	_check("the Corsair binds a canopy and a tailhook", mechanisms.has("canopy") and mechanisms.has("tailhook"), str(mechanisms.keys()))

	# In the air: both mechanisms work and the flight goes on.
	var altitude_before := _altitude()
	var tick_before: int = session.sim.tick
	var t0 := Time.get_ticks_msec()
	await _press(KEY_U)
	await _press(KEY_Y)
	var opened := await _wait_until(func() -> bool: return _state("canopy") >= 1.0 and _state("tailhook") >= 1.0, 10.0)
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	_check("U opens the canopy and Y lowers the hook in the air, over about their 2.5 s and 1.5 s cycles",
		opened and seconds > 2.0 and seconds < 5.0, "%.1f s" % seconds)
	var glass: Dictionary = mechanisms.canopy.parts[0].members[1]
	_check("the rendered canopy is open by R59's slide", glass.node.transform.origin.distance_to(glass.rest.origin + mechanisms.canopy.parts[0].offset) < 1e-6)
	main._update_hud()
	var hud: String = main._hud.text
	_check("the HUD reports the open canopy and the lowered hook", hud.contains("Canopy: open  [U] close") and hud.contains("Tailhook: down  [Y] raise"), hud)
	_check("the flight goes on: the solver advanced, no throttle hold, still airborne", session.sim.tick > tick_before
		and session.throttle_holds.is_empty() and _altitude() > 1.0 and session.crash.is_empty(),
		"ticks %d -> %d, altitude %.1f -> %.1f m, holds %s" % [tick_before, session.sim.tick, altitude_before, _altitude(), str(session.holds)])

	await _press(KEY_U)
	await create_timer(1.0).timeout
	var closing := _state("canopy")
	main._update_hud()
	_check("pressing U again closes the canopy part way back", closing > 0.0 and closing < 1.0 and main._hud.text.contains("Canopy: closing"),
		"%.2f" % closing)

	# Runway: open both for the screenshots, then restart closes and stows them.
	session.start_choice = session.START_RUNWAY
	session.reset()
	for i in 30:
		await process_frame
	_check("restart closes the canopy and stows the hook", _state("canopy") == 0.0 and _state("tailhook") == 0.0
		and mechanisms.canopy.parts[0].members.all(func(m: Dictionary) -> bool: return m.node.transform == m.rest))
	await _press(KEY_U)
	await _press(KEY_Y)
	await _wait_until(func() -> bool: return _state("canopy") >= 1.0 and _state("tailhook") >= 1.0, 10.0)
	await create_timer(0.5).timeout
	var part: Dictionary = mechanisms.tailhook.parts[0]
	var hook: Dictionary = part.members[0]
	var tip: Vector3 = main._airplane.root.global_transform * (hook.node.transform * (hook.rest.affine_inverse() * part.ground_point))
	var clearance: float = tip.y - main._ground_height(tip.x, tip.z)
	_check("on the runway the lowered hook rests on the ground instead of passing through it", clearance > -0.001 and clearance < 0.005
		and hook.node.transform != _turned(part, hook, 1.0), "tip %.4f m above the runway" % clearance)
	main._inspect = true
	await create_timer(1.5).timeout
	await _shot("runway-closeup-canopy-open-hook-down")
	await _press(KEY_2)
	await create_timer(1.5).timeout
	await _shot("runway-canopy-open-hook-down")

	var failed := checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({ format = "F4U-21 mechanism check v1", checks = checks, failures = failed }, "\t"))
	file.close()
	print("F4U-21 mechanisms: %d checks, %d failures" % [checks.size(), failed])
	quit(1 if failed else 0)
