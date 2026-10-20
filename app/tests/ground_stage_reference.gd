## H16: original stage body, retained verbatim as the behavior oracle.
## Frozen full session SHA-256: 6c13355f3f24edb9152ddd4fd0789ae4d7bee7570f27fcf19e49d2a1c7e9a6d3
extends "res://sim/flight_session.gd"


## Legacy gear keeps its original contact law; a file-backed wheel profile opts into terrain and wheel-spin state.
func _ground_evaluation(s: PackedFloat64Array, aux: PackedFloat64Array, values: PackedFloat64Array, stage_air: Dictionary = {}, properties: Dictionary = {}) -> Dictionary:
	if gear_is_retractable() and (not _gear_aux_valid(aux) or sim.inputs.size() != _input_count() or stage_air.is_empty()):
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var gear: Dictionary = current_landing_gear(aux)
	var steer: float = aux[AUX_SERVO + 2]
	var brake: float = sim.inputs[5] if gear_is_retractable() else 0.0
	var anchors: PackedFloat64Array = aux.slice(AUX_ANCHORS, AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE)
	var hull: PackedFloat64Array = PackedFloat64Array()
	if soft_hull_contacts:
		if glow_is_active() or not properties.is_empty():
			if _hull_contact.is_empty() or (glow_is_active() and values.size() < GlowFlight.SIZE):
				return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
			# Geometry reach is independent of fuel; avoid any new mass/contact work in free flight.
			if -s[RB.POS + 2] <= float(_hull_contact.reach):
				var sampled: Dictionary = HullContact.loads_at_properties(s, _hull_contact, properties if not properties.is_empty() else GlowFlight.properties(self, values[1], values[GlowFlight.LINE_FUEL_INDEX]))
				if not sampled.get("ok", false):
					return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
				hull = sampled.loads
				if hull.size() not in [0, 6]:
					return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
		else:
			hull = HullContact.loads(s, _hull_contact)
		for value: float in hull:
			if not is_finite(value):
				return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	if gear_is_retractable():
		hull = _add_loads(hull, RetractableGear.drag_loads(s, stage_air.v_air, aircraft.model.landing_gear, aux[gear_aux_index()], air_density(s)))
	if wheel_count() == 0:
		return {ok = true, loads = _add_loads(Ground.loads(s, gear, steer, ground_surfaces, anchors,
			PackedFloat64Array(), brake, _lake), hull), derivative = PackedFloat64Array()}
	if values.size() != wheel_index() + wheel_count():
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var speeds: PackedFloat64Array = values.slice(wheel_index(), wheel_index() + wheel_count())
	for speed in speeds:
		if not is_finite(speed):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	var evaluation: Dictionary = Ground.evaluate(s, gear, steer, ground_surfaces, anchors, speeds, brake, false, _lake)
	var loads: PackedFloat64Array = evaluation.get("loads", PackedFloat64Array())
	var rates: PackedFloat64Array = evaluation.get("derivative", PackedFloat64Array())
	if (not loads.is_empty() and loads.size() != 6) or rates.size() != wheel_count():
		return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	for value in loads:
		if not is_finite(value):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	for value in rates:
		if not is_finite(value):
			return {ok = false, loads = PackedFloat64Array([NAN]), derivative = PackedFloat64Array([NAN])}
	evaluation.ok = true
	evaluation.loads = _add_loads(loads, hull)
	return evaluation
