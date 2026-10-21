## L15b-R2: largest crown-top sway that keeps every displaced source vertex inside the
## unchanged CollisionWorld proxies of the smallest placed tree of each asset.
## godot --headless --path app --script <abs>/proxy_slack_probe.gd -- --out=<abs json>
extends SceneTree

const Library := preload("res://scenery/imported_vegetation.gd")
const VegetationPlacement := preload("res://scenery/vegetation_placement.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")


func _initialize() -> void:
	var out := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	var result := {}
	for asset_id: String in ["landscapelab_quercus", "landscapelab_pine"]:
		result[asset_id] = _probe(asset_id)
	var text := JSON.stringify(result, "\t", true) + "\n"
	print(text)
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(text)
	quit(0)


func _probe(asset_id: String) -> Dictionary:
	var smallest: Dictionary = {}
	for prefab: String in ["shade_tree", "sapling"]:
		for seed in range(512):
			var spec := VegetationPlacement.spec(prefab, seed)
			if str(spec.get("asset_id", "")) == asset_id and (smallest.is_empty() or float(spec.height) < float(smallest.height)):
				smallest = spec
	var parts := Library.get_parts(asset_id)
	var bounds: AABB = parts[0].bounds
	var ground_offset := float(Library.get_asset(asset_id).source_bounds_m.get("ground_offset", 0.0))
	var scale := float(smallest.scale)
	var height := float(smallest.height)
	var margin := float(smallest.wind_margin)
	var half_x := float(smallest.width) * 0.5 + margin
	var half_z := float(smallest.depth) * 0.5 + margin
	var crown_bottoms: Array[float] = []
	for trunk_hash in [0.0, 1.0]:
		var trunk_height: float = height * (CollisionWorld.SHADE_TREE_TRUNK_HEIGHT_FRACTION
			+ CollisionWorld.SHADE_TREE_TRUNK_HEIGHT_VARIATION_FRACTION * trunk_hash)
		if asset_id == "landscapelab_quercus":
			trunk_height = minf(trunk_height, height * CollisionWorld.LANDSCAPELAB_QUERCUS_CROWN_BOTTOM_FRACTION)
		crown_bottoms.append(trunk_height)
	var crown_limit := INF
	var crown_limit_height_fraction := 0.0
	var trunk_limit := INF
	var vertices_checked := 0
	var mesh: Mesh = parts[0].mesh
	for surface_index in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			vertices_checked += 1
			var fraction := clampf((vertex.y - bounds.position.y) / bounds.size.y, 0.0, 1.0)
			var weight := fraction * fraction
			if weight <= 0.0:
				continue
			var above_ground := (vertex.y + ground_offset) * scale
			for crown_bottom: float in crown_bottoms:
				if above_ground >= crown_bottom:
					var slack := minf(half_x - absf(vertex.x * scale - float(smallest.crown_offset_x)),
						half_z - absf(vertex.z * scale - float(smallest.crown_offset_z)))
					if slack / weight < crown_limit:
						crown_limit = slack / weight
						crown_limit_height_fraction = fraction
				else:
					trunk_limit = minf(trunk_limit, margin / weight)
	return {
		smallest_placed_height_m = height, scale = scale, wind_margin_m = margin,
		crown_bottom_heights_m = crown_bottoms, vertices_checked = vertices_checked,
		max_top_sway_crown_m = crown_limit, limiting_vertex_height_fraction = crown_limit_height_fraction,
		max_top_sway_trunk_band_m = trunk_limit, max_top_sway_m = minf(crown_limit, trunk_limit),
		runtime_limit_m = float(Library.TREE_WIND_LEAN_LIMITS_M.get(asset_id, 0.0)),
	}
