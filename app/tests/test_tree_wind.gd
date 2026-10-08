# L15b: independent geometric envelope for any saturated wind direction.
# Real shader displacement and calm parity are checked by tools/trees/check_wind.py.
extends SceneTree
const Loader = preload("res://data/field_loader.gd")
const Trees = preload("res://render/treeline.gd")
const Assets = preload("res://render/tree_assets.gd")
var checks: int = 0
var failed: int = 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var loaded: Dictionary = Loader.load_from()
	check("field validates", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var data: Dictionary = loaded.field.objects[0]
	var grove: Node3D = Trees.build(data, loaded.field.pilot)
	var catalog: Dictionary = Assets.catalog().catalog
	var frames: Array[float] = []
	for entry: Dictionary in catalog.species:
		frames.append(float(entry.frame_size_m))
	var peak_displacement: float = 0.0
	for point: Array in data.positions:
		var shape: Dictionary = Trees.identity(point[0], point[1])
		var height: float = shape.height
		var frame: float = frames[shape.species]
		var node: MultiMeshInstance3D = grove.get_node("Sector%d" % Trees.sector(point[0], point[1]))
		var bounds: AABB = node.multimesh.custom_aabb
		var origin: Vector3 = Vector3(point[1], -point[2], -point[0])
		var yaw: Basis = Basis(Vector3.UP, shape.yaw)
		var vertices: PackedVector3Array = node.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var radius: float = sqrt(pow(frame * height * 0.5, 2.0) + pow((0.5 + frame * 0.5) * height, 2.0))
		# Independent chord bound: a rigid rotation through theta displaces any
		# vertex by <=2*r*sin(theta/2), for every azimuth and every phase.
		var bound: float = 2.0 * radius * sin(0.24 / height / 2.0)
		check("default cards stay below 0.30m", bound < 0.30)
		peak_displacement = maxf(peak_displacement, bound)
		for template: Vector3 in vertices:
			var ratio: float = frame / frames[0]
			var local: Vector3 = Vector3(template.x * ratio, (template.y - 0.5) * ratio + 0.5, template.z * ratio)
			local = yaw * local * height
			# Check all six extrema of the complete displacement sphere, not just
			# sampled wind directions or dummy-renderer instance transforms.
			for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
				check("wind envelope inside sector AABB", bounds.has_point(origin + local + direction * bound))
	check("same eight batches", grove.get_child_count() == 8)
	check("render-only, no process", not grove.is_processing())
	grove.free()
	print("L15b wind bounds: %d checks, %d failed; maximum chord %.6fm" % [checks, failed, peak_displacement])
	quit(1 if failed else 0)
