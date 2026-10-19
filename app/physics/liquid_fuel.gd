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
	var prepared_value: Variant = adapter.get("prepared_inventory", null)
	if not prepared_value is Dictionary:
		return _failure("liquid-fuel mass reference is not prepared")
	var prepared: Dictionary = prepared_value
	if typeof(prepared.get("ok", false)) != TYPE_BOOL or not prepared.get("ok", false):
		return _failure("liquid-fuel mass reference is not prepared")
	var store_ids_value: Variant = adapter.get("store_ids", null)
	var stores_value: Variant = adapter.get("stores_by_id", null)
	if not store_ids_value is PackedStringArray or not stores_value is Dictionary:
		return _failure("liquid-fuel adapter has malformed normalized stores")
	var store_ids: PackedStringArray = store_ids_value
	var stores: Dictionary = stores_value
	var resources_value: Variant = prepared.get("resources", null)
	if store_ids.is_empty() or not resources_value is Array or stores.is_empty():
		return _failure("liquid-fuel adapter has no normalized stores")
	var prepared_resources: Array = resources_value
	if prepared_resources.size() != store_ids.size() or stores.size() != store_ids.size():
		return _failure("liquid-fuel store ids do not match the prepared inventory")
	var store_ids_seen: Dictionary = {}
	for tank_id: String in store_ids:
		if tank_id.is_empty() or store_ids_seen.has(tank_id) or not stores.has(tank_id):
			return _failure("liquid-fuel store ids must uniquely match normalized stores")
		store_ids_seen[tank_id] = true
	var prepared_ids_seen: Dictionary = {}
	for prepared_index: int in prepared_resources.size():
		var resource_value: Variant = prepared_resources[prepared_index]
		if not resource_value is Dictionary:
			return _failure("liquid-fuel prepared resource is malformed")
		var resource_id: Variant = resource_value.get("id", null)
		if not resource_id is String or not store_ids_seen.has(resource_id) or prepared_ids_seen.has(resource_id):
			return _failure("liquid-fuel prepared resource ids do not match normalized stores")
		prepared_ids_seen[resource_id] = true
	if prepared_ids_seen.size() != store_ids_seen.size():
		return _failure("liquid-fuel prepared resource ids do not match normalized stores")
	var reference_mass: Variant = prepared.get("reference_mass_kg", null)
	var references_value: Variant = prepared.get("references", null)
	var capacities_value: Variant = prepared.get("capacities", null)
	var centers_value: Variant = prepared.get("centers", null)
	var tensors_value: Variant = prepared.get("tensors", null)
	var count: int = prepared_resources.size()
	if prepared.get("law", "") != MassInventory.REFERENCE_LAW or not _finite_number(reference_mass) \
			or float(reference_mass) <= 0.0 or not references_value is PackedFloat64Array \
			or not capacities_value is PackedFloat64Array or not centers_value is Array or not tensors_value is Array \
			or references_value.size() != count or capacities_value.size() != count \
			or centers_value.size() != count or tensors_value.size() != count:
		return _failure("liquid-fuel prepared inventory is malformed")
	for i: int in count:
		var reference: float = references_value[i]
		var usable_capacity: float = capacities_value[i]
		var center: Variant = centers_value[i]
		var tensor: Variant = tensors_value[i]
		if not is_finite(reference) or reference < 0.0 or not is_finite(usable_capacity) \
				or usable_capacity <= 0.0 or reference > usable_capacity \
				or not center is PackedFloat64Array or center.size() != 3 \
				or not tensor is PackedFloat64Array or tensor.size() != 6:
			return _failure("liquid-fuel prepared inventory is malformed")
		for value: float in center:
			if not is_finite(value):
				return _failure("liquid-fuel prepared inventory is malformed")
		for value: float in tensor:
			if not is_finite(value):
				return _failure("liquid-fuel prepared inventory is malformed")
	for key: Variant in onboard_kg_by_tank.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not store_ids_seen.has(String(key)):
			return _failure("unknown tank id '%s'" % String(key))

	var usable_amounts := PackedFloat64Array()
	var reported: Dictionary = {}
	for prepared_index: int in prepared_resources.size():
		var resource_value: Variant = prepared_resources[prepared_index]
		var resource: Dictionary = resource_value
		var tank_id: String = resource.id
		var store: Variant = stores.get(tank_id, null)
		if not store is Dictionary or store.get("id", null) != tank_id:
			return _failure("normalized store '%s' is missing or mismatched" % tank_id)
		var capacity_value: Variant = store.get("capacity_kg", null)
		var unusable_value: Variant = store.get("unusable_kg", null)
		var reference_value: Variant = store.get("reference_kg", null)
		if not _finite_number(capacity_value) or not _finite_number(unusable_value) or not _finite_number(reference_value):
			return _failure("normalized store '%s' has invalid mass fields" % tank_id)
		var capacity: float = float(capacity_value)
		var unusable: float = float(unusable_value)
		var reference: float = float(reference_value)
		var requested: Variant = onboard_kg_by_tank.get(tank_id, reference)
		if not _finite_number(requested) or capacity <= 0.0 or unusable < 0.0 or unusable >= capacity \
				or reference < 0.0 or reference > capacity \
				or float(requested) < 0.0 or float(requested) > capacity:
			return _failure("tank '%s' onboard mass must be finite and within [0, capacity]" % tank_id)
		var expected_usable_capacity: float = capacity - unusable
		var expected_reference: float = maxf(reference - unusable, 0.0)
		if not is_equal_approx(capacities_value[prepared_index], expected_usable_capacity) \
				or not is_equal_approx(references_value[prepared_index], expected_reference):
			return _failure("normalized store '%s' does not match its prepared resource" % tank_id)
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
			var bsfc_value: Variant = adapter.get("bsfc_kg_kwh", null)
			var idle_power_value: Variant = adapter.get("idle_power_w", null)
			var idle_flow_value: Variant = adapter.get("idle_flow_kg_s", null)
			if not _finite_number(shaft_power) or not _finite_number(bsfc_value) \
					or not _finite_number(idle_power_value) or not _finite_number(idle_flow_value):
				return NAN
			var bsfc: float = float(bsfc_value)
			var idle_power: float = float(idle_power_value)
			var idle_flow: float = float(idle_flow_value)
			if bsfc <= 0.0 or idle_power < 0.0 or idle_flow < 0.0:
				return NAN
			var result: float = idle_flow + maxf(float(shaft_power) - idle_power, 0.0) * bsfc / 3_600_000.0
			return result if is_finite(result) and result >= 0.0 else NAN
		TURBINE_LAW:
			var rpm: Variant = operating_point.get("rpm", NAN)
			var table: Variant = adapter.get("fuel_flow_kg_s_by_rpm", PackedFloat64Array())
			if not _finite_number(rpm) or float(rpm) < 0.0 or not table is PackedFloat64Array or table.size() < 4:
				return NAN
			for value: float in table:
				if not is_finite(value) or value < 0.0:
					return NAN
			var result: float = Turbine.fuel_flow(float(rpm), {fuel_flow = table})
			return result if is_finite(result) and result >= 0.0 else NAN
		_:
			return NAN


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _failure(message: String) -> Dictionary:
	return {ok = false, error = message}
