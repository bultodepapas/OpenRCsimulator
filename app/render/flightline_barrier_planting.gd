## L10c-R2: reuse downloaded CC0 plants in deterministic, bounded post-foot clusters.
extends RefCounted
const Plants = preload("res://scenery/imported_vegetation.gd")
const Palette = preload("res://scenery/palette.gd")
const MeshKit = preload("res://scenery/mesh_kit.gd")
const Soil = preload("res://render/flightline_barrier_soil.gdshader")
const Foliage = preload("res://render/flightline_barrier_foliage.gdshader")
const SEED := 101602
const ASSETS := ["grass_common_short", "clover_1", "grass_wispy_tall"]
const POST_HALF_WIDTH_M := 0.04


## A position-derived key keeps a post's variation independent of traversal order.
static func _post_key(post: Vector3) -> int:
	return int(round(post.x * 1000.0))


static func _is_gate_post(cue: Dictionary, post: Vector3) -> bool:
	return absf(absf(post.x) - float(cue.gap_width) * 0.5 - POST_HALF_WIDTH_M) < 0.001


static func _is_outer_post(cue: Dictionary, post: Vector3) -> bool:
	return absf(absf(post.x) - float(cue.width) * 0.5 + POST_HALF_WIDTH_M) < 0.001


static func _near_gate(cue: Dictionary, post: Vector3) -> bool:
	# On short custom fences the outer post still carries the richer end group.
	return not _is_outer_post(cue, post) and absf(post.x) - float(cue.gap_width) * 0.5 < 3.0


static func _plant_count(cue: Dictionary, post: Vector3, key: int) -> int:
	var choice := Palette.hash01(SEED, key, 7)
	if _is_gate_post(cue, post):
		return 1
	if _is_outer_post(cue, post):
		return 4 + int(choice > 0.5)
	if _near_gate(cue, post):
		return 1 + int(choice < 0.4)
	if choice < 0.12:
		return 0
	if choice < 0.26:
		return 1
	if choice < 0.50:
		return 2
	if choice < 0.72:
		return 3
	return 4 if choice < 0.90 else 5

static func layout(cue: Dictionary, posts: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in posts.size():
		var post := posts[i]
		var post_key := _post_key(post)
		var min_x: float = -cue.width * 0.5 if post.x < 0.0 else cue.gap_width * 0.5
		var max_x: float = -cue.gap_width * 0.5 if post.x < 0.0 else cue.width * 0.5
		var count := _plant_count(cue, post, post_key)
		var near_gate := _near_gate(cue, post)
		var direction := Palette.hash01(SEED, post_key, 4) * TAU
		var spread := lerpf(0.65, 2.4, Palette.hash01(SEED, post_key, 8))
		for j in count:
			var key := post_key * 7 + j
			var kind := 1 if j >= 2 else 0
			if j == 0 and not near_gate and (_is_outer_post(cue, post) or Palette.hash01(SEED, post_key, 13) > 0.5):
				kind = 2
			elif j == 1 and near_gate:
				kind = 1
			var asset_id: String = ASSETS[kind]
			var height := lerpf(0.07, 0.15, Palette.hash01(SEED, key, 1))
			if kind == 1:
				height = lerpf(0.045, 0.085, Palette.hash01(SEED, key, 2))
			elif kind == 2:
				height = lerpf(0.12, 0.20, Palette.hash01(SEED, key, 3))
			elif _is_gate_post(cue, post):
				height = lerpf(0.05, 0.075, Palette.hash01(SEED, key, 1))
			elif near_gate:
				height = lerpf(0.065, 0.105, Palette.hash01(SEED, key, 1))
			var angle := direction + (float(j) - float(count - 1) * 0.5) * spread
			var distance := lerpf(0.075, 0.17, Palette.hash01(SEED, key, 5))
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
		var key := _post_key(post)
		var gate := _is_gate_post(cue, post)
		# Small worn gate contacts and occasional exposed soil elsewhere.
		if not gate and Palette.hash01(SEED, key, 10) >= 0.42:
			continue
		var min_x: float = -cue.width * 0.5 if post.x < 0.0 else cue.gap_width * 0.5
		var max_x: float = -cue.gap_width * 0.5 if post.x < 0.0 else cue.width * 0.5
		var centre := Vector3(post.x, 0.013, post.z)
		var edge := PackedVector3Array()
		var radius := lerpf(0.10, 0.14, Palette.hash01(SEED, key, 14)) if gate else lerpf(0.13, 0.24, Palette.hash01(SEED, key, 14))
		var direction := Palette.hash01(SEED, key, 15) * TAU
		var aspect := lerpf(0.48, 0.85, Palette.hash01(SEED, key, 16))
		for j in 10:
			var angle := float(j) * TAU / 10.0
			var irregular := lerpf(0.84, 1.08, Palette.hash01(SEED, key, 20 + j))
			var offset := Vector2(cos(angle), sin(angle) * aspect).rotated(direction) * radius * irregular
			var p := centre + Vector3(offset.x, 0, offset.y)
			p.x = clampf(p.x, min_x, max_x)
			edge.append(p)
		for j in 10:
			var a := edge[j]
			var b := edge[(j + 1) % 10]
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
	material.set_shader_parameter("soil_color", load("res://assets/landscape/rc-ground/dirt-albedo.jpg"))
	var node := MeshInstance3D.new()
	node.name = "SoilCollars"
	node.mesh = kit.to_mesh(material)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
