# DR-05/06/07/09/18/19/20: the closed-loop multirotor as a framed sampled VehicleModel (DR-16a protocol).
# The flight controller samples the accepted frame once per tick (flight_controller.gd); every stage of that tick
# reads the same held motor commands from the kernel's sampled context. Nothing here is mutable after create():
# no duty cache, no controller memory, no event latch outside the checkpointed arrays.
#
# Two identified laws, each with its own state layout identity:
#   LAW_LAB       controlled laboratory law: the DR-04a…06a quadratic rotors and first-order shafts of plant.gd,
#                 driven by the controller instead of raw duties; disarm is zero drive (the shaft coasts under the
#                 same lag). Continuous: four shaft speeds.
#   LAW_ELECTRIC  experimental product law: four motors on one battery bus, either one-quadrant (electric_bus.gd:
#                 drive only, the shaft coasts above the commanded speed) or, with powertrain.braking = "damped",
#                 a signed-current bridge (active braking and regeneration into the pack, no current limit),
#                 coupled shaft/body acceleration (FPV flight dynamics §4), pack charge and energy integrals and
#                 the terminal cut latch. Continuous: four shaft speeds, charge [C], terminal energy [J], pack
#                 loss [J], cut latch (exactly 0 or 1, zero derivative).
# Both add flat-pad penalty contacts with regularized Coulomb friction at the feet and hull points.
#
# Declared simplifications (not the plan's full hybrid event policy): the shaft friction of the electrical law is
# viscous below FRICTION_SPEED so a coasting shaft approaches rest smoothly instead of stopping at a located
# event; aerodynamic loads use the motoring branch (speed >= 0) only; crash, propeller strike, obstacle strike
# and pack depletion are decided on the accepted endpoint, so the drive cut takes effect at the end of the
# detecting tick, not at a sub-tick root (pack depletion additionally removes drive inside any stage whose
# charge is not positive). Static quadratic rotor loads: no inflow, descent, propwash or ground effect.
# Research-grade estimates; nothing here is validated against flight data. 64-bit floats only.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")
const Powertrain := preload("res://physics/multirotor/powertrain.gd")
const Airframe := preload("res://physics/multirotor/airframe.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Allocator := preload("res://physics/multirotor/allocator.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const ElectricBus := preload("res://physics/multirotor/electric_bus.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const LAW_LAB := "multirotor-controlled-first-order-v1"
const LAW_ELECTRIC := "multirotor-controlled-el-coupled-v1"
## Bus law identity of the damped (signed-current) bridge variant; the one-quadrant variant is electric_bus.gd.
const BUS_DAMPED := "multirotor-four-load-damped-bus-v1"
const LAYOUT_LAB := "openrc-multirotor-controlled-lab-v1"
const LAYOUT_ELECTRIC := "openrc-multirotor-controlled-el-v1"

const C_SPEED := 0
const C_CHARGE := 4
const C_TERMINAL_ENERGY := 5
const C_PACK_LOSS := 6
const C_CUT_LATCH := 7
const LAB_CONTINUOUS := 4
const ELECTRIC_CONTINUOUS := 8

## Below this relative shaft speed (rad/s) the electrical law's friction torque is viscous.
const FRICTION_SPEED := 30.0
## State domain tolerances of the validator.
const SPEED_TOLERANCE := 5.0
const CHARGE_TOLERANCE := 2.0
## Regularization speed of the contact friction (m/s) and the CG height above which no contact is evaluated.
const FRICTION_CREEP := 0.05
const CONTACT_REACH := 0.6
## Pad contact refinement: pieces per tick and the CG height below which they apply (airframe radius plus margin).
const CONTACT_SUBSTEPS := 4
const CONTACT_SUBSTEP_HEIGHT := 0.25
## Crash impact law: fractions of the tangential velocity and of the body rates kept at a ground crash.
const CRASH_TANGENT_KEEP := 0.5
const CRASH_RATE_KEEP := 0.3

var prepared: Dictionary
var config: Dictionary
var electric: bool = false
var environment: RefCounted # SimEnvironment; null = calm air at reference density
var rho: float = 1.225
## ground(north, east) -> [height_up_m, slope_north, slope_east]; unset = flat ground at height zero.
var ground: Callable = Callable()
## obstacle(north, east, down) -> clearance_m to the nearest solid (<= 0 inside); unset = none.
var obstacle: Callable = Callable()

var _rotor_laws: Array[Dictionary] = []
var _motor: Dictionary = {}
var _effective_inverse := PackedFloat64Array()
var _points: Array[PackedFloat64Array] = []
var _foot_count := 0
var _body_radius := 0.0
var _resistance := PackedFloat64Array()
var _braking := false
var _hub := PackedFloat64Array() # four hubs, three values each
var _spin := PackedFloat64Array()
var _rotor_inertia := PackedFloat64Array()
var _k_t := 0.0
var _k_q := 0.0
var _k_h := 0.0


## {ok, errors, plant}. `data` is a prepared multirotor document (physics/multirotor_data.gd), `rates_profile` an
## openrc-rates profile, `throttle_policy` FC.THROTTLE_ABSOLUTE or FC.THROTTLE_RATE.
static func create(data: Dictionary, rates_profile: Dictionary, throttle_policy: int, research_sample_hz: int = 0,
		throttle_limit: float = 1.0) -> Dictionary:
	var errors := PackedStringArray()
	var plant: RefCounted = (load("res://physics/multirotor/controlled_plant.gd") as GDScript).new()
	plant.prepared = data
	var law: String = str(data.get("powertrain", {}).get("law", ""))
	plant.electric = law == ActuatorMap.LAW_ELECTRIC
	plant._braking = plant.electric and str(data.powertrain.get("braking", "none")) == "damped"
	var actuator: Dictionary = ActuatorMap.prepare(data.get("powertrain", {}), data.get("rotor_law", {}))
	if not actuator.ok:
		errors.append_array(actuator.errors)
	var rates: Dictionary = Rates.prepare(rates_profile)
	if not rates.ok:
		errors.append_array(rates.errors)
	if not errors.is_empty():
		return {ok = false, errors = errors, plant = null}
	var k_t: float = data.rotor_law.thrust_coefficient_n_s2
	var kappa: float = float(data.rotor_law.torque_coefficient_n_m_s2) / k_t
	var full_voltage: float = plant._ocv(1.0) if plant.electric else 0.0
	var top_thrust: float = ActuatorMap.static_thrust(actuator.map, actuator.map.top, full_voltage)
	var reach_x := 0.0
	var reach_y := 0.0
	var rotor_inertia := 0.0
	plant._k_t = k_t
	plant._k_q = float(data.rotor_law.torque_coefficient_n_m_s2)
	plant._k_h = float(data.rotor_law.rotor_drag_n_s2_per_m)
	for rotor: Dictionary in data.rotors:
		plant._hub.append_array(rotor.hub_frd)
		plant._spin.append(float(rotor.spin))
		plant._rotor_inertia.append(float(rotor.inertia_kg_m2))
		reach_x = maxf(reach_x, absf(rotor.hub_frd[0]))
		reach_y = maxf(reach_y, absf(rotor.hub_frd[1]))
		rotor_inertia += float(rotor.inertia_kg_m2)
		plant._body_radius = maxf(plant._body_radius, M.norm(rotor.hub_frd) + 0.5 * float(rotor.diameter_m))
		plant._rotor_laws.append({thrust_coefficient_n_s2 = k_t,
			torque_coefficient_n_m_s2 = float(data.rotor_law.torque_coefficient_n_m_s2),
			rotor_drag_n_s2_per_m = float(data.rotor_law.rotor_drag_n_s2_per_m), inertia_kg_m2 = float(rotor.inertia_kg_m2)})
	var allocator: Dictionary = Allocator.prepare(data.rotors, PackedFloat64Array([kappa, kappa, kappa, kappa]),
		PackedFloat64Array([4.0 * top_thrust, 2.0 * top_thrust * reach_y, 2.0 * top_thrust * reach_x, 2.0 * top_thrust * kappa]),
		data.controller.allocator_weights)
	if not allocator.ok:
		errors.append_array(allocator.errors)
		return {ok = false, errors = errors, plant = null}
	var controller: Dictionary = FC.prepare(data.controller, rates.prepared, allocator, actuator.map, throttle_policy,
		research_sample_hz, throttle_limit)
	if not controller.ok:
		errors.append_array(controller.errors)
		return {ok = false, errors = errors, plant = null}
	plant.config = controller.config
	if plant.electric:
		var effective: PackedFloat64Array = data.inertia_kg_m2.duplicate()
		effective[2] -= rotor_inertia # every spin axis is body z
		plant._effective_inverse = RB.inertia_inverse(effective)
		var r: float = data.powertrain.resistance_ohm
		plant._resistance = PackedFloat64Array([r, r, r, r])
		for value: float in plant._effective_inverse:
			if not is_finite(value):
				return {ok = false, errors = PackedStringArray(["plant: effective inertia is not invertible"]), plant = null}
	else:
		plant._motor = {full_duty_speed_rad_s = float(data.powertrain.full_command_speed_rad_s),
			time_constant_s = float(data.powertrain.time_constant_s)}
	for point: PackedFloat64Array in data.contacts.feet_frd:
		plant._points.append(point.duplicate())
	plant._foot_count = plant._points.size()
	for point: PackedFloat64Array in data.contacts.hull_frd:
		plant._points.append(point.duplicate())
	return {ok = true, errors = errors, plant = plant}


func law() -> String:
	return LAW_ELECTRIC if electric else LAW_LAB


func layout() -> String:
	return LAYOUT_ELECTRIC if electric else LAYOUT_LAB


func continuous_size() -> int:
	return ELECTRIC_CONTINUOUS if electric else LAB_CONTINUOUS


## Build the framed VehicleModel for this plant.
func build() -> VehicleModel:
	var vehicle := VehicleModel.new()
	vehicle.callback_protocol = VehicleModel.PROTOCOL_FRAMED_SAMPLED
	vehicle.state_layout_identity = layout()
	vehicle.input_size = FC.INPUT_SIZE
	vehicle.aux_size = FC.AUX_SIZE
	vehicle.modes_size = FC.MODES_SIZE
	vehicle.continuous_size = continuous_size()
	vehicle.identity = {vehicle = "multirotor", law = law(), layout = layout(), controller = FC.LAW,
		controller_identity = str(config.identity), allocator = Allocator.LAW, rates = str(config.rates.identity),
		bus = (BUS_DAMPED if _braking else ElectricBus.LAW) if electric else "ideal-supply", data = str(prepared.identity.get("data_sha256", "")),
		variant = str(prepared.identity.get("variant", "")), throttle_policy = int(config.throttle_policy)}
	vehicle.sample_tick = sample_tick
	vehicle.stage_sampled = stage_sampled
	vehicle.endpoint_transition = endpoint_transition
	vehicle.substeps = substeps
	# The domain check (state_validator below) runs inside the endpoint transition on every accepted tick and is
	# called by the session before a reset or restore is committed. It is deliberately not installed as the
	# kernel's per-step validator hook, which would run its guarded copy of the frame twice per tick.
	return vehicle


## The prepared start frame for a body state: shafts at rest, pack at `soc`, controller disarmed.
func initial_frame(body: PackedFloat64Array, source_generation: int = 0, soc: float = -1.0) -> Dictionary:
	var continuous := PackedFloat64Array()
	continuous.resize(continuous_size())
	if electric:
		var start_soc: float = float(prepared.battery.initial_soc) if soc < 0.0 else soc
		continuous[C_CHARGE] = start_soc * 3600.0 * float(prepared.battery.capacity_ah)
	return {body = body.duplicate(), continuous = continuous, aux = FC.initial_aux(body),
		modes = FC.initial_modes(source_generation)}


func sample_tick(frame: Dictionary, input: PackedFloat64Array, clock: Dictionary) -> Dictionary:
	return FC.sample(config, frame, input, clock, supply_voltage(frame.continuous))


## Supply voltage the controller's static map uses: the pack's open-circuit voltage at the sampled charge.
func supply_voltage(continuous: PackedFloat64Array) -> float:
	return _ocv(_soc(continuous)) if electric else 0.0


func _soc(continuous: PackedFloat64Array) -> float:
	return clampf(continuous[C_CHARGE] / (3600.0 * float(prepared.battery.capacity_ah)), 0.0, 1.0)


## Piecewise-linear open-circuit pack voltage; ocv_points = [soc0, v0, soc1, v1, ...] with increasing soc.
func _ocv(soc: float) -> float:
	var points: PackedFloat64Array = prepared.battery.ocv_points
	var last: int = points.size() - 2
	if soc <= points[0]:
		return points[1]
	for i in range(0, last, 2):
		if soc <= points[i + 2]:
			var fraction: float = (soc - points[i]) / (points[i + 2] - points[i])
			return points[i + 1] + fraction * (points[i + 3] - points[i + 1])
	return points[last + 1]


## Joint stage: {loads, derivative, rotor_momentum}; loads about the CG in FRD, gravity excluded.
func stage_sampled(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float, context: Dictionary) -> Dictionary:
	var evaluation: Dictionary = _evaluate(body, continuous, t, context.aux, context.modes)
	return {loads = evaluation.loads, derivative = evaluation.derivative, rotor_momentum = evaluation.rotor_momentum}


## One pure evaluation of the plant at a state and a held sample. Also the telemetry source.
func _evaluate(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float, aux: PackedFloat64Array,
		modes: PackedInt64Array) -> Dictionary:
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var v_air: PackedFloat64Array = velocity
	var density: float = rho
	if environment != null:
		var position_ned: PackedFloat64Array = M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2])
		v_air = M.sub(velocity, M.q_rotate(M.q_conj(attitude), environment.wind_world(position_ned, t)))
		density = environment.air_density(body[RB.POS + 2])
	var force: PackedFloat64Array = Airframe.loads(v_air, density, prepared.airframe)
	var moment: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var contact: Dictionary = _contact_loads(body, attitude, velocity, rates)
	force = M.add(force, contact.force)
	moment = M.add(moment, contact.moment)
	var armed: bool = modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED
	var derivative := PackedFloat64Array()
	derivative.resize(continuous_size())
	var momentum_z := 0.0
	if not electric:
		for i in 4:
			var rotor: Dictionary = prepared.rotors[i]
			var omega: float = continuous[i]
			var command: float = aux[FC.AUX_COMMAND + i] if armed else 0.0
			var omega_dot: float = Powertrain.omega_rate(omega, command, _motor)
			derivative[i] = omega_dot
			var loads: Dictionary = Rotor.loads(omega, float(rotor.spin), rotor.hub_frd, v_air, rates, omega_dot, _rotor_laws[i])
			force = M.add(force, loads.force)
			moment = M.add(moment, loads.moment)
			momentum_z += -float(rotor.spin) * float(rotor.inertia_kg_m2) * omega
		return {loads = PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]),
			derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, momentum_z), bus = {}}
	# Electrical law: one bus for the four loads, then the coupled shaft/body acceleration.
	var connected: bool = continuous[C_CHARGE] > 0.0
	var drive: bool = armed and connected and continuous[C_CUT_LATCH] == 0.0
	var kv: float = prepared.powertrain.kv_rad_s_per_v
	var kt: float = 1.0 / kv
	var duty := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var back_emf := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var enabled := PackedInt64Array([0, 0, 0, 0])
	for i in 4:
		back_emf[i] = (continuous[i] if _braking else maxf(continuous[i], 0.0)) / kv
		if drive:
			duty[i] = aux[FC.AUX_COMMAND + i]
			enabled[i] = 1
	var bus: Dictionary = {}
	if connected:
		bus = _bus(_ocv(_soc(continuous)), duty, back_emf, enabled, drive)
		if not bus.get("ok", false):
			return {loads = PackedFloat64Array([NAN, 0.0, 0.0, 0.0, 0.0, 0.0]), derivative = derivative,
				rotor_momentum = M.v3(0.0, 0.0, 0.0), bus = bus}
	var shaft_torque := PackedFloat64Array([0.0, 0.0, 0.0, 0.0]) # net motor torque minus aerodynamic torque
	var reaction_z := 0.0
	var friction_torque: float = kt * float(prepared.powertrain.no_load_current_a)
	# The rotor law of rotor.gd (quadratic thrust and torque, linear rotor drag at the hub's air velocity) written
	# out in scalars: this loop runs four times per stage, and the tests hold it equal to Rotor.loads.
	var fx: float = force[0]
	var fy: float = force[1]
	var fz: float = force[2]
	var mx: float = moment[0]
	var my: float = moment[1]
	var mz: float = moment[2]
	for i in 4:
		var omega: float = continuous[i]
		var motoring: float = maxf(omega, 0.0)
		var hx: float = _hub[3 * i]
		var hy: float = _hub[3 * i + 1]
		var hz: float = _hub[3 * i + 2]
		var thrust: float = _k_t * motoring * motoring
		var torque: float = _k_q * motoring * motoring
		var rotor_fx: float = -_k_h * motoring * (v_air[0] + rates[1] * hz - rates[2] * hy)
		var rotor_fy: float = -_k_h * motoring * (v_air[1] + rates[2] * hx - rates[0] * hz)
		fx += rotor_fx
		fy += rotor_fy
		fz -= thrust
		mx += hy * -thrust - hz * rotor_fy
		my += hz * rotor_fx - hx * -thrust
		mz += hx * rotor_fy - hy * rotor_fx + _spin[i] * torque
		var current: float = bus.i_motor[i] if connected else 0.0
		shaft_torque[i] = kt * current - friction_torque * clampf(omega / FRICTION_SPEED, -1.0, 1.0) - torque
		reaction_z += _spin[i] * shaft_torque[i]
		momentum_z += -_spin[i] * _rotor_inertia[i] * omega
	force = M.v3(fx, fy, fz)
	moment = M.v3(mx, my, mz)
	# I_eff·alpha = tau_ext − omega × (I_L·omega + h) + z·sum(spin·(Q_motor − Q_aero)); spin axes are body −z.
	var momentum: PackedFloat64Array = M.add(RB.inertia_mul(prepared.inertia_kg_m2, rates), M.v3(0.0, 0.0, momentum_z))
	var rhs: PackedFloat64Array = M.sub(moment, M.cross(rates, momentum))
	rhs[2] += reaction_z
	var alpha: PackedFloat64Array = RB.inertia_mul(_effective_inverse, rhs)
	for i in 4:
		var omega_dot: float = shaft_torque[i] / _rotor_inertia[i] + _spin[i] * alpha[2]
		derivative[i] = omega_dot
		moment[2] += _spin[i] * _rotor_inertia[i] * omega_dot # counted once, here
	if connected:
		derivative[C_CHARGE] = -float(bus.i_pack)
		derivative[C_TERMINAL_ENERGY] = float(bus.p_terminal_w)
		derivative[C_PACK_LOSS] = float(bus.p_pack_loss_w)
	return {loads = PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]]),
		derivative = derivative, rotor_momentum = M.v3(0.0, 0.0, momentum_z), bus = bus}


## The shared bus of one stage: {ok, v_bus, i_motor, i_pack, p_terminal_w, p_pack_loss_w}. Two closed forms cover
## flight: no drive (only the auxiliary load), and all four loads driving, accepted only when that active set is
## consistent with its own bus voltage. Every other case (a coasting rotor among driving ones) is the exhaustive
## active-set solve of electric_bus.gd, the law's reference (tests compare the two).
func _bus(voc: float, duty: PackedFloat64Array, back_emf: PackedFloat64Array, enabled: PackedInt64Array, drive: bool) -> Dictionary:
	var pack_resistance: float = prepared.battery.resistance_ohm
	var auxiliary: float = prepared.battery.auxiliary_current_a
	if not drive:
		var idle_bus: float = voc - pack_resistance * auxiliary
		return {ok = idle_bus > 0.0, v_bus = idle_bus, i_motor = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), i_pack = auxiliary,
			p_terminal_w = idle_bus * auxiliary, p_pack_loss_w = pack_resistance * auxiliary * auxiliary}
	var resistance: float = _resistance[0]
	var emf_sum := 0.0
	var duty_sum := 0.0
	for i in 4:
		emf_sum += duty[i] * back_emf[i] / resistance
		duty_sum += duty[i] * duty[i] / resistance
	var v_bus: float = (voc - pack_resistance * auxiliary + pack_resistance * emf_sum) / (1.0 + pack_resistance * duty_sum)
	var currents := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var pack_current: float = auxiliary
	if _braking:
		# Damped bridge: every driven motor carries a signed current, so the four-load bus is linear with no
		# active set. A negative motor current brakes the shaft; a negative pack current charges the pack.
		for i in 4:
			currents[i] = (duty[i] * v_bus - back_emf[i]) / resistance
			pack_current += duty[i] * currents[i]
		return {ok = v_bus > 0.0, v_bus = v_bus, i_motor = currents, i_pack = pack_current,
			p_terminal_w = v_bus * pack_current, p_pack_loss_w = pack_resistance * pack_current * pack_current}
	var consistent: bool = v_bus > 0.0
	for i in 4:
		if duty[i] * v_bus <= back_emf[i]:
			consistent = false
			break
		currents[i] = (duty[i] * v_bus - back_emf[i]) / resistance
		pack_current += duty[i] * currents[i]
	if not consistent:
		return ElectricBus.solve(voc, pack_resistance, auxiliary, duty, back_emf, _resistance, enabled)
	return {ok = true, v_bus = v_bus, i_motor = currents, i_pack = pack_current,
		p_terminal_w = v_bus * pack_current, p_pack_loss_w = pack_resistance * pack_current * pack_current}


func _ground_at(north: float, east: float) -> PackedFloat64Array:
	if ground.is_valid():
		return ground.call(north, east)
	return PackedFloat64Array([0.0, 0.0, 0.0])


## Penalty contacts of the feet and hull points with the terrain: {force, moment} in body axes about the CG.
## Normal force max(0, k·depth + c·closing) along the terrain normal; friction mu·N against the tangential
## velocity, regularized below FRICTION_CREEP so a resting airframe is a stiff damper, never a division by zero.
func _contact_loads(body: PackedFloat64Array, attitude: PackedFloat64Array, velocity: PackedFloat64Array,
		rates: PackedFloat64Array) -> Dictionary:
	var force: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var moment: PackedFloat64Array = M.v3(0.0, 0.0, 0.0)
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	if -body[RB.POS + 2] - under[0] > CONTACT_REACH:
		return {force = force, moment = moment}
	var contacts: Dictionary = prepared.contacts
	var stiffness: float = contacts.stiffness_n_per_m
	var damping: float = contacts.damping_n_s_per_m
	var friction: float = contacts.friction
	var inverse: PackedFloat64Array = M.q_conj(attitude)
	for point: PackedFloat64Array in _points:
		var offset: PackedFloat64Array = M.q_rotate(attitude, point)
		var north: float = body[RB.POS] + offset[0]
		var east: float = body[RB.POS + 1] + offset[1]
		var surface: PackedFloat64Array = _ground_at(north, east)
		var depth: float = body[RB.POS + 2] + offset[2] + surface[0]
		if depth <= 0.0:
			continue
		var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(surface[1], surface[2])
		var v_world: PackedFloat64Array = M.q_rotate(attitude, M.add(velocity, M.cross(rates, point)))
		var along: float = M.dot(v_world, normal)
		var load: float = maxf(0.0, stiffness * depth * -normal[2] - damping * along)
		if load <= 0.0:
			continue
		var tangential: PackedFloat64Array = M.sub(v_world, M.scale(normal, along))
		var slip: float = M.norm(tangential)
		var f_world: PackedFloat64Array = M.add(M.scale(normal, load), M.scale(tangential, -friction * load / (slip + FRICTION_CREEP)))
		var f_body: PackedFloat64Array = M.q_rotate(inverse, f_world)
		force = M.add(force, f_body)
		moment = M.add(moment, M.cross(point, f_body))
	return {force = force, moment = moment}


## Pure endpoint transition: terminal adjudication on the accepted candidate. A crash or an exhausted pack sets the
## motor lifecycle, latches the drive cut and reports one event; the sampled commands of the interval stay as held.
func endpoint_transition(_previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
	var modes: PackedInt64Array = candidate.modes
	var continuous: PackedFloat64Array = candidate.continuous
	var events: Array = []
	# A crash is adjudicated until one has happened, also for a quad falling on an exhausted pack.
	if modes[FC.MODE_MOTOR] != FC.MOTOR_CRASHED:
		var reason: String = crash_reason(_previous.body, candidate.body, continuous)
		if not reason.is_empty():
			modes[FC.MODE_MOTOR] = FC.MOTOR_CRASHED
			modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_TERMINAL
			events.append({type = "crash", time_s = float(context.time_s), reason = reason})
			if reason != "Obstacle strike":
				candidate.body = _settle_impact(candidate.body)
		elif electric and continuous[C_CHARGE] <= 0.0 and modes[FC.MODE_MOTOR] != FC.MOTOR_DEPLETED:
			modes[FC.MODE_MOTOR] = FC.MOTOR_DEPLETED
			modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_TERMINAL
			events.append({type = "pack_depleted", time_s = float(context.time_s)})
		if electric and not events.is_empty():
			continuous[C_CUT_LATCH] = 1.0
	var accepted := {body = candidate.body, continuous = continuous, aux = candidate.aux, modes = modes}
	if not state_validator(accepted, context):
		return {} # outside the law's domain: a malformed result, so the kernel refuses the tick
	accepted.events = events
	return accepted


## Crash impact law, applied once on the accepted endpoint of a ground crash: the closing velocity along the
## terrain normal is removed, the tangential velocity and the body rates keep the declared fractions, and the
## body is lifted along the normal until its deepest contact point is at the surface. A declared aftermath for
## presentation (the airframe comes to rest instead of burying itself in the penalty springs), not a structural
## or restitution model; the attempt is already terminal when it runs.
func _settle_impact(body: PackedFloat64Array) -> PackedFloat64Array:
	var settled: PackedFloat64Array = body.duplicate()
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(under[1], under[2])
	var v_world: PackedFloat64Array = M.q_rotate(attitude, M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2]))
	var along: float = M.dot(v_world, normal)
	var tangential: PackedFloat64Array = M.scale(M.sub(v_world, M.scale(normal, along)), CRASH_TANGENT_KEEP)
	var kept: PackedFloat64Array = M.add(tangential, M.scale(normal, maxf(along, 0.0)))
	var v_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), kept)
	var deepest := 0.0
	for point: PackedFloat64Array in _points:
		var offset: PackedFloat64Array = M.q_rotate(attitude, point)
		var surface: PackedFloat64Array = _ground_at(body[RB.POS] + offset[0], body[RB.POS + 1] + offset[1])
		deepest = maxf(deepest, body[RB.POS + 2] + offset[2] + surface[0])
	for i in 3:
		settled[RB.VEL + i] = v_body[i]
		settled[RB.RATE + i] = body[RB.RATE + i] * CRASH_RATE_KEEP
		settled[RB.POS + i] = body[RB.POS + i] + normal[i] * deepest * -normal[2]
	return settled


## Contact substeps for this tick: the stiff pad contact is integrated in CONTACT_SUBSTEPS pieces while the CG is
## within CONTACT_SUBSTEP_HEIGHT of the terrain; free flight keeps one RK4 step per tick.
func substeps(body: PackedFloat64Array, _continuous: PackedFloat64Array, _t: float) -> int:
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	return CONTACT_SUBSTEPS if -body[RB.POS + 2] - under[0] < CONTACT_SUBSTEP_HEIGHT else 1


## "" or the terminal cause at this accepted body state: a hard impact of a foot or hull point, a spinning rotor
## disc reaching the terrain, or the airframe sphere reaching a solid obstacle (also tested at the tick midpoint).
func crash_reason(previous_body: PackedFloat64Array, body: PackedFloat64Array, continuous: PackedFloat64Array) -> String:
	if obstacle.is_valid():
		for fraction: float in [0.5, 1.0]:
			var north: float = lerpf(previous_body[RB.POS], body[RB.POS], fraction)
			var east: float = lerpf(previous_body[RB.POS + 1], body[RB.POS + 1], fraction)
			var down: float = lerpf(previous_body[RB.POS + 2], body[RB.POS + 2], fraction)
			var clearance: Variant = obstacle.call(north, east, down)
			if typeof(clearance) == TYPE_FLOAT and clearance <= _body_radius:
				return "Obstacle strike"
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	if -body[RB.POS + 2] - under[0] > CONTACT_REACH:
		return ""
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var attitude: PackedFloat64Array = M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3])
	var crash_speed: float = prepared.contacts.crash_speed_mps
	var previous_velocity: PackedFloat64Array = M.v3(previous_body[RB.VEL], previous_body[RB.VEL + 1], previous_body[RB.VEL + 2])
	var previous_rates: PackedFloat64Array = M.v3(previous_body[RB.RATE], previous_body[RB.RATE + 1], previous_body[RB.RATE + 2])
	var previous_attitude: PackedFloat64Array = M.quat(previous_body[RB.ATT], previous_body[RB.ATT + 1], previous_body[RB.ATT + 2],
		previous_body[RB.ATT + 3])
	for point: PackedFloat64Array in _points:
		var offset: PackedFloat64Array = M.q_rotate(attitude, point)
		var surface: PackedFloat64Array = _ground_at(body[RB.POS] + offset[0], body[RB.POS + 1] + offset[1])
		if body[RB.POS + 2] + offset[2] + surface[0] <= 0.0:
			continue
		var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(surface[1], surface[2])
		var v_world: PackedFloat64Array = M.q_rotate(attitude, M.add(velocity, M.cross(rates, point)))
		# The stiff contact has already slowed the point by the endpoint of its first contact tick, so the
		# closing speed it arrived with (the previous accepted frame) decides as well.
		var v_before: PackedFloat64Array = M.q_rotate(previous_attitude, M.add(previous_velocity, M.cross(previous_rates, point)))
		if maxf(-M.dot(v_world, normal), -M.dot(v_before, normal)) > crash_speed:
			return "Hard impact"
	# Spinning disc: the rim point closest to the ground.
	var axis: PackedFloat64Array = M.q_rotate(attitude, M.v3(0.0, 0.0, -1.0))
	var lowest: PackedFloat64Array = M.sub(M.v3(0.0, 0.0, 1.0), M.scale(axis, axis[2]))
	var lowest_norm: float = M.norm(lowest)
	var strike_speed: float = prepared.contacts.rotor_strike_speed_rad_s
	for i in 4:
		if continuous[i] <= strike_speed:
			continue
		var rotor: Dictionary = prepared.rotors[i]
		var rim: PackedFloat64Array = M.q_rotate(attitude, rotor.hub_frd)
		if lowest_norm > 1.0e-9:
			rim = M.add(rim, M.scale(lowest, 0.5 * float(rotor.diameter_m) / lowest_norm))
		var surface: PackedFloat64Array = _ground_at(body[RB.POS] + rim[0], body[RB.POS + 1] + rim[1])
		if body[RB.POS + 2] + rim[2] + surface[0] > 0.0:
			return "Propeller strike"
	return ""


## Domain of an accepted frame: enum values, shaft speeds, charge and the cut latch's agreement with the lifecycle.
func state_validator(frame: Dictionary, _context: Dictionary) -> bool:
	if not FC.modes_are_valid(frame.modes):
		return false
	var continuous: PackedFloat64Array = frame.continuous
	var ceiling: float = 1.5 * float(prepared.rotor_law.max_speed_rad_s)
	# The electrical law's shaft speed is relative to the body: a stopped rotor on a tumbling airframe reads
	# negative while friction drags it along, so its domain is symmetric. The lag law never goes below rest.
	var floor_speed: float = -ceiling if electric else -SPEED_TOLERANCE
	for i in 4:
		if continuous[i] < floor_speed or continuous[i] > ceiling:
			return false
	var aux: PackedFloat64Array = frame.aux
	for i in 4:
		if aux[FC.AUX_COMMAND + i] < 0.0 or aux[FC.AUX_COMMAND + i] > 1.0:
			return false
	if aux[FC.AUX_COLLECTIVE] < 0.0 or aux[FC.AUX_COLLECTIVE] > 1.0 \
			or aux[FC.AUX_VIRTUAL_THROTTLE] < 0.0 or aux[FC.AUX_VIRTUAL_THROTTLE] > 1.0:
		return false
	if electric:
		var terminal: bool = frame.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED or frame.modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED
		if continuous[C_CHARGE] < -CHARGE_TOLERANCE or continuous[C_CUT_LATCH] not in [0.0, 1.0] \
				or (continuous[C_CUT_LATCH] == 1.0) != terminal:
			return false
	return true


## Read-only telemetry of an accepted frame (a pure evaluation; nothing advances). Battery values exist only for
## the electrical law; the laboratory law has an ideal supply and reports none.
func telemetry(frame: Dictionary, t: float = 0.0) -> Dictionary:
	var modes: PackedInt64Array = frame.modes
	var aux: PackedFloat64Array = frame.aux
	var out := {motor_state = modes[FC.MODE_MOTOR], flight_mode = modes[FC.MODE_FLIGHT], arm_block = modes[FC.MODE_ARM_BLOCK],
		collective = aux[FC.AUX_COLLECTIVE], rotor_speed_rad_s = frame.continuous.slice(0, 4),
		commands = aux.slice(FC.AUX_COMMAND, FC.AUX_COMMAND + 4), has_battery = electric}
	if electric:
		var evaluation: Dictionary = _evaluate(frame.body, frame.continuous, t, aux, modes)
		var bus: Dictionary = evaluation.bus
		out.soc = _soc(frame.continuous)
		out.bus_voltage_v = float(bus.get("v_bus", 0.0))
		out.pack_current_a = float(bus.get("i_pack", 0.0))
		out.consumed_mah = (float(prepared.battery.initial_soc) * 3600.0 * float(prepared.battery.capacity_ah) - frame.continuous[C_CHARGE]) / 3.6
	return out
