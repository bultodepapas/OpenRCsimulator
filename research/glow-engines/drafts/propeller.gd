## NITRO: passive annular blade-element surrogate, including stopped/windmilling flow.
## All section coefficients are estimated installation inputs, never measured propeller maps.
extends RefCounted
const M := preload("res://physics/math3d.gd")

static func evaluate(rpm: float, axial_speed: float, rho: float, p: Dictionary) -> Dictionary:
	if not is_finite(rpm) or rpm < 0.0 or not is_finite(axial_speed) or not is_finite(rho) or rho <= 0.0:
		return {ok = false}
	for key in ["diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"]:
		if typeof(p.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(p[key])) or p[key] <= 0.0:
			return {ok = false}
	var radius: float = 0.5 * p.diameter_m
	var omega: float = rpm * TAU / 60.0
	var thrust: float = 0.0
	var torque: float = 0.0
	var dissipation: float = 0.0
	# Midpoint annuli, inner 20% excluded as a root/hub. Smooth flat-plate stall blend.
	var dr: float = radius * 0.8 / 12.0
	for i in 12:
		var r: float = radius * 0.2 + (i + 0.5) * dr
		var tangential: float = omega * r
		var speed_sq: float = tangential * tangential + axial_speed * axial_speed
		if speed_sq == 0.0:
			continue
		var speed: float = sqrt(speed_sq)
		var phi: float = M.atan2_(axial_speed, tangential)
		var beta: float = M.atan2_(p.pitch_m, TAU * r)
		var alpha: float = beta - phi
		var cl: float = p.lift_slope * M.sin_(2.0 * alpha) / 2.0
		# At large alpha lift is bounded; pressure drag increases to the flat-plate limit.
		cl = clampf(cl, -1.25, 1.25)
		var cd: float = p.cd0 + p.induced_drag * cl * cl + 1.2 * pow(M.sin_(alpha), 2.0)
		var area_pressure: float = 0.5 * rho * speed_sq * p.chord_m * dr * p.blades
		var lift: float = area_pressure * cl
		var drag: float = area_pressure * cd
		thrust += (lift * tangential - drag * axial_speed) / speed
		torque += (lift * axial_speed + drag * tangential) * r / speed
		dissipation += drag * speed
	return {ok = true, thrust_n = thrust, torque_nm = torque,
		shaft_power_w = torque * omega, thrust_power_w = thrust * axial_speed,
		dissipation_w = dissipation}
