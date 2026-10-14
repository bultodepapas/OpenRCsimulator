extends RefCounted


## Existing sampled servo law, with the original arithmetic order. Callers of this
## hot scalar path own validation. Zero rate holds the actual position, not demand.
static func rate_limit(value: float, target: float, rate: float, dt: float) -> float:
	var max_step := rate * dt
	return value + clampf(target - value, -max_step, max_step)


## Prepare detached normalized actuator positions. This kernel does not establish
## installed hardware, mixing, a clock or a checkpoint layout. The owner commits
## the returned candidate only after its complete simulation step is accepted.
## Nominal rates are neutral-to-full travel per second; optional factors in [0,1]
## represent reduced rate or a jam (0). An empty result rejects the entire input.
static func step_normalized(actual: PackedFloat64Array, demand: PackedFloat64Array,
		rates: PackedFloat64Array, dt: float,
		rate_factors := PackedFloat64Array()) -> PackedFloat64Array:
	var count := actual.size()
	if count == 0 or demand.size() != count or rates.size() != count \
			or (not rate_factors.is_empty() and rate_factors.size() != count) \
			or not is_finite(dt) or dt < 0.0:
		return PackedFloat64Array()
	for index in count:
		var factor: float = 1.0 if rate_factors.is_empty() else rate_factors[index]
		if not is_finite(actual[index]) or absf(actual[index]) > 1.0 \
				or not is_finite(demand[index]) or absf(demand[index]) > 1.0 \
				or not is_finite(rates[index]) or rates[index] <= 0.0 \
				or not is_finite(factor) or factor < 0.0 or factor > 1.0 \
				or not is_finite((rates[index] * factor) * dt):
			return PackedFloat64Array()
	var candidate := PackedFloat64Array()
	candidate.resize(count)
	for index in count:
		var rate: float = rates[index] if rate_factors.is_empty() else rates[index] * rate_factors[index]
		candidate[index] = rate_limit(actual[index], demand[index], rate, dt)
	return candidate
