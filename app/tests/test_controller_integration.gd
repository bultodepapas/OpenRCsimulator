extends SceneTree
const Service := preload("res://input/controller_service.gd")
const Session := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const DT := 1.0 / 240.0
var checks := 0
var failures := 0
var axes := PackedFloat64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func neutral(session: Node) -> void:
	axes.fill(0.0)
	for channel in ["roll", "pitch", "yaw", "throttle"]:
		session.radio.on_motion(session.radio.device_id, session.radio.profile[channel].axis, 0.0)
	for i in 50: session._physics_process(DT)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var service := Service.new()
	service.store = Service.Store.new("user://controller_integration_missing.cfg", "user://controller_integration_missing_legacy.cfg")
	var observed := [{"id": 10, "guid": "xbox", "name": "Xbox", "known": true, "vendor_id": 1118, "product_id": 1},
		{"id": 20, "guid": "sony", "name": "DualSense", "known": true, "vendor_id": 1356, "product_id": 2}]
	service.enumerate_devices = func() -> Array: return observed
	service.refresh()
	check("enumeration never claims either role", service.registry.selected_device_id("flight") == -1 and service.registry.selected_device_id("ui") == -1)
	check("explicitly select flight and separate UI pad", service.select_devices(10, 20))
	var session := Session.new()
	session.external_controller_selection = true
	session.physics_enabled = false
	session.rate_profile = "normal"
	session.read_axis = func(_id: int, axis: int) -> float: return axes[axis]
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.setup()
	var launch: float = session.commands.throttle
	service.attach_session(session)
	check("connection starts paused without automatic throttle", session.sim.paused and session.commands.throttle == 0.0 and not session.radio.armed)
	session.resume()
	check("resume cannot bypass initial neutral evidence", session.sim.paused)
	neutral(session)
	check("selected mapped channels can arm while paused", session.radio.armed and session.sim.paused)
	session.resume()
	check("explicit resume seeds declared airborne throttle exactly once", not session.sim.paused and absf(session.commands.throttle - launch) < 1e-12)
	session.radio.set_rate_throttle_for_start(0.37)
	session._physics_process(DT)
	session.hold("menu")
	service.select_devices(10, 10)
	check("UI-only selection preserves flight throttle", absf(session.radio.throttle_position() - 0.37) < 1e-12)
	service.select_devices(10, 20)
	axes[1] = -1.0
	session.radio.on_motion(10, 1, -1.0)
	for i in 240: session._physics_process(DT)
	check("menu movement cannot integrate rate throttle", absf(session.radio.throttle_position() - 0.37) < 1e-12 and session.sim.paused)
	axes[1] = 0.0
	session.radio.on_motion(10, 1, 0.0)
	for i in 50: session._physics_process(DT)
	session.release("menu")
	check("menu release is not resume", session.sim.paused)
	session.resume()
	check("menu resume preserves current throttle not original launch", absf(session.commands.throttle - 0.37) < 1e-12)
	session.controller_focus_lost()
	check("focus loss preserves throttle while clearing gamepad evidence", session.sim.paused and not session.radio.armed and not session.radio.has_axis_sample(0) and absf(session.radio.throttle_position() - 0.37) < 1e-12)
	for i in 50: session._physics_process(DT)
	session.resume()
	check("polled zero after focus loss cannot prove physical neutral", session.sim.paused and not session.radio.armed)
	neutral(session)
	check("fresh neutral after focus loss cannot auto-resume", session.radio.armed and session.sim.paused)
	session.resume()
	check("explicit focus recovery restores held virtual throttle", not session.sim.paused and absf(session.commands.throttle - 0.37) < 1e-12)
	check("K calibration cannot convert gamepad to radio", not session.start_calibration() and session.radio.profile.kind == "gamepad")
	observed.append({"id": 30, "name": "Extra pad", "guid": "extra", "known": true})
	service.refresh()
	check("arrival cannot steal active controls", session.radio.device_id == 10 and service.registry.selected_device_id("ui") == 20)
	observed.remove_at(0)
	service.refresh()
	check("loss pauses with zero throttle and no keyboard fallback", session.sim.paused and session.commands.throttle == 0.0 and not session.radio.connected and not session.can_resume())
	observed.append({"id": 10, "guid": "xbox", "name": "Xbox", "known": true, "vendor_id": 1118, "product_id": 1})
	service.refresh()
	check("same-ID reconnect never auto-selects", service.registry.selected_device_id("flight") == -1 and not session.radio.connected)
	check("explicit keyboard fallback is supported", service.select_devices(-1, 20))
	check("keyboard fallback clears loss only after explicit choice", not session._controller_lost and not session.radio.connected)
	service.select_devices(10, 20)
	neutral(session)
	session.resume()
	check("handover starts from idle rather than old airborne throttle", session.commands.throttle == 0.0)
	var trigger := Profile.defaults("gamepad", "trigger_absolute")
	check("trigger profile can be explicitly applied", service.apply_profile(trigger))
	neutral(session)
	session.resume()
	check("trigger release is idle", session.radio.armed and session.commands.throttle == 0.0)
	axes[5] = 0.75
	session._physics_process(DT)
	check("trigger is unipolar absolute and aircraft rates stay active", absf(session.commands.throttle - 0.75) < 1e-12 and session.rates_active())
	service.apply_profile(Profile.defaults())
	neutral(session)
	session.resume()
	session.radio.set_rate_throttle_for_start(0.9)
	session.reset()
	check("restart pauses and does not retain previous virtual throttle", session.sim.paused and session.radio.throttle_position() == 0.0)
	neutral(session)
	session.resume()
	check("restart uses declared launch throttle", absf(session.commands.throttle - launch) < 1e-12)
	axes[0] = NAN
	session._physics_process(DT)
	check("invalid input pauses and requires explicit recovery", session.sim.paused and session._controller_lost and session.commands.throttle == 0.0 and not session.radio.connected)
	service.attach_session(null)
	session.free()
	service.free()
	print("Controller integration: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
