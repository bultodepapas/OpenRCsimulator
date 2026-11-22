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
#                 a signed-current bridge (active braking and regeneration into the pack, no current limit; the
#                 pack accepts charge only below its capacity, see CHARGE_ACCEPTANCE_S),
#                 coupled shaft/body acceleration (FPV flight dynamics §4), pack charge and energy integrals and
#                 the terminal cut latch. Continuous: four shaft speeds, charge [C], terminal energy [J], pack
#                 loss [J], cut latch (exactly 0 or 1, zero derivative), four prop health factors (DR-19c, in [0, 1],
#                 zero derivative, changed only by the graded impact law at an accepted endpoint).
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
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")

const LAW_LAB := "multirotor-controlled-first-order-v1"
const LAW_ELECTRIC := "multirotor-controlled-el-coupled-v1"
## Bus law identity of the damped (signed-current) bridge variant; the one-quadrant variant is electric_bus.gd.
## v2 (audit A06): regeneration is bounded by the pack's charge acceptance.
const BUS_DAMPED := "multirotor-four-load-damped-bus-v2"
## Audit A06, declared charge-acceptance law of the damped bridge: a charging pack current is limited to
## (capacity charge - charge) / CHARGE_ACCEPTANCE_S, so a full pack accepts none and the charge approaches its capacity
## without crossing it (RK4 with h/tau <= 1/48 is monotone on that decay). While the limit binds, the bus floats above
## the pack's Thevenin voltage until the motors' regenerative currents fall to what the pack accepts (overvoltage that
## weakens the braking, as a blocked pack would), and the energy the pack cannot store is dissipated in it
## (p_pack_loss_w = (Voc - V)*I, which reduces to R*I^2 when the limit does not bind). Not a model of a real ESC's
## braking, a LiPo's overvoltage limit or its charge chemistry: a coherent bound in place of unbounded regeneration.
const CHARGE_ACCEPTANCE_S := 0.2
const LAYOUT_LAB := "openrc-multirotor-controlled-lab-v1"
## v2 (DR-19c): four prop health factors after the cut latch.
const LAYOUT_ELECTRIC := "openrc-multirotor-controlled-el-v2"

const C_SPEED := 0
const C_CHARGE := 4
const C_TERMINAL_ENERGY := 5
const C_PACK_LOSS := 6
const C_CUT_LATCH := 7
const C_HEALTH := 8
const LAB_CONTINUOUS := 4
const ELECTRIC_CONTINUOUS := 12

## Below this relative shaft speed (rad/s) the electrical law's friction torque is viscous.
const FRICTION_SPEED := 30.0
## State domain tolerances of the validator.
const SPEED_TOLERANCE := 5.0
const CHARGE_TOLERANCE := 2.0
## Regularization speed of the contact friction (m/s) and the CG height above which no contact is evaluated.
## 0.02 m/s (DR-18-R2, 2026-11-12; was 0.05): softer regularization made the friction a 0.64 N·m·s yaw damper whose
## 3.2 ms time constant, under the motors' immediate torque response, closed the armed-idle yaw loop above unit gain
## (a 120 Hz yaw-rate flip of ±0.021 rad/s and diagonal motor chatter on the pad); 0.02 removes it with margin and
## cuts creep on a slope 2.5 times. Below about 0.01 the stiff friction mode needs more than four pieces.
const FRICTION_CREEP := 0.02
const CONTACT_REACH := 0.6
## Pad contact refinement: pieces per tick and the CG height below which they apply (airframe radius plus margin).
const CONTACT_SUBSTEPS := 4
const CONTACT_SUBSTEP_HEIGHT := 0.25
## A contact within that height is refined unless the quad is RESTING: CG speed, body rate and every rotor below
## these bounds (below REST_ROTOR_FRACTION of the symmetric hover speed a rotor lifts less than a quarter of the
## weight share: disarmed, or armed at idle). A resting quad takes `parked_pieces` (DR-18/R1, R2, 2026-11-12: with
## the R2 friction regularization the armed-idle pad state converges from two pieces up).
const REST_SPEED_MPS := 0.25
const REST_RATE_RAD_S := 0.5
const REST_ROTOR_FRACTION := 0.5
## Standard gravity for the rest threshold's symmetric hover speed only (the kernel owns the gravity of the dynamics).
const STANDARD_GRAVITY := 9.80665
## One piece is admitted for a parked quad only while h·|λ| of its stiffest parked contact mode stays at or below
## this bound (RK4's real-axis stability limit is about 2.79), at the session's fixed 240 Hz tick.
const PARKED_H_LAMBDA_LIMIT := 2.0
const PARKED_CHECK_DT := 1.0 / 240.0
## Crash impact law: fractions of the tangential velocity and of the body rates kept at a ground crash.
const CRASH_TANGENT_KEEP := 0.5
const CRASH_RATE_KEEP := 0.3
## Rotor disc strike search (audit A07): rim samples are taken once the planar penetration bound at the hub is within
## this margin (m) of the terrain. 0.03 m is four times the plane-versus-ramp deviation of the steepest shipped RC ramp
## over the prop radius (1/2 * 2.88 1/m * 0.0648^2 m^2 = 6 mm) and above the 21.5 mm hub height of a quad resting on
## the pad (so the ring also runs there, with no false strike: only real terrain samples decide).
const ROTOR_RIM_MARGIN := 0.03
## Rim directions, 45 degrees apart in the disc plane (the first is the worst direction of the local plane).
const ROTOR_RIM_COS := [1.0, 0.7071067811865476, 0.0, -0.7071067811865476, -1.0, -0.7071067811865476, 0.0, 0.7071067811865476]
const ROTOR_RIM_SIN := [0.0, 0.7071067811865476, 1.0, 0.7071067811865476, 0.0, -0.7071067811865476, -1.0, -0.7071067811865476]

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
## Shaft speed (rad/s) above which a rotor counts as turning for the contact refinement; 0 refines any turning rotor
## and a negative value means the quad is never parked (its parked contact would be too stiff for one piece).
var _rest_rotor_speed := 0.0
## h·|λ| of the stiffest parked contact mode (see parked_stiffness); above PARKED_H_LAMBDA_LIMIT nothing is parked.
var parked_one_piece_h_lambda := INF
## RK4 pieces per tick for a parked quad near the terrain (1…CONTACT_SUBSTEPS; see substeps).
var parked_pieces := CONTACT_SUBSTEPS
var _resistance := PackedFloat64Array()
var _braking := false
var _hub := PackedFloat64Array() # four hubs, three values each
var _spin := PackedFloat64Array()
var _rotor_inertia := PackedFloat64Array()
var _k_t := 0.0
var _k_q := 0.0
var _k_h := 0.0
## DR-19c: graded impacts (IMPACT_GRADED) instead of the strict law where every contact ends the flight. Electrical
## law only; part of the model identity. obstacle_class(north, east, down) names the nearest solid's response class.
var graded_impacts := false
var obstacle_class: Callable = Callable()
## CR-AUD-25: prop_disc_contact(hub_ned, axis_ned, radius_m, half_thickness_m) -> {} or the deepest obstacle that
## intersects the finite prop disc: {penetration_m, normal (outward, NED), point_ned, kind}, judged per obstacle.
## Unset keeps the hub-clearance estimate.
var prop_disc_contact: Callable = Callable()
## CR-AUD-01/R2: water_contact(body, time_s) -> true when the airframe touches an enabled lake's water; unset =
## no water. Terminal in the endpoint transition (no water force model): the drive is cut, nothing is settled.
var water_contact: Callable = Callable()
var _hover_speed := 0.0
## DR-19e (§19.4): the frame's collision box (FRD, from the CG): x/y across the motor hubs, z from the hull's top point
## to the feet (the declared contact geometry, the same the ground sees). Centre and half extents.
var _frame_box_centre := PackedFloat64Array([0.0, 0.0, 0.0])
var _frame_box_half := PackedFloat64Array([0.0, 0.0, 0.0])


## {ok, errors, plant}. `data` is a prepared multirotor document (physics/multirotor_data.gd), `rates_profile` an
## openrc-rates profile, `throttle_policy` FC.THROTTLE_ABSOLUTE or FC.THROTTLE_RATE.
## A36 R7-F02: admitted bound on one motor's decay rate times the fixed controller/kernel step.
const MOTOR_MAX_STEP_RATIO := 0.5


## Largest h*lambda over the rotors, lambda = (1/(R Kv^2) + 2 k_Q Omega_max) / J_rotor, h = 1/SAMPLE_HZ: the
## differential electrical-plus-aerodynamic shaft mode of an equal-duty same-spin pair (A36 R7 oracle). Common-mode
## bus coupling, friction and contact are additional; this bound is a necessary resolution check, not a qualification.
static func electric_motor_step_ratio(data: Dictionary) -> float:
	var pt: Dictionary = data.get("powertrain", {})
	var law: Dictionary = data.get("rotor_law", {})
	var kv: float = float(pt.get("kv_rad_s_per_v", NAN))
	var conductance: float = 1.0 / (float(pt.get("resistance_ohm", NAN)) * kv * kv)
	var aero: float = 2.0 * float(law.get("torque_coefficient_n_m_s2", NAN)) * float(law.get("max_speed_rad_s", NAN))
	var worst := 0.0
	for rotor: Dictionary in data.get("rotors", []):
		worst = maxf(worst, (conductance + aero) / float(rotor.get("inertia_kg_m2", NAN)) / float(FC.SAMPLE_HZ))
	return worst if is_finite(conductance) and is_finite(aero) else NAN


## A36 R7-F02: flight admission of an electric document's motor resolution. A 0.001 ohm motor (h*lambda = 11.85)
## passed the strict loader but failed its first arming tick; stock is 0.197. Empty when resolved or not electric.
## Component oracles may still create a plant from deliberately degenerate rotors; a flight may not.
static func motor_step_error(data: Dictionary) -> String:
	if str(data.get("powertrain", {}).get("law", "")) != ActuatorMap.LAW_ELECTRIC:
		return ""
	var ratio: float = electric_motor_step_ratio(data)
	if is_finite(ratio) and ratio <= MOTOR_MAX_STEP_RATIO:
		return ""
	return "motor response is too fast for the %d Hz step (h*lambda = %s > %s); qualify a slower motor model" \
		% [FC.SAMPLE_HZ, str(snappedf(ratio, 0.001)), str(MOTOR_MAX_STEP_RATIO)]


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
	var hover_speed: float = sqrt(float(data.get("mass_kg", 0.0)) * STANDARD_GRAVITY / (4.0 * k_t)) if k_t > 0.0 else NAN
	plant._rest_rotor_speed = REST_ROTOR_FRACTION * hover_speed if is_finite(hover_speed) and hover_speed > 0.0 else 0.0
	plant._hover_speed = hover_speed if is_finite(hover_speed) and hover_speed > 0.0 else 0.0
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
	plant._prepare_frame_box()
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
	# DR-19e: the turtle sample chooses motors by their hub side.
	var hubs: Array = []
	for rotor: Dictionary in data.rotors:
		hubs.append(PackedFloat64Array(rotor.hub_frd))
	plant.config.hubs = hubs
	# DR-19e: only the damped bridge can drive a motor backwards; elsewhere turtle mode commands nothing.
	plant.config.reverse_drive = plant._braking
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
	var yaw_inertia: float = float(data.inertia_kg_m2[2]) - (rotor_inertia if plant.electric else 0.0)
	plant.parked_one_piece_h_lambda = parked_stiffness(data, yaw_inertia) * PARKED_CHECK_DT
	# The fewest pieces that keep h·|λ| of the parked contact within the bound; more than the moving contact's
	# CONTACT_SUBSTEPS (or no estimate) means the quad is never treated as parked.
	var needed: float = ceilf(plant.parked_one_piece_h_lambda / PARKED_H_LAMBDA_LIMIT)
	if is_finite(needed) and needed <= float(CONTACT_SUBSTEPS):
		plant.parked_pieces = maxi(1, int(needed))
	else:
		plant.parked_pieces = CONTACT_SUBSTEPS
		plant._rest_rotor_speed = -1.0
	return {ok = true, errors = errors, plant = plant}


## Largest |λ| (1/s) of the parked contact's modes, a conservative single-axis estimate: heave, roll and pitch
## rocking (penalty springs and dampers, max(ω, c/I) bounds a damped pair's roots) and the regularized friction
## in translation and yaw (μ·N/FRICTION_CREEP per foot). Infinite for unusable data.
static func parked_stiffness(data: Dictionary, yaw_inertia: float) -> float:
	var contacts: Dictionary = data.contacts
	var feet: Array = contacts.feet_frd
	var mass := float(data.mass_kg)
	var inertia: PackedFloat64Array = data.inertia_kg_m2
	if feet.is_empty() or not (mass > 0.0) or not (inertia[0] > 0.0) or not (inertia[1] > 0.0) or not (yaw_inertia > 0.0):
		return INF
	var k := float(contacts.stiffness_n_per_m)
	var c := float(contacts.damping_n_s_per_m)
	var n := float(feet.size())
	var sum_x2 := 0.0
	var sum_y2 := 0.0
	for foot: PackedFloat64Array in feet:
		sum_x2 += foot[0] * foot[0]
		sum_y2 += foot[1] * foot[1]
	var friction_rate := float(contacts.friction) * STANDARD_GRAVITY / FRICTION_CREEP # per unit mass
	var rates := PackedFloat64Array([
		maxf(sqrt(n * k / mass), n * c / mass),
		maxf(sqrt(k * sum_y2 / inertia[0]), c * sum_y2 / inertia[0]),
		maxf(sqrt(k * sum_x2 / inertia[1]), c * sum_x2 / inertia[1]),
		friction_rate,
		friction_rate * mass * (sum_x2 + sum_y2) / n / yaw_inertia,
	])
	var worst := 0.0
	for rate: float in rates:
		worst = maxf(worst, rate) if is_finite(rate) else INF
	return worst


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
	vehicle.identity = {vehicle = "multirotor", law = law(), layout = layout(), rotor_density = Rotor.DENSITY_LAW, controller = FC.LAW,
		controller_identity = str(config.identity), allocator = Allocator.LAW, rates = str(config.rates.identity),
		bus = (BUS_DAMPED if _braking else ElectricBus.LAW) if electric else "ideal-supply", data = str(prepared.identity.get("data_sha256", "")),
		variant = str(prepared.identity.get("variant", "")), throttle_policy = int(config.throttle_policy),
		impacts = IMPACT_GRADED if graded_impacts and electric else IMPACT_STRICT}
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
		for i in 4:
			continuous[C_HEALTH + i] = 1.0
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
	# A36 R2-F01: rotor aerodynamics see the same stage density as the airframe (exactly 1 at the reference air).
	var sigma: float = density / Rotor.REFERENCE_DENSITY
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
			var loads: Dictionary = Rotor.loads(omega, float(rotor.spin), rotor.hub_frd, v_air, rates, omega_dot, _rotor_laws[i],
				sigma)
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
			# DR-19e: a turtle command is negative (reverse drive); only the damped bridge can drive in reverse.
			duty[i] = aux[FC.AUX_COMMAND + i] if _braking else maxf(aux[FC.AUX_COMMAND + i], 0.0)
			enabled[i] = 1
	var bus: Dictionary = {}
	if connected:
		bus = _bus(_ocv(_soc(continuous)), duty, back_emf, enabled, drive, continuous[C_CHARGE])
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
		var health: float = continuous[C_HEALTH + i]
		# Thrust follows the prop's health; its drag never falls below what a broken prop's hub and stubs keep, so a
		# driven motor with a broken prop cannot run away past the shaft-speed domain.
		var load: float = maxf(health, BROKEN_PROP_LOAD)
		var thrust: float = _k_t * motoring * motoring * health * sigma
		var torque: float = _k_q * motoring * motoring * load * sigma
		if omega < 0.0:
			# DR-19e: a prop spinning backwards (turtle mode) pushes the other way at a fraction of its efficiency; its
			# drag torque opposes the reversed rotation.
			thrust = -_k_t * REVERSE_PROP_EFFICIENCY * omega * omega * health * sigma
			torque = -_k_q * REVERSE_PROP_EFFICIENCY * omega * omega * load * sigma
		var rotor_fx: float = -_k_h * motoring * (v_air[0] + rates[1] * hz - rates[2] * hy) * load * sigma
		var rotor_fy: float = -_k_h * motoring * (v_air[1] + rates[2] * hx - rates[0] * hz) * load * sigma
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
func _bus(voc: float, duty: PackedFloat64Array, back_emf: PackedFloat64Array, enabled: PackedInt64Array, drive: bool,
		charge: float = 0.0) -> Dictionary:
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
		var acceptance: float = maxf(0.0, 3600.0 * float(prepared.battery.capacity_ah) - charge) / CHARGE_ACCEPTANCE_S
		if pack_current < -acceptance and duty_sum > 0.0:
			# Audit A06: the pack accepts no more charge; the floating bus sets the regenerative currents so that the
			# pack current is exactly -acceptance (the bus is linear in V: sum(d_i (d_i V - E_i)/R) + I_aux = -acceptance).
			v_bus = (emf_sum - auxiliary - acceptance) / duty_sum
			pack_current = auxiliary
			for i in 4:
				currents[i] = (duty[i] * v_bus - back_emf[i]) / resistance
				pack_current += duty[i] * currents[i]
			return {ok = v_bus > 0.0, v_bus = v_bus, i_motor = currents, i_pack = pack_current,
				p_terminal_w = v_bus * pack_current, p_pack_loss_w = (voc - v_bus) * pack_current, acceptance_limited = true}
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
	# DR-22/R1 scalar form of the M.* vector sequence: every value is computed by the same operations in the same
	# order and grouping as M.q_rotate, M.add, M.cross, M.dot, M.sub, M.scale and M.norm (bit-identical results,
	# checked against the vector form in test_mr_fast_paths), without the per-point temporary arrays.
	var q0: float = attitude[0]
	var q1: float = attitude[1]
	var q2: float = attitude[2]
	var q3: float = attitude[3]
	var i1: float = -q1 # M.q_conj
	var i2: float = -q2
	var i3: float = -q3
	var v0: float = velocity[0]
	var v1: float = velocity[1]
	var v2: float = velocity[2]
	var r0: float = rates[0]
	var r1: float = rates[1]
	var r2: float = rates[2]
	var fx: float = force[0]
	var fy: float = force[1]
	var fz: float = force[2]
	var mx: float = moment[0]
	var my: float = moment[1]
	var mz: float = moment[2]
	for point: PackedFloat64Array in _points:
		var p0: float = point[0]
		var p1: float = point[1]
		var p2: float = point[2]
		# offset = M.q_rotate(attitude, point)
		var tx: float = (q2 * p2 - q3 * p1) * 2.0
		var ty: float = (q3 * p0 - q1 * p2) * 2.0
		var tz: float = (q1 * p1 - q2 * p0) * 2.0
		var o0: float = (p0 + tx * q0) + (q2 * tz - q3 * ty)
		var o1: float = (p1 + ty * q0) + (q3 * tx - q1 * tz)
		var o2: float = (p2 + tz * q0) + (q1 * ty - q2 * tx)
		var north: float = body[RB.POS] + o0
		var east: float = body[RB.POS + 1] + o1
		var surface: PackedFloat64Array = _ground_at(north, east)
		var depth: float = body[RB.POS + 2] + o2 + surface[0]
		if depth <= 0.0:
			continue
		var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(surface[1], surface[2])
		var n0: float = normal[0]
		var n1: float = normal[1]
		var n2: float = normal[2]
		# v_world = M.q_rotate(attitude, M.add(velocity, M.cross(rates, point)))
		var a0: float = v0 + (r1 * p2 - r2 * p1)
		var a1: float = v1 + (r2 * p0 - r0 * p2)
		var a2: float = v2 + (r0 * p1 - r1 * p0)
		tx = (q2 * a2 - q3 * a1) * 2.0
		ty = (q3 * a0 - q1 * a2) * 2.0
		tz = (q1 * a1 - q2 * a0) * 2.0
		var w0: float = (a0 + tx * q0) + (q2 * tz - q3 * ty)
		var w1: float = (a1 + ty * q0) + (q3 * tx - q1 * tz)
		var w2: float = (a2 + tz * q0) + (q1 * ty - q2 * tx)
		var along: float = w0 * n0 + w1 * n1 + w2 * n2
		var load: float = maxf(0.0, stiffness * depth * -n2 - damping * along)
		if load <= 0.0:
			continue
		# tangential = M.sub(v_world, M.scale(normal, along)); slip = M.norm(tangential)
		var g0: float = w0 - n0 * along
		var g1: float = w1 - n1 * along
		var g2: float = w2 - n2 * along
		var slip: float = sqrt(g0 * g0 + g1 * g1 + g2 * g2)
		var k: float = -friction * load / (slip + FRICTION_CREEP)
		# f_world = M.add(M.scale(normal, load), M.scale(tangential, k)); f_body = M.q_rotate(q_conj, f_world)
		var c0: float = n0 * load + g0 * k
		var c1: float = n1 * load + g1 * k
		var c2: float = n2 * load + g2 * k
		tx = (i2 * c2 - i3 * c1) * 2.0
		ty = (i3 * c0 - i1 * c2) * 2.0
		tz = (i1 * c1 - i2 * c0) * 2.0
		var b0: float = (c0 + tx * q0) + (i2 * tz - i3 * ty)
		var b1: float = (c1 + ty * q0) + (i3 * tx - i1 * tz)
		var b2: float = (c2 + tz * q0) + (i1 * ty - i2 * tx)
		fx = fx + b0
		fy = fy + b1
		fz = fz + b2
		mx = mx + (p1 * b2 - p2 * b1)
		my = my + (p2 * b0 - p0 * b2)
		mz = mz + (p0 * b1 - p1 * b0)
	return {force = M.v3(fx, fy, fz), moment = M.v3(mx, my, mz)}


## Pure endpoint transition: terminal adjudication on the accepted candidate. A crash or an exhausted pack sets the
## motor lifecycle, latches the drive cut and reports one event; the sampled commands of the interval stay as held.
func endpoint_transition(_previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
	var modes: PackedInt64Array = candidate.modes
	var continuous: PackedFloat64Array = candidate.continuous
	var events: Array = []
	var terminal := false
	# A crash is adjudicated until one has happened, also for a quad falling on an exhausted pack.
	if modes[FC.MODE_MOTOR] != FC.MOTOR_CRASHED:
		var reason := ""
		if graded_impacts and electric:
			var graded: Dictionary = _graded_impacts(_previous.body, candidate.body, continuous, float(context.time_s))
			reason = graded.reason
			candidate.body = graded.body
			continuous = graded.continuous
			events.append_array(graded.events)
		else:
			reason = crash_reason(_previous.body, candidate.body, continuous)
		if reason.is_empty() and water_contact.is_valid() \
				and bool(water_contact.call(candidate.body, float(context.time_s))):
			reason = WATER_CRASH_REASON
		if not reason.is_empty():
			terminal = true
			modes[FC.MODE_MOTOR] = FC.MOTOR_CRASHED
			modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_TERMINAL
			events.append({type = "crash", time_s = float(context.time_s), reason = reason})
			if reason != "Obstacle strike" and reason != WATER_CRASH_REASON:
				candidate.body = _settle_impact(candidate.body)
		elif electric and continuous[C_CHARGE] <= 0.0 and modes[FC.MODE_MOTOR] != FC.MOTOR_DEPLETED:
			modes[FC.MODE_MOTOR] = FC.MOTOR_DEPLETED
			modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_TERMINAL
			events.append({type = "pack_depleted", time_s = float(context.time_s)})
			terminal = true
		if electric and terminal:
			continuous[C_CUT_LATCH] = 1.0
	elif graded_impacts and electric and obstacle.is_valid():
		# CR-AUD-20: the crash is adjudicated once, but the wreck stays a solid: later ticks keep the frame's obstacle
		# response (push-out and bounded bounce), without new events, crash or prop wear.
		var aftermath := {reason = "", body = candidate.body.duplicate(), continuous = continuous.duplicate(), events = []}
		_graded_frame_obstacle(_previous.body, aftermath, float(context.time_s), true)
		candidate.body = aftermath.body
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


## CR-AUD-20: the crash aftermath against an obstacle (world `normal`, outward; the frame `depth` inside it): pushed out
## along the normal, the closing velocity removed, the tangential velocity and the body rates kept by the declared
## CRASH_*_KEEP fractions, as _settle_impact does on the terrain. Presentation aftermath, not a restitution model.
func _settle_on(body: PackedFloat64Array, normal: PackedFloat64Array, depth: float) -> PackedFloat64Array:
	var settled: PackedFloat64Array = body.duplicate()
	var attitude := RB._att(body)
	var v_world: PackedFloat64Array = M.q_rotate(attitude, RB._slice3(body, RB.VEL))
	var along: float = M.dot(v_world, normal)
	var tangential: PackedFloat64Array = M.scale(M.sub(v_world, M.scale(normal, along)), CRASH_TANGENT_KEEP)
	var v_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude), M.add(tangential, M.scale(normal, maxf(along, 0.0))))
	for k in 3:
		settled[RB.POS + k] = body[RB.POS + k] + normal[k] * maxf(depth, 0.0)
		settled[RB.VEL + k] = v_body[k]
		settled[RB.RATE + k] = body[RB.RATE + k] * CRASH_RATE_KEEP
	return settled


## Contact substeps for this tick: the stiff pad contact is integrated in CONTACT_SUBSTEPS pieces while the CG is
## within CONTACT_SUBSTEP_HEIGHT of the terrain, unless the quad rests there (still, rotors below lift): a resting
## quad takes `parked_pieces`, the fewest that keep its stiffest contact mode within the RK4 bound (the static
## solution on the flat pad does not depend on the step); free flight keeps one piece (DR-18/R1, R2).
func substeps(body: PackedFloat64Array, continuous: PackedFloat64Array, _t: float) -> int:
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	var height: float = -body[RB.POS + 2] - under[0]
	if graded_impacts:
		# DR-19d: a fast approach takes pieces short enough that no RK4 stage overshoots deep into the stiff pad springs
		# (at 12.5 m/s four pieces let one stage sink 13 mm and kicked a flat landing into a 136 rad/s pitch).
		var attitude := RB._att(body)
		var descent: float = M.q_rotate(attitude, M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2]))[2]
		var travel: float = descent * PARKED_CHECK_DT
		# Audit 2026-11-17: only the tick in which a contact point can reach the ground needs the fine pieces (before it
		# the quad is in free flight); refining every tick below 0.25 m cost up to 11 ms per tick on a 12 m/s dive.
		if descent > 0.0 and height < CONTACT_SUBSTEP_HEIGHT + travel \
				and _lowest_point_height(attitude, height) < travel + IMPACT_REFINE_MARGIN_M:
			var fine: int = int(ceilf(travel / IMPACT_PIECE_TRAVEL_M))
			if fine > CONTACT_SUBSTEPS:
				return mini(fine, IMPACT_MAX_PIECES)
	if not (height < CONTACT_SUBSTEP_HEIGHT):
		return 1
	return CONTACT_SUBSTEPS if contact_is_moving(body, continuous) else parked_pieces


## Height (m) above the terrain under the CG of the lowest foot or hull point at `attitude`, for a CG `height` above
## it (the local slope is covered by IMPACT_REFINE_MARGIN_M).
func _lowest_point_height(attitude: PackedFloat64Array, height: float) -> float:
	var deepest := 0.0
	for point: PackedFloat64Array in _points:
		deepest = maxf(deepest, M.q_rotate(attitude, point)[2])
	return height - deepest


## Whether a contact near the terrain needs the refined pieces (see substeps): CG speed, body rate or a turning
## rotor. Non-finite values refine.
func contact_is_moving(body: PackedFloat64Array, continuous: PackedFloat64Array) -> bool:
	if _rest_rotor_speed < 0.0:
		return true
	var speed2: float = body[RB.VEL] * body[RB.VEL] + body[RB.VEL + 1] * body[RB.VEL + 1] + body[RB.VEL + 2] * body[RB.VEL + 2]
	var rate2: float = body[RB.RATE] * body[RB.RATE] + body[RB.RATE + 1] * body[RB.RATE + 1] \
		+ body[RB.RATE + 2] * body[RB.RATE + 2]
	if not (speed2 <= REST_SPEED_MPS * REST_SPEED_MPS) or not (rate2 <= REST_RATE_RAD_S * REST_RATE_RAD_S):
		return true
	for i in mini(4, continuous.size()):
		if not (absf(continuous[i]) <= _rest_rotor_speed):
			return true
	return false


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
	# Spinning disc (audit A07): the hub centre, the rim point lowest in the world and, within ROTOR_RIM_MARGIN of the
	# terrain, a ring of rim points whose first point is the worst rim direction of the plane through the hub's local
	# slopes. On planar terrain the deepest rim penetration is hub_depth + r·|l − a(a·l)|, l = (slope_n, slope_e, 1) and
	# a the disc normal, so an uphill rim point is found, not only the world-lowest one. A strike is always a real
	# terrain sample below the surface. A witness search, not a clearance proof: a crest narrower than the ring
	# spacing can still pass between samples (no curvature bound exists for the composed ground callable).
	var axis: PackedFloat64Array = M.q_rotate(attitude, M.v3(0.0, 0.0, -1.0))
	var lowest: PackedFloat64Array = M.sub(M.v3(0.0, 0.0, 1.0), M.scale(axis, axis[2]))
	var lowest_norm: float = M.norm(lowest)
	var position: PackedFloat64Array = M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2])
	var strike_speed: float = prepared.contacts.rotor_strike_speed_rad_s
	for i in 4:
		if continuous[i] > strike_speed and _disc_in_ground(i, position, attitude, axis, lowest, lowest_norm):
			return "Propeller strike"
	return ""


## Whether rotor `i`'s disc reaches the terrain (audit A07 search: hub, world-lowest rim point, and the ring of rim
## points within ROTOR_RIM_MARGIN; every hit is a real terrain sample below the surface).
func _disc_in_ground(i: int, position: PackedFloat64Array, attitude: PackedFloat64Array, axis: PackedFloat64Array,
		lowest: PackedFloat64Array, lowest_norm: float) -> bool:
	return not _disc_ground_hit(i, position, attitude, axis, lowest, lowest_norm).is_empty()


## Where rotor `i`'s disc reaches the terrain: the world unit direction from its hub to the rim point found below the
## surface (the world-lowest direction for a buried hub), or empty when the disc is clear. Same search as A07.
func _disc_ground_hit(i: int, position: PackedFloat64Array, attitude: PackedFloat64Array, axis: PackedFloat64Array,
		lowest: PackedFloat64Array, lowest_norm: float) -> PackedFloat64Array:
	var rotor: Dictionary = prepared.rotors[i]
	var radius: float = 0.5 * float(rotor.diameter_m)
	var hub: PackedFloat64Array = M.add(position, M.q_rotate(attitude, rotor.hub_frd))
	var under_hub: PackedFloat64Array = _ground_at(hub[0], hub[1])
	var hub_depth: float = hub[2] + under_hub[0]
	var down_rim: PackedFloat64Array = M.scale(lowest, 1.0 / lowest_norm) if lowest_norm > 1.0e-9 \
		else M.q_rotate(attitude, M.v3(1.0, 0.0, 0.0))
	if hub_depth > 0.0:
		return down_rim
	if lowest_norm > 1.0e-9 and _rim_depth(hub, down_rim, radius) > 0.0:
		return down_rim
	var up: PackedFloat64Array = M.v3(under_hub[1], under_hub[2], 1.0)
	var worst: PackedFloat64Array = M.sub(up, M.scale(axis, M.dot(axis, up)))
	var worst_norm: float = M.norm(worst)
	if hub_depth + radius * worst_norm <= -ROTOR_RIM_MARGIN:
		return PackedFloat64Array()
	var u: PackedFloat64Array = M.q_rotate(attitude, M.v3(1.0, 0.0, 0.0))
	if worst_norm > 1.0e-9:
		u = M.scale(worst, 1.0 / worst_norm)
	var v: PackedFloat64Array = M.cross(axis, u)
	for k in ROTOR_RIM_COS.size():
		var direction: PackedFloat64Array = M.add(M.scale(u, float(ROTOR_RIM_COS[k])), M.scale(v, float(ROTOR_RIM_SIN[k])))
		if _rim_depth(hub, direction, radius) > 0.0:
			return direction
	return PackedFloat64Array()


## DR-19c (docs/plans/drone-racing.md §17.2): impact laws. The strict law ends the flight at any hard contact, prop
## strike or obstacle touch (crash_reason). The graded law is a declared, deterministic gameplay law, not measured
## damage data: severity is the closing speed along the contact normal at the contact point; the frame and the props
## are told apart; most contacts bounce or wear the props and the flight goes on, and only the hardest impacts end it.
const IMPACT_STRICT := "multirotor-strict-impact-v1"
## v2 (DR-19e §19.4): the frame is a box and each spinning prop a thin disc (v1: spheres of the hub and prop radii,
## which reached 7.7 cm above and below the 4.9 cm body and 6.5 cm above and below each prop disc).
## v3 (DR-19f §20): grazes and material. Coulomb friction on obstacle and touchdown impulses; props chip only when a
## frame hit lands at their disc; prop wear and breaks follow the material and the blade's bite; an obstacle prop strike
## brakes and kicks like a ground strike; sliding contacts raise scrape events.
const IMPACT_GRADED := "multirotor-graded-impact-v3"
## A ground touchdown faster than this multiple of contacts.crash_speed ends the flight ("Hard impact").
const HARD_IMPACT_FACTOR := 3.0
## Prop health lost per accepted tick while a spinning prop is in contact, at the hover shaft speed (scales with speed).
const PROP_WEAR_PER_TICK := 0.2
## Below this health a prop is broken (health 0: no thrust, torque or rotor drag).
const PROP_BROKEN_HEALTH := 0.3
## Health a spinning prop keeps when a hard landing or a frame bounce chips it.
const PROP_CHIP_FACTOR := 0.85
## DR-19d (§18): a touchdown faster than this (m/s along the normal) is resolved as one impulse at the contact patch
## (the centroid of the touching points) instead of being left to the stiff pad springs, which sank the quad by up to
## 28 mm and threw it into a spin on a flat 12 m/s landing. Restitution of that impulse.
const TOUCHDOWN_IMPULSE_SPEED_MPS := 3.0
## DR-19d: graded law only, the longest travel (m) of one RK4 piece toward the ground, and the piece cap per tick.
const IMPACT_PIECE_TRAVEL_M := 0.004
const IMPACT_MAX_PIECES := 16
## Slack (m) on the lowest point's height when deciding that a contact can begin this tick (slopes, rounding).
const IMPACT_REFINE_MARGIN_M := 0.03
const TOUCHDOWN_RESTITUTION := 0.15
## DR-19d: a spinning prop that digs into the ground loses this share of its shaft speed per tick, and the ground's
## reaction on the blade (the rotor's lost angular momentum over the prop radius) kicks the quad at the hub: the
## prop "walks" and flips the quad, as real prop strikes do.
const PROP_STRIKE_BRAKE := 0.5
## DR-19e: thrust and drag-torque share of a prop driven backwards (turtle mode); a pitched blade run in reverse is
## far less efficient (declared estimate). A reverse-spinning prop is exempt from the strike laws (wear, brake, kick):
## those are tuned for brief forward strikes, and the per-tick strike brake would stall any crash flip on grass (audit
## 2026-11-17; a declared simplification, so turtle mode never damages props).
const REVERSE_PROP_EFFICIENCY := 0.35
## Share of the intact prop's aerodynamic torque and rotor drag a broken prop still has (hub and blade stubs).
const BROKEN_PROP_LOAD := 0.3
## A frame contact closing slower than this (m/s) is resting or scraping: no chipped props and no impact event.
const IMPACT_EVENT_SPEED_MPS := 0.5
## A spinning prop that strikes an obstacle faster than this (m/s along the normal) breaks.
const PROP_BREAK_SPEED_MPS := 6.0
## Frame impact speed (m/s along the normal) that ends the flight, by the obstacle's response class (declared
## gameplay estimates, ordered by how much the obstacle gives way): foliage and people 12, a foam parked airplane 11,
## frangible stakes, lamps, bales and gate fabric 10, and buildings, trunks, benches or an unknown class 8.
const FRAME_TERMINAL_SPEED_MPS := {"soft_foliage_impulse": 12.0, "light_airframe_impulse": 11.0,
	"frangible_impulse": 10.0, "gate_frame": 10.0, "hard_terminal": 8.0}
const FRAME_TERMINAL_DEFAULT_MPS := 8.0
## Bounce classes of the shared scenery response (restitution 0.35 for foliage, 0.25 for a parked airframe, 0.20
## otherwise; the touchdown uses the 0.20 class, the nearest shared value to TOUCHDOWN_RESTITUTION).
const FOLIAGE_RESPONSE := "soft_foliage_impulse"
const AIRFRAME_RESPONSE := "light_airframe_impulse"
const SOLID_RESPONSE := "frangible_impulse"
const TOUCHDOWN_RESPONSE := "frangible_impulse"
## Step (m) of the central differences that give an obstacle's surface normal from its clearance field.
const OBSTACLE_NORMAL_STEP_M := 0.005
## DR-19e: half thickness (m) of a spinning prop disc (blade pitch envelope; the model's blades span 5 mm).
const PROP_DISC_HALF_THICKNESS_M := 0.003
const WATER_CRASH_REASON := "Water contact"
## Normal component (body axes) below which a box contact point blends from an edge to the face centre, so a face that
## is nearly parallel to the surface does not jump between its edges.
const BOX_EDGE_BLEND := 0.05
## DR-19f (§20): Coulomb friction coefficient of a frame contact by obstacle class (declared estimates: carbon and
## plastic on wood, metal, fabric and leaves). Terrain uses the data's contacts.friction.
const OBSTACLE_FRICTION := {"soft_foliage_impulse": 0.3, "light_airframe_impulse": 0.4, "frangible_impulse": 0.5,
	"gate_frame": 0.4, "hard_terminal": 0.5}
const OBSTACLE_FRICTION_DEFAULT := 0.5
## A frame hit chips only the spinning props whose disc reaches within this margin (m) of the contact point, and only
## above PROP_CHIP_SPEED_MPS along the normal: a scrape of the battery, the belly or a far corner leaves them alone. A
## ground touchdown chips from contacts.crash_speed.
const PROP_CHIP_REACH_M := 0.02
const PROP_CHIP_SPEED_MPS := 3.0
## How hard a surface is on a spinning blade (wear share and break speed): leaves 0.15, gate fabric 0.4, terrain (grass
## and soil) 0.5, a foam airframe 0.5, stakes, lamps and bales 0.6, buildings, trunks and benches 1. A prop breaks on an
## obstacle above PROP_BREAK_SPEED_MPS / sqrt(material).
const PROP_MATERIAL := {"soft_foliage_impulse": 0.15, "gate_frame": 0.4, "ground": 0.5, "light_airframe_impulse": 0.5,
	"frangible_impulse": 0.6, "hard_terminal": 1.0}
const PROP_MATERIAL_DEFAULT := 1.0
## Blade bite (m into the surface) of a full-strength strike; a lighter tip brush counts in proportion, at least
## PROP_MIN_BITE of it (wear and the strike brake).
const PROP_FULL_BITE_M := 0.015
const PROP_MIN_BITE := 0.25
## Sliding speed (m/s) of a touching frame or contact point above which a scrape event is raised (presentation only).
## A sustained ground skid reports once per SCRAPE_EVENT_PERIOD_S of simulation time (a frame graze on its bounce ticks).
const SCRAPE_EVENT_SPEED_MPS := 2.0
const SCRAPE_EVENT_PERIOD_S := 0.1


## The frame box from the hubs (x, y) and the hull and feet heights (z).
func _prepare_frame_box() -> void:
	var low := PackedFloat64Array([INF, INF, INF])
	var high := PackedFloat64Array([-INF, -INF, -INF])
	for rotor: Dictionary in prepared.rotors:
		for k in 2:
			low[k] = minf(low[k], float(rotor.hub_frd[k]))
			high[k] = maxf(high[k], float(rotor.hub_frd[k]))
	var contacts: Dictionary = prepared.get("contacts", {})
	for key: String in ["hull_frd", "feet_frd"]:
		for point in contacts.get(key, []):
			low[2] = minf(low[2], float(point[2]))
			high[2] = maxf(high[2], float(point[2]))
	for k in 3:
		if not (is_finite(low[k]) and is_finite(high[k])):
			low[k] = 0.0
			high[k] = 0.0
		_frame_box_centre[k] = 0.5 * (low[k] + high[k])
		_frame_box_half[k] = 0.5 * (high[k] - low[k])


## Support (m) of the frame box along the body-axes unit normal `nb` (its extent from the box centre toward -nb), and
## the body point (FRD from the CG) that touches a surface with that outward normal.
func _box_support(nb: PackedFloat64Array) -> Dictionary:
	var extent := 0.0
	var point := _frame_box_centre.duplicate()
	for k in 3:
		extent += _frame_box_half[k] * absf(nb[k])
		point[k] -= _frame_box_half[k] * clampf(nb[k] / BOX_EDGE_BLEND, -1.0, 1.0)
	return {extent = extent, point = point}


## Support (m) of a thin prop disc (radius, unit axis, half thickness) along the body-axes unit normal `nb`, and the
## touching point relative to the hub.
static func _disc_support(nb: PackedFloat64Array, axis: PackedFloat64Array, radius: float) -> Dictionary:
	var along := M.dot(nb, axis)
	var in_plane := M.sub(nb, M.scale(axis, along))
	var spread := M.norm(in_plane)
	var extent := radius * spread + PROP_DISC_HALF_THICKNESS_M * absf(along)
	var point := M.scale(axis, -PROP_DISC_HALF_THICKNESS_M * signf(along))
	if spread > 1.0e-9:
		point = M.sub(point, M.scale(in_plane, radius / spread))
	return {extent = extent, point = point}


## The graded law at an accepted endpoint: {reason ("" unless terminal), body (bounced and pushed out of obstacles),
## continuous (prop health), events (impact and prop_damage)}. Pure: the same frames give the same outcome.
func _graded_impacts(previous_body: PackedFloat64Array, body: PackedFloat64Array, continuous: PackedFloat64Array,
		t: float) -> Dictionary:
	var out := {reason = "", body = body.duplicate(), continuous = continuous.duplicate(), events = []}
	if obstacle.is_valid():
		_graded_frame_obstacle(previous_body, out, t)
		if not str(out.reason).is_empty():
			return out
		_graded_prop_obstacles(out, t)
	_graded_ground(previous_body, out, t)
	return out


## Frame (the box over the hubs, hull top and feet) against an obstacle: the endpoint, else the tick's midpoint (a thin
## solid crossed within the tick). The obstacle is judged by its clearance and normal at the box centre (exact for a
## wall, roof or bar wider than the box; never wider than a sphere around the box for a thinner one). DR-19f: the bounce
## carries Coulomb friction (a graze drags and spins the quad), only a hit at a prop's disc chips it, and a sliding
## contact raises a scrape event.
## CR-AUD-20: a terminal strike also leaves the solid at its contact with the same bounded response (the crash is a
## classification, not a pass-through); `aftermath` (after the crash) applies the response only: no events or chips.
func _graded_frame_obstacle(previous_body: PackedFloat64Array, out: Dictionary, t: float, aftermath := false) -> void:
	var body: PackedFloat64Array = out.body
	var attitude := RB._att(body)
	var offset := M.q_rotate(attitude, _frame_box_centre)
	for fraction: float in [1.0, 0.5]:
		var centre := PackedFloat64Array()
		for k in 3:
			centre.append(lerpf(previous_body[RB.POS + k], body[RB.POS + k], fraction) + offset[k])
		var clearance: Variant = obstacle.call(centre[0], centre[1], centre[2])
		if typeof(clearance) != TYPE_FLOAT or float(clearance) > M.norm(_frame_box_half):
			continue
		var normal := _obstacle_normal(centre)
		var support := _box_support(M.q_rotate(M.q_conj(attitude), normal))
		var depth: float = float(support.extent) - float(clearance)
		if not (depth >= 0.0 and is_finite(depth)):
			continue
		var kind := str(obstacle_class.call(centre[0], centre[1], centre[2])) if obstacle_class.is_valid() else ""
		var contact_body: PackedFloat64Array = support.point
		var speed := _closing_speed(body, contact_body, normal)
		var terminal: bool = not aftermath and speed >= float(FRAME_TERMINAL_SPEED_MPS.get(kind, FRAME_TERMINAL_DEFAULT_MPS))
		var point_ned := M.sub(centre, M.scale(normal, float(support.extent)))
		var slip := _slip_speed(body, contact_body, normal)
		if aftermath:
			# The wreck rests on or slides off the solid with the same declared aftermath law as the terrain
			# (_settle_impact): out of the solid, no inward normal velocity, kept fractions of tangential speed and rates.
			# Endpoint only, so a resting wreck is not pulled back to the tick midpoint.
			if fraction == 1.0:
				out.body = _settle_on(body, normal, depth)
			return
		# Survivable: back to this contact position, out of the solid, then a bounded bounce with friction.
		var moved := body.duplicate()
		for k in 3:
			moved[RB.POS + k] = centre[k] - offset[k] + normal[k] * depth
		out.body = _bounce(moved, contact_body, normal, speed, kind if kind in [FOLIAGE_RESPONSE, AIRFRAME_RESPONSE] else SOLID_RESPONSE,
			float(OBSTACLE_FRICTION.get(kind, OBSTACLE_FRICTION_DEFAULT)))
		if terminal:
			out.reason = "Obstacle strike"
			return
		var surface := kind if not kind.is_empty() else "obstacle"
		if speed > PROP_CHIP_SPEED_MPS:
			_chip_near(out, contact_body, t, "frame")
		if speed > IMPACT_EVENT_SPEED_MPS:
			out.events.append({type = "impact", time_s = t, surface = surface, part = "frame", normal_speed_mps = speed,
				slip_speed_mps = slip, point_ned = point_ned})
		if slip > SCRAPE_EVENT_SPEED_MPS and speed > 0.0:
			out.events.append({type = "scrape", time_s = t, surface = surface, part = "frame", slip_speed_mps = slip,
				point_ned = point_ned})
		return


## Spinning prop discs (thin discs of the prop radius at their hubs, judged by the clearance and normal at the hub)
## against obstacles, all judged on the same pose. DR-19f: each touching prop wears by the obstacle's material and the
## blade's bite, or breaks above PROP_BREAK_SPEED_MPS / sqrt(material); the blade is braked and kicks the airframe as
## on the ground; then one push-out and one bounce at the deepest contact.
func _graded_prop_obstacles(out: Dictionary, t: float) -> void:
	var strike_speed: float = prepared.contacts.rotor_strike_speed_rad_s
	var body: PackedFloat64Array = out.body
	var attitude := RB._att(body)
	var deepest := {}
	for i in 4:
		if out.continuous[i] <= strike_speed or out.continuous[C_HEALTH + i] <= 0.0: # forward spin only (see REVERSE_PROP_EFFICIENCY)
			continue
		var rotor: Dictionary = prepared.rotors[i]
		var radius: float = 0.5 * float(rotor.diameter_m)
		var hub := M.add(M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]), M.q_rotate(attitude, rotor.hub_frd))
		var clearance: Variant = obstacle.call(hub[0], hub[1], hub[2])
		# The hub clearance is a cheap gate: no obstacle farther than the disc's rim (and half thickness) can touch it.
		if typeof(clearance) != TYPE_FLOAT or float(clearance) > radius + PROP_DISC_HALF_THICKNESS_M:
			continue
		var normal: PackedFloat64Array
		var depth: float
		var kind: String
		var support_point: PackedFloat64Array
		if prop_disc_contact.is_valid():
			# CR-AUD-25: the finite disc against each obstacle, with that obstacle's own witness, normal and class.
			var contact: Variant = prop_disc_contact.call(hub, M.q_rotate(attitude, M.v3(0.0, 0.0, -1.0)), radius,
				PROP_DISC_HALF_THICKNESS_M)
			if typeof(contact) != TYPE_DICTIONARY or (contact as Dictionary).is_empty():
				continue
			normal = contact.normal
			depth = float(contact.penetration_m)
			kind = str(contact.kind)
			var witness_body: PackedFloat64Array = M.q_rotate(M.q_conj(attitude),
				M.sub(contact.point_ned, M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2])))
			support_point = M.sub(witness_body, rotor.hub_frd)
		else:
			if float(clearance) > radius:
				continue
			normal = _obstacle_normal(hub)
			var support := _disc_support(M.q_rotate(M.q_conj(attitude), normal), M.v3(0.0, 0.0, -1.0), radius) # the admitted thrust axis
			depth = float(support.extent) - float(clearance)
			kind = str(obstacle_class.call(hub[0], hub[1], hub[2])) if obstacle_class.is_valid() else ""
			support_point = support.point
		if not (depth >= 0.0 and is_finite(depth)):
			continue
		var material := float(PROP_MATERIAL.get(kind, PROP_MATERIAL_DEFAULT))
		var contact_body := M.add(rotor.hub_frd, support_point)
		var speed := _closing_speed(body, contact_body, normal)
		if speed > PROP_BREAK_SPEED_MPS / sqrt(material):
			_set_health(out, i, 0.0, t, "obstacle")
		else:
			_wear(out, i, t, "obstacle", material, depth)
		# The blade's in-plane direction from the hub to the contact (none for a face-on touch of the disc).
		var rim := M.v3(support_point[0], support_point[1], 0.0)
		var rim_norm := M.norm(rim)
		if rim_norm > 1.0e-9:
			_prop_strike_kick(out, i, M.q_rotate(attitude, M.scale(rim, 1.0 / rim_norm)), _bite(depth))
		if deepest.is_empty() or depth > float(deepest.depth):
			deepest = {depth = depth, normal = normal, contact = contact_body}
	if deepest.is_empty():
		return
	var moved: PackedFloat64Array = out.body.duplicate()
	for k in 3:
		moved[RB.POS + k] += deepest.normal[k] * maxf(0.0, float(deepest.depth))
	out.body = _bounce(moved, deepest.contact, deepest.normal, _closing_speed(moved, deepest.contact, deepest.normal),
		SOLID_RESPONSE)


## Terrain: a new touchdown of a foot or hull point (severity: the faster of its arrival and endpoint closing speeds)
## is terminal above HARD_IMPACT_FACTOR × crash_speed and a hard landing (chipped props) above crash_speed; every
## spinning prop disc in the ground wears.
func _graded_ground(previous_body: PackedFloat64Array, out: Dictionary, t: float) -> void:
	var body: PackedFloat64Array = out.body
	var under: PackedFloat64Array = _ground_at(body[RB.POS], body[RB.POS + 1])
	if -body[RB.POS + 2] - under[0] > CONTACT_REACH:
		return
	var attitude := RB._att(body)
	var previous_attitude := RB._att(previous_body)
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var previous_velocity: PackedFloat64Array = M.v3(previous_body[RB.VEL], previous_body[RB.VEL + 1], previous_body[RB.VEL + 2])
	var previous_rates: PackedFloat64Array = M.v3(previous_body[RB.RATE], previous_body[RB.RATE + 1], previous_body[RB.RATE + 2])
	var crash_speed: float = prepared.contacts.crash_speed_mps
	var hardest := 0.0
	var hardest_point := PackedFloat64Array()
	var patch := M.v3(0.0, 0.0, 0.0)
	var patch_weight := 0.0
	var patch_normal := M.v3(0.0, 0.0, -1.0)
	var deepest := 0.0
	var slide_speed := 0.0
	var slide_point := PackedFloat64Array()
	for point: PackedFloat64Array in _points:
		var offset: PackedFloat64Array = M.q_rotate(attitude, point)
		var surface: PackedFloat64Array = _ground_at(body[RB.POS] + offset[0], body[RB.POS + 1] + offset[1])
		if body[RB.POS + 2] + offset[2] + surface[0] <= 0.0:
			continue
		var previous_offset: PackedFloat64Array = M.q_rotate(previous_attitude, point)
		var previous_surface: PackedFloat64Array = _ground_at(previous_body[RB.POS] + previous_offset[0],
			previous_body[RB.POS + 1] + previous_offset[1])
		var normal: PackedFloat64Array = Terrain.normal_from_up_slopes(surface[1], surface[2])
		if previous_body[RB.POS + 2] + previous_offset[2] + previous_surface[0] > 0.0:
			# Already touching: sliding, not a new touchdown (DR-19f: a fast skid raises a scrape event).
			var skid := _slip_speed(body, point, normal)
			if skid > slide_speed:
				slide_speed = skid
				slide_point = point
			continue
		var v_world: PackedFloat64Array = M.q_rotate(attitude, M.add(velocity, M.cross(rates, point)))
		var v_before: PackedFloat64Array = M.q_rotate(previous_attitude, M.add(previous_velocity, M.cross(previous_rates, point)))
		var speed: float = maxf(-M.dot(v_world, normal), -M.dot(v_before, normal))
		if speed > hardest:
			hardest = speed
			hardest_point = point
		var depth: float = body[RB.POS + 2] + offset[2] + surface[0]
		patch = M.add(patch, M.scale(point, depth))
		patch_weight += depth
		if depth > deepest:
			deepest = depth
			patch_normal = normal
	if hardest > HARD_IMPACT_FACTOR * crash_speed:
		out.reason = "Hard impact"
		return
	if slide_speed > SCRAPE_EVENT_SPEED_MPS \
			and floori(t / SCRAPE_EVENT_PERIOD_S) != floori((t - PARKED_CHECK_DT) / SCRAPE_EVENT_PERIOD_S):
		out.events.append({type = "scrape", time_s = t, surface = "ground", part = "frame", slip_speed_mps = slide_speed,
			point_ned = M.add(M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]), M.q_rotate(attitude, slide_point))})
	if hardest > crash_speed:
		_chip_near(out, hardest_point, t, "ground")
		out.events.append({type = "impact", time_s = t, surface = "ground", part = "frame", normal_speed_mps = hardest,
			point_ned = M.add(M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]), M.q_rotate(attitude, hardest_point))})
	if hardest > TOUCHDOWN_IMPULSE_SPEED_MPS and patch_weight > 0.0:
		# The patch's closing speed at the endpoint (what the springs have not yet stopped), resolved at once; then
		# lifted along the normal so the deepest new contact sits on the surface.
		var centroid: PackedFloat64Array = M.scale(patch, 1.0 / patch_weight)
		var closing := _closing_speed(body, centroid, patch_normal)
		var lifted := body.duplicate()
		for k in 3:
			lifted[RB.POS + k] += patch_normal[k] * deepest * -patch_normal[2]
		out.body = _bounce(lifted, centroid, patch_normal, closing, TOUCHDOWN_RESPONSE, float(prepared.contacts.friction)) \
			if closing > 0.0 else lifted
		body = out.body
		attitude = RB._att(body)
	var axis: PackedFloat64Array = M.q_rotate(attitude, M.v3(0.0, 0.0, -1.0))
	var lowest: PackedFloat64Array = M.sub(M.v3(0.0, 0.0, 1.0), M.scale(axis, axis[2]))
	var position: PackedFloat64Array = M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2])
	var strike_speed: float = prepared.contacts.rotor_strike_speed_rad_s
	for i in 4:
		if out.continuous[i] <= strike_speed or out.continuous[C_HEALTH + i] <= 0.0: # forward spin only (see REVERSE_PROP_EFFICIENCY)
			continue
		var hit := _disc_ground_hit(i, position, attitude, axis, lowest, M.norm(lowest))
		if hit.is_empty():
			continue
		var hub: PackedFloat64Array = M.add(position, M.q_rotate(attitude, prepared.rotors[i].hub_frd))
		var bite := maxf(0.0, _rim_depth(hub, hit, 0.5 * float(prepared.rotors[i].diameter_m)))
		_wear(out, i, t, "ground", float(PROP_MATERIAL.ground), bite)
		_prop_strike_kick(out, i, hit, _bite(bite))


## DR-19d: a spinning prop digging into the ground. The ground stops the blade (the shaft loses PROP_STRIKE_BRAKE of its
## speed this tick) and pushes back on it: an impulse I_r·Δω / r against the blade tip's motion at the contact, applied
## at the hub (its rim lever cancels the rotor's own momentum change). Bounded by the rotor's lost momentum; energy only
## leaves the system (the rotor's lost kinetic energy far exceeds what the kick gives the airframe). DR-19f: a lighter
## bite (`engagement` in [PROP_MIN_BITE, 1]) brakes and kicks in proportion; obstacles strike the same way.
## CR-AUD-21: the kick may not add energy. The coupled body-and-shaft kinetic energy after braking and kicking is
## compared with the energy before; when the airframe's own motion along the kick would raise it, the impulse is
## scaled down (bisection on its magnitude) until the transition is passive. A conservative limit, not a solved
## contact impulse.
func _prop_strike_kick(out: Dictionary, i: int, hit_world: PackedFloat64Array, engagement: float = 1.0) -> void:
	var energy_before: float = _coupled_energy(out.body, out.continuous)
	var omega: float = out.continuous[i]
	var lost: float = omega * PROP_STRIKE_BRAKE * engagement
	out.continuous[i] = omega - lost
	var rotor: Dictionary = prepared.rotors[i]
	var radius: float = 0.5 * float(rotor.diameter_m)
	var body: PackedFloat64Array = out.body
	var attitude := RB._att(body)
	var conj := M.q_conj(attitude)
	var rim_body: PackedFloat64Array = M.scale(M.q_rotate(conj, hit_world), radius)
	# Rotor angular velocity in FRD is (0, 0, −spin·ω) (momentum_z = −spin·I·ω); the tip moves as Ω × r.
	var tip_velocity: PackedFloat64Array = M.cross(M.v3(0.0, 0.0, -float(rotor.spin) * omega), rim_body)
	var tip_speed := M.norm(tip_velocity)
	if not (tip_speed > 1.0e-9) or not (radius > 0.0):
		return
	var magnitude: float = float(rotor.inertia_kg_m2) * absf(lost) / radius
	var impulse: PackedFloat64Array = M.scale(tip_velocity, -magnitude / tip_speed)
	var inverse_inertia: PackedFloat64Array = RB.inertia_inverse(prepared.inertia_kg_m2)
	var delta_rates: PackedFloat64Array = RB.inertia_mul(inverse_inertia, M.cross(rotor.hub_frd, impulse))
	var mass: float = prepared.mass_kg
	var kicked := _kicked(body, impulse, delta_rates, mass, 1.0)
	var budget: float = energy_before + KICK_ENERGY_TOLERANCE * maxf(absf(energy_before), 1.0)
	if _coupled_energy(kicked, out.continuous) > budget:
		var low := 0.0
		var high := 1.0
		for iteration in KICK_PASSIVITY_ITERATIONS:
			var middle := 0.5 * (low + high)
			if _coupled_energy(_kicked(body, impulse, delta_rates, mass, middle), out.continuous) > budget:
				high = middle
			else:
				low = middle
		kicked = _kicked(body, impulse, delta_rates, mass, low)
	out.body = kicked


const KICK_PASSIVITY_ITERATIONS := 40
## Relative round-off allowance of the passivity comparison (the energies are sums of products).
const KICK_ENERGY_TOLERANCE := 1.0e-12


static func _kicked(body: PackedFloat64Array, impulse: PackedFloat64Array, delta_rates: PackedFloat64Array, mass: float,
		scale: float) -> PackedFloat64Array:
	var kicked := body.duplicate()
	for k in 3:
		kicked[RB.VEL + k] += scale * impulse[k] / mass
		kicked[RB.RATE + k] += scale * delta_rates[k]
	return kicked


## Coupled kinetic energy of the airframe and its relative shafts (CR-AUD-21 oracle): the locked-inertia body term
## plus each rotor's relative spin and the body-yaw cross term, K = ½m|v|² + ½ωᵀI_Lω + Σ ½I_iΩ_i² − ω_z Σ s_i I_i Ω_i.
func _coupled_energy(body: PackedFloat64Array, continuous: PackedFloat64Array) -> float:
	var energy: float = _kinetic_energy(body)
	for i in 4:
		var rotor: Dictionary = prepared.rotors[i]
		var inertia := float(rotor.inertia_kg_m2)
		energy += 0.5 * inertia * continuous[i] * continuous[i] - body[RB.RATE + 2] * float(rotor.spin) * inertia * continuous[i]
	return energy


## Unit outward normal of the nearest obstacle at `point` (central differences of the clearance field); straight up
## when the field is flat there (inside a solid's interior plateau).
func _obstacle_normal(point: PackedFloat64Array) -> PackedFloat64Array:
	var g := PackedFloat64Array([0.0, 0.0, 0.0])
	for k in 3:
		var plus := point.duplicate()
		var minus := point.duplicate()
		plus[k] += OBSTACLE_NORMAL_STEP_M
		minus[k] -= OBSTACLE_NORMAL_STEP_M
		var a: Variant = obstacle.call(plus[0], plus[1], plus[2])
		var b: Variant = obstacle.call(minus[0], minus[1], minus[2])
		if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
			g[k] = (float(a) - float(b)) / (2.0 * OBSTACLE_NORMAL_STEP_M)
	var length := M.norm(g)
	return M.scale(g, 1.0 / length) if is_finite(length) and length > 1.0e-6 else M.v3(0.0, 0.0, -1.0)


## Closing speed (m/s, positive into the surface) of the body point `contact_body` (FRD from the CG) along `normal`.
func _closing_speed(body: PackedFloat64Array, contact_body: PackedFloat64Array, normal: PackedFloat64Array) -> float:
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var v_world: PackedFloat64Array = M.q_rotate(RB._att(body), M.add(velocity, M.cross(rates, contact_body)))
	return -M.dot(v_world, normal)


## The shared, energy-bounded scenery normal impulse (scenery_collision.gd) at a body point; a separating contact keeps
## its velocity. DR-19f: then a Coulomb friction impulse against the contact point's sliding, at most `friction` × the
## normal impulse and at most what stops the sliding (so it only removes energy).
func _bounce(body: PackedFloat64Array, contact_body: PackedFloat64Array, normal: PackedFloat64Array, speed: float,
		response_class: String, friction: float = 0.0) -> PackedFloat64Array:
	if not (speed > 0.0):
		return body
	var event := SceneryCollision.Event.new()
	event.normal_ned = normal
	event.body_point = contact_body
	event.normal_speed_mps = speed
	event.response_class = response_class
	event.terminal = false
	var response: Dictionary = SceneryCollision.apply_response(body, event, float(prepared.mass_kg), prepared.inertia_kg_m2)
	if not bool(response.get("ok", false)):
		return body
	return _friction(body, response.state, contact_body, normal, friction)


## DR-19f: the Coulomb friction impulse of a contact (body axes throughout). The normal impulse actually applied is read
## from the velocity change (the shared response may have fallen back to restitution 0). Capped at mu × that impulse, at
## what stops the sliding and at what keeps the contact separating.
func _friction(before: PackedFloat64Array, after: PackedFloat64Array, contact_body: PackedFloat64Array,
		normal: PackedFloat64Array, coefficient: float) -> PackedFloat64Array:
	if not (coefficient > 0.0):
		return after
	var mass: float = prepared.mass_kg
	var normal_body := M.q_rotate(M.q_conj(RB._att(after)), normal)
	var normal_impulse: float = mass * M.dot(M.sub(RB._slice3(after, RB.VEL), RB._slice3(before, RB.VEL)), normal_body)
	if not (normal_impulse > 0.0):
		return after
	var v_contact := M.add(RB._slice3(after, RB.VEL), M.cross(RB._slice3(after, RB.RATE), contact_body))
	var tangential := M.sub(v_contact, M.scale(normal_body, M.dot(v_contact, normal_body)))
	var slip := M.norm(tangential)
	if not (slip > 1.0e-9):
		return after
	var direction := M.scale(tangential, 1.0 / slip)
	var inverse_inertia: PackedFloat64Array = RB.inertia_inverse(prepared.inertia_kg_m2)
	var arm := M.cross(contact_body, direction)
	var inverse_mass: float = 1.0 / mass + M.dot(arm, RB.inertia_mul(inverse_inertia, arm))
	if not (inverse_mass > 0.0):
		return after
	var magnitude := minf(coefficient * normal_impulse, slip / inverse_mass)
	# Off the CG the friction impulse also changes the contact's normal velocity (the inertia couples them): it may
	# shorten the rebound but never turn it back into closing (a separating contact stays separating).
	var separating := M.dot(v_contact, normal_body) # > 0 after the normal impulse
	var normal_change := M.dot(M.add(M.scale(direction, -1.0 / mass),
		M.cross(RB.inertia_mul(inverse_inertia, M.cross(contact_body, M.scale(direction, -1.0))), contact_body)), normal_body)
	if normal_change < 0.0 and separating >= 0.0:
		magnitude = minf(magnitude, separating / -normal_change)
	var impulse := M.scale(direction, -magnitude)
	var rate_change: PackedFloat64Array = RB.inertia_mul(inverse_inertia, M.cross(contact_body, impulse))
	var out := after.duplicate()
	for k in 3:
		out[RB.VEL + k] += impulse[k] / mass
		out[RB.RATE + k] += rate_change[k]
	if not (_kinetic_energy(out) <= _kinetic_energy(after) * (1.0 + 1.0e-12) + 1.0e-12):
		return after
	return out


func _kinetic_energy(body: PackedFloat64Array) -> float:
	var energy := 0.0
	var rates: PackedFloat64Array = RB._slice3(body, RB.RATE)
	var momentum: PackedFloat64Array = RB.inertia_mul(prepared.inertia_kg_m2, rates)
	for k in 3:
		energy += 0.5 * float(prepared.mass_kg) * body[RB.VEL + k] * body[RB.VEL + k] + 0.5 * rates[k] * momentum[k]
	return energy


## DR-19f: sliding speed (m/s) of the body point `contact_body` across a surface with world normal `normal`.
func _slip_speed(body: PackedFloat64Array, contact_body: PackedFloat64Array, normal: PackedFloat64Array) -> float:
	var velocity: PackedFloat64Array = M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2])
	var rates: PackedFloat64Array = M.v3(body[RB.RATE], body[RB.RATE + 1], body[RB.RATE + 2])
	var v_world: PackedFloat64Array = M.q_rotate(RB._att(body), M.add(velocity, M.cross(rates, contact_body)))
	return M.norm(M.sub(v_world, M.scale(normal, M.dot(v_world, normal))))


## DR-19f: chip the spinning props whose disc reaches the contact point (within PROP_CHIP_REACH_M of the prop
## radius from the hub): a hit on an arm tip chips that prop, a belly, battery or far-corner contact chips none.
func _chip_near(out: Dictionary, contact_body: PackedFloat64Array, t: float, cause: String) -> void:
	var strike_speed: float = prepared.contacts.rotor_strike_speed_rad_s
	for i in 4:
		if out.continuous[i] <= strike_speed or out.continuous[C_HEALTH + i] <= 0.0: # forward spin only (see REVERSE_PROP_EFFICIENCY)
			continue
		var rotor: Dictionary = prepared.rotors[i]
		if M.norm(M.sub(rotor.hub_frd, contact_body)) <= 0.5 * float(rotor.diameter_m) + PROP_CHIP_REACH_M:
			_set_health(out, i, out.continuous[C_HEALTH + i] * PROP_CHIP_FACTOR, t, cause)


## One tick of contact wears a spinning prop in proportion to its shaft speed, the surface's material (PROP_MATERIAL)
## and the blade's bite (DR-19f: a tip brushing leaves or grass loses far less than a full bite into wood or concrete).
func _wear(out: Dictionary, i: int, t: float, cause: String, material: float = 1.0, depth_m: float = PROP_FULL_BITE_M) -> void:
	var speed_share := absf(out.continuous[i]) / _hover_speed if _hover_speed > 0.0 else 1.0
	var share := PROP_WEAR_PER_TICK * speed_share * material * _bite(depth_m)
	_set_health(out, i, out.continuous[C_HEALTH + i] * (1.0 - clampf(share, 0.0, 1.0)), t, cause)


## Engagement of a blade biting `depth_m` into a surface, in [PROP_MIN_BITE, 1].
static func _bite(depth_m: float) -> float:
	return clampf(depth_m / PROP_FULL_BITE_M, PROP_MIN_BITE, 1.0) if is_finite(depth_m) else 1.0


func _set_health(out: Dictionary, i: int, value: float, t: float, cause: String) -> void:
	var before: float = out.continuous[C_HEALTH + i]
	var health := clampf(value, 0.0, before)
	if health < PROP_BROKEN_HEALTH:
		health = 0.0
	if health == before:
		return
	out.continuous[C_HEALTH + i] = health
	var body: PackedFloat64Array = out.body
	var hub: PackedFloat64Array = M.add(M.v3(body[RB.POS], body[RB.POS + 1], body[RB.POS + 2]),
		M.q_rotate(RB._att(body), prepared.rotors[i].hub_frd))
	out.events.append({type = "prop_damage", time_s = t, rotor = i, health = health, cause = cause, point_ned = hub,
		broken = health == 0.0, first = before == 1.0})


## Penetration (m, positive below the terrain) of the rim point `radius` from `hub` along the world unit `direction`.
func _rim_depth(hub: PackedFloat64Array, direction: PackedFloat64Array, radius: float) -> float:
	var surface: PackedFloat64Array = _ground_at(hub[0] + radius * direction[0], hub[1] + radius * direction[1])
	return hub[2] + radius * direction[2] + surface[0]


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
	var command_floor: float = -1.0 if _braking and frame.modes[FC.MODE_FLIGHT] == FC.FLIGHT_TURTLE else 0.0 # DR-19e
	for i in 4:
		if aux[FC.AUX_COMMAND + i] < command_floor or aux[FC.AUX_COMMAND + i] > 1.0:
			return false
	if aux[FC.AUX_COLLECTIVE] < 0.0 or aux[FC.AUX_COLLECTIVE] > 1.0 \
			or aux[FC.AUX_VIRTUAL_THROTTLE] < 0.0 or aux[FC.AUX_VIRTUAL_THROTTLE] > 1.0:
		return false
	if electric:
		var terminal: bool = frame.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED or frame.modes[FC.MODE_MOTOR] == FC.MOTOR_DEPLETED
		# Audit A06: the charge never exceeds the capacity (the damped bridge's acceptance bound keeps it there).
		for i in 4:
			if not (continuous[C_HEALTH + i] >= 0.0 and continuous[C_HEALTH + i] <= 1.0):
				return false
		var capacity: float = 3600.0 * float(prepared.battery.capacity_ah)
		if continuous[C_CHARGE] < -CHARGE_TOLERANCE or continuous[C_CHARGE] > capacity * (1.0 + 1.0e-12) 				or continuous[C_CUT_LATCH] not in [0.0, 1.0] \
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
		out.rotor_health = frame.continuous.slice(C_HEALTH, C_HEALTH + 4)
		out.bus_voltage_v = float(bus.get("v_bus", 0.0))
		out.pack_current_a = float(bus.get("i_pack", 0.0))
		out.consumed_mah = (float(prepared.battery.initial_soc) * 3600.0 * float(prepared.battery.capacity_ah) - frame.continuous[C_CHARGE]) / 3.6
	return out
