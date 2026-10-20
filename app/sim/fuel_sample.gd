## Detached accepted-state fuel telemetry. Never evaluates the solver or mutates a model.
extends RefCounted

const FORMAT := "openrc-mass-sample v1"

static func build(properties: Dictionary, tanks: Array, remaining: Dictionary,
		tick: Variant, time_s: Variant, finite: Variant) -> Dictionary:
	var properties_ok: Variant = properties.get("ok", null)
	var mass_value: Variant = properties.get("mass_kg", null)
	if typeof(properties_ok) != TYPE_BOOL or not properties_ok or not _finite_number(mass_value) \
			or float(mass_value) <= 0.0 or typeof(tick) != TYPE_INT or tick < 0 or typeof(finite) != TYPE_BOOL \
			or not _finite_number(time_s) or float(time_s) < 0.0 \
			or not _finite_packed(properties.get("cg_body_m", null), 3) \
			or not _finite_packed(properties.get("inertia", null), 6) \
			or not _finite_packed(properties.get("inverse", null), 6):
		return {ok = false}
	var out: Dictionary = properties.duplicate(true)
	out.format = FORMAT
	out.tick = tick
	out.time_s = float(time_s)
	out.finite_fuel = finite
	out.stores = []
	out.fuel_remaining_kg = NAN
	out.fuel_capacity_kg = 0.0
	out.fuel_usable_kg = 0.0
	out.volume_ml = 0.0
	out.fill_fraction = 0.0
	out.reserve_fraction = 0.0
	out.low_fuel = false
	out.reserve_estimated = false
	out.reserve_basis = "none"
	if not finite:
		return out
	var total_remaining := 0.0
	var capacity_ml := 0.0
	var reserve_ml := 0.0
	var ids := {}
	for tank_value: Variant in tanks:
		if not tank_value is Dictionary:
			return {ok = false}
		var tank: Dictionary = tank_value
		var id_value: Variant = tank.get("id", null)
		var kind_value: Variant = tank.get("kind", "tank")
		var fuel_value: Variant = tank.get("fuel", "")
		var family_value: Variant = tank.get("family", "")
		if not id_value is String or id_value.is_empty() or ids.has(id_value) \
				or not kind_value is String or not fuel_value is String or not family_value is String:
			return {ok = false}
		var id: String = id_value
		ids[id] = true
		var amount_value: Variant = remaining.get(id, null)
		var capacity_value: Variant = tank.get("capacity_kg", null)
		var unusable_value: Variant = tank.get("unusable_kg", null)
		var density_value: Variant = tank.get("density_kg_m3", null)
		if not _finite_number(amount_value) or not _finite_number(capacity_value) \
				or not _finite_number(unusable_value) or not _finite_number(density_value):
			return {ok = false}
		var amount: float = float(amount_value)
		var capacity: float = float(capacity_value)
		var unusable: float = float(unusable_value)
		var density: float = float(density_value)
		if not is_finite(amount) or amount < 0.0 or not is_finite(capacity) or capacity <= 0.0 \
				or not is_finite(unusable) or unusable < 0.0 or unusable >= capacity \
				or not is_finite(density) or density <= 0.0:
			return {ok = false}
		var capacity_tolerance: float = capacity * 1.0e-9
		if capacity - amount < -capacity_tolerance or amount - unusable < -capacity_tolerance:
			return {ok = false}
		amount = clampf(amount, unusable, capacity)
		var reserve_value: Variant = tank.get("reserve_kg", minf(capacity, unusable + 0.1 * capacity))
		var reserve_estimated_value: Variant = tank.get("reserve_estimated", true)
		if not _finite_number(reserve_value) or typeof(reserve_estimated_value) != TYPE_BOOL:
			return {ok = false}
		var reserve: float = float(reserve_value)
		if not is_finite(reserve) or reserve < unusable or reserve > capacity:
			return {ok = false}
		var volume: float = amount / density * 1.0e6
		var store_capacity_ml: float = capacity / density * 1.0e6
		var store_reserve_ml: float = reserve / density * 1.0e6
		if not is_finite(volume) or volume < 0.0 or not is_finite(store_capacity_ml) \
				or store_capacity_ml <= 0.0 or not is_finite(store_reserve_ml) or store_reserve_ml < 0.0:
			return {ok = false}
		var usable: float = maxf(0.0, amount - unusable)
		var store: Dictionary = {id = id, kind = kind_value, blend = fuel_value, family = family_value,
			density_kg_m3 = density, capacity_kg = capacity, unusable_kg = unusable, remaining_kg = amount,
			usable_kg = usable, fill_fraction = amount / capacity,
			volume_ml = volume, reserve_fraction = reserve / capacity,
			reserve_estimated = reserve_estimated_value, low_fuel = kind_value != "feed_line" and amount <= reserve}
		out.stores.append(store)
		total_remaining += amount
		out.fuel_capacity_kg += capacity
		out.fuel_usable_kg += usable
		out.volume_ml += volume
		capacity_ml += store_capacity_ml
		reserve_ml += store_reserve_ml
		out.low_fuel = out.low_fuel or store.low_fuel
		out.reserve_estimated = out.reserve_estimated or store.reserve_estimated
		if not is_finite(total_remaining) or not is_finite(out.fuel_capacity_kg) \
				or not is_finite(out.fuel_usable_kg) or not is_finite(out.volume_ml) \
				or not is_finite(capacity_ml) or not is_finite(reserve_ml):
			return {ok = false}
	if tanks.is_empty() or remaining.size() != tanks.size():
		return {ok = false}
	for key: Variant in remaining.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not ids.has(String(key)):
			return {ok = false}
	if capacity_ml <= 0.0:
		return {ok = false}
	out.fuel_remaining_kg = total_remaining
	out.fill_fraction = clampf(out.volume_ml / capacity_ml, 0.0, 1.0)
	out.reserve_fraction = clampf(reserve_ml / capacity_ml, 0.0, 1.0)
	out.reserve_basis = "estimated reserve" if out.reserve_estimated else "authored reserve"
	return out


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _finite_packed(value: Variant, expected_size: int) -> bool:
	if not value is PackedFloat64Array or value.size() != expected_size:
		return false
	for entry: float in value:
		if not is_finite(entry):
			return false
	return true
