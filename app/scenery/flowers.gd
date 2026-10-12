## SCENERY-PLAN SC-16: wildflower clusters. One small opaque mesh (green stems/leaves, petal vertices marked with alpha 0),
## one MultiMesh per 60 m chunk, the species colour per instance in INSTANCE_CUSTOM (flowers.gdshader). Cushions are
## sized ≥ d/386 m by the placement tool so they cover at least 2 px where they stand (scenery report 02).
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const Frames = preload("res://render/frames.gd")
const SHADER: Shader = preload("res://scenery/flowers.gdshader")
const CHUNK_M := 60.0
## Species mix of a temperate meadow edge (report 02): buttercup and daisy dominate, then clover, poppy, cornflower.
const MIX: Array[String] = ["buttercup", "buttercup", "buttercup", "daisy", "daisy", "daisy", "clover", "clover", "poppy", "cornflower", "campion"]


## A sub-metre plant, 24 triangles: three rising stems, three two-triangle leaf blades and three compact four-petal heads.
## Thousands share this mesh, so the increase stays within the whole-landscape triangle budget.
static func cushion_mesh(theme: String) -> ArrayMesh:
	var k := MeshKit.new()
	var stem := Palette.veg("stem", theme)
	var leaf := Palette.veg("leaf", theme)
	var leaf_light := Palette.veg("leaf_light", theme)
	var petal := Color(1, 1, 1, 0)
	var pollen := Color("#d7b64a")
	var bases: Array[Vector3] = [Vector3(-0.13, 0.02, 0.04), Vector3(0.13, 0.02, -0.09), Vector3(0.02, 0.02, 0.15)]
	var heads: Array[Vector3] = [Vector3(-0.17, 0.31, 0.04), Vector3(0.14, 0.42, -0.10), Vector3(0.03, 0.36, 0.18)]
	for i in 3:
		var base: Vector3 = bases[i]
		var head: Vector3 = heads[i]
		var rise := head - base
		var azimuth := atan2(rise.z, rise.x)
		var side := Vector3(-sin(azimuth), 0.0, cos(azimuth)) * 0.012
		# One slim tapered face per stem keeps the plant legible from a low camera without tube geometry.
		_oriented_triangle(k, base - side, head - Vector3(0.0, 0.035, 0.0), base + side,
			stem, (Vector3.UP + rise.normalized() * 0.16).normalized())
		# A small pair of narrow leaves branches from each stem; their pitched faces catch overhead views.
		var attach := base.lerp(head, 0.42)
		var leaf_angle := azimuth + (0.90 if i % 2 == 0 else -0.90)
		var leaf_dir := Vector3(cos(leaf_angle), 0.0, sin(leaf_angle))
		var tip := attach + leaf_dir * 0.18 + Vector3(0.0, 0.095, 0.0)
		var leaf_side := Vector3(-leaf_dir.z, 0.0, leaf_dir.x) * 0.024
		var p0 := attach - leaf_side * 0.58
		var p1 := tip - leaf_side * 0.16
		var p2 := tip + leaf_side * 0.16
		var p3 := attach + leaf_side * 0.58
		var leaf_col := leaf.lerp(leaf_light, 0.18 + 0.12 * float(i % 2))
		_oriented_quad(k, p0, p1, p2, p3, leaf_col, (Vector3.UP + leaf_dir * 0.24).normalized())
	for i in 3:
		var center: Vector3 = heads[i]
		var phase := 0.23 * float(i)
		for petal_index in 4:
			var a := TAU * float(petal_index) / 4.0 + phase
			var inner_a := a - 0.45
			var inner_b := a + 0.45
			var root_a := center + Vector3(cos(inner_a) * 0.038, 0.002, sin(inner_a) * 0.038)
			var tip := center + Vector3(cos(a) * 0.135, 0.012, sin(a) * 0.135)
			var root_b := center + Vector3(cos(inner_b) * 0.038, 0.002, sin(inner_b) * 0.038)
			_oriented_triangle(k, root_a, tip, root_b, petal, Vector3.UP)
		var pollen_a := center + Vector3(0.024, 0.018, 0.0)
		var pollen_b := center + Vector3(-0.012, 0.018, 0.021)
		var pollen_c := center + Vector3(-0.012, 0.018, -0.021)
		_oriented_triangle(k, pollen_a, pollen_b, pollen_c, pollen, Vector3.UP)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	return k.to_mesh(mat)


static func _oriented_triangle(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, colour: Color, front: Vector3) -> void:
	if (b - a).cross(c - a).dot(front) < 0.0:
		k.tri(a, c, b, colour)
	else:
		k.tri(a, b, c, colour)


static func _oriented_quad(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		colour: Color, front: Vector3) -> void:
	if (b - a).cross(c - a).dot(front) < 0.0:
		k.quad(a, d, c, b, colour)
	else:
		k.quad(a, b, c, d, colour)


## Builds MultiMesh nodes for NED positions [north, east, size]. Returns the nodes (one per chunk).
static func build(positions: Array, theme: String, keep: Callable) -> Array[MultiMeshInstance3D]:
	var mesh := cushion_mesh(theme)
	var chunks := {}
	var i := 0
	for p: Vector3 in positions:
		i += 1
		if not keep.call(i):
			continue
		var key := Vector2i(floori(p.x / CHUNK_M), floori(p.y / CHUNK_M))
		if not chunks.has(key):
			chunks[key] = []
		(chunks[key] as Array).append([p, i])
	var out: Array[MultiMeshInstance3D] = []
	var keys := chunks.keys()
	keys.sort()
	for key: Vector2i in keys:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		# Compatibility 4.7.2: without per-instance colours the vertex COLOR reaches the shader with alpha 0 (measured:
		# the leaves took the petal colour). Enabling them, all white, keeps the vertex colour intact.
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			var p: Vector3 = list[j][0]
			var id: int = list[j][1]
			var pos := Frames.ned_to_render([p.x, p.y, 0.0])
			var yaw := TAU * Palette.hash01(id, 1)
			var s := p.z * (0.85 + 0.3 * Palette.hash01(id, 2))
			mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * (0.8 + 0.4 * Palette.hash01(id, 4)), s)), pos))
			var species: String = MIX[int(Palette.hash01(int(p.x * 3.0), int(p.y * 3.0), 7) * MIX.size()) % MIX.size()]
			var c: Color = Palette.vegetation(Palette.FLOWERS[species], theme) if theme == "autumn" else Palette.FLOWERS[species]
			mm.set_instance_custom_data(j, c.srgb_to_linear())
			mm.set_instance_color(j, Color.WHITE)
		var node := MultiMeshInstance3D.new()
		node.name = "flowers_%d_%d" % [key.x, key.y]
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = mm.get_aabb().grow(0.2) # sway bounds (VQ §10)
		out.append(node)
	return out
