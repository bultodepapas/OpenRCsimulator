# D10-R2 flight-log baseline (2026-10-18): records a deterministic Ugly Stik .orfl through the real FlightSession input
# sampling, for the docs/FLIGHT-LOGGING.md baseline/exact-replay/candidate comparison. Tape from the trimmed 15 m/s
# airborne start moved to 150 m: 1.0 s hands off, full rudder right 0.5 s then left 0.5 s, 2.0 s released, a 0.3 s 15 %
# right aileron pulse (≈ 8° of bank, small enough for the linear spiral), then 16 s hands off (bank drift). Sticks are
# session commands; the session applies its own rates and trims.
# Run from the repository root:
#   godot --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/record_tape.gd" -- --out=tmp/d10r2/baseline.orfl
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")


func _initialize() -> void:
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	if out.is_empty():
		printerr("--out=<path.orfl> is required")
		quit(2)
		return
	if not out.is_absolute_path():
		out = ProjectSettings.globalize_path("res://..").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	Engine.physics_ticks_per_second = 240
	var session := FlightSession.new()
	session.input_enabled = false
	session.setup()
	session.set_start_altitude(150.0)
	session.reset()
	if not session.is_flyable():
		printerr("Stik is not flyable")
		quit(1)
		return
	var log := FlightLog.new(session)
	if log.start(out) != OK:
		printerr("cannot start the flight log")
		quit(1)
		return
	var throttle: float = session.start.throttle
	var ticks := int(round(20.3 * 240.0))
	for tick in ticks:
		var t := tick / 240.0
		var yaw := 0.0
		var roll := 0.0
		if t >= 1.0 and t < 1.5: yaw = 1.0
		elif t >= 1.5 and t < 2.0: yaw = -1.0
		if t >= 4.0 and t < 4.3: roll = 0.15
		session.commands = { roll = roll, pitch = 0.0, yaw = yaw, throttle = throttle }
		session.sim.inputs = session._inputs()
		session.sim.step()
		if not session.sim.fault_reason.is_empty():
			printerr("fault: ", session.sim.fault_reason)
			break
	print("stop: ", log.stop(), " ticks ", session.sim.tick, " -> ", out)
	session.free()
	quit(0)
