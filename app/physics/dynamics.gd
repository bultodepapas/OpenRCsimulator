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
## ground_up: M5-GE-1 ground height under the CG (m above the NED datum) for the aero ground-effect module;
## NAN = out of ground effect (trim, linearisation, static solves and aircraft without the module).
static func loads(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, wind_ned: PackedFloat64Array, downwash_cl := NAN, transported_dv := PackedFloat64Array(),
		ground_up := NAN) -> PackedFloat64Array:
	return _load_components(state, model, d, rpm, rho, wind_ned, downwash_cl, transported_dv, ground_up).loads


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
		rho: float, wind_ned: PackedFloat64Array, downwash_cl := NAN, transported_dv := PackedFloat64Array(),
		ground_up := NAN) -> Dictionary:
	var air := Air.compute(state, wind_ned, rho)
	return _components_from_air(state, model, d, rpm, rho, air, downwash_cl, transported_dv, ground_up)


## Share one stage's air data with the shaft solve. `air` must be Air.compute for this
## exact state, wind and density; never reuse it across RK stages or simulation ticks.
## `stage_propulsion_loads`, when supplied, has the same requirement and is body
## force/moment about the reference CG. Empty retains the independent evaluation.
## `stage_thrust_torque` ([N, N·m], EX-14c) is that same stage's propeller result; a Glow slipstream needs it with
## `stage_propulsion_loads` so the wake carries the shaft's thrust and torque.
static func loads_from_air(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, air: Dictionary, downwash_cl := NAN, transported_dv := PackedFloat64Array(),
		ground_up := NAN, stage_propulsion_loads := PackedFloat64Array(),
		stage_thrust_torque := PackedFloat64Array()) -> PackedFloat64Array:
	return _components_from_air(state, model, d, rpm, rho, air, downwash_cl, transported_dv, ground_up, stage_propulsion_loads,
		stage_thrust_torque).loads


static func _components_from_air(state: PackedFloat64Array, model: Dictionary, d: Dictionary, rpm: float,
		rho: float, air: Dictionary, downwash_cl: float, transported_dv: PackedFloat64Array,
		ground_up := NAN, stage_propulsion_loads := PackedFloat64Array(),
		stage_thrust_torque := PackedFloat64Array()) -> Dictionary:
	var aero_loads := Aero.loads(state, air, d, model, rho, downwash_cl, ground_up)
	var washed: bool = not model.propulsion.get("slipstream", {}).is_empty()
	var wake_thrust_torque: PackedFloat64Array = stage_thrust_torque
	# Powered-device loads use their local inflow point: the turbine intake and the Glow propeller hub.
	# The stage-reuse route already evaluated that same point; other legacy routes retain their convention.
	var propulsion_loads: PackedFloat64Array = stage_propulsion_loads
	if propulsion_loads.is_empty():
		var prop_air: PackedFloat64Array = air.v_air
		if Turbine.is_turbine(model.propulsion):
			prop_air = Turbine.local_intake_velocity(air.v_air, state.slice(RB.RATE, RB.RATE + 3), model.propulsion)
		elif Propulsion.is_glow(model.propulsion):
			prop_air = Propulsion.hub_air_velocity(state, air.v_air, model.propulsion.offset)
		if washed and Propulsion.is_glow(model.propulsion):
			# EX-14c: one hub evaluation feeds the shaft loads and the wake, exactly as the Glow stage route does.
			wake_thrust_torque = Propulsion.thrust_torque(prop_air, rpm, model.propulsion, rho).slice(0, 2)
			propulsion_loads = Propulsion.loads_from_thrust_torque(prop_air, rpm, model.propulsion, rho,
				wake_thrust_torque[0], wake_thrust_torque[1])
		else:
			propulsion_loads = Propulsion.loads(prop_air, rpm, model.propulsion, rho)
	var total := aero_loads.duplicate()
	for i in 6:
		total[i] += propulsion_loads[i]
	# E0b (P51-12, opt-in): the propeller's slipstream on the tail surfaces. Absent data adds nothing at all.
	if washed:
		var wash := Slipstream.stage_loads(state, air, d, model, rpm, rho, downwash_cl, transported_dv, 1, wake_thrust_torque)
		for i in 6:
			total[i] += wash[i]
	return {
		air = air,
		aero_loads = aero_loads,
		propulsion_loads = propulsion_loads,
		loads = total,
	}
