# Propulsion v0 (D5): glow engine rpm with a first-order lag, propeller thrust and torque from Ct(J), Cp(J).
# 64-bit floats only (guarded). Data: AircraftData model.propulsion.
# Not yet: in-flight prop unloading (rpm rising with airspeed), fuel, sound physics — see ROADMAP G1–G4.
extends RefCounted

const M := preload("res://physics/math3d.gd")

## Below this, the engine produces nothing (stopped).
const STOPPED_RPM := 1.0
## Beyond the table, coefficients extrapolate linearly but never below these floors (windmilling).
const CT_FLOOR := -0.1
const CP_FLOOR := 0.0


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


## Throttle (0…1) → target rpm between idle and the static maximum.
static func target_rpm(throttle: float, prop: Dictionary) -> float:
	return prop.idle_rpm + clampf(throttle, 0.0, 1.0) * (prop.max_rpm - prop.idle_rpm)


## Exact first-order lag over one step: independent of how the time is split into steps.
static func rpm_step(rpm: float, throttle: float, dt: float, prop: Dictionary) -> float:
	var target := target_rpm(throttle, prop)
	return target + (rpm - target) * M.exp_(-dt / prop.lag)


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz] for air-relative body velocity v_air.
## Thrust along body +x on the thrust line; the reaction to a clockwise (from behind) prop rolls the airplane left.
static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var D: float = prop.diameter
	var n := rpm / 60.0
	var J := maxf(v_air[0], 0.0) / (n * D)
	var thrust := coefficient(prop.ct, J, CT_FLOOR) * rho * n * n * pow(D, 4)
	var power := coefficient(prop.cp, J, CP_FLOOR) * rho * n * n * n * pow(D, 5)
	var torque := power / (TAU * n)
	var r: PackedFloat64Array = prop.offset # [x_aft, y_right, z_up] from the CG
	var arm := M.cross(M.v3(-r[0], r[1], -r[2]), M.v3(thrust, 0.0, 0.0))
	return PackedFloat64Array([thrust, 0.0, 0.0, -torque + arm[0], arm[1], arm[2]])
