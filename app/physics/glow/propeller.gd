## NITRO: passive annular blade-element surrogate, including stopped/windmilling flow.
## All section coefficients are estimated installation inputs, never measured propeller maps.
extends RefCounted
const M := preload("res://physics/math3d.gd")
const POWER_BOUND_REL_TOL := 1.0e-10

static func evaluate(rpm: float, axial_speed: float, rho: float, p: Dictionary) -> Dictionary:
	if not is_finite(rpm) or rpm < 0.0 or not is_finite(axial_speed) or not is_finite(rho) or rho <= 0.0:
		return {ok = false}
	for key in ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]:
		if typeof(p.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p[key])) or p[key] <= 0.0:
			return {ok = false}
	# Hoist validated installation values out of the 12-annulus loop.
	var diameter_m: float = float(p.diameter_m)
	var pitch_m: float = float(p.pitch_m)
	var chord_m: float = float(p.chord_m)
	var lift_slope: float = float(p.lift_slope)
	var cd0: float = float(p.cd0)
	var induced_drag: float = float(p.induced_drag)
	var blades: float = float(p.blades)
	var radius: float = 0.5 * diameter_m
	var omega: float = rpm * TAU / 60.0
	if not is_finite(omega):
		return {ok = false, message = "Propeller angular speed overflowed"}
	var thrust: float = 0.0
	var torque: float = 0.0
	var dissipation: float = 0.0
	# Midpoint annuli, inner 20% excluded as a root/hub. Smooth flat-plate stall blend.
	var dr: float = radius * 0.8 / 12.0
	for i in 12:
		var r: float = radius * 0.2 + (i + 0.5) * dr
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
		var beta: float = M.atan2_(pitch_m, TAU * r)
		var alpha: float = beta - phi
		var cl: float = lift_slope * M.sin_(2.0 * alpha) / 2.0
		# At large alpha lift is bounded; pressure drag increases to the flat-plate limit.
		cl = clampf(cl, -1.25, 1.25)
		var cd: float = cd0 + induced_drag * cl * cl + 1.2 * M.pow_(M.sin_(alpha), 2.0)
		var area_pressure: float = 0.5 * rho * speed_sq * chord_m * dr * blades
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
		var disk_area: float = PI * diameter_m * diameter_m / 4.0
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
