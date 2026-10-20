## LU-16-R2. Downloaded SRTM relief, reduced offline to four bounded mesh chunks.
## Art-directed visual backdrop at 1.6–8.6 km; no physical terrain or process callbacks.
extends RefCounted

const Atmosphere := preload("res://render/atmosphere.gd")
const HAZE_SHADER := preload("res://render/landscape_upgrade/ridge_haze.gdshader")
const RELIEF := preload("res://assets/landscape/mountains/relief.png")
const HABITAT := preload("res://assets/landscape/mountains/habitat.png")
const GRASS_ROCK := preload("res://assets/landscape/mountains/aerial_grass_rock_diff_1k.jpg")
const ROCKS := preload("res://assets/landscape/mountains/aerial_rocks_01_diff_1k.jpg")
const PROFILE_PATH := "res://data/fields/mountains.json"

const COLUMNS := 192
const ROWS := 72
const EAST_MIN := -6500.0
const EAST_MAX := 6500.0
const NORTH_MIN := 1600.0
const NORTH_MAX := 8600.0
static var _heights := PackedFloat32Array()

static func height_at(north: float, east: float) -> float:
	if _heights.is_empty() and not _load_profile():
		return 0.0
	var x := clampf((east - EAST_MIN) / (EAST_MAX - EAST_MIN) * COLUMNS, 0.0, COLUMNS)
	var y := clampf((north - NORTH_MIN) / (NORTH_MAX - NORTH_MIN) * ROWS, 0.0, ROWS)
	var col := mini(int(x), COLUMNS - 1)
	var row := mini(int(y), ROWS - 1)
	var a := row * (COLUMNS + 1) + col
	var b := a + COLUMNS + 1
	return lerpf(lerpf(_heights[a], _heights[a + 1], x - col),
		lerpf(_heights[b], _heights[b + 1], x - col), y - row)

static func _load_profile() -> bool:
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not profile is Dictionary or profile.get("format") != "openrc-visual-mountains v1" \
			or profile.get("columns") != COLUMNS or profile.get("rows") != ROWS \
			or profile.get("east_min_m") != EAST_MIN or profile.get("east_max_m") != EAST_MAX \
			or profile.get("north_min_m") != NORTH_MIN or profile.get("north_max_m") != NORTH_MAX \
			or not profile.get("heights_m") is Array \
			or profile.heights_m.size() != (COLUMNS + 1) * (ROWS + 1):
		push_error("Missing or incompatible visual mountain profile: " + PROFILE_PATH)
		return false
	var values := PackedFloat32Array()
	for value: Variant in profile.heights_m:
		if not (value is float or value is int) or not is_finite(float(value)) \
				or float(value) < 0.0 or float(value) > 1600.0:
			push_error("Invalid visual mountain elevation")
			return false
		values.append(float(value))
	_heights = values
	return true

static func build(lighting: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "DistantRidges"
	if _heights.is_empty() and not _load_profile():
		return root
	var material := ShaderMaterial.new()
	material.shader = HAZE_SHADER
	material.set_shader_parameter("relief", RELIEF)
	material.set_shader_parameter("habitat", HABITAT)
	material.set_shader_parameter("grass_rock", GRASS_ROCK)
	material.set_shader_parameter("rocks", ROCKS)
	Atmosphere.update_ground_material(material, lighting)
	root.set_meta("lighting_material", material)
	for chunk in 4:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
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
		for row in ROWS:
			for column in COLUMNS / 4:
				var a: int = row * (COLUMNS / 4 + 1) + column
				var b: int = a + COLUMNS / 4 + 1
				# Godot front faces are clockwise when viewed from above.
				indices.append_array(PackedInt32Array([a, b, a + 1, b, b + 1, a + 1]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
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
	root.set_meta("kind", "SRTM-derived, rotated/scaled visual backdrop; not surveyed field terrain")
	return root
