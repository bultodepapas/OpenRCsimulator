## Detached accepted-state fuel telemetry. Never evaluates the solver or mutates a model.
extends RefCounted

const FORMAT := "openrc-mass-sample v1"

static func build(properties: Dictionary, tanks: Array, remaining: Dictionary,
		tick: int, time_s: float, finite: bool) -> Dictionary:
	if not properties.get("ok", false) or not is_finite(time_s) or time_s < 0.0 or tick < 0 \
			or not is_finite(float(properties.get("mass_kg", NAN))) or float(properties.mass_kg) <= 0.0 \
			or not properties.get("cg_body_m") is PackedFloat64Array or properties.cg_body_m.size() != 3:
		return {ok = false}
	var out: Dictionary = properties.duplicate(true)
	for key: String in ["cg_body_m", "inertia", "inverse"]:
		var values: Variant = properties.get(key)
		if not values is PackedFloat64Array or values.size() != (3 if key == "cg_body_m" else 6):
			return {ok = false}
		for value: float in values:
			if not is_finite(value):
				return {ok = false}
	out.format = FORMAT
	out.tick = tick
	out.time_s = time_s
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
	for tank: Dictionary in tanks:
		var id: String = str(tank.get("id", ""))
		if ids.has(id):
			return {ok = false}
		ids[id] = true
		var amount: float = float(remaining.get(id, NAN))
		var capacity: float = float(tank.get("capacity_kg", NAN))
		var unusable: float = float(tank.get("unusable_kg", NAN))
		var density: float = float(tank.get("density_kg_m3", NAN))
		var reserve: float = float(tank.get("reserve_kg", minf(capacity, unusable + 0.1 * capacity)))
		if id.is_empty() or not is_finite(amount) or amount < 0.0 or not is_finite(capacity) or capacity <= 0.0 \
				or amount > capacity * (1.0 + 1e-9) or not is_finite(unusable) or unusable < 0.0 or unusable >= capacity \
				or not is_finite(density) or density <= 0.0 or not is_finite(reserve) or reserve < unusable or reserve > capacity:
			return {ok = false}
		var volume: float = amount / density * 1.0e6
		var store: Dictionary = {id = id, blend = str(tank.get("fuel", "")), family = str(tank.get("family", "")),
			density_kg_m3 = density, capacity_kg = capacity, unusable_kg = unusable, remaining_kg = amount,
			usable_kg = maxf(0.0, amount - unusable), fill_fraction = amount / capacity,
			volume_ml = volume, reserve_fraction = reserve / capacity,
			reserve_estimated = bool(tank.get("reserve_estimated", true)), low_fuel = amount <= reserve}
		out.stores.append(store)
		total_remaining += amount
		out.fuel_capacity_kg += capacity
		out.fuel_usable_kg += store.usable_kg
		out.volume_ml += volume
		capacity_ml += capacity / density * 1.0e6
		reserve_ml += reserve / density * 1.0e6
		out.low_fuel = out.low_fuel or store.low_fuel
		out.reserve_estimated = out.reserve_estimated or store.reserve_estimated
	if tanks.is_empty() or remaining.size() != tanks.size():
		return {ok = false}
	out.fuel_remaining_kg = total_remaining
	out.fill_fraction = out.volume_ml / capacity_ml
	out.reserve_fraction = reserve_ml / capacity_ml
	out.reserve_basis = "estimated reserve" if out.reserve_estimated else "authored reserve"
	return out
