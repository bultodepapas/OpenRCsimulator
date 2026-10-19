## FUEL-04: rigid-body derivative of a finite-resource vehicle whose state is referenced to a fixed body datum O
## (the CG of its authored state) while its mass, CG and inertia change. Shared by every finite-fuel law.
## Co-moving efflux: departing fuel leaves with the velocity of the body point it leaves from, so it adds no
## thrust-like reaction, no jet damping and no dm/dt or dI/dt term; adding -İω would create spin-up.
## Moved verbatim from the glow FuelMass (NITRO-02); verified by test_glow_flight_physics and
## test_fuel_mass_reference (momentum of body plus ejected fuel is conserved).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const LAW := "fixed-datum-co-moving-efflux-v1"


## Convert a derivative evaluated for CM acceleration into the fixed datum's acceleration.
## `properties` is one MassInventory.evaluate_reference sample {mass_kg, cg_body_m, inertia, inverse}.
static func derivative(s: PackedFloat64Array, properties: Dictionary, force: PackedFloat64Array,
		moment_cm: PackedFloat64Array, gravity: float, rotor: PackedFloat64Array) -> PackedFloat64Array:
	var out: PackedFloat64Array = RB.derivative(s, properties.mass_kg, properties.inertia, properties.inverse,
		force, moment_cm, gravity, rotor)
	var w: PackedFloat64Array = s.slice(RB.RATE, RB.RATE+3)
	var alpha: PackedFloat64Array = out.slice(RB.RATE, RB.RATE+3)
	var correction: PackedFloat64Array = M.add(M.cross(alpha, properties.cg_body_m), M.cross(w, M.cross(w, properties.cg_body_m)))
	for i in 3: out[RB.VEL+i] -= correction[i]
	return out
