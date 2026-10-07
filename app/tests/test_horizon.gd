## L7 mesh topology, committed profile integrity and atmosphere presets. Visual-only: no simulation dependencies.
extends SceneTree

const Horizon = preload("res://render/horizon.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Ground = preload("res://render/ground.gd")
var failures: int = 0
var checks: int = 0


func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var profile: Dictionary = Horizon.profile()
	check("committed profile checksum and format accepted", not profile.is_empty())
	if profile.is_empty():
		quit(1)
		return
	var start: int = Time.get_ticks_usec()
	var mesh: ArrayMesh = Horizon.mesh()
	print("horizon build ms: ", (Time.get_ticks_usec() - start) / 1000.0)
	check("one surface/draw replaces rough plane", mesh.get_surface_count() == 1)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check("bounded mesh budget", vertices.size() < 65536 and indices.size() / 3 < 90000)
	check("original 40 km square footprint", mesh.get_aabb().position == Vector3(-20000.0, 0.0, -20000.0)
		and mesh.get_aabb().size.x == 40000.0 and mesh.get_aabb().size.z == 40000.0)
	var flat: bool = true
	var exact: bool = true
	var unit_normals: bool = true
	var edges: Dictionary = {}
	var winding: bool = true
	for i: int in vertices.size():
		var v: Vector3 = vertices[i]
		if Vector2(v.x, v.z).length() <= 1500.01 and v.y != 0.0:
			flat = false
		unit_normals = unit_normals and normals[i].y > 0.0 and absf(normals[i].length() - 1.0) < 1e-6
	for row: int in Horizon.ROWS:
		for col: int in Horizon.SAMPLES:
			var v: Vector3 = vertices[1 + (row + Horizon.INNER_RADII.size()) * Horizon.SAMPLES + col]
			exact = exact and v.y == float(profile.heights_q[row][col]) / 256.0
	for i: int in range(0, indices.size(), 3):
		var tri: Array[int] = [indices[i], indices[i + 1], indices[i + 2]]
		winding = winding and (vertices[tri[1]] - vertices[tri[0]]).cross(vertices[tri[2]] - vertices[tri[0]]).y < 0.0
		for j: int in 3:
			var a: int = mini(tri[j], tri[(j + 1) % 3])
			var b: int = maxi(tri[j], tri[(j + 1) % 3])
			var key: int = a * vertices.size() + b
			edges[key] = int(edges.get(key, 0)) + 1
	var manifold: bool = true
	var boundary_count: int = 0
	var last_ring: int = vertices.size() - Horizon.SAMPLES
	for key: int in edges:
		var count: int = edges[key]
		if count == 1:
			boundary_count += 1
			@warning_ignore("integer_division")
			var a: int = key / vertices.size()
			var b: int = key % vertices.size()
			manifold = manifold and a >= last_ring and b >= last_ring
		else:
			manifold = manifold and count == 2
	check("flat flight area through 1500 m", flat)
	check("every committed quantized height survives mesh readback exactly", exact)
	check("smooth upward unit normals", unit_normals)
	check("all triangles face up, no zero-area poles", winding)
	check("no cracks at radial joins or periodic seam; only outer border open", manifold and boundary_count == Horizon.SAMPLES)
	print("horizon vertices=", vertices.size(), " triangles=", indices.size() / 3, " boundary=", boundary_count)
	# Corrupt only a temporary user file; never mutate the repository profile.
	var scratch: String = "user://test_horizon_corrupt.json"
	profile.heights_q[12][17] += 1
	var file: FileAccess = FileAccess.open(scratch, FileAccess.WRITE)
	file.store_string(JSON.stringify(profile))
	file.close()
	check("changed payload rejected by SHA", Horizon.profile(scratch).is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	var original_visibility: float = Atmosphere.visibility_m
	for preset: String in Atmosphere.VISIBILITY_PRESETS:
		Atmosphere.visibility_m = Atmosphere.VISIBILITY_PRESETS[preset]
		var env: Environment = Atmosphere.environment()
		var ground: ShaderMaterial = Ground.grass_material()
		var sky: ShaderMaterial = env.sky.sky_material
		check("fog density shared at " + preset, absf(ground.get_shader_parameter("beta") - env.fog_density) < 1e-9)
		check("sky and ground haze shared at " + preset, ground.get_shader_parameter("haze_lin") == sky.get_shader_parameter("haze_lin")
			and ground.get_shader_parameter("sun_lin") == sky.get_shader_parameter("sun_lin"))
		check("Koschmieder density at " + preset, absf(Atmosphere.beta() - 3.912 / Atmosphere.visibility_m) < 1e-12)
	Atmosphere.visibility_m = original_visibility
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
