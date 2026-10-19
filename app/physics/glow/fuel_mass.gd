## NITRO: uniform rigid tank contents, co-moving distributed efflux, no slosh/jet thrust.
## Body state remains at the initial wet CG datum; geometry never jumps as fuel burns.
## FUEL-04: a thin glow adapter. The law lives in the shared kernels: MassInventory.prepare_reference /
## evaluate_reference (mass properties) and FixedDatumBody.derivative (dynamics). Results are bit-identical
## to the historical implementation.
extends RefCounted
const MassInventory := preload("res://physics/mass_inventory.gd")
const FixedDatumBody := preload("res://physics/fixed_datum_body.gd")

const RESOURCE_ID := "glow_fuel"

static func tensor_per_kg(position: PackedFloat64Array, size: PackedFloat64Array) -> PackedFloat64Array:
	return MassInventory.rectangular_box_per_kg(position, size)

## Prepared single-tank reference: the wet aircraft holds `initial_fuel` in the tank; the tank may not exceed it.
static func prepare(wet_mass: float, wet_inertia: PackedFloat64Array, initial_fuel: float,
		tank_position: PackedFloat64Array, tank_size: PackedFloat64Array) -> Dictionary:
	if wet_inertia.size() != 6 or tank_position.size() != 3 or tank_size.size() != 3:
		return {ok = false}
	return MassInventory.prepare_reference(wet_mass, wet_inertia, [{id = RESOURCE_ID,
		reference_mass_kg = initial_fuel, capacity_mass_kg = initial_fuel,
		center_body_m = tank_position, size_body_m = tank_size}])

static func evaluate(wet_mass: float, wet_inertia: PackedFloat64Array, initial_fuel: float,
		remaining: float, tank_position: PackedFloat64Array, tank_size: PackedFloat64Array) -> Dictionary:
	var prepared: Dictionary = prepare(wet_mass, wet_inertia, initial_fuel, tank_position, tank_size)
	if not prepared.get("ok", false):
		return {ok = false}
	return MassInventory.evaluate_reference(prepared, PackedFloat64Array([remaining]))

## Convert a derivative evaluated for CM acceleration into the fixed datum's acceleration.
static func datum_derivative(s: PackedFloat64Array, properties: Dictionary, force: PackedFloat64Array,
		moment_cm: PackedFloat64Array, gravity: float, rotor: PackedFloat64Array) -> PackedFloat64Array:
	return FixedDatumBody.derivative(s, properties, force, moment_cm, gravity, rotor)
