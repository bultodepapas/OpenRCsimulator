extends RefCounted
## Explicit new normalized servo trajectory. Historical sampled arithmetic is unchanged.
## One shared binary64 distance/rate arrival owns the endpoint, stages and interior cuts.
## Reached targets use the exact target bits; numeric no-motion (including +/-0) holds start bits.
## No epsilon snapping/merging is performed. Clock resolution is checked by the step composer.
const Actuators := preload("res://physics/control_actuators.gd")
const LAW := "normalized-slew-arrivals-v1"
const MAX_CHANNELS := 3


static func prepare(actual: PackedFloat64Array, demand: PackedFloat64Array,
		rates: PackedFloat64Array, dt: float) -> Dictionary:
	if actual.is_empty() or actual.size() > MAX_CHANNELS or not is_finite(dt) or dt <= 0.0:
		return {ok = false, message = "invalid servo trajectory interval"}
	# Reuse the established bounded input validation and arithmetic for a non-arriving channel.
	var endpoint := Actuators.step_normalized(actual, demand, rates, dt)
	if endpoint.size() != actual.size():
		return {ok = false, message = "invalid normalized servo trajectory data"}
	var arrivals := PackedFloat64Array()
	var cuts := PackedFloat64Array()
	for index: int in actual.size():
		var distance := absf(demand[index] - actual[index])
		var arrival := INF
		if distance == 0.0:
			endpoint[index] = actual[index]
		else:
			arrival = distance / rates[index]
			if arrival <= 0.0 or is_nan(arrival):
				return {ok = false, message = "servo arrival underflows local time"}
			if arrival <= dt:
				endpoint[index] = demand[index]
			if arrival < dt:
				cuts.append(arrival)
		arrivals.append(arrival)
		if not is_finite(endpoint[index]) or absf(endpoint[index]) > 1.0:
			return {ok = false, message = "servo endpoint outside normalized travel"}
	cuts.sort()
	var unique := PackedFloat64Array()
	for offset: float in cuts:
		if unique.is_empty() or unique[-1] != offset:
			unique.append(offset)
	return {ok = true, law = LAW, start = actual.duplicate(), target = demand.duplicate(),
		rates = rates.duplicate(), duration = dt, arrivals = arrivals, endpoint = endpoint, offsets = unique}


static func sample(plan: Dictionary, elapsed: float) -> PackedFloat64Array:
	if not plan.get("ok", false) or plan.get("law", "") != LAW or not is_finite(elapsed) \
			or elapsed < 0.0 or elapsed > plan.get("duration", -1.0):
		return PackedFloat64Array()
	if elapsed == 0.0:
		return plan.start.duplicate()
	if elapsed == plan.duration:
		return plan.endpoint.duplicate()
	var values: PackedFloat64Array = plan.start.duplicate()
	for index: int in values.size():
		if plan.start[index] == plan.target[index]:
			continue
		values[index] = plan.target[index] if elapsed >= plan.arrivals[index] else \
			Actuators.rate_limit(plan.start[index], plan.target[index], plan.rates[index], elapsed)
	return values


## A piece may be shorter than one ULP of its tick-local origin. Preserve its
## phase with an error-free sum; every exactly represented query retains sample().
## This extends the same ramp/hold to split clock queries without merging cuts.
static func sample_split(plan: Dictionary, origin: float, phase: float) -> PackedFloat64Array:
	if not is_finite(origin) or not is_finite(phase) or origin < 0.0 or phase < 0.0 \
		or not plan.get("ok",false) or origin > plan.duration or phase > plan.duration-origin:
		return PackedFloat64Array()
	var high := origin + phase
	var virtual_phase := high - origin
	var low := (origin - (high - virtual_phase)) + (phase - virtual_phase)
	if low == 0.0:
		return sample(plan,high)
	var values: PackedFloat64Array = plan.start.duplicate()
	for index: int in values.size():
		if plan.start[index] == plan.target[index]:continue
		if high > plan.arrivals[index] or (high == plan.arrivals[index] and low >= 0.0):
			values[index]=plan.target[index]
		else:
			var direction: float=1.0 if plan.target[index]>plan.start[index] else -1.0
			var value: float=Actuators.rate_limit(plan.start[index],plan.target[index],plan.rates[index],high)
			value += direction*plan.rates[index]*low
			values[index]=minf(value,plan.target[index]) if direction>0.0 else maxf(value,plan.target[index])
	return values
