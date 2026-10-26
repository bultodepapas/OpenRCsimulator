## GP-16/17 experimental, attached-support normal-capacity model.
## Pure profile/state arithmetic: no contact solve, geometry/mass edit or physical calibration.
extends RefCounted

const FORMAT := "openrc-gear-damage v1"
const LAW := "experimental-brittle-normal-capacity-attached-v1"
const QUALIFICATION := "experimental_unvalidated"
const HEALTHY := 0
const FAILED_ATTACHED := 1
const MODE_STRIDE := 2
const MAX_COMPONENTS := 32
const MAX_SUPPORTS := 128
const MAX_ID_LENGTH := 128
const MAX_SOURCE_LENGTH := 1024
const MAX_SAFE_TICK := 9007199254740991
const FLOAT_EPSILON := 2.220446049250313e-16
## Same provenance vocabulary as aircraft v2; kept local to avoid an AircraftData import cycle.
const QUANTITY_KINDS := ["manual", "measured", "borrowed", "estimated", "derived"]


## Every installed support belongs to exactly one component. Components are ordered by ID.
## A missing normal_failure_force is unknown, never a default or zero strength.
static func prepare(raw: Variant, installed_support_ids: Variant) -> Dictionary:
	if not _keys(raw, ["format", "law", "source", "components"]) \
		or raw.format != FORMAT or raw.law != LAW or not _source(raw.source):
		return _failure("profile: expected the versioned experimental law, source and components")
	if typeof(raw.components) != TYPE_ARRAY or raw.components.size() > MAX_COMPONENTS:
		return _failure("components: expected a bounded array")
	var installed := _ids(installed_support_ids, MAX_SUPPORTS)
	if not installed.ok:
		return _failure("installed_support_ids: expected unique bounded IDs")
	var components: Array[Dictionary] = []
	var component_ids := {}
	var bound_supports := {}
	for item: Variant in raw.components:
		if not _keys(item, ["component_id", "support_ids", "source"], ["normal_failure_force"]) \
			or not _id(item.component_id) or not _source(item.source) or component_ids.has(item.component_id):
			return _failure("component: expected a unique component_id, source and support_ids")
		var supports := _ids(item.support_ids, MAX_SUPPORTS)
		if not supports.ok or supports.ids.is_empty():
			return _failure("component.support_ids: expected a nonempty unique bounded set")
		var support_ids: PackedStringArray = supports.ids
		support_ids.sort()
		var indices := PackedInt32Array()
		for support: String in support_ids:
			if not installed.ids.has(support) or bound_supports.has(support):
				return _failure("component.support_ids: unknown support or double binding")
			bound_supports[support] = true
			indices.append(installed.ids.find(support))
		var component := {component_id = str(item.component_id), support_ids = support_ids,
			support_indices = indices, source = str(item.source), strength_known = item.has("normal_failure_force")}
		if component.strength_known:
			var quantity: Variant = item.normal_failure_force
			if not _keys(quantity, ["value", "unit", "kind", "source"]) \
				or typeof(quantity.value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(quantity.value)) \
				or float(quantity.value) <= 0.0 or quantity.unit != "N" \
				or quantity.kind not in QUANTITY_KINDS or not _source(quantity.source):
				return _failure("normal_failure_force: expected a positive finite N quantity with kind/source")
			component.normal_failure_force = {value = float(quantity.value), unit = "N", kind = str(quantity.kind), source = str(quantity.source)}
		components.append(component)
		component_ids[item.component_id] = true
	if bound_supports.size() != installed.ids.size():
		return _failure("component.support_ids: every installed support must be bound exactly once")
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.component_id) < str(b.component_id))
	var mapping := PackedInt32Array()
	mapping.resize(installed.ids.size())
	for index: int in components.size():
		for support_index: int in components[index].support_indices:
			mapping[support_index] = index
	var profile := {format = FORMAT, law = LAW, qualification = QUALIFICATION, source = str(raw.source),
		components = components, installed_support_ids = installed.ids.duplicate(), support_to_component = mapping}
	profile.identity = _digest(profile)
	return {ok = true, errors = PackedStringArray(), profile = profile}


static func initial_state(profile: Variant) -> Dictionary:
	if not _profile_valid(profile): return _failure("invalid prepared profile")
	var modes := PackedInt64Array()
	var losses := PackedFloat64Array()
	for _component: Dictionary in profile.components:
		modes.append_array(PackedInt64Array([HEALTHY, -1]))
		losses.append(0.0)
	return {ok = true, modes = modes, losses = losses, events = [], assessments = _assessments(profile, modes)}


## Strict clock-aware state predicate, suitable for VehicleModel.state_validator.
## Losses are J per component; their finite sum is required as well as finite entries.
static func validate_state(profile: Variant, modes: Variant, losses: Variant, tick: Variant) -> bool:
	if not _profile_valid(profile) or typeof(tick) != TYPE_INT or tick < 0 or tick > MAX_SAFE_TICK \
		or typeof(modes) != TYPE_PACKED_INT64_ARRAY or modes.size() != MODE_STRIDE * profile.components.size() \
		or not _nonnegative_array(losses, profile.components.size()):
		return false
	var total := 0.0
	for index: int in profile.components.size():
		var mode: int = modes[MODE_STRIDE * index]
		var first_tick: int = modes[MODE_STRIDE * index + 1]
		if mode == HEALTHY:
			if first_tick != -1 or losses[index] != 0.0: return false
		elif mode == FAILED_ATTACHED:
			if not profile.components[index].strength_known or first_tick < 1 or first_tick > tick: return false
		else:
			return false
		total += losses[index]
		if not is_finite(total): return false
	return true


## Aggregate ONLY after the adapter qualifies aligned positive structural/support axes.
## Arbitrary banked normals, bending/shear and mount wrenches need a qualified local
## structural reduction, not this scalar sum. No probe receives an independent budget.
static func sum_aligned_normal_loads(profile: Variant, support_loads_n: Variant,
		aligned_positive_axes_qualified: Variant) -> Dictionary:
	if not _profile_valid(profile) or typeof(aligned_positive_axes_qualified) != TYPE_BOOL \
		or not aligned_positive_axes_qualified or not _nonnegative_array(support_loads_n, profile.installed_support_ids.size()):
		return _failure("normal aggregation requires qualified aligned positive axes and matching finite support loads")
	var result := PackedFloat64Array()
	result.resize(profile.components.size())
	for support: int in support_loads_n.size():
		var component: int = profile.support_to_component[support]
		result[component] += support_loads_n[support]
		if not is_finite(result[component]): return _failure("normal load aggregate overflow")
	return {ok = true, loads_n = result}


## Each row is one component's accepted aggregate normal load. Both potential arrays
## contain elastic normal spring + progressive stop + anchor potential, counted once,
## evaluated at the SAME body state for the healthy/current and declared failed law.
## The after value is used ONLY for a prospective new failure. Damper heat, slip work,
## aircraft kinetic energy and arbitrary energy budgets are not fracture inputs.
## This function changes no body/geometry/mass; an adapter must supply the failed law.
static func transition(profile: Variant, modes: Variant, losses: Variant, normal_loads_n: Variant,
		total_support_potential_before_j: Variant, failed_support_potential_after_j: Variant,
		context: Variant, generation_id: Variant) -> Dictionary:
	if not _clock(context) or not _id(generation_id) or not validate_state(profile, modes, losses, context.tick):
		return _failure("transition requires valid clock, generation and component state")
	var count: int = profile.components.size()
	if not _nonnegative_array(normal_loads_n, count) \
		or not _nonnegative_array(total_support_potential_before_j, count) \
		or not _nonnegative_array(failed_support_potential_after_j, count):
		return _failure("transition arrays must match component count and contain finite nonnegative values")
	var candidate_modes: PackedInt64Array = modes.duplicate()
	var candidate_losses: PackedFloat64Array = losses.duplicate()
	var events: Array[Dictionary] = []
	for index: int in count:
		var component: Dictionary = profile.components[index]
		if modes[MODE_STRIDE * index] == FAILED_ATTACHED or not component.strength_known \
			or normal_loads_n[index] <= component.normal_failure_force.value:
			continue
		var before: float = total_support_potential_before_j[index]
		var after: float = failed_support_potential_after_j[index]
		if after > before:
			return _failure("failed support candidate requires unbudgeted potential energy")
		var released: float = before - after
		candidate_losses[index] += released
		if not is_finite(candidate_losses[index]): return _failure("transition loss ledger overflow")
		candidate_modes[MODE_STRIDE * index] = FAILED_ATTACHED
		candidate_modes[MODE_STRIDE * index + 1] = context.tick
		events.append({type = "gear_failure", event_id = "gd1:" + _digest([LAW, generation_id, component.component_id, context.tick]),
			time_s = context.time_s, tick = context.tick, generation_id = str(generation_id),
			component_id = component.component_id, support_ids = component.support_ids.duplicate(),
			law = LAW, profile_identity = profile.identity, qualification = QUALIFICATION,
			criterion = "declared_normal_capacity_exceeded", normal_load_n = normal_loads_n[index],
			normal_failure_force_n = component.normal_failure_force.value, transition_loss_j = released,
			potential_before_j = before, potential_after_j = after,
			loss_provenance = "elastic_normal_stop_and_anchor_potential_before_minus_after_at_same_body_state",
			terminal = false, continuation = "declared_failed_attached_support"})
	if not validate_state(profile, candidate_modes, candidate_losses, context.tick):
		return _failure("transition produced an invalid component state or aggregate loss overflow")
	return {ok = true, modes = candidate_modes, losses = candidate_losses, events = events,
		assessments = _assessments(profile, candidate_modes)}


static func _clock(context: Variant) -> bool:
	if not _keys(context, ["tick", "time_s", "dt"]) or typeof(context.tick) != TYPE_INT \
		or context.tick < 1 or context.tick > MAX_SAFE_TICK or typeof(context.dt) != TYPE_FLOAT \
		or typeof(context.time_s) != TYPE_FLOAT or not is_finite(context.dt) or context.dt <= 0.0 \
		or not is_finite(context.time_s): return false
	var expected: float = context.tick * context.dt
	var following: float = (context.tick + 1) * context.dt
	if not is_finite(expected) or not is_finite(following) or following <= expected \
		or expected + context.dt * 0.5 <= expected: return false
	# Only floating-point clock arithmetic slack; never a fraction-of-tick event grace.
	var slack: float = minf(0.25 * context.dt, 4.0 * FLOAT_EPSILON * maxf(absf(expected), context.dt))
	return absf(context.time_s - expected) <= slack


static func _profile_valid(profile: Variant) -> bool:
	if not _keys(profile, ["format", "law", "qualification", "source", "components", "installed_support_ids", "support_to_component", "identity"]) \
		or typeof(profile.components) != TYPE_ARRAY or profile.components.size() > MAX_COMPONENTS \
		or typeof(profile.installed_support_ids) != TYPE_PACKED_STRING_ARRAY \
		or typeof(profile.support_to_component) != TYPE_PACKED_INT32_ARRAY:
		return false
	var raw_components: Array = []
	for component: Variant in profile.components:
		if not _keys(component, ["component_id", "support_ids", "support_indices", "source", "strength_known"], ["normal_failure_force"]) \
			or typeof(component.strength_known) != TYPE_BOOL or typeof(component.support_ids) != TYPE_PACKED_STRING_ARRAY \
			or typeof(component.support_indices) != TYPE_PACKED_INT32_ARRAY \
			or component.has("normal_failure_force") != component.strength_known:
			return false
		var raw := {component_id = component.component_id, support_ids = component.support_ids.duplicate(), source = component.source}
		if component.strength_known: raw.normal_failure_force = component.normal_failure_force.duplicate(true) \
			if typeof(component.normal_failure_force) == TYPE_DICTIONARY else component.normal_failure_force
		raw_components.append(raw)
	var rebuilt := prepare({format = profile.format, law = profile.law, source = profile.source, components = raw_components}, profile.installed_support_ids)
	return rebuilt.ok and var_to_bytes(profile) == var_to_bytes(rebuilt.profile)


static func _assessments(profile: Dictionary, modes: PackedInt64Array) -> PackedStringArray:
	var result := PackedStringArray()
	for index: int in profile.components.size():
		result.append("inspection_required_unknown_strength" if not profile.components[index].strength_known \
			else "experimental_failed_attached" if modes[MODE_STRIDE * index] == FAILED_ATTACHED else "unfailed_under_declared_law")
	return result


static func _nonnegative_array(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != count: return false
	for number: float in value:
		if not is_finite(number) or number < 0.0: return false
	return true


static func _ids(value: Variant, limit: int) -> Dictionary:
	if typeof(value) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] or value.size() > limit: return {ok = false}
	var result := PackedStringArray()
	for id: Variant in value:
		if not _id(id) or result.has(id): return {ok = false}
		result.append(id)
	return {ok = true, ids = result}


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= MAX_ID_LENGTH \
		and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r") and not value.contains("\t")


static func _source(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty() and value.length() <= MAX_SOURCE_LENGTH


static func _keys(value: Variant, required: Array, optional: Array = []) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not value.has_all(required) or value.size() > required.size() + optional.size(): return false
	for key: Variant in value:
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or (str(key) not in required and str(key) not in optional): return false
	return true


static func _digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()


static func _failure(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message]), events = []}
