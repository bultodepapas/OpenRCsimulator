# DR-05: constant-parameter one-RC Thevenin pack, positive current = discharge. The RC energy is explicit;
# polarization voltage is a state, not a correction derived from throttle or wall time. Parameters are estimates
# unless identified by a pack-specific pulse/rest test. Zero R1 is the exactly resistive limiting model.
extends RefCounted

const LAW := "multirotor-pack-one-rc-v1"
const MIN_TIME_S := 0.02 # Scalar RC floor; the loaded-bus slope is screened separately below.
const SAMPLE_HZ := 240.0
const MAX_RC_STEP_SLOPE := 1.0

static func voltage(points: PackedFloat64Array, soc: float) -> float:
	var last := points.size() - 2
	if soc <= points[0]:
		return points[1]
	for i in range(0, last, 2):
		if soc <= points[i + 2]:
			return lerpf(points[i + 1], points[i + 3], (soc - points[i]) / (points[i + 2] - points[i]))
	return points[last + 1]

static func branch(battery: Dictionary, polarization_v: float, current_a: float) -> Dictionary:
	var r1: float = float(battery.get("polarization_resistance_ohm", 0.0))
	if r1 == 0.0:
		return {rate_vps = 0.0, loss_w = 0.0, stored_j = 0.0}
	var tau: float = float(battery.polarization_time_s)
	return {rate_vps = (r1 * current_a - polarization_v) / tau,
		loss_w = polarization_v * polarization_v / r1,
		stored_j = 0.5 * tau * polarization_v * polarization_v / r1}

## Bound the additional RC mode at the fixed flight tick. At frozen shaft speeds, dI/dVsource = G/(1+R0*G),
## G <= 4*max_command²/Rm, so h*|lambda_RC| <= h/tau * (1 + R1*G/(1+R0*G)). This conservative screen
## covers both active-set and zero-pack-current branches; it is not a proof for the full coupled Jacobian.
static func integration_error(battery: Dictionary, motor: Dictionary) -> String:
	var r1: Variant = battery.get("polarization_resistance_ohm", 0.0)
	if not _number(r1) or float(r1) < 0.0:
		return "battery polarization resistance must be finite and nonnegative"
	if float(r1) == 0.0:
		return ""
	var r0: Variant = battery.get("resistance_ohm")
	var tau: Variant = battery.get("polarization_time_s")
	var rm: Variant = motor.get("resistance_ohm")
	var duty: Variant = motor.get("max_command")
	if not _number(r0) or float(r0) < 0.0 or not _number(tau) or float(tau) < MIN_TIME_S \
			or not _number(rm) or float(rm) <= 0.0 or not _number(duty) or float(duty) <= 0.0 or float(duty) > 1.0:
		return "battery polarization integration requires valid pack, time and motor bounds"
	var gain := 4.0 * float(duty) * float(duty)
	var slope := (1.0 + float(r1) * gain / (float(rm) + float(r0) * gain)) / (SAMPLE_HZ * float(tau))
	if not is_finite(slope) or slope > MAX_RC_STEP_SLOPE:
		return "battery polarization: loaded RC step slope %s exceeds %s at 240 Hz; these parameters require qualified smaller steps" % [slope, MAX_RC_STEP_SLOPE]
	return ""


## Shared normalized battery domains. Raw-unit/provenance admission remains with the document loader.
static func error(battery: Dictionary) -> String:
	if not _number(battery.get("cells")) or float(battery.cells) != floorf(float(battery.cells)) \
			or float(battery.cells) < 1.0 or float(battery.cells) > 14.0:
		return "battery.cells must be an integer from 1 through 14"
	for key: String in ["capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc"]:
		if not _number(battery.get(key)):
			return "battery.%s must be finite" % key
	if float(battery.capacity_ah) <= 0.0 or float(battery.capacity_ah) > 100.0 \
			or float(battery.resistance_ohm) < 0.0 or float(battery.resistance_ohm) > 10.0 \
			or float(battery.auxiliary_current_a) < 0.0 or float(battery.auxiliary_current_a) > 100.0 \
			or float(battery.initial_soc) <= 0.0 or float(battery.initial_soc) > 1.0:
		return "battery capacity, resistance, auxiliary load or initial SOC is outside its domain"
	var points: Variant = battery.get("ocv_points")
	if typeof(points) != TYPE_PACKED_FLOAT64_ARRAY or points.size() < 4 or points.size() > 64 or points.size() % 2 != 0:
		return "battery.ocv_points must contain 2 through 32 [SOC, volts] pairs"
	var cells := float(battery.cells)
	for i in range(0, points.size(), 2):
		if not is_finite(points[i]) or not is_finite(points[i + 1]) or points[i] < 0.0 or points[i] > 1.0 \
				or points[i + 1] < 2.5 * cells or points[i + 1] > 4.35 * cells:
			return "battery.ocv_points has an out-of-domain SOC or cell voltage"
		if i > 0 and (points[i] <= points[i - 2] or points[i + 1] < points[i - 1]):
			return "battery.ocv_points requires increasing SOC and nondecreasing voltage"
	if points[0] != 0.0 or points[points.size() - 2] != 1.0:
		return "battery.ocv_points must span SOC 0 through 1"
	var r1: Variant = battery.get("polarization_resistance_ohm", 0.0)
	var tau: Variant = battery.get("polarization_time_s", 0.0)
	if not _number(r1) or float(r1) < 0.0 or float(r1) > 10.0 or not _number(tau):
		return "battery polarization resistance and time must be finite and in range"
	if (float(r1) == 0.0 and float(tau) != 0.0) \
			or (float(r1) > 0.0 and (float(tau) < MIN_TIME_S or float(tau) > 3600.0)):
		return "battery polarization needs positive R1 and time >= 0.02 s, or both zero"
	return ""

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
