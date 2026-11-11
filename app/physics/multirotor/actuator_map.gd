# DR-05/07: static command-to-thrust map of one rotor, used by the flight controller to turn allocated thrust
# targets into held actuator commands and to bound the allocation. It is a steady-state prediction, not a force
# sensor: motor lag, pack sag below the sampled supply voltage and forward flight all make the produced thrust
# differ, and the rate loop closes that gap. Two powertrain laws:
#   first-order-lab-v1      command u is the fraction of the full-command speed: f = k_T·(u·w_full)²
#   el-one-quadrant-bus-v1  command u is the effective bridge duty; the steady shaft speed solves
#                           Kt·((u·V − w/Kv)/R − I0) = k_Q·w², with Kt = 1/Kv (Kv in rad/s per volt)
# The electrical map takes the supply voltage of the sample (the open-circuit voltage at the sampled charge);
# it does not compensate for sag under load. 64-bit floats only.
extends RefCounted

const LAW_LAB := "first-order-lab-v1"
const LAW_ELECTRIC := "el-one-quadrant-bus-v1"


## {ok, errors, map}: an immutable-by-convention flat dictionary of the constants the two functions need.
static func prepare(powertrain: Dictionary, rotor_law: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var law: String = str(powertrain.get("law", ""))
	var k_t: float = float(rotor_law.get("thrust_coefficient_n_s2", NAN))
	var k_q: float = float(rotor_law.get("torque_coefficient_n_m_s2", NAN))
	var idle: float = float(powertrain.get("idle_command", NAN))
	var top: float = float(powertrain.get("max_command", NAN))
	if not (is_finite(k_t) and k_t > 0.0 and is_finite(k_q) and k_q > 0.0):
		errors.append("actuator map: thrust and torque coefficients must be positive")
	if not (is_finite(idle) and is_finite(top) and idle >= 0.0 and idle < top and top <= 1.0):
		errors.append("actuator map: command range must satisfy 0 <= idle < max <= 1")
	var map := {law = law, k_t = k_t, k_q = k_q, idle = idle, top = top}
	if law == LAW_LAB:
		map.full_speed = float(powertrain.get("full_command_speed_rad_s", NAN))
		if not (is_finite(map.full_speed) and map.full_speed > 0.0):
			errors.append("actuator map: full-command speed must be positive")
	elif law == LAW_ELECTRIC:
		map.kv = float(powertrain.get("kv_rad_s_per_v", NAN))
		map.resistance = float(powertrain.get("resistance_ohm", NAN))
		map.no_load = float(powertrain.get("no_load_current_a", NAN))
		if not (is_finite(map.kv) and map.kv > 0.0 and is_finite(map.resistance) and map.resistance > 0.0
				and is_finite(map.no_load) and map.no_load >= 0.0):
			errors.append("actuator map: motor constants are invalid")
		else:
			map.kt = 1.0 / map.kv
	else:
		errors.append("actuator map: unsupported powertrain law '%s'" % law)
	return {ok = errors.is_empty(), errors = errors, map = map}


## Steady shaft speed (rad/s) at command u and supply voltage v (ignored by the lab law).
static func static_speed(map: Dictionary, u: float, v: float) -> float:
	if map.law == LAW_LAB:
		return maxf(u, 0.0) * float(map.full_speed)
	var kt: float = map.kt
	var b: float = kt / (float(map.kv) * float(map.resistance))
	var c: float = kt * (u * v / float(map.resistance) - float(map.no_load))
	if c <= 0.0:
		return 0.0
	var k_q: float = map.k_q
	return (-b + sqrt(b * b + 4.0 * k_q * c)) / (2.0 * k_q)


## Steady thrust (N) at command u and supply voltage v.
static func static_thrust(map: Dictionary, u: float, v: float) -> float:
	var speed: float = static_speed(map, u, v)
	return float(map.k_t) * speed * speed


## The command whose steady thrust is f (N), unclamped: the caller applies its idle and output limits.
static func command_for_thrust(map: Dictionary, f: float, v: float) -> float:
	var speed: float = sqrt(maxf(f, 0.0) / float(map.k_t))
	if map.law == LAW_LAB:
		return speed / float(map.full_speed)
	if v <= 0.0:
		return float(map.top)
	var current: float = float(map.k_q) * speed * speed / float(map.kt) + float(map.no_load)
	return (speed / float(map.kv) + float(map.resistance) * current) / v
