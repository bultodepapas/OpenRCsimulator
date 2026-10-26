# M5-W05c-R1: diagnostic station-flow bundle for a fixed-datum aircraft state.
# Experimental input seam only; this does not admit a spatial weather scenario or integrate local forces.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Simulation := preload("res://sim/simulation.gd")

const LAW := "m5-w05c-r1-fixed-datum-station-relative-flow-v1"


## Build immutable station arms in body FRD from the authored datum O.
## Order: main-wing envelope stations, horizontal tail, vertical tail, then optional propeller hub or turbine intake.
static func geometry(model: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(model) != TYPE_DICTIONARY:
		errors.append("model must be a Dictionary")
		return _geometry_failure(errors)
	var cg_value: Variant = model.get("cg_le", null)
	if not _finite3(cg_value):
		errors.append("model.cg_le must be three finite authored-datum LE coordinates")
		return _geometry_failure(errors)
	var cg: PackedFloat64Array = cg_value

	var reference_value: Variant = model.get("reference", null)
	if typeof(reference_value) != TYPE_DICTIONARY:
		errors.append("model.reference must be a Dictionary")
		return _geometry_failure(errors)
	var reference: Dictionary = reference_value
	var arp_value: Variant = reference.get("arp_le", null)
	if not _finite3(arp_value):
		errors.append("model.reference.arp_le must be three finite LE coordinates")
		return _geometry_failure(errors)
	var span_value: Variant = reference.get("b", null)
	if typeof(span_value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(span_value)) or float(span_value) <= 0.0:
		errors.append("model.reference.b must be a finite positive span")
		return _geometry_failure(errors)
	var half_span: float = 0.5 * float(span_value)

	var envelope_value: Variant = model.get("envelope", null)
	if typeof(envelope_value) != TYPE_DICTIONARY:
		errors.append("model.envelope must be a Dictionary")
		return _geometry_failure(errors)
	var envelope: Dictionary = envelope_value
	var station_value: Variant = envelope.get("station_ys", null)
	var wing_count: int = Aero.WING_STATIONS_PER_SIDE * 2
	if typeof(station_value) != TYPE_PACKED_FLOAT64_ARRAY or station_value.size() != wing_count:
		errors.append("model.envelope.station_ys must contain the validated left-to-right wing stations")
		return _geometry_failure(errors)
	var station_ys: PackedFloat64Array = station_value
	for i in station_ys.size():
		if not is_finite(station_ys[i]):
			errors.append("model.envelope.station_ys[%d] must be finite" % i)
		elif absf(station_ys[i]) >= half_span:
			errors.append("model.envelope.station_ys[%d] must lie inside the declared semi-span" % i)
		elif i > 0 and station_ys[i] <= station_ys[i - 1]:
			errors.append("model.envelope.station_ys must be strictly ordered left to right")
			break
	var right_side_start: int = wing_count >> 1
	if station_ys[right_side_start - 1] >= 0.0 or station_ys[right_side_start] <= 0.0:
		errors.append("model.envelope.station_ys must contain stations on both sides of the centreline")
	if not errors.is_empty():
		return _geometry_failure(errors)

	var surfaces_value: Variant = model.get("surfaces", null)
	if typeof(surfaces_value) != TYPE_DICTIONARY:
		errors.append("model.surfaces must be a Dictionary")
		return _geometry_failure(errors)
	var surfaces: Dictionary = surfaces_value
	var horizontal_value: Variant = surfaces.get("horizontal", null)
	var vertical_value: Variant = surfaces.get("vertical", null)
	if typeof(horizontal_value) != TYPE_DICTIONARY or typeof(vertical_value) != TYPE_DICTIONARY:
		errors.append("model.surfaces.horizontal and vertical must be Dictionaries")
		return _geometry_failure(errors)
	var horizontal: Dictionary = horizontal_value
	var vertical: Dictionary = vertical_value
	var horizontal_position: Variant = horizontal.get("position", null)
	var vertical_position: Variant = vertical.get("position", null)
	if not _finite3(horizontal_position):
		errors.append("model.surfaces.horizontal.position must be three finite LE coordinates")
	if not _finite3(vertical_position):
		errors.append("model.surfaces.vertical.position must be three finite LE coordinates")
	if not errors.is_empty():
		return _geometry_failure(errors)

	var offsets := PackedFloat64Array()
	var wing_arm: PackedFloat64Array = Aero._arm(arp_value, cg)
	if not _finite3(wing_arm):
		errors.append("main-wing aerodynamic reference arm is nonfinite")
		return _geometry_failure(errors)
	for y in station_ys:
		offsets.append(wing_arm[0])
		offsets.append(wing_arm[1] + y)
		offsets.append(wing_arm[2])

	var horizontal_index: int = wing_count
	var horizontal_arm: PackedFloat64Array = Aero._arm(horizontal_position, cg)
	var vertical_index: int = wing_count + 1
	var vertical_arm: PackedFloat64Array = Aero._arm(vertical_position, cg)
	if not _finite3(horizontal_arm):
		errors.append("horizontal-tail arm is nonfinite")
	if not _finite3(vertical_arm):
		errors.append("vertical-tail arm is nonfinite")
	if not errors.is_empty():
		return _geometry_failure(errors)
	offsets.append_array(horizontal_arm)
	offsets.append_array(vertical_arm)

	var propulsion_index: int = -1
	var propulsion_value: Variant = model.get("propulsion", null)
	if propulsion_value != null:
		if typeof(propulsion_value) != TYPE_DICTIONARY:
			errors.append("model.propulsion must be a Dictionary when present")
		else:
			var propulsion: Dictionary = propulsion_value
			var kind: String = str(propulsion.get("kind", "glow_prop"))
			var location_key: String = ""
			if kind == "turbine":
				location_key = "intake_offset"
			elif kind in ["glow_prop", "electric_prop"]:
				location_key = "offset"
			elif kind == "none":
				location_key = ""
			else:
				errors.append("model.propulsion.kind has no supported station definition")
			if not location_key.is_empty():
				var propulsion_location: Variant = propulsion.get(location_key, null)
				if not _finite3(propulsion_location):
					errors.append("model.propulsion.%s must be three finite authored-datum coordinates" % location_key)
				else:
					var point: PackedFloat64Array = propulsion_location
					# Propulsion offsets are already relative to authored O. Convert only [aft,right,up] axes to FRD;
					# subtracting cg_le again would move a finite-resource vehicle's fixed datum.
					offsets.append(-point[0])
					offsets.append(point[1])
					offsets.append(-point[2])
					propulsion_index = wing_count + 2
	if not errors.is_empty():
		return _geometry_failure(errors)
	for value: float in offsets:
		if not is_finite(value):
			errors.append("station offsets contain a nonfinite body-frame coordinate")
			return _geometry_failure(errors)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"offsets_body": offsets,
		"wing_count": wing_count,
		"horizontal_index": horizontal_index,
		"vertical_index": vertical_index,
		"propulsion_index": propulsion_index,
	}


## Sample the same position/time wind law at O and every station, returning diagnostic local relative flows.
## relative_body includes datum air-relative velocity, one omega×r term, and the spatial wind delta.
static func sample(s: Variant, model: Variant, environment: Variant, time_s: float) -> Dictionary:
	var station_geometry: Dictionary = geometry(model)
	if not station_geometry.ok:
		return _sample_failure(station_geometry.errors, station_geometry, time_s)
	var errors := PackedStringArray()
	if typeof(s) != TYPE_PACKED_FLOAT64_ARRAY or not Simulation.state_is_valid(s):
		errors.append("state must be a finite full rigid-body state with a nondegenerate quaternion")
	if not is_finite(time_s) or time_s < 0.0:
		errors.append("time_s must be finite and nonnegative")
	if environment == null or typeof(environment) != TYPE_OBJECT or not environment.has_method("wind_world"):
		errors.append("environment must provide wind_world(position_ned, time_s)")
	if not errors.is_empty():
		return _sample_failure(errors, station_geometry, time_s)

	var state: PackedFloat64Array = s
	# RK stages use the supplied quaternion directly; normalization belongs to the integrator's accepted-step path.
	# Match Air.compute and the existing stage-point transform even when an intermediate stage is not exactly unit length.
	var q_body_to_ned: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var q_ned_to_body: PackedFloat64Array = M.q_conj(q_body_to_ned)
	var position_ned: PackedFloat64Array = state.slice(RB.POS, RB.POS + 3)
	var reference_wind_value: Variant = environment.call("wind_world", position_ned.duplicate(), time_s)
	if not _finite3(reference_wind_value):
		errors.append("environment rejected the datum wind sample")
		return _sample_failure(errors, station_geometry, time_s)
	var reference_wind: PackedFloat64Array = reference_wind_value.duplicate()
	var reference_air_body: PackedFloat64Array = Air.compute(state, reference_wind).v_air
	if not _finite3(reference_air_body):
		errors.append("datum air-relative body velocity is nonfinite")
		return _sample_failure(errors, station_geometry, time_s)

	var offsets: PackedFloat64Array = station_geometry.offsets_body
	var station_count: int = offsets.size() / 3
	var positions_ned := PackedFloat64Array()
	var wind_ned := PackedFloat64Array()
	var relative_body := PackedFloat64Array()
	var delta_body := PackedFloat64Array()
	var omega: PackedFloat64Array = state.slice(RB.RATE, RB.RATE + 3)
	var uniform := true
	for i in station_count:
		var arm := offsets.slice(i * 3, i * 3 + 3)
		var station_position: PackedFloat64Array = M.add(position_ned, M.q_rotate(q_body_to_ned, arm))
		if not _finite3(station_position):
			errors.append("station %d world position is nonfinite" % i)
			return _sample_failure(errors, station_geometry, time_s)
		var station_wind_value: Variant = environment.call("wind_world", station_position.duplicate(), time_s)
		if not _finite3(station_wind_value):
			errors.append("environment rejected wind at station %d" % i)
			return _sample_failure(errors, station_geometry, time_s)
		var station_wind: PackedFloat64Array = station_wind_value.duplicate()
		var station_uniform: bool = _same3(reference_wind, station_wind)
		uniform = uniform and station_uniform
		var delta: PackedFloat64Array
		if station_uniform:
			# Preserve the exact uniform-field limit rather than subtracting and rotating equal samples.
			delta = PackedFloat64Array([0.0, 0.0, 0.0])
		else:
			delta = M.q_rotate(q_ned_to_body, M.sub(reference_wind, station_wind))
		var rate_delta: PackedFloat64Array = M.cross(omega, arm)
		var local_air: PackedFloat64Array = reference_air_body.duplicate()
		for axis in 3:
			if rate_delta[axis] != 0.0:
				local_air[axis] += rate_delta[axis]
		if not station_uniform:
			for axis in 3:
				if delta[axis] != 0.0:
					local_air[axis] += delta[axis]
		if not _finite3(delta) or not _finite3(local_air):
			errors.append("station %d relative flow is nonfinite" % i)
			return _sample_failure(errors, station_geometry, time_s)
		positions_ned.append_array(station_position)
		wind_ned.append_array(station_wind)
		relative_body.append_array(local_air)
		delta_body.append_array(delta)

	return {
		"ok": true,
		"errors": PackedStringArray(),
		"law": LAW,
		"position_ned": position_ned,
		"time_s": time_s,
		"offsets_body": offsets.duplicate(),
		"positions_ned": positions_ned,
		"wind_ned": wind_ned,
		"relative_body": relative_body,
		"delta_body": delta_body,
		"reference_wind_ned": reference_wind,
		"reference_air_body": reference_air_body,
		"uniform": uniform,
		"wing_count": int(station_geometry.wing_count),
		"horizontal_index": int(station_geometry.horizontal_index),
		"vertical_index": int(station_geometry.vertical_index),
		"propulsion_index": int(station_geometry.propulsion_index),
		"indices": {
			"wing_count": int(station_geometry.wing_count),
			"horizontal_index": int(station_geometry.horizontal_index),
			"vertical_index": int(station_geometry.vertical_index),
			"propulsion_index": int(station_geometry.propulsion_index),
		},
	}


static func _geometry_failure(errors: PackedStringArray) -> Dictionary:
	return {
		"ok": false,
		"errors": errors.duplicate(),
		"offsets_body": PackedFloat64Array(),
		"wing_count": 0,
		"horizontal_index": -1,
		"vertical_index": -1,
		"propulsion_index": -1,
	}


static func _sample_failure(errors: PackedStringArray, station_geometry: Dictionary, time_s: float) -> Dictionary:
	return {
		"ok": false,
		"errors": errors.duplicate(),
		"law": LAW,
		"position_ned": PackedFloat64Array(),
		"time_s": time_s,
		"offsets_body": station_geometry.get("offsets_body", PackedFloat64Array()).duplicate(),
		"positions_ned": PackedFloat64Array(),
		"wind_ned": PackedFloat64Array(),
		"relative_body": PackedFloat64Array(),
		"delta_body": PackedFloat64Array(),
		"reference_wind_ned": PackedFloat64Array(),
		"reference_air_body": PackedFloat64Array(),
		"uniform": false,
		"wing_count": int(station_geometry.get("wing_count", 0)),
		"horizontal_index": int(station_geometry.get("horizontal_index", -1)),
		"vertical_index": int(station_geometry.get("vertical_index", -1)),
		"propulsion_index": int(station_geometry.get("propulsion_index", -1)),
		"indices": {
			"wing_count": int(station_geometry.get("wing_count", 0)),
			"horizontal_index": int(station_geometry.get("horizontal_index", -1)),
			"vertical_index": int(station_geometry.get("vertical_index", -1)),
			"propulsion_index": int(station_geometry.get("propulsion_index", -1)),
		},
	}


static func _finite3(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != 3:
		return false
	for component: float in value:
		if not is_finite(component):
			return false
	return true


static func _same3(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a[0] == b[0] and a[1] == b[1] and a[2] == b[2]
