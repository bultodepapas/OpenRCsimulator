# EX-14c probe (read-only): a hammerhead (stall turn) flown the way RC pilots fly one with a glow engine, unlike the FT
# card's idle up-line: full-throttle pull to vertical from 30 m/s, the up-line held at a set throttle so the propwash
# stays on the tail, then at the kick speed full rudder; ailerons hold the roll rate at zero against the torque, the
# elevator holds the pitch rate at zero (the pivot stays in its plane). The pivot ends when the nose points 70 deg down.
# Reports pivot time, the horizontal radius swept by the CG, the roll angle accumulated, the least forward speed (a tail
# slide goes negative) and whether the nose came round by yaw. One JSON line per case.
#   godot --headless --path <app> --audio-driver Dummy --script <abs>/hammerhead_probe.gd -- [--kick=6] [--throttle=0.5]
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


func _initialize() -> void:
	var kick := 6.0
	var throttle := 0.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kick="):
			kick = float(arg.trim_prefix("--kick="))
		elif arg.begins_with("--throttle="):
			throttle = float(arg.trim_prefix("--throttle="))
	for direction in [1.0, -1.0]:
		print(JSON.stringify(_hammerhead(direction, kick, throttle)))
	quit(0)


## Nose direction in NED from the body x axis.
func _nose(s: PackedFloat64Array) -> PackedFloat64Array:
	var q := s.slice(RB.ATT, RB.ATT + 4)
	var w := q[0]
	var x := q[1]
	var y := q[2]
	var z := q[3]
	return PackedFloat64Array([1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y + w * z), 2.0 * (x * z - w * y)])


func _hammerhead(direction: float, kick: float, throttle: float) -> Dictionary:
	var session := Flight.new()
	session.setup(Catalog.entry("gp-extra-300s-60").data)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	session.trim_at(30.0, "level")
	session.set_start_altitude(300.0)
	session.reset()
	var sim: Node = session.sim
	var dt: float = sim.dt()
	var phase := "pull"
	var out := {case = "right" if direction > 0.0 else "left", kick_mps = kick, throttle = throttle,
		data_has_slipstream = not session.aircraft.model.propulsion.get("slipstream", {}).is_empty()}
	var t_kick := -1.0
	var kick_pos := PackedFloat64Array()
	var roll_acc := 0.0
	var min_u := INF
	var max_radius := 0.0
	var yaw_integral := 0.0
	var pitch_integral := 0.0
	var h0 := _nose(sim.state)  # entry heading (horizontal) of the figure's vertical plane
	for tick in roundi(20.0 / dt):
		var s: PackedFloat64Array = sim.state
		var nose := _nose(s)
		var elevation := rad_to_deg(asin(clampf(-nose[2], -1.0, 1.0)))
		# Signed angle in the entry plane: 90 = vertical, above 90 = past vertical over the top.
		var plane_angle := rad_to_deg(atan2(-nose[2], nose[0] * h0[0] + nose[1] * h0[1]))
		# Out of that plane (positive to the right of the entry heading), held with the rudder on the up-line.
		var lateral := rad_to_deg(asin(clampf(-nose[0] * h0[1] + nose[1] * h0[0], -1.0, 1.0)))
		var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
		var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0}
		var p: float = s[RB.RATE]
		var q: float = s[RB.RATE + 1]
		var r: float = s[RB.RATE + 2]
		if phase == "pull":
			c.pitch = clampf(0.6 - 0.2 * q, -1.0, 1.0)
			c.roll = clampf(-0.3 * p, -1.0, 1.0)
			if plane_angle > 85.0:
				phase = "upline"
		elif phase == "upline":
			c.throttle = throttle
			c.pitch = clampf(0.04 * (90.0 - plane_angle) - 0.3 * q, -1.0, 1.0)
			c.yaw = clampf(-0.05 * lateral - 0.3 * r, -1.0, 1.0)
			c.roll = clampf(-0.3 * p, -1.0, 1.0)
			if speed < kick:
				phase = "pivot"
				t_kick = tick * dt
				kick_pos = s.slice(RB.POS, RB.POS + 3)
		elif phase == "pivot":
			c.throttle = throttle
			c.yaw = direction
			c.roll = clampf(-0.6 * p, -1.0, 1.0)
			c.pitch = clampf(-0.5 * q, -1.0, 1.0)
			roll_acc += rad_to_deg(p) * dt
			min_u = minf(min_u, s[RB.VEL])
			yaw_integral += rad_to_deg(absf(r)) * dt
			pitch_integral += rad_to_deg(absf(q)) * dt
			var dn: float = s[RB.POS] - kick_pos[0]
			var de: float = s[RB.POS + 1] - kick_pos[1]
			max_radius = maxf(max_radius, sqrt(dn * dn + de * de))
			if elevation < -70.0:
				out.pivot_time_s = tick * dt - t_kick
				break
			if tick * dt - t_kick > 6.0:
				out.pivot_time_s = -1.0
				out.final_elevation_deg = elevation
				break
		session.commands = {roll = c.roll, pitch = c.pitch, yaw = c.yaw, throttle = c.throttle}
		sim.inputs = session._inputs()
		sim.step()
		if not sim.fault_reason.is_empty() or not session.crash.is_empty():
			out.stopped = sim.fault_reason + str(session.crash)
			break
	out.kick_time_s = t_kick
	out.roll_during_pivot_deg = roll_acc
	out.least_forward_speed_mps = min_u
	out.cg_sweep_radius_m = max_radius
	out.cg_sweep_radius_spans = max_radius / float(session.aircraft.model.reference.b)
	out.yaw_rotation_deg = yaw_integral
	out.pitch_rotation_deg = pitch_integral
	out.came_round_by = "yaw" if yaw_integral > pitch_integral else "pitch"
	out.rpm_end = sim.continuous[0] if not sim.continuous.is_empty() else sim.aux[0]
	session.free()
	return out
