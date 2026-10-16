## L10c-R2: reuse downloaded CC0 plants in deterministic, bounded post-foot clusters.
extends RefCounted
const Plants = preload("res://scenery/imported_vegetation.gd")
const Palette = preload("res://scenery/palette.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Soil = preload("res://render/flightline_barrier_soil.gdshader")
const Foliage = preload("res://render/flightline_barrier_foliage.gdshader")
const SEED := 101602
const ASSETS := ["grass_common_short", "clover_1", "grass_wispy_tall"]

static func layout(cue: Dictionary, posts: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in posts.size():
		var post := posts[i]
		var min_x: float = -cue.width * 0.5 if post.x < 0.0 else cue.gap_width * 0.5
		var max_x: float = -cue.gap_width * 0.5 if post.x < 0.0 else cue.width * 0.5
		var count := 4 + i % 3
		for j in count:
			var key := i * 17 + j
			var kind := 1 if j >= 3 else 0
			if j < 2:
				kind = 2
			var asset_id: String = ASSETS[kind]
			var height := lerpf(0.09, 0.19, Palette.hash01(SEED, key, 1))
			if kind == 1:
				height = lerpf(0.045, 0.085, Palette.hash01(SEED, key, 2))
			elif kind == 2:
				height = lerpf(0.12, 0.21, Palette.hash01(SEED, key, 3))
			var angle := float(j) * 2.39996 + Palette.hash01(SEED, i, 4) * TAU
			var distance := lerpf(0.075, 0.18, Palette.hash01(SEED, key, 5))
			var yaw := Palette.hash01(SEED, key, 6) * TAU
			var origin := post + Vector3(cos(angle) * distance, 0, sin(angle) * distance)
			# Conservative source-box radius keeps every leaf outside the walking gap.
			var bounds: Dictionary = Plants.get_asset(asset_id).source_bounds_m
			var radius := Vector2(maxf(absf(bounds.min[0]), absf(bounds.max[0])), maxf(absf(bounds.min[2]), absf(bounds.max[2]))).length() * height / float(bounds.height)
			origin.x = clampf(origin.x, min_x + radius, max_x - radius)
			# No stems originate inside the post shoe.
			if absf(origin.x - post.x) < 0.065 and absf(origin.z) < 0.065:
				origin.z = 0.08 if origin.z >= 0.0 else -0.08
			var xf := Plants.fit_to_height(asset_id, height, Transform3D(Basis(Vector3.UP, yaw), origin))
			result.append({asset = asset_id, transform = xf, height = height, post = i, seed = SEED + key})
	return result

static func build(cue: Dictionary, posts: PackedVector3Array) -> Node3D:
	var batches := {}
	var records := layout(cue, posts)
	var triangles := 0
	for row in records:
		Plants.queue(batches, row.asset, row.transform, row.seed)
		triangles += int(Plants.get_asset(row.asset).source_triangles)
	var root := Plants.build(batches, false)
	root.name = "PostVegetation"
	root.set_meta("layout", records)
	root.set_meta("source_triangles", triangles)
	# Duplicate only materials; the source geometry/textures and other field plants stay intact.
	for node in root.get_children():
		if node is MultiMeshInstance3D:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mesh: Mesh = node.multimesh.mesh
			for s in mesh.get_surface_count():
				var source := mesh.surface_get_material(s) as StandardMaterial3D
				var material := ShaderMaterial.new()
				material.shader = Foliage
				material.set_shader_parameter("leaf_color", source.albedo_texture)
				var asset_id := str(node.name).split("_Part_")[0]
				material.set_shader_parameter("source_height", float(Plants.get_asset(asset_id).source_bounds_m.height))
				if asset_id == "clover_1":
					material.set_shader_parameter("leaf_tint", Color(0.42, 0.52, 0.24))
				mesh.surface_set_material(s, material)
	root.add_child(_soil(cue, posts))
	return root

static func _soil(cue: Dictionary, posts: PackedVector3Array) -> MeshInstance3D:
	var kit := MeshKit.new()
	for i in posts.size():
		var post := posts[i]
		var min_x: float = -cue.width * 0.5 if post.x < 0.0 else cue.gap_width * 0.5
		var max_x: float = -cue.gap_width * 0.5 if post.x < 0.0 else cue.width * 0.5
		var centre := Vector3(post.x, 0.013, post.z)
		var edge := PackedVector3Array()
		for j in 12:
			var angle := float(j) * TAU / 12.0
			var radius := lerpf(0.17, 0.29, Palette.hash01(SEED, i * 12 + j, 9))
			var p := centre + Vector3(cos(angle) * radius, 0, sin(angle) * radius * 0.8)
			p.x = clampf(p.x, min_x, max_x)
			edge.append(p)
		for j in 12:
			var a := edge[j]
			var b := edge[(j + 1) % 12]
			var inner_a := centre.lerp(a, 0.48)
			var inner_b := centre.lerp(b, 0.48)
			kit.tri(centre, inner_b, inner_a, Color.WHITE)
			var first := kit.verts.size()
			kit.quad(inner_a, inner_b, b, a, Color.WHITE)
			for v in range(first, kit.verts.size()):
				if kit.verts[v].is_equal_approx(a) or kit.verts[v].is_equal_approx(b):
					kit.cols[v] = Color(1, 1, 1, 0)
	var material := ShaderMaterial.new()
	material.shader = Soil
	material.set_shader_parameter("soil_color", preload("res://assets/landscape/rc-ground/dirt-albedo.jpg"))
	var node := MeshInstance3D.new()
	node.name = "SoilCollars"
	node.mesh = kit.to_mesh(material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
