## FW-84. Deterministic, presentation-only electrical storm event schedule.
## Event identity depends on the visual seed and simulation tick, never render cadence or a global RNG.
extends RefCounted

const SCHEDULE_VERSION: int = 1
const SLOT_SECONDS: float = 12.0
const MAX_EVENT_SECONDS: float = 1.25
const MAX_QUERY_SLOTS: int = 64
const DEFAULT_ANCHOR_WORLD: Vector3 = Vector3(0.0, 3000.0, -9000.0)
const DEFAULT_GROUND_WORLD: Vector3 = Vector3(0.0, 0.0, -9000.0)
const StormCell := preload("res://render/weather/storm_cell.gd")

var _enabled: bool = false
var _seed: int = 1
var _tick_rate_hz: int = 60
var _slot_ticks: int = 720
var _appearance_generation: int = 0
var _anchor_world: Vector3 = DEFAULT_ANCHOR_WORLD
var _ground_world: Vector3 = DEFAULT_GROUND_WORLD
var _cell_spec: Dictionary = {}
var _cell_transport: Dictionary = {}
var _cell_reference_world: Vector3 = Vector3.ZERO
var _cell_context_valid: bool = false


func configure(config: Dictionary) -> void:
	_clear_cell_context()
	_enabled = str(config.get("preset", "classic")) == "electrical_storm"
	_seed = int(config.get("seed", 1))
	_tick_rate_hz = clampi(int(config.get("tick_rate_hz", Engine.physics_ticks_per_second)), 1, 1000)
	_slot_ticks = maxi(1, int(round(SLOT_SECONDS * float(_tick_rate_hz))))
	_anchor_world = _as_vector3(config.get("storm_anchor_world", DEFAULT_ANCHOR_WORLD), DEFAULT_ANCHOR_WORLD)
	_ground_world = _as_vector3(config.get("storm_ground_world", DEFAULT_GROUND_WORLD), DEFAULT_GROUND_WORLD)
	_appearance_generation = int(hash([_seed, "FW84", SCHEDULE_VERSION]))


func reset() -> void:
	# No mutable cursor exists here; consumers reset their playback and history cursors.
	pass


func set_cloud_altitude(altitude_m: float) -> void:
	# Presentation anchor only; the simulation state and event identity do not change.
	_anchor_world.y = maxf(altitude_m, 100.0)


## Optional FW-84b placement context. Empty or malformed input clears back to legacy placement.
## Event schedules remain pure: each emitted position is reconstructed from its own start time.
func set_cell_context(spec: Dictionary, transport: Dictionary, reference_world: Vector3) -> void:
	if spec.is_empty() and transport.is_empty():
		_clear_cell_context()
		return
	if not is_finite(reference_world.x) or not is_finite(reference_world.y) or not is_finite(reference_world.z):
		_clear_cell_context()
		return
	if _cell_context_valid and spec == _cell_spec and transport == _cell_transport:
		_cell_reference_world = reference_world
		return
	if not StormCell.context_is_valid(spec, transport, reference_world):
		_clear_cell_context()
		return
	_cell_spec = spec.duplicate(true)
	_cell_transport = transport.duplicate(true)
	_cell_reference_world = reference_world
	_cell_context_valid = true


func _clear_cell_context() -> void:
	_cell_spec.clear()
	_cell_transport.clear()
	_cell_reference_world = Vector3.ZERO
	_cell_context_valid = false


func enabled() -> bool:
	return _enabled


func tick_rate_hz() -> int:
	return _tick_rate_hz


func tick_for_time(sim_time_s: float) -> int:
	return int(round(maxf(sim_time_s, 0.0) * float(_tick_rate_hz)))


func events_for_window(from_tick: int, to_tick: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _enabled or to_tick < 0 or from_tick > to_tick:
		return result
	var max_duration_ticks: int = int(ceil(MAX_EVENT_SECONDS * float(_tick_rate_hz)))
	var first_slot: int = maxi(0, int(floor(float(from_tick - max_duration_ticks) / float(_slot_ticks))))
	var last_slot: int = maxi(0, int(floor(float(to_tick) / float(_slot_ticks))) + 1)
	# Callers reconstruct near the displayed time. A long seek must not turn into unbounded history replay.
	first_slot = maxi(first_slot, last_slot - MAX_QUERY_SLOTS + 1)
	for slot_index: int in range(first_slot, last_slot + 1):
		var event: Dictionary = _event_for_slot(slot_index)
		if event.is_empty():
			continue
		var start_tick: int = int(event.start_tick)
		var end_tick: int = start_tick + int(ceil(float(event.duration_s) * float(_tick_rate_hz)))
		if start_tick <= to_tick and end_tick >= from_tick:
			result.append(event)
	return result


func events_started_between(from_tick_exclusive: int, to_tick_inclusive: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if to_tick_inclusive <= from_tick_exclusive:
		return result
	for event: Dictionary in events_for_window(from_tick_exclusive, to_tick_inclusive):
		var start_tick: int = int(event.start_tick)
		if start_tick > from_tick_exclusive and start_tick <= to_tick_inclusive:
			result.append(event)
	return result


func events_started_in_window(from_tick_inclusive: int, to_tick_inclusive: int) -> Array[Dictionary]:
	## Rebuilds presentation queues after a restore. Unlike events_for_window(), this includes
	## events whose visible flash has ended but whose bounded sound travel is still in progress.
	var result: Array[Dictionary] = []
	if not _enabled or to_tick_inclusive < from_tick_inclusive or to_tick_inclusive < 0:
		return result
	var first_slot: int = maxi(0, int(floor(float(from_tick_inclusive) / float(_slot_ticks))))
	var last_slot: int = maxi(0, int(floor(float(to_tick_inclusive) / float(_slot_ticks))) + 1)
	first_slot = maxi(first_slot, last_slot - MAX_QUERY_SLOTS + 1)
	for slot_index: int in range(first_slot, last_slot + 1):
		var event: Dictionary = _event_for_slot(slot_index)
		if event.is_empty():
			continue
		var start_tick: int = int(event.start_tick)
		if start_tick >= from_tick_inclusive and start_tick <= to_tick_inclusive:
			result.append(event)
	return result


func _event_for_slot(slot_index: int) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# A private stream per slot means querying or skipping other slots cannot advance this slot's RNG.
	rng.seed = int(_seed ^ (slot_index * 104729 + 97))
	if rng.randf() >= 0.78:
		return {}
	var start_s: float = float(slot_index) * SLOT_SECONDS + rng.randf_range(1.25, 10.75)
	var start_tick: int = int(round(start_s * float(_tick_rate_hz)))
	var start_time_s: float = float(start_tick) / float(_tick_rate_hz)
	var kind: String = "cloud_to_ground" if rng.randf() < 0.16 else "intracloud"
	# Keep these private-stream draws and their order identical to FW-84's legacy schedule.
	var source_offset_x: float = rng.randf_range(-1500.0, 1500.0)
	var source_offset_y: float = rng.randf_range(-220.0, 420.0)
	var source_offset_z: float = rng.randf_range(-1200.0, 1200.0)
	var source: Vector3 = _anchor_world + Vector3(source_offset_x, source_offset_y, source_offset_z)
	var ground_offset_x: float = rng.randf_range(-500.0, 500.0)
	var ground_offset_z: float = rng.randf_range(-500.0, 500.0)
	var ground: Vector3 = _ground_world + Vector3(source.x - _anchor_world.x + ground_offset_x,
		0.0, source.z - _anchor_world.z + ground_offset_z)
	var channel: Vector3 = source.lerp(ground, 0.48) if kind == "cloud_to_ground" else source + Vector3(850.0, -170.0, -240.0)
	var geometry_seed: int = int(rng.randi() & 0x7fffffff)
	var placement_mode: String = "legacy"
	if _cell_context_valid:
		var placed: Dictionary = _place_in_cell(start_time_s, source_offset_x, source_offset_z,
			ground_offset_x, ground_offset_z, kind)
		source = placed.source
		ground = placed.ground
		channel = placed.channel
		placement_mode = "storm_cell"
	var pulses: Array[Dictionary] = []
	if kind == "cloud_to_ground":
		pulses = [
			{"offset_s": 0.0, "duration_s": 0.075, "intensity": 1.0},
			{"offset_s": 0.16, "duration_s": 0.060, "intensity": 0.58},
			{"offset_s": 0.61, "duration_s": 0.095, "intensity": 0.72},
		]
	else:
		pulses = [
			{"offset_s": 0.0, "duration_s": 0.18, "intensity": 0.66},
			{"offset_s": 0.29, "duration_s": 0.12, "intensity": 0.42},
			{"offset_s": 0.78, "duration_s": 0.16, "intensity": 0.56},
		]
	var event := {
		"version": SCHEDULE_VERSION,
		"event_id": "%d:%d" % [_appearance_generation, slot_index],
		"slot_index": slot_index,
		"appearance_generation": _appearance_generation,
		"start_tick": start_tick,
		"start_time_s": start_time_s,
		"kind": kind,
		"geometry_seed": geometry_seed,
		"source_world": _to_f64(source),
		"ground_world": _to_f64(ground),
		"channel_world": _to_f64(channel),
		"pulse_envelope": pulses,
		"duration_s": 0.94,
		"intensity": 1.0 if kind == "cloud_to_ground" else 0.72,
		"thunder_asset_id": "rubberduck_100_cc0_thunder_01",
	}
	if placement_mode == "storm_cell":
		event["placement_mode"] = placement_mode
	return event


func _place_in_cell(start_time_s: float, source_offset_x: float, source_offset_z: float,
		ground_offset_x: float, ground_offset_z: float, kind: String) -> Dictionary:
	var center: Vector3 = StormCell.center_at(_cell_spec, _cell_transport, start_time_s, _cell_reference_world)
	var width_m: float = float(_cell_spec.width_m)
	var depth_m: float = float(_cell_spec.depth_m)
	var source_x: float = source_offset_x / 1500.0 * width_m * 0.12
	var source_z: float = source_offset_z / 1200.0 * depth_m * 0.16
	var source_height: float = float(_cell_spec.base_m) \
		+ (float(_cell_spec.top_m) - float(_cell_spec.base_m)) * 0.65
	var source: Vector3 = Vector3(center.x + source_x, source_height, center.z + source_z)
	var ground: Vector3 = Vector3(
		center.x + source_x + ground_offset_x / 500.0 * width_m * 0.08,
		0.0,
		center.z + source_z + ground_offset_z / 500.0 * depth_m * 0.08)
	var channel: Vector3 = source.lerp(ground, 0.48) if kind == "cloud_to_ground" \
		else source + Vector3(850.0, -170.0, -240.0)
	return {"source": source, "ground": ground, "channel": channel}


static func _as_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


static func _to_f64(value: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([value.x, value.y, value.z])
