## PBR roof skins fitted to the existing structural roof geometry. One small mesh per
## building keeps UV courses aligned to each eave, and follows scenery damage by id.
extends RefCounted

const Palette = preload("res://scenery/palette.gd")
const ROOF_SHADER: Shader = preload("res://scenery/building_roofs.gdshader")
const SLATE_DIFF: Texture2D = preload("res://assets/landscape/building-roofs/roof_slates_03_diff_1k.jpg")
const SLATE_NORMAL: Texture2D = preload("res://assets/landscape/building-roofs/roof_slates_03_nor_gl_1k.png")
const SLATE_ARM: Texture2D = preload("res://assets/landscape/building-roofs/roof_slates_03_arm_1k.jpg")
const CLAY_DIFF: Texture2D = preload("res://assets/landscape/building-roofs/clay_roof_tiles_diff_1k.jpg")
const CLAY_NORMAL: Texture2D = preload("res://assets/landscape/building-roofs/clay_roof_tiles_nor_gl_1k.png")
const CLAY_ARM: Texture2D = preload("res://assets/landscape/building-roofs/clay_roof_tiles_arm_1k.jpg")
const METAL_DIFF: Texture2D = preload("res://assets/landscape/pit-shelter/corrugated_iron_02_diff_2k.jpg")
const METAL_NORMAL: Texture2D = preload("res://assets/landscape/pit-shelter/corrugated_iron_02_nor_gl_2k.png")
const METAL_ARM: Texture2D = preload("res://assets/landscape/pit-shelter/corrugated_iron_02_arm_2k.jpg")
const OFFSET_M := 0.018
static var _materials: Dictionary = {}


static func create(prefab: String, xf: Transform3D, seed: int, damage_id: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	match prefab:
		"pavilion":
			result.append(_pavilion(xf, damage_id))
			result.append(_veranda(xf, damage_id))
		"shed":
			result.append(_gable(xf, damage_id, "shed_metal", 3.0, 2.4, 2.1, 0.75, 0.2))
		"barn":
			result.append(_barn(xf, damage_id))
		"farmhouse":
			result.append(_gable(xf, damage_id, "clay", 9.0, 7.0, 5.2, 2.0, 0.4))
		"village_house":
			var w := 7.0 + 2.0 * Palette.hash01(seed, 1)
			var d := 8.0 + 3.0 * Palette.hash01(seed, 2)
			var roof: Color = Palette.pick([Palette.col("roof_terracotta"), Palette.col("roof_slate"),
				Palette.col("roof_terracotta")], seed, 4)
			var eave := 5.2 if Palette.hash01(seed, 5) < 0.6 else 3.0
			result.append(_gable(xf, damage_id, "slate" if roof == Palette.col("roof_slate") else "clay",
				w, d, eave, 2.4, 0.3))
		"church":
			result.append(_gable(xf, damage_id, "slate", 8.0, 18.0, 7.0, 4.5, 0.3))
	return result


static func _material(kind: String) -> ShaderMaterial:
	if _materials.has(kind):
		return _materials[kind]
	var maps: Array[Texture2D]
	var tint := Color.WHITE
	var metallic := 0.0
	match kind:
		"slate":
			maps = [SLATE_DIFF, SLATE_NORMAL, SLATE_ARM]
			tint = Color(0.95, 0.96, 0.97)
		"clay":
			maps = [CLAY_DIFF, CLAY_NORMAL, CLAY_ARM]
			tint = Color(0.96, 0.94, 0.91)
		"shed_metal", "metal":
			maps = [METAL_DIFF, METAL_NORMAL, METAL_ARM]
			metallic = 0.78
			tint = Color(0.38, 0.52, 0.43) if kind == "shed_metal" else Color(0.72, 0.75, 0.76)
	var mat := ShaderMaterial.new()
	mat.shader = ROOF_SHADER
	mat.set_shader_parameter("albedo_map", maps[0])
	mat.set_shader_parameter("normal_map", maps[1])
	mat.set_shader_parameter("arm_map", maps[2])
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("metallic_scale", metallic)
	mat.set_shader_parameter("normal_strength", 0.38 if kind == "slate" else 0.67)
	mat.set_shader_parameter("roughness_floor", 0.78 if kind == "slate" else 0.74 if kind == "clay" else 0.6)
	_materials[kind] = mat
	return mat


static func _tool() -> SurfaceTool:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	return tool


static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (b - a).cross(c - a).normalized()
	for pair: Array in [[a, ua], [c, uc], [b, ub]]:
		tool.set_normal(n)
		tool.set_uv(pair[1])
		tool.add_vertex(pair[0])


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(tool, a, b, c, ua, ub, uc)
	_tri(tool, a, c, d, ua, uc, ud)


static func _node(tool: SurfaceTool, kind: String, xf: Transform3D, damage_id: String) -> MeshInstance3D:
	tool.set_material(_material(kind))
	var node := MeshInstance3D.new()
	node.name = "Roof_" + damage_id.replace(":", "_") + "_" + kind
	node.mesh = tool.commit()
	node.transform = xf
	node.set_meta("damage_motion_id", damage_id)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


static func _gable(xf: Transform3D, damage_id: String, kind: String,
		w: float, l: float, eave: float, rise: float, overhang: float) -> MeshInstance3D:
	var tool := _tool()
	var hw := w * 0.5 + overhang
	var hl := l * 0.5 + overhang
	var edge_y := eave - overhang * rise / (w * 0.5) + OFFSET_M
	var ridge_y := eave + rise + OFFSET_M
	var slope := Vector2(hw, ridge_y - edge_y).length()
	var tile := 2.7 if kind.ends_with("metal") else 3.0 if kind == "slate" else 4.0
	for side: float in [-1.0, 1.0]:
		var edge_back := Vector3(side * hw, edge_y, hl)
		var edge_front := Vector3(side * hw, edge_y, -hl)
		var ridge_front := Vector3(0, ridge_y, -hl)
		var ridge_back := Vector3(0, ridge_y, hl)
		if side < 0.0:
			_quad(tool, edge_front, edge_back, ridge_back, ridge_front,
				Vector2(-hl / tile, slope / tile), Vector2(hl / tile, slope / tile),
				Vector2(hl / tile, 0), Vector2(-hl / tile, 0))
		else:
			_quad(tool, edge_back, edge_front, ridge_front, ridge_back,
				Vector2(-hl / tile, slope / tile), Vector2(hl / tile, slope / tile),
				Vector2(hl / tile, 0), Vector2(-hl / tile, 0))
	return _node(tool, kind, xf, damage_id)


static func _pavilion(xf: Transform3D, damage_id: String) -> MeshInstance3D:
	var tool := _tool()
	var hw := 5.0
	var hl := 3.5
	var ridge_half := hw - hl * 0.98
	var y := 2.85 + OFFSET_M
	var top := 4.65 + OFFSET_M
	var a := Vector3(-hw, y, -hl)
	var b := Vector3(hw, y, -hl)
	var c := Vector3(hw, y, hl)
	var d := Vector3(-hw, y, hl)
	var r0 := Vector3(-ridge_half, top, 0)
	var r1 := Vector3(ridge_half, top, 0)
	var slope := Vector2(hl, top - y).length()
	var end_slope := Vector2(hw - ridge_half, top - y).length()
	# Slate courses follow each eave and are cut at the hip seams.
	_quad(tool, d, c, r1, r0, Vector2(-hw / 3.0, slope / 3.0),
		Vector2(hw / 3.0, slope / 3.0), Vector2(ridge_half / 3.0, 0), Vector2(-ridge_half / 3.0, 0))
	_quad(tool, b, a, r0, r1, Vector2(-hw / 3.0, slope / 3.0),
		Vector2(hw / 3.0, slope / 3.0), Vector2(ridge_half / 3.0, 0), Vector2(-ridge_half / 3.0, 0))
	_tri(tool, c, b, r1, Vector2(-hl / 3.0, end_slope / 3.0),
		Vector2(hl / 3.0, end_slope / 3.0), Vector2(0, 0))
	_tri(tool, a, d, r0, Vector2(-hl / 3.0, end_slope / 3.0),
		Vector2(hl / 3.0, end_slope / 3.0), Vector2(0, 0))
	return _node(tool, "slate", xf, damage_id)


static func _veranda(xf: Transform3D, damage_id: String) -> MeshInstance3D:
	var tool := _tool()
	var front := -6.2
	var back := -3.0
	var slope := Vector2(back - front, 2.95 - 2.62).length()
	_quad(tool, Vector3(-4.7, 2.62 + OFFSET_M, front),
		Vector3(-4.7, 2.95 + OFFSET_M, back),
		Vector3(4.7, 2.95 + OFFSET_M, back),
		Vector3(4.7, 2.62 + OFFSET_M, front),
		Vector2(-4.7 / 2.7, slope / 2.7), Vector2(-4.7 / 2.7, 0),
		Vector2(4.7 / 2.7, 0), Vector2(4.7 / 2.7, slope / 2.7))
	return _node(tool, "metal", xf, damage_id)


static func _barn(xf: Transform3D, damage_id: String) -> MeshInstance3D:
	var tool := _tool()
	var hl := 7.35
	var profile: Array[Vector3] = [Vector3(5.35, 3.35 + OFFSET_M, 0),
		Vector3(3.3, 5.8 + OFFSET_M, 0), Vector3(0, 7.3 + OFFSET_M, 0)]
	for side: float in [-1.0, 1.0]:
		var down := 0.0
		for i in 2:
			var high := profile[i + 1] * Vector3(side, 1, 1)
			var low := profile[i] * Vector3(side, 1, 1)
			var upper := down
			down += high.distance_to(low)
			var a := Vector3(low.x, low.y, -hl)
			var b := Vector3(low.x, low.y, hl)
			var c := Vector3(high.x, high.y, hl)
			var d := Vector3(high.x, high.y, -hl)
			if side < 0.0:
				_quad(tool, a, b, c, d, Vector2(-hl / 2.7, down / 2.7),
					Vector2(hl / 2.7, down / 2.7), Vector2(hl / 2.7, upper / 2.7),
					Vector2(-hl / 2.7, upper / 2.7))
			else:
				_quad(tool, b, a, d, c, Vector2(-hl / 2.7, down / 2.7),
					Vector2(hl / 2.7, down / 2.7), Vector2(hl / 2.7, upper / 2.7),
					Vector2(-hl / 2.7, upper / 2.7))
	return _node(tool, "metal", xf, damage_id)
