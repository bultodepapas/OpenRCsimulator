## LU-01. Original synthetic rural foothills: four bounded mesh chunks, no textures/process callbacks.
## Visual backdrop at 3.5–10 km. Terrain contact in the flying field remains the GP sampler.
extends RefCounted

const Atmosphere := preload("res://render/atmosphere.gd")
const HAZE_SHADER := preload("res://render/landscape_upgrade/ridge_haze.gdshader")

const COLUMNS := 128
const ROWS := 48
const EAST_MIN := -9500.0
const EAST_MAX := 9500.0
const NORTH_MIN := 3500.0
const NORTH_MAX := 10500.0

static func height_at(north: float, east: float) -> float:
	var u := clampf((east - EAST_MIN) / (EAST_MAX - EAST_MIN), 0.0, 1.0)
	var v := clampf((north - NORTH_MIN) / (NORTH_MAX - NORTH_MIN), 0.0, 1.0)
	var edge := pow(sin(u * PI), 0.8) * pow(sin(v * PI), 1.3)
	var spine := north - (6500.0 + 430.0 * sin(east * 0.0007) + 260.0 * sin(east * 0.0017))
	var ridge := exp(-pow(spine / 1600.0, 2.0))
	var peaks := 410.0 + 180.0 * sin(east * 0.0008 + 0.7) + 100.0 * sin(east * 0.0019)
	var gullies := 0.78 + 0.14 * sin(east * 0.004 + north * 0.0012) + 0.08 * sin(east * 0.009 - north * 0.004)
	return maxf(0.0, edge * (90.0 + peaks * ridge * gullies))

static func build(lighting: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "DistantRidges"
	var material := ShaderMaterial.new()
	material.shader = HAZE_SHADER
	Atmosphere.update_ground_material(material, lighting)
	root.set_meta("lighting_material", material)
	for chunk in 4:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		for row in ROWS + 1:
			var north := lerpf(NORTH_MIN, NORTH_MAX, float(row) / ROWS)
			for column in COLUMNS / 4 + 1:
				var east := lerpf(EAST_MIN, EAST_MAX, float(chunk * (COLUMNS / 4) + column) / COLUMNS)
				var h := height_at(north, east)
				var dn := (height_at(north + 5.0, east) - height_at(north - 5.0, east)) / 10.0
				var de := (height_at(north, east + 5.0) - height_at(north, east - 5.0)) / 10.0
				vertices.append(Vector3(east, h + 0.02, -north))
				normals.append(Vector3(-de, 1.0, dn).normalized())
				var rock := smoothstep(0.12, 0.28, sqrt(dn * dn + de * de)) * smoothstep(160.0, 420.0, h)
				var col := Color("#526147").lerp(Color("#77766b"), rock)
				var variation := 0.93 + 0.07 * sin(east * 0.007 + north * 0.011)
				colors.append(Color(col.r * variation, col.g * variation, col.b * variation))
		for row in ROWS:
			for column in COLUMNS / 4:
				var a: int = row * (COLUMNS / 4 + 1) + column
				var b: int = a + COLUMNS / 4 + 1
				indices.append_array(PackedInt32Array([a, a + 1, b, b, a + 1, b + 1]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.name = "Ridge%d" % chunk
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	root.set_meta("triangles", COLUMNS * ROWS * 2)
	root.set_meta("kind", "estimated: original synthetic visual backdrop; not surveyed terrain")
	return root
