extends RefCounted

## Deterministic presentation-only cloud advection. Offsets are in base-noise cells, with the
## positive direction matching the shader's texture offset (and therefore opposite cloud motion).
const VERSION := 1
const PERIOD := 64.0
const MAX_LAYERS := 8
const VALID_MOTIONS := ["legacy", "still", "follow_wind", "aloft"]
const VALID_TYPES := ["cirrus", "fair_cumulus", "cumulus", "stratocumulus", "stratus", "cumulonimbus", "anvil"]
const STATE_KEYS := ["version", "motion", "anchor_time_s", "step_s", "mean_wind_ned", "legacy_anchor_offset", "legacy_velocity_cells_s", "layers"]
const LAYER_KEYS := ["type", "seed", "scale_m", "drift_multiplier", "cluster_strength", "anchor_offset", "velocity_cells_s"]


static func build(selection: Dictionary, layers: Array, mean_wind_ned: Array, anchor_time_s: float,
		step_s: float, legacy_drift_cells_s: Vector2, base_offsets: Array, legacy_cell_scale_m := 250.0) -> Dictionary:
	var motion := str(selection.get("motion", "legacy"))
	if not VALID_MOTIONS.has(motion):
		return {}
	var wind := _wind_array(mean_wind_ned)
	var quantum := step_s if is_finite(step_s) and step_s > 0.0 else 1.0
	var at := anchor_time_s if is_finite(anchor_time_s) else 0.0
	var classic_scale := maxf(legacy_cell_scale_m, 1.0)
	var aloft := _aloft_ned(selection)
	var legacy_velocity := [legacy_drift_cells_s.x, legacy_drift_cells_s.y]
	match motion:
		"still":
			legacy_velocity = [0.0, 0.0]
		"follow_wind":
			legacy_velocity = [-float(wind[1]) / classic_scale, float(wind[0]) / classic_scale]
		"aloft":
			legacy_velocity = [-float(aloft[1]) / classic_scale, float(aloft[0]) / classic_scale]
	var state := {
		"version": VERSION,
		"motion": motion,
		"anchor_time_s": at,
		"step_s": quantum,
		"mean_wind_ned": wind,
		"legacy_anchor_offset": _offset_at(base_offsets, 0),
		"legacy_velocity_cells_s": legacy_velocity,
		"layers": [],
	}
	for i in mini(layers.size(), MAX_LAYERS):
		var source: Dictionary = layers[i]
		var scale_m := maxf(float(source.get("scale_m", 1.0)), 1.0)
		var multiplier := clampf(float(source.get("drift_multiplier", 1.0)), 0.0, 4.0)
		var velocity_x := 0.0
		var velocity_y := 0.0
		match motion:
			"legacy":
				velocity_x = legacy_drift_cells_s.x * multiplier
				velocity_y = legacy_drift_cells_s.y * multiplier
			"follow_wind":
				velocity_x = -float(wind[1]) * multiplier / scale_m
				velocity_y = float(wind[0]) * multiplier / scale_m
			"aloft":
				velocity_x = -float(aloft[1]) * multiplier / scale_m
				velocity_y = float(aloft[0]) * multiplier / scale_m
			# still leaves the initialized zero velocity.
		var record := {
			"type": str(source.get("type", "cumulus")),
			"seed": int(source.get("seed", 1)),
			"scale_m": scale_m,
			"drift_multiplier": multiplier,
			"cluster_strength": clampf(float(source.get("cluster_strength", 0.0)), 0.0, 1.0),
			"anchor_offset": _offset_at(base_offsets, i),
			"velocity_cells_s": [velocity_x, velocity_y],
		}
		state.layers.append(record)
	return state if validate(state) else {}


static func legacy_offset(state: Dictionary, sim_time_s: float) -> Vector2:
	var pair := legacy_offset_pair(state, sim_time_s)
	return Vector2(float(pair[0]), float(pair[1]))


static func legacy_offset_pair(state: Dictionary, sim_time_s: float) -> Array:
	return _offset_pair(state.get("legacy_anchor_offset", [0.0, 0.0]),
		state.get("legacy_velocity_cells_s", [0.0, 0.0]), state, sim_time_s)


static func layer_offset(state: Dictionary, index: int, sim_time_s: float) -> Vector2:
	var layers: Array = state.get("layers", [])
	if index < 0 or index >= layers.size():
		return Vector2.ZERO
	var record: Dictionary = layers[index]
	var pair := _offset_pair(record.get("anchor_offset", [0.0, 0.0]),
		record.get("velocity_cells_s", [0.0, 0.0]), state, sim_time_s)
	return Vector2(float(pair[0]), float(pair[1]))


static func offsets(state: Dictionary, sim_time_s: float) -> Array:
	var result := []
	var layers: Array = state.get("layers", [])
	for i in layers.size():
		var layer: Dictionary = layers[i]
		result.append(_offset_pair(layer.anchor_offset, layer.velocity_cells_s, state, sim_time_s))
	return result


static func rebase(state: Dictionary, sim_time_s: float) -> Dictionary:
	if not validate(state) or not is_finite(sim_time_s):
		return {}
	var result: Dictionary = state.duplicate(true)
	result.anchor_time_s = sim_time_s
	result.legacy_anchor_offset = _offset_pair(state.legacy_anchor_offset, state.legacy_velocity_cells_s, state, sim_time_s)
	for i in result.layers.size():
		var layer: Dictionary = state.layers[i]
		result.layers[i].anchor_offset = _offset_pair(layer.anchor_offset, layer.velocity_cells_s, state, sim_time_s)
	return result


## Strict, read-only structural check suitable for validating a checkpoint before any state is committed.
static func validate(raw: Variant) -> bool:
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var value: Dictionary = raw
	if not _has_exact_keys(value, STATE_KEYS) or typeof(value.get("version")) != TYPE_INT \
			or int(value.version) != VERSION or not VALID_MOTIONS.has(value.get("motion", "")):
		return false
	if not _finite_in_range(value.get("anchor_time_s"), 0.0, 1.0e15):
		return false
	if not _finite_in_range(value.get("step_s"), 0.001, 60.0):
		return false
	if not _valid_vector(value.get("mean_wind_ned"), 3, -1000.0, 1000.0):
		return false
	if not _valid_offset(value.get("legacy_anchor_offset")):
		return false
	if not _valid_vector(value.get("legacy_velocity_cells_s"), 2, -10.0, 10.0):
		return false
	var layers: Variant = value.get("layers")
	if typeof(layers) != TYPE_ARRAY or layers.size() > MAX_LAYERS:
		return false
	for layer_value: Variant in layers:
		if typeof(layer_value) != TYPE_DICTIONARY:
			return false
		var layer: Dictionary = layer_value
		if not _has_exact_keys(layer, LAYER_KEYS):
			return false
		if not VALID_TYPES.has(layer.get("type", "")):
			return false
		if typeof(layer.get("seed")) != TYPE_INT or int(layer.seed) < 0 or int(layer.seed) > 0xffffffff:
			return false
		if not _finite_in_range(layer.get("scale_m"), 100.0, 50000.0):
			return false
		if not _finite_in_range(layer.get("drift_multiplier"), 0.0, 4.0):
			return false
		if not _finite_in_range(layer.get("cluster_strength"), 0.0, 1.0):
			return false
		if not _valid_offset(layer.get("anchor_offset")):
			return false
		if not _valid_vector(layer.get("velocity_cells_s"), 2, -10.0, 10.0):
			return false
	return true


static func _offset(anchor: Vector2, velocity: Vector2, state: Dictionary, sim_time_s: float) -> Vector2:
	if not is_finite(sim_time_s):
		return anchor
	var at := float(state.get("anchor_time_s", 0.0))
	var step := maxf(float(state.get("step_s", 1.0)), 0.001)
	var t0 := floorf(at / step) * step
	var t := floorf(sim_time_s / step) * step
	var elapsed := t - t0
	return Vector2(fposmod(anchor.x + velocity.x * elapsed, PERIOD),
		fposmod(anchor.y + velocity.y * elapsed, PERIOD))


## Keep checkpoint rebasing in scalar float64 arithmetic; Vector2 is only the GPU-facing representation.
static func _offset_pair(anchor_raw: Variant, velocity_raw: Variant, state: Dictionary, sim_time_s: float) -> Array:
	var anchor_x := float(anchor_raw[0])
	var anchor_y := float(anchor_raw[1])
	var velocity_x := float(velocity_raw[0])
	var velocity_y := float(velocity_raw[1])
	if not is_finite(sim_time_s):
		return [fposmod(anchor_x, PERIOD), fposmod(anchor_y, PERIOD)]
	var step := maxf(float(state.get("step_s", 1.0)), 0.001)
	var t0 := floorf(float(state.get("anchor_time_s", 0.0)) / step) * step
	var time := floorf(sim_time_s / step) * step
	var elapsed := time - t0
	return [fposmod(anchor_x + velocity_x * elapsed, PERIOD), fposmod(anchor_y + velocity_y * elapsed, PERIOD)]


static func _wind_array(raw: Array) -> Array:
	if raw.size() < 3:
		return [0.0, 0.0, 0.0]
	var result := []
	for i in 3:
		var item: Variant = raw[i]
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)):
			return [0.0, 0.0, 0.0]
		result.append(float(item))
	return result


static func _aloft_ned(selection: Dictionary) -> Array:
	var speed := float(selection.get("wind_aloft_speed_mps", 0.0))
	var from_deg := float(selection.get("wind_aloft_from_deg", 0.0))
	if not is_finite(speed) or not is_finite(from_deg):
		return [0.0, 0.0, 0.0]
	var from_rad := deg_to_rad(from_deg)
	return [-cos(from_rad) * speed, -sin(from_rad) * speed, 0.0]


static func _offset_at(offsets_value: Array, index: int) -> Array:
	if offsets_value.is_empty():
		return [0.0, 0.0]
	var source_index := mini(index, offsets_value.size() - 1)
	var value: Variant = offsets_value[source_index]
	if value is Vector2:
		return [fposmod(value.x, PERIOD), fposmod(value.y, PERIOD)]
	if _valid_vector(value, 2, -1.0e9, 1.0e9):
		return [fposmod(float(value[0]), PERIOD), fposmod(float(value[1]), PERIOD)]
	return [0.0, 0.0]


static func _read_pair(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if _valid_vector(raw, 2, -1.0e9, 1.0e9):
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


static func _valid_vector(raw: Variant, length: int, low: float, high: float) -> bool:
	if typeof(raw) != TYPE_ARRAY and typeof(raw) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	if raw.size() != length:
		return false
	for item: Variant in raw:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not _finite_in_range(item, low, high):
			return false
	return true


static func _valid_offset(raw: Variant) -> bool:
	if not _valid_vector(raw, 2, 0.0, PERIOD):
		return false
	return float(raw[0]) < PERIOD and float(raw[1]) < PERIOD


static func _finite_in_range(raw: Variant, low: float, high: float) -> bool:
	return typeof(raw) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(raw)) and float(raw) >= low and float(raw) <= high


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true
