extends RefCounted

## FW-84b shared storm-bank placement math. Coordinates are presentation-only.
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")
const CELLS_PER_PERIOD: float = 64.0


static func context_is_valid(spec: Variant, transport: Variant, reference_world: Variant) -> bool:
	if typeof(spec) != TYPE_DICTIONARY or typeof(transport) != TYPE_DICTIONARY:
		return false
	if not reference_world is Vector3 or not _finite_vector3(reference_world):
		return false
	if not CloudTransport.validate(transport):
		return false
	var layers_value: Variant = transport.get("layers")
	if typeof(layers_value) != TYPE_ARRAY:
		return false
	var layers: Array = layers_value
	return SkyConfig._validate_bank(spec, layers).is_empty()


## Return the advected bank's nearest periodic world centre at the supplied simulation time.
## Offsets stay as float64 pairs here; rendering's Vector2 conversion is only needed at the GPU edge.
static func center_at(spec: Dictionary, transport: Dictionary, time_s: float,
		reference_world: Vector3) -> Vector3:
	if not is_finite(time_s) or not context_is_valid(spec, transport, reference_world):
		return Vector3.ZERO
	var layer_index: int = int(spec.advection_layer)
	var layers: Array = transport.layers
	if layer_index < 0 or layer_index >= layers.size():
		return Vector3.ZERO
	var layer: Dictionary = layers[layer_index]
	var cell_m: float = float(layer.scale_m)
	var offsets: Array = CloudTransport.offsets(transport, time_s)
	if layer_index >= offsets.size():
		return Vector3.ZERO
	var offset_cells: Array = offsets[layer_index]
	return center_from_offset(spec, cell_m, offset_cells, reference_world)


## Convert one cloud-layer offset pair into the bank's nearest periodic world centre.
## StormBank calls this with its render-facing offset pair so both paths share the wrap formula.
static func center_from_offset(spec: Dictionary, cell_m: float, offset_cells: Array,
		reference_world: Vector3) -> Vector3:
	if not is_finite(cell_m) or cell_m <= 0.0 or offset_cells.size() < 2:
		return Vector3.ZERO
	if not spec.has("east_m") or not spec.has("north_m"):
		return Vector3.ZERO
	if not _finite_vector3(reference_world):
		return Vector3.ZERO
	for index: int in 2:
		if typeof(offset_cells[index]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(offset_cells[index])):
			return Vector3.ZERO
	var east_m: float = float(spec.east_m)
	var north_m: float = float(spec.north_m)
	if not is_finite(east_m) or not is_finite(north_m):
		return Vector3.ZERO
	var period_m: float = CELLS_PER_PERIOD * cell_m
	if not is_finite(period_m):
		return Vector3.ZERO
	var east_coordinate: float = east_m - float(offset_cells[0]) * cell_m
	var north_coordinate: float = -north_m - float(offset_cells[1]) * cell_m
	return Vector3(
		_nearest_copy(east_coordinate, reference_world.x, period_m),
		0.0,
		_nearest_copy(north_coordinate, reference_world.z, period_m))


static func _nearest_copy(coordinate: float, reference_coordinate: float, period_m: float) -> float:
	return coordinate + floor((reference_coordinate - coordinate) / period_m + 0.5) * period_m


static func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
