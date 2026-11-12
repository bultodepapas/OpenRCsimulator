# DR-14/20/31/36a/37 (ROUTE-01…06, VIS-05…07 headless parts): Home -> Garage "FPV quad" -> Fly FPV quad -> the
# multirotor activity in the exclusive slot -> Home. Paused, disarmed start on the pad; a held-high arm switch does
# not arm and the OSD says why; OFF then ON at low throttle arms; climb, flight, crash or landing; truthful OSD
# (EXPERIMENTAL, arm state, battery only with a pack); focus loss holds; restart on the pad returns a disarmed quad
# with the camera snapped; the imported frame agrees with the physics hubs; the lab fixture appears only when the
# frame cannot load; the direct --multirotor= route and its refusals; car and blimp entries unchanged; repeated
# Home <-> activity switching leaks no activity node. Headless: no 1080p rendering, pacing or latency claim.
extends SceneTree

const AppRoot = preload("res://app_root.gd")
const AirshipCatalog = preload("res://vehicles/airship/airship_catalog.gd")
const GroundCatalog = preload("res://vehicles/ground/vehicle_catalog.gd")
const Catalog = preload("res://vehicles/multirotor/multirotor_catalog.gd")
const Activity = preload("res://vehicles/multirotor/multirotor_scene.gd")
const Visual = preload("res://vehicles/multirotor/multirotor_visual.gd")
const Cam = preload("res://vehicles/multirotor/multirotor_camera.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const UiDriver = preload("res://tests/ui_driver.gd")

const DT := 1.0 / 240.0

## AppRoot's controller registry, reduced to what the activity reads (selection, device records, the signal).
class FakeRegistry extends RefCounted:
	signal selection_changed(role: String, id: int)
	var flight := -1
	var devices := {}

	func selected_device_id(role: String) -> int:
		return flight if role == "flight" else -1

	func device_for_id(id: int) -> Dictionary:
		return (devices.get(id, {}) as Dictionary).duplicate(true)

	func select_flight(id: int) -> void:
		flight = id
		selection_changed.emit("flight", id)

	func connection_generation(_id: int) -> int:
		return 1

	func select_device(role: String, id: int) -> bool:
		if role == "flight":
			select_flight(id)
		return true


var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


static func _frame(arm: bool, throttle: float, pitch := 0.0, generation := 0) -> PackedFloat64Array:
	var frame := FC.neutral_input(generation, true)
	frame[FC.IN_ARM] = 1.0 if arm else 0.0
	frame[FC.IN_THROTTLE] = throttle
	frame[FC.IN_PITCH] = pitch
	return frame


## Drive the activity's own physics step synchronously (same path as the engine's tick).
static func _ticks(activity: Node, count: int) -> void:
	for i in count:
		activity._physics_process(DT)
		if activity.session.paused:
			return


func _run() -> void:
	var ui: RefCounted = UiDriver.new(self)
	var accumulated_before := Input.use_accumulated_input
	var app := AppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = "user://test_mr_activity_settings.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	await process_frame
	await process_frame
	_check("Home prepares", app.home != null)
	if app.home == null:
		await ui.close_app(app)
		quit(1)
		return
	await _garage(app)
	var activity: Node = await _launch(app)
	if activity == null:
		await ui.close_app(app)
		print("%d checks, %d failed" % [_count, _failures])
		quit(1)
		return
	_frame_alignment(activity)
	await _held_switch(activity)
	await _flight(activity)
	await _restart(activity)
	await _focus(activity)
	activity.handle_action("home")
	for i in 8:
		await process_frame
	_check("Home returns after the FPV quad and no activity node remains", app.ground_vehicle == null and app.home != null
		and root.find_child("MultirotorActivity", true, false) == null)
	_check("Input.use_accumulated_input is restored on return", Input.use_accumulated_input == accumulated_before)
	if app.home != null:
		_check("Garage remembers the FPV quad", app.home.multirotor_selected and app.home.ground_vehicle_button.text == "Fly FPV quad",
			"%s %s" % [app.home.multirotor_selected, app.home.ground_vehicle_button.text])
		await _switching(app)
	await ui.close_app(app)
	await _direct_route(ui)
	await _fixture_and_direct_launch()
	await _audit_fixes()
	await _pause_keeps_throttle()
	await _radio_source()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _garage(app: Node) -> void:
	app.home._page_buttons[3].pressed.emit()
	await process_frame
	var choice: OptionButton = app.home.ground_vehicle_choice
	var cars := GroundCatalog.IDS.size()
	var skins := AirshipCatalog.SKIN_IDS.size()
	_check("Garage lists the RC cars, the blimp skins and the FPV quad last", choice.item_count == cars + skins + 1)
	var unchanged := true
	for i in cars:
		unchanged = unchanged and choice.get_item_text(i) == GroundCatalog.entry(GroundCatalog.IDS[i]).name
	for i in skins:
		var skin: Dictionary = AirshipCatalog.skins()[i]
		unchanged = unchanged and choice.get_item_text(cars + i) == "%s — %s" % [TranslationServer.translate("RC blimp (experimental)"), skin.name]
	_check("car and blimp items keep their order and labels", unchanged)
	_check("the FPV quad item is named", choice.get_item_text(cars + skins) == TranslationServer.translate(Catalog.DISPLAY_NAME),
		choice.get_item_text(cars + skins))
	var requests := {car = 0, blimp = 0, quad = 0}
	app.home.ground_vehicle_requested.disconnect(app.start_ground_vehicle)
	app.home.airship_requested.disconnect(app.start_airship)
	app.home.ground_vehicle_requested.connect(func() -> void: requests.car += 1)
	app.home.airship_requested.connect(func() -> void: requests.blimp += 1)
	app.home.multirotor_requested.connect(func() -> void: requests.quad += 1)
	choice.select(0)
	choice.item_selected.emit(0)
	_check("a car keeps \"Open RC car garage\"", app.home.ground_vehicle_button.text == "Open RC car garage" and not app.home.multirotor_selected)
	app.home.ground_vehicle_button.pressed.emit()
	choice.select(cars + 1)
	choice.item_selected.emit(cars + 1)
	_check("a blimp skin keeps \"Fly RC blimp\"", app.home.ground_vehicle_button.text == "Fly RC blimp"
		and app.home.airship_skin_id == AirshipCatalog.SKIN_IDS[1] and not app.home.multirotor_selected)
	app.home.ground_vehicle_button.pressed.emit()
	choice.select(cars + skins)
	choice.item_selected.emit(cars + skins)
	_check("the FPV quad turns the action into \"Fly FPV quad\"", app.home.ground_vehicle_button.text == "Fly FPV quad"
		and app.home.multirotor_selected and not app.home.airship_selected and app.home._garage_index() == cars + skins)
	_check("car and blimp actions still request their own activities", requests.car == 1 and requests.blimp == 1 and requests.quad == 0,
		str(requests))
	app.home.ground_vehicle_requested.connect(app.start_ground_vehicle)
	app.home.airship_requested.connect(app.start_airship)


func _launch(app: Node) -> Node:
	var before_car := [0]
	app.home.ground_vehicle_requested.connect(func() -> void: before_car[0] += 1)
	app.home.ground_vehicle_button.pressed.emit()
	for i in 4:
		await process_frame
	var activity: Node = app.ground_vehicle
	_check("Fly FPV quad routes to the multirotor activity only", before_car[0] == 0 and activity != null
		and activity.name == "MultirotorActivity" and app.home == null and app.flight == null)
	if activity == null:
		return null
	_check("activity starts: " + str(activity.startup_error), str(activity.startup_error).is_empty())
	if not str(activity.startup_error).is_empty():
		return null
	var t: Dictionary = activity.session.telemetry()
	_check("starts paused with its menu open, disarmed on the ground", activity.session.paused and activity.hud.menu_visible
		and not t.armed and float(t.altitude_agl_m) < 0.1, "agl %.3f" % float(t.altitude_agl_m))
	_check("the activity owns input accumulation (off)", not Input.use_accumulated_input)
	_check("the imported frame is used (no lab fixture)", not activity.visual.fixture and not activity.hud.fixture_label.visible,
		activity.visual.fallback_reason)
	_check("OSD tag is the short EXPERIMENTAL; the variant id is in the menu", activity.hud.tag.text == "EXPERIMENTAL"
		and str(activity.session.data.identity.variant) in activity.hud.menu_variant.text, activity.hud.tag.text)
	_check("throttle policy follows the (keyboard) source", str(activity.session.options.throttle_policy) == "rate")
	_check("keyboard flights start with the 45% trainer throttle limit",
		is_equal_approx(float(activity.session.options.throttle_limit), 0.45), str(activity.session.options.throttle_limit))
	_check("the pad start hint names the arm key", "Press E to arm" in activity.hud.hint_label.text, activity.hud.hint_label.text)
	_check("the OSD shows the pilot's Angle selection before the first tick", activity.hud.mode_label.text == "ANGL",
		activity.hud.mode_label.text)
	await process_frame
	var viewport_centre: Vector2 = activity.hud.root_control.size * 0.5
	var menu_centre: Vector2 = activity.hud.menu.get_global_rect().get_center()
	_check("the pause menu is centred", menu_centre.distance_to(viewport_centre) < 2.0, "%s vs %s" % [menu_centre, viewport_centre])
	activity._process(0.0)
	var covered: bool = activity.hud.menu.get_global_rect().grow(8.0).intersects(Activity.Hud._text_rect(activity.hud.hint_label))
	_check("the open menu never covers a visible hint", activity.hud.hint_label.visible != covered and not activity.hud.warning_label.visible,
		"covered %s visible %s" % [covered, activity.hud.hint_label.visible])
	return activity


## The frame GLB against the physics data: hubs horizontally within 2 mm, the camera pivot within 3 mm.
func _frame_alignment(activity: Node) -> void:
	var visual: RefCounted = activity.visual
	var empties: Dictionary = Visual.model_empties(visual.model)
	var offset: Vector3 = visual.model.position
	var worst := 0.0
	var rotors: Array = activity.session.data.rotors
	for i in rotors.size():
		var hub := Visual.body_point(rotors[i].hub_frd)
		var empty: Vector3 = empties.propellers[int(rotors[i].id) - 1] + offset
		worst = maxf(worst, Vector2(hub.x - empty.x, hub.z - empty.z).length())
	_check("propeller empties agree with the physics hubs horizontally within 2 mm", worst <= 0.002, "worst %.4f m" % worst)
	var hub_y := Visual.hub_centroid(rotors).y
	var empty_y: float = (empties.propeller_centroid as Vector3).y + offset.y
	_check("the frame sits MOTOR_HEIGHT_M below the prop plane", absf(hub_y - empty_y - Visual.MOTOR_HEIGHT_M) < 1.0e-6)
	var mount := Visual.body_point(activity.session.data.camera.mount_frd)
	var pivot: Vector3 = empties.camera_mount + offset if empties.camera_mount != null else Vector3.INF
	_check("camera_mount agrees with the physics camera mount within 3 mm", mount.distance_to(pivot) <= 0.003,
		"%s vs %s" % [mount, pivot])


func _held_switch(activity: Node) -> void:
	activity.scripted_pilot = func(_tick: int) -> PackedFloat64Array: return _frame(true, -1.0)
	activity.handle_action("resume")
	var started: int = activity.session.sim.tick
	_ticks(activity, 48)
	activity._process(0.0)
	var t: Dictionary = activity.session.telemetry()
	_check("resumed flight advances accepted ticks", activity.session.sim.tick >= started + 48 and not activity.session.paused)
	_check("a held-high arm switch at start does not arm", not t.armed and int(t.arm_block) == FC.BLOCK_SWITCH, str(t.arm_block))
	_check("the OSD says why: cycle the arm switch", "DISARMED" in activity.hud.arm_label.text
		and "Cycle the arm switch" in activity.hud.arm_label.text, activity.hud.arm_label.text)
	_check("the hint explains the refused arm request", "Arming refused" in activity.hud.hint_label.text, activity.hud.hint_label.text)


func _flight(activity: Node) -> void:
	activity.handle_action("restart")
	_check("restart pauses a disarmed quad", activity.session.paused and not activity.session.telemetry().armed)
	var identity_before: String = str(activity.session.identity().controller)
	activity.handle_action("throttle_limit")
	_check("on the untouched pad a throttle limit choice applies at once through a fresh prepare",
		is_equal_approx(float(activity.session.options.throttle_limit), 0.6) and str(activity.session.identity().controller) != identity_before
		and activity.session.paused and not activity.hud.limit_note.visible and "60%" in activity.hud.limit_button.text,
		"%s %s" % [activity.session.options.throttle_limit, activity.hud.limit_button.text])
	activity.handle_action("throttle_limit")
	_check("the next choice is full range", is_equal_approx(float(activity.session.options.throttle_limit), 1.0))
	var base := [0]
	# OFF for 0.1 s, ON at zero throttle, add throttle for 0.5 s, hold 0.5 s, nose down a little, then cut to idle.
	activity.scripted_pilot = func(tick: int) -> PackedFloat64Array:
		var k: int = tick - base[0]
		if k < 24: return _frame(false, -1.0)
		if k < 48: return _frame(true, -1.0)
		if k < 48 + 120: return _frame(true, 1.0)
		if k < 48 + 240: return _frame(true, 0.0)
		if k < 48 + 300: return _frame(true, 0.0, -0.3)
		return _frame(true, -1.0)
	activity.handle_action("resume")
	base[0] = int(activity.session.sim.tick)
	_ticks(activity, 60)
	activity._process(0.016)
	var t: Dictionary = activity.session.telemetry()
	_check("OFF then ON at low throttle arms", t.armed, str(t.arm_block))
	# The scripted frames request Acro (IN_MODE 0).
	_check("OSD shows ARMED, the mode and the timer", activity.hud.arm_label.text == "MOTORS ARMED" and activity.hud.mode_label.text == "ACRO"
		and activity.hud.timer_label.text == Activity.Hud.format_timer(activity._armed_ticks * DT), "%s | %s | %s" % [activity.hud.arm_label.text, activity.hud.mode_label.text,
		activity.hud.timer_label.text])
	if bool(t.has_battery):
		var cell_v := float(t.bus_voltage_v) / float(activity.session.data.battery.cells)
		_check("OSD shows pack voltage, average cell voltage, current and consumed charge", "mAh" in activity.hud.battery_label.text
			and ("%.2f V/cell" % cell_v) in activity.hud.battery_label.text and activity.hud.battery_label.visible, activity.hud.battery_label.text)
	else:
		_check("no pack: the OSD shows no battery values", not activity.hud.battery_label.visible)
	_check("no throttle limit line at full range", not "LIMIT" in activity.hud.throttle_label.text, activity.hud.throttle_label.text)
	_check("the FPV view draws the artificial horizon", not (activity.hud._draw_state.horizon as Dictionary).is_empty())
	activity.view.cycle_view()
	activity._process(0.016)
	_check("other views draw no artificial horizon", (activity.hud._draw_state.horizon as Dictionary).is_empty())
	activity.view.view = 0
	_ticks(activity, 120)
	activity._process(0.016)
	t = activity.session.telemetry()
	_check("the quad climbs under power", float(t.altitude_agl_m) > 0.5, "agl %.2f m" % float(t.altitude_agl_m))
	var spinning := true
	for i in 4:
		var rotor: Dictionary = activity.visual.rotors[i]
		spinning = spinning and is_equal_approx(float(rotor.speed), absf(t.rotor_speed_rad_s[i])) and activity.visual.blur_fraction(i) > 0.5
	_check("rotor views follow the achieved shaft speeds and blur at speed", spinning)
	var before_phase: Array = []
	for rotor: Dictionary in activity.visual.rotors:
		before_phase.append(float(rotor.phase))
	activity.visual.pose(activity.session.interpolated(1.0), t.rotor_speed_rad_s, 0.0005)
	var directions_ok := true
	for i in 4:
		var rotor: Dictionary = activity.visual.rotors[i]
		var moved := wrapf(float(rotor.phase) - float(before_phase[i]), -PI, PI)
		directions_ok = directions_ok and signf(moved) == signf(float(activity.session.data.rotors[i].spin))
	_check("each rotor turns in its own direction", directions_ok)
	_check("the flight timer runs from arming", activity._arm_time >= 0.0)
	_ticks(activity, 240 * 12)
	activity._process(0.016)
	t = activity.session.telemetry()
	var crashed: bool = not activity.session.crash.is_empty()
	var landed: bool = float(t.altitude_agl_m) < 0.2 and float(t.speed_mps) < 0.5
	_check("the flight ends in a crash or on the ground", crashed or landed,
		"crash %s agl %.2f speed %.2f" % [activity.session.crash, float(t.altitude_agl_m), float(t.speed_mps)])
	if crashed:
		_check("after the aftermath the menu offers only a restart", activity.session.paused and activity.hud.menu_visible
			and activity.hud.resume_button.disabled and not activity.hud.resume_button.visible
			and activity.hud.restart_button.get_index() < activity.hud.resume_button.get_index()
			and "Press R" in activity.hud.menu_reason.text, activity.hud.menu_reason.text)
		_check("the OSD names the crash cause", str(activity.session.crash.reason) in activity.hud.hint_label.text, activity.hud.hint_label.text)
		_check("the session's terminal state is a crash", activity._terminal_state() == "crash")
	_terminal_menus(activity)


func _restart(activity: Node) -> void:
	activity.scripted_pilot = func(_tick: int) -> PackedFloat64Array: return _frame(false, -1.0)
	activity.view.view = 0
	_limit_after_flight(activity)
	activity.handle_action("restart")
	_check("Restart on pad applies the pending throttle limit", is_equal_approx(float(activity.session.options.throttle_limit), 0.35)
		and not activity.hud.limit_note.visible, str(activity.session.options.throttle_limit))
	await process_frame
	var t: Dictionary = activity.session.telemetry()
	_check("restart on pad: paused, disarmed, no crash, on the ground", activity.session.paused and not t.armed
		and activity.session.crash.is_empty() and float(t.altitude_agl_m) < 0.1 and float(t.speed_mps) < 0.05)
	_check("restart clears the OSD timer and crash cause", activity._arm_time < 0.0 and activity._crash_cause.is_empty()
		and activity.hud.timer_label.text == "00:00.0" and not "Crashed" in activity.hud.hint_label.text)
	_check("the menu leads with resume again on a flyable quad", activity.hud.resume_button.visible
		and activity.hud.resume_button.get_index() < activity.hud.restart_button.get_index())
	var pose: PackedFloat64Array = activity.session.interpolated(1.0)
	var expected := Cam.fpv_transform(pose.slice(0, 3), pose.slice(6, 10), activity.session.data.camera.mount_frd,
		deg_to_rad(activity.view.tilt_deg))
	_check("the camera is snapped to the reset pose", activity.camera.global_transform.is_equal_approx(expected))
	var stopped := true
	for i in 4:
		stopped = stopped and activity.visual.blur_fraction(i) == 0.0
	_check("stopped rotors show solid blades", stopped)


## Menu honesty after depletion, through the menu itself (a depleted pack takes minutes of flight to reach).
func _terminal_menus(activity: Node) -> void:
	var hud: CanvasLayer = activity.hud
	hud.show_menu("depleted", true, false, "depleted_air")
	_check("depleted in the air: restart first and focused, resume only to watch the fall",
		hud.restart_button.get_index() < hud.resume_button.get_index() and hud.resume_button.visible
		and not hud.resume_button.disabled and hud.resume_button.text == "Resume to watch the fall", hud.resume_button.text)
	hud.show_menu("depleted", true, false, "depleted_ground")
	_check("depleted on the ground: no resume", not hud.resume_button.visible and hud.resume_button.disabled)
	hud.show_menu("paused", true, false, "")
	_check("a flyable quad: resume first", hud.resume_button.visible and hud.resume_button.text == "Resume flight"
		and hud.resume_button.get_index() < hud.restart_button.get_index())


## After a flight a throttle limit choice waits for Restart on pad; the flight keeps its own.
func _limit_after_flight(activity: Node) -> void:
	activity.handle_action("throttle_limit")
	_check("after a flight the new limit is pending, the flight keeps its own and the menu says so",
		is_equal_approx(float(activity.session.options.throttle_limit), 1.0) and is_equal_approx(activity.input.throttle_limit(), 0.35)
		and activity.hud.limit_note.visible and "35%" in activity.hud.limit_note.text, activity.hud.limit_note.text)


func _focus(activity: Node) -> void:
	activity.handle_action("resume")
	for i in 6:
		await physics_frame
	_check("resume after restart flies again", not activity.session.paused)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var held: int = activity.session.sim.tick
	for i in 10:
		await physics_frame
	_check("losing focus holds the flight behind the menu", activity.session.paused and activity.hud.menu_visible
		and activity.session.sim.tick == held)
	activity.handle_action("resume")
	for i in 6:
		await physics_frame
	_check("explicit resume continues the same flight", not activity.session.paused and activity.session.sim.tick > held)


func _switching(app: Node) -> void:
	var counts: Array[int] = []
	for cycle in 2:
		app.home.ground_vehicle_button.pressed.emit()
		for i in 4:
			await process_frame
		var activity: Node = app.ground_vehicle
		if activity == null or activity.name != "MultirotorActivity":
			_check("switch cycle %d starts the activity" % cycle, false)
			return
		activity.handle_action("home")
		for i in 8:
			await process_frame
		counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_check("rapid Home <-> activity switching leaks no node", counts.size() == 2 and counts[1] <= counts[0]
		and root.find_child("MultirotorActivity", true, false) == null, str(counts))


func _direct_route(ui: RefCounted) -> void:
	var ok: Dictionary = Catalog.route_from_args(PackedStringArray(["--multirotor=openrc-fpv5-x1"]))
	_check("direct route parses the valid id", ok.requested and ok.ok and ok.id == Catalog.ID)
	var unknown: Dictionary = Catalog.route_from_args(PackedStringArray(["--multirotor=x9"]))
	_check("an unknown id is a useful refusal naming the valid id", unknown.requested and not unknown.ok
		and Catalog.ID in str(unknown.error) and "x9" in str(unknown.error), str(unknown.error))
	var extra: Dictionary = Catalog.route_from_args(PackedStringArray(["--multirotor=openrc-fpv5-x1", "--aircraft=stik"]))
	_check("a second option is refused, not passed to the airplane parser", extra.requested and not extra.ok, str(extra.error))
	_check("airplane arguments do not request the multirotor route",
		not Catalog.route_from_args(PackedStringArray(["--aircraft=stik"])).requested)
	var accumulated_before := Input.use_accumulated_input
	var app := AppRoot.new()
	app.user_args = PackedStringArray(["--multirotor=openrc-fpv5-x1"])
	app.preferences_path = "user://test_mr_activity_settings.cfg"
	app.update_check_url = "http://127.0.0.1:1/unavailable"
	root.add_child(app)
	for i in 4:
		await process_frame
	var activity: Node = app.ground_vehicle
	_check("--multirotor= starts the activity directly, without Home or a fixed-wing flight", activity != null
		and activity.name == "MultirotorActivity" and app.home == null and app.flight == null
		and str(activity.startup_error).is_empty())
	_check("a direct launch disables input accumulation itself", not Input.use_accumulated_input)
	await ui.close_app(app)
	_check("leaving the direct route restores input accumulation", Input.use_accumulated_input == accumulated_before)


func _fixture_and_direct_launch() -> void:
	Input.use_accumulated_input = true
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.frame_model = "res://assets/multirotors/openrc-fpv5/missing_frame.glb"
	root.add_child(activity)
	await process_frame
	_check("standalone activity starts: " + str(activity.startup_error), str(activity.startup_error).is_empty())
	_check("a missing frame falls back to the LAB FIXTURE and the OSD says so", activity.visual.fixture
		and activity.hud.fixture_label.visible and activity.hud.fixture_label.text == "LAB FIXTURE VISUAL"
		and not str(activity.visual.fallback_reason).is_empty(), str(activity.visual.fallback_reason))
	_check("audio disabled allocates no player", activity._audio == null and activity.find_children("*", "AudioStreamPlayer3D", true, false).is_empty())
	_check("standalone entry turns accumulation off", not Input.use_accumulated_input)
	root.remove_child(activity)
	activity.free()
	_check("standalone exit restores the previous accumulation", Input.use_accumulated_input)


## 2026-11-12 drone audit fixes: the app's selected flight device (not the first joypad) flies the quad and a changed
## selection holds the flight; Start only from the active gamepad; a queued race action dies with the menu; telemetry
## is evaluated once per accepted tick; the race start hint only on the ground; OSD colours set only on change.
func _audit_fixes() -> void:
	var registry := FakeRegistry.new()
	registry.devices[7] = {id = 7, connected = true, name = "Test gamepad", guid = "0300test", known = true, kind = "gamepad"}
	registry.flight = 7
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.controller_registry = registry
	activity.controller_profile_for = func(_id: int) -> Dictionary: return {}
	# ControllerService._confirmed_gamepad_connection stand-in: the selected pad of this connection generation.
	activity.controller_confirmation = func(id: int, expected_id: int, generation: int) -> bool:
		return id == expected_id and generation == registry.connection_generation(id) and registry.flight == id
	root.add_child(activity)
	await process_frame
	var first_sample: Dictionary = activity.input.sample(DT, false)
	_check("a confirmed gamepad is ready at once, without moving the sticks", bool(first_sample.ready),
		str(first_sample.get("error", "")))
	_check("the app's selected flight device is the source (not the first joypad)",
		activity.input.radio.connected and int(activity.input.radio.device_id) == 7 and activity.input.source() == "gamepad",
		activity.input.source())
	# Unplug: the registry drops the selection (as ControllerRegistry does); the same pad returning is adopted again.
	registry.flight = -1
	activity._joy_connection_changed(7, false)
	var dropped: bool = not activity.input.radio.connected
	activity._joy_connection_changed(7, true)
	for i in 3:
		await process_frame
	_check("an unplugged gamepad that returns flies the quad again", dropped and activity.input.radio.connected
		and int(activity.input.radio.device_id) == 7 and registry.flight == 7)
	# A profile saved for the device in use (AppRoot's profile_saved hook) is adopted as a new source.
	var custom: Dictionary = activity.input.radio.profile.duplicate(true)
	custom.roll = (custom.roll as Dictionary).duplicate(true)
	custom.roll.deadzone = 0.2
	activity.controller_profile_for = func(_id: int) -> Dictionary: return custom
	var before_profile: int = activity.input.source_generation
	activity.handle_action("resume")
	var adopted: bool = activity.apply_controller_selection(7)
	_check("a profile saved for the device in use is adopted as a new source", adopted
		and activity.input.source_generation > before_profile and is_equal_approx(float(activity.input.radio.profile.roll.get("deadzone", 0.0)), 0.2)
		and activity.session.paused, str(activity.input.radio.profile.get("roll", {})))
	activity.controller_profile_for = func(_id: int) -> Dictionary: return {}
	activity.handle_action("resume")
	var generation: int = activity.input.source_generation
	registry.select_flight(-1)
	await process_frame
	await process_frame
	_check("selecting the keyboard drops the device, holds the flight and says so", activity.input.source() == "keyboard"
		and activity.input.source_generation > generation and activity.session.paused and activity.hud.menu_visible
		and "disconnected" in activity.hud.menu_reason.text, activity.hud.menu_reason.text)
	activity.handle_action("resume")
	var start := InputEventJoypadButton.new()
	start.device = 3
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	activity._unhandled_input(start)
	_check("Start from a device that is not the active gamepad does not pause", not activity.session.paused
		and not activity.hud.menu_visible)
	activity.request_race()
	var queued: int = activity._race_action
	activity._open_menu("test hold")
	_check("a race action queued before a hold is dropped with the menu", queued != 0 and activity._race_action == 0,
		"queued %d" % queued)
	var first: Dictionary = activity._current_telemetry()
	_check("telemetry is evaluated once per accepted tick", is_same(first, activity._current_telemetry()))
	activity.restart_on_pad()
	_check("a pad restart drops the cached telemetry", not is_same(first, activity._current_telemetry()))
	var hud: CanvasLayer = activity.hud
	var t: Dictionary = activity._current_telemetry().duplicate(true)
	t.race = {phase = "IDLE"}
	t.altitude_agl_m = 0.02
	t.speed_mps = 0.0
	hud.update(t, {})
	var on_pad: bool = hud.race_label.visible
	t.altitude_agl_m = 12.0
	t.speed_mps = 8.0
	hud.update(t, {})
	_check("the race start hint shows on the ground and hides in flight", on_pad and not hud.race_label.visible)
	t.race = {phase = "RACING", laps = [{}, {}, {}], valid_laps = 0, next_gate = 1, gate_count = 6, elapsed_lap_s = 3.0}
	hud.update(t, {})
	_check("a race in progress keeps its line in flight", hud.race_label.visible and "Lap" in hud.race_label.text, hud.race_label.text)
	_check("OSD colours are cached per label", hud._label_colors.has("ArmState"))
	hud.hide_menu() # the start count stays clear of an open menu
	t.race = {phase = "COUNTDOWN", countdown_s_left = 2.4}
	hud.update(t, {})
	var counting: bool = hud.countdown_label.visible and hud.countdown_label.text == "3" and not hud.race_label.visible
	t.race = {phase = "RACING", laps = [{}, {}, {}], valid_laps = 0, next_gate = 0, gate_count = 6, elapsed_lap_s = 0.4}
	hud.update(t, {})
	var go: bool = hud.countdown_label.visible and hud.countdown_label.text == "GO"
	t.race.elapsed_lap_s = 1.5
	hud.update(t, {})
	_check("the race start count is large: 3 2 1, then GO for one second", counting and go and not hud.countdown_label.visible)
	root.remove_child(activity)
	activity.free()


## A plain pause in the air resumes at the frozen keyboard throttle (no drop); the zero-throttle resume is reserved for
## a recovery across a source change (FPV/02 §6).
func _pause_keeps_throttle() -> void:
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	root.add_child(activity)
	await process_frame
	var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	activity.handle_action("resume")
	_ticks(activity, 4)
	keys.arm = true
	_ticks(activity, 4)
	keys.arm = false
	keys.throttle = 1.0
	_ticks(activity, 60)
	keys.throttle = 0.0
	_ticks(activity, 2)
	var held: float = activity.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]
	var armed: bool = activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	activity._open_menu("Flight paused")
	var label: String = activity.hud.resume_button.text
	activity.handle_action("resume")
	_ticks(activity, 1)
	_check("a plain pause resumes at the frozen keyboard throttle (no drop)", armed and held > 0.1
		and label == "Resume flight" and activity.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == held,
		"%s %.3f -> %.3f" % [label, held, activity.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]])
	root.remove_child(activity)
	activity.free()


## A radio selected in the app: the flight is prepared for it from the start (absolute throttle, full range), so it
## can resume without a Restart; while it is not ready the OSD says so instead of "No controller".
func _radio_source() -> void:
	var registry := FakeRegistry.new()
	registry.devices[8] = {id = 8, connected = true, name = "Test radio", guid = "0300radio", known = false, kind = "radio"}
	registry.flight = 8
	var activity: Node3D = Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.controller_registry = registry
	activity.controller_profile_for = func(_id: int) -> Dictionary: return {}
	root.add_child(activity)
	await process_frame
	_check("a selected radio prepares the flight with its own throttle policy and limit", activity.input.source() == "radio"
		and str(activity.session.options.throttle_policy) == "absolute" and is_equal_approx(float(activity.session.options.throttle_limit), 1.0),
		"%s %s" % [activity.session.options.throttle_policy, activity.session.options.throttle_limit])
	activity.handle_action("resume")
	_ticks(activity, 2)
	activity._process(0.0)
	_check("an uncalibrated radio is reported as not ready, not as missing", not bool(activity._last_input.get("ready", true))
		and "not ready" in activity.hud.hint_label.text and "Controller not ready" in activity.hud.arm_label.text,
		"%s | %s" % [activity.hud.hint_label.text, activity.hud.arm_label.text])
	root.remove_child(activity)
	activity.free()
