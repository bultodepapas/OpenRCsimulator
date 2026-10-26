## NITRO: passive annular blade-element surrogate, including stopped/windmilling flow.
## All section coefficients are estimated installation inputs, never measured propeller maps.
## EX-14f (optional): a cambered section's zero-lift angle zero_lift_angle_rad (≤ 0) shifts the lift and the flat-plate
## blend to the angle from the zero-lift line, α − α0; absent or 0 leaves the symmetric section exactly as before.
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")
const POWER_BOUND_REL_TOL := 1.0e-10


## A detached, immutable-by-interface installation snapshot for repeated flight
## stages. The annulus radii and pitch angles are computed once with the same
## float64 operation order as the public evaluator's original loop.
class PreparedEvaluator extends RefCounted:
	const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")
	const POWER_BOUND_REL_TOL := 1.0e-10
	var _valid: bool = false
	var _message: String = "Invalid propeller parameters"
	var _diameter_m: float
	var _chord_m: float
	var _lift_slope: float
	var _cd0: float
	var _induced_drag: float
	var _blades: float
	var _zero_lift_angle: float = 0.0
	var _dr: float
	var _annulus_radii: PackedFloat64Array
	var _pitch_angles: PackedFloat64Array

	func _init(p: Dictionary) -> void:
		for key: String in ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]:
			if typeof(p.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p[key])) or p[key] <= 0.0:
				_message = "Invalid propeller parameter: " + key
				return
		_diameter_m = float(p.diameter_m)
		_chord_m = float(p.chord_m)
		_lift_slope = float(p.lift_slope)
		_cd0 = float(p.cd0)
		_induced_drag = float(p.induced_drag)
		_blades = float(p.blades)
		if p.has("zero_lift_angle_rad"):
			var zero_lift: Variant = p.zero_lift_angle_rad
			if typeof(zero_lift) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(zero_lift)) \
					or float(zero_lift) < -0.3 or float(zero_lift) > 0.0:
				_message = "Invalid propeller parameter: zero_lift_angle_rad"
				return
			_zero_lift_angle = float(zero_lift)
		var pitch_m: float = float(p.pitch_m)
		var radius: float = 0.5 * _diameter_m
		_dr = radius * 0.8 / 12.0
		for i in 12:
			var r: float = radius * 0.2 + (i + 0.5) * _dr
			_annulus_radii.append(r)
			_pitch_angles.append(M.atan2_(pitch_m, TAU * r))
		_valid = true
		_message = ""

	func _evaluate(rpm: float, axial_speed: float, rho: float) -> Dictionary:
		if not is_finite(rpm) or rpm < 0.0 or not is_finite(axial_speed) or not is_finite(rho) or rho <= 0.0:
			return {ok = false}
		var omega: float = rpm * TAU / 60.0
		if not is_finite(omega):
			return {ok = false, message = "Propeller angular speed overflowed"}
		var thrust: float = 0.0
		var torque: float = 0.0
		var dissipation: float = 0.0
		# Midpoint annuli, inner 20% excluded as a root/hub. Smooth flat-plate stall blend.
		for i in 12:
			var r: float = _annulus_radii[i]
			var tangential: float = omega * r
			var speed_sq: float = tangential * tangential + axial_speed * axial_speed
			if not is_finite(speed_sq) or speed_sq < 0.0:
				return {ok = false, message = "Propeller section speed overflowed"}
			if speed_sq == 0.0:
				continue
			var speed: float = M.sqrt_(speed_sq)
			if not is_finite(speed) or speed <= 0.0:
				return {ok = false, message = "Propeller section speed is invalid"}
			var phi: float = M.atan2_(axial_speed, tangential)
			var beta: float = _pitch_angles[i]
			var alpha: float = beta - phi - _zero_lift_angle # from the zero-lift line (exact for 0)
			var cl: float = _lift_slope * M.sin_(2.0 * alpha) / 2.0
			# At large alpha lift is bounded; pressure drag increases to the flat-plate limit.
			cl = clampf(cl, -1.25, 1.25)
			var cd: float = _cd0 + _induced_drag * cl * cl + 1.2 * M.pow_(M.sin_(alpha), 2.0)
			var area_pressure: float = 0.5 * rho * speed_sq * _chord_m * _dr * _blades
			var lift: float = area_pressure * cl
			var drag: float = area_pressure * cd
			if not is_finite(area_pressure) or not is_finite(lift) or not is_finite(drag):
				return {ok = false, message = "Propeller section force overflowed"}
			thrust += (lift * tangential - drag * axial_speed) / speed
			torque += (lift * axial_speed + drag * tangential) * r / speed
			dissipation += drag * speed
		var shaft_power: float = torque * omega
		var thrust_power: float = thrust * axial_speed
		if not is_finite(thrust) or not is_finite(torque) or not is_finite(dissipation) \
				or not is_finite(shaft_power) or not is_finite(thrust_power):
			return {ok = false, message = "Propeller force or power overflowed"}
		# Powered forward flow must supply at least the ideal actuator-disk work for
		# this thrust and disk area. This is a necessary momentum-energy bound, not a
		# solution for induced flow. Reverse inflow and windmilling retain their
		# existing signed-power behavior and are intentionally outside this branch.
		if thrust > 0.0 and axial_speed >= 0.0:
			var disk_area: float = PI * _diameter_m * _diameter_m / 4.0
			var disk_mass_term: float = rho * disk_area
			if not is_finite(disk_area) or disk_area <= 0.0 or not is_finite(disk_mass_term) or disk_mass_term <= 0.0:
				return {ok = false, message = "Propeller actuator-disk area overflowed"}
			var ideal_speed_sq: float = axial_speed * axial_speed + 2.0 * thrust / disk_mass_term
			if not is_finite(ideal_speed_sq) or ideal_speed_sq <= 0.0:
				return {ok = false, message = "Propeller ideal induced speed overflowed"}
			var ideal_power: float = 0.5 * thrust * (axial_speed + M.sqrt_(ideal_speed_sq))
			if not is_finite(ideal_power) or ideal_power <= 0.0:
				return {ok = false, message = "Propeller ideal actuator-disk power overflowed"}
			var power_scale: float = maxf(absf(shaft_power), ideal_power)
			if shaft_power < ideal_power - POWER_BOUND_REL_TOL * power_scale:
				return {ok = false, message = "Forward thrust requires more power than the shaft supplies"}
		return {ok = true, thrust_n = thrust, torque_nm = torque,
			shaft_power_w = shaft_power, thrust_power_w = thrust_power,
			dissipation_w = dissipation}


## Public, fully guarded path. This remains suitable for arbitrary installation
## dictionaries; repeated flight stages should use prepare_evaluator once.
static func evaluate(rpm: float, axial_speed: float, rho: float, p: Dictionary) -> Dictionary:
	if not _valid_query(rpm, axial_speed, rho):
		return {ok = false}
	var evaluator := PreparedEvaluator.new(p)
	if not evaluator._valid:
		return {ok = false}
	return evaluator._evaluate(rpm, axial_speed, rho)

## Validates all public installation parameters and returns a detached typed
## evaluator. It has no mutable physical state and can be replaced atomically
## whenever an installation changes.
static func prepare_evaluator(p: Dictionary) -> Dictionary:
	var evaluator := PreparedEvaluator.new(p)
	if not evaluator._valid:
		return {ok = false, message = evaluator._message}
	return {ok = true, message = "", evaluator = evaluator}


## The prepared route accepts only the typed snapshot returned above and still
## checks each dynamic query before entering the shared numerical kernel.
static func evaluate_prepared(evaluator: Variant, rpm: float,
		axial_speed: float, rho: float) -> Dictionary:
	if not evaluator is PreparedEvaluator or not evaluator._valid:
		return {ok = false, message = "A prepared propeller evaluator is required"}
	return evaluator._evaluate(rpm, axial_speed, rho)


static func _valid_query(rpm: float, axial_speed: float, rho: float) -> bool:
	return is_finite(rpm) and rpm >= 0.0 and is_finite(axial_speed) \
		and is_finite(rho) and rho > 0.0
