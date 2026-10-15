# P51-11b: the P-51D's retractable taildragger gear on the shared retractable-point-gear-v1 law. Data and provenance;
# airborne flights start stowed and the sequenced extension takes the authored 4 s with the legs still during the door
# phases; the gear drag is exactly the module's and absent when stowed; the runway start is down and locked and the
# operator interlock refuses retraction on the wheels; the animated wheels follow the physics contact paths and the
# doors are closed at both ends and open in transit.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const RG := preload("res://physics/retractable_gear.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Builder := preload("res://render/airplane.gd")
const P51 := preload("res://aircraft/p51d_model.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	Engine.physics_ticks_per_second = 240
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var loaded: Dictionary = AD.load_file(DATA)
	_check("data loads as a retractable taildragger", loaded.ok and raw.capabilities.gear == "retractable_taildragger"
		and RG.enabled(loaded.model.landing_gear), str(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	var gear: Dictionary = loaded.model.landing_gear
	_check("retraction module: 4 s each way, drag area 0.022 m2 (the gear-down build-up item)", gear.retraction.extension_time == 4.0
		and gear.retraction.retraction_time == 4.0 and absf(float(gear.retraction.drag_area) - 0.022) < 1e-12)
	_check("three 129-sample contact paths ending at the deployed contacts", raw.landing_gear.contacts.all(func(c: Dictionary) -> bool:
		var p: Array = c.retraction_path.value
		var q: Array = c.position.value
		return p.size() == 387 and Vector3(p[384], p[385], p[386]).is_equal_approx(Vector3(q[0], q[1], q[2]))))

	# 1. Airborne start stowed; sequenced extension.
	var air := FlightSession.new()
	air.setup(DATA)
	root.add_child(air)
	air.input_enabled = true
	_check("airborne start: gear up and locked", air.gear_state().extension == 0.0 and air.gear_state().status == "up", str(air.gear_state()))
	_check("gear-down request accepted in flight", air.set_gear_down(true))
	var dt: float = air.sim.dt()
	var at_door_end := NAN
	var at_half := NAN
	for i in roundi(4.0 / dt) + 2:
		air._physics_process(dt)
		air.sim.step()
		var e: float = air.gear_state().extension
		if i == roundi(0.8 / dt):
			at_door_end = e
		if i == roundi(2.0 / dt):
			at_half = e
	_check("extension reaches down and locked in the authored 4 s (0.2 at 0.8 s, 0.5 at 2 s)", air.gear_state().status == "down"
		and absf(at_door_end - 0.2) < 0.01 and absf(at_half - 0.5) < 0.01, "%.3f %.3f %s" % [at_door_end, at_half, air.gear_state().status])
	air.queue_free()

	# 2. Gear drag: exactly the module's quadratic drag at the declared point, nothing when stowed.
	var s := RB.make_state(M.v3(0, 0, -100), M.v3(25, 0, 1), M.q_identity(), M.v3(0, 0, 0))
	var down := RG.drag_loads(s, M.v3(25, 0, 1), gear, 1.0, 1.225)
	var half := RG.drag_loads(s, M.v3(25, 0, 1), gear, 0.5, 1.225)
	var expected: float = 0.5 * 1.225 * 0.022 * (25.0 * 25.0 + 1.0)
	_check("gear-down drag is 1/2 rho V2 CdA; half extension half of it; stowed none", absf(M.norm(down.slice(0, 3)) - expected) < 1e-9
		and absf(M.norm(half.slice(0, 3)) - expected / 2.0) < 1e-9 and RG.drag_loads(s, M.v3(25, 0, 1), gear, 0.0, 1.225).is_empty(),
		"%.4f N vs %.4f N" % [M.norm(down.slice(0, 3)), expected])

	# 3. Runway start: down and locked, retraction refused on the wheels.
	var ground := FlightSession.new()
	ground.setup(DATA)
	root.add_child(ground)
	ground.input_enabled = true
	var field_loaded := FieldLoader.load_from()
	var field_ok: bool = field_loaded.ok and ground.set_field(field_loaded.field)
	var spot: Dictionary = GroundStart.threshold(field_loaded.field) if field_ok else {ok = false}
	var parked: bool = spot.ok and ground.reset_on_runway(spot.north, spot.east, spot.heading)
	_check("runway start is down and locked on three wheels", parked and ground.gear_state().status == "down" and ground.wheel_count() == 3,
		str(ground.gear_state()))
	_check("retraction on the wheels is refused by the interlock", parked and not ground.set_gear_down(false) and ground.gear_state().inhibited)
	ground.queue_free()

	# 3b. P51-11c brakes: from the same taxi run (rudder holding the heading), full brakes stop shorter than rolling,
	# without lifting the tail (nose-over) or swerving. Mains carry the estimated 2 N·m brakes; the tail wheel has none.
	var unbraked := _rollout(field_loaded.field, spot, 0.0)
	var braked := _rollout(field_loaded.field, spot, 1.0)
	_check("brakes: data has 2 N·m on each main wheel and none on the tail", is_equal_approx(float(loaded.model.landing_gear.contacts[0].brake_torque), 2.0)
		and is_equal_approx(float(loaded.model.landing_gear.contacts[1].brake_torque), 2.0) and float(loaded.model.landing_gear.contacts[2].brake_torque) == 0.0)
	# The shared GP-02 tyre law caps the longitudinal tyre force at (wheel mass / spin relaxation) x slip, about
	# 1.7 N per m/s for this wheel, so the 2 N·m brakes deliver only part of their ~0.2 g (P51-11c evidence); the check is
	# that the brakes act, not their full-scale effect.
	_check("full brakes shorten the rollout from the same taxi speed (shared tyre-law limited)", unbraked.ok and braked.ok and braked.distance < 0.85 * unbraked.distance,
		"%.1f m vs %.1f m from %.1f m/s" % [braked.get("distance", NAN), unbraked.get("distance", NAN), braked.get("start_speed", NAN)])
	_check("braking keeps the tail wheel loaded (no nose-over) and the heading within 6 deg", braked.ok and braked.tail_loaded and braked.heading_change < 6.0,
		"tail loaded %s, heading change %.1f deg" % [braked.get("tail_loaded", false), braked.get("heading_change", NAN)])

	# 4. Rendering: wheels on the physics paths; doors closed at both ends and open in transit; down = the built pose.
	var airplane: Dictionary = Builder.build(Builder.P51_ID)
	root.add_child(airplane.root)
	var wheels := {main_left = airplane.gear.left, main_right = airplane.gear.right, tail = airplane.gear.tail}
	var radius := {main_left = loaded.model.landing_gear.contacts[0].wheel_radius, main_right = loaded.model.landing_gear.contacts[1].wheel_radius,
		tail = loaded.model.landing_gear.contacts[2].wheel_radius}
	var worst := 0.0
	for i in [0, 16, 32, 48, 64, 80, 96, 112, 128]:
		P51.set_gear(airplane, float(i) / 128.0)
		for c: Dictionary in raw.landing_gear.contacts:
			var p: Array = c.retraction_path.value
			var physics := Vector3(p[3 * i + 1], p[3 * i + 2], p[3 * i]) # le [x_aft, y_right, z_up] -> model (x, y, z)
			var wheel: Node3D = wheels[c.name]
			var to_root: Transform3D = airplane.root.global_transform.affine_inverse() * wheel.get_parent().global_transform
			var visual: Vector3 = to_root * (wheel.position + Vector3(0, -float(radius[c.name]), 0))
			worst = maxf(worst, visual.distance_to(physics))
	_check("animated wheel bottoms follow the physics contact paths (9 samples x 3 wheels)", worst < 1e-5, "worst %s m" % String.num_scientific(worst))
	var door := func(name: String) -> float: return absf((airplane.root.find_child(name, true, false) as Node3D).rotation.z)
	P51.set_gear(airplane, 0.0)
	var closed_up: bool = door.call("inner_door_left_hinge") == 0.0 and door.call("tail_door_left_hinge") == 0.0
	P51.set_gear(airplane, 0.5)
	var open_mid: bool = door.call("inner_door_left_hinge") > 1.4 and door.call("tail_door_left_hinge") > 1.3
	P51.set_gear(airplane, 1.0)
	var down_pose: bool = door.call("inner_door_left_hinge") == 0.0 and door.call("tail_door_left_hinge") > 1.3 \
		and (airplane.gear_rig.mains.left.pivot as Node3D).basis.is_equal_approx(Basis.IDENTITY) and (airplane.gear_rig.tail as Node3D).rotation == Vector3.ZERO
	_check("doors: closed stowed, open in transit; down: inner doors closed, tail doors open, legs at the built pose", closed_up and open_mid and down_pose)
	_finish()



## A pilot's rudder on the runway heading: proportional to the heading error, damped by the yaw rate.
func _hold(st: PackedFloat64Array, yaw_ref: float) -> float:
	var yaw: float = M.q_to_euler(M.quat(st[RB.ATT], st[RB.ATT + 1], st[RB.ATT + 2], st[RB.ATT + 3]))[0]
	return clampf(-3.0 * wrapf(yaw - yaw_ref, -PI, PI) - 0.6 * st[RB.RATE + 2], -1.0, 1.0)


func _rollout(field: Dictionary, spot: Dictionary, brake: float) -> Dictionary:
	var session := FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = true
	if not session.set_field(field) or not session.reset_on_runway(spot.north, spot.east, spot.heading):
		session.queue_free()
		return {ok = false}
	var dt: float = session.sim.dt()
	session.input_enabled = false
	session.engine_running = true
	var yaw_ref: float = spot.heading
	for i in roundi(2.0 / dt): # taxi: full power, stick back to hold the tail down, rudder holding the runway heading
		session.commands = {roll = 0.0, pitch = 1.0, yaw = _hold(session.sim.state, yaw_ref), throttle = 1.0}
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		session.sim.step()
	var s0: PackedFloat64Array = session.sim.state.duplicate()
	var v0: float = M.norm(PackedFloat64Array([s0[RB.VEL], s0[RB.VEL + 1], s0[RB.VEL + 2]]))
	var yaw0: float = M.q_to_euler(M.quat(s0[RB.ATT], s0[RB.ATT + 1], s0[RB.ATT + 2], s0[RB.ATT + 3]))[0]
	session.input_enabled = true
	session.set_wheel_brake(brake)
	session.input_enabled = false
	var tail_loaded := true
	var t := 0.0
	while t < 30.0:
		session.commands = {roll = 0.0, pitch = 1.0, yaw = _hold(session.sim.state, yaw_ref), throttle = 0.0}
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		session.sim.step()
		t += dt
		var c: PackedFloat64Array = session.gear_compressions(session.sim.state)
		tail_loaded = tail_loaded and c.size() == 3 and c[2] > 0.0
		var st: PackedFloat64Array = session.sim.state
		if M.norm(PackedFloat64Array([st[RB.VEL], st[RB.VEL + 1], st[RB.VEL + 2]])) < 0.05:
			break
	var s1: PackedFloat64Array = session.sim.state
	var distance := sqrt((s1[RB.POS] - s0[RB.POS]) ** 2 + (s1[RB.POS + 1] - s0[RB.POS + 1]) ** 2)
	var yaw1: float = M.q_to_euler(M.quat(s1[RB.ATT], s1[RB.ATT + 1], s1[RB.ATT + 2], s1[RB.ATT + 3]))[0]
	var heading := absf(rad_to_deg(wrapf(yaw1 - yaw0, -PI, PI)))
	var result := {ok = session.crash.is_empty() and session.sim.fault_reason.is_empty(), distance = distance, start_speed = v0,
		tail_loaded = tail_loaded, heading_change = heading}
	session.queue_free()
	return result


func _finish() -> void:
	print("P51-11b retracts: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
