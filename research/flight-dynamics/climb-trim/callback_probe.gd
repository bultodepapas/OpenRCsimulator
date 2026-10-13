# Actual SceneTree callback probe for the production flight session and simulation.
# Run from the repository root with the Godot binary:
# Godot --headless --path app --script ../research/flight-dynamics/climb-trim/callback_probe.gd -- --fps=60
# Repeat with --fps=15,30,60,144. State hashes should match for the same tick count;
# low render caps may stretch wall time after max_physics_steps_per_frame is reached.
extends SceneTree

const Spec := preload("res://spec.gd")

var _main: Node
var _fps := 60
const TOTAL_TICKS := 240
const HOLD_TICKS := 48

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="):
			_fps = int(arg.trim_prefix("--fps="))
	Engine.max_fps = _fps
	_run.call_deferred()

func _run() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	var session: Node = _main.session
	if session == null or session.sim == null:
		printerr("NO_SESSION")
		quit(2)
		return
	# Make the result independent of any physical radio attached to the host.
	session.radio.disconnect_device()
	session.hold("rate-probe-setup")
	session.reset()
	var tick_zero: int = session.sim.tick
	if tick_zero != 0:
		printerr("BAD_START_TICK ", tick_zero)
		quit(2)
		return
	session.release("rate-probe-setup")
	session.resume()
	var start_command: float = session.commands.throttle
	var start_usec: int = Time.get_ticks_usec()
	_key(KEY_W, true)
	for i in HOLD_TICKS:
		await session.sim.stepped
	var hold_command: float = session.commands.throttle
	_key(KEY_W, false)
	for i in TOTAL_TICKS - HOLD_TICKS:
		await session.sim.stepped
	var state: PackedFloat64Array = session.sim.state
	var bytes: PackedByteArray = var_to_bytes([state, session.sim.inputs, session.commands])
	var hold_delta: float = hold_command - start_command
	var expected_time: float = float(TOTAL_TICKS) / float(Engine.physics_ticks_per_second)
	var expected_hold: float = float(HOLD_TICKS) * session.sim.dt() * float(Spec.CONTROLS.throttle_rate)
	var tick_ok: bool = session.sim.tick == TOTAL_TICKS
	var time_ok: bool = absf(session.sim.time() - expected_time) <= 1e-12
	var hold_ok: bool = absf(hold_delta - expected_hold) <= 1e-12
	print("RATE_PROBE fps=%d hz=%d cap=%d ticks=%d tick=%d sim_s=%.12f real_s=%.6f hold=%.12f start=%.12f end=%.12f state_md5=%s inputs=%s" % [
		_fps, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame, TOTAL_TICKS, session.sim.tick, session.sim.time(),
		float(Time.get_ticks_usec() - start_usec) / 1000000.0, hold_delta, start_command,
		hold_command, bytes.hex_encode().md5_text(), str(session.sim.inputs)])
	if not tick_ok or not time_ok or not hold_ok:
		printerr("RATE_PROBE_FAILED tick_ok=%s time_ok=%s hold_ok=%s expected_time=%.12f expected_hold=%.12f" % [
			str(tick_ok), str(time_ok), str(hold_ok), expected_time, expected_hold])
		quit(3)
		return
	_key(KEY_W, false)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	await process_frame
	_main.free()
	quit()

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


