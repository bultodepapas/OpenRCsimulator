## FUEL-08 finite liquid stores and combustion flow laws. Stage callers pass absolute onboard mass;
## the fixed-datum inventory varies only usable liquid, so declared residue remains aboard after exhaustion.
extends RefCounted

const MassInventory := preload("res://physics/mass_inventory.gd")
const Turbine := preload("res://physics/turbine.gd")

const FORMAT := "openrc-liquid-fuel v1"
const GASOLINE_LAW := "gasoline_bsfc_v1"
const TURBINE_LAW := "turbine_map_v1"


## Evaluate stores at absolute onboard amounts in kg (usable liquid + unusable residue).
## Values below unusable are treated as an exhausted usable store while preserving its physical residue.
## Omitted stores remain at their authored reference amounts; unknown IDs and amounts above capacity fail.
static func properties(adapter: Dictionary, onboard_kg_by_tank: Dictionary) -> Dictionary:
	if adapter.get("format", "") != FORMAT:
		return _failure("liquid-fuel adapter format is unsupported")
	var prepared: Dictionary = adapter.get("prepared_inventory", {})
	if not prepared.get("ok", false):
		return _failure("liquid-fuel mass reference is not prepared")
	var store_ids: PackedStringArray = adapter.get("store_ids", PackedStringArray())
	var stores: Dictionary = adapter.get("stores_by_id", {})
	if store_ids.is_empty() or stores.is_empty():
		return _failure("liquid-fuel adapter has no normalized stores")
	for key: Variant in onboard_kg_by_tank.keys():
		if not stores.has(String(key)):
			return _failure("unknown tank id '%s'" % String(key))

	var usable_amounts := PackedFloat64Array()
	var reported: Dictionary = {}
	for tank_id: String in store_ids:
		var store: Variant = stores.get(tank_id, null)
		if not store is Dictionary:
			return _failure("normalized store '%s' is missing" % tank_id)
		var capacity: float = float(store.get("capacity_kg", NAN))
		var unusable: float = float(store.get("unusable_kg", NAN))
		var reference: float = float(store.get("reference_kg", NAN))
		var requested: Variant = onboard_kg_by_tank.get(tank_id, reference)
		if not _finite_number(requested) or not is_finite(capacity) or not is_finite(unusable) \
				or not is_finite(reference) or capacity <= 0.0 or unusable < 0.0 or unusable >= capacity \
				or float(requested) < 0.0 or float(requested) > capacity:
			return _failure("tank '%s' onboard mass must be finite and within [0, capacity]" % tank_id)
		var requested_onboard: float = float(requested)
		var effective_onboard: float = maxf(requested_onboard, unusable)
		var usable: float = clampf(effective_onboard - unusable, 0.0, capacity - unusable)
		usable_amounts.append(usable)
		reported[tank_id] = {
			requested_onboard_kg = requested_onboard,
			onboard_kg = effective_onboard,
			usable_kg = usable,
			unusable_kg = unusable,
			capacity_kg = capacity,
			below_unusable = requested_onboard < unusable,
		}
	var result: Dictionary = MassInventory.evaluate_reference(prepared, usable_amounts)
	if not result.get("ok", false):
		return _failure("liquid-fuel mass evaluation failed: " + str(result.get("error", "unknown error")))
	result.store_amounts_by_id = reported
	return result


## Outflow for a running source in kg/s. Stopped engines consume zero; gas negative/windmilling shaft
## power is floored at the explicit idle estimate, while a turbine uses its authored RPM flow map.
## Invalid operating-point data returns NAN so a stage cannot silently accept a missing flow law.
static func flow_rate_kg_s(adapter: Dictionary, operating_point: Dictionary) -> float:
	if adapter.get("format", "") != FORMAT:
		return NAN
	var running: Variant = operating_point.get("running", null)
	if typeof(running) != TYPE_BOOL:
		return NAN
	if not bool(running):
		return 0.0
	match String(adapter.get("law", "")):
		GASOLINE_LAW:
			var shaft_power: Variant = operating_point.get("shaft_power_w", NAN)
			var bsfc: float = float(adapter.get("bsfc_kg_kwh", NAN))
			var idle_power: float = float(adapter.get("idle_power_w", NAN))
			var idle_flow: float = float(adapter.get("idle_flow_kg_s", NAN))
			if not _finite_number(shaft_power) or not is_finite(bsfc) or not is_finite(idle_power) \
					or not is_finite(idle_flow) or bsfc <= 0.0 or idle_power < 0.0 or idle_flow < 0.0:
				return NAN
			var result: float = idle_flow + maxf(float(shaft_power) - idle_power, 0.0) * bsfc / 3_600_000.0
			return result if is_finite(result) and result >= 0.0 else NAN
		TURBINE_LAW:
			var rpm: Variant = operating_point.get("rpm", NAN)
			var table: Variant = adapter.get("fuel_flow_kg_s_by_rpm", PackedFloat64Array())
			if not _finite_number(rpm) or float(rpm) < 0.0 or not table is PackedFloat64Array or table.size() < 4:
				return NAN
			return Turbine.fuel_flow(float(rpm), {fuel_flow = table})
		_:
			return NAN


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _failure(message: String) -> Dictionary:
	return {ok = false, error = message}
