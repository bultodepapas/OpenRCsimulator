## LU-21: textured CC0 population. Shared imported meshes retain UVs, smooth normals,
## material boundaries and Godot's import-generated LODs. One MultiMesh per model part
## groups the compact club population; no actor process callbacks or runtime plugins.
extends RefCounted

const Palette = preload("res://scenery/palette.gd")
const HUMAN_SHADER: Shader = preload("res://scenery/population_person.gdshader")
const ASSETS := {
	"car_sedan": "sedan", "car_hatch": "hatch", "car_suv": "crossover", "car_sport": "hatch",
	"person_standing": "standing", "person_sitting": "sitting", "person_pilot": "pilot", "person_working": "working",
}
const DIR := "res://assets/scenery/population/"
## SC-HUM-07: outfit variants per pose (tools/scenery/population/outfits/). A person asset key is
## "<pose>/<outfit>" and loads people/<outfit>_<pose>.glb at natural scale. Placements take the
## variants in turn per pose and zone, so neighbours differ; without the files the LU-21 pose is used.
const HUMAN_POSES: Array[String] = ["standing", "sitting", "pilot", "working"]
const OUTFITS := {
	"pilot": ["pilot_polo", "veteran_cap"],
	"standing": ["casual_shirt", "woman_tee", "casual_jacket", "mechanic_overalls"],
	"sitting": ["woman_tee", "veteran_cap"],
	"working": ["mechanic_overalls", "casual_shirt", "woman_tee"],
}
const ZONE_OUTFITS := {
	"pits": {"standing": ["mechanic_overalls", "casual_shirt", "mechanic_overalls", "casual_jacket", "woman_tee"]},
}
const VARIANT_COUNTS := "__variant_counts"
## SC-HUM-02 merged people (tools/scenery/population/merge_people_atlas.py): UV2.x shading class.
const MERGED_MATERIAL := "Human.atlas"
const CLASS_EYES := 3
const CLASS_FLAT := 4
const SHIRT_TINTS: Array[Color] = [Color("#66829b"), Color("#a88966"), Color("#628071"), Color("#ad6b58"), Color("#b4b0a0"), Color("#606c7f")]
static var _cache: Dictionary = {}


static func handles(id: String) -> bool:
	return ASSETS.has(id)


static func queue(batches: Dictionary, id: String, xf: Transform3D, seed: int, size: Vector3, foot_height: float = 0.0,
		zone: String = "") -> void:
	var asset: String = ASSETS[id]
	if OUTFITS.has(asset):
		asset = _outfit_variant(batches, asset, zone)
	if not batches.has(asset):
		batches[asset] = []
	xf.origin.y += foot_height
	batches[asset].append({id = id, transform = xf, seed = seed, size = size, foot_height = foot_height, zone = zone})


## The next outfit for this pose and zone (round robin in placement order), or the LU-21 pose
## when that outfit's file is not shipped.
static func _outfit_variant(batches: Dictionary, pose: String, zone: String) -> String:
	var choices: Array = ZONE_OUTFITS.get(zone, {}).get(pose, OUTFITS[pose])
	if not batches.has(VARIANT_COUNTS):
		batches[VARIANT_COUNTS] = {}
	var counts: Dictionary = batches[VARIANT_COUNTS]
	var key := pose + "|" + zone
	var turn: int = counts.get(key, 0)
	counts[key] = turn + 1
	var asset := pose + "/" + str(choices[turn % choices.size()])
	return asset if ResourceLoader.exists(asset_path(asset)) else pose


## Every person asset key the field can use (outfit variants), for tests and captures.
static func human_assets() -> Array[String]:
	var keys: Array[String] = []
	for pose: String in HUMAN_POSES:
		var outfits: Array = OUTFITS[pose].duplicate()
		for zone: String in ZONE_OUTFITS:
			outfits.append_array(ZONE_OUTFITS[zone].get(pose, []))
		for outfit: Variant in outfits:
			var key := pose + "/" + str(outfit)
			if not keys.has(key):
				keys.append(key)
	return keys


## Queue one placement with an explicit asset key (captures and tests); no variant rotation.
static func queue_asset(batches: Dictionary, asset: String, id: String, xf: Transform3D, seed: int, size: Vector3) -> void:
	if not batches.has(asset):
		batches[asset] = []
	batches[asset].append({id = id, transform = xf, seed = seed, size = size, foot_height = 0.0, zone = ""})


## Pose kind of an asset key ("standing/woman_tee" → "standing"; cars return their own name).
static func pose_of(asset: String) -> String:
	return asset.get_slice("/", 0)


static func asset_path(asset: String) -> String:
	if "/" in asset:
		return DIR + "people/" + asset.get_slice("/", 1) + "_" + asset.get_slice("/", 0) + ".glb"
	return DIR + asset + ".glb"


static func build(batches: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Population"
	var instance_total := 0
	var triangle_total := 0
	var moving_total := 0
	# SC-HUM-03: one entry per person for PeopleGaze; nodes per asset receive its yaw/pitch writes.
	var people: Array[Dictionary] = []
	var people_nodes := {}
	for asset: String in batches:
		if asset == VARIANT_COUNTS:
			continue
		var source := _source(asset)
		if source.is_empty():
			continue
		var placements: Array = batches[asset]
		var pose := pose_of(asset)
		var human := pose in HUMAN_POSES
		# SC-HUM-07 outfits are authored at their natural size; LU-21 poses fit the prefab envelope.
		var natural := "/" in asset
		var bounds: AABB = source.bounds
		instance_total += placements.size()
		for part_index in source.parts.size():
			var part: Dictionary = source.parts[part_index]
			var mesh: Mesh = part.mesh
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh
			mm.instance_count = placements.size()
			var combined := AABB()
			var instance_transforms: Array[Transform3D] = []
			for i in placements.size():
				var p: Dictionary = placements[i]
				# Source vehicles are generic, not measured production vehicles. Keep the
				# field's documented gameplay envelope and collision geometry in agreement.
				var scale: Vector3 = p.size / bounds.size
				if natural:
					# Natural height, capped by the prefab's collision envelope (plan §4.5).
					var cap: float = minf(p.size.y / bounds.size.y, minf(p.size.x / bounds.size.x, p.size.z / bounds.size.z))
					scale = Vector3.ONE * minf(1.0, cap)
				elif human:
					# Preserve anatomical proportions. Height varies within the existing proxy.
					var uniform: float = minf(p.size.y / bounds.size.y, minf(p.size.x / bounds.size.x, p.size.z / bounds.size.z))
					scale = Vector3.ONE * uniform
				var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
				var fit := Transform3D(Basis.from_scale(scale), -center * scale)
				var xf: Transform3D = p.transform * fit * part.transform
				instance_transforms.append(xf)
				mm.set_instance_transform(i, xf)
				var tint: Color = Palette.pick(Palette.PAINTS, int(p.seed), 17) if not human else Palette.pick(SHIRT_TINTS, int(p.seed), 2)
				if human:
					tint.a = 0.5 # Head pitch encoding: 0.5 + pitch / PI (level head).
				mm.set_instance_color(i, tint)
				var moving := human and (pose == "pilot" or Palette.hash01(int(p.seed), 91) < 0.30)
				var custom := Color(Palette.hash01(int(p.seed), 77), 1.0 if moving else 0.0, Palette.hash01(int(p.seed), 4), 0.0)
				mm.set_instance_custom_data(i, custom)
				if part_index == 0 and moving:
					moving_total += 1
				if part_index == 0 and human and source.has("head"):
					var placement: Transform3D = p.transform
					people.append({asset = asset, index = i, seed = int(p.seed), id = str(p.id),
						role = _role(str(p.id), str(p.get("zone", ""))),
						pivot = placement * fit * (source.head.pivot as Vector3),
						basis = placement.basis.orthonormalized(), tint = tint, custom = custom})
				var box: AABB = xf * mesh.get_aabb()
				combined = box if i == 0 else combined.merge(box)
			var node := MultiMeshInstance3D.new()
			node.name = "%s_%d" % [asset.replace("/", "_"), part_index]
			node.multimesh = mm
			# People: room for the head and neck turning up to ±75° (SC-HUM-03) as well as the sway.
			node.custom_aabb = combined.grow(0.15 if human else 0.0)
			node.visibility_range_end = 1200.0
			node.visibility_range_end_margin = 40.0
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.set_meta("source_asset", pose)
			node.set_meta("asset_key", asset)
			node.set_meta("placements", placements)
			# Keep the CPU copy authoritative for collectors and tests. MultiMesh's
			# instance getter is an engine-side render resource and may return identity
			# in headless/dummy rendering backends.
			node.set_meta("instance_transforms", instance_transforms)
			node.set_meta("source_bounds", bounds)
			root.add_child(node)
			if human:
				if not people_nodes.has(asset):
					people_nodes[asset] = []
				people_nodes[asset].append(node)
			triangle_total += triangles(mesh) * placements.size()
	root.set_meta("instances", instance_total)
	root.set_meta("triangles", triangle_total)
	root.set_meta("moving_people", moving_total)
	root.set_meta("people", people)
	root.set_meta("people_nodes", people_nodes)
	return root


## Gaze role from the placement: flight-line pilots stay coupled to the aircraft.
static func _role(id: String, zone: String) -> String:
	if id == "person_pilot" or zone == "pilot_line":
		return "pilot"
	if id == "person_working":
		return "worker"
	if zone == "pits":
		return "pits"
	return "spectator"


static func triangles(mesh: Mesh) -> int:
	var total := 0
	# Imported ArrayMeshes expose counts without copying/decompressing all vertex
	# attributes. PrimitiveMesh still needs its general Mesh array fallback.
	if mesh is ArrayMesh:
		var array_mesh := mesh as ArrayMesh
		for surface in array_mesh.get_surface_count():
			var index_count := array_mesh.surface_get_array_index_len(surface)
			total += (index_count if index_count > 0 else array_mesh.surface_get_array_len(surface)) / 3
		return total
	for surface in mesh.get_surface_count():
		# Mesh array-length convenience methods belong to ArrayMesh and fail on
		# primitive sources such as QuadMesh. The surface arrays are available on
		# both, and indexed geometry must count indices rather than unique vertices.
		var arrays: Array = mesh.surface_get_arrays(surface)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
		var index_count := (index_data as PackedInt32Array).size() if index_data is PackedInt32Array else 0
		var vertex_count := (vertex_data as PackedVector3Array).size() if vertex_data is PackedVector3Array else 0
		total += (index_count if index_count > 0 else vertex_count) / 3
	return total


static func _source(asset: String) -> Dictionary:
	if _cache.has(asset):
		return _cache[asset]
	var packed := load(asset_path(asset)) as PackedScene
	if packed == null:
		push_error("LU21 missing population asset: " + asset)
		return {}
	var root := packed.instantiate()
	var parts: Array[Dictionary] = []
	_collect(root, Transform3D.IDENTITY, parts, asset)
	var bounds := AABB()
	for i in parts.size():
		var box: AABB = parts[i].transform * parts[i].mesh.get_aabb()
		bounds = box if i == 0 else bounds.merge(box)
	root.free()
	if parts.is_empty() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		push_error("LU21 empty population geometry: " + asset)
		return {}
	var result := {parts = parts, bounds = bounds}
	if pose_of(asset) in HUMAN_POSES:
		var head := head_rig(parts)
		if not head.is_empty():
			result.head = head
			for part: Dictionary in parts:
				_set_head_parameters(part, head)
	_cache[asset] = result
	return result


static func _collect(node: Node, parent_xf: Transform3D, parts: Array[Dictionary], asset: String) -> void:
	var human := pose_of(asset) in HUMAN_POSES
	var xf: Transform3D = parent_xf * node.transform if node is Node3D else parent_xf
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh.duplicate()
		for surface in mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original is StandardMaterial3D:
				var material: Material
				if human:
					material = _person_material(original, pose_of(asset))
				else:
					material = original.duplicate()
					material.vertex_color_use_as_albedo = "paint" in original.resource_name.to_lower()
					material.vertex_color_is_srgb = true
					if material.vertex_color_use_as_albedo:
						# Source paint maps are flat swatches; instance paint supplies the color.
						material.albedo_color = Color.WHITE
						material.albedo_texture = null
						material.metallic = 0.18
						material.roughness = 0.42
					elif "alloy" in original.resource_name.to_lower() or "chrome" in original.resource_name.to_lower():
						material.roughness = maxf(material.roughness, 0.38)
				mesh.surface_set_material(surface, material)
		parts.append({mesh = mesh, transform = xf, name = str(node.name)})
	for child: Node in node.get_children():
		_collect(child, xf, parts, asset)


static func _person_material(original: StandardMaterial3D, asset: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = HUMAN_SHADER
	material.resource_name = original.resource_name
	material.set_shader_parameter("base_color", original.albedo_color)
	material.set_shader_parameter("base_texture", original.albedo_texture)
	material.set_shader_parameter("has_texture", original.albedo_texture != null)
	material.set_shader_parameter("roughness_value", maxf(0.60, original.roughness))
	material.set_shader_parameter("normal_texture", original.normal_texture)
	material.set_shader_parameter("has_normal", original.normal_enabled and original.normal_texture != null)
	material.set_shader_parameter("normal_strength", original.normal_scale)
	material.set_shader_parameter("fabric", "casualsuit" in original.resource_name.to_lower())
	material.set_shader_parameter("skin", original.resource_name.ends_with(".body"))
	# SC-HUM-02: one atlas material per pose; UV2 carries the per-part shading class and roughness.
	material.set_shader_parameter("merged", original.resource_name == MERGED_MATERIAL)
	material.set_shader_parameter("shirt_start", 0.53 if asset == "sitting" else 0.90)
	return material


## SC-HUM-03: neck pivot and weight band from the posed mesh itself, so regenerated people need
## no authored head weights. The eye proxy gives the eye height; the cranium above it gives the
## yaw axis. Below the band and outside the radius (shoulders, hands, transmitter) nothing moves.
static func head_rig(parts: Array[Dictionary]) -> Dictionary:
	# Separate LU-21 parts are recognised by name; SC-HUM-02 merged poses by their UV2 class.
	var body := PackedVector3Array()
	var eye_low := INF
	var eye_high := -INF
	for part: Dictionary in parts:
		var name := str(part.name).to_lower()
		if "transmitter" in name:
			continue
		var xf: Transform3D = part.transform
		var mesh: Mesh = part.mesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var classes: Variant = arrays[Mesh.ARRAY_TEX_UV2]
			for index in vertices.size():
				var shading: int = int(round((classes as PackedVector2Array)[index].x)) if classes is PackedVector2Array else -1
				if shading == CLASS_FLAT:
					continue
				var v := xf * vertices[index]
				body.append(v)
				if "low-poly" in name or shading == CLASS_EYES:
					eye_low = minf(eye_low, v.y)
					eye_high = maxf(eye_high, v.y)
	if body.is_empty():
		return {}
	var top := -INF
	for v: Vector3 in body:
		top = maxf(top, v.y)
	var eye_y: float = (eye_low + eye_high) * 0.5 if is_finite(eye_low) else top - 0.12
	var sum := Vector2.ZERO
	var count := 0
	for v: Vector3 in body:
		if v.y > eye_y:
			sum += Vector2(v.x, v.z)
			count += 1
	if count == 0:
		return {}
	var axis := sum / float(count)
	return {pivot = Vector3(axis.x, eye_y - 0.07, axis.y), band = Vector2(eye_y - 0.15, eye_y - 0.06),
		radius = Vector2(0.13, 0.18), eye_y = eye_y}


## CPU copy of the shader's head weight, for tests and diagnostics.
static func head_weight(head: Dictionary, vertex: Vector3) -> float:
	var band: Vector2 = head.band
	var radius: Vector2 = head.radius
	var pivot: Vector3 = head.pivot
	var r := Vector2(vertex.x - pivot.x, vertex.z - pivot.z).length()
	return smoothstep(band.x, band.y, vertex.y) * (1.0 - smoothstep(radius.x, radius.y, r))


## CPU mirror of the shader's head rotation (pitch about X, then yaw about Y, around the pivot).
static func head_rotate(head: Dictionary, vertex: Vector3, yaw: float, pitch: float) -> Vector3:
	var w := head_weight(head, vertex)
	if w <= 0.0:
		return vertex
	var pivot: Vector3 = head.pivot
	var rotated := (vertex - pivot).rotated(Vector3.RIGHT, pitch * w).rotated(Vector3.UP, yaw * w)
	return pivot + rotated


static func _set_head_parameters(part: Dictionary, head: Dictionary) -> void:
	var mesh: Mesh = part.mesh
	# Shader VERTEX is part-local; the pivot is in asset space.
	var local_pivot: Vector3 = (part.transform as Transform3D).affine_inverse() * (head.pivot as Vector3)
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as ShaderMaterial
		if material == null or material.shader != HUMAN_SHADER:
			continue
		material.set_shader_parameter("head_enabled", true)
		material.set_shader_parameter("head_pivot", local_pivot)
		material.set_shader_parameter("head_band", head.band)
		material.set_shader_parameter("head_radius", head.radius)
