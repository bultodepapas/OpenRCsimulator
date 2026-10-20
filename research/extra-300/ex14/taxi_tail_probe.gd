# EX-14c probe (read-only): the RCM April 2000 taxi test of the GP Extra 300S .60, "at 1/3 throttle, the tail lifted
# off the ground". Qualified runway start, glow engine started, then a fixed throttle with the elevator neutral and the
# rudder holding the runway heading (PD), for up to 20 s. Reports when the tail wheel unloads (compression 0), the
# ground speed then, the peak rudder and the heading excursion, and the lift-off if it comes first. One JSON line per
# throttle. Run against any app copy:
#   godot --headless --path <app> --audio-driver Dummy --script <abs>/taxi_tail_probe.gd -- [--throttles=0.25,0.33,0.5]
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const DURATION_S := 20.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var throttles := [0.25, 1.0 / 3.0, 0.5]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--throttles="):
			throttles = Array(arg.trim_prefix("--throttles=").split(",")).map(func(x: String) -> float: return float(x))
	var loaded := FieldLoader.load_from()
	if not loaded.ok:
		printerr("field: ", loaded.errors)
		quit(1)
		return
	for throttle in throttles:
		print(JSON.stringify(_taxi(float(throttle), loaded.field)))
	quit(0)


func _taxi(throttle: float, field: Dictionary) -> Dictionary:
	var session := Flight.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.setup("res://data/aircraft/gp_extra_300s_60.json", "gp-extra-300s-60")
	root.add_child(session)
	session.set_field(field)
	session.start_choice = Flight.START_RUNWAY
	session.reset()
	var out := {throttle = throttle, data_has_slipstream = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()}
	if not session.is_flyable() or not session.start_error.is_empty():
		out.error = session.start_error
		session.free()
		return out
	if session.glow_is_active() and not session.engine_running:
		session.glow_start()
	var dt: float = session.sim.dt()
	var heading0: float = M.q_to_euler(session.sim.state.slice(RB.ATT, RB.ATT + 4))[0]
	var tail_off_t := -1.0
	var tail_off_speed := NAN
	var tail_off_rpm := NAN
	var liftoff_t := -1.0
	var peak_rudder := 0.0
	var worst_heading := 0.0
	var pitch_at_tail_off := NAN
	for tick in roundi(DURATION_S / dt):
		var s: PackedFloat64Array = session.sim.state
		var euler := M.q_to_euler(s.slice(RB.ATT, RB.ATT + 4))
		var heading_error := wrapf(euler[0] - heading0, -PI, PI)
		worst_heading = maxf(worst_heading, absf(rad_to_deg(heading_error)))
		var rudder := clampf(-2.0 * heading_error - 0.6 * s[RB.RATE + 2], -1.0, 1.0)
		peak_rudder = maxf(peak_rudder, absf(rudder))
		var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
		inputs[0] = 0.0
		inputs[1] = 0.0
		inputs[2] = rudder
		inputs[3] = throttle
		session.sim.inputs = inputs
		session.sim.step()
		session._physics_process(dt)
		if not session.sim.fault_reason.is_empty() or not session.crash.is_empty() or not session.prop_strike.is_empty():
			out.stopped = session.sim.fault_reason + str(session.crash) + str(session.prop_strike)
			break
		var c: PackedFloat64Array = session.gear_compressions(session.sim.state)
		var t := (tick + 1) * dt
		var v: PackedFloat64Array = session.sim.state.slice(RB.VEL, RB.VEL + 3)
		if tail_off_t < 0.0 and c.size() == 3 and c[2] <= 0.0 and (c[0] > 0.0 or c[1] > 0.0):
			tail_off_t = t
			tail_off_speed = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
			tail_off_rpm = session.sim.aux[0] if session.sim.continuous.is_empty() else session.sim.continuous[0]
			pitch_at_tail_off = rad_to_deg(M.q_to_euler(session.sim.state.slice(RB.ATT, RB.ATT + 4))[1])
		if liftoff_t < 0.0 and c.size() == 3 and c[0] <= 0.0 and c[1] <= 0.0 and c[2] <= 0.0:
			liftoff_t = t
			out.liftoff_speed_mps = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
			break
	out.tail_off_s = tail_off_t
	out.tail_off_speed_mps = tail_off_speed
	out.tail_off_rpm = tail_off_rpm
	out.pitch_at_tail_off_deg = pitch_at_tail_off
	out.liftoff_s = liftoff_t
	out.peak_rudder = peak_rudder
	out.worst_heading_deg = worst_heading
	var end_v: PackedFloat64Array = session.sim.state.slice(RB.VEL, RB.VEL + 3)
	out.end_speed_mps = sqrt(end_v[0] * end_v[0] + end_v[1] * end_v[1] + end_v[2] * end_v[2])
	session.free()
	return out
