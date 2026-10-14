## RCV-09: friction-circle optimality and physically defined slip telemetry.
extends SceneTree

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _road(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]), "mu": 0.85, "rolling": 1.0}

func _run() -> void:
	# Construct independent KKT solutions: f=[3,4], lambda=2,
	# W=[[4,1],[1,2]], b=(W+lambda*I)*f=[22,19].
	var projected := Vehicle._project_friction_circle(4.0, 1.0, 1.0, 2.0, 25.0/7.0, 54.0/7.0, 5.0)
	_check("anisotropic saturated contact satisfies known KKT solution",
		absf(projected[0] - 3.0) < 1.0e-7 and absf(projected[1] - 4.0) < 1.0e-7)
	_check("projection respects friction circle", M.sqrt_(projected[0]*projected[0]+projected[1]*projected[1]) <= 5.0 + 1.0e-12)
	var mirrored := Vehicle._project_friction_circle(4.0, -1.0, -1.0, 2.0, 25.0/7.0, -54.0/7.0, 5.0)
	_check("reflection preserves force magnitude and changes lateral sign",
		absf(mirrored[0]-projected[0]) < 1.0e-12 and absf(mirrored[1]+projected[1]) < 1.0e-12)
	var interior := Vehicle._project_friction_circle(4.0, 1.0, 1.0, 2.0, 0.4, -0.3, 5.0)
	_check("unsaturated contact preserves the unconstrained solution exactly", interior == PackedFloat64Array([0.4, -0.3]))
	var isotropic := Vehicle._project_friction_circle(2.0, 0.0, 0.0, 2.0, 6.0, 8.0, 5.0)
	_check("isotropic metric reduces to radial projection", absf(isotropic[0]-3.0)<1.0e-7 and absf(isotropic[1]-4.0)<1.0e-7)
	_check("zero grip gives zero tangential force", Vehicle._project_friction_circle(4.0, 1.0, 1.0, 2.0, 4.0, 5.0, 0.0) == PackedFloat64Array([0.0, 0.0]))
	var scaled := Vehicle._project_friction_circle(4000.0, 1000.0, 1000.0, 2000.0, 25.0/7.0, 54.0/7.0, 5.0)
	_check("uniform mobility scaling preserves the solution", absf(scaled[0]-projected[0])<1.0e-10 and absf(scaled[1]-projected[1])<1.0e-10)
	var loaded := Data.load_default()
	_check("vehicle fixture loads", bool(loaded.get("ok", false)))
	if not loaded.get("ok", false):
		quit(1)
		return
	var initialized := Vehicle.initialize(loaded.model, _road, 0.0, 0.0)
	_check("vehicle fixture initializes", bool(initialized.get("ok", false)))
	if not initialized.get("ok", false):
		quit(1)
		return
	var state: PackedFloat64Array = initialized.state.duplicate()
	state[Vehicle.VEL] = 8.0
	state[Vehicle.VEL+1] = 0.8
	var angle_ok := true
	var parity_ok := true
	# A freely rolling tire and a locked tire have the same hub slip angle;
	# their longitudinal slip ratios and friction forces remain different.
	for spin in [0.0, 80.0, 140.0]:
		for corner in 4:
			state[Vehicle.WHEEL_SPIN+corner] = spin
		var active := Vehicle.telemetry(state, loaded.model, _road)
		var reference := Vehicle._evaluate(state, loaded.model, Vehicle.DEFAULT_CONTROLS, _road)
		angle_ok = angle_ok and bool(active.get("ok", false)) and bool(reference.get("ok", false))
		if angle_ok:
			for corner in 4:
				angle_ok = angle_ok and absf(active.wheel_slip_angle_rad[corner]-M.atan2_(0.8,8.0)) < 1.0e-10
				parity_ok = parity_ok and absf(active.wheel_slip_angle_rad[corner]-reference.wheel_slip_angle_rad[corner]) < 1.0e-10
	_check("slip angle uses hub direction, independently of wheel spin", angle_ok)
	_check("active/reference slip-angle telemetry agrees", parity_ok)
	state = initialized.state.duplicate()
	state[Vehicle.VEL] = 10.0
	state[Vehicle.VEL+1] = 0.0
	for corner in 4:
		state[Vehicle.WHEEL_SPIN+corner] = 10.0 / float(loaded.model.tire_radius_m)
	var braking := {"throttle":0.0, "steering":0.0, "brake":0.6, "reverse":false}
	var symmetric := Vehicle.derivative(state, loaded.model, braking, _road)
	print("Symmetric braking yaw/lateral acceleration: ", symmetric[Vehicle.RATE+2], " / ", symmetric[Vehicle.VEL+1], " backend=", Vehicle.backend_identity().backend)
	_check("straight symmetric braking does not create a numerical yaw moment",
		symmetric.size()==Vehicle.STATE_SIZE and absf(symmetric[Vehicle.RATE+2])<1.0e-5
		and absf(symmetric[Vehicle.VEL+1])<1.0e-5)
	state[Vehicle.VEL+1] = 2.0
	var skid := Vehicle.telemetry(state, loaded.model, _road)
	var grip_bounded := bool(skid.get("ok",false))
	var lateral_power := 0.0
	if grip_bounded:
		for corner in 4:
			var fx: float = skid.wheel_longitudinal_force_n[corner]
			var fy: float = skid.wheel_lateral_force_n[corner]
			var limit: float = 0.85 * loaded.model.tire_friction_scale * skid.wheel_load_n[corner]
			grip_bounded = grip_bounded and M.sqrt_(fx*fx+fy*fy) <= limit + 1.0e-9
			lateral_power += fy * 2.0
	_check("combined skid forces share each tire's friction budget", grip_bounded)
	_check("coasting lateral skid dissipates energy", lateral_power < -1.0)
	_test_brake_capacity(initialized.state, loaded.model)
	_test_disturbed_braking(initialized.state, loaded.model)
	print("RCV handling: %d/%d checks passed" % [_checks-_failures, _checks])
	quit(1 if _failures else 0)

func _test_brake_capacity(resting: PackedFloat64Array, base: Dictionary) -> void:
	# An airborne spinning wheel isolates actuator capacity from tire forces.
	var state := resting.duplicate()
	state[Vehicle.POS+2] -= 2.0
	for corner in 4:
		state[Vehicle.WHEEL_SPIN+corner] = 100.0
	var controls := {"throttle":0.0, "steering":0.0, "brake":1.0, "reverse":false}
	for fraction in [0.0, 0.5, 0.85, 1.0]:
		var model := base.duplicate(true)
		model.brake_front_fraction = fraction
		var evaluated := Vehicle._evaluate(state, model, controls, _road)
		var valid: bool = evaluated.get("ok", false)
		var total := 0.0
		if valid:
			for corner in 4:
				var capacity: float = 2.0 * model.brake_torque_per_wheel_nm * (fraction if corner < 2 else 1.0-fraction)
				var actual: float = absf(evaluated.wheel_brake_torque_n_m[corner])
				total += actual
				valid = valid and absf(actual-capacity)<1.0e-9
		_check("fixed axle split preserves total brake capacity: " + str(fraction), valid and absf(total-4.0*model.brake_torque_per_wheel_nm)<1.0e-9)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS: " if condition else "FAIL: ") + label)


func _test_disturbed_braking(resting: PackedFloat64Array, model: Dictionary) -> void:
	var left := _disturbed_stop(resting, model, -0.05, 1.0/240.0)
	var right := _disturbed_stop(resting, model, 0.05, 1.0/240.0)
	var fine := _disturbed_stop(resting, model, 0.05, 1.0/480.0)
	_check("partial braking arrests both signs of a small lateral disturbance",
		left.ok and right.ok and left.lateral_peak < 0.1 and right.lateral_peak < 0.1
		and left.yaw_peak < 0.06 and right.yaw_peak < 0.06
		and left.upright_min > 0.97 and right.upright_min > 0.97)
	_check("mirrored disturbed stops preserve distance and lateral symmetry",
		left.ok and right.ok and absf(left.distance-right.distance) < 0.01
		and absf(left.lateral_distance+right.lateral_distance) < 0.01)
	_check("240/480 Hz disturbed braking agrees in distance and time",
		right.ok and fine.ok and absf(right.distance-fine.distance) < 0.02
		and absf(right.time-fine.time) < 0.015)
	print("Disturbed brake metrics (left/right/fine): ", [left, right, fine])


func _disturbed_stop(resting: PackedFloat64Array, model: Dictionary, lateral: float, dt: float) -> Dictionary:
	var state := resting.duplicate()
	state[Vehicle.VEL] = 11.87
	state[Vehicle.VEL+1] = lateral
	for corner in 4:
		state[Vehicle.WHEEL_SPIN+corner] = 11.87 / float(model.tire_radius_m)
	var result := {"ok": false, "distance":0.0, "lateral_distance":0.0, "time":0.0,
		"yaw_peak":0.0, "lateral_peak":absf(lateral), "upright_min":1.0}
	var controls := {"throttle":0.0, "steering":0.0, "brake":0.6, "reverse":false}
	for tick in int(4.0/dt):
		state = Vehicle.step(state, model, controls, dt, _road)
		if state.size() != Vehicle.STATE_SIZE:
			return result
		var q := PackedFloat64Array([state[6],state[7],state[8],state[9]])
		var forward := M.q_rotate(q, PackedFloat64Array([1.0,0.0,0.0]))
		var upright := -M.q_rotate(q, PackedFloat64Array([0.0,0.0,-1.0]))[2]
		result.upright_min = minf(result.upright_min, upright)
		result.yaw_peak = maxf(result.yaw_peak, absf(M.atan2_(forward[1],forward[0])))
		result.lateral_peak = maxf(result.lateral_peak, absf(state[Vehicle.VEL+1]))
		result.time = (tick+1)*dt
		result.distance = state[Vehicle.POS]-resting[Vehicle.POS]
		result.lateral_distance = state[Vehicle.POS+1]-resting[Vehicle.POS+1]
		var speed := M.norm(PackedFloat64Array([state[Vehicle.VEL],state[Vehicle.VEL+1],state[Vehicle.VEL+2]]))
		if speed < 0.1:
			result.ok = true
			return result
	return result
