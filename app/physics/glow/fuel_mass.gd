## NITRO: uniform rigid tank contents, co-moving distributed efflux, no slosh/jet thrust.
## Body state remains at the initial wet CG datum; geometry never jumps as fuel burns.
extends RefCounted
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const MassInventory := preload("res://physics/mass_inventory.gd")

static func tensor_per_kg(position: PackedFloat64Array, size: PackedFloat64Array) -> PackedFloat64Array:
	return MassInventory.rectangular_box_per_kg(position, size)

static func evaluate(wet_mass: float, wet_inertia: PackedFloat64Array, initial_fuel: float,
		remaining: float, tank_position: PackedFloat64Array, tank_size: PackedFloat64Array) -> Dictionary:
	if wet_inertia.size() != 6 or tank_position.size() != 3 or tank_size.size() != 3:
		return {ok = false}
	for value in [wet_mass, initial_fuel, remaining]:
		if not is_finite(value): return {ok = false}
	if initial_fuel < 0.0 or remaining < 0.0 or remaining > initial_fuel or wet_mass <= initial_fuel:
		return {ok = false}
	for value in wet_inertia + tank_position + tank_size:
		if not is_finite(value): return {ok = false}
	for value in tank_size:
		if value < 0.0: return {ok = false}
	var removed: float = initial_fuel - remaining
	var mass: float = wet_mass - removed
	var cg: PackedFloat64Array = M.scale(tank_position, -removed / mass)
	var inertia_origin: PackedFloat64Array = wet_inertia.duplicate()
	var tank_tensor: PackedFloat64Array = tensor_per_kg(tank_position, tank_size)
	var parallel: PackedFloat64Array = tensor_per_kg(cg, PackedFloat64Array([0.,0.,0.]))
	var inertia: PackedFloat64Array = wet_inertia.duplicate()
	for i in 6:
		inertia_origin[i] -= removed * tank_tensor[i]
		inertia[i] = inertia_origin[i] - mass * parallel[i]
	var inverse: PackedFloat64Array = RB.inertia_inverse(inertia)
	if inertia[0] <= 0.0 or inertia[0]*inertia[1]-inertia[3]*inertia[3] <= 0.0:
		return {ok = false}
	var determinant: float = inertia[0]*(inertia[1]*inertia[2]-inertia[5]*inertia[5])-inertia[3]*(inertia[3]*inertia[2]-inertia[4]*inertia[5])+inertia[4]*(inertia[3]*inertia[5]-inertia[4]*inertia[1])
	if determinant <= 0.0: return {ok = false}
	for v in inverse:
		if not is_finite(v): return {ok = false}
	return {ok = true, mass_kg = mass, cg_body_m = cg, inertia = inertia, inverse = inverse, inertia_origin = inertia_origin}

## Convert a derivative evaluated for CM acceleration into the fixed datum's acceleration.
## Co-moving efflux cancels dm/dt and dI/dt terms; adding -I_dot*omega would create spin-up.
static func datum_derivative(s: PackedFloat64Array, properties: Dictionary, force: PackedFloat64Array,
		moment_cm: PackedFloat64Array, gravity: float, rotor: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = RB.derivative(s, properties.mass_kg, properties.inertia, properties.inverse,
		force, moment_cm, gravity, rotor)
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE+3)
	var alpha: PackedFloat64Array = out.slice(RB.RATE, RB.RATE+3)
	var correction: PackedFloat64Array = M.add(M.cross(alpha, properties.cg_body_m), M.cross(w, M.cross(w, properties.cg_body_m)))
	for i in 3: out[RB.VEL+i] -= correction[i]
	return out
