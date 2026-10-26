extends RefCounted
class_name ThermalBudget

## Generic lumped energy accounting only. Does not model combustion, faults,
## structural damage, aircraft installation, or visual effects.
const FORMAT := "openrc-thermal-budget v1"
const SCENARIO := "scenario_assumption"
const VALIDATED := "independently_validated"
const INSPECT := "inspect"
const UNRECOVERABLE := "unrecoverable"
const MAX_COMPONENTS := 64
const MAX_SOURCES := 64
const MAX_TICK := 2147483647
const MIN_DT := 0.000000001
const MAX_DT := 1.0
const MAX_ENERGY := 1000000000000.0
const MAX_POWER := 1000000000.0
const MAX_TOTAL_POWER := 1000000000000.0
const MIN_CAPACITY := 0.000001
const MAX_CAPACITY := 1000000000000.0
const MAX_COOLING := 1000000000.0
const MAX_COOLING_RATE := 1000000000000000.0
const MAX_K := 1000000.0
const MAX_DOSE := 1000000000000.0
const BALANCE_TOLERANCE := 0.00000001
const SMALL_X := 0.000001

const MODEL_KEYS := ["format", "first_tick", "tick_duration_s", "components", "sources"]
const COMPONENT_KEYS := [
	"id", "heat_capacity_j_per_k", "cooling_w_per_k", "ambient_k",
	"initial_temperature_k", "parameter_basis", "parameter_provenance",
	"damage_dose_threshold_k_s", "damage_threshold_basis",
	"damage_threshold_provenance", "damage_disposition"
]
const SOURCE_KEYS := ["id", "energy_j", "power_w", "ignition_tick", "allocation_shares", "basis", "provenance"]


class State extends RefCounted:
	var model_sha256 := ""
	var last_tick := -1
	var temperatures_k := PackedFloat64Array()
	var dose_k_s := PackedFloat64Array()
	var source_remaining_j := PackedFloat64Array()


static func initial_state(model: Dictionary) -> Dictionary:
	var valid := _validate_model(model)
	if not valid.ok:
		return _failure(valid.error)
	var state := State.new()
	state.model_sha256 = _fingerprint(model)
	state.last_tick = int(model.first_tick) - 1
	for component in model.components:
		state.temperatures_k.append(float(component.initial_temperature_k))
		state.dose_k_s.append(0.0)
	for source in model.sources:
		state.source_remaining_j.append(float(source.energy_j))
	return {"ok": true, "state": state}


## Accepts one fixed tick. Repeating the last tick returns an idempotent no-op.
## Caller basis labels are retained as declarations and never verified here.
static func advance(model: Dictionary, state_value: Variant, accepted_tick: int, tick_duration_s: float) -> Dictionary:
	var valid := _validate_model(model)
	if not valid.ok:
		return _failure(valid.error)
	if not (state_value is State):
		return _failure("state must be a ThermalBudget.State")
	var old: State = state_value
	if old.model_sha256 != _fingerprint(model) or not _valid_state(model, old):
		return _failure("state fingerprint, arrays, or values are invalid")
	if accepted_tick < 0 or accepted_tick > MAX_TICK:
		return _failure("accepted tick outside finite bound")
	if not _finite(tick_duration_s) or tick_duration_s < MIN_DT or tick_duration_s > MAX_DT:
		return _failure("tick duration outside finite bound")
	if absf(tick_duration_s - float(model.tick_duration_s)) > 0.000000000001 * maxf(1.0, float(model.tick_duration_s)):
		return _failure("tick duration must match fixed model step")
	if accepted_tick == old.last_tick:
		return _no_op(model, _copy_state(old))
	if accepted_tick != old.last_tick + 1:
		return _failure("only the next tick or a duplicate of the last tick is accepted")

	var state := _copy_state(old)
	state.last_tick = accepted_tick
	var nc: int = model.components.size()
	var ns: int = model.sources.size()
	var used := PackedFloat64Array()
	var unused := PackedFloat64Array()
	var component_input := PackedFloat64Array()
	var storage_delta := PackedFloat64Array()
	var cooling_out := PackedFloat64Array()
	used.resize(ns)
	unused.resize(ns)
	component_input.resize(nc)
	storage_delta.resize(nc)
	cooling_out.resize(nc)

	# Source release is explicit, delayed until its tick, and capped by remaining J.
	for si in range(ns):
		var src: Dictionary = model.sources[si]
		if src.ignition_tick == null or accepted_tick < int(src.ignition_tick):
			continue
		var remaining: float = old.source_remaining_j[si]
		if remaining <= 0.0:
			continue
		var joules := minf(remaining, float(src.power_w) * tick_duration_s)
		used[si] = joules
		state.source_remaining_j[si] = maxf(0.0, remaining - joules)
		var shares := 0.0
		for ci in range(nc):
			var share: float = src.allocation_shares[ci]
			shares += share
			component_input[ci] += joules * share
		unused[si] = joules * maxf(0.0, 1.0 - shares)

	# Split the tick at source depletion times, then integrate each constant-power
	# interval analytically. This avoids smearing a short source across the full tick.
	var boundaries := PackedFloat64Array([0.0, tick_duration_s])
	for si in range(ns):
		if used[si] <= 0.0:
			continue
		var src: Dictionary = model.sources[si]
		var depletion := used[si] / float(src.power_w)
		if depletion > 0.0 and depletion < tick_duration_s:
			boundaries.append(depletion)
	boundaries.sort()
	for bi in range(boundaries.size() - 1):
		var t0: float = boundaries[bi]
		var duration: float = boundaries[bi + 1] - t0
		if duration <= 0.0:
			continue
		var powers := PackedFloat64Array()
		powers.resize(nc)
		for si in range(ns):
			var src: Dictionary = model.sources[si]
			if src.ignition_tick == null or accepted_tick < int(src.ignition_tick):
				continue
			var start_energy: float = old.source_remaining_j[si]
			if start_energy <= 0.0 or t0 >= minf(tick_duration_s, start_energy / float(src.power_w)):
				continue
			for ci in range(nc):
				powers[ci] += float(src.power_w) * float(src.allocation_shares[ci])
		for ci in range(nc):
			var part: Dictionary = model.components[ci]
			var step := _integrate(
				state.temperatures_k[ci], float(part.ambient_k),
				float(part.heat_capacity_j_per_k), float(part.cooling_w_per_k),
				powers[ci], duration
			)
			if not step.ok:
				return _failure("component integration exceeded finite bounds")
			state.temperatures_k[ci] = step.temperature_k
			state.dose_k_s[ci] += step.dose_k_s
			storage_delta[ci] += step.storage_delta_j
			cooling_out[ci] += step.cooling_j
			if state.dose_k_s[ci] > MAX_DOSE:
				return _failure("thermal dose exceeded finite bound")

	var total_used := _sum(used)
	var total_unused := _sum(unused)
	var total_storage := _sum(storage_delta)
	var total_cooling := _sum(cooling_out)
	var balance_error := total_used - total_unused - total_storage - total_cooling
	if absf(balance_error) > BALANCE_TOLERANCE * maxf(1.0, total_used):
		return _failure("source energy does not balance unused, stored, and cooled energy")
	var rows: Array[Dictionary] = []
	for ci in range(nc):
		var part: Dictionary = model.components[ci]
		var threshold: Variant = part.damage_dose_threshold_k_s
		var exceeded := threshold != null and state.dose_k_s[ci] >= float(threshold)
		var disposition := INSPECT
		if exceeded and _qualified_unrecoverable(model, ci):
			disposition = UNRECOVERABLE
		rows.append({
			"id": part.id,
			"temperature_k": state.temperatures_k[ci],
			"dose_k_s": state.dose_k_s[ci],
			"threshold_exceeded": exceeded,
			"disposition": disposition,
			"declared_parameter_basis": part.parameter_basis,
			"declared_threshold_basis": part.damage_threshold_basis
		})
	return {
		"ok": true, "duplicate_tick": false, "accepted_tick": accepted_tick,
		"tick_duration_s": tick_duration_s, "state": state, "components": rows,
		"source_used_j": used, "source_unallocated_j": unused,
		"component_input_j": component_input,
		"component_storage_delta_j": storage_delta, "component_cooling_j": cooling_out,
		"energy_balance_error_j": balance_error, "declared_basis": _basis(model),
		"provenance_is_caller_declared_not_verified": true
	}


static func _no_op(model: Dictionary, state: State) -> Dictionary:
	var rows: Array[Dictionary] = []
	for ci in range(model.components.size()):
		var part: Dictionary = model.components[ci]
		var threshold: Variant = part.damage_dose_threshold_k_s
		var exceeded := threshold != null and state.dose_k_s[ci] >= float(threshold)
		var disposition := INSPECT
		if exceeded and _qualified_unrecoverable(model, ci):
			disposition = UNRECOVERABLE
		rows.append({
			"id": part.id, "temperature_k": state.temperatures_k[ci],
			"dose_k_s": state.dose_k_s[ci], "threshold_exceeded": exceeded,
			"disposition": disposition
		})
	var zero_sources := PackedFloat64Array()
	var zero_components := PackedFloat64Array()
	zero_sources.resize(model.sources.size())
	zero_components.resize(model.components.size())
	return {
		"ok": true, "duplicate_tick": true, "accepted_tick": state.last_tick,
		"state": state, "components": rows, "source_used_j": zero_sources,
		"source_unallocated_j": zero_sources.duplicate(),
		"component_input_j": zero_components,
		"component_storage_delta_j": zero_components.duplicate(),
		"component_cooling_j": zero_components.duplicate(),
		"energy_balance_error_j": 0.0, "declared_basis": _basis(model),
		"provenance_is_caller_declared_not_verified": true
	}


## C dT/dt = P - h(T - Ta). Returns the exact constant-power solution and
## integral of max(T-Ta, 0); initial validation ensures T >= Ta and P >= 0.
static func _integrate(temp: float, ambient: float, capacity: float, h: float, power: float, dt: float) -> Dictionary:
	var x0 := temp - ambient
	var rate := h / capacity
	var x1: float
	var dose: float
	if rate == 0.0:
		x1 = x0 + power * dt / capacity
		dose = x0 * dt + 0.5 * power * dt * dt / capacity
	else:
		var x := rate * dt
		var phi: float
		var psi: float
		if x < 0.0001:
			phi = 1.0 - 0.5 * x + x * x / 6.0 - x * x * x / 24.0
			psi = 0.5 - x / 6.0 + x * x / 24.0 - x * x * x / 120.0
		else:
			var one_minus_decay := 1.0 - exp(-x)
			phi = one_minus_decay / x
			psi = (x - one_minus_decay) / (x * x)
		x1 = x0 * exp(-x) + power / capacity * dt * phi
		dose = x0 * dt * phi + power / capacity * dt * dt * psi
	var next_temp := ambient + x1
	if not _finite(next_temp) or next_temp < ambient - 0.000000001 or next_temp > MAX_K:
		return {"ok": false}
	if not _finite(dose) or dose < -0.000000001:
		return {"ok": false}
	var delta := capacity * (x1 - x0)
	var input_j := power * dt
	var removed := input_j - delta
	var tolerance := BALANCE_TOLERANCE * maxf(1.0, input_j + absf(delta))
	if removed < -tolerance:
		return {"ok": false}
	return {
		"ok": true, "temperature_k": next_temp, "dose_k_s": maxf(0.0, dose),
		"storage_delta_j": delta, "cooling_j": maxf(0.0, removed)
	}

static func _validate_model(model: Dictionary) -> Dictionary:
	if not _exact_keys(model, MODEL_KEYS) or model.format != FORMAT:
		return {"ok": false, "error": "model does not match openrc-thermal-budget v1"}
	if not (model.first_tick is int) or model.first_tick < 0 or model.first_tick > MAX_TICK:
		return {"ok": false, "error": "first_tick outside finite tick bound"}
	if not _finite(model.tick_duration_s) or model.tick_duration_s < MIN_DT or model.tick_duration_s > MAX_DT:
		return {"ok": false, "error": "model tick duration outside finite bound"}
	if not (model.components is Array) or model.components.is_empty() or model.components.size() > MAX_COMPONENTS:
		return {"ok": false, "error": "components must contain 1..64 rows"}
	if not (model.sources is Array) or model.sources.size() > MAX_SOURCES:
		return {"ok": false, "error": "sources must contain 0..64 rows"}
	var component_ids := {}
	for part in model.components:
		if not (part is Dictionary) or not _exact_keys(part, COMPONENT_KEYS):
			return {"ok": false, "error": "component row keys do not match v1"}
		if not _valid_id(part.id) or component_ids.has(part.id):
			return {"ok": false, "error": "component ids must be unique"}
		component_ids[part.id] = true
		if not _finite(part.heat_capacity_j_per_k) or part.heat_capacity_j_per_k < MIN_CAPACITY or part.heat_capacity_j_per_k > MAX_CAPACITY:
			return {"ok": false, "error": "heat capacity outside finite bound"}
		if not _finite(part.cooling_w_per_k) or part.cooling_w_per_k < 0.0 or part.cooling_w_per_k > MAX_COOLING:
			return {"ok": false, "error": "cooling coefficient outside finite bound"}
		if float(part.cooling_w_per_k) / float(part.heat_capacity_j_per_k) > MAX_COOLING_RATE:
			return {"ok": false, "error": "cooling rate outside finite bound"}
		if not _finite(part.ambient_k) or part.ambient_k < 0.0 or part.ambient_k > MAX_K:
			return {"ok": false, "error": "ambient temperature outside finite bound"}
		if not _finite(part.initial_temperature_k) or part.initial_temperature_k < part.ambient_k or part.initial_temperature_k > MAX_K:
			return {"ok": false, "error": "initial temperature must be bounded and at/above ambient"}
		if not _valid_basis(part.parameter_basis) or not _valid_provenance(part.parameter_provenance):
			return {"ok": false, "error": "parameter basis/provenance required"}
		var threshold: Variant = part.damage_dose_threshold_k_s
		if threshold == null:
			if part.damage_threshold_basis != null or part.damage_threshold_provenance != null or part.damage_disposition != null:
				return {"ok": false, "error": "null threshold requires null basis, provenance, disposition"}
		else:
			if not _finite(threshold) or threshold <= 0.0 or threshold > MAX_DOSE:
				return {"ok": false, "error": "damage dose threshold outside finite bound"}
			if not _valid_basis(part.damage_threshold_basis) or not _valid_provenance(part.damage_threshold_provenance):
				return {"ok": false, "error": "threshold basis/provenance required"}
			if part.damage_disposition != UNRECOVERABLE:
				return {"ok": false, "error": "threshold disposition must explicitly be unrecoverable"}
	var source_ids := {}
	var total_power := 0.0
	for src in model.sources:
		if not (src is Dictionary) or not _exact_keys(src, SOURCE_KEYS):
			return {"ok": false, "error": "source row keys do not match v1"}
		if not _valid_id(src.id) or source_ids.has(src.id):
			return {"ok": false, "error": "source ids must be unique"}
		source_ids[src.id] = true
		if not _finite(src.energy_j) or src.energy_j < 0.0 or src.energy_j > MAX_ENERGY:
			return {"ok": false, "error": "source energy outside finite bound"}
		if not _finite(src.power_w) or src.power_w < 0.0 or src.power_w > MAX_POWER:
			return {"ok": false, "error": "source power outside finite bound"}
		if src.energy_j > 0.0 and src.power_w <= 0.0:
			return {"ok": false, "error": "positive source energy requires positive power"}
		var trigger: Variant = src.ignition_tick
		if trigger != null and (not (trigger is int) or trigger < model.first_tick or trigger > MAX_TICK):
			return {"ok": false, "error": "ignition_tick must be null or a bounded future tick"}
		if not (src.allocation_shares is PackedFloat64Array) or src.allocation_shares.size() != model.components.size():
			return {"ok": false, "error": "allocation_shares must be an aligned PackedFloat64Array"}
		var share_sum := 0.0
		for share in src.allocation_shares:
			if not _finite(share) or share < 0.0 or share > 1.0:
				return {"ok": false, "error": "allocation shares must be finite in [0,1]"}
			share_sum += share
		if share_sum > 1.0:
			return {"ok": false, "error": "allocation shares must sum to at most one"}
		if not _valid_basis(src.basis) or not _valid_provenance(src.provenance):
			return {"ok": false, "error": "source basis/provenance required"}
		total_power += float(src.power_w)
		if total_power > MAX_TOTAL_POWER:
			return {"ok": false, "error": "total source power outside finite bound"}
	return {"ok": true}


static func _valid_state(model: Dictionary, state: State) -> bool:
	if state.last_tick < int(model.first_tick) - 1 or state.last_tick > MAX_TICK:
		return false
	if state.temperatures_k.size() != model.components.size() or state.dose_k_s.size() != model.components.size():
		return false
	if state.source_remaining_j.size() != model.sources.size():
		return false
	for ci in range(model.components.size()):
		var temp: float = state.temperatures_k[ci]
		var dose: float = state.dose_k_s[ci]
		if not _finite(temp) or temp < float(model.components[ci].ambient_k) or temp > MAX_K:
			return false
		if not _finite(dose) or dose < 0.0 or dose > MAX_DOSE:
			return false
	for si in range(model.sources.size()):
		var remaining: float = state.source_remaining_j[si]
		if not _finite(remaining) or remaining < 0.0 or remaining > float(model.sources[si].energy_j):
			return false
	return true


static func _qualified_unrecoverable(model: Dictionary, component_index: int) -> bool:
	var part: Dictionary = model.components[component_index]
	if part.damage_threshold_basis != VALIDATED or part.parameter_basis != VALIDATED:
		return false
	for src in model.sources:
		if src.ignition_tick != null and src.allocation_shares[component_index] > 0.0 and src.basis != VALIDATED:
			return false
	return true


static func _basis(model: Dictionary) -> String:
	for part in model.components:
		if part.parameter_basis != VALIDATED:
			return SCENARIO
		if part.damage_dose_threshold_k_s != null and part.damage_threshold_basis != VALIDATED:
			return SCENARIO
	for src in model.sources:
		if src.basis != VALIDATED:
			return SCENARIO
	return VALIDATED

static func _fingerprint(model: Dictionary) -> String:
	return JSON.stringify(model, "", true, true).sha256_text()


static func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true


static func _valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 80


static func _valid_basis(value: Variant) -> bool:
	return value == SCENARIO or value == VALIDATED


static func _valid_provenance(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 1000


static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _sum(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


static func _copy_state(old: State) -> State:
	var copy := State.new()
	copy.model_sha256 = old.model_sha256
	copy.last_tick = old.last_tick
	copy.temperatures_k = old.temperatures_k.duplicate()
	copy.dose_k_s = old.dose_k_s.duplicate()
	copy.source_remaining_j = old.source_remaining_j.duplicate()
	return copy


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
