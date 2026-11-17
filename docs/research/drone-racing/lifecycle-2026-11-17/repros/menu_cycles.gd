# Diagnostic witnesses, not regression tests for repaired behavior.
# Run with the checked runner from this checkout; headless event/state evidence only.
# The only overridden production seam is _session_options for admitted starts and
# an explicitly invalid candidate used to exercise prepare refusal.
extends SceneTree

const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const UiInput := preload("res://ui/ui_input.gd")
const DT := 1.0 / 240.0

class AuditActivity extends "res://vehicles/multirotor/multirotor_scene.gd":
	var option_overrides: Dictionary = {}
	func _session_options() -> Dictionary:
		var opts := super._session_options()
		opts.merge(option_overrides, true)
		return opts

var _count := 0
var _failures := 0
var _observations: Array[Dictionary] = []
var _directory := "user://lifecycle-menu-%d" % Time.get_ticks_usec()
var _sequence := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(id: String, label: String, ok: bool, facts: Dictionary = {}) -> void:
	_count += 1
	if not ok:
		_failures += 1
	_observations.append({id = id, label = label, observed = ok, facts = facts})
	print("%s %s %s %s" % ["ok" if ok else "FAIL", id, label, JSON.stringify(facts)])

func _new_activity(options: Dictionary = {}, scripted := false) -> Node3D:
	_sequence += 1
	var act := AuditActivity.new()
	act.enable_world = false
	act.enable_audio = false
	act.departure_managed = true
	act.option_overrides = options
	act.results_directory = _directory.path_join(str(_sequence))
	if scripted:
		act.scripted_pilot = _pilot
	root.add_child(act)
	act.set_physics_process(false)
	act.set_process(false)
	await process_frame
	_check("setup", "prepared activity", act.session != null and act.session.prepared and act.startup_error.is_empty())
	return act

func _pilot(tick: int) -> PackedFloat64Array:
	return Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0 if tick < 4 else 1, 1)

func _ticks(act: Node, count: int) -> void:
	for _i in count:
		act._physics_process(DT)
	act._process(0.0)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func _button(device: int, button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = device
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func _dispose(act: Node) -> void:
	var log_path: String = str(act.flight_log.path) if act.flight_log != null else ""
	root.remove_child(act)
	act.free()
	if not log_path.is_empty() and FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)
	await process_frame

func _held_keys() -> void:
	var act: Node = await _new_activity()
	var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}
	act.input.read_keys = func() -> Dictionary: return keys.duplicate()
	act.handle_action("resume")
	_ticks(act, 4)
	keys.arm = true
	_ticks(act, 4)
	keys.arm = false
	keys.throttle = 1.0
	_ticks(act, 60)
	keys.throttle = 0.0
	_ticks(act, 2)
	var frozen: float = act.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]
	act._open_menu("Flight paused")
	await _key(KEY_ESCAPE)
	_ticks(act, 1)
	_check("L01-control", "released keys preserve throttle across Resume", frozen > 0.1 and
		act.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == frozen and not act.session.paused,
		{frozen_throttle = frozen, resumed_throttle = act.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]})
	act._open_menu("Flight paused")
	keys.throttle = 1.0
	keys.pitch = 1.0
	_ticks(act, 2) # Held samples do not advance the flight.
	var before_tick: int = act.session.sim.tick
	await _key(KEY_ESCAPE)
	_ticks(act, 1)
	var after: float = act.session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]
	var pitch: float = act._last_input.pilot[FC.IN_PITCH]
	_check("L01", "held keyboard controls act on the first resumed tick", after > frozen and pitch > 0.0
		and act.session.sim.tick == before_tick + 1,
		{before_tick = before_tick, after_tick = act.session.sim.tick, frozen_throttle = frozen,
		resumed_throttle = after, first_pitch = pitch})
	await _dispose(act)

func _semantic_back() -> void:
	var act: Node = await _new_activity()
	UiInput.set_gamepad(42)
	act.hud.toggle_osd_settings()
	await process_frame
	await _button(42, JOY_BUTTON_B)
	_check("L02", "selected mapped Back leaves OSD settings open", act.hud.settings_panel.visible)
	await _key(KEY_ESCAPE)
	_check("L02-control", "physical Escape closes OSD settings without resuming", not act.hud.settings_panel.visible
		and act.hud.menu_visible and act.session.paused)
	await _button(42, JOY_BUTTON_B)
	_check("L02", "selected mapped Back leaves the flight menu open", act.hud.menu_visible and act.session.paused)
	await _key(KEY_ESCAPE)
	_check("L02-control", "physical Escape resumes from the flight menu", not act.hud.menu_visible and not act.session.paused)
	await _button(42, JOY_BUTTON_START)
	_check("L02", "selected UI-only pad Start does not open the flight menu", not act.hud.menu_visible and not act.session.paused)
	await _button(43, JOY_BUTTON_START)
	_check("L02-control", "unselected pad does not open the flight menu", not act.hud.menu_visible and not act.session.paused)
	UiInput.isolate_joypads()
	await _dispose(act)

func _depleted_ground() -> void:
	var act: Node = await _new_activity({initial_soc = 0.0})
	act.handle_action("resume")
	_ticks(act, 500)
	var before: int = act.session.sim.tick
	_check("L03-setup", "ground depletion offers restart only", act._terminal_state() == "depleted_ground"
		and act.hud.menu_visible and not act.hud.resume_button.visible and act.hud.resume_button.disabled
		and act._aftermath_until < 0.0, {tick = before, terminal = act._terminal_state()})
	await _key(KEY_ESCAPE)
	_ticks(act, 1)
	_check("L03", "Escape bypasses the hidden ground-depletion Resume", not act.session.paused and not act.hud.menu_visible
		and act.session.sim.tick == before + 1, {before_tick = before, after_tick = act.session.sim.tick})
	_check("L03-control", "bypass does not restore charge or motor power", act.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED
		and act.session.sim.continuous[Plant.C_CHARGE] == 0.0)
	await _dispose(act)
	act = await _new_activity({initial_soc = 0.0, start = "air", altitude_m = 50.0, race_track = ""})
	act.handle_action("resume")
	_ticks(act, 500)
	_check("L03-control", "air depletion offers watch-the-fall Resume", act._terminal_state() == "depleted_air"
		and act.hud.resume_button.visible and not act.hud.resume_button.disabled)
	await _key(KEY_ESCAPE)
	_check("L03-control", "air depletion remains resumable and unpowered", not act.session.paused
		and act.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED)
	await _dispose(act)

func _race_messages() -> void:
	var act: Node = await _new_activity({}, true)
	act.handle_action("resume")
	_ticks(act, 8)
	act.request_race()
	_ticks(act, 740)
	_check("L04-setup", "real countdown reaches RACING", act._race_phase() == "RACING")
	act.request_race()
	_ticks(act, 1)
	var old_title: String = act.hud.race_card_text().title
	_check("L04-setup", "G after GO publishes an aborted outcome", act._race_phase() == "ABORTED" and not old_title.is_empty())
	var reset_ok: bool = act.restart_on_pad()
	_check("L04", "restart menu carries the previous race outcome into IDLE", reset_ok and act._race_phase() == "IDLE"
		and act.hud.menu_reason.text.contains(old_title), {phase = act._race_phase(), old_title = old_title,
		menu_reason = act.hud.menu_reason.text})
	_check("L04-control", "centered race card is hidden in IDLE", not act.hud.race_card.visible)
	var old_course: String = act.session.options.race_track
	act.cycle_course()
	_check("L04", "course-change menu also keeps the old outcome", act.session.options.race_track != old_course
		and act._race_phase() == "IDLE" and act.hud.menu_reason.text.contains(old_title),
		{menu_reason = act.hud.menu_reason.text})
	act.request_race()
	_ticks(act, 1)
	_check("L04-control", "new countdown clears the cached outcome", act._race_phase() == "COUNTDOWN"
		and str(act.hud.race_card_text().title).is_empty())
	act.request_race()
	_ticks(act, 1)
	_check("L04-control", "cancelling before GO returns to IDLE without a result card", act._race_phase() == "IDLE"
		and str(act.hud.race_card_text().title).is_empty())
	await _dispose(act)

func _refused_reconfiguration() -> void:
	for requested_phase in ["IDLE", "COUNTDOWN", "RACING"]:
		var active: bool = requested_phase != "IDLE"
		var act: Node = await _new_activity({}, true)
		act.handle_action("resume")
		_ticks(act, 10)
		if active:
			act.request_race()
			_ticks(act, 740 if requested_phase == "RACING" else 10)
		act.toggle_recording()
		_ticks(act, 5)
		var tick: int = act.session.sim.tick
		var tape_size: int = act.session.tape().size()
		var armed_ticks: int = act._armed_ticks
		var phase: String = act._race_phase()
		var bad: Dictionary = act._session_options()
		bad.initial_soc = 2.0
		var direct_ok: bool = act.session.prepare(act.field, bad)
		_check("L05-control", "Session.prepare refusal preserves old flight and log", not direct_ok
			and act.session.sim.tick == tick and act.session.tape().size() == tape_size and act.flight_log.recording,
			{active_attempt = active, tick = tick, phase = phase})
		act.input.cycle_throttle_limit()
		act.option_overrides.initial_soc = 2.0 # Controlled invalid candidate; no file or disk corruption.
		var restarted: bool = act.restart_on_pad()
		_check("L05", "scene restart reports refusal but closes the old recording", not restarted and not act.flight_log.recording,
			{active_attempt = active, old_tick = tick, new_tick = act.session.sim.tick,
			old_phase = phase, new_phase = act._race_phase(), armed_ticks_before = armed_ticks,
			armed_ticks_after = act._armed_ticks, message = act.hud.message.text})
		if active:
			_check("L05", "active attempt was already reset before prepare refusal", act.session.sim.tick == 0
				and act.session.tape().is_empty() and act._race_phase() == "IDLE")
		else:
			_check("L05", "inactive attempt keeps session state but resets scene counters", act.session.sim.tick == tick
				and act.session.tape().size() == tape_size and armed_ticks > 0 and act._armed_ticks == 0)
		act.option_overrides.erase("initial_soc")
		var accepted: bool = act.restart_on_pad()
		_check("L05-control", "valid replacement applies the pending limit at a paused pad", accepted and act.session.sim.tick == 0
			and act.session.paused and is_equal_approx(act.session.options.throttle_limit, act.input.throttle_limit()))
		await _dispose(act)

func _crash_reason() -> void:
	for early_focus in [true, false]:
		var act: Node = await _new_activity({start = "air", altitude_m = 8.0, race_track = ""})
		act.handle_action("resume")
		var crashed := false
		for _i in 2000:
			_ticks(act, 1)
			if not act.session.crash.is_empty():
				crashed = true
				break
		_check("L08-setup", "admitted airborne free fall produces a real crash", crashed,
			{tick = act.session.sim.tick, early_focus = early_focus})
		if not crashed:
			await _dispose(act)
			continue
		if not early_focus:
			_ticks(act, 500)
		act.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		var tick: int = act.session.sim.tick
		_ticks(act, 600)
		var reason: String = act.hud.menu_reason.text
		if early_focus:
			_check("L08", "focus during crash aftermath leaves a generic menu reason", reason == "Paused: the window lost focus."
				and not act._crash_cause.is_empty() and act._aftermath_until >= 0.0 and act.session.sim.tick == tick,
				{menu_reason = reason, crash_cause = act._crash_cause, hint = act.hud.hint_label.text})
		else:
			_check("L08-control", "focus after the aftermath preserves the crash reason", reason.begins_with("Crashed:"),
				{menu_reason = reason})
		await _key(KEY_ESCAPE)
		_check("L08-control", "crashed flight refuses shortcut Resume", act.session.paused and act.hud.menu_visible)
		await _key(KEY_R)
		_check("L08-control", "R deliberately resets and resumes from the crash menu", act.session.crash.is_empty()
			and not act.session.paused and not act.hud.menu_visible and act.session.sim.tick == 0)
		await _dispose(act)

func _clean(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for child in DirAccess.get_directories_at(path):
		_clean(path.path_join(child))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

func _run() -> void:
	root.size = Vector2i(1920, 1080) # Layout coordinates only; no native/rendered qualification.
	await _held_keys()
	await _semantic_back()
	await _depleted_ground()
	await _race_messages()
	await _refused_reconfiguration()
	await _crash_reason()
	_clean(_directory)
	print("LIFECYCLE_MENU_JSON " + JSON.stringify({checks = _count, failures = _failures, observations = _observations}))
	print("LIFECYCLE MENU: %d checks, %d failures" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
