## GP-16: persistent failure of FIXED-HUB effective leg/tire compliance.
## Authored weaker spring/stop responses, unchanged geometry, mass and rotor inertia.
## Not a moving/collapsed leg, detached component, fracture calibration or peak locator.
extends RefCounted

const Stage := preload("res://physics/aircraft_ground_stage.gd")
const NormalStage := preload("res://physics/aircraft_ground_dynamics.gd")
const Normal := preload("res://physics/normal_compliance.gd")
const Damage := preload("res://physics/gear_damage.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const FORMAT := "openrc-attached-gear-response v1"
const LAW := "fixed-hub-weaker-compliance-attached-failure-v1"
const ALIGNMENT_TOLERANCE := 1e-9 # Numerical collinearity only, not an allowed impact angle.


## raw = {format, source, damage, supports:[{contact_id,failed_normal}],
##        component_axes:[{component_id,positive_load_axis_body:{value,unit,kind,source}}]}.
## Every support needs an explicit failed response, even when strength is unknown.
## The restricted elastic family proves U_failed(x)<=U_healthy(x) for all x.
## Damping remains passive but need not become smaller after failure.
static func prepare(raw: Variant, ground_profile: Dictionary, model: Dictionary) -> Dictionary:
	if not _bounded(raw, 0, {left = 32768}) or not _bounded(ground_profile, 0, {left = 32768}) \
		or not Damage._keys(raw, ["format", "source", "damage", "supports", "component_axes"]) \
		or typeof(raw.format) != TYPE_STRING \
		or raw.format != FORMAT or not Damage._source(raw.source) or not raw.supports is Array \
		or not raw.component_axes is Array:
		return _failure("invalid authored attached response")
	var binding := _model_binding(model)
	if not binding.ok or not _source_shapes(ground_profile, binding.model):
		return _failure("invalid healthy stage source binding")
	var healthy := Stage.prepare(ground_profile, binding.model)
	if not healthy.ok: return _failure("healthy aircraft stage did not prepare")
	var ids := PackedStringArray()
	for row: Dictionary in healthy.normal.supports: ids.append(row.contact_id)
	var damage := Damage.prepare(raw.damage, ids)
	if not damage.ok: return _failure("component capacity/binding did not prepare")
	if raw.supports.size() != ids.size() or raw.component_axes.size() != damage.profile.components.size():
		return _failure("every support and component requires exactly one response/axis")
	var failed: Array = []
	failed.resize(ids.size())
	for item: Variant in raw.supports:
		if not Damage._keys(item, ["contact_id", "failed_normal"]) or not Damage._id(item.contact_id) \
			or not ids.has(item.contact_id) or not item.failed_normal is Dictionary:
			return _failure("unknown support or invalid failed normal response")
		var index := ids.find(item.contact_id)
		if failed[index] != null: return _failure("duplicate failed response")
		var compiled := Normal.prepare(item.failed_normal)
		if not compiled.ok: return _failure("failed normal response did not prepare")
		var h: Dictionary = healthy.normal.supports[index].normal.values
		var f: Dictionary = compiled.values
		for key: String in ["stroke", "stop_scale", "stop_exponent"]:
			if f[key] != h[key]: return _failure("failed elastic family must retain stroke, stop scale and exponent")
		if f.stiffness > h.stiffness or f.stop_stiffness > h.stop_stiffness \
			or (f.stiffness == h.stiffness and f.stop_stiffness == h.stop_stiffness):
			return _failure("failure requires reduced stiffness or stop stiffness without elastic hardening")
		failed[index] = compiled
	var axes: Array = []
	axes.resize(damage.profile.components.size())
	for item: Variant in raw.component_axes:
		if not Damage._keys(item, ["component_id", "positive_load_axis_body"]) or not Damage._id(item.component_id):
			return _failure("invalid structural axis record")
		var index := -1
		for i in damage.profile.components.size():
			if damage.profile.components[i].component_id == item.component_id: index = i
		if index < 0 or axes[index] != null: return _failure("unknown or duplicate structural axis")
		var quantity: Variant = item.positive_load_axis_body
		if not Damage._keys(quantity, ["value", "unit", "kind", "source"]) or typeof(quantity.unit) != TYPE_STRING or quantity.unit != "1" \
			or quantity.kind not in Damage.QUANTITY_KINDS or not Damage._source(quantity.source) \
			or typeof(quantity.value) not in [TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or quantity.value.size() != 3:
			return _failure("structural axis requires a provenance-bearing dimensionless unit vector")
		var axis := PackedFloat64Array()
		for value: Variant in quantity.value:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return _failure("nonfinite structural axis")
			axis.append(float(value))
		if absf(M.dot(axis, axis) - 1.0) > ALIGNMENT_TOLERANCE: return _failure("structural axis must be unit length")
		axes[index] = axis
	var result := {ok = true, format = FORMAT, law = LAW, qualification = Damage.QUALIFICATION,
		source = str(raw.source), launch_available = false, healthy_stage = healthy,
		damage_profile = damage.profile, failed_normals = failed, positive_load_axes_body = axes,
		provenance = raw.duplicate(true), ground_source = ground_profile.duplicate(true), model_binding = binding.model}
	result.identity = Damage._digest(result)
	return result


## The prepared value is immutable. Failed flags select existing compliance;
## first-failure clocks/losses never become extra forces. A healthy selection is
## byte-identical to the original stage. A failed selection remains launch-unavailable.
static func select(prepared: Dictionary, modes: PackedInt64Array, losses: PackedFloat64Array, tick: int) -> Dictionary:
	if not _valid(prepared) or not Damage.validate_state(prepared.damage_profile, modes, losses, tick):
		return _failure("invalid prepared response or persistent component state")
	return {ok = true, stage = _selected(prepared, modes)}


## Evaluate accepted BOUNDARY state with the actual normal geometry/law, then
## change persistent modes and potential at that SAME state. The owner must locate
## failure time or qualify its sampling error; this API does not claim interval peaks.
## Do not call after a body filter discarded the accepted path. No published state,
## event or stage changes until the caller commits the complete returned transaction.
static func transition_at_boundary(prepared: Dictionary, modes: PackedInt64Array, losses: PackedFloat64Array,
		body: PackedFloat64Array, provider: Dictionary, spin_radps: PackedFloat64Array, motion: Array,
		context: Dictionary, generation_id: String, body_filter_applied: bool) -> Dictionary:
	if body_filter_applied or not Damage._clock(context): return _failure("discarded path or invalid accepted clock")
	var selected := select(prepared, modes, losses, context.tick)
	if not selected.ok: return selected
	var current := NormalStage.evaluate(selected.stage.normal, body, provider, context.time_s, spin_radps, motion)
	if not current.ok: return _failure("current normal geometry/response refused boundary")
	var component_count: int = prepared.damage_profile.components.size()
	var loads := PackedFloat64Array()
	var before := PackedFloat64Array()
	var after := PackedFloat64Array()
	loads.resize(component_count)
	before.resize(component_count)
	after.resize(component_count)
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	var inverse := PackedFloat64Array([q[0], -q[1], -q[2], -q[3]])
	for index in current.contacts.size():
		var contact: Dictionary = current.contacts[index]
		var component: int = prepared.damage_profile.support_to_component[index]
		if contact.normal_load_n > 0.0:
			var axis: PackedFloat64Array = prepared.positive_load_axes_body[component]
			if M.norm(M.sub(M.q_rotate(inverse, contact.normal_ned), axis)) > ALIGNMENT_TOLERANCE:
				return _failure("normal load is not aligned with the authored structural axis; wrench law required")
		loads[component] += contact.normal_load_n
		before[component] += contact.potential_j
		if contact.geometry_evaluated:
			var prospective := Normal.evaluate(prepared.failed_normals[index], -contact.gap_m, -contact.gap_rate_mps)
			if not prospective.ok: return _failure("failed response refused identical geometry")
			after[component] += prospective.potential_j
	var applied := Damage.transition(prepared.damage_profile, modes, losses, loads, before, after, context, generation_id)
	if not applied.ok: return applied
	var stage := _selected(prepared, applied.modes)
	var resulting := NormalStage.evaluate(stage.normal, body, provider, context.time_s, spin_radps, motion)
	if not resulting.ok: return _failure("resulting selected response refused boundary")
	for event: Dictionary in applied.events:
		event.response_law = LAW
		event.response_identity = prepared.identity
		event.sampling = "accepted_boundary_only_not_interval_peak"
		event.continuation = "authored_weaker_fixed_hub_compliance"
	applied.stage = stage
	applied.before_normal = current
	applied.after_normal = resulting
	applied.component_normal_loads_n = loads
	applied.response_identity = prepared.identity
	return applied


static func _selected(prepared: Dictionary, modes: PackedInt64Array) -> Dictionary:
	var result: Dictionary = prepared.healthy_stage.duplicate(true)
	var mask := PackedInt64Array()
	var changed := false
	for index in result.normal.supports.size():
		var component: int = prepared.damage_profile.support_to_component[index]
		var failed: bool = modes[Damage.MODE_STRIDE * component] == Damage.FAILED_ATTACHED
		mask.append(1 if failed else 0)
		if failed:
			changed = true
			result.normal.supports[index].normal = prepared.failed_normals[index].duplicate(true)
			result.normal.supports[index].normal_profile_id = "failed:" + prepared.failed_normals[index].identity
	if changed:
		result.normal.identity = Damage._digest([LAW, prepared.identity, mask, "normal"])
		result.identity = Damage._digest([LAW, prepared.identity, mask, "stage"])
	return result


static func _valid(prepared: Dictionary) -> bool:
	if not _bounded(prepared, 0, {left = 65536}) or not Damage._keys(prepared, ["ok", "format", "law", "qualification", "source", "launch_available",
		"healthy_stage", "damage_profile", "failed_normals", "positive_load_axes_body", "provenance", "ground_source", "model_binding", "identity"]) \
		or typeof(prepared.ok) != TYPE_BOOL or not prepared.ok or typeof(prepared.format) != TYPE_STRING \
		or prepared.format != FORMAT or typeof(prepared.law) != TYPE_STRING or prepared.law != LAW \
		or typeof(prepared.identity) != TYPE_STRING or not prepared.provenance is Dictionary \
		or not prepared.ground_source is Dictionary or not prepared.model_binding is Dictionary:
		return false
	# A public digest is an identity, not proof that compiled values match source.
	# Rebuild all compiled response, axis, hardware and rotor bindings. This is a
	# correctness-first path, not a qualified production performance claim.
	var rebuilt := prepare(prepared.provenance, prepared.ground_source, prepared.model_binding)
	return rebuilt.ok and var_to_bytes(rebuilt) == var_to_bytes(prepared)


static func _model_binding(model: Dictionary) -> Dictionary:
	if not model.get("propulsion") is Dictionary or not model.get("landing_gear") is Dictionary \
		or not model.get("wheel_profile") is Dictionary or typeof(model.get("inertia")) != TYPE_PACKED_FLOAT64_ARRAY:
		return {ok = false}
	var prop := {}
	for key: String in ["kind", "id", "rotor_inertia", "axis", "shaft", "glow"]:
		if model.propulsion.has(key): prop[key] = model.propulsion[key]
	var result := {inertia = model.inertia, propulsion = prop, wheel_profile = model.wheel_profile,
		landing_gear = {contacts = model.landing_gear.get("contacts")}}
	if not _bounded(result, 0, {left = 32768}): return {ok = false}
	return {ok = true, model = result.duplicate(true)}


static func _source_shapes(profile: Dictionary, model: Dictionary) -> bool:
	if not profile.get("supports") is Array or not profile.get("normal_profiles") is Dictionary \
		or not model.landing_gear.get("contacts") is Array or not model.propulsion.get("shaft", {}) is Dictionary \
		or typeof(model.propulsion.get("axis", PackedFloat64Array())) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(model.propulsion.get("rotor_inertia")) not in [TYPE_FLOAT, TYPE_INT]: return false
	for row: Variant in profile.supports:
		if not row is Dictionary or not row.get("normal") is Dictionary \
			or not row.normal.get("provenance") is Dictionary: return false
	return true


## Bound recursion before any duplicate/hash/compiler call. Cycles exceed depth;
## the shared node budget also bounds branching. Known primitive selector labels
## are type-checked before existing resource compilers compare string values.
static func _bounded(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth > 16 or budget.left <= 0: return false
	budget.left -= 1
	match typeof(value):
		TYPE_BOOL, TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_STRING, TYPE_STRING_NAME: return str(value).length() <= 4096
		TYPE_DICTIONARY:
			if value.size() > 4096: return false
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or str(key).length() > 256: return false
				if str(key) in ["format", "law", "kind", "unit", "support_type", "width_model", "center_model", "status"] \
					and typeof(value[key]) != TYPE_STRING: return false
				if not _bounded(value[key], depth + 1, budget): return false
			return true
		TYPE_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			if value.size() > 4096: return false
			for item: Variant in value:
				if not _bounded(item, depth + 1, budget): return false
			return true
	return false


static func _failure(reason: String) -> Dictionary:
	return {ok = false, law = LAW, errors = PackedStringArray([reason]), events = []}

## Project already committed component state/events into detached observer facts.
## No normal/geometry evaluation. Validate binding once at attach and on sparse
## transition batches; an owner should return its valid empty packet between events.
static func accepted_observation(prepared: Dictionary, modes: PackedInt64Array,
		losses: PackedFloat64Array, raw_events: Variant, context: Dictionary, generation_id: String) -> Dictionary:
	var initial_clock: bool = Damage._keys(context, ["tick", "time_s", "dt"]) \
		and typeof(context.tick) == TYPE_INT and context.tick == 0 \
		and typeof(context.time_s) == TYPE_FLOAT and context.time_s == 0.0 \
		and typeof(context.dt) == TYPE_FLOAT and is_finite(context.dt) and context.dt > 0.0
	if not _valid(prepared) or (not Damage._clock(context) and not initial_clock) or not Damage._id(generation_id) \
		or not Damage.validate_state(prepared.damage_profile, modes, losses, context.tick) \
		or not raw_events is Array or raw_events.size() > prepared.damage_profile.components.size(): return {}
	var records: Array[Dictionary] = []
	var seen := {}
	var keys := ["type", "event_id", "time_s", "tick", "generation_id", "component_id", "support_ids",
		"law", "profile_identity", "qualification", "criterion", "normal_load_n", "normal_failure_force_n",
		"transition_loss_j", "potential_before_j", "potential_after_j", "loss_provenance", "terminal", "continuation",
		"response_law", "response_identity", "sampling"]
	for raw: Variant in raw_events:
		if context.tick == 0: return {}
		if not Damage._keys(raw, keys): return {}
		for key: String in ["type", "event_id", "generation_id", "component_id", "law", "profile_identity",
			"qualification", "criterion", "loss_provenance", "continuation", "response_law", "response_identity", "sampling"]:
			if typeof(raw[key]) != TYPE_STRING: return {}
		if raw.type != "gear_failure" or raw.law != Damage.LAW or raw.response_law != LAW \
			or raw.profile_identity != prepared.damage_profile.identity or raw.response_identity != prepared.identity \
			or raw.generation_id != generation_id or raw.qualification != Damage.QUALIFICATION \
			or raw.criterion != "declared_normal_capacity_exceeded" \
			or raw.loss_provenance != "elastic_normal_stop_and_anchor_potential_before_minus_after_at_same_body_state" \
			or raw.continuation != "authored_weaker_fixed_hub_compliance" \
			or raw.sampling != "accepted_boundary_only_not_interval_peak" \
			or typeof(raw.terminal) != TYPE_BOOL or raw.terminal or typeof(raw.tick) != TYPE_INT \
			or raw.tick != context.tick or typeof(raw.time_s) != TYPE_FLOAT or raw.time_s != context.time_s \
			or typeof(raw.support_ids) != TYPE_PACKED_STRING_ARRAY or seen.has(raw.component_id): return {}
		var index := -1
		for i in prepared.damage_profile.components.size():
			if prepared.damage_profile.components[i].component_id == raw.component_id: index = i
		if index < 0: return {}
		var component: Dictionary = prepared.damage_profile.components[index]
		if not component.strength_known or raw.support_ids != component.support_ids \
			or modes[index * Damage.MODE_STRIDE] != Damage.FAILED_ATTACHED \
			or modes[index * Damage.MODE_STRIDE + 1] != context.tick \
			or raw.event_id != "gd1:" + Damage._digest([Damage.LAW, generation_id, component.component_id, context.tick]): return {}
		for key: String in ["normal_load_n", "normal_failure_force_n", "transition_loss_j", "potential_before_j", "potential_after_j"]:
			if typeof(raw[key]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(raw[key])) or raw[key] < 0.0: return {}
		if raw.normal_failure_force_n != component.normal_failure_force.value or raw.normal_load_n <= raw.normal_failure_force_n \
			or raw.potential_after_j > raw.potential_before_j or raw.transition_loss_j != losses[index]: return {}
		var scale: float = maxf(raw.potential_before_j, maxf(raw.potential_after_j, raw.transition_loss_j))
		if absf(raw.potential_before_j - raw.potential_after_j - raw.transition_loss_j) > 16.0 * Damage.FLOAT_EPSILON * maxf(scale, 1e-300): return {}
		seen[raw.component_id] = true
		records.append({component_id = raw.component_id, contact_ids = Array(component.support_ids),
			law_identity = LAW, accepted_tick = context.tick,
			physical_evidence = {source_event_id = raw.event_id, source_generation_id = generation_id,
				damage_profile_identity = prepared.damage_profile.identity, response_identity = prepared.identity,
				qualification = Damage.QUALIFICATION, sampling = raw.sampling, criterion = raw.criterion, response_mode = "failed_attached"},
			measurements = {normal_load_n = float(raw.normal_load_n), normal_failure_force_n = float(raw.normal_failure_force_n),
				potential_before_j = float(raw.potential_before_j), potential_after_j = float(raw.potential_after_j),
				transition_loss_j = float(raw.transition_loss_j), confirmation_tick = context.tick, sample_interval_s = context.dt}})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.component_id < b.component_id)
	return {schema = "openrc-aircraft-component-failure-observation", version = 1, tick = context.tick,
		generation_id = generation_id, identity = prepared.identity, available = true, events = records, reason = ""}
