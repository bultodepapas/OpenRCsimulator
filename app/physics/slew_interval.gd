extends RefCounted
## A bounded interval of the existing normalized slew law. No state is committed here.
const Actuators := preload("res://physics/control_actuators.gd")
const MAX_CHANNELS := 64


static func prepare(actual: PackedFloat64Array,demand: PackedFloat64Array,rates: PackedFloat64Array,
		dt: float,rate_factors := PackedFloat64Array()) -> Dictionary:
	if actual.is_empty() or actual.size()>MAX_CHANNELS or not is_finite(dt) or dt<=0.0:
		return {ok=false,message="invalid bounded slew interval"}
	var endpoint := Actuators.step_normalized(actual,demand,rates,dt,rate_factors)
	if endpoint.size()!=actual.size():
		return {ok=false,message="invalid normalized slew data"}
	var cuts := PackedFloat64Array()
	for index: int in actual.size():
		var rate: float = rates[index] if rate_factors.is_empty() else rates[index]*rate_factors[index]
		var distance := absf(demand[index]-actual[index])
		# Exact endpoint arrivals, zero motion and jams require no interior cut.
		if rate==0.0 or distance==0.0 or distance>=rate*dt:
			continue
		var offset := distance/rate
		if not is_finite(offset) or offset<=0.0 or offset>=dt:
			return {ok=false,message="slew arrival is not representable inside the interval"}
		cuts.append(offset)
	cuts.sort()
	var unique := PackedFloat64Array()
	for offset: float in cuts:
		if unique.is_empty() or offset!=unique[unique.size()-1]:
			unique.append(offset)
	return {ok=true,endpoint=endpoint,offsets=unique}
