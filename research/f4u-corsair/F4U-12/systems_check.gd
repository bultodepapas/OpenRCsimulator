extends SceneTree
## F4U-12: retracts, flaps and show smoke on the production flight scene with the Corsair. Starts main.tscn airborne,
## then, through the session API the key bindings use, lowers the gear, sets the flaps and switches the smoke on, and
## raises the gear again. Checks the accepted actuator state, the rendered rig (wheel travel, flap hinge angle), the
## flap aerodynamics at the same flight state, and the smoke emitters; writes checks.json and one screenshot per step.
## Godot_v4.7.2-stable_win64.exe --rendering-driver opengl3 --resolution 1920x1080 --path app \
##   --script <repo>/research/f4u-corsair/F4U-12/systems_check.gd -- --aircraft=f4u-corsair-250 --start=airborne --out=<new dir>
const MainScene := preload("res://main.tscn")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
var main: Node
var session: Node
var out := ""
var checks := []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
	if out.is_empty() or DirAccess.dir_exists_absolute(out):
		printerr("F4U-12 systems: pass --out=<new directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = MainScene.instantiate()
	main.set_user_args(OS.get_cmdline_user_args())
	main.crash_effects_enabled = false
	root.add_child(main)
	call_deferred("_run")


func _check(label: String, ok: bool, detail := "") -> void:
	checks.append({ label = label, ok = ok, detail = detail })
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


## Rendered left main wheel in the airplane's frame, and the first left flap's angle from its rest.
func _rig() -> Dictionary:
	var airplane: Dictionary = main._airplane
	var model: Node3D = airplane.root
	var wheel: Node3D = airplane.gear.left
	var flap: Dictionary = airplane.hinges.flap_left_1
	return { wheel = model.global_transform.affine_inverse() * wheel.global_position,
		flap_deg = rad_to_deg(flap.rest.y.angle_to(flap.node.basis.y)) }


func _aero(flap_fraction: float) -> PackedFloat64Array:
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	var a: PackedFloat64Array = sim.aux.duplicate()
	a[session.flap_aux_index()] = flap_fraction
	var rho: float = session.air_density(s)
	var air: Dictionary = Air.compute(s, session.wind_at(sim.time()), rho)
	var lag: int = session.downwash_index()
	return Aero.loads(s, air, session._deflections(a), session.aircraft.model, rho, a[lag] if lag >= 0 else NAN, session._ground_up(s))


func _run() -> void:
	for i in 20:
		await process_frame
	session = main.session
	main._inspect = true # the close aircraft-mounted view
	# A connected gamepad would own the throttle and the smoke AUX; the keyboard path holds the trimmed throttle and
	# takes the smoke key. Restart higher so the unflown airplane has room while gear and flaps change its trim.
	session.radio.disconnect_device()
	session.set_start_altitude(150.0)
	session.reset()
	for i in 10:
		await process_frame
	_check("Corsair flight running on the keyboard path", session.aircraft.get("ok", false) and session.is_flyable() and session.crash.is_empty()
		and not session.radio.connected, str(session.aircraft.model.get("id", "")) if session.aircraft.get("ok", false) else session.start_error)
	await _wait(1.0)
	var up: Dictionary = _rig()
	var gear0: Dictionary = session.gear_state()
	_check("airborne start: gear retractable and up", gear0.available and gear0.status == "up", str(gear0.status))
	await _shot("1-gear-up")

	var t0 := Time.get_ticks_msec()
	_check("gear down request accepted", session.set_gear_down(true))
	while session.gear_state().status != "down" and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	var down: Dictionary = _rig()
	var travel: float = (down.wheel - up.wheel).length()
	_check("gear extends to down and locked", session.gear_state().status == "down", "%.1f s (data 4.0 s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check("rendered main wheel travels with the rig", travel > 0.1, "%.3f m" % travel)
	await _shot("2-gear-down")

	var clean := _aero(0.0)
	var flapped := _aero(1.0)
	_check("full flap adds lift and drag at the same state", -flapped[2] > -clean[2] and flapped[0] < clean[0],
		"lift %+.1f N, drag %+.1f N, pitch moment %+.2f N m" % [-(flapped[2] - clean[2]), -(flapped[0] - clean[0]), flapped[4] - clean[4]])
	t0 = Time.get_ticks_msec()
	_check("flap request accepted", session.set_flaps(1.0))
	while session.flap_state().actual < 1.0 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	var flaps: Dictionary = session.flap_state()
	_check("flaps reach the 30 deg landing setting", absf(float(flaps.angle_deg) - 30.0) < 1e-6, "%.2f deg in %.1f s (data 2.5 s)" % [flaps.angle_deg, (Time.get_ticks_msec() - t0) / 1000.0])
	await process_frame
	var flap_deg: float = _rig().flap_deg
	_check("rendered flap hinge follows to 30 deg", absf(flap_deg - 30.0) < 0.5, "%.2f deg" % flap_deg)
	await _shot("3-gear-down-flaps-30")

	var smoke: Node = main._profile_smoke
	var budget: Dictionary = smoke.budget_info() if smoke != null else {}
	_check("stock show-smoke profile configured", smoke != null and budget.get("configured", false) and int(budget.get("show_emitters", 0)) > 0,
		str(budget.get("slot_particles", {})))
	main._smoke_key_on = true
	await _wait(2.0)
	var emitting := []
	for slot: String in smoke._emitters:
		if (smoke._emitters[slot] as GPUParticles3D).emitting:
			emitting.append(slot)
	_check("smoke on: emitters running with the engine", not emitting.is_empty() and main._profile_smoke_request() > 0.0,
		"request %.2f, emitting %s" % [main._profile_smoke_request(), str(emitting)])
	await _shot("4-smoke-on")
	main._smoke_key_on = false

	session.set_flaps(0.0)
	t0 = Time.get_ticks_msec()
	_check("gear up request accepted in flight", session.set_gear_down(false))
	while session.gear_state().status != "up" and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	_check("gear retracts to up", session.gear_state().status == "up", "%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	_check("rendered wheel returns to the stowed pose", (_rig().wheel - up.wheel).length() < 0.005, "%.4f m" % (_rig().wheel - up.wheel).length())
	_check("no crash or fault during the sequence", session.crash.is_empty() and session.sim.fault_reason.is_empty(), str(session.pause_reason))
	await _shot("5-gear-up-again")

	var failed := checks.filter(func(c: Dictionary) -> bool: return not c.ok).size()
	var file := FileAccess.open(out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({ format = "F4U-12 systems check v1", checks = checks, failures = failed }, "\t"))
	file.close()
	print("F4U-12 systems: %d checks, %d failures" % [checks.size(), failed])
	quit(1 if failed else 0)
