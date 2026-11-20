# Fixture-only extraction from app/render/lake/lake_plants.gd; selected functions are unchanged.
extends RefCounted
const Surface := preload("res://physics/lake_surface.gd")
const SEED := 221022
const LILY_ANCHORS := [1, 4, 7, 10, 13, 15, 18]
const REED_ANCHORS := [3, 9, 16]

static func layout(lake: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pads: Array[Dictionary] = []
	var flowers: Array[Dictionary] = []
	var reeds: Array[Dictionary] = []
	for anchor_index in LILY_ANCHORS:
		var anchor := _anchor(lake, anchor_index)
		if anchor.is_empty():
			continue
		var cluster_count := 0
		for attempt in 80:
			if cluster_count >= 15:
				break
			var tangent_m := rng.randf_range(-5.5, 5.5)
			var inset_m := rng.randf_range(2.4, 7.6)
			var point: Vector2 = anchor.point + anchor.tangent * tangent_m - anchor.outward * inset_m
			var distance := Surface.shore_distance_validated(lake, point.x, point.y)
			if distance < 1.15 or distance > 9.0 or _too_close(pads, point, 0.60):
				continue
			var sample := Surface.sample_terrain_validated(lake, point.x, point.y)
			if str(sample.get("region", "")) != "bed" or float(sample.get("bed_depth_m", 0.0)) < 0.30 \
					or float(sample.get("bed_depth_m", 0.0)) > 1.15:
				continue
			pads.append({"north": point.x, "east": point.y, "shore_m": distance,
				"depth_m": float(sample.bed_depth_m), "diameter_m": rng.randf_range(0.56, 0.94),
				"angle": rng.randf_range(-PI, PI), "tint": rng.randf_range(0.80, 1.18),
				"cluster": anchor_index})
			cluster_count += 1
			if cluster_count == 5 or cluster_count == 12:
				var flower_point: Vector2 = point + anchor.tangent * 0.46
				var flower_shore := Surface.shore_distance_validated(lake, flower_point.x, flower_point.y)
				if flower_shore > 0.75:
					flowers.append({"north": flower_point.x, "east": flower_point.y,
						"shore_m": flower_shore, "angle": rng.randf_range(-PI, PI),
						"cluster": anchor_index})
	for anchor_index in REED_ANCHORS:
		var anchor := _anchor(lake, anchor_index)
		if anchor.is_empty():
			continue
		var cluster_count := 0
		for attempt in 70:
			if cluster_count >= 9:
				break
			var point: Vector2 = anchor.point + anchor.tangent * rng.randf_range(-4.2, 4.2) \
				- anchor.outward * rng.randf_range(0.55, 2.25)
			var distance := Surface.shore_distance_validated(lake, point.x, point.y)
			if distance < 0.45 or distance > 2.5 or _too_close(reeds, point, 0.9):
				continue
			var sample := Surface.sample_terrain_validated(lake, point.x, point.y)
			if str(sample.get("region", "")) != "bed" or float(sample.get("bed_depth_m", 1.0)) > 0.38:
				continue
			reeds.append({"north": point.x, "east": point.y, "shore_m": distance,
				"depth_m": float(sample.bed_depth_m), "ground_down_m": float(sample.ground_down_m),
				"height_m": rng.randf_range(1.00, 1.55), "angle": rng.randf_range(-PI, PI),
				"cluster": anchor_index})
			cluster_count += 1
	return {"pads": pads, "flowers": flowers, "reeds": reeds}

static func _anchor(lake: Dictionary, index: int) -> Dictionary:
	var shore: PackedFloat64Array = lake.shoreline_ne_m
	var bank: PackedFloat64Array = lake.bank_ne_m
	var count := shore.size() / 2
	if count < 3 or index >= count:
		return {}
	var before := posmod(index - 1, count)
	var after := posmod(index + 1, count)
	var point := Vector2(shore[index * 2], shore[index * 2 + 1])
	var tangent := Vector2(shore[after * 2] - shore[before * 2],
		shore[after * 2 + 1] - shore[before * 2 + 1]).normalized()
	var outward := (Vector2(bank[index * 2], bank[index * 2 + 1]) - point).normalized()
	return {"point": point, "tangent": tangent, "outward": outward}

static func _too_close(records: Array[Dictionary], point: Vector2, spacing: float) -> bool:
	for record in records:
		if point.distance_to(Vector2(float(record.north), float(record.east))) < spacing:
			return true
	return false
