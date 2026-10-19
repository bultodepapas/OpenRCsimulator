extends RefCounted
## Bounded, source-pinned Workshop mass edits for authored openrc-aircraft v2 records.
##
## The FAA weight-and-balance method sums component moments and divides by total weight;
## this module uses that first-moment relation in the repository's LE datum (x aft, y right,
## z up). Full inertia remains recomputed by AircraftData's box + parallel-axis calculation.
## See FAA-H-8083-1B, Weight & Balance Handbook, ch. 3, and the JSBSim FGMassBalance
## reference for structural-frame cross-product signs and parallel-axis contributions.
const AircraftData := preload("res://physics/aircraft_data.gd")
const PhysicalIdentity := preload("res://physics/physical_identity.gd")
const Descriptor := preload("res://workshop/descriptor.gd")

const MAX_EDITS := 32
const MAX_SOURCE_LENGTH := 256
const MIN_INVENTORY_MASS_KG := 0.001
const MAX_INVENTORY_MASS_KG := 5.0
const LIQUID_FUEL_SOURCES := ["glow_fuel", "gasoline", "kerosene"]
const EDIT_KEYS := ["id", "mass_kg", "source"]


## Validate an in-memory source, resolve its inventory only by authored stable ID, and report
## the measured-state mass/CG. This does not read files or mutate the supplied source.
static func inspect(base: Dictionary) -> Dictionary:
	var context := _validated_context(base)
	if not context.ok:
		return _failure(context.errors)
	var state: String = _declared_weighing_state(base)
	var metrics := _metrics_for_state(base, state)
	if not metrics.ok:
		return _failure(metrics.errors)
	var rows: Array[Dictionary] = []
	var resource_ids: Dictionary = _finite_resource_ids(base)
	for index: int in range(base.inventory.size()):
		var item: Dictionary = base.inventory[index]
		var item_id: String = str(item.get("id", ""))
		var reason: String = _mass_edit_refusal(item, resource_ids.has(item_id))
		rows.append({
			"id": item_id,
			"name": str(item.get("name", "")),
			"mass_kg": float(item.mass.value),
			"mass_kind": str(item.mass.kind),
			"mass_source": str(item.mass.source),
			"position_le_m": item.position.value.duplicate(),
			"editable": reason.is_empty(),
			"reason": reason,
		})
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"aircraft_id": str(base.id),
		"inventory": rows,
		"weighing_state": state,
		"mass_kg": metrics.mass_kg,
		"cg_le_m": metrics.cg_le_m,
		"cg_tolerance_m": float(base.balance.cg_tolerance.value),
		"position_edits_supported": false,
		"mass_bounds_kg": [MIN_INVENTORY_MASS_KG, MAX_INVENTORY_MASS_KG],
		"mass_bounds_source": "app/data/schema/openrc-aircraft-v2.schema.json#/properties/inventory/items/properties/mass/properties/value",
	}


## Apply direct per-component measurements to a detached v2 source. Exact {id,mass_kg,source}
## records are required; stable IDs, units and positions never change. The aircraft loader is
## the final authority, including mass-balance tolerance, mass range, fuel and inertia checks.
static func apply_to_validated_base(base: Dictionary, edits: Array) -> Dictionary:
	var context := _validated_context(base)
	if not context.ok:
		return _failure(context.errors)
	if edits.size() > MAX_EDITS:
		return _failure(PackedStringArray(["Mass edit has more than %d entries." % MAX_EDITS]))
	var indices: Dictionary = context.identity.inventory_index_by_id
	var resource_ids: Dictionary = _finite_resource_ids(base)
	var seen: Dictionary = {}
	var accepted: Array[Dictionary] = []
	for edit_index: int in range(edits.size()):
		var edit: Variant = edits[edit_index]
		if not edit is Dictionary or not _has_exact_keys(edit, EDIT_KEYS):
			return _failure(PackedStringArray(["Mass edit %d must contain exactly id, mass_kg and source." % edit_index]))
		if not edit.id is String or str(edit.id).is_empty():
			return _failure(PackedStringArray(["Mass edit %d has an invalid stable inventory ID." % edit_index]))
		var item_id: String = str(edit.id)
		if seen.has(item_id):
			return _failure(PackedStringArray(["Mass edit ID '%s' is duplicated." % item_id]))
		seen[item_id] = true
		if not indices.has(item_id):
			return _failure(PackedStringArray(["Mass edit ID '%s' is not present in this source inventory." % item_id]))
		var inventory_index: int = int(indices[item_id])
		var item: Dictionary = base.inventory[inventory_index]
		var refusal: String = _mass_edit_refusal(item, resource_ids.has(item_id))
		if not refusal.is_empty():
			return _failure(PackedStringArray(["Mass edit ID '%s' is unavailable: %s" % [item_id, refusal]]))
		if typeof(edit.mass_kg) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(edit.mass_kg)):
			return _failure(PackedStringArray(["Mass edit ID '%s' mass_kg must be finite." % item_id]))
		var measured_mass_kg: float = float(edit.mass_kg)
		if measured_mass_kg < MIN_INVENTORY_MASS_KG or measured_mass_kg > MAX_INVENTORY_MASS_KG:
			return _failure(PackedStringArray(["Mass edit ID '%s' mass_kg must lie within the v2 source bound [0.001, 5.0] kg." % item_id]))
		var measurement_source: Variant = edit.source
		if not _valid_measurement_source(measurement_source):
			return _failure(PackedStringArray(["Mass edit ID '%s' source must be a nonempty measurement description of at most %d characters without control characters." % [item_id, MAX_SOURCE_LENGTH]]))
		accepted.append({"id": item_id, "mass_kg": measured_mass_kg, "source": str(measurement_source).strip_edges()})
	var output: Dictionary = base.duplicate(true)
	for edit: Dictionary in accepted:
		var inventory_index: int = int(indices[edit.id])
		output.inventory[inventory_index].mass = {
			"value": float(edit.mass_kg),
			"unit": "kg",
			"kind": "measured",
			"source": str(edit.source),
		}
	var data: Dictionary = AircraftData.validate_and_derive(output)
	if not bool(data.get("ok", false)):
		return _failure(_as_errors(data.get("errors", [])))
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"raw": output,
		"data": data,
		"applied_ids": _ids(accepted),
		"edits": accepted.duplicate(true),
		"mass_kind": "measured",
	}


## Verify the exact source bytes and descriptor pins before delegating to the deterministic
## core. Callers holding a frozen trial should pass that exact source snapshot, not reload catalog data.
static func inspect_pinned(base: Dictionary, descriptor: Dictionary, base_bytes: PackedByteArray) -> Dictionary:
	var pin := _validate_pinned_source(base, descriptor, base_bytes)
	if not pin.ok:
		return _failure(pin.errors)
	return inspect(base)


static func apply_pinned(base: Dictionary, descriptor: Dictionary, base_bytes: PackedByteArray, edits: Array) -> Dictionary:
	var pin := _validate_pinned_source(base, descriptor, base_bytes)
	if not pin.ok:
		return _failure(pin.errors)
	return apply_to_validated_base(base, edits)


## Read-only report comparing a scale/CG observation with the source inventory at the explicitly
## selected weighing state. Mass residual is reported without an invented tolerance; CG uses the
## source's balance.cg_tolerance. Axes are x aft, y right, z up in metres.
static func target_consistency_report(base: Dictionary, observed_total_mass_kg: Variant,
		observed_cg_le_m: Variant, weighing_state: String) -> Dictionary:
	var context := _validated_context(base)
	if not context.ok:
		return _failure(context.errors)
	var state_check := _check_weighing_state(base, weighing_state)
	if not state_check.ok:
		return _failure(state_check.errors)
	var metrics := _metrics_for_state(base, weighing_state)
	if not metrics.ok:
		return _failure(metrics.errors)
	var measurement := _validate_observation(observed_total_mass_kg, observed_cg_le_m)
	if not measurement.ok:
		return _failure(measurement.errors)
	var observed_cg: Array = measurement.cg_le_m
	var source_cg: Array = metrics.cg_le_m
	var residual: Array[float] = []
	var within_source_tolerance := true
	var tolerance: float = float(base.balance.cg_tolerance.value)
	for axis: int in range(3):
		var difference: float = float(observed_cg[axis]) - float(source_cg[axis])
		residual.append(difference)
		within_source_tolerance = within_source_tolerance and absf(difference) <= tolerance
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"weighing_state": weighing_state,
		"axes": ["x_aft", "y_right", "z_up"],
		"unit": "m",
		"source_mass_kg": metrics.mass_kg,
		"observed_mass_kg": float(observed_total_mass_kg),
		"mass_residual_kg": float(observed_total_mass_kg) - metrics.mass_kg,
		"source_cg_le_m": source_cg.duplicate(),
		"observed_cg_le_m": observed_cg.duplicate(),
		"cg_residual_m": residual,
		"cg_tolerance_m": tolerance,
		"cg_within_source_tolerance": within_source_tolerance,
		"source_mass_bounds_kg": base.plausibility.mass_range.value.duplicate(),
		"observed_mass_within_source_range": float(observed_total_mass_kg) >= float(base.plausibility.mass_range.value[0])
			and float(observed_total_mass_kg) <= float(base.plausibility.mass_range.value[1]),
	}


## Proposal-only single-component inverse solve. It holds every inventory position and every
## other mass fixed, uses one stable-ID component to satisfy measured total mass, then checks
## the resulting 3-axis CG against both the observation and source plan CG. It never applies
## the inferred result or labels it as a component measurement.
static func solve_fixed_station(base: Dictionary, component_id: String,
		observed_total_mass_kg: Variant, observed_cg_le_m: Variant, weighing_state: String) -> Dictionary:
	var context := _validated_context(base)
	if not context.ok:
		return _failure(context.errors)
	var state_check := _check_weighing_state(base, weighing_state)
	if not state_check.ok:
		return _failure(state_check.errors)
	var measurement := _validate_observation(observed_total_mass_kg, observed_cg_le_m)
	if not measurement.ok:
		return _failure(measurement.errors)
	var indices: Dictionary = context.identity.inventory_index_by_id
	if not indices.has(component_id):
		return _failure(PackedStringArray(["Fixed-station solve ID '%s' is not present in this source inventory." % component_id]))
	var resource_ids: Dictionary = _finite_resource_ids(base)
	var selected: Dictionary = base.inventory[int(indices[component_id])]
	var refusal: String = _mass_edit_refusal(selected, resource_ids.has(component_id))
	if not refusal.is_empty():
		return _failure(PackedStringArray(["Fixed-station solve ID '%s' is unavailable: %s" % [component_id, refusal]]))
	var current_metrics := _metrics_for_state(base, weighing_state)
	if not current_metrics.ok:
		return _failure(current_metrics.errors)
	var target_mass: float = float(observed_total_mass_kg)
	var declared_range: Array = base.plausibility.mass_range.value
	if target_mass < float(declared_range[0]) or target_mass > float(declared_range[1]):
		return _failure(PackedStringArray(["Observed total mass is outside the source plausibility.mass_range [%.6f, %.6f] kg." % [float(declared_range[0]), float(declared_range[1])]]))
	var selected_is_in_state: bool = weighing_state != "empty_tanks" or not resource_ids.has(component_id)
	if not selected_is_in_state:
		return _failure(PackedStringArray(["Fixed-station solve component is absent from the selected weighing state."]))
	var others_mass := 0.0
	var first_moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Dictionary in base.inventory:
		var item_id: String = str(item.id)
		if weighing_state == "empty_tanks" and resource_ids.has(item_id):
			continue
		var item_mass: float = float(item.mass.value)
		if item_id != component_id:
			others_mass += item_mass
			for axis: int in range(3):
				first_moment[axis] += item_mass * float(item.position.value[axis])
	var proposal_mass: float = target_mass - others_mass
	if not is_finite(proposal_mass) or proposal_mass < MIN_INVENTORY_MASS_KG or proposal_mass > MAX_INVENTORY_MASS_KG:
		return _failure(PackedStringArray(["Fixed-station solve proposes %.9f kg for '%s'; source v2 component bound is [0.001, 5.0] kg." % [proposal_mass, component_id]]))
	var proposed_moment := PackedFloat64Array(first_moment)
	for axis: int in range(3):
		proposed_moment[axis] += proposal_mass * float(selected.position.value[axis])
	var predicted_cg: Array[float] = []
	var cg_residual: Array[float] = []
	var measured_cg: Array = measurement.cg_le_m
	var tolerance: float = float(base.balance.cg_tolerance.value)
	var matches_observed_cg := true
	var plan_cg: Array = base.balance.plan_cg.value
	var matches_plan_cg := true
	for axis: int in range(3):
		var cg_axis: float = proposed_moment[axis] / target_mass
		predicted_cg.append(cg_axis)
		var measured_error: float = cg_axis - float(measured_cg[axis])
		var plan_error: float = cg_axis - float(plan_cg[axis])
		cg_residual.append(measured_error)
		matches_observed_cg = matches_observed_cg and absf(measured_error) <= tolerance
		matches_plan_cg = matches_plan_cg and absf(plan_error) <= tolerance
	if not matches_observed_cg:
		return _failure(PackedStringArray(["Fixed-station mass solution misses observed CG by more than the source balance.cg_tolerance (%.6f m)." % tolerance]), {
			"input": _solve_input(component_id, target_mass, measured_cg, weighing_state, selected, tolerance),
			"proposal": {"id": component_id, "mass_kg": proposal_mass, "kind": "derived"},
			"predicted_cg_le_m": predicted_cg,
			"cg_residual_m": cg_residual,
			"matches_source_plan_cg": matches_plan_cg,
		})
	if not matches_plan_cg:
		return _failure(PackedStringArray(["Fixed-station solution matches the observation but conflicts with source balance.plan_cg; authored balance evidence is preserved." ]), {
			"input": _solve_input(component_id, target_mass, measured_cg, weighing_state, selected, tolerance),
			"proposal": {"id": component_id, "mass_kg": proposal_mass, "kind": "derived"},
			"predicted_cg_le_m": predicted_cg,
			"cg_residual_m": cg_residual,
			"matches_source_plan_cg": false,
		})
	var candidate: Dictionary = base.duplicate(true)
	var candidate_item: Dictionary = candidate.inventory[int(indices[component_id])]
	candidate_item.mass = {
		"value": proposal_mass,
		"unit": "kg",
		"kind": "derived",
		"source": "Derived fixed-station proposal from observed total mass and 3-axis CG; not a component mass measurement.",
	}
	var loader_result: Dictionary = AircraftData.validate_and_derive(candidate)
	if not bool(loader_result.get("ok", false)):
		return _failure(_as_errors(loader_result.get("errors", [])), {
			"input": _solve_input(component_id, target_mass, measured_cg, weighing_state, selected, tolerance),
			"proposal": candidate_item.mass.duplicate(true),
			"predicted_mass_kg": target_mass,
			"predicted_cg_le_m": predicted_cg,
			"cg_residual_m": cg_residual,
			"loader_compatible": false,
		})
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"input": _solve_input(component_id, target_mass, measured_cg, weighing_state, selected, tolerance),
		"proposal": {"id": component_id, "mass": candidate_item.mass.duplicate(true), "position_le_m": selected.position.value.duplicate()},
		"predicted_mass_kg": loader_result.model.mass_kg if weighing_state == "as_inventory" else target_mass,
		"predicted_cg_le_m": predicted_cg,
		"cg_residual_m": cg_residual,
		"matches_source_plan_cg": true,
		"loader_compatible": true,
		"applied": false,
		"notice": "Derived proposal only. No source field was changed and no inferred mass is marked measured.",
	}


static func _solve_input(component_id: String, mass: float, cg: Array, state: String, item: Dictionary, tolerance: float) -> Dictionary:
	return {
		"component_id": component_id,
		"observed_total_mass_kg": mass,
		"observed_cg_le_m": cg.duplicate(),
		"weighing_state": state,
		"fixed_station_le_m": item.position.value.duplicate(),
		"source_mass_kg": float(item.mass.value),
		"axes": ["x_aft", "y_right", "z_up"],
		"cg_tolerance_m": tolerance,
	}


static func _validated_context(base: Dictionary) -> Dictionary:
	if base.get("format") != AircraftData.FORMAT:
		return {"ok": false, "errors": PackedStringArray(["Mass editing requires openrc-aircraft v2 source data."])}
	if not base.has("physical_identity_version"):
		return {"ok": false, "errors": PackedStringArray(["Mass editing requires complete authored physical inventory IDs."])}
	var identity_errors: PackedStringArray = PhysicalIdentity.validate(base)
	if not identity_errors.is_empty():
		return {"ok": false, "errors": identity_errors}
	var identity: Dictionary = PhysicalIdentity.describe(base)
	var indices: Variant = identity.get("inventory_index_by_id", null)
	if identity.is_empty() or not indices is Dictionary or indices.size() != base.get("inventory", []).size():
		return {"ok": false, "errors": PackedStringArray(["Mass editing requires a complete stable-ID inventory resolver."])}
	var data: Dictionary = AircraftData.validate_and_derive(base)
	if not bool(data.get("ok", false)):
		return {"ok": false, "errors": _as_errors(data.get("errors", []))}
	return {"ok": true, "errors": PackedStringArray(), "identity": identity, "data": data}


static func _validate_pinned_source(base: Dictionary, descriptor: Dictionary, base_bytes: PackedByteArray) -> Dictionary:
	if base_bytes.is_empty() or base_bytes.size() > Descriptor.MAX_BASE_BYTES:
		return {"ok": false, "errors": PackedStringArray(["Exact aircraft source bytes are empty or exceed the descriptor size limit."])}
	var source_text: String = base_bytes.get_string_from_utf8()
	if source_text.to_utf8_buffer() != base_bytes:
		return {"ok": false, "errors": PackedStringArray(["Exact aircraft source bytes are not valid UTF-8."])}
	var parser := JSON.new()
	if parser.parse(source_text) != OK or not parser.data is Dictionary:
		return {"ok": false, "errors": PackedStringArray(["Exact aircraft source bytes are not a valid JSON object."])}
	if parser.data != base:
		return {"ok": false, "errors": PackedStringArray(["In-memory aircraft data do not match the exact pinned source bytes."])}
	var checked: Dictionary = Descriptor.validate(descriptor, str(base.get("id", "")), base_bytes)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "errors": _as_errors(checked.get("errors", []))}
	return {"ok": true, "errors": PackedStringArray()}


static func _metrics_for_state(base: Dictionary, state: String) -> Dictionary:
	var state_check := _check_weighing_state(base, state)
	if not state_check.ok:
		return state_check
	var excluded: Dictionary = _finite_resource_ids(base) if state == "empty_tanks" else {}
	var total_mass := 0.0
	var first_moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Dictionary in base.inventory:
		var item_id: String = str(item.get("id", ""))
		if excluded.has(item_id):
			continue
		var item_mass: float = float(item.mass.value)
		total_mass += item_mass
		for axis: int in range(3):
			first_moment[axis] += item_mass * float(item.position.value[axis])
	if not is_finite(total_mass) or total_mass <= 0.0:
		return {"ok": false, "errors": PackedStringArray(["Selected weighing state has no positive finite inventory mass."])}
	var cg: Array[float] = []
	for axis: int in range(3):
		cg.append(first_moment[axis] / total_mass)
	return {"ok": true, "errors": PackedStringArray(), "mass_kg": total_mass, "cg_le_m": cg}


static func _check_weighing_state(base: Dictionary, state: String) -> Dictionary:
	if state not in ["empty_tanks", "as_inventory"]:
		return {"ok": false, "errors": PackedStringArray(["Weighing state must be 'empty_tanks' or 'as_inventory'."])}
	var declared: String = _declared_weighing_state(base)
	if state != declared:
		return {"ok": false, "errors": PackedStringArray(["Requested weighing state '%s' does not match source-declared state '%s'." % [state, declared]])}
	var resource_ids: Dictionary = _finite_resource_ids(base)
	if not resource_ids.is_empty() and state != "empty_tanks":
		return {"ok": false, "errors": PackedStringArray(["Finite-fuel mass/CG solving is supported only for the source-declared empty_tanks weighing state."])}
	if resource_ids.is_empty() and state == "empty_tanks":
		return {"ok": false, "errors": PackedStringArray(["Source declares empty_tanks but has no finite liquid-fuel inventory."])}
	return {"ok": true, "errors": PackedStringArray()}


static func _declared_weighing_state(base: Dictionary) -> String:
	var balance: Variant = base.get("balance", {})
	return str(balance.get("fuel_state", "as_inventory")) if balance is Dictionary else "as_inventory"


static func _finite_resource_ids(base: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	var fuel_system: Variant = base.get("fuel_system", {})
	var tanks: Variant = fuel_system.get("tanks", []) if fuel_system is Dictionary else []
	if tanks is Array:
		for tank: Variant in tanks:
			if not tank is Dictionary:
				continue
			var liquid_id: String = str(tank.get("liquid_inventory_id", ""))
			if not liquid_id.is_empty():
				ids[liquid_id] = true
			var line: Variant = tank.get("feed_line", {})
			if line is Dictionary:
				var line_id: String = str(line.get("liquid_inventory_id", ""))
				if not line_id.is_empty():
					ids[line_id] = true
	for item: Variant in base.get("inventory", []):
		if not item is Dictionary:
			continue
		if str(item.get("energy_source", "")) in LIQUID_FUEL_SOURCES:
			var item_id: String = str(item.get("id", ""))
			if not item_id.is_empty():
				ids[item_id] = true
	return ids


static func _mass_edit_refusal(item: Dictionary, is_finite_resource: bool) -> String:
	if is_finite_resource:
		return "finite liquid fuel and feed-line inventory are controlled by fuel-system state, not component measurements"
	var mass: Variant = item.get("mass", {})
	if mass is Dictionary and str(mass.get("kind", "")) == "derived" \
			and str(mass.get("source", "")).to_lower().contains("virtual"):
		return "source provenance marks this as a virtual reference-build mass, not physical hardware"
	return ""


static func _validate_observation(total_mass: Variant, cg: Variant) -> Dictionary:
	var errors := PackedStringArray()
	if typeof(total_mass) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(total_mass)) or float(total_mass) <= 0.0:
		errors.append("Observed total mass must be positive and finite kg.")
	if not cg is Array or cg.size() != 3:
		errors.append("Observed CG must be three LE-frame coordinates [x_aft, y_right, z_up] in metres.")
	else:
		for axis: int in range(3):
			if typeof(cg[axis]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cg[axis])) \
					or float(cg[axis]) < -2.0 or float(cg[axis]) > 2.0:
				errors.append("Observed CG axis %d must be finite and within the schema's [-2, 2] m coordinate bound." % axis)
	return {"ok": errors.is_empty(), "errors": errors, "cg_le_m": cg.duplicate(true) if cg is Array else []}


static func _valid_measurement_source(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = str(value).strip_edges()
	if text.is_empty() or text.length() > MAX_SOURCE_LENGTH:
		return false
	for index: int in range(text.length()):
		var code: int = text.unicode_at(index)
		if code < 32 or code == 127:
			return false
	return true


static func _has_exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func _as_errors(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is PackedStringArray:
		out.append_array(value)
	elif value is Array:
		for item: Variant in value:
			out.append(str(item))
	return out


static func _failure(errors: PackedStringArray, extra: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "errors": errors}
	for key: Variant in extra:
		out[key] = extra[key]
	return out


static func _ids(edits: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for edit: Dictionary in edits:
		out.append(str(edit.id))
	return out
