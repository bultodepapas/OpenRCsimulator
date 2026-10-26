## Complete coarse/fine aircraft path accuracy. No integrator or conservation
## acceptance law. Numerical quality and physical layout have separate owners.
extends RefCounted

const Q := preload("res://physics/wheel_profiles.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const FORMAT := "openrc-aircraft-ground-accuracy v1"
const LAYOUT_FORMAT := "openrc-aircraft-ground-accuracy-layout v1"
const LAW := "complete-split-path-SI-accuracy-local-tick-v1"
const RECEIPT_FORMAT := "openrc-aircraft-ground-integration v1"
const WORK_KEYS := ["external_work_j", "tangent_dissipation_j", "normal_dissipation_j", "prescribed_contact_work_j"]
const BODY_UNITS := {position = "m", velocity_cm = "m/s", attitude = "rad", angular_rate = "rad/s"}
const UNITS := ["rpm", "rad/s", "m/s", "m", "1", "J", "K", "kg", "C", "s", "N"]
const MAX_STATE := 256
const EPSILON := 2.220446049250313e-16


## raw contains explicit provenance quantities: quality_name/source, body
## tolerances, continuous{id:tolerance}, normal_peak, four work tolerances and
## time_tolerance. A tolerance is {absolute,relative,floor}; work also declares
## scale_sources (only named J ledgers, never stored shaft kinetic energy).
## layout is the compiled physical owner's descriptor: identities, fixed CG,
## state_size, continuous_start=13, fully covering {id,indices:int64[],unit}
## blocks, contact IDs and Step law/order. It authors no second CG/radius truth.
static func prepare(raw: Dictionary, layout: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	if not _keys(raw, ["format", "quality_name", "source", "body", "continuous", "normal_peak", "work", "time_tolerance"]) \
		or raw.get("format") != FORMAT or not _text(raw.get("quality_name"), 128) or not _text(raw.get("source"), 1024):
		return _failure("explicit versioned numerical quality name/source and fields required")
	if not _keys(layout, ["format", "identity", "state_layout_id", "state_size", "continuous_start", "cg_body_m", "blocks", "contact_ids", "step_law", "operator_order"]) \
		or layout.get("format") != LAYOUT_FORMAT or not _text(layout.get("identity"), 256) or not _text(layout.get("state_layout_id"), 256) \
		or not _text(layout.get("step_law"), 256) or typeof(layout.get("state_size")) != TYPE_INT \
		or layout.state_size < RB.SIZE or layout.state_size > MAX_STATE or typeof(layout.get("continuous_start")) != TYPE_INT or layout.continuous_start != RB.SIZE \
		or typeof(layout.get("operator_order")) != TYPE_INT or layout.operator_order not in [1, 2, 4] \
		or not _vector(layout.get("cg_body_m")) or typeof(layout.get("blocks")) != TYPE_ARRAY or layout.blocks.size() > 64 \
		or typeof(layout.get("contact_ids")) != TYPE_PACKED_STRING_ARRAY or layout.contact_ids.size() > 16:
		return _failure("invalid compiled physical layout/CG/Step binding")
	if not _unique_ids(layout.contact_ids): return _failure("contact identity layout is invalid")
	var body := {}
	if not _keys(raw.body, BODY_UNITS.keys()) or typeof(raw.continuous) != TYPE_DICTIONARY or not _keys(raw.work, WORK_KEYS):
		return _failure("complete body/continuous/work quality declarations required")
	for key: String in BODY_UNITS: body[key] = _tolerance(raw.body[key], BODY_UNITS[key], false, errors)
	var normal := _tolerance(raw.normal_peak, "N", false, errors)
	var work := {}
	for key: String in WORK_KEYS: work[key] = _tolerance(raw.work[key], "J", true, errors)
	var time_tolerance := _quantity(raw.time_tolerance, "s", 1e-15, 1e-3, errors)
	var blocks: Array = []
	var ids := {}
	var covered := PackedByteArray()
	covered.resize(layout.state_size)
	for value: Variant in layout.blocks:
		if not _keys(value, ["id", "indices", "unit"]) or not _text(value.get("id"), 128) \
			or ids.has(value.id) or typeof(value.get("indices")) != TYPE_PACKED_INT64_ARRAY or value.indices.is_empty() \
			or value.indices.size() > MAX_STATE or typeof(value.get("unit")) != TYPE_STRING or value.unit not in UNITS:
			return _failure("invalid/duplicate continuous physical block or units")
		ids[value.id] = true
		if not raw.continuous.has(value.id): return _failure("continuous physical block has no numerical quality")
		for index: int in value.indices:
			if index < RB.SIZE or index >= layout.state_size or covered[index] != 0:
				return _failure("continuous index is outside layout or multiply covered")
			covered[index] = 1
		var unit: String = "rad/s" if value.unit == "rpm" else value.unit
		blocks.append({id = value.id, indices = value.indices.duplicate(), state_unit = value.unit, unit = unit,
			scale = TAU / 60.0 if value.unit == "rpm" else 1.0,
			tolerance = _tolerance(raw.continuous[value.id], unit, false, errors)})
	if raw.continuous.size() != ids.size(): return _failure("quality contains an unknown continuous block")
	for index in range(RB.SIZE, layout.state_size):
		if covered[index] != 1: return _failure("continuous layout has an uncovered state")
	if not errors.is_empty(): return _failure("; ".join(errors))
	var layout_identity := (LAW + JSON.stringify(layout, "", true, true)).sha256_text()
	var identity := (LAW + layout_identity + JSON.stringify(raw, "", true, true)).sha256_text()
	var prepared := {ok = true, format = FORMAT, law = LAW, identity = identity, layout_identity = layout_identity,
		quality_name = raw.quality_name, state_size = layout.state_size, cg_body_m = layout.cg_body_m.duplicate(),
		body = body, blocks = blocks, normal_peak = normal, work = work, time_tolerance_s = time_tolerance,
		layout = layout.duplicate(true), provenance = raw.duplicate(true)}
	prepared.seal = _seal(prepared)
	return prepared


## EXACT four-key result accepted by AircraftGroundStep.error_gate. Bind the
## prepared resource to the chosen model/layout at the runtime owner boundary.
## Existing Step receipts do not self-authenticate that physical model binding.
static func compare(prepared: Dictionary, coarse: PackedFloat64Array, fine: PackedFloat64Array,
		coarse_receipt: Dictionary, fine_receipt: Dictionary, dt: float) -> Dictionary:
	var result := diagnose(prepared, coarse, fine, coarse_receipt, fine_receipt, dt)
	return {ok = result.ok, admitted = result.admitted, identity = result.identity, normalized_error = result.normalized_error}


## Read-only per-channel diagnostics. Raw split differences, no Richardson/15.
## Receipt algebra is checked; conservation residual magnitudes are only
## reported. This gate does not certify conservation or global trajectory error.
static func diagnose(prepared: Dictionary, coarse: PackedFloat64Array, fine: PackedFloat64Array,
		coarse_receipt: Dictionary, fine_receipt: Dictionary, dt: float) -> Dictionary:
	var id: String = prepared.identity if _text(prepared.get("identity"), 256) else LAW
	if not _prepared(prepared): return _failure("prepared quality/layout was altered or is invalid", id)
	if not _state(coarse, prepared.state_size) or not _state(fine, prepared.state_size) or not is_finite(dt) or dt <= 0.0 or dt > 1.0:
		return _failure("finite complete state and bounded positive tick required", id)
	if prepared.time_tolerance_s >= dt / 4.0: return _failure("receipt clock tolerance is too large for this tick", id)
	var ca := _receipt(prepared, coarse_receipt, dt)
	var cb := _receipt(prepared, fine_receipt, dt)
	if not ca.ok or not cb.ok: return _failure(str(ca.get("reason", cb.get("reason", "invalid receipt"))), id)
	if fine_receipt.accepted_substeps != 2 * coarse_receipt.accepted_substeps \
		or absf(coarse_receipt.normal_sample_times_s[0] - fine_receipt.normal_sample_times_s[0]) > prepared.time_tolerance_s \
		or coarse_receipt.contact_ids != fine_receipt.contact_ids:
		return _failure("coarse/fine paths do not share a tick and adjacent n/2n contact layout", id)
	var initial_scale := maxf(absf(coarse_receipt.initial_mechanical_energy_j), absf(fine_receipt.initial_mechanical_energy_j))
	if absf(coarse_receipt.initial_mechanical_energy_j - fine_receipt.initial_mechanical_energy_j) > 128 * EPSILON * maxf(1e-300, initial_scale):
		return _failure("coarse/fine receipts have different initial mechanical energy", id)
	var qa := M.q_normalized(coarse.slice(RB.ATT, RB.ATT + 4))
	var qb := M.q_normalized(fine.slice(RB.ATT, RB.ATT + 4))
	var va := M.q_rotate(qa, M.add(coarse.slice(RB.VEL, RB.VEL + 3), M.cross(coarse.slice(RB.RATE, RB.RATE + 3), prepared.cg_body_m)))
	var vb := M.q_rotate(qb, M.add(fine.slice(RB.VEL, RB.VEL + 3), M.cross(fine.slice(RB.RATE, RB.RATE + 3), prepared.cg_body_m)))
	if not _finite(va) or not _finite(vb): return _failure("CM kinematics overflow", id)
	var channels := {}
	var maximum := 0.0
	var speed := maxf(M.norm(va), M.norm(vb))
	for i in 3:
		maximum = maxf(maximum, _record(channels, "position:" + str(i), absf(coarse[i] - fine[i]), maxf(prepared.body.position.floor, speed * dt), prepared.body.position, "m"))
		maximum = maxf(maximum, _record(channels, "velocity_cm:" + str(i), absf(va[i] - vb[i]), maxf(prepared.body.velocity_cm.floor, speed), prepared.body.velocity_cm, "m/s"))
		maximum = maxf(maximum, _record(channels, "angular_rate:" + str(i), absf(coarse[RB.RATE + i] - fine[RB.RATE + i]),
			maxf(prepared.body.angular_rate.floor, maxf(absf(coarse[RB.RATE + i]), absf(fine[RB.RATE + i]))), prepared.body.angular_rate, "rad/s"))
	var relative := M.q_mul(M.q_conj(qa), qb)
	var angle := 2.0 * M.atan2_(M.norm(relative.slice(1)), absf(relative[0]))
	maximum = maxf(maximum, _record(channels, "attitude", angle, prepared.body.attitude.floor, prepared.body.attitude, "rad"))
	for block: Dictionary in prepared.blocks:
		for index: int in block.indices:
			var a: float = coarse[index] * block.scale
			var b: float = fine[index] * block.scale
			maximum = maxf(maximum, _record(channels, "continuous:" + block.id + ":" + str(index), absf(a - b),
				maxf(block.tolerance.floor, maxf(absf(a), absf(b))), block.tolerance, block.unit))
	for i in coarse_receipt.contact_ids.size():
		var a: float = coarse_receipt.sampled_peak_normal_n[i]
		var b: float = fine_receipt.sampled_peak_normal_n[i]
		maximum = maxf(maximum, _record(channels, "sampled_normal_peak:" + coarse_receipt.contact_ids[i], absf(a - b),
			maxf(prepared.normal_peak.floor, maxf(a, b)), prepared.normal_peak, "N"))
	for key: String in WORK_KEYS:
		var tolerance: Dictionary = prepared.work[key]
		var scale: float = tolerance.floor
		for source: String in tolerance.scale_sources:
			scale = maxf(scale, maxf(absf(coarse_receipt[source]), absf(fine_receipt[source])))
		maximum = maxf(maximum, _record(channels, "work:" + key, absf(coarse_receipt[key] - fine_receipt[key]), scale, tolerance, "J"))
	if not is_finite(maximum): return _failure("accuracy arithmetic exceeds finite numeric range", id)
	return {ok = true, admitted = maximum <= 1.0, identity = id, normalized_error = maximum,
		layout_identity = prepared.layout_identity, quality_name = prepared.quality_name, channels = channels,
		scope = "one_tick_complete_path_accuracy_not_global_trajectory_or_conservation",
		conservation_certificate = false,
		conservation_residuals_j = PackedFloat64Array([coarse_receipt.energy_balance_residual_j, fine_receipt.energy_balance_residual_j])}


static func _receipt(prepared: Dictionary, r: Dictionary, dt: float) -> Dictionary:
	var expected: Dictionary = prepared.layout
	if not _bounded(r, 0, {left = 4096}) or r.get("format") != RECEIPT_FORMAT or r.get("law") != expected.step_law \
		or r.get("contact_operator_order") != expected.operator_order or typeof(r.get("accepted_substeps")) != TYPE_INT \
		or r.accepted_substeps not in [1, 2, 4, 8, 16] or typeof(r.get("contact_ids")) != TYPE_PACKED_STRING_ARRAY \
		or r.contact_ids != expected.contact_ids or typeof(r.get("normal_sample_times_s")) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(r.get("normal_samples_n")) != TYPE_ARRAY or typeof(r.get("sampled_peak_normal_n")) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(r.get("sampled_peak_times_s")) != TYPE_PACKED_FLOAT64_ARRAY:
		return _failure("receipt format/law/contact layout or bounded data is invalid")
	var n: int = r.accepted_substeps
	var m: int = expected.contact_ids.size()
	if r.normal_sample_times_s.size() != n + 1 or r.normal_samples_n.size() != n + 1 \
		or r.sampled_peak_normal_n.size() != m or r.sampled_peak_times_s.size() != m:
		return _failure("receipt sample/peak dimensions disagree")
	if r.get("normal_sampling_method") != "accepted_substep_start_and_end_states_not_interval_maximum" \
		or r.get("quadrature_method") != "RK4_algebraic_stage_weights_not_damage_samples":
		return _failure("receipt sampling/quadature contract differs")
	var start: float = r.normal_sample_times_s[0]
	if start < 0.0: return _failure("negative receipt clock")
	var peak := PackedFloat64Array()
	var peak_times := PackedFloat64Array()
	peak.resize(m)
	peak_times.resize(m)
	for i in n + 1:
		if absf(r.normal_sample_times_s[i] - (start + dt * float(i) / n)) > prepared.time_tolerance_s:
			return _failure("stale receipt tick or nonuniform accepted sample clock")
		if i > 0 and r.normal_sample_times_s[i] <= r.normal_sample_times_s[i - 1]: return _failure("receipt clock did not advance")
		var values: Variant = r.normal_samples_n[i]
		if typeof(values) != TYPE_PACKED_FLOAT64_ARRAY or values.size() != m: return _failure("invalid accepted normal sample")
		for j in m:
			if values[j] < 0.0: return _failure("negative normal reaction")
			if i == 0 or values[j] > peak[j]:
				peak[j] = values[j]
				peak_times[j] = r.normal_sample_times_s[i]
	for i in m:
		if r.sampled_peak_times_s[i] < 0.0 or r.sampled_peak_normal_n[i] != peak[i] or absf(r.sampled_peak_times_s[i] - peak_times[i]) > prepared.time_tolerance_s:
			return _failure("sampled peak was altered or is not an accepted boundary sample")
	for key: String in WORK_KEYS + ["initial_mechanical_energy_j", "final_mechanical_energy_j", "energy_balance_residual_j", "maximum_piece_energy_residual_j", "absolute_impulse_sum"]:
		if not _number(r.get(key)): return _failure("missing/nonfinite work or energy diagnostic")
	for key: String in ["tangent_dissipation_j", "normal_dissipation_j", "maximum_piece_energy_residual_j", "absolute_impulse_sum"]:
		if r[key] < 0.0: return _failure("negative heat/loss diagnostic")
	var algebra: float = r.final_mechanical_energy_j - r.initial_mechanical_energy_j + r.normal_dissipation_j + r.tangent_dissipation_j - r.external_work_j - r.prescribed_contact_work_j
	var magnitude: float = absf(r.final_mechanical_energy_j) + absf(r.initial_mechanical_energy_j) + absf(r.normal_dissipation_j) + absf(r.tangent_dissipation_j) + absf(r.external_work_j) + absf(r.prescribed_contact_work_j)
	if not is_finite(algebra) or not is_finite(magnitude) or absf(algebra - r.energy_balance_residual_j) > 128 * EPSILON * maxf(1e-300, magnitude):
		return _failure("receipt work/residual algebra was altered")
	if r.has("accuracy_layout_identity") and r.accuracy_layout_identity != prepared.layout_identity:
		return _failure("owner-supplied receipt layout pin is stale")
	if r.has("state_layout_identity") and r.state_layout_identity != expected.state_layout_id:
		return _failure("owner-supplied receipt state layout differs")
	return {ok = true}


static func _tolerance(value: Variant, unit: String, work: bool, errors: PackedStringArray) -> Dictionary:
	var keys := ["absolute", "relative", "floor", "scale_sources"] if work else ["absolute", "relative", "floor"]
	if not _keys(value, keys):
		errors.append("explicit absolute/relative/positive floor tolerance required")
		return {}
	var result := {absolute = _quantity(value.absolute, unit, 1e-15, 1e12, errors),
		relative = _quantity(value.relative, "1", 0.0, 1.0, errors), floor = _quantity(value.floor, unit, 1e-15, 1e12, errors)}
	if result.relative >= 1.0: errors.append("relative tolerance must be below one")
	if work:
		if typeof(value.scale_sources) != TYPE_ARRAY or value.scale_sources.is_empty() or value.scale_sources.size() > 4:
			errors.append("work scale_sources must explicitly name J ledgers")
		else:
			var seen := {}
			for key: Variant in value.scale_sources:
				if typeof(key) != TYPE_STRING or key not in WORK_KEYS or seen.has(key): errors.append("unknown/duplicate work scale source")
				seen[key] = true
			result.scale_sources = value.scale_sources.duplicate()
	return result


static func _quantity(value: Variant, unit: String, low: float, high: float, errors: PackedStringArray) -> float:
	Q._validate_quantity("accuracy quantity", value, [unit, low, high], errors)
	if value is Dictionary and typeof(value.get("source")) == TYPE_STRING and value.source.length() > 1024:
		errors.append("quantity source exceeds the bounded resource contract")
	if not value is Dictionary or not _number(value.get("value")): return 0.0
	return float(value.value)


static func _record(channels: Dictionary, key: String, delta: float, scale: float, tolerance: Dictionary, unit: String) -> float:
	var denominator: float = tolerance.absolute + tolerance.relative * scale
	var normalized := delta / denominator
	channels[key] = {absolute_difference = delta, scale = scale, bound = denominator, normalized_error = normalized, unit = unit}
	return normalized if is_finite(delta) and is_finite(scale) and is_finite(denominator) and denominator > 0.0 and is_finite(normalized) else INF


static func _prepared(p: Dictionary) -> bool:
	if not _keys(p, ["ok", "format", "law", "identity", "layout_identity", "quality_name", "state_size", "cg_body_m", "body", "blocks", "normal_peak", "work", "time_tolerance_s", "layout", "provenance", "seal"]) \
		or p.format != FORMAT or p.law != LAW or typeof(p.ok) != TYPE_BOOL or not p.ok \
		or not _text(p.identity, 256) or not _text(p.layout_identity, 256) or typeof(p.state_size) != TYPE_INT \
		or p.state_size < RB.SIZE or p.state_size > MAX_STATE or not _vector(p.cg_body_m) \
		or not _keys(p.body, BODY_UNITS.keys()) or not _keys(p.work, WORK_KEYS) or not p.blocks is Array \
		or p.blocks.size() > 64 or not p.layout is Dictionary or not p.provenance is Dictionary \
		or not _number(p.time_tolerance_s) or p.time_tolerance_s <= 0 \
		or typeof(p.seal) != TYPE_STRING or not _bounded(p, 0, {left = 16384}): return false
	var raw: Dictionary = p.provenance
	if not _keys(raw, ["format", "quality_name", "source", "body", "continuous", "normal_peak", "work", "time_tolerance"]) \
		or raw.format != FORMAT or not _text(raw.quality_name, 128) or not _text(raw.source, 1024) \
		or raw.quality_name != p.quality_name or not _keys(raw.body, BODY_UNITS.keys()) \
		or not raw.continuous is Dictionary or not _keys(raw.work, WORK_KEYS): return false
	var l: Dictionary = p.layout
	if not _keys(l, ["format", "identity", "state_layout_id", "state_size", "continuous_start", "cg_body_m", "blocks", "contact_ids", "step_law", "operator_order"]) \
		or l.format != LAYOUT_FORMAT or typeof(l.state_size) != TYPE_INT or l.state_size != p.state_size \
		or typeof(l.continuous_start) != TYPE_INT or l.continuous_start != RB.SIZE or l.cg_body_m != p.cg_body_m \
		or not _text(l.identity, 256) or not _text(l.state_layout_id, 256) or not _text(l.step_law, 256) \
		or typeof(l.operator_order) != TYPE_INT or l.operator_order not in [1, 2, 4] \
		or not l.blocks is Array or l.blocks.size() != p.blocks.size() \
		or typeof(l.contact_ids) != TYPE_PACKED_STRING_ARRAY or l.contact_ids.size() > 16 or not _unique_ids(l.contact_ids): return false
	for key: String in BODY_UNITS:
		if not _compiled_tolerance(p.body[key], false) or not _tolerance_matches(p.body[key], raw.body[key], BODY_UNITS[key], false): return false
	if not _compiled_tolerance(p.normal_peak, false) or not _tolerance_matches(p.normal_peak, raw.normal_peak, "N", false): return false
	for key: String in WORK_KEYS:
		if not _compiled_tolerance(p.work[key], true) or not _tolerance_matches(p.work[key], raw.work[key], "J", true): return false
	var covered := PackedByteArray()
	covered.resize(p.state_size)
	var block_ids := {}
	for i in p.blocks.size():
		var block: Variant = p.blocks[i]
		if not _keys(block, ["id", "indices", "state_unit", "unit", "scale", "tolerance"]) \
			or not _text(block.id, 128) or typeof(block.indices) != TYPE_PACKED_INT64_ARRAY \
			or block.indices.is_empty() or block_ids.has(block.id) or block.state_unit not in UNITS \
			or not _number(block.scale) or block.scale != (TAU / 60.0 if block.state_unit == "rpm" else 1.0) \
			or block.unit != ("rad/s" if block.state_unit == "rpm" else block.state_unit) \
			or not _compiled_tolerance(block.tolerance, false) or not _keys(l.blocks[i], ["id", "indices", "unit"]) \
			or l.blocks[i].id != block.id or l.blocks[i].indices != block.indices or l.blocks[i].unit != block.state_unit \
			or not raw.continuous.has(block.id) or not _tolerance_matches(block.tolerance, raw.continuous[block.id], block.unit, false): return false
		block_ids[block.id] = true
		for index: int in block.indices:
			if index < RB.SIZE or index >= p.state_size or covered[index] != 0: return false
			covered[index] = 1
	for index in range(RB.SIZE, p.state_size):
		if covered[index] == 0: return false
	if raw.continuous.size() != block_ids.size() or not _quantity_matches(raw.time_tolerance, "s", p.time_tolerance_s) \
		or p.time_tolerance_s < 1e-15 or p.time_tolerance_s > 1e-3: return false
	var pin := (LAW + JSON.stringify(l, "", true, true)).sha256_text()
	return pin == p.layout_identity and (LAW + pin + JSON.stringify(raw, "", true, true)).sha256_text() == p.identity and _seal(p) == p.seal


static func _tolerance_matches(compiled: Dictionary, raw: Variant, unit: String, work: bool) -> bool:
	if not _keys(raw, ["absolute", "relative", "floor", "scale_sources"] if work else ["absolute", "relative", "floor"]): return false
	for key: String in ["absolute", "relative", "floor"]:
		if not _quantity_matches(raw[key], "1" if key == "relative" else unit, compiled[key]): return false
	return not work or raw.scale_sources == compiled.scale_sources


static func _quantity_matches(q: Variant, unit: String, value: float) -> bool:
	return _keys(q, ["value", "unit", "kind", "source"]) and _number(q.value) and float(q.value) == value \
		and typeof(q.unit) == TYPE_STRING and q.unit == unit and typeof(q.kind) == TYPE_STRING and q.kind in Q.KINDS \
		and typeof(q.source) == TYPE_STRING and not q.source.strip_edges().is_empty() and q.source.length() <= 1024


static func _compiled_tolerance(value: Variant, work: bool) -> bool:
	var keys := ["absolute", "relative", "floor", "scale_sources"] if work else ["absolute", "relative", "floor"]
	if not _keys(value, keys) or not _number(value.absolute) or value.absolute <= 0 \
		or not _number(value.relative) or value.relative < 0 or value.relative >= 1 \
		or not _number(value.floor) or value.floor <= 0 \
		or value.absolute < 1e-15 or value.absolute > 1e12 or value.floor < 1e-15 or value.floor > 1e12: return false
	if work:
		if not value.scale_sources is Array or value.scale_sources.is_empty(): return false
		for key: Variant in value.scale_sources:
			if typeof(key) != TYPE_STRING or key not in WORK_KEYS: return false
	return true


static func _seal(p: Dictionary) -> String:
	var copy := p.duplicate(true)
	copy.erase("seal")
	return var_to_bytes(copy).hex_encode().sha256_text()


static func _keys(value: Variant, keys: Array) -> bool:
	return value is Dictionary and value.size() == keys.size() and value.has_all(keys)


static func _text(value: Variant, maximum: int) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value == value.strip_edges() and value.length() <= maximum


static func _unique_ids(ids: PackedStringArray) -> bool:
	var seen := {}
	for id: String in ids:
		if not _text(id, 128) or seen.has(id): return false
		seen[id] = true
	return true


static func _state(s: PackedFloat64Array, size: int) -> bool:
	if s.size() != size or not _finite(s): return false
	var norm := 0.0
	for i in 4: norm += s[RB.ATT + i] * s[RB.ATT + i]
	return is_finite(norm) and norm > 1e-24


static func _vector(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_FLOAT64_ARRAY and value.size() == 3 and _finite(value)


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true


static func _bounded(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth > 10 or budget.left <= 0: return false
	budget.left -= 1
	match typeof(value):
		TYPE_BOOL, TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME: return str(value).length() <= 1024
		TYPE_DICTIONARY:
			if value.size() > MAX_STATE: return false
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 256 or not _bounded(value[key], depth + 1, budget): return false
			return true
		TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			if value.size() > MAX_STATE: return false
			for item: Variant in value:
				if not _bounded(item, depth + 1, budget): return false
			return true
	return false


static func _failure(reason: String, id := LAW) -> Dictionary:
	return {ok = false, admitted = false, identity = id, normalized_error = 0.0, reason = reason}
