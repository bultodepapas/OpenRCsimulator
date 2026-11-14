# DR-04a…06a (foundation slice): the multirotor plant as a VehicleModel on the shared Simulation kernel.
# Layout: the 13-value body, four continuous rotor speeds (rad/s), four sampled duties in aux, four inputs that are
# the duties themselves (the flight controller of drone plan §4.7 is DR-07; until then the plant is driven by
# duty commands). Loads: four quadratic rotors with linear rotor drag, airframe drag, the N-rotor spinning
# momentum and the inertial yaw of rotor acceleration. Wind comes from the environment contract (SF-07).
# Research-grade: the fixture data is estimated from the identified ETH/UZH research quad (DR-01) and nothing
# here is validated against flight data. No session, catalog or presentation integration.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")
const Powertrain := preload("res://physics/multirotor/powertrain.gd")
const Airframe := preload("res://physics/multirotor/airframe.gd")

const LAW := "multirotor-quadratic-rotor-first-order-motor-v1"
const THRUST_AXIS_BODY := [0.0, 0.0, -1.0]

var data: Dictionary
var environment: RefCounted # SimEnvironment; null = calm air at reference density
var rho: float = 1.225
## Duties of the tick being integrated, written by pre_tick and read by every stage.
var duties: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


## Estimated fixture for the identified 5-inch research quad (DR-01 §1.3–1.4): mass and maximum static thrust
## are measured there; inertia, geometry, coefficients and drag areas are estimates with their derivation noted.
static func research_quad() -> Dictionary:
	var full_speed := 3140.0 # rad/s at full duty under load (≈ 30,000 rpm, estimated for a 2306 2400 KV motor on 4S)
	var max_thrust_per_rotor := 33.0 / 4.0 # N, measured maximum static thrust 33 N (NeuroBEM)
	var c_t := max_thrust_per_rotor / (full_speed * full_speed)
	var half := 0.152 / 2.0 * 0.70710678118654752 # quad-X on a 152 mm motor-to-motor diagonal
	return {
		mass_kg = 0.752, # measured (NeuroBEM airframe)
		inertia_kg_m2 = PackedFloat64Array([2.5e-3, 2.1e-3, 4.3e-3, 0.0, 0.0, 0.0]), # estimated, Agilicious class
		rotors = [ # Betaflight quad-X numbering: 1 rear right, 2 front right, 3 rear left, 4 front left; spin +1 = CCW from above
			{ id = 1, hub_frd = PackedFloat64Array([-half, half, 0.0]), spin = -1.0 },
			{ id = 2, hub_frd = PackedFloat64Array([half, half, 0.0]), spin = 1.0 },
			{ id = 3, hub_frd = PackedFloat64Array([-half, -half, 0.0]), spin = 1.0 },
			{ id = 4, hub_frd = PackedFloat64Array([half, -half, 0.0]), spin = -1.0 },
		],
		rotor = {
			thrust_coefficient_n_s2 = c_t, # calibrated at the measured static point
			torque_coefficient_n_m_s2 = 0.016 * c_t, # torque-to-thrust ratio 0.016 m, estimated for a 5-inch tri-blade
			rotor_drag_n_s2_per_m = 7.6e-5, # k_h so that 4·k_h·ω_h ≈ m·d_x with d_x = 0.6 1/s (identified on another 5-inch quad), estimated
			inertia_kg_m2 = 7.0e-6, # DR-01 derived check
		},
		motor = { full_duty_speed_rad_s = full_speed, time_constant_s = 0.0391, idle_duty = 0.055, output_limit = 1.0 }, # τ measured (Agilicious), idle Betaflight default
		airframe = { drag_areas_m2 = PackedFloat64Array([0.012, 0.012, 0.020]) }, # estimated frontal areas
	}


## Build the VehicleModel for this plant.
func build() -> VehicleModel:
	var vehicle := VehicleModel.new()
	vehicle.input_size = 4
	vehicle.aux_size = 4
	vehicle.modes_size = 0
	vehicle.continuous_size = 4
	vehicle.identity = { vehicle = "multirotor", law = LAW, rotors = data.rotors.size() }
	vehicle.stage = stage
	vehicle.pre_tick = pre_tick
	vehicle.rotor_momentum = Callable() # the stage supplies it
	vehicle.stage_rotor_momentum = Callable()
	vehicle.block_aux = block_aux
	# A sampled momentum callback is required by the contract; the joint stage is the one the kernel uses.
	vehicle.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array()
	return vehicle


## Hover rotor speed and the duty that holds it.
func hover() -> Dictionary:
	var omega: float = Rotor.hover_speed(float(data.mass_kg), 9.80665, data.rotors.size(), data.rotor)
	return { omega = omega, duty = Powertrain.duty_for_speed(omega, data.motor) }


func pre_tick(aux: PackedFloat64Array, inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
	var out := aux.duplicate()
	for i in 4:
		out[i] = Powertrain.duty(inputs[i], data.motor)
	duties = out
	return out


func block_aux(_continuous: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	return aux # the duties are the tick's sampled commands; nothing projects back from the rotor speeds


## Joint stage: {loads, derivative, rotor_momentum}; loads about the CG in FRD, gravity excluded.
func stage(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float) -> Dictionary:
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var v_air: PackedFloat64Array = velocity
	var density: float = rho
	if environment != null:
		var position_ned: PackedFloat64Array = M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2])
		var wind_ned: PackedFloat64Array = environment.wind_world(position_ned, t)
		var wind_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), wind_ned)
		v_air = M.sub(velocity, wind_body)
		density = environment.air_density(body[RB.POS + 2])
	var force: PackedFloat64Array = Airframe.loads(v_air, density, data.airframe)
	var moment: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var derivative := PackedFloat64Array()
	derivative.resize(4)
	var momentum_z := 0.0
	for i in 4:
		var rotor: Dictionary = data.rotors[i]
		var omega: float = continuous[i]
		var omega_dot: float = Powertrain.omega_rate(omega, duties[i], data.motor)
		derivative[i] = omega_dot
		var loads: Dictionary = Rotor.loads(omega, float(rotor.spin), rotor.hub_frd, v_air, rates, omega_dot, data.rotor)
		force = M.add(force, loads.force)
		moment = M.add(moment, loads.moment)
		momentum_z += -float(rotor.spin) * float(data.rotor.inertia_kg_m2) * omega # h = J_r Σ spin·ω along a = [0, 0, −1]
	return {
		loads = PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]),
		derivative = derivative,
		rotor_momentum = M.v3(0.0, 0.0, momentum_z),
	}
