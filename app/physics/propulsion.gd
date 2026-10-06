# Propulsion v0 (D5): glow engine rpm with a first-order lag, propeller thrust and torque from Ct(J), Cp(J).
# 64-bit floats only (guarded). Data: AircraftData model.propulsion.
# Optional, per aircraft (absent = the D5 behaviour, bit for bit):
#  - shaft balance (G2 first slice, P51-06): rpm from J_rot·dω/dt = Q_engine(n, throttle) − Q_prop(J, n), so the
#    propeller unloads with airspeed, windmills and brakes at idle, and spools up at a torque-limited rate;
#  - thrust axis angles (down/right thrust): thrust, reaction torque and rotor momentum along the tilted shaft;
#  - propeller normal force at a disc angle of attack (the "fin effect" and P-factor), see normal_force().
# Not yet: fuel, engine stop/start in flight, sound physics — see ROADMAP G2–G4.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const Turbine := preload("res://physics/turbine.gd")

## Below this, the engine produces nothing (stopped).
const STOPPED_RPM := 1.0
## Beyond the table, coefficients extrapolate linearly but never below these floors (windmilling).
const CT_FLOOR := -0.1
const CP_FLOOR := 0.0
## Shaft balance: the rpm search bracket's top, as a multiple of the power curve's last rpm row.
const SHAFT_RPM_CEILING := 1.6


## Piecewise-linear table [J0, v0, J1, v1, …]. J < 0 (flying backwards) uses the J = 0 value;
## beyond the last row, linear extrapolation from the last two rows, floored at `floor_value`.
static func coefficient(table: PackedFloat64Array, J: float, floor_value: float) -> float:
	var n := table.size() / 2
	if J <= table[0]:
		return table[1]
	for i in range(1, n):
		if J <= table[2 * i]:
			var j0 := table[2 * i - 2]
			var j1 := table[2 * i]
			return lerpf(table[2 * i - 1], table[2 * i + 1], (J - j0) / (j1 - j0))
	var ja := table[2 * n - 4]
	var jb := table[2 * n - 2]
	var slope := (table[2 * n - 1] - table[2 * n - 3]) / (jb - ja)
	return maxf(floor_value, table[2 * n - 1] + slope * (J - jb))


## Throttle (0…1) → target rpm between idle and the static maximum (D5 lag model).
static func target_rpm(throttle: float, prop: Dictionary) -> float:
	return prop.idle_rpm + clampf(throttle, 0.0, 1.0) * (prop.max_rpm - prop.idle_rpm)


## Exact first-order lag over one step: independent of how the time is split into steps.
static func rpm_step(rpm: float, throttle: float, dt: float, prop: Dictionary) -> float:
	var target := target_rpm(throttle, prop)
	return target + (rpm - target) * M.exp_(-dt / prop.lag)


## True when the aircraft declares a shaft model (rpm from the torque balance instead of the throttle lag).
static func has_shaft(prop: Dictionary) -> bool:
	return not prop.get("shaft", {}).is_empty()


## Cp floor: 0 for the D5 tables (no windmilling torque), the table's own minimum when it tabulates windmilling.
static func _cp_floor(prop: Dictionary) -> float:
	return minf(CP_FLOOR, float(prop.get("cp_min", 0.0)))


## Propeller shaft torque (N·m, positive = absorbs engine power) at rpm and axial airspeed u (m/s).
static func prop_torque(rpm: float, u: float, prop: Dictionary, rho: float) -> float:
	if rpm < STOPPED_RPM:
		return 0.0
	var D: float = prop.diameter
	var n := rpm / 60.0
	var J := maxf(u, 0.0) / (n * D)
	return coefficient(prop.cp, J, _cp_floor(prop)) * rho * n * n * pow(D, 5) / TAU


## Engine output torque (N·m) at rpm for throttle 0…1 (shaft model). The throttle admits indicated power
## P_adm = P_idle + θ·(P_peak_ind − P_idle) (air flow through the carburettor); the engine delivers
## Q = min(Q_full_ind(n), P_adm/ω) − Q_friction(n). Q_full_ind is the full-throttle brake torque curve plus friction.
static func engine_torque(rpm: float, throttle: float, prop: Dictionary) -> float:
	var sh: Dictionary = prop.shaft
	var omega := maxf(rpm, 0.0) * TAU / 60.0
	var friction: float = sh.friction[0] + sh.friction[1] * rpm / 1000.0
	var curve: PackedFloat64Array = sh.power_curve # [rpm0, W0, rpm1, W1, …], brake power at full throttle
	var brake_full: float
	if rpm <= curve[0]:
		brake_full = curve[1] / (curve[0] * TAU / 60.0) # constant torque below the first row
	else:
		brake_full = coefficient(curve, rpm, 0.0) / omega
	var admitted: float = sh.idle_power + clampf(throttle, 0.0, 1.0) * (sh.peak_indicated_power - sh.idle_power)
	var indicated := minf(brake_full + friction, admitted / maxf(omega, 1.0))
	return indicated - friction


## Shaft model step: J_rot·dω/dt = Q_engine − Q_prop, explicit over one tick (τ ≈ 0.2 s ≫ dt). rpm ≥ 0.
static func shaft_step(rpm: float, throttle: float, u: float, dt: float, prop: Dictionary, rho: float) -> float:
	var net := engine_torque(rpm, throttle, prop) - prop_torque(rpm, u, prop, rho)
	return maxf(0.0, rpm + net / float(prop.rotor_inertia) * dt * 60.0 / TAU)


## Steady rpm for a throttle at axial airspeed u: the lag model's target, or the shaft model's torque balance
## (bisection; the net torque falls with rpm through a single root).
static func steady_rpm(throttle: float, u: float, prop: Dictionary, rho: float) -> float:
	if Turbine.is_turbine(prop): # AV-05
		return Turbine.steady_rpm(throttle, prop)
	if not has_shaft(prop):
		return target_rpm(throttle, prop)
	var curve: PackedFloat64Array = prop.shaft.power_curve
	var lo := STOPPED_RPM
	var hi := curve[curve.size() - 2] * SHAFT_RPM_CEILING
	for _i in 80:
		var mid := 0.5 * (lo + hi)
		if engine_torque(mid, throttle, prop) - prop_torque(mid, u, prop, rho) > 0.0:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## Unit shaft axis in body FRD: +x tilted down (down thrust: +z) and right (right thrust: +y). [1, 0, 0] by default.
static func axis(prop: Dictionary) -> PackedFloat64Array:
	return prop.get("axis", PackedFloat64Array([1.0, 0.0, 0.0]))


## Propeller normal force and P-factor moment at a disc angle of attack (McCormick's blade-element result as used by
## Selig 2010, AIAA 2010-7938; Ribner NACA TR 819 agrees within ~20 %). With the crossflow v_c (air-relative body
## velocity minus its shaft component) and sin α_p = |v_c|/V:
##   force  F = −C_N(J)·ρn²D⁴·v_c/V   (in the disc plane, like a fin at the propeller: up at positive α)
##   moment M = −s·C_M(J)·ρn²D⁵·v_c/V (s = +1 clockwise from behind: positive α yaws the nose LEFT, flow from the
##   right pitches it down: the descending blade carries more thrust)
## C_N and C_M are the data's normal_force and pfactor_moment tables (per radian of α_p). Empty tables → zero.
static func normal_force(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	return _crossflow(v_air, rpm, prop, rho, "normal_force", 4)


static func pfactor_moment(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	return _crossflow(v_air, rpm, prop, rho, "pfactor_moment", 5)


static func _crossflow(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float, key: String,
		power: int) -> PackedFloat64Array:
	var table: PackedFloat64Array = prop.get(key, PackedFloat64Array())
	var speed := sqrt(M.dot(v_air, v_air))
	if table.is_empty() or rpm < STOPPED_RPM or speed < 1e-6:
		return M.v3(0.0, 0.0, 0.0)
	var ax := axis(prop)
	var along := M.dot(v_air, ax)
	var cross := M.sub(v_air, M.scale(ax, along))
	var D: float = prop.diameter
	var n := rpm / 60.0
	var J := maxf(along, 0.0) / (n * D)
	return M.scale(cross, -coefficient(table, J, 0.0) * rho * n * n * pow(D, power) / speed)


## Thrust (N, along the shaft), shaft torque (N·m) and advance ratio for air-relative body velocity v_air.
static func thrust_torque(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	var D: float = prop.diameter
	var n := rpm / 60.0
	var u := v_air[0] if not prop.has("axis") else M.dot(v_air, prop.axis)
	var J := maxf(u, 0.0) / (n * D)
	var thrust := coefficient(prop.ct, J, CT_FLOOR) * rho * n * n * pow(D, 4)
	var power := coefficient(prop.cp, J, _cp_floor(prop)) * rho * n * n * n * pow(D, 5)
	return PackedFloat64Array([thrust, power / (TAU * n), J])


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz] for air-relative body velocity v_air.
## Thrust along the shaft (body +x unless tilted) on the thrust line; the reaction to a clockwise (from behind) prop
## rolls the airplane left. With a normal-force table, the in-plane force acts at the propeller disc.
static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if Turbine.is_turbine(prop): # AV-05
		return Turbine.loads(v_air, rpm, prop, rho)
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var tq := thrust_torque(v_air, rpm, prop, rho)
	var thrust := tq[0]
	var torque := tq[1]
	var r: PackedFloat64Array = prop.offset # [x_aft, y_right, z_up] from the CG
	var at := M.v3(-r[0], r[1], -r[2])
	if not prop.has("axis"):
		var arm := M.cross(at, M.v3(thrust, 0.0, 0.0))
		return PackedFloat64Array([thrust, 0.0, 0.0, -torque + arm[0], arm[1], arm[2]])
	var ax: PackedFloat64Array = prop.axis
	var force := M.add(M.scale(ax, thrust), normal_force(v_air, rpm, prop, rho))
	var moment := M.add(M.sub(M.cross(at, force), M.scale(ax, torque)), pfactor_moment(v_air, rpm, prop, rho))
	return PackedFloat64Array([force[0], force[1], force[2], moment[0], moment[1], moment[2]])
