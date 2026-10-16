# Flight-test pilot laws for any fixed-wing catalog aircraft (FT-01). Pilot units: +roll right, +pitch nose up,
# +yaw nose right, stick in [-1, 1] added to the radio trims; throttle absolute in [0, 1].
# Gains are stick per radian at the aircraft's start speed and fall with dynamic pressure, (v_ref/V)², like a gain-
# scheduled autopilot, so the same law flies a 1.3 m trainer and a 2.8 m warbird. Integrators remove steady offsets
# (a proportional pilot measures its own error, P51-22); they accumulate in stick units and reach the full ±1 whatever
# the schedule, so a pilot never stops short of a stop the airplane could still use. Research tool, not runtime code.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")


static func euler(s: PackedFloat64Array) -> PackedFloat64Array: # [yaw, pitch, roll]
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))


static func speed(s: PackedFloat64Array) -> float:
	return sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)


static func alpha(s: PackedFloat64Array) -> float:
	return atan2(s[RB.VEL + 2], s[RB.VEL])


static func beta(s: PackedFloat64Array) -> float:
	return atan2(s[RB.VEL + 1], sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 2] ** 2))


static func altitude(s: PackedFloat64Array) -> float:
	return -s[RB.POS + 2]


static func climb_rate(s: PackedFloat64Array) -> float:
	return -M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]), M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))[2]


## Earth-frame "up" expressed in body axes [x fwd, y right, z down].
static func up_body(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(M.q_conj(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])), M.v3(0.0, 0.0, -1.0))


## Gain schedule: (v_ref/V)², bounded so a near-stopped or very fast airplane keeps a usable loop.
static func schedule(s: PackedFloat64Array, v_ref: float) -> float:
	var v := maxf(speed(s), 1.0)
	return clampf((v_ref / v) ** 2, 0.25, 4.0)


static func _integrate(st: Dictionary, key: String, error: float, dt: float, limit: float) -> float:
	st[key] = clampf(float(st.get(key, 0.0)) + error * dt, -limit, limit)
	return st[key]


## Ailerons for a bank angle (rad), PD on bank and roll rate.
static func bank(s: PackedFloat64Array, target: float, k: float) -> float:
	var e := euler(s)
	return clampf(k * (2.0 * wrapf(target - e[2], -PI, PI) - 0.3 * s[RB.RATE]), -1.0, 1.0)


## Ailerons for a bank angle with an integrator: holds a bank against steady rolling moments (knife-edge, inverted).
static func bank_pi(s: PackedFloat64Array, target: float, k: float, st: Dictionary, dt: float) -> float:
	var error := wrapf(target - euler(s)[2], -PI, PI)
	var i := _integrate(st, "bank_i", 2.0 * k * error, dt, 1.0)
	return clampf(k * (2.0 * error - 0.3 * s[RB.RATE]) + i, -1.0, 1.0)


## Ailerons that only stop roll rate (no Euler angle: valid through loops and vertical lines).
static func roll_damper(s: PackedFloat64Array, k: float) -> float:
	return clampf(-k * s[RB.RATE], -1.0, 1.0)


## Elevator for a pitch attitude (rad): PI on attitude with pitch-rate damping.
static func pitch(s: PackedFloat64Array, target: float, k: float, st: Dictionary, dt: float) -> float:
	var error: float = target - euler(s)[1]
	var i := _integrate(st, "pitch_i", 2.0 * k * error, dt, 1.0)
	return clampf(k * (3.0 * error - 0.6 * s[RB.RATE + 1]) + i, -1.0, 1.0)


## Elevator for an angle of attack (rad): PI on α with pitch-rate damping (Euler-free).
static func alpha_hold(s: PackedFloat64Array, target: float, k: float, st: Dictionary, dt: float) -> float:
	var error: float = target - alpha(s)
	var i := _integrate(st, "alpha_i", 4.0 * k * error, dt, 1.0)
	return clampf(k * (4.0 * error - 0.3 * s[RB.RATE + 1]) + i, -1.0, 1.0)


## Elevator for an altitude (m): outer PI loop to a pitch target, inner pitch PI.
static func hold_altitude(s: PackedFloat64Array, target: float, k: float, st: Dictionary, dt: float, pitch_trim := 0.0) -> float:
	var error := target - altitude(s)
	var i := _integrate(st, "altitude_i", error, dt, 100.0)
	var wanted := clampf(pitch_trim + 0.02 * error - 0.03 * climb_rate(s) + 0.002 * i, -0.35, 0.35)
	return pitch(s, wanted, k, st, dt)


## Elevator for an airspeed (m/s): nose up when too fast, through the pitch PI. The outer integral holds the speed
## at any steady flight-path angle.
static func hold_speed(s: PackedFloat64Array, target: float, k: float, st: Dictionary, dt: float) -> float:
	var error: float = speed(s) - target
	var i := _integrate(st, "speed_i", error, dt, 60.0)
	var wanted := clampf(0.04 * error + 0.02 * i, -0.6, 1.3)
	return pitch(s, wanted, k, st, dt)


## Rudder holding zero sideslip (a pilot's feet on the ball), as Maneuvers.COORDINATION_GAIN.
static func coordinate(s: PackedFloat64Array) -> float:
	return clampf(10.0 * beta(s), -1.0, 1.0)


## Rudder centring the ball, as a test pilot does: the fast loop holds a sideslip target (stable, like
## Maneuvers.COORDINATION_GAIN), and a slow integral moves that target until the lateral specific force ay (g, body
## +right, stored by the caller in st.ay) is zero. Under power the slipstream and propeller put a side force on the
## airplane at β = 0; a closed fast loop on ay oscillates because the rudder's own side force leads the sideslip.
static func ball(s: PackedFloat64Array, k: float, st: Dictionary, dt: float) -> float:
	var target := _integrate(st, "ball_beta", 0.5 * float(st.get("ay", 0.0)), dt, deg_to_rad(10.0))
	return clampf(10.0 * k * (beta(s) - target), -1.0, 1.0) # rudder power grows with V²: scheduled like the others


## Rudder for a heading (rad) on the ground: PD on heading and yaw rate.
static func ground_heading(s: PackedFloat64Array, heading: float) -> float:
	return clampf(3.0 * wrapf(heading - euler(s)[0], -PI, PI) - 1.0 * s[RB.RATE + 2], -1.0, 1.0)
