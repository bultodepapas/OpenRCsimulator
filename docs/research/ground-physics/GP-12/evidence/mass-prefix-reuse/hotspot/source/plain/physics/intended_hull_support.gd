## GP-14: authored intent for existing accepted soft-hull contacts.
## No force, damage, contact detection, dwell timer or landing-result classifier.
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/math3d.gd")
const Q := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/wheel_profiles.gd")
const Hull := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/plain/physics/hull_contact.gd")
const FORMAT := "openrc-intended-hull-support v1"
const LAW := "authored-hull-role-pose-observation-v1"
const CONTACT_LAW := "soft_hull_spring_friction_v2"
const RAW_KEYS := ["format", "role", "evidence", "contact_law", "allowed_contact_ids", "stop_groups", "rest_pose", "control_envelope"]
const PREPARED_KEYS := ["ok", "format", "law", "identity", "aircraft_id", "hull_geometry_identity", "required_hull_law", "all_hull_ids", "allowed_contact_ids", "stop_groups", "rest_pose", "control_envelope", "provenance"]
const MAX_HULL := 256
const MAX_ALLOWED := 64
const MAX_GROUPS := 16
const MAX_GROUP_SIZE := 16
const MAX_PREPARED_BYTES := 131072
const UNIT_TOLERANCE := 1.0e-10


## model is the validated physical owner's normalized result, after PhysicalIdentity.
## No authored coordinate/CG/radius copy is accepted. An absent optional v2 module
## must be handled by the owner as unavailable intent; it must not call with {}.
static func prepare(raw: Dictionary, model: Dictionary) -> Dictionary:
	var all_ids: Variant = model.get("physical_identity", {}).get("hull_ids") if model.get("physical_identity") is Dictionary else null
	var hull: Variant = model.get("crash_hull")
	if not _text(model.get("id"), 80) or not _ids(all_ids, MAX_HULL, true) \
		or not hull is PackedFloat64Array or hull.size() != 3 * all_ids.size():
		return _failure("validated authored hull identity and matching physical float64 geometry required")
	var support_ids: Variant = model.physical_identity.get("support_ids")
	var gear: Variant = model.get("landing_gear", {})
	if all_ids.size() < 4 or typeof(model.physical_identity.get("version")) != TYPE_INT \
		or model.physical_identity.version != 1 or typeof(model.physical_identity.get("status")) != TYPE_STRING \
		or model.physical_identity.status != "authored" \
		or (not support_ids is PackedStringArray and not support_ids is Array) or not support_ids.is_empty() \
		or not gear is Dictionary or not gear.is_empty():
		return _failure("initial hull-support capability requires authored identity and no installed wheel supports")
	for coordinate: float in hull:
		if not is_finite(coordinate) or absf(coordinate) > 1000.0:
			return _failure("hull geometry outside finite supported range")
	var compiled := _compile(raw, all_ids)
	if not compiled.ok: return compiled
	var required_law := Hull.law()
	var geometry_identity := _hash({ids = all_ids, coordinates_body_m = hull, soft_hull_law = required_law})
	var result := {ok = true, format = FORMAT, law = LAW, aircraft_id = str(model.id),
		hull_geometry_identity = geometry_identity, required_hull_law = required_law,
		all_hull_ids = Array(all_ids), allowed_contact_ids = raw.allowed_contact_ids.duplicate(),
		stop_groups = compiled.groups, rest_pose = compiled.rest, control_envelope = compiled.envelope, provenance = raw.duplicate(true)}
	result.identity = _hash(result)
	if var_to_bytes(result).size() > MAX_PREPARED_BYTES: return _failure("prepared hull-support resource exceeds byte bound")
	return result


## Call at installation/hot reload with the CURRENT physical owner's model. The
## query receipt does not authenticate model ownership or detect an external model
## swap by itself. The same existing geometry is hashed, never re-authored here.
static func matches_model(prepared: Dictionary, model: Dictionary) -> bool:
	if not _prepared_valid(prepared): return false
	var current := prepare(prepared.provenance, model)
	return current.ok and current.identity == prepared.identity


static func _compile(raw: Dictionary, all_ids: Variant) -> Dictionary:
	if not _keys(raw, RAW_KEYS) or typeof(raw.format) != TYPE_STRING or raw.format != FORMAT \
		or raw.get("role") not in ["belly", "skid"] or typeof(raw.contact_law) != TYPE_STRING \
		or raw.contact_law != CONTACT_LAW or not _evidence(raw.get("evidence")):
		return _failure("strict authored hull-support format, role, soft-hull law and provenance required")
	if not _keys(raw.get("rest_pose"), ["roll", "pitch"]) \
		or not _keys(raw.get("control_envelope"), ["roll_tolerance", "pitch_tolerance", "max_angular_speed"]):
		return _failure("explicit rest pose and complete control envelope required")
	var errors := PackedStringArray()
	var rest := {}
	var envelope := {}
	for key: String in ["roll", "pitch"]:
		_quantity("rest_pose." + key, raw.rest_pose[key], ["rad", -PI / 4.0, PI / 4.0], errors)
	for key: String in ["roll_tolerance", "pitch_tolerance"]:
		_quantity("control_envelope." + key, raw.control_envelope[key], ["rad", 1.0e-6, PI / 4.0], errors)
	_quantity("control_envelope.max_angular_speed", raw.control_envelope.max_angular_speed, ["rad/s", 1.0e-6, 100.0], errors)
	if not errors.is_empty(): return {ok = false, errors = errors}
	for key: String in raw.rest_pose: rest[key] = float(raw.rest_pose[key].value)
	for key: String in raw.control_envelope: envelope[key] = float(raw.control_envelope[key].value)
	if not _ids(raw.allowed_contact_ids, MAX_ALLOWED):
		return _failure("nonempty unique authored allowed_contact_ids required")
	for contact_id: String in raw.allowed_contact_ids:
		if contact_id not in all_ids: return _failure("allowed hull support ID is not physically bound: " + contact_id)
	if not raw.stop_groups is Array or raw.stop_groups.is_empty() or raw.stop_groups.size() > MAX_GROUPS:
		return _failure("1..16 explicit stop groups required")
	var groups: Array = []
	var seen_groups := {}
	for group: Variant in raw.stop_groups:
		if not _ids(group, MAX_GROUP_SIZE): return _failure("stop groups require nonempty unique hull IDs")
		for contact_id: String in group:
			if contact_id not in raw.allowed_contact_ids: return _failure("stop group references a non-intended hull ID")
		var canonical: Array = group.duplicate()
		canonical.sort()
		var group_key := JSON.stringify(canonical)
		if seen_groups.has(group_key): return _failure("duplicate stop group")
		seen_groups[group_key] = true
		groups.append(group.duplicate())
	return {ok = true, rest = rest, envelope = envelope, groups = groups}


## Caller supplies only accepted active IDs and explicitly NORMALIZES the terrain
## normal at its boundary. Neither raw terrain gradient nor a trial RK contact is
## accepted evidence. q is body-to-NED; normal points out of solid terrain.
## Role coverage remains factual; intended support additionally requires the
## authored pose envelope, so a wrong-pose contact cannot mask an incident.
## Rate qualification remains controlled, separate from intended support. A stop
## group is an OR of groups, each an ALL requirement. Speed/dwell stay in detector.
static func evaluate(prepared: Dictionary, active_ids: PackedStringArray,
		q_body_to_ned: PackedFloat64Array, normal_ned: PackedFloat64Array,
		angular_rate_body: PackedFloat64Array, selected_hull_law: String,
		surface_kind: String = "solid_ground") -> Dictionary:
	if not _prepared_valid(prepared): return _failure("invalid or mutated prepared hull-support resource")
	if selected_hull_law != prepared.required_hull_law or surface_kind != "solid_ground":
		return _failure("intended hull support requires the pinned soft-hull law on solid ground")
	if not _unit(q_body_to_ned, 4) or not _unit(normal_ned, 3) or not _vector(angular_rate_body, 3, 1.0e6):
		return _failure("finite unit attitude/normalized terrain normal and finite body rates required")
	if active_ids.size() > MAX_HULL or not _ids(active_ids, MAX_HULL, true, true):
		return _failure("accepted active hull IDs must be unique and bounded")
	var intended := PackedStringArray()
	var incidental := PackedStringArray()
	for contact_id: String in active_ids:
		if contact_id not in prepared.all_hull_ids: return _failure("unknown accepted hull ID: " + contact_id)
		if contact_id in prepared.allowed_contact_ids: intended.append(contact_id)
		else: incidental.append(contact_id)
	var n_body := M.q_rotate(M.q_conj(q_body_to_ned), normal_ned)
	var roll := M.atan2_(-n_body[1], -n_body[2])
	var pitch := M.atan2_(n_body[0], M.sqrt_(n_body[1] * n_body[1] + n_body[2] * n_body[2]))
	var roll_error := _angle(roll - prepared.rest_pose.roll)
	var pitch_error: float = pitch - prepared.rest_pose.pitch
	var angular_speed := M.norm(angular_rate_body)
	var pose_ok: bool = absf(roll_error) <= prepared.control_envelope.roll_tolerance \
		and absf(pitch_error) <= prepared.control_envelope.pitch_tolerance
	var controlled: bool = pose_ok and angular_speed <= prepared.control_envelope.max_angular_speed
	var intended_only := not intended.is_empty() and incidental.is_empty()
	var stop_group := -1
	for i: int in prepared.stop_groups.size():
		var all_present := true
		for contact_id: String in prepared.stop_groups[i]:
			all_present = all_present and contact_id in active_ids
		if all_present:
			stop_group = i
			break
	var coverage := "empty" if active_ids.is_empty() else ("intended_only" if incidental.is_empty() \
		else ("incidental_only" if intended.is_empty() else "mixed"))
	return {ok = true, identity = prepared.identity, touching = not active_ids.is_empty(),
		role_coverage = coverage, role_covered = intended_only, intended_support = intended_only and pose_ok,
		stop_support = intended_only and pose_ok and stop_group >= 0, controlled = controlled,
		pose_within_envelope = pose_ok, matched_stop_group_index = stop_group,
		intended_contact_ids = intended, incidental_contact_ids = incidental,
		pose_facts = {roll_rad = roll, pitch_rad = pitch, roll_error_rad = roll_error,
			pitch_error_rad = pitch_error, angular_speed_radps = angular_speed}}


static func _prepared_valid(value: Dictionary) -> bool:
	if not _keys(value, PREPARED_KEYS) or typeof(value.ok) != TYPE_BOOL or not value.ok \
		or typeof(value.format) != TYPE_STRING or value.format != FORMAT \
		or typeof(value.law) != TYPE_STRING or value.law != LAW or not _digest(value.get("identity")) \
		or not _text(value.get("aircraft_id"), 80) or not _digest(value.get("hull_geometry_identity")) \
		or typeof(value.required_hull_law) != TYPE_STRING or value.required_hull_law != Hull.law() \
		or not _ids(value.get("all_hull_ids"), MAX_HULL) \
		or not _ids(value.get("allowed_contact_ids"), MAX_ALLOWED) \
		or not value.get("stop_groups") is Array or value.stop_groups.size() > MAX_GROUPS \
		or not value.get("provenance") is Dictionary or not _bounded_tree(value, 0) \
		or var_to_bytes(value).size() > MAX_PREPARED_BYTES:
		return false
	if value.all_hull_ids.size() < 4: return false
	var compiled := _compile(value.provenance, value.all_hull_ids)
	if not compiled.ok or not value.rest_pose is Dictionary or not value.control_envelope is Dictionary:
		return false
	if _hash({rest = value.rest_pose, envelope = value.control_envelope, groups = value.stop_groups, allowed = value.allowed_contact_ids}) \
		!= _hash({rest = compiled.rest, envelope = compiled.envelope, groups = compiled.groups, allowed = value.provenance.allowed_contact_ids}):
		return false
	var copy := value.duplicate(true)
	copy.erase("identity")
	return _hash(copy) == value.identity


static func _quantity(path: String, value: Variant, spec: Array, errors: PackedStringArray) -> void:
	if not _keys(value, ["value", "unit", "kind", "source"]) or not _text(value.get("source") if value is Dictionary else null, 2048):
		errors.append(path + ": strict provenance quantity required")
		return
	Q._validate_quantity(path, value, spec, errors)


static func _evidence(value: Variant) -> bool:
	return _keys(value, ["kind", "source"]) and value.kind in ["manual", "measured", "borrowed", "estimated", "derived"] \
		and _text(value.source, 2048)


static func _ids(value: Variant, limit: int, packed := false, allow_empty := false) -> bool:
	if not value is Array and not (packed and value is PackedStringArray): return false
	if (value.is_empty() and not allow_empty) or value.size() > limit: return false
	var seen := {}
	for item: Variant in value:
		if not _id(item) or seen.has(item): return false
		seen[item] = true
	return true


static func _id(value: Variant) -> bool:
	if not _text(value, 80) or value != value.strip_edges(): return false
	var expression := RegEx.new()
	expression.compile("^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
	return expression.search(value) != null


static func _unit(value: PackedFloat64Array, size: int) -> bool:
	if not _vector(value, size, 2.0): return false
	var norm2 := 0.0
	for number: float in value: norm2 += number * number
	return absf(norm2 - 1.0) <= UNIT_TOLERANCE


static func _vector(value: PackedFloat64Array, size: int, bound: float) -> bool:
	if value.size() != size: return false
	for number: float in value:
		if not is_finite(number) or absf(number) > bound: return false
	return true


static func _keys(value: Variant, expected: Array) -> bool:
	return value is Dictionary and value.size() == expected.size() and value.has_all(expected)


static func _text(value: Variant, limit: int) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty() and value.length() <= limit


static func _angle(value: float) -> float:
	return M.atan2_(M.sin_(value), M.cos_(value))


static func _hash(value: Dictionary) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


static func _digest(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 64: return false
	for character: String in value:
		if character not in "0123456789abcdef": return false
	return true


static func _bounded_tree(value: Variant, depth: int) -> bool:
	if depth > 6: return false
	if value is Dictionary:
		if value.size() > 32: return false
		for key: Variant in value:
			if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 80 or not _bounded_tree(value[key], depth + 1): return false
		return true
	if value is Array:
		if value.size() > MAX_HULL: return false
		for item: Variant in value:
			if not _bounded_tree(item, depth + 1): return false
		return true
	if typeof(value) == TYPE_STRING: return value.length() <= 2048
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]: return is_finite(float(value))
	return typeof(value) == TYPE_BOOL


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}
