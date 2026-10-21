extends SceneTree
const Population = preload("res://scenery/population.gd")

func reference(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		var ni: int = indices.size() if indices is PackedInt32Array else 0
		var nv: int = vertices.size() if vertices is PackedVector3Array else 0
		total += (ni if ni > 0 else nv) / 3
	return total

func candidate(mesh: Mesh) -> int:
	if not mesh is ArrayMesh:
		return reference(mesh)
	var array_mesh := mesh as ArrayMesh
	var total := 0
	for surface in array_mesh.get_surface_count():
		var ni := array_mesh.surface_get_array_index_len(surface)
		total += (ni if ni > 0 else array_mesh.surface_get_array_len(surface)) / 3
	return total

func measure(meshes: Array[Mesh], fast: bool) -> float:
	var started := Time.get_ticks_usec()
	var sum := 0
	for repeat in 10:
		for mesh in meshes:
			sum += candidate(mesh) if fast else reference(mesh)
	assert(sum > 0)
	return float(Time.get_ticks_usec() - started) / 1000.0

func _initialize() -> void:
	preload("res://render/shader_clock.gd").register()
	var meshes: Array[Mesh] = []
	for asset: Dictionary in ImportedVegetation.catalog().assets:
		for part: Dictionary in ImportedVegetation.get_parts(asset.id):
			meshes.append(part.mesh)
	for asset: String in ["sedan", "hatch", "crossover", "standing", "sitting", "pilot"]:
		for part: Dictionary in Population._source(asset).parts:
			meshes.append(part.mesh)
	meshes.append(QuadMesh.new())
	meshes.append(BoxMesh.new())
	var total := 0
	for mesh in meshes:
		assert(reference(mesh) == candidate(mesh))
		assert(reference(mesh) == Population.triangles(mesh))
		assert(reference(mesh) == ImportedVegetation._triangle_count(mesh))
		total += reference(mesh)
	var old: Array[float] = []
	var new: Array[float] = []
	for round in 7:
		if round % 2 == 0:
			old.append(measure(meshes, false))
			new.append(measure(meshes, true))
		else:
			new.append(measure(meshes, true))
			old.append(measure(meshes, false))
	print(JSON.stringify({meshes=meshes.size(), triangles=total, loops=10, before_ms=old, after_ms=new}))
	quit()
