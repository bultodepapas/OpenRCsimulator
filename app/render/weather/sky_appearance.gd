extends RefCounted

## Maps the validated preset catalog into render-only values. RGB source values are sRGB; shader
## colors are stored here in linear units so they match the existing Atmosphere pipeline.
const MAX_LAYERS := 8
const CLOUD_PERIOD := 64.0


static func resolve(profile: Dictionary, selection: Dictionary) -> Dictionary:
	var renderer: Dictionary = profile.get("renderer", {})
	if renderer.is_empty():
		return {}
	var base_seed := int(selection.get("seed", 1))
	var layers: Array[Dictionary] = []
	var source_layers: Array = renderer.get("cloud_layers", [])
	for index in mini(source_layers.size(), MAX_LAYERS):
		var source: Dictionary = source_layers[index]
		var layer := source.duplicate(true)
		layer["seed"] = (base_seed + (index + 1) * 104729) & 0x7fffffff
		layer["cluster_strength"] = cluster_strength(String(source.get("type", "")))
		layers.append(layer)
	return {
		"id": str(profile.get("id", "")),
		"legacy": str(profile.get("id", "")) == "classic" or str(selection.get("preset", "")) == "classic",
		"cloud_cover": clampf(float(renderer.get("cloud_cover", 0.0)), 0.0, 1.0),
		"cloud_density": clampf(float(renderer.get("cloud_density", 0.0)), 0.0, 1.0),
		"cloud_layers": layers,
		"zenith_lin": _linear_rgb(renderer.get("zenith_color", [0.0, 0.0, 0.0])),
		"horizon_lin": _linear_rgb(renderer.get("horizon_color", [0.0, 0.0, 0.0])),
		"cloud_lin": _linear_rgb(renderer.get("cloud_color", [1.0, 1.0, 1.0])),
		"sun_lin": _linear_rgb(renderer.get("sun_color", [1.0, 1.0, 1.0])),
		"ambient_lin": _linear_rgb(renderer.get("ambient_color", [1.0, 1.0, 1.0])),
		"sun_intensity": clampf(float(renderer.get("sun_intensity", 1.0)), 0.0, 2.0),
		"ambient_intensity": clampf(float(renderer.get("ambient_intensity", 1.0)), 0.0, 2.0),
		"haze": clampf(float(renderer.get("haze", 0.0)), 0.0, 1.0),
		"haze_scale": 0.45 + 3.0 * clampf(float(renderer.get("haze", 0.0)), 0.0, 1.0),
		"cloud_shadow": clampf(float(renderer.get("cloud_shadow", 0.0)), 0.0, 1.0),
	}


static func cluster_strength(layer_type: String) -> float:
	match layer_type:
		"cirrus", "anvil":
			return 0.0
		"fair_cumulus":
			return 0.62
		"stratocumulus":
			return 0.34
		"stratus":
			return 0.08
		"cumulus":
			return 0.42
		"cumulonimbus":
			return 0.44
	return 0.0


static func shape_code(layer_type: String) -> float:
	if layer_type == "cirrus":
		return 1.0
	if layer_type == "anvil":
		return 2.0
	if layer_type == "stratus":
		return 3.0
	if layer_type == "cumulonimbus":
		return 4.0
	if layer_type == "fair_cumulus":
		return 5.0
	return 0.0


static func shader_arrays(layers: Array, offsets: Array, cloud_cover: float, cloud_density: float) -> Dictionary:
	var parameters := PackedVector4Array()
	var motion := PackedVector4Array()
	var seeds := PackedInt32Array()
	var count := mini(layers.size(), MAX_LAYERS)
	var order: Array[int] = []
	for index in count:
		order.append(index)
	# The shader paints from the highest deck down to the nearest low deck. Sort the
	# resolved arrays by altitude so catalog order cannot reverse cloud occlusion.
	for left in count:
		for right in range(left + 1, count):
			if float(layers[order[right]].get("altitude_m", 0.0)) < float(layers[order[left]].get("altitude_m", 0.0)):
				var swap := order[left]
				order[left] = order[right]
				order[right] = swap
	for index in count:
		var source_index := order[index]
		var layer: Dictionary = layers[source_index]
		var offset := _read_offset(offsets, source_index)
		var coverage := clampf(float(layer.get("coverage", 0.0)) + (cloud_cover - 0.5) * 0.5, 0.0, 1.0)
		parameters.append(Vector4(float(layer.get("altitude_m", 0.0)), float(layer.get("scale_m", 1000.0)),
			coverage, clampf(float(layer.get("density", 0.0)), 0.0, 1.0)))
		motion.append(Vector4(offset.x, offset.y, cluster_strength(String(layer.get("type", ""))),
			shape_code(String(layer.get("type", "")))))
		seeds.append(int(layer.get("seed", 1)))
	while parameters.size() < MAX_LAYERS:
		parameters.append(Vector4.ZERO)
		motion.append(Vector4.ZERO)
		seeds.append(0)
	return {
		"layer_count": count,
		"layer_parameters": parameters,
		"layer_motion": motion,
		"layer_seeds": seeds,
		"cloud_density": clampf(cloud_density, 0.0, 1.0),
	}


static func _linear_rgb(raw: Variant) -> Vector3:
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return Vector3.ONE
	var value := Color(float(raw[0]), float(raw[1]), float(raw[2])).srgb_to_linear()
	return Vector3(value.r, value.g, value.b)


static func _read_offset(offsets: Array, index: int) -> Vector2:
	if index >= offsets.size():
		return Vector2.ZERO
	var raw: Variant = offsets[index]
	if raw is Vector2:
		return Vector2(fposmod(raw.x, CLOUD_PERIOD), fposmod(raw.y, CLOUD_PERIOD))
	if typeof(raw) == TYPE_ARRAY and raw.size() == 2:
		return Vector2(fposmod(float(raw[0]), CLOUD_PERIOD), fposmod(float(raw[1]), CLOUD_PERIOD))
	return Vector2.ZERO
