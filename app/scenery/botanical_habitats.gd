## LU-25 original deterministic planting recipes for the bundled rural field.
## Plants are soft decorative cover. Existing scenery remains the authority for tangible obstacles.
extends RefCounted

const Shapes := preload("res://scenery/botanical_meshes.gd")
const Palette := preload("res://scenery/palette.gd")
const Frames := preload("res://render/frames.gd")
const Grass := preload("res://render/near_grass.gd")
const Mask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const SHADER := preload("res://scenery/botanicals.gdshader")
const SEED := 221013


## A plant's identity/position never depends on the selected quality tier.
static func layout(field: Dictionary, scenery: Dictionary, quality: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if str(field.get("id", "")) != "default":
		return out
	var bundled_groups := {}
	for group: Dictionary in scenery.get("groups", []):
		bundled_groups[str(group.get("id", ""))] = true
	if not bundled_groups.has("shade-trees") or not bundled_groups.has("farm-barn"):
		return out
	var exclusions := exclusions_for(scenery)
	# Deliberate planting islands, not an even scatter. N/E centres and half extents in metres.
	var patches := [
		{zone = "club", n = -15.0, e = -3.0, rn = 0.35, re = 2.0, count = 55, mix = ["clover", "daisy", "spike", "rosette"]},
		{zone = "club", n = -15.0, e = 3.0, rn = 0.35, re = 2.0, count = 55, mix = ["buttercup", "daisy", "clover", "rosette"]},
		{zone = "club", n = -52.0, e = -23.0, rn = 3.0, re = 5.0, count = 65, mix = ["tussock", "oat", "rosette"]},
		{zone = "club", n = -54.0, e = 7.0, rn = 3.0, re = 6.0, count = 65, mix = ["tussock", "oat", "rosette"]},
		{zone = "club", n = -29.5, e = -54.0, rn = 3.0, re = 4.0, count = 65, mix = ["tussock", "rosette", "clover"]},
		{zone = "club", n = -30.5, e = 54.0, rn = 3.0, re = 4.0, count = 65, mix = ["tussock", "oat", "rosette"]},
		{zone = "edge", n = 25.5, e = -42.0, rn = 2.0, re = 13.0, count = 95, mix = ["tussock", "oat", "daisy"]},
		{zone = "edge", n = 25.5, e = 42.0, rn = 2.0, re = 13.0, count = 95, mix = ["tussock", "oat", "buttercup"]},
		{zone = "meadow", n = 58.0, e = 98.0, rn = 12.0, re = 17.0, count = 115, mix = ["tussock", "oat", "daisy", "buttercup", "cornflower"]},
		{zone = "meadow", n = 77.0, e = 116.0, rn = 14.0, re = 14.0, count = 115, mix = ["tussock", "oat", "clover", "cornflower", "poppy"]},
		{zone = "meadow", n = 47.0, e = 135.0, rn = 9.0, re = 12.0, count = 90, mix = ["tussock", "oat", "daisy", "buttercup"]},
	]
	var id := 0
	for patch: Dictionary in patches:
		for i in int(patch.count):
			id += 1
			var a := TAU * Palette.hash01(SEED, id, 1)
			var r := sqrt(Palette.hash01(SEED, id, 2))
			var n := float(field.pilot.north) + float(patch.n) + cos(a) * r * float(patch.rn)
			var e := float(field.pilot.east) + float(patch.e) + sin(a) * r * float(patch.re)
			if not Grass.accepts(n, e, field, exclusions) or not _quality_keeps(id, quality):
				continue
			var mix: Array = patch.mix
			# Adjacent plants favour one species, producing coherent drifts within each island.
			var species: String = mix[int(Palette.hash01(floori(n / 2.0), floori(e / 2.0), SEED) * mix.size()) % mix.size()]
			out.append({zone = patch.zone, species = species, n = n, e = e,
				scale = 0.72 + 0.36 * Palette.hash01(SEED, id, 3), seed = id})
	# Two modest plots beside the existing farm. Inter-row gaps and missing plants remain visible.
	for plot in 2:
		for row in 18:
			for column in 24:
				id += 1
				if Palette.hash01(SEED, id, 5) < 0.06 or not _quality_keeps(id, quality):
					continue
				var n := float(field.pilot.north) + 561.0 + float(column) * 0.78 + (Palette.hash01(SEED, id, 6) - 0.5) * 0.2
				var e := float(field.pilot.east) + 324.0 + float(plot) * 22.0 + float(row) * 0.88 + (Palette.hash01(SEED, id, 7) - 0.5) * 0.12
				if Grass.accepts(n, e, field, exclusions):
					out.append({zone = "farm", species = "wheat" if plot == 0 else "fieldbean", n = n, e = e,
					scale = 0.82 + 0.16 * Palette.hash01(SEED, id, 8), seed = id})
	return out


## Include the worn footpaths as well as the shared foundation/gravel footprints.
static func exclusions_for(scenery: Dictionary) -> Array[Dictionary]:
	var result := Mask.footprints(scenery)
	for group: Dictionary in scenery.get("groups", []):
		if group.get("type", "") != "track" or group.get("surface", "") != "worn":
			continue
		var points := PackedVector2Array()
		for point: Vector2 in group.points:
			points.append(point)
		for polygon: PackedVector2Array in Geometry2D.offset_polyline(points, float(group.width) * 0.5,
				Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
			result.append(Mask._record(str(group.id), "footpath", polygon))
	return result


static func _quality_keeps(id: int, quality: String) -> bool:
	var fraction := 0.25 if quality == "low" else 0.55 if quality == "balanced" else 1.0
	return Palette.hash01(SEED, id, 4242) < fraction


static func build(field: Dictionary, scenery: Dictionary, theme: String, quality: String) -> Node3D:
	var root := Node3D.new()
	root.name = "BotanicalHabitats"
	var plants := layout(field, scenery, quality)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var batches := {}
	var meshes := {}
	for plant: Dictionary in plants:
		var key: String = plant.zone + "_" + plant.species
		if not batches.has(key):
			batches[key] = []
		batches[key].append(plant)
	var keys: Array = batches.keys()
	keys.sort()
	var triangles := 0
	for key: String in keys:
		var list: Array = batches[key]
		var species: String = list[0].species
		if not meshes.has(species):
			meshes[species] = Shapes.mesh(species, theme, material)
		var mesh: ArrayMesh = meshes[species]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true # retain vertex COLOR in Compatibility
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		var bounds := AABB()
		for i in list.size():
			var p: Dictionary = list[i]
			var s: float = p.scale
			var basis := Basis(Vector3.UP, TAU * Palette.hash01(SEED, p.seed, 10)).scaled(Vector3(s, s, s))
			var xf := Transform3D(basis, Frames.ned_to_render([p.n, p.e, 0.0]))
			mm.set_instance_transform(i, xf)
			mm.set_instance_color(i, Color.WHITE)
			var tone := 0.84 + 0.26 * Palette.hash01(SEED, p.seed, 11)
			mm.set_instance_custom_data(i, Color(tone, tone * (0.98 + 0.04 * Palette.hash01(SEED, p.seed, 12)), tone * 0.96, 1.0))
			var occupied: AABB = xf * mesh.get_aabb()
			bounds = occupied if i == 0 else bounds.merge(occupied)
		var node := MultiMeshInstance3D.new()
		node.name = key
		node.multimesh = mm
		node.custom_aabb = bounds.grow(0.12)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# CPU placements make headless verification independent of dummy GPU-buffer readback.
		node.set_meta("plants", list)
		root.add_child(node)
		triangles += mesh.surface_get_array_len(0) / 3 * list.size()
	root.set_meta("plants", plants)
	root.set_meta("triangles", triangles)
	root.set_meta("batches", keys.size())
	if not plants.is_empty():
		var soil := _crop_ground(field, theme)
		root.add_child(soil)
		root.set_meta("triangles", triangles + soil.mesh.surface_get_array_len(0) / 3)
	return root


static func _crop_ground(field: Dictionary, theme: String) -> MeshInstance3D:
	var k := MeshKit.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	var pn: float = field.pilot.north
	var pe: float = field.pilot.east
	for plot in 2:
		var soil := Color("#86785c") if plot == 0 else Color("#6d7051")
		_ground_quad(k, pn + 560.4, pe + 323.4 + float(plot) * 22.0, 19.2, 16.2, soil)
		for row in 18:
			_ground_quad(k, pn + 560.8, pe + 323.9 + float(plot) * 22.0 + float(row) * 0.88,
				18.8, 0.22, soil.darkened(0.12))
	var node := MeshInstance3D.new()
	node.name = "CropGround"
	node.mesh = k.to_mesh(material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _ground_quad(k: MeshKit, n: float, e: float, length_n: float, length_e: float, colour: Color) -> void:
	k.quad(Vector3(e, 0.01, -n), Vector3(e + length_e, 0.01, -n),
		Vector3(e + length_e, 0.01, -n - length_n), Vector3(e, 0.01, -n - length_n), colour)
