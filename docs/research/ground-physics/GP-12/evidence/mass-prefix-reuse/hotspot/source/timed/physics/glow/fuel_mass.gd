## NITRO: uniform rigid tank contents, co-moving distributed efflux, no slosh/jet thrust.
## Body state remains at the initial wet CG datum; geometry never jumps as fuel burns.
## FUEL-04: a thin glow adapter. The law lives in the shared kernels: MassInventory.prepare_reference /
## evaluate_reference (mass properties) and FixedDatumBody.derivative (dynamics). Results are bit-identical
## to the historical implementation.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")
const MassInventory := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/mass_inventory.gd")
const FixedDatumBody := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/fixed_datum_body.gd")

const RESOURCE_ID := "glow_fuel"
const FLOAT64_EPSILON := 2.220446049250313e-16
const CAPACITY_ROUNDING_EPSILONS := 4.0


## Blend-derived capacity and inventory mass can differ by a few float64 rounding steps
## when an authored tank is exactly full. Canonicalize only that arithmetic noise;
## meaningful over-capacity references remain invalid in MassInventory.
static func _roundoff_safe_capacity(reference_fuel: float, capacity_fuel: float) -> float:
	if not is_finite(reference_fuel) or not is_finite(capacity_fuel) or reference_fuel <= capacity_fuel:
		return capacity_fuel
	var tolerance: float = CAPACITY_ROUNDING_EPSILONS * FLOAT64_EPSILON \
		* maxf(absf(reference_fuel), absf(capacity_fuel))
	return reference_fuel if reference_fuel - capacity_fuel <= tolerance else capacity_fuel

static func tensor_per_kg(position: PackedFloat64Array, size: PackedFloat64Array) -> PackedFloat64Array:
	return MassInventory.rectangular_box_per_kg(position, size)

## Prepared single-tank reference. `reference_fuel` is the amount in the authored wet
## aircraft; `capacity_fuel` may be higher when the authored inventory is not full.
static func prepare(wet_mass: float, wet_inertia: PackedFloat64Array, reference_fuel: float,
		tank_position: PackedFloat64Array, tank_size: PackedFloat64Array,
		capacity_fuel: float = -1.0, tank_id: String = RESOURCE_ID) -> Dictionary:
	if wet_inertia.size() != 6 or tank_position.size() != 3 or tank_size.size() != 3:
		return {ok = false}
	var capacity: float = reference_fuel if capacity_fuel < 0.0 else capacity_fuel
	capacity = _roundoff_safe_capacity(reference_fuel, capacity)
	return MassInventory.prepare_reference(wet_mass, wet_inertia, [{id = tank_id,
		reference_mass_kg = reference_fuel, capacity_mass_kg = capacity,
		center_body_m = tank_position, size_body_m = tank_size}])


## Multi-resource fixed-reference form used only when a Glow installation has a separate finite feed-line store.
## The one-resource path above remains operation-for-operation compatible with existing aircraft.
static func prepare_resources(wet_mass: float, wet_inertia: PackedFloat64Array,
		resources: Array) -> Dictionary:
	if wet_inertia.size() != 6 or resources.is_empty():
		return {ok = false, error = "Glow resource reference is malformed"}
	var normalized: Array = []
	for value: Variant in resources:
		if not value is Dictionary:
			normalized.append(value)
			continue
		var resource: Dictionary = value.duplicate(true)
		var reference: Variant = resource.get("reference_mass_kg", null)
		var capacity: Variant = resource.get("capacity_mass_kg", null)
		if typeof(reference) in [TYPE_FLOAT, TYPE_INT] and typeof(capacity) in [TYPE_FLOAT, TYPE_INT]:
			resource.capacity_mass_kg = _roundoff_safe_capacity(float(reference), float(capacity))
		normalized.append(resource)
	return MassInventory.prepare_reference(wet_mass, wet_inertia, normalized)

static func evaluate(wet_mass: float, wet_inertia: PackedFloat64Array, reference_fuel: float,
		remaining: float, tank_position: PackedFloat64Array, tank_size: PackedFloat64Array,
		capacity_fuel: float = -1.0, tank_id: String = RESOURCE_ID) -> Dictionary:
	var prepared: Dictionary = prepare(wet_mass, wet_inertia, reference_fuel, tank_position, tank_size,
		capacity_fuel, tank_id)
	if not prepared.get("ok", false):
		return {ok = false}
	return MassInventory.evaluate_reference(prepared, PackedFloat64Array([remaining]))


static func evaluate_resources(prepared: Dictionary, amounts: PackedFloat64Array) -> Dictionary:
	return MassInventory.evaluate_reference(prepared, amounts)

## Convert a derivative evaluated for CM acceleration into the fixed datum's acceleration.
static func datum_derivative(s: PackedFloat64Array, properties: Dictionary, force: PackedFloat64Array,
		moment_cm: PackedFloat64Array, gravity: float, rotor: PackedFloat64Array) -> PackedFloat64Array:
	return FixedDatumBody.derivative(s, properties, force, moment_cm, gravity, rotor)
