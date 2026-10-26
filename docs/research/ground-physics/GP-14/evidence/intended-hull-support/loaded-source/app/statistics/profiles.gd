## Reviewed contact-role metadata for the current catalog fixed-wing fleet.
## These are statistics classifications, not physics inputs or generated aircraft data.
extends RefCounted

const Rules := preload("res://statistics/rules.gd")
const IntendedHullSupport := preload("res://physics/intended_hull_support.gd")
const M := preload("res://physics/math3d.gd")
const PROFILE_VERSION := "fixed-wing-contacts-v1"
const _GEOMETRY_TOLERANCE_M := 0.000001

# Each profile stores the accepted datum span and model-local support points from the
# current aircraft JSON. A changed/missing support ID or geometry disables landing credit.
const _PROFILES := {
	"f4u-corsair-250": {
		"span_m": 2.777778,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_tail"],
		"points": {
			"contact_main_left": [0.0934803807411916, -0.431111, 0.468341531472859],
			"contact_main_right": [0.0934803807411916, 0.431111, 0.468341531472859],
			"contact_tail": [-1.25763161925881, 0.0, 0.120858531472859],
		},
	},
	"gp-extra-300s-60": {
		"span_m": 1.6256,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_tail"],
		"points": {
			"contact_main_left": [0.0787471145849838, -0.16, 0.244749293699338],
			"contact_main_right": [0.0787471145849838, 0.16, 0.244749293699338],
			"contact_tail": [-0.855252885415016, 0.0, 0.0655242936993376],
		},
	},
	"jensen-das-ugly-stik-60": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.105607562648019, -0.18, 0.253308375964654],
			"contact_main_right": [-0.105607562648019, 0.18, 0.253308375964654],
			"contact_nose": [0.245668437351981, 0.0, 0.250133375964654],
		},
	},
	"p51d-mustang-120": {
		"span_m": 2.82,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_tail"],
		"points": {
			"contact_main_left": [0.147084897436693, -0.451, 0.439723993592372],
			"contact_main_right": [0.147084897436693, 0.451, 0.439723993592372],
			"contact_tail": [-1.10971510256331, 0.0, 0.128873993592372],
		},
	},
	"sebart-avanti-s-a200-p100rx": {
		"span_m": 2.0,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.114632673047296, -0.32, 0.240730047126487],
			"contact_main_right": [-0.114632673047296, 0.32, 0.240730047126487],
			"contact_nose": [0.748367326952704, 0.0, 0.241550047126487],
		},
	},
	"stik-glow-55ax-2t": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.118048539225418, -0.18, 0.255268269735212],
			"contact_main_right": [-0.118048539225418, 0.18, 0.255268269735212],
			"contact_nose": [0.233227460774582, 0.0, 0.252093269735212],
		},
	},
	"stik-glow-61fx-2t": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.11597554105369, -0.18, 0.253496116632932],
			"contact_main_right": [-0.11597554105369, 0.18, 0.253496116632932],
			"contact_nose": [0.23530045894631, 0.0, 0.250321116632932],
		},
	},
	"stik-glow-fs64v-4t": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.109961325469416, -0.18, 0.255613111776503],
			"contact_main_right": [-0.109961325469416, 0.18, 0.255613111776503],
			"contact_nose": [0.241314674530584, 0.0, 0.252438111776503],
		},
	},
	"synthetic_stik_electric_4s": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.105607562648019, -0.18, 0.253308375964654],
			"contact_main_right": [-0.105607562648019, 0.18, 0.253308375964654],
			"contact_nose": [0.245668437351981, 0.0, 0.250133375964654],
		},
	},
	"synthetic_stik_electric_4s_battery": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.105607562648019, -0.18, 0.253308375964654],
			"contact_main_right": [-0.105607562648019, 0.18, 0.253308375964654],
			"contact_nose": [0.245668437351981, 0.0, 0.250133375964654],
		},
	},
	"synthetic_stik_electric_6s": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [-0.105607562648019, -0.18, 0.253308375964654],
			"contact_main_right": [-0.105607562648019, 0.18, 0.253308375964654],
			"contact_nose": [0.245668437351981, 0.0, 0.250133375964654],
		},
	},
	"synthetic_stik_electric_6s_battery": {
		"span_m": 1.524,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_nose"],
		"points": {
			"contact_main_left": [0.215, -0.18, -0.2531],
			"contact_main_right": [0.215, 0.18, -0.2531],
			"contact_nose": [-0.136276, 0.0, -0.249925],
		},
	},
	"turbo-lumber-evolution": {
		"span_m": 1.555,
		"main_ids": ["contact_main_left", "contact_main_right"],
		"stop_ids": ["contact_main_left", "contact_main_right", "contact_tail"],
		"points": {
			"contact_main_left": [0.052, -0.131979, 0.253840200913242],
			"contact_main_right": [0.052, 0.131979, 0.253840200913242],
			"contact_tail": [-0.699, 0.0, 0.123828200913242],
		},
	},
}


static func resolve(aircraft_id: String, model: Dictionary, bindings: Dictionary) -> Dictionary:
	var span := _model_span(model)
	var reference_speed := _model_start_speed(model)
	var speed_cap := maxf(float(Rules.DEFAULTS.default_speed_cap_mps), 4.0 * reference_speed)
	var result := {
		"profile_version": PROFILE_VERSION,
		"rules_version": Rules.VERSION,
		"aircraft_id": aircraft_id,
		"landing_available": false,
		"reason": "unreviewed_aircraft_profile",
		"main_indices": PackedInt32Array(),
		"stop_indices": PackedInt32Array(),
		"main_ids": [],
		"stop_ids": [],
		"clearance_m": maxf(0.25, 0.1 * span) if span > 0.0 else 0.25,
		"rest_height_m": -1.0,
		"rest_pitch_rad": 0.0,
		"speed_cap_mps": speed_cap,
		"initial_tick": 0,
	}
	if model.has("intended_hull_support"):
		return _hull_profile(result, aircraft_id, model, bindings)
	var review: Variant = _PROFILES.get(aircraft_id)
	if typeof(review) != TYPE_DICTIONARY:
		return result
	if typeof(model.get("id", "")) != TYPE_STRING or str(model.get("id", "")) != aircraft_id:
		result.reason = "aircraft_identity_mismatch"
		return result
	if absf(span - float(review.span_m)) > _GEOMETRY_TOLERANCE_M:
		result.reason = "wing_span_changed"
		return result
	if not bool(bindings.get("ok", false)):
		result.reason = "contact_bindings_unavailable"
		return result
	var contact_map := _validated_contact_map(model, bindings, review)
	if contact_map.is_empty():
		result.reason = "support_geometry_changed_or_unavailable"
		return result
	var main_indices := PackedInt32Array()
	var stop_indices := PackedInt32Array()
	for contact_id: String in review.main_ids:
		main_indices.append(int(contact_map[contact_id].index))
	for contact_id: String in review.stop_ids:
		stop_indices.append(int(contact_map[contact_id].index))
	var rest_pitch := _rest_pitch(review, contact_map)
	var rest_height := _rest_height(review, contact_map, rest_pitch)
	if not is_finite(rest_pitch) or not is_finite(rest_height) or rest_height <= 0.0:
		result.reason = "support_geometry_invalid"
		return result
	result.landing_available = true
	result.reason = ""
	result.main_indices = main_indices
	result.stop_indices = stop_indices
	result.main_ids = review.main_ids.duplicate()
	result.stop_ids = review.stop_ids.duplicate()
	result.rest_height_m = rest_height
	result.rest_pitch_rad = rest_pitch
	return result


static func _hull_profile(result: Dictionary, aircraft_id: String, model: Dictionary, bindings: Dictionary) -> Dictionary:
	result.profile_version = "fixed-wing-authored-hull-contacts-v1"
	result.support_kind = "authored_hull"
	result.reason = "intended_hull_support_unavailable"
	if typeof(model.get("id")) != TYPE_STRING or model.id != aircraft_id \
		or typeof(bindings.get("ok")) != TYPE_BOOL or not bindings.ok:
		return result
	var prepared: Variant = model.intended_hull_support
	var bound: Variant = bindings.get("intended_hull_support")
	if not prepared is Dictionary or not bound is Dictionary or not IntendedHullSupport.matches_model(prepared, model) \
		or var_to_bytes(prepared) != var_to_bytes(bound):
		return result
	var policy: Variant = bindings.get("policy")
	var hull_policy: Variant = policy.get("hull") if policy is Dictionary else null
	if not hull_policy is Dictionary or typeof(hull_policy.get("mode")) != TYPE_STRING or hull_policy.mode != "soft":
		result.reason = "intended_hull_support_requires_soft_hull"
		return result
	if not str(bindings.get("lake_identity", "")).is_empty():
		result.reason = "intended_hull_support_lake_scope_unavailable"
		return result
	var rest := M.q_from_euler(0.0, prepared.rest_pose.pitch, prepared.rest_pose.roll)
	var height := -INF
	for index: int in range(0, model.crash_hull.size(), 3):
		height = maxf(height, M.q_rotate(rest, model.crash_hull.slice(index, index + 3))[2])
	if not is_finite(height) or height <= 0.0:
		result.reason = "intended_hull_rest_geometry_invalid"
		return result
	result.landing_available = true
	result.reason = ""
	result.hull_support_identity = prepared.identity
	result.hull_support_scope = "legacy-flat-solid-only-v1"
	result.hull_stop_group_count = prepared.stop_groups.size()
	result.rest_height_m = height
	result.rest_pitch_rad = prepared.rest_pose.pitch
	result.rest_roll_rad = prepared.rest_pose.roll
	return result


static func _validated_contact_map(model: Dictionary, bindings: Dictionary, review: Dictionary) -> Dictionary:
	var binding_points: Variant = bindings.get("support_points", [])
	var gear_value: Variant = model.get("landing_gear", {})
	if typeof(binding_points) != TYPE_ARRAY or typeof(gear_value) != TYPE_DICTIONARY:
		return {}
	var model_contacts: Variant = gear_value.get("contacts", [])
	if typeof(model_contacts) != TYPE_ARRAY or model_contacts.size() != review.points.size():
		return {}
	if binding_points.size() != review.points.size():
		return {}
	var model_by_id: Dictionary = {}
	for model_index in model_contacts.size():
		var contact_value: Variant = model_contacts[model_index]
		if typeof(contact_value) != TYPE_DICTIONARY:
			return {}
		var contact: Dictionary = contact_value
		var contact_id := str(contact.get("id", ""))
		if contact_id.is_empty() or model_by_id.has(contact_id):
			return {}
		model_by_id[contact_id] = {"index": model_index, "position": _point3(contact.get("position"))}
	var result: Dictionary = {}
	var seen_indices: Dictionary = {}
	for binding_value: Variant in binding_points:
		if typeof(binding_value) != TYPE_DICTIONARY:
			return {}
		var binding: Dictionary = binding_value
		var contact_id := str(binding.get("id", ""))
		var index := int(binding.get("contact_index", -1))
		if contact_id.is_empty() or result.has(contact_id) or seen_indices.has(index):
			return {}
		if not model_by_id.has(contact_id) or index != int(model_by_id[contact_id].index):
			return {}
		var expected_value: Variant = review.points.get(contact_id)
		if typeof(expected_value) != TYPE_ARRAY:
			return {}
		var binding_point := _point3(binding.get("position"))
		var model_point: Array = model_by_id[contact_id].position
		if binding_point.size() != 3 or model_point.size() != 3:
			return {}
		if not _points_match(binding_point, expected_value) or not _points_match(model_point, expected_value):
			return {}
		seen_indices[index] = true
		result[contact_id] = {"index": index, "position": binding_point}
	if result.size() != review.points.size():
		return {}
	return result


static func _rest_pitch(review: Dictionary, contact_map: Dictionary) -> float:
	var main_ids: Array = review.main_ids
	var main_x := 0.0
	var main_z := 0.0
	for contact_id: String in main_ids:
		var point: Array = contact_map[contact_id].position
		main_x += float(point[0])
		main_z += float(point[2])
	main_x /= float(main_ids.size())
	main_z /= float(main_ids.size())
	var remaining_ids: Array = review.stop_ids
	var third_id := ""
	for contact_id: String in remaining_ids:
		if contact_id not in main_ids:
			third_id = contact_id
			break
	if third_id.is_empty():
		return NAN
	var third: Array = contact_map[third_id].position
	var dx := float(third[0]) - main_x
	if absf(dx) <= 0.000001:
		return NAN
	return atan((float(third[2]) - main_z) / dx)


static func _rest_height(review: Dictionary, contact_map: Dictionary, pitch: float) -> float:
	var cos_pitch := cos(pitch)
	var sin_pitch := sin(pitch)
	var projected_z := 0.0
	var ids: Array = review.stop_ids
	for contact_id: String in ids:
		var point: Array = contact_map[contact_id].position
		projected_z += float(point[2]) * cos_pitch - float(point[0]) * sin_pitch
	return projected_z / float(ids.size())


static func _points_match(actual: Array, expected: Array) -> bool:
	if actual.size() != 3 or expected.size() != 3:
		return false
	for i in 3:
		if typeof(actual[i]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(actual[i])):
			return false
		if absf(float(actual[i]) - float(expected[i])) > _GEOMETRY_TOLERANCE_M:
			return false
	return true


static func _point3(value: Variant) -> Array:
	if typeof(value) == TYPE_DICTIONARY:
		return _point3(value.get("value"))
	if typeof(value) not in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or value.size() != 3:
		return []
	var result: Array = []
	for item: Variant in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)):
			return []
		result.append(float(item))
	return result


static func _model_span(model: Dictionary) -> float:
	var reference: Variant = model.get("reference", {})
	if typeof(reference) != TYPE_DICTIONARY:
		return -1.0
	var value: Variant = reference.get("b", reference.get("wing_span", -1.0))
	return _quantity_scalar(value)


static func _model_start_speed(model: Dictionary) -> float:
	var start: Variant = model.get("start", {})
	if typeof(start) != TYPE_DICTIONARY:
		return 0.0
	for key: String in ["level_speed", "level_speed_mps", "reference_speed_mps"]:
		if start.has(key):
			return maxf(0.0, _quantity_scalar(start[key]))
	return 0.0


static func _quantity_scalar(value: Variant) -> float:
	if typeof(value) == TYPE_DICTIONARY:
		return _quantity_scalar(value.get("value", -1.0))
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return -1.0
	return float(value)
