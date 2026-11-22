# Diagnostic only. Uses the shipped data and the real multirotor session and plant.
# Constructed frame cases do not establish reachability from a player flight.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Airframe := preload("res://physics/multirotor/airframe.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var failures := 0
var checks := 0

func check(label: String, condition: bool, details: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label + " " + details)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var prepared: bool = s.prepare({}, {start = "air", altitude_m = 20.0, initial_soc = 1.0})
	check("stock research air session prepares", prepared, s.load_error)
	if not prepared:
		quit(1)
		return
	var selected := -1
	for i in 4:
		if float(s.data.rotors[i].spin) == 1.0:
			selected = i
			break
	check("stock rotor with spin +1 found", selected >= 0)
	if selected < 0:
		quit(1)
		return
	for yaw: float in [0.0, 10.0, 20.0]:
		_rate_case(s, selected, yaw)
	s.free()
	_pad_climb()
	print("R7_ROTOR_COMPLETE %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _rate_case(s: Node, idx: int, yaw: float) -> void:
	var frame: Dictionary = s.frame()
	frame = s.plant.initial_frame(frame.body, 0, 1.0)
	for i in 4:
		frame.continuous[i] = 0.0
	frame.continuous[idx] = 10.0
	var h: PackedFloat64Array = s.data.rotors[idx].hub_frd
	frame.body[RB.RATE] = 0.0
	frame.body[RB.RATE + 1] = 0.0
	frame.body[RB.RATE + 2] = yaw
	# In a still atmosphere, this makes the selected hub stationary instantaneously.
	frame.body[RB.VEL] = yaw * h[1]
	frame.body[RB.VEL + 1] = -yaw * h[0]
	frame.body[RB.VEL + 2] = 0.0
	var valid: bool = s.plant.state_validator(frame, {})
	var pilot: PackedFloat64Array = FC.neutral_input()
	var reset: Dictionary = s.sim.prepare_reset_frame(frame, pilot)
	check("constructed frame validator and kernel preparation yaw %.1f" % yaw, valid and reset.ok, str(reset.get("message", "")))
	if not reset.ok:
		return
	var committed: bool = s.sim.commit_prepared_reset_frame(reset)
	check("constructed frame committed yaw %.1f" % yaw, committed)
	if not committed:
		return
	frame = s.frame()
	var eval: Dictionary = s.plant._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	var loads: PackedFloat64Array = eval.loads
	var mass: float = float(s.data.mass_kg)
	var inertia: PackedFloat64Array = s.data.inertia_kg_m2
	var force := M.v3(loads[0], loads[1], loads[2])
	var moment := M.v3(loads[3], loads[4], loads[5])
	var bodydot: PackedFloat64Array = RB.derivative(frame.body, mass, inertia, RB.inertia_inverse(inertia), force, moment, 0.0, eval.rotor_momentum)
	var v := M.v3(frame.body[RB.VEL], frame.body[RB.VEL + 1], frame.body[RB.VEL + 2])
	var vdot := M.v3(bodydot[RB.VEL], bodydot[RB.VEL + 1], bodydot[RB.VEL + 2])
	var w := M.v3(0.0, 0.0, yaw)
	var alpha := M.v3(bodydot[RB.RATE], bodydot[RB.RATE + 1], bodydot[RB.RATE + 2])
	var dke: float = mass * M.dot(v, vdot) + M.dot(w, RB.inertia_mul(inertia, alpha))
	var cross_alpha := 0.0
	var cross_speed := 0.0
	for i in 4:
		var j: float = float(s.data.rotors[i].inertia_kg_m2)
		var sign: float = float(s.data.rotors[i].spin)
		var speed: float = frame.continuous[i]
		var acceleration: float = eval.derivative[i]
		dke += j * speed * acceleration
		cross_alpha += sign * j * speed
		cross_speed += sign * j * acceleration
	dke -= alpha[2] * cross_alpha + yaw * cross_speed
	var drag: PackedFloat64Array = Airframe.loads(v, s.environment.air_density(frame.body[RB.POS + 2]), s.data.airframe)
	var drag_power: float = M.dot(drag, v)
	var omega: float = frame.continuous[idx]
	var q: float = float(s.data.rotor_law.torque_coefficient_n_m_s2) * omega * omega
	var thrust: float = float(s.data.rotor_law.thrust_coefficient_n_s2) * omega * omega
	var friction_power: float = -(1.0 / float(s.data.powertrain.kv_rad_s_per_v)) * float(s.data.powertrain.no_load_current_a) * clampf(omega / Plant.FRICTION_SPEED, -1.0, 1.0) * omega
	var rotor_port: float = q * (yaw - omega) # spin +1, relative spin omega
	var expected: float = drag_power + friction_power + rotor_port
	var port_from_dynamics: float = dke - drag_power - friction_power
	check("full gravity-free body-plus-four-rotor power identity yaw %.1f" % yaw,
		absf(dke - expected) < 2e-10, "residual %.12f W" % (dke - expected))
	check("aerodynamic thrust follows relative shaft at yaw %.1f" % yaw,
		absf(loads[2] + thrust) < 1e-12, "%.12f N" % -loads[2])
	if yaw == 0.0:
		check("zero-yaw rotational aero port is dissipative", port_from_dynamics < 0.0)
	if yaw == 10.0:
		check("stationary rotor-in-air still reports positive thrust", absf(yaw - omega) < 1e-12 and -loads[2] > 0.0)
	if yaw == 20.0:
		check("reversed air-relative rotor receives positive aerodynamic rotational power", port_from_dynamics > 0.0)
	var resumed: bool = s.resume()
	var stepped: bool = resumed and s.tick_once(pilot)
	check("a single 240 Hz session tick accepted yaw %.1f" % yaw, stepped and s.sim.tick == 1 and s.fault_reason.is_empty(), s.fault_reason)
	print("R7_RATE " + JSON.stringify({"yaw_rad_s": yaw, "relative_shaft_rad_s": omega, "air_relative_signed_rad_s": omega - yaw,
		"hub": Array(h), "body_v": Array(v), "thrust_n": -loads[2], "q_nm": q, "rotor_aero_port_w": port_from_dynamics,
		"body_drag_w": drag_power, "shaft_friction_w": friction_power, "total_mechanical_power_w": dke,
		"power_identity_residual_w": dke - expected, "accepted_tick": stepped, "tick_end_yaw": s.sim.state[RB.RATE+2],
		"body": Array(frame.body), "continuous": Array(frame.continuous), "body_derivative": Array(bodydot),
		"continuous_derivative": Array(eval.derivative), "data_sha256": s.source_sha256}, "", true, true))

func _pad_climb() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var prepared: bool = s.prepare({}, {start = "pad", initial_soc = 1.0})
	check("stock pad-start session prepares", prepared, s.load_error)
	if not prepared:
		s.free()
		return
	var pilot: PackedFloat64Array = FC.neutral_input()
	var ok: bool = s.resume() and s.tick_once(pilot)
	pilot[FC.IN_ARM] = 1.0
	ok = ok and s.tick_once(pilot)
	var best := {ratio = -1.0}
	var best_punch := {ratio = -1.0}
	var first_violation := {}
	var best_frame := {}
	var punch_frame := {}
	var first_frame := {}
	for i in 1600:
		pilot[FC.IN_THROTTLE] = 1.0 if i < 700 else 0.05
		if not s.tick_once(pilot):
			ok = false
			break
		var frame: Dictionary = s.frame()
		var ascent: float = -frame.body[RB.VEL + 2]
		var total_t := 0.0
		var total_p := 0.0
		for j in 4:
			var spin: float = maxf(0.0, frame.continuous[j])
			var health: float = frame.continuous[Plant.C_HEALTH + j]
			total_t += float(s.data.rotor_law.thrust_coefficient_n_s2) * spin * spin * health
			total_p += float(s.data.rotor_law.torque_coefficient_n_m_s2) * spin * spin * spin * maxf(health, Plant.BROKEN_PROP_LOAD)
		if total_p > 1e-12 and ascent > 0.0:
			var snapshot := {ratio = total_t * ascent / total_p, tick = s.sim.tick, altitude = -frame.body[RB.POS + 2],
				ascent = ascent, thrust_n = total_t, shaft_aero_w = total_p,
				body_thrust_power_w = total_t * ascent, speed = Array(frame.continuous.slice(0,4)),
				yaw = frame.body[RB.RATE + 2], rates = Array(frame.body.slice(RB.RATE, RB.RATE + 3)),
				velocity = Array(frame.body.slice(RB.VEL, RB.VEL + 3)), throttle = pilot[FC.IN_THROTTLE], motor_state = frame.modes[FC.MODE_MOTOR]}
			if first_violation.is_empty() and float(snapshot.ratio) > 1.0:
				first_violation = snapshot
				first_frame = frame.duplicate(true)
			if i < 700 and float(snapshot.ratio) > float(best_punch.ratio):
				best_punch = snapshot
				punch_frame = frame.duplicate(true)
			if float(snapshot.ratio) > float(best.ratio):
				best = snapshot
				best_frame = frame.duplicate(true)
	check("pad-start scripted throttle tape accepted", ok, "tick %d %s" % [s.sim.tick, s.fault_reason])
	check("pad-start tape reached rotor thrust-power threshold", not first_violation.is_empty())
	if not best_frame.is_empty():
		var ledger: Dictionary = _airborne_ledger(s, best_frame)
		check("pad-start stage total body-rotor energy ledger closes", absf(float(ledger.residual_w)) < 1e-7, "residual %.12f W" % float(ledger.residual_w))
		check("pad-start rotor aero port delivers positive mechanical power", float(ledger.rotor_air_power_w) > 1.0)
		check("selected atmosphere is calm reference density", absf(float(ledger.rho_kg_m3) - 1.225) < 1e-12 and M.norm(PackedFloat64Array(ledger.wind_ned_mps)) < 1e-12)
		best.ledger = ledger
	if not first_frame.is_empty():
		first_violation.ledger = _airborne_ledger(s, first_frame)
	if not punch_frame.is_empty():
		best_punch.ledger = _airborne_ledger(s, punch_frame)
		check("full-throttle selected rotor aero port also positive", float(best_punch.ledger.rotor_air_power_w) > 1.0 and absf(float(best_punch.ledger.residual_w)) < 1e-7)
	check("selected climb snapshots are armed and the complete tape has no crash", s.crash.is_empty() and s.fault_reason.is_empty()
		and best.motor_state == FC.MOTOR_ARMED and best_punch.motor_state == FC.MOTOR_ARMED and first_violation.motor_state == FC.MOTOR_ARMED)
	print("R7_CLIMB " + JSON.stringify({best = best, first_violation = first_violation, best_punch = best_punch,
		accepted_ticks = s.sim.tick, data_sha256 = s.source_sha256, fault = s.fault_reason, crash = s.crash}, "", true, true))
	s.free()

func _airborne_ledger(s: Node, f: Dictionary) -> Dictionary:
	var body: PackedFloat64Array = f.body
	var v := M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var w := M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var stage: Dictionary = s.plant._evaluate(body, f.continuous, 0.0, f.aux, f.modes)
	var loads: PackedFloat64Array = stage.loads
	var inertia: PackedFloat64Array = s.data.inertia_kg_m2
	var bd: PackedFloat64Array = RB.derivative(body, float(s.data.mass_kg), inertia, RB.inertia_inverse(inertia),
		M.v3(loads[0], loads[1], loads[2]), M.v3(loads[3], loads[4], loads[5]), 0.0, stage.rotor_momentum)
	var alpha := M.v3(bd[RB.RATE], bd[RB.RATE + 1], bd[RB.RATE + 2])
	var vd := M.v3(bd[RB.VEL], bd[RB.VEL + 1], bd[RB.VEL + 2])
	var dke: float = float(s.data.mass_kg) * M.dot(v, vd) + M.dot(w, RB.inertia_mul(inertia, alpha))
	var rotor_air := 0.0
	var motor := 0.0
	var friction := 0.0
	var thrust_work := 0.0
	var torque_work := 0.0
	var inplane_work := 0.0
	var kt: float = 1.0 / float(s.data.powertrain.kv_rad_s_per_v)
	for i in 4:
		var rotor: Dictionary = s.data.rotors[i]
		var j: float = float(rotor.inertia_kg_m2)
		var sign: float = float(rotor.spin)
		var speed: float = f.continuous[i]
		var sd: float = stage.derivative[i]
		dke += j * speed * sd - alpha[2] * sign * j * speed - w[2] * sign * j * sd
		var health: float = f.continuous[Plant.C_HEALTH + i]
		var load: float = maxf(health, Plant.BROKEN_PROP_LOAD)
		var thrust: float = float(s.data.rotor_law.thrust_coefficient_n_s2) * speed * speed * health
		var torque: float = float(s.data.rotor_law.torque_coefficient_n_m_s2) * speed * speed * load
		var vh: PackedFloat64Array = M.add(v, M.cross(w, rotor.hub_frd))
		thrust_work += -thrust * vh[2]
		inplane_work += -float(s.data.rotor_law.rotor_drag_n_s2_per_m) * speed * load * (vh[0] * vh[0] + vh[1] * vh[1])
		torque_work += torque * (sign * w[2] - speed)
		motor += kt * float(stage.bus.i_motor[i]) * speed
		friction -= kt * float(s.data.powertrain.no_load_current_a) * clampf(speed / Plant.FRICTION_SPEED, -1.0, 1.0) * speed
	rotor_air = thrust_work + inplane_work + torque_work
	var air_drag: PackedFloat64Array = Airframe.loads(v, s.environment.air_density(body[RB.POS + 2]), s.data.airframe)
	var body_drag: float = M.dot(air_drag, v)
	return {rotor_air_power_w = rotor_air, rotor_thrust_work_w = thrust_work, rotor_torque_work_w = torque_work,
		rotor_inplane_work_w = inplane_work, body_drag_w = body_drag, motor_power_w = motor, friction_w = friction,
		total_mechanical_power_w = dke, residual_w = dke - rotor_air - body_drag - motor - friction,
		body = Array(body), continuous = Array(f.continuous), body_derivative = Array(bd),
		continuous_derivative = Array(stage.derivative), motor_current_a = Array(stage.bus.i_motor),
		rho_kg_m3 = s.environment.air_density(body[RB.POS + 2]), wind_ned_mps = Array(s.environment.wind_world(M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]), 0.0))}
