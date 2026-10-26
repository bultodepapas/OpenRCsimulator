## Reservation for the model-bound integrated operator after a freshly published original pre-QP.
## The caller binds the exact prepublication and stable row/group topology.
## Containment reuses its original finite-precision membership contract; it is
## not a new claim of exact-real membership beyond the original publisher.
extends RefCounted
const AR := preload("res://physics/contact_assembly_resolution.gd")
const M := preload("res://physics/math3d.gd")


static func reserve_published_group(
	published_impulse: PackedFloat64Array,
	pre_half_limits: PackedFloat64Array,
	actual_half_limits: PackedFloat64Array
) -> Dictionary:
	if (
		published_impulse.size() not in [1, 2]
		or pre_half_limits.size() != published_impulse.size()
		or actual_half_limits.size() != published_impulse.size()
	):
		return {ok = false, status = "invalid"}
	var contained := true
	for i in published_impulse.size():
		if (
			not is_finite(published_impulse[i])
			or not is_finite(pre_half_limits[i])
			or not is_finite(actual_half_limits[i])
			or pre_half_limits[i] < 0.0
			or actual_half_limits[i] < 0.0
		):
			return {ok = false, status = "invalid"}
		if absf(published_impulse[i]) > pre_half_limits[i]:
			return {ok = false, status = "invalid_pre_publication"}
		contained = contained and pre_half_limits[i] <= actual_half_limits[i]
	if contained:
		return {
			ok = true,
			status = "contained_original_membership",
			post_limits = actual_half_limits.duplicate(),
			pre_full_budget_fraction_upper = 0.5
		}
	if published_impulse.size() == 1:
		# full=2*half is exact in supported finite binary64. When |published_impulse|>half,
		# full and |published_impulse| differ by at most a factor2, so Sterbenz subtraction
		# full-|published_impulse| is exact (including gradual underflow). No sqrt/division.
		var full := 2.0 * actual_half_limits[0]
		if not is_finite(full):
			return {ok = false, status = "unsupported_arithmetic"}
		var used := absf(published_impulse[0])
		if used > full:
			return {
				ok = false, status = "refine", reason = "scalar preimpulse exceeds actual full cap"
			}
		var remaining := actual_half_limits[0] if used <= actual_half_limits[0] else full - used
		return {
			ok = true,
			status = "exact_scalar_actual_budget",
			post_limits = PackedFloat64Array([remaining]),
			pre_full_budget_fraction_upper =
			0.0 if full == 0.0 else (0.5 if used <= actual_half_limits[0] else 1.0)
		}
	var squared := 0.0
	for i in published_impulse.size():
		if actual_half_limits[i] == 0.0:
			if published_impulse[i] != 0.0:
				return {
					ok = false,
					status = "refine",
					reason = "nonzero preimpulse without actual capacity"
				}
			continue
		var full := 2.0 * actual_half_limits[i]
		if not is_finite(full) or full == 0.0:
			return {ok = false, status = "unsupported_arithmetic"}
		var ratio := AR._div(absf(published_impulse[i]), full)
		squared = AR._add(squared, AR._mul(ratio, ratio))
	if not is_finite(squared):
		return {ok = false, status = "unsupported_arithmetic"}
	var used := 0.0 if squared == 0.0 else AR._mul(M.sqrt_(squared), 1.0 + 4.0 * AR.EPS)
	if not is_finite(used):
		return {ok = false, status = "unsupported_arithmetic"}
	if used > 1.0:
		return {
			ok = false,
			status = "refine",
			reason = "preimpulse exceeds actual integrated group capacity",
			pre_full_budget_fraction_upper = used
		}
	var factor := minf(1.0, 2.0 * AR._one_minus(used))
	var post := PackedFloat64Array()
	for value: float in actual_half_limits:
		if factor == 1.0:
			post.append(value)
		else:
			post.append(_mul_down(value, factor))
		if not is_finite(post[-1]) or post[-1] < 0.0:
			return {ok = false, status = "unsupported_arithmetic"}
	return {
		ok = true,
		status = "outward_reserved_actual_budget",
		post_limits = post,
		pre_full_budget_fraction_upper = used,
		post_half_capacity_factor = factor
	}


static func _mul_down(a: float, b: float) -> float:
	if a == 0.0 or b == 0.0:
		return 0.0
	var product := a * b
	if not is_finite(product) or product < 0.0:
		return NAN
	if product == 0.0:
		return 0.0
	var bytes := PackedFloat64Array([product]).to_byte_array()
	var bits := bytes.decode_u64(0)
	bytes.encode_u64(0, bits - 1)
	return bytes.decode_double(0)


const FORMAT := "openrc-interval-contact-capacity v1"
const LAW := "fixed-plane-current-pose-normal-product-capacity-v1"
const RB := preload("res://physics/rigid_body.gd")
const Impulse := preload("res://physics/aircraft_ground_impulse.gd")
const COLUMNS := [
	"group_index",
	"contact_index",
	"dimension",
	"pre_p0",
	"pre_p1",
	"pre_half0",
	"pre_half1",
	"actual_half0",
	"actual_half1",
	"post_cap0",
	"post_cap1",
	"pre_fraction_upper",
	"proof_code"
]


## Packet metadata is not proof of the evaluator's physical ownership. Its
## trusted owner binds source/held configuration and the whole interval.
static func validate(
	raw: Variant, state: PackedFloat64Array, at: float, rotors: int, contacts: PackedStringArray
) -> Dictionary:
	if rotors < 1 or rotors > Impulse.MAX_ROTORS or contacts.size() > 16:
		return _packet_failure("capacity mechanical/contact bounds")
	var contact_set := {}
	for contact: String in contacts:
		if not _text(contact) or contact_set.has(contact):
			return _packet_failure("duplicate capacity contact identity")
		contact_set[contact] = true
	var keys := [
		"format",
		"law",
		"binding_identity",
		"time_s",
		"pose_state",
		"contact_ids",
		"row_ids",
		"group_ids",
		"jacobian",
		"bias",
		"groups",
		"row_contact_indices",
		"normal_first",
		"normal_last",
		"independent_rates"
	]
	if typeof(raw) != TYPE_DICTIONARY or raw.size() != keys.size() or not raw.has_all(keys):
		return _packet_failure("capacity packet fields")
	var packet: Dictionary = raw
	if (
		typeof(packet.format) != TYPE_STRING
		or packet.format != FORMAT
		or typeof(packet.law) != TYPE_STRING
		or packet.law != LAW
		or not _text(packet.binding_identity)
		or not _number(packet.time_s)
		or packet.time_s != at
		or typeof(packet.pose_state) != TYPE_PACKED_FLOAT64_ARRAY
		or packet.pose_state.size() != 7
		or typeof(packet.contact_ids) != TYPE_PACKED_STRING_ARRAY
		or packet.contact_ids != contacts
		or typeof(packet.row_ids) != TYPE_PACKED_STRING_ARRAY
		or typeof(packet.group_ids) != TYPE_PACKED_STRING_ARRAY
		or typeof(packet.groups) != TYPE_ARRAY
		or typeof(packet.row_contact_indices) != TYPE_PACKED_INT64_ARRAY
	):
		return _packet_failure("capacity identity, pose or layout")
	var pose := state.slice(0, 3)
	pose.append_array(state.slice(RB.ATT, RB.ATT + 4))
	if var_to_bytes(pose) != var_to_bytes(packet.pose_state):
		return _packet_failure("stale capacity pose")
	var rows: int = packet.row_ids.size()
	if (
		rows > Impulse.MAX_ROWS
		or packet.group_ids.size() != packet.groups.size()
		or packet.groups.size() > rows
		or packet.row_contact_indices.size() != rows
	):
		return _packet_failure("capacity row dimensions")
	for key: String in ["jacobian", "bias", "normal_first", "normal_last", "independent_rates"]:
		if (
			typeof(packet[key]) != TYPE_PACKED_FLOAT64_ARRAY
			or not _finite(packet[key])
			or packet[key].size() != (rows * (6 + rotors) if key == "jacobian" else rows)
		):
			return _packet_failure("capacity numeric dimensions")
	var unique := {}
	for id: String in packet.row_ids:
		if not _text(id) or unique.has(id):
			return _packet_failure("duplicate capacity row identity")
		unique[id] = true
	unique = {}
	for id: String in packet.group_ids:
		if not _text(id) or unique.has(id):
			return _packet_failure("duplicate capacity group identity")
		unique[id] = true
	var seen := PackedByteArray()
	seen.resize(rows)
	for group: Variant in packet.groups:
		if typeof(group) != TYPE_PACKED_INT32_ARRAY or group.size() not in [1, 2]:
			return _packet_failure("capacity group type/dimension")
		var dependency := -2
		for index: int in group:
			if index < 0 or index >= rows or seen[index] != 0:
				return _packet_failure("capacity group partition")
			seen[index] = 1
			var contact: int = packet.row_contact_indices[index]
			if (
				contact < -1
				or contact >= contacts.size()
				or (dependency != -2 and contact != dependency)
			):
				return _packet_failure("mixed capacity ownership")
			dependency = contact
			if (
				packet.normal_first[index] < 0.0
				or packet.normal_last[index] < 0.0
				or packet.independent_rates[index] < 0.0
				or packet.bias[index] != 0.0
			):
				return _packet_failure("negative or moving capacity")
			if contact == -1:
				if (
					group.size() != 1
					or packet.normal_first[index] != 0.0
					or packet.normal_last[index] != 0.0
				):
					return _packet_failure("independent torque mapping")
			elif packet.independent_rates[index] != 0.0:
				return _packet_failure("normal/independent double allocation")
	for value: int in seen:
		if value != 1:
			return _packet_failure("uncovered capacity row")
	return {ok = true}


static func same_binding(a: Dictionary, b: Dictionary) -> bool:
	for key: String in [
		"format",
		"law",
		"binding_identity",
		"contact_ids",
		"row_ids",
		"group_ids",
		"groups",
		"row_contact_indices",
		"normal_first",
		"normal_last",
		"independent_rates"
	]:
		if not a.has(key) or not b.has(key):
			return false
		if var_to_bytes(a[key]) != var_to_bytes(b[key]):
			return false
	return true


static func limits(packet: Dictionary, mean: PackedFloat64Array, half_h: float) -> Dictionary:
	if (
		mean.size() != packet.contact_ids.size()
		or not _finite(mean)
		or not is_finite(half_h)
		or half_h <= 0.0
	):
		return _packet_failure("invalid capacity integration")
	for value: float in mean:
		if value < 0.0:
			return _packet_failure("negative integrated normal load")
	var out := PackedFloat64Array()
	for i in packet.row_ids.size():
		var contact: int = packet.row_contact_indices[i]
		# Preserve original authored multiplication order, especially Crr*N*R.
		var rate: float = (
			packet.independent_rates[i]
			if contact == -1
			else (packet.normal_first[i] * mean[contact]) * packet.normal_last[i]
		)
		var limit: float = rate * half_h
		if (
			not is_finite(rate)
			or not is_finite(limit)
			or rate < 0.0
			or (rate > 0.0 and limit == 0.0)
		):
			return _packet_failure("capacity overflow/underflow")
		out.append(limit)
	return {ok = true, limits = out}


## Called only on this piece's freshly published Impulse result and exact caps.
## Stable row IDs AND original group topology must be bound before membership
## reuse. A row-label-only map cannot inherit interval feasibility as a disk.
static func reserve(
	published_pre: Dictionary,
	pre_packet: Dictionary,
	pre_limits: PackedFloat64Array,
	post_packet: Dictionary,
	actual_half: PackedFloat64Array
) -> Dictionary:
	if (
		not same_binding(pre_packet, post_packet)
		or not published_pre.get("ok", false)
		or typeof(published_pre.get("impulse")) != TYPE_PACKED_FLOAT64_ARRAY
		or published_pre.impulse.size() != pre_limits.size()
		or pre_limits.size() != actual_half.size()
	):
		return _packet_failure("changed original capacity topology or publication")
	var out := actual_half.duplicate()
	var compact := PackedFloat64Array()
	var contained := 0
	var adjusted := 0
	var internal := 0
	var maximum := 0.0
	for g in post_packet.groups.size():
		var group: PackedInt32Array = post_packet.groups[g]
		var pre_group_impulse := PackedFloat64Array()
		var pre_group_limits := PackedFloat64Array()
		var actual_group_half_limits := PackedFloat64Array()
		for index: int in group:
			pre_group_impulse.append(published_pre.impulse[index])
			pre_group_limits.append(pre_limits[index])
			actual_group_half_limits.append(actual_half[index])
		var dependency: int = post_packet.row_contact_indices[group[0]]
		var judged: Dictionary
		var code := 3.0
		if dependency == -1:
			if pre_group_limits != actual_group_half_limits:
				return _packet_failure("changed independent torque capacity")
			judged = {
				ok = true,
				post_limits = actual_group_half_limits.duplicate(),
				pre_full_budget_fraction_upper = 0.5
			}
			internal += 1
		else:
			judged = reserve_published_group(
				pre_group_impulse, pre_group_limits, actual_group_half_limits
			)
			if not judged.ok:
				return judged
			if judged.status == "contained_original_membership":
				code = 0.0
				contained += 1
			else:
				code = 2.0 if judged.status == "exact_scalar_actual_budget" else 1.0
				adjusted += 1
			maximum = maxf(maximum, judged.pre_full_budget_fraction_upper)
		for i in group.size():
			out[group[i]] = judged.post_limits[i]
		var n := group.size()
		compact.append_array(
			PackedFloat64Array(
				[
					float(g),
					float(dependency),
					float(n),
					pre_group_impulse[0],
					pre_group_impulse[1] if n == 2 else 0.0,
					pre_group_limits[0],
					pre_group_limits[1] if n == 2 else 0.0,
					actual_group_half_limits[0],
					actual_group_half_limits[1] if n == 2 else 0.0,
					judged.post_limits[0],
					judged.post_limits[1] if n == 2 else 0.0,
					judged.pre_full_budget_fraction_upper,
					code
				]
			)
		)
	return {
		ok = true,
		limits = out,
		compact = compact,
		summary =
		{
			contained_groups = contained,
			adjusted_groups = adjusted,
			independent_groups = internal,
			maximum_pre_fraction_upper = maximum
		}
	}


static func normal_mean(samples: Array, count: int) -> Dictionary:
	if samples.size() != 4:
		return _packet_failure("normal quadrature shape")
	for row: Variant in samples:
		if typeof(row) != TYPE_PACKED_FLOAT64_ARRAY or row.size() != count or not _finite(row):
			return _packet_failure("normal quadrature data")
		for value: float in row:
			if value < 0.0:
				return _packet_failure("negative normal quadrature")
	var mean := PackedFloat64Array()
	for i in count:
		var maximum := maxf(maxf(samples[0][i], samples[1][i]), maxf(samples[2][i], samples[3][i]))
		var value: float = (
			0.0
			if maximum == 0.0
			else (
				maximum
				* (
					(
						samples[0][i] / maximum
						+ 2.0 * (samples[1][i] / maximum)
						+ 2.0 * (samples[2][i] / maximum)
						+ samples[3][i] / maximum
					)
					/ 6.0
				)
			)
		)
		if not is_finite(value) or value < 0.0 or value > maximum:
			return _packet_failure("unsupported normal mean arithmetic")
		mean.append(value)
	return {ok = true, mean = mean}


static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 256


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _packet_failure(reason: String) -> Dictionary:
	return {ok = false, status = "invalid_capacity_packet", reason = reason}


## Contact arrays have arbitrary bounded length; Math3D vector helpers are3D.
static func normal_integrals(
	predicted: PackedFloat64Array, actual: PackedFloat64Array, h: float
) -> Dictionary:
	if (
		predicted.size() != actual.size()
		or predicted.size() > 16
		or not is_finite(h)
		or h <= 0.0
		or not _finite(predicted)
		or not _finite(actual)
	):
		return _packet_failure("normal integral shape/domain")
	var ip := PackedFloat64Array()
	var ia := PackedFloat64Array()
	var difference := PackedFloat64Array()
	var nominal := PackedFloat64Array()
	for i in predicted.size():
		if predicted[i] < 0.0 or actual[i] < 0.0:
			return _packet_failure("negative normal integral mean")
		ip.append(predicted[i] * h)
		ia.append(actual[i] * h)
		difference.append(ip[i] - ia[i])
		nominal.append((ip[i] + ia[i]) * 0.5)
	if not _finite(ip) or not _finite(ia) or not _finite(difference) or not _finite(nominal):
		return _packet_failure("normal integral overflow")
	return {ok = true, predicted = ip, actual = ia, difference = difference, nominal = nominal}


static func receipt_groups(packet: Dictionary) -> Array:
	var out: Array = []
	for group: PackedInt32Array in packet.groups:
		var indices := PackedInt64Array()
		for index: int in group:
			indices.append(index)
		out.append(indices)
	return out
