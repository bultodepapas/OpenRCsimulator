## Prepared, float64 FPV contact geometry for the same grounded assets as the nearby FPV meshes.
extends RefCounted

const World := preload("res://scenery/collision_world.gd")
const PROFILE_PATH := "res://data/fpv_tree_profiles.json"
const VERSION := "fpv-tree-contact-v2"
const GRID := 24


## Project one installed world for the quad. Generated trees own their geometry. Detach the ordinary
## solids and unprofiled crowns retained by the session from the caller's mutable inventory.
static func project(world: Dictionary) -> Dictionary:
	var solids: Array[Dictionary] = []
	var foliage: Array[Dictionary] = []
	var out := {ok = true, solids = solids, foliage = foliage, identity = str(world.get("identity", ""))}
	var source: Array = world.get("proxies", [])
	var profiles := {}
	var replaced := {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([VERSION, out.identity]))
	for proxy: Dictionary in source:
		if str(proxy.get("kind", "")) != "tree_foliage":
			continue
		if not proxy.has("fpv_tree"):
			foliage.append(proxy.duplicate(true))
			continue
		if profiles.is_empty():
			var content := FileAccess.get_file_as_string(PROFILE_PATH).replace("\r\n", "\n")
			var parsed: Variant = JSON.parse_string(content)
			if not parsed is Dictionary or int(parsed.get("grid", 0)) != GRID or not parsed.get("profiles") is Dictionary:
				return {ok = false, error = "Missing or invalid FPV tree contact profiles"}
			profiles = parsed.profiles
			for record: Dictionary in profiles.values():
				record.grid_bytes = Marshalls.base64_to_raw(str(record.get("leaf_area", "")))
				if record.grid_bytes.size() != GRID * GRID * GRID:
					return {ok = false, error = "Invalid FPV tree leaf density grid"}
			hash.update(content.sha256_text().to_ascii_buffer())
		var descriptor: Variant = proxy.fpv_tree
		if not descriptor is Array or descriptor.size() != 6 or not profiles.has(descriptor[0]):
			return {ok = false, error = "Invalid FPV tree placement for '%s'" % proxy.id}
		for i in range(1, 6):
			if typeof(descriptor[i]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(descriptor[i])):
				return {ok = false, error = "Invalid FPV tree transform for '%s'" % proxy.id}
		if descriptor[4] <= 0.0 or not str(proxy.id).ends_with(":crown"):
			return {ok = false, error = "Invalid FPV tree height or crown ID '%s'" % proxy.id}
		var trunk_id := str(proxy.id).trim_suffix(":crown") + ":trunk"
		replaced[trunk_id] = true
		_append_tree(solids, foliage, str(proxy.id), trunk_id, descriptor, profiles[descriptor[0]])
		hash.update(var_to_bytes([proxy.id, descriptor]))
	for proxy: Dictionary in source:
		var kind := str(proxy.get("kind", ""))
		if kind == "tree_foliage" or (kind == "tree_trunk" and replaced.has(proxy.get("id"))):
			continue
		solids.append(proxy.duplicate(true))
	if not foliage.is_empty():
		out.identity = hash.finish().hex_encode()
	return out


static func _append_tree(solids: Array[Dictionary], foliage: Array[Dictionary], crown_id: String,
		trunk_id: String, placement: Array, profile: Dictionary) -> void:
	var n := float(placement[1])
	var e := float(placement[2])
	var base := float(placement[3])
	var height := float(placement[4])
	var heading := float(placement[5])
	var angle := deg_to_rad(heading)
	var sn := sin(angle)
	var cs := cos(angle)
	for i in profile.stem.size():
		var section: Array = profile.stem[i] # x, z, bottom, top, bark radius, all in tree heights
		var pos := World.placement_point_rotated(n, e, sn, cs, height * section[0], height * section[1])
		var radius := float(section[4]) * height
		# Adjacent stem sections overlap their round ends. Keep the lowest one grounded.
		var low := maxf(height * section[2], radius)
		var high := maxf(low, height * section[3])
		World._add_capsule(solids, "%s:%02d" % [trunk_id, i], "tree_trunk", "trunk", "hard_terminal",
			pos[0], pos[1], base - 0.5 * (low + high), radius, 0.5 * (high - low))
	for i in profile.limbs.size():
		var limb: Array = profile.limbs[i] # bark-interior segment endpoints in normalized source x/up/z
		var start := World.placement_point_rotated(n, e, sn, cs, height * limb[0], height * limb[2])
		var end := World.placement_point_rotated(n, e, sn, cs, height * limb[3], height * limb[5])
		var down_delta := height * (float(limb[1]) - float(limb[4]))
		var axis := PackedFloat64Array([end[0] - start[0], end[1] - start[1], down_delta])
		var length := sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])
		for k in 3:
			axis[k] /= length
		var radius := float(limb[6]) * height
		World._add_capsule(solids, "%s:branch:%02d" % [trunk_id, i], "tree_trunk", "branch", "hard_terminal",
			0.5 * (start[0] + end[0]), 0.5 * (start[1] + end[1]), base - height * 0.5 * (float(limb[1]) + float(limb[4])),
			radius, 0.5 * length)
		var branch: Dictionary = solids.back()
		branch.axis_ned = axis
		var dn: float = absf(axis[0]) * branch.half_length + radius
		var de: float = absf(axis[1]) * branch.half_length + radius
		var dd: float = absf(axis[2]) * branch.half_length + radius
		branch.bounds_north_min = branch.north - dn
		branch.bounds_north_max = branch.north + dn
		branch.bounds_east_min = branch.east - de
		branch.bounds_east_max = branch.east + de
		branch.bounds_down_min = branch.down - dd
		branch.bounds_down_max = branch.down + dd
	var lo: Array = profile.bounds[0]
	var hi: Array = profile.bounds[1]
	var center := World.placement_point_rotated(n, e, sn, cs, height * 0.5 * (lo[0] + hi[0]), height * 0.5 * (lo[2] + hi[2]))
	World._add_box_at_down(foliage, crown_id, "tree_foliage", "crown", "soft_foliage_impulse",
		center[0], center[1], base - 0.5 * height, height * (hi[0] - lo[0]), height, height * (hi[2] - lo[2]), heading)
	foliage.back().grid_bytes = profile.grid_bytes # shared between all instances of this species


## Fraction of leaf engagement at a world point. A species grid stores source leaf area in each cell.
## Linear filtering avoids impulses when a small drone crosses a cell face. Bounds alone contribute no drag.
static func density_at(proxy: Dictionary, north: float, east: float, down: float) -> float:
	var dn: float = north - proxy.north
	var de: float = east - proxy.east
	var up: float = proxy.down - down
	if proxy.shape == "capsule":
		var beyond := maxf(absf(up) - float(proxy.half_length), 0.0)
		return maxf(0.0, 1.0 - (dn * dn + de * de + beyond * beyond) / (proxy.radius * proxy.radius))
	var x: float = (-dn * proxy.sin_heading + de * proxy.cos_heading) / proxy.half_x
	var z: float = (-dn * proxy.cos_heading - de * proxy.sin_heading) / proxy.half_z
	var y: float = up / proxy.half_down
	if absf(x) >= 1.0 or absf(y) >= 1.0 or absf(z) >= 1.0:
		return 0.0
	if not proxy.has("grid_bytes"):
		# A hedge runs along its long axis. A bush or an unprofiled crown tapers in all directions.
		if str(proxy.get("part", "")) == "hedge":
			return maxf(0.0, 1.0 - x*x - y*y) * minf(1.0, (1.0-absf(z)) * proxy.half_z / proxy.half_x)
		return maxf(0.0, 1.0 - x*x - y*y - z*z)
	var gx := (x + 1.0) * (0.5 * GRID) - 0.5
	var gy := (y + 1.0) * (0.5 * GRID) - 0.5
	var gz := (z + 1.0) * (0.5 * GRID) - 0.5
	var ix := floori(gx)
	var iy := floori(gy)
	var iz := floori(gz)
	var values: PackedByteArray = proxy.grid_bytes
	var density := 0.0
	for dy in 2:
		var j := iy + dy
		if j < 0 or j >= GRID:
			continue
		var wy := 1.0 - absf(gy - float(j))
		for dz in 2:
			var k := iz + dz
			if k < 0 or k >= GRID:
				continue
			var weight := wy * (1.0 - absf(gz - float(k)))
			var row := (j * GRID + k) * GRID
			if ix >= 0:
				density += weight * (1.0 - (gx - ix)) * values[row + ix]
			if ix + 1 < GRID:
				density += weight * (gx - ix) * values[row + ix + 1]
	return density / 255.0
