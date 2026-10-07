# D6a end to end: a fake radio (device 15, injected InputEventJoypadMotion) flying the real main scene.
# Arming, unshaped sticks, the unplug failsafe and the return to the keyboard.
# Never calls Input.get_joy_guid on the fake device (that prints an engine error): device_info is replaced.
# Run: godot --headless --path . --script res://tests/test_e2e_radio.gd
extends SceneTree

const ID := 15 # a real radio on the dev machine would take id 0
const PROFILES := "user://test_e2e_rc_calibration.cfg"

var _failures := 0
var _main: Node
var _session: Node


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _motion(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new() # a new event each time (debug builds warn on reuse)
	e.device = ID
	e.axis = axis as JoyAxis
	e.axis_value = value
	Input.parse_input_event(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)


func _panel_has(text: String) -> bool:
	return text in (_main._panel as Label).text


## Counted in ticks and frames, not wall time: a slow first frame could eat a timer before any tick ran.
func _settle() -> void:
	for i in 4:
		await physics_frame # emitted before a tick; 4 awaits guarantee 3 complete ticks
	await process_frame
	await process_frame # the panel updates in _process


func _initialize() -> void:
	_run()


func _run() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	await _settle()
	_session = _main.session
	_session.device_info = func(_device: int) -> Dictionary:
		return { guid = "fake", name = "Fake EdgeTX", vendor_id = 0x1209, product_id = 0x4f54 }
	_session.profiles_path = PROFILES # never the pilot's real calibration file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILES))
	_check("starts on the keyboard", not _session.radio.connected and _panel_has("input: keyboard"))

	Input.joy_connection_changed.emit(ID, true)
	await _settle()
	_check("radio connected with its device key", _session.radio.connected and _session.radio.device_key == "fake|1209:4f54|Fake EdgeTX", _session.radio.device_key)
	_check("untouched throttle (reads mid-stick) keeps the engine at idle", _session.commands.throttle == 0.0 and _session.radio.throttle_position() == 0.5, "throttle %s, stick %s, axes %s" % [_session.commands.throttle, _session.radio.throttle_position(), _session.radio.axes])
	_check("panel says SAFE", _panel_has("SAFE"))

	_motion(2, 0.2)
	await _settle()
	_check("throttle moved to 60 %: still SAFE", not _session.radio.armed and _session.commands.throttle == 0.0)
	_motion(2, -1.0)
	await _settle()
	_check("throttle low: ARMED", _session.radio.armed and _panel_has("ARMED"))
	_motion(2, 1.0)
	await _settle()
	_check("armed: full throttle", _session.commands.throttle == 1.0)

	_motion(0, 1.0)
	await _settle()
	_check("roll stick full right → +1 at once (radio positions are not rate-limited)", _session.commands.roll == 1.0)
	_check("the simulation flies it (stick + trim, clamped)", _session.sim.inputs[0] == 1.0, str(_session.sim.inputs))
	_motion(1, 1.0)
	await _settle()
	_check("elevator stick forward → pitch −1 (nose down)", _session.commands.pitch == -1.0)

	Input.joy_connection_changed.emit(ID, false)
	await _settle()
	_check("unplug: simulation paused", _session.sim.paused)
	_check("unplug: engine idle, sticks centred", _session.commands.throttle == 0.0 and _session.commands.roll == 0.0 and _session.commands.pitch == 0.0)
	_check("unplug: panel says why", _panel_has("PAUSED (radio disconnected)"))
	var t0: float = _session.sim.time()
	await _settle()
	_check("unplug: stays paused (no automatic resume)", _session.sim.paused and _session.sim.time() == t0)

	_key(KEY_P)
	await _settle()
	_check("P resumes on the keyboard", not _session.sim.paused and _panel_has("input: keyboard"))

	# Godot keeps the fake device's last axis values (throttle high) after the unplug.
	Input.joy_connection_changed.emit(ID, true)
	await _settle()
	_check("replug with the throttle stick high: SAFE, idle", not _session.radio.armed and _session.commands.throttle == 0.0, "position %.2f" % _session.radio.throttle_position())

	# D6b: calibrate a radio whose aileron is on axis 3 and rudder on axis 0 (swapped from the default).
	for a in [0, 1, 3]:
		_motion(a, 0.0)
	_motion(2, -1.0)
	await _settle()
	_key(KEY_K)
	await _settle()
	_check("K starts the calibration (paused, step 1)", _panel_has("CALIBRATION 1/5") and _session.sim.paused, (_main._panel as Label).text)
	_key(KEY_ENTER) # rest
	await _settle()
	for move in [[2, [1.0, -1.0]], [3, [1.0, -1.0, 0.0]], [1, [-1.0, 1.0, 0.0]], [0, [1.0, -1.0, 0.0]]]:
		for v in move[1]:
			_motion(move[0], v)
			await _settle()
		_key(KEY_ENTER)
		await _settle()
	var p: Dictionary = _session.radio.profile
	_check("calibrated: aileron axis 3, rudder axis 0, elevator inverted", p.roll.axis == 3 and p.yaw.axis == 0 and p.pitch.invert and p.throttle.axis == 2, str(p))
	_check("calibration saved for this device", FileAccess.file_exists(PROFILES) and _panel_has("radio calibrated"))
	_key(KEY_P)
	await _settle()
	_motion(3, 1.0)
	await _settle()
	_check("after calibration: axis 3 flies the ailerons; armed by the low throttle", _session.commands.roll == 1.0 and _session.radio.armed, str(_session.commands))
	Input.joy_connection_changed.emit(ID, false)
	await _settle()
	Input.joy_connection_changed.emit(ID, true)
	await _settle()
	_check("replug loads the saved calibration", _session.radio.profile_source == "calibrated" and _session.radio.profile.roll.axis == 3)
	_check("valid saved replug still requires a fresh throttle event", not _session.radio.armed and _session.commands.throttle == 0.0)
	_key(KEY_K)
	await _settle()
	_key(KEY_ESCAPE)
	await _settle()
	_check("Esc cancels; the calibration stays", _session.calibration == null and _session.radio.profile.roll.axis == 3)

	# D6b-R1: malformed files cannot partially apply a mapping when the device is reconnected.
	# Keep throttle high across replug: a rejected calibration must not bypass arming.
	for defect: String in ["duplicate_axis", "nan_endpoint", "wrong_identity"]:
		Input.joy_connection_changed.emit(ID, false)
		await _settle()
		_motion(2, 1.0)
		var bad: Dictionary = p.duplicate(true)
		var identity: String = _session.radio.device_key
		if defect == "duplicate_axis":
			bad.pitch.axis = bad.roll.axis
		elif defect == "nan_endpoint":
			bad.roll.min = NAN
		var cfg: ConfigFile = ConfigFile.new()
		cfg.set_value(identity.md5_text(), "device_key", "another device" if defect == "wrong_identity" else identity)
		cfg.set_value(identity.md5_text(), "profile", bad)
		_check("writes malformed fixture " + defect, cfg.save(PROFILES) == OK)
		Input.joy_connection_changed.emit(ID, true)
		await _settle()
		_check("invalid profile falls back completely " + defect,
			_session.radio.profile_source == "default" and _session.radio.profile == _session.radio.DEFAULT_PROFILE)
		_check("rejected profile remains safe at high throttle " + defect,
			not _session.radio.armed and _session.commands.throttle == 0.0 and _session.sim.paused)
		_motion(2, -1.0)
		await _settle()
		_check("fallback profile can rearm at low throttle " + defect, _session.radio.armed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILES))

	print("all e2e radio checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
