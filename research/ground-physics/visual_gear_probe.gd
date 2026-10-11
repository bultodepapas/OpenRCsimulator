extends SceneTree

const AirplaneBuilder := preload("res://render/airplane.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Frames := preload("res://render/frames.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const CASES: Array[Dictionary] = [
	{"id": "jensen-das-ugly-stik-60", "path": "res://data/aircraft/jensen_ugly_stik_60.json"},
	{"id": "gp-extra-300s-60", "path": "res://data/aircraft/gp_extra_300s_60.json"},
	{"id": "p51d-mustang-120", "path": "res://data/aircraft/p51d_mustang_120.json"},
]
const TARGET_COMPRESSION_M := 0.003
const SPIN_SPEED_MPS := 0.5
const SPIN_TICKS := 12
const STEERING_COMMAND := 0.3
const STEERING_TICKS := 48

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("GP-03 visual gear probe: integrated app source, native session + model builders")
	var loaded: Dictionary = FieldLoader.load_from()
	if not loaded.ok:
		_fail("default field loads", "; ".join(loaded.errors))
		quit(1)
		return
	var host := Node3D.new()
	host.name = "VisualGearProbe"
	get_root().add_child(host)
	for case in CASES:
		await _probe_case(host, case, loaded.field)
	print("visual gear probe: %d checks, %d failed" % [_checks, _failures])
	host.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _probe_case(host: Node3D, case: Dictionary, field: Dictionary) -> void:
	var aircraft_id: String = str(case.id)
	var airplane: Dictionary = AirplaneBuilder.build(aircraft_id)
	if airplane.is_empty() or not airplane.has("gear"):
		_fail("%s model builds with gear pivots" % aircraft_id, "builder returned no gear dictionary")
		return
	host.add_child(airplane.root)
	var session = FlightSession.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.setup(str(case.path), aircraft_id)
	session.set_field(field)
	host.add_child(session)
	session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	session.reset()
	if not session.aircraft.get("ok", false) or session.wheel_count() == 0:
		_fail("%s physics session loads" % aircraft_id, str(session.aircraft.get("errors", [])))
		airplane.root.queue_free()
		session.free()
		await process_frame
		return

	var model: Dictionary = session.aircraft.model
	var contacts: Array = model.landing_gear.contacts
	var gear: Dictionary = airplane.gear
	_check("%s contact count matches rendered wheels" % aircraft_id,
		contacts.size() == session.wheel_count(), "contacts=%d wheels=%d" % [contacts.size(), session.wheel_count()])
	var contact_map: Array[String] = []
	for contact in contacts:
		var key := _key(str(contact.name))
		contact_map.append(key)
		_check("%s %s pivot exists" % [aircraft_id, str(contact.name)], gear.has(key), "mapped pivot=%s" % key)
	print("%s contact order=%s wheel_index=%d" % [aircraft_id, contact_map, session.wheel_index()])

	var datum: Vector2 = AirplaneBuilder.datum(aircraft_id)
	var cg_model: Vector3 = Frames.cg_in_model_frame(model.cg_le, datum.x, datum.y)
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var runway: Dictionary = {}
	for surface in field.surfaces:
		if surface.type == "runway":
			runway = surface
			break
	if runway.is_empty():
		_fail("%s default field has a runway" % aircraft_id, "no normalized runway surface")
		airplane.root.queue_free()
		session.free()
		await process_frame
		return
	state[RB.POS] = float(runway.center_north)
	state[RB.POS + 1] = float(runway.center_east)
	state[RB.POS + 2] = 0.0
	state[RB.VEL] = 0.0
	state[RB.VEL + 1] = 0.0
	state[RB.VEL + 2] = 0.0
	var plane_q: PackedFloat64Array = _resting_attitude(contacts)
	for i in 4:
		state[RB.ATT + i] = plane_q[i]
	state[RB.RATE] = 0.0
	state[RB.RATE + 1] = 0.0
	state[RB.RATE + 2] = 0.0
	var compression: PackedFloat64Array = session.gear_compressions(state)
	var least_compressed := INF
	for value in compression:
		least_compressed = minf(least_compressed, value)
	var static_sag: float = float(model.landing_gear.get("static_sag", TARGET_COMPRESSION_M))
	state[RB.POS + 2] += static_sag - least_compressed
	var reset_ok: bool = session.sim.reset(state)
	_check("%s loads contact-height state" % aircraft_id, reset_ok, str(session.sim.fault_reason))
	session.engine_running = false
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	_apply_root_pose(airplane, session, cg_model)
	var root_inverse: Transform3D = airplane.root.global_transform.affine_inverse()
	var center_details := PackedStringArray()
	var worst_center_residual := 0.0
	for i in contacts.size():
		var key: String = contact_map[i]
		var contact: Dictionary = contacts[i]
		var body: PackedFloat64Array = contact.position
		var radius: float = float(contact.wheel_radius)
		var expected_contact := cg_model + Vector3(body[1], -body[2], -body[0])
		var expected_axle := expected_contact + Vector3(0.0, radius, 0.0)
		var actual_axle: Vector3 = root_inverse * gear[key].global_position
		var contact_residual: float = actual_axle.distance_to(expected_contact)
		var axle_residual: float = actual_axle.distance_to(expected_axle)
		worst_center_residual = maxf(worst_center_residual, minf(contact_residual, axle_residual))
		center_details.append("%s contact=%.4f m contact+radius=%.4f m" % [key, contact_residual, axle_residual])
	print("%s rest wheel-center mapping: %s" % [aircraft_id, "; ".join(center_details)])
	_check("%s rendered wheel center maps to contact/axle coordinates" % aircraft_id,
		worst_center_residual <= 0.01, "best per-contact residual <= 0.010 m; worst=%.6f m" % worst_center_residual)
	var observer: Node = GroundGear.attach(airplane, session)
	var rest: Dictionary = observer.get("_rest")
	var maximum_compression := 0.0
	var maximum_pivot_error := 0.0
	var maximum_supported_contacts := 0
	session.sim.set_paused(false)
	for _tick in 4:
		session.sim.step()
		_apply_root_pose(airplane, session, cg_model)
		observer.call("_process", 0.0)
		var shown_state: PackedFloat64Array = session.sim.interpolated(Engine.get_physics_interpolation_fraction())
		var shown_compression: PackedFloat64Array = session.gear_compressions(shown_state)
		var supported_contacts := 0
		for i in contacts.size():
			var key: String = contact_map[i]
			var wheel: Node3D = gear[key]
			var amount: float = maxf(0.0, shown_compression[i])
			if amount > 0.0:
				supported_contacts += 1
			maximum_compression = maxf(maximum_compression, amount)
			var up_local: Vector3 = wheel.get_parent().global_basis.inverse() * Vector3.UP
			var expected: Vector3 = rest[key] + up_local * amount
			maximum_pivot_error = maxf(maximum_pivot_error, wheel.position.distance_to(expected))
		maximum_supported_contacts = maxi(maximum_supported_contacts, supported_contacts)
	_check("%s physics compression articulates every matching pivot" % aircraft_id,
		maximum_supported_contacts == contacts.size() and maximum_pivot_error <= 1e-8,
		"max simultaneous support=%d/%d max compression=%.6f m max local pivot error=%.9f m" % [maximum_supported_contacts, contacts.size(), maximum_compression, maximum_pivot_error])

	# Reset to air, seed positive forward rim speed, and drive the actual servo input
	# through Simulation.step so both observer callbacks run on emitted physics ticks.
	state = session.sim.state.duplicate()
	state[RB.POS + 2] = -2.0
	state[RB.VEL] = 0.0
	state[RB.VEL + 1] = 0.0
	state[RB.VEL + 2] = 0.0
	state[RB.ATT] = 1.0
	state[RB.ATT + 1] = 0.0
	state[RB.ATT + 2] = 0.0
	state[RB.ATT + 3] = 0.0
	state[RB.RATE] = 0.0
	state[RB.RATE + 1] = 0.0
	state[RB.RATE + 2] = 0.0
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var wheel_index: int = session.wheel_index()
	for i in contacts.size():
		continuous[wheel_index + i] = SPIN_SPEED_MPS
	session.sim.continuous = continuous
	session.sim.inputs = PackedFloat64Array([0.0, 0.0, STEERING_COMMAND, 0.0])
	_check("%s reset to airborne spin/steer state" % aircraft_id, session.sim.reset(state), str(session.sim.fault_reason))
	var steering_index := -1
	for i in contacts.size():
		if absf(float(contacts[i].get("max_steering", 0.0))) > 0.0:
			steering_index = i
			break
	_check("%s has a physics steering contact" % aircraft_id, steering_index >= 0, str(contacts.map(func(c): return c.get("max_steering", 0.0))))
	for _tick in STEERING_TICKS:
		session.sim.step()
		_apply_root_pose(airplane, session, cg_model)
		observer.call("_process", 0.0)

	var final_state: PackedFloat64Array = session.sim.interpolated(Engine.get_physics_interpolation_fraction())
	var final_aux: PackedFloat64Array = session.sim.aux
	var steer_command: float = final_aux[session.AUX_SERVO + 2]
	var spin_failures := 0
	var spin_details := PackedStringArray()
	for i in contacts.size():
		var key: String = contact_map[i]
		var wheel: Node3D = gear[key]
		var radius: float = float(contacts[i].wheel_radius)
		var angle: float = wheel.rotation.x
		if angle >= -1e-6:
			spin_failures += 1
		spin_details.append("%s angle_x=%.6f rim=%.3f radius=%.4f" % [key, angle, continuous[wheel_index + i], radius])
	_check("%s positive forward rim speed rotates about -X" % aircraft_id, spin_failures == 0, "; ".join(spin_details))
	if steering_index >= 0:
		var steering_contact: Dictionary = contacts[steering_index]
		var pivot: Node3D = gear.steering
		var expected_angle: float = -steer_command * float(steering_contact.max_steering)
		var visual_heading: Vector3 = pivot.global_basis * Vector3.FORWARD
		var physics_frame: Dictionary = GroundWheels.frame(final_state, steering_contact, steer_command, session.ground_surfaces)
		var heading: PackedFloat64Array = physics_frame.heading
		var physics_heading: Vector3 = Frames.ned_to_render([heading[0], heading[1], heading[2]]).normalized()
		var dot: float = visual_heading.normalized().dot(physics_heading)
		_check("%s steering pivot follows servo limit and physical wheel heading" % aircraft_id,
			steer_command > 0.0 and absf(pivot.rotation.y - expected_angle) <= 1e-8 and dot >= 1.0 - 1e-5,
			"servo=%.6f max=%.6f pivot_y=%.6f expected=%.6f heading_dot=%.12f" % [steer_command, steering_contact.max_steering, pivot.rotation.y, expected_angle, dot])

	var faults: String = str(session.sim.fault_reason)
	_check("%s remains finite and fault-free through spin/steer ticks" % aircraft_id,
		faults.is_empty() and session.sim.tick >= STEERING_TICKS, "tick=%d fault='%s'" % [session.sim.tick, faults])

	# Keep the airplane/observer alive while freeing the session. The observer must
	# tolerate teardown on subsequent idle frames without touching the freed session.
	session.free()
	await process_frame
	await process_frame
	_check("%s observer survives session teardown" % aircraft_id, is_instance_valid(observer), "observer freed with session")
	airplane.root.queue_free()
	await process_frame


func _apply_root_pose(airplane: Dictionary, session: Node, cg_model: Vector3) -> void:
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var state: PackedFloat64Array = session.sim.interpolated(fraction)
	var attitude: Basis = Frames.quat_to_render(state.slice(RB.ATT, RB.ATT + 4))
	var position: Vector3 = Frames.ned_to_render([state[RB.POS], state[RB.POS + 1], state[RB.POS + 2]])
	airplane.root.transform = Frames.root_transform(attitude, position, cg_model)


func _resting_attitude(contacts: Array) -> PackedFloat64Array:
	var p0: PackedFloat64Array = contacts[0].position
	var p1: PackedFloat64Array = contacts[1].position
	var p2: PackedFloat64Array = contacts[2].position
	var ax: float = p1[0] - p0[0]
	var ay: float = p1[1] - p0[1]
	var az: float = p1[2] - p0[2]
	var bx: float = p2[0] - p0[0]
	var by: float = p2[1] - p0[1]
	var bz: float = p2[2] - p0[2]
	var nx: float = ay * bz - az * by
	var ny: float = az * bx - ax * bz
	var nz: float = ax * by - ay * bx
	var length: float = sqrt(nx * nx + ny * ny + nz * nz)
	if length <= 1e-9:
		return PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	nx /= length
	ny /= length
	nz /= length
	if nz < 0.0:
		nx = -nx
		ny = -ny
		nz = -nz
	return M.q_from_euler(0.0, asin(-nx), atan2(ny, nz))


func _key(name: String) -> String:
	return name.trim_prefix("main_")


func _check(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", label, " — " + detail if detail != "" else ""])
	if not ok:
		_failures += 1


func _fail(label: String, detail: String) -> void:
	_check(label, false, detail)
