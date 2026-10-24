extends SceneTree
## F4U-12: the CARF manual's take-off note on the simulated Corsair. "Take off at 50 % power: at full power the
## low-rate elevator cannot hold the tail down and the model may nose over." From the qualified runway start, throttle
## up over 1 s and hold the elevator stick fully back at the normal rate (CARF's 20 mm), and once at the full throw,
## heading held with the steerable tail wheel and rudder, wings level. Reports when the tail wheel leaves the ground,
## the least pitch attitude and any prop strike or crash, until lift-off or 8 s. Not physical validation.
## godot --headless --path app --audio-driver Dummy --script <repo>/research/f4u-corsair/F4U-12/ground_handling.gd
const FlightSession := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const P := preload("../../flight-test/pilot.gd")
const DATA := "res://data/aircraft/f4u_corsair_250.json"
const SECONDS := 8.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = false
	session.crash_auto_restart = false
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not session.set_field(field.get("field", field)):
		printerr("F4U-12 ground handling: the default field did not load")
		quit(2)
		return
	var normal: float = float(session.aircraft.model.controls.rates.normal.elevator)
	var rows := []
	for case: Array in [["50 % power, normal-rate elevator", 0.5, normal, 0.0], ["full power, normal-rate elevator", 1.0, normal, 0.0],
			["full power, full elevator throw", 1.0, 1.0, 0.0], ["full-power run-up on the brakes, normal-rate elevator", 1.0, normal, 1.0]]:
		rows.append(_roll(session, str(case[0]), float(case[1]), float(case[2]), float(case[3])))
	session.queue_free()
	print(JSON.stringify({ format = "F4U-12 ground handling v1", data = DATA, normal_rate_elevator = normal, cases = rows }, "\t"))
	quit(0 if rows.all(func(r: Dictionary) -> bool: return r.ok) else 1)


func _roll(session: Node, label: String, throttle: float, stick: float, brake: float) -> Dictionary:
	session.start_choice = FlightSession.START_RUNWAY
	session.reset()
	if not session.is_flyable() or not session.start_error.is_empty():
		return { case = label, ok = false, message = "runway start failed: " + session.start_error }
	# The card sets session fields the same way; set_wheel_brake() needs live input.
	session._wheel_brake_demand = brake
	var sim: Node = session.sim
	var dt: float = sim.dt()
	var gear: Dictionary = session.current_landing_gear()
	var tail := 0
	for i in 3:
		if gear.contacts[i].position[0] < gear.contacts[tail].position[0]:
			tail = i
	var heading: float = P.euler(sim.state)[0]
	var pitch0: float = P.euler(sim.state)[1]
	var out := { case = label, ok = true, throttle = throttle, elevator_stick = snappedf(stick, 0.001), brake = brake,
		three_point_pitch_deg = snappedf(rad_to_deg(pitch0), 0.01), tail_lifted = false, crashed = "" }
	var least_pitch := pitch0
	for k in roundi(SECONDS / dt):
		var t := k * dt
		var s: PackedFloat64Array = sim.state
		session.commands = { roll = clampf(P.bank(s, 0.0, 1.0), -1.0, 1.0), pitch = stick,
			yaw = P.ground_heading(s, heading), throttle = clampf(t, 0.0, 1.0) * throttle }
		sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty():
			out.crashed = str(session.pause_reason)
			out.crash_t_s = snappedf(t, 0.01)
			break
		sim.step()
		s = sim.state
		var c: PackedFloat64Array = Ground.compressions(s, gear)
		least_pitch = minf(least_pitch, P.euler(s)[1])
		if not out.tail_lifted and c[tail] <= 0.0 and (c[0] > 0.0 or c[1] > 0.0 or c[2] > 0.0):
			out.tail_lifted = true
			out.tail_lift_t_s = snappedf(t, 0.01)
			out.tail_lift_speed_mps = snappedf(P.speed(s), 0.01)
		if t > 0.5 and c[0] <= 0.0 and c[1] <= 0.0 and c[2] <= 0.0:
			out.liftoff_t_s = snappedf(t, 0.01)
			out.liftoff_speed_mps = snappedf(P.speed(s), 0.01)
			break
	out.least_pitch_deg = snappedf(rad_to_deg(least_pitch), 0.01)
	out.end_speed_mps = snappedf(P.speed(sim.state), 0.01)
	return out
