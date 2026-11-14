## LU-21: scalar support heights for scenery that has a raised walkable slab.
## Coordinates are world north/east metres; heights are metres above the field datum.
extends RefCounted

# Anrico seated mesh rests at 0.4742 m; the existing bench top is 0.48 m.
const SEATED_OFFSET_M := 0.006

const SURFACE_SPECS := {
	"pavilion": {"half_width_m": 5.0, "half_depth_m": 4.8, "center_local_z_m": -1.3, "top_up_m": 0.15},
	"pit_shelter": {"half_width_m": 14.3, "half_depth_m": 2.8, "center_local_z_m": 0.0, "top_up_m": 0.10},
}


## Build immutable-by-convention scalar support records from normalized placements.
static func build(scenery: Dictionary) -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	var groups_value: Variant = scenery.get("groups", [])
	if typeof(groups_value) != TYPE_ARRAY:
		return surfaces
	for group_value: Variant in groups_value:
		if typeof(group_value) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = group_value
		if str(group.get("type", "")) != "instances":
			continue
		var placements_value: Variant = group.get("placements", [])
		if typeof(placements_value) != TYPE_ARRAY:
			continue
		for index: int in placements_value.size():
			if typeof(placements_value[index]) != TYPE_DICTIONARY:
				continue
			var placement: Dictionary = placements_value[index]
			var prefab := str(placement.get("prefab", group.get("prefab", "")))
			if not SURFACE_SPECS.has(prefab):
				continue
			var north_value: Variant = placement.get("north", NAN)
			var east_value: Variant = placement.get("east", NAN)
			var heading_value: Variant = placement.get("heading", 0.0)
			if not _finite_number(north_value) or not _finite_number(east_value) or not _finite_number(heading_value):
				continue
			var heading := deg_to_rad(float(heading_value))
			var spec: Dictionary = SURFACE_SPECS[prefab]
			surfaces.append({
				"id": "%s:%02d:%s" % [str(group.get("id", "group")), index, prefab],
				"prefab": prefab,
				"north": float(north_value),
				"east": float(east_value),
				"sin_heading": sin(heading),
				"cos_heading": cos(heading),
				"half_width_m": float(spec.half_width_m),
				"half_depth_m": float(spec.half_depth_m),
				"center_local_z_m": float(spec.center_local_z_m),
				"top_up_m": float(spec.top_up_m),
			})
	return surfaces


## Highest slab top containing this point; zero is the field datum when no support is present.
static func height_at(north: float, east: float, surfaces: Array[Dictionary]) -> float:
	if not is_finite(north) or not is_finite(east):
		return 0.0
	var height := 0.0
	for surface: Dictionary in surfaces:
		var center_north := float(surface.get("north", NAN))
		var center_east := float(surface.get("east", NAN))
		var sin_heading := float(surface.get("sin_heading", NAN))
		var cos_heading := float(surface.get("cos_heading", NAN))
		var half_width := float(surface.get("half_width_m", NAN))
		var half_depth := float(surface.get("half_depth_m", NAN))
		var center_local_z := float(surface.get("center_local_z_m", NAN))
		var top_up := float(surface.get("top_up_m", NAN))
		if not _finite_all([center_north, center_east, sin_heading, cos_heading, half_width,
				half_depth, center_local_z, top_up]) or half_width <= 0.0 or half_depth <= 0.0:
			continue
		var delta_north := north - center_north
		var delta_east := east - center_east
		# Inverse of Scenery._placement_xf / CollisionWorld._placement_point, in scalar N/E math.
		var local_x := -sin_heading * delta_north + cos_heading * delta_east
		var local_z := -cos_heading * delta_north - sin_heading * delta_east
		if absf(local_x) <= half_width and absf(local_z - center_local_z) <= half_depth:
			height = maxf(height, top_up)
	return height


static func _finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _finite_all(values: Array) -> bool:
	for value: Variant in values:
		if not _finite_number(value):
			return false
	return true
