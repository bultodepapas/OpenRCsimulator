# Multirotor test fixtures (DR tests only; never product data). Two prepared documents in the shape
# physics/multirotor_data.gd produces, written by hand so plant and controller tests do not depend on the loader:
#   lab()       the DR-04a research fixture of plant.gd under the controlled first-order law
#   electric()  round synthetic numbers of a 5-inch class quad under the electrical law
# plus helpers to put a controlled plant on a kernel.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const LabPlant := preload("res://physics/multirotor/plant.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")


static func _controller() -> Dictionary:
	return {sample_hz = 240, kp = PackedFloat64Array([0.040, 0.036, 0.050]), ki = PackedFloat64Array([0.20, 0.18, 0.15]),
		kd = PackedFloat64Array([0.0004, 0.0004, 0.0]), i_max = PackedFloat64Array([0.08, 0.08, 0.06]),
		kaw = PackedFloat64Array([20.0, 20.0, 20.0]), tau_limit = PackedFloat64Array([0.9, 0.9, 0.35]),
		gyro_lpf_hz = 90.0, dterm_lpf_hz = 60.0, angle_max_tilt_rad = deg_to_rad(55.0), angle_gain_per_s = 6.0,
		angle_rate_limit_rad_s = deg_to_rad(400.0), arm_low_throttle = 0.05,
		allocator_weights = PackedFloat64Array([1.0, 20.0, 20.0, 5.0]), throttle_rate_per_s = 0.8}


static func _contacts(half: float, mass: float) -> Dictionary:
	var stiffness: float = mass * 9.80665 / (4.0 * 0.004)
	return {feet_frd = [PackedFloat64Array([-half, half, 0.022]), PackedFloat64Array([half, half, 0.022]),
			PackedFloat64Array([-half, -half, 0.022]), PackedFloat64Array([half, -half, 0.022])],
		stiffness_n_per_m = stiffness, damping_n_s_per_m = 2.0 * 0.6 * sqrt(4.0 * stiffness * mass) / 4.0, friction = 0.7,
		hull_frd = [PackedFloat64Array([-half, half, -0.012]), PackedFloat64Array([half, half, -0.012]),
			PackedFloat64Array([-half, -half, -0.012]), PackedFloat64Array([half, -half, -0.012]),
			PackedFloat64Array([0.0, 0.0, -0.045])],
		crash_speed_mps = 5.0, rotor_strike_speed_rad_s = 300.0}


static func lab() -> Dictionary:
	var source: Dictionary = LabPlant.research_quad()
	var rotors: Array = []
	for rotor: Dictionary in source.rotors:
		rotors.append({id = int(rotor.id), hub_frd = rotor.hub_frd.duplicate(), spin = float(rotor.spin), diameter_m = 0.127,
			inertia_kg_m2 = float(source.rotor.inertia_kg_m2)})
	return {
		identity = {schema = "test-fixture", family = "lab", variant = "research-quad-controlled", status = "fixture",
			data_sha256 = "fixture-lab", experimental = true},
		mass_kg = float(source.mass_kg), inertia_kg_m2 = source.inertia_kg_m2.duplicate(), rotors = rotors,
		rotor_law = {thrust_coefficient_n_s2 = float(source.rotor.thrust_coefficient_n_s2),
			torque_coefficient_n_m_s2 = float(source.rotor.torque_coefficient_n_m_s2),
			rotor_drag_n_s2_per_m = float(source.rotor.rotor_drag_n_s2_per_m), max_speed_rad_s = 3140.0},
		airframe = {drag_areas_m2 = source.airframe.drag_areas_m2.duplicate()},
		powertrain = {law = "first-order-lab-v1", full_command_speed_rad_s = float(source.motor.full_duty_speed_rad_s),
			time_constant_s = float(source.motor.time_constant_s), idle_command = float(source.motor.idle_duty), max_command = 1.0},
		controller = _controller(), contacts = _contacts(0.0537, float(source.mass_kg)),
		camera = {mount_frd = PackedFloat64Array([0.06, 0.0, -0.015]), tilt_deg = 40.0, hfov_deg = 120.0},
		start = {rest_height_m = 0.018}, derived = {},
	}


static func electric() -> Dictionary:
	var half: float = 0.215 / 2.0 * 0.70710678118654752
	var mass := 0.65
	var points := PackedFloat64Array()
	for row: Array in [[0.0, 3.30], [0.05, 3.55], [0.10, 3.68], [0.20, 3.74], [0.30, 3.77], [0.40, 3.80], [0.50, 3.84],
			[0.60, 3.88], [0.70, 3.94], [0.80, 4.02], [0.90, 4.11], [1.0, 4.20]]:
		points.append(row[0])
		points.append(6.0 * float(row[1]))
	return {
		identity = {schema = "test-fixture", family = "lab", variant = "synthetic-electric", status = "fixture",
			data_sha256 = "fixture-electric", experimental = true},
		mass_kg = mass, inertia_kg_m2 = PackedFloat64Array([3.2e-3, 3.2e-3, 5.5e-3, 0.0, 0.0, 0.0]),
		rotors = [
			{id = 1, hub_frd = PackedFloat64Array([-half, half, 0.0]), spin = -1.0, diameter_m = 0.12954, inertia_kg_m2 = 7.0e-6},
			{id = 2, hub_frd = PackedFloat64Array([half, half, 0.0]), spin = 1.0, diameter_m = 0.12954, inertia_kg_m2 = 7.0e-6},
			{id = 3, hub_frd = PackedFloat64Array([-half, -half, 0.0]), spin = 1.0, diameter_m = 0.12954, inertia_kg_m2 = 7.0e-6},
			{id = 4, hub_frd = PackedFloat64Array([half, -half, 0.0]), spin = -1.0, diameter_m = 0.12954, inertia_kg_m2 = 7.0e-6},
		],
		rotor_law = {thrust_coefficient_n_s2 = 1.53e-6, torque_coefficient_n_m_s2 = 1.58e-8, rotor_drag_n_s2_per_m = 7.6e-5,
			max_speed_rad_s = 4200.0},
		airframe = {drag_areas_m2 = PackedFloat64Array([0.012, 0.012, 0.020])},
		powertrain = {law = "el-one-quadrant-bus-v1", kv_rad_s_per_v = 225.15, resistance_ohm = 0.133, no_load_current_a = 1.0,
			idle_command = 0.055, max_command = 1.0},
		battery = {cells = 6, capacity_ah = 1.3, ocv_points = points, resistance_ohm = 0.030, auxiliary_current_a = 0.6, initial_soc = 1.0},
		controller = _controller(), contacts = _contacts(half, mass),
		camera = {mount_frd = PackedFloat64Array([0.06, 0.0, -0.015]), tilt_deg = 40.0, hfov_deg = 120.0},
		start = {rest_height_m = 0.018}, derived = {},
	}


## {ok, errors, plant, sim}: a controlled plant on a fresh kernel (not reset yet). The caller frees `sim`.
static func install(parent: Node, data: Dictionary, throttle_policy: int = FC.THROTTLE_ABSOLUTE) -> Dictionary:
	var created: Dictionary = Plant.create(data, Rates.default_profile(), throttle_policy)
	if not created.ok:
		return {ok = false, errors = created.errors, plant = null, sim = null}
	var sim: Node = Sim.new()
	parent.add_child(sim)
	var installed: bool = sim.set_model(created.plant.build())
	sim.mass = float(data.mass_kg)
	sim.inertia = data.inertia_kg_m2.duplicate()
	return {ok = installed, errors = PackedStringArray(), plant = created.plant, sim = sim}


## Commit a full-frame reset. Returns the kernel's refusal message, or "".
static func reset(sim: Node, frame: Dictionary, input: PackedFloat64Array) -> String:
	var prepared: Dictionary = sim.prepare_reset_frame(frame, input)
	if not prepared.ok:
		return str(prepared.message)
	return "" if sim.commit_prepared_reset_frame(prepared) else "commit refused"


static func body(altitude_m: float, attitude: PackedFloat64Array = M.q_identity()) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -altitude_m), M.v3(0.0, 0.0, 0.0), attitude, M.v3(0.0, 0.0, 0.0))


## A pilot frame: sticks [roll, pitch, yaw, throttle], arm level and flight mode.
static func pilot(roll: float, pitch: float, yaw: float, throttle: float, arm: int, mode: int = 0, generation: int = 0) -> PackedFloat64Array:
	var input: PackedFloat64Array = FC.neutral_input(generation)
	input[FC.IN_ROLL] = roll
	input[FC.IN_PITCH] = pitch
	input[FC.IN_YAW] = yaw
	input[FC.IN_THROTTLE] = throttle
	input[FC.IN_ARM] = float(arm)
	input[FC.IN_MODE] = float(mode)
	return input


## Run `ticks` with a constant pilot frame; false when the kernel faults.
static func run(sim: Node, input: PackedFloat64Array, ticks: int) -> bool:
	for _i in ticks:
		sim.inputs = input
		sim.step()
		if not sim.fault_reason.is_empty():
			return false
	return true
