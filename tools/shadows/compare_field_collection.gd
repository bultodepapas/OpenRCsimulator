## DT-11a: alternating exact comparisons of nearby static and population casters.
## Population includes static work; report the two kinds separately, never sum them.
extends SceneTree
const Field = preload("res://render/field.gd")
const Loader = preload("res://data/field_loader.gd")
const Spec = preload("res://spec.gd")
var Baseline: Script
var Candidate: Script
var reference_projected: Script
var candidate_projected: Script
func _initialize() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2: args[parts[0]] = parts[1]
	for required in ["reference", "reference-projected", "out"]:
		if not args.has(required):
			printerr("Missing --", required, "=<path>")
			quit(2)
			return
	Baseline = load(args.reference)
	Candidate = load(args.get("candidate", "res://render/field_projected_shadows.gd"))
	reference_projected = load(args["reference-projected"])
	candidate_projected = load(args.get("candidate-projected", "res://render/projected_shadow.gd"))
	if Baseline == null or Candidate == null or reference_projected == null or candidate_projected == null:
		quit(2)
		return
	var data: Dictionary = Loader.load_from().field
	var field: Node3D = Field.build(data, Spec.ATMOSPHERE.duplicate(true))
	var scenery: Node3D = field.get_node("Scenery")
	var population: Node3D = scenery.get_node("Population")
	var pilot := Vector2(float(data.pilot.east), -float(data.pilot.north))
	var cells: Array[MeshInstance3D] = []
	for node in scenery.get_children():
		if node is MeshInstance3D and str(node.name).begins_with("cell_"):
			var box: AABB = node.mesh.get_aabb()
			var centre := box.get_center()
			if box.size.y >= 0.08 and Vector2(centre.x, centre.z).distance_to(pilot) <= 100.0:
				cells.append(node)
	if cells.is_empty():
		printerr("No nearby caster cells found")
		field.free()
		quit(2)
		return
	var owners: Dictionary = Baseline.population_cell_owners(cells, population, pilot)
	var workloads: Array = []
	for cell in cells:
		workloads.append({kind="population", node=cell})
		workloads.append({kind="static", node=cell})
	var rows: Array = []
	var exact := true
	for pair in 10:
		var values: Array = [[], []]
		for variant: int in ([0,1] if pair % 2 == 0 else [1,0]):
			var script: Script = Baseline if variant == 0 else Candidate
			for workload in workloads:
				var cell: MeshInstance3D = workload.node
				var start := Time.get_ticks_usec()
				var shape: Dictionary
				if workload.kind == "population":
					shape = script.collect_cell_shape(cell, population, pilot, 100.0, 0.04, owners)
				else:
					var projected: Script = reference_projected if variant == 0 else candidate_projected
					shape = projected.collect(cell, 0.04)
				var elapsed := Time.get_ticks_usec() - start
				var arrays: Array = shape.mesh.surface_get_arrays(0) if not shape.is_empty() else []
				values[variant].append([var_to_bytes(arrays), var_to_bytes(shape.get("bounds")), shape.get("triangles"), shape.get("population_placements"), shape.get("population_elevated_placements"), shape.get("population_triangles")])
				rows.append({pair=pair, variant=variant, kind=workload.kind, cell=str(cell.name), usec=elapsed, population_triangles=shape.get("population_triangles",0)})
		exact = exact and values[0] == values[1]
		print("pair %d: %d workloads; exact=%s" % [pair,workloads.size(),str(values[0]==values[1])])
	var output: String = args.out
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write comparison: ", output)
		field.free()
		quit(2)
		return
	file.store_string(JSON.stringify({exact=exact,engine=Engine.get_version_info(),args=args,cells=cells.size(),rows=rows}, "\t") + "\n")
	field.free()
	print("shadow collection exact: ", exact)
	quit(0 if exact else 1)
