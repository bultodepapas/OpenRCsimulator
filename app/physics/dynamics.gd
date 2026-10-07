# Shared, pure aircraft load and rigid-body evaluator (D8a-R1).
# Inputs are derived aircraft data, state, actual aerodynamic surface angles, rpm, density, wind and gravity.
# Surface angles use Aero's data convention (radians: elevator/ailerons +TE down, rudder +TE left).
# Wind is world-frame NED. All simulation values remain float64.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Turbine := preload("res://physics/turbine.gd")
const Slipstream := preload("res://physics/slipstream.gd")


## Angular momentum of the spinning propeller/crankshaft, in body axes (clockwise from behind is +x; along the
## tilted shaft when the aircraft declares thrust angles).
static func rotor_momentum(model: Dictionary, rpm: float) -> PackedFloat64Array:
	if Turbine.is_turbine(model.propulsion): # AV-05: the spool, signed by its rotation sense
		return Turbine.rotor_momentum(rpm, model.propulsion)
	var h: float = float(model.propulsion.rotor_inertia) * rpm * TAU / 60.0
	if model.propulsion.has("axis"):
		return M.scale(model.propulsion.axis, h)
	return M.v3(h, 0.0, 0.0)


## Total body loads about the CG [Fx, Fy, Fz, Mx, My, Mz], with gravity excluded.
## `d` contains aerodynamic-convention deflections in radians; pass actual surfaces, not stick commands.
## downwash_cl: E0a2b's lagged wing CL for the tail (aux); NAN = quasi-static (trim, linearisation, static solves).
## transported_dv: E0b5's stage wash speed per piece; empty = quasi-static (including trim/static solves).
static func loads(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, wind_ned: PackedFloat64Array, downwash_cl := NAN, transported_dv := PackedFloat64Array()) -> PackedFloat64Array:
	return _load_components(state, model, d, rpm, rho, wind_ned, downwash_cl, transported_dv).loads


## Evaluate loads and the state derivative from the same physics calls.
## `rotor_h_body` optionally supplies an explicit rotor momentum; an empty array derives it from model and rpm.
## `downwash_cl` as in loads (D11g: the flight-mode linearisation carries the lag as a state).
## Returns { state, air, aero_loads, propulsion_loads, loads, rotor_momentum, derivative }.
static func evaluate(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, wind_ned: PackedFloat64Array, g: float,
		rotor_h_body := PackedFloat64Array(), downwash_cl := NAN) -> Dictionary:
	var components := _load_components(state, model, d, rpm, rho, wind_ned, downwash_cl)
	var h := rotor_h_body if not rotor_h_body.is_empty() else rotor_momentum(model, rpm)
	var total: PackedFloat64Array = components.loads
	var derivative := RB.derivative(state, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia),
		M.v3(total[0], total[1], total[2]), M.v3(total[3], total[4], total[5]), g, h)
	components["state"] = state
	components["rotor_momentum"] = h
	components["derivative"] = derivative
	return components


## Convenience derivative for callers that need only the state derivative.
static func derivative(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, wind_ned: PackedFloat64Array, g: float,
		rotor_h_body := PackedFloat64Array()) -> PackedFloat64Array:
	return evaluate(state, model, d, rpm, rho, wind_ned, g, rotor_h_body).derivative


static func _load_components(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, wind_ned: PackedFloat64Array, downwash_cl := NAN, transported_dv := PackedFloat64Array()) -> Dictionary:
	var air := Air.compute(state, wind_ned, rho)
	var aero_loads := Aero.loads(state, air, d, model, rho, downwash_cl)
	var propulsion_loads := Propulsion.loads(air.v_air, rpm, model.propulsion, rho)
	var total := aero_loads.duplicate()
	for i in 6:
		total[i] += propulsion_loads[i]
	# E0b (P51-12, opt-in): the propeller's slipstream on the tail surfaces. Absent data adds nothing at all.
	if not model.propulsion.get("slipstream", {}).is_empty():
		var wash := Slipstream.loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv)
		for i in 6:
			total[i] += wash[i]
	return {
		air = air,
		aero_loads = aero_loads,
		propulsion_loads = propulsion_loads,
		loads = total,
	}
