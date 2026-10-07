## SCENERY-PLAN SC-16: wildflower cushions. One small opaque mesh (green leaves, petal vertices marked with alpha 0),
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


## A 1 m cushion, ~21 triangles: a low six-sided leafy dome and five petal heads (alpha 0 marks petals for the shader).
## Thousands of them stand in the field, so the mesh is deliberately tiny (SC-16 budget).
static func cushion_mesh(theme: String) -> ArrayMesh:
	var k := MeshKit.new()
	var leaf := Palette.veg("stem", theme)
	var top := Vector3(0, 0.22, 0)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		var r0 := 0.5 * (0.85 + 0.3 * Palette.hash01(i, 1))
		var r1 := 0.5 * (0.85 + 0.3 * Palette.hash01((i + 1) % 6, 1))
		k.tri(Vector3(cos(a0) * r0, 0.0, sin(a0) * r0), top, Vector3(cos(a1) * r1, 0.0, sin(a1) * r1), leaf.lightened(0.04 * (i % 2)))
	var petal := Color(1, 1, 1, 0)
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var r := 0.14 + 0.18 * Palette.hash01(i, 3)
		var c := Vector3(cos(a) * r, 0.2 + 0.06 * Palette.hash01(i, 5), sin(a) * r)
		var p0 := c + Vector3(0.09, 0, 0)
		var p1 := c + Vector3(-0.045, 0, 0.078)
		var p2 := c + Vector3(-0.045, 0, -0.078)
		var apex := c + Vector3(0, 0.07, 0)
		k.tri(p0, apex, p1, petal)
		k.tri(p1, apex, p2, petal)
		k.tri(p2, apex, p0, petal)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	return k.to_mesh(mat)


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
