## SCENERY-PLAN SC-20 (optional, `--scenery_birds=on`): a flock of 12 small "V" birds on an analytic path ≥ 300 m from
## the pilot, low over the treeline (a 1 m bird at 150 m is as large on screen as the airplane at 225 m: report 02).
extends RefCounted

const Palette = preload("res://scenery/palette.gd")
const Frames = preload("res://render/frames.gd")
const SHADER: Shader = preload("res://scenery/birds.gdshader")
const COUNT := 12
const CENTRE_NED := [420.0, -260.0] # NE of nothing in particular: over the treeline, away from the sun (az 225°)
const ALTITUDE_M := 32.0


static func bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body along +Z (flight direction), wings to ±X, 0.9 m span
	var pts := [Vector3(0, 0, 0.2), Vector3(-0.45, 0.05, -0.05), Vector3(0, 0, -0.15), Vector3(0.45, 0.05, -0.05)]
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for i: int in tri:
			st.set_normal(Vector3.UP)
			st.add_vertex(pts[i])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mesh.surface_set_material(0, mat)
	return mesh


static func flock(_pilot: Vector2) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true # see flowers.gd: keeps vertex COLOR intact in Compatibility
	mm.mesh = bird_mesh()
	mm.instance_count = COUNT
	for i in COUNT:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, Color.WHITE)
		var off := Vector3((Palette.hash01(i, 1) - 0.5) * 18.0, (Palette.hash01(i, 2) - 0.5) * 5.0, (Palette.hash01(i, 3) - 0.5) * 18.0)
		mm.set_instance_custom_data(i, Color(off.x, off.y, off.z, Palette.hash01(i, 4)))
	var node := MultiMeshInstance3D.new()
	node.name = "Birds"
	node.multimesh = mm
	node.position = Frames.ned_to_render([CENTRE_NED[0], CENTRE_NED[1], -ALTITUDE_M])
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-170, -20, -110), Vector3(340, 40, 220))
	return node
