extends SceneTree
const FieldLoader = preload("res://data/field_loader.gd")
const SceneryLoader = preload("res://scenery/scenery_loader.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Spec = preload("res://spec.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
var reference: Script
var candidate: Script
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference = load(arg.trim_prefix("--reference="))
		if arg.begins_with("--candidate="): candidate = load(arg.trim_prefix("--candidate="))
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	ShaderClock.register()
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var data: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH,field).scenery
	var scenery: Node3D = Scenery.build(field,data,{audio=false,birds=false,theme="",quality="high"},Spec.ATMOSPHERE.duplicate(true))
	var population := scenery.get_node_or_null("Population") as Node3D
	var pilot := Vector2(float(field.pilot.east),-float(field.pilot.north))
	var cells: Array[MeshInstance3D] = []
	for node in scenery.get_children():
		if not node is MeshInstance3D or not str(node.name).begins_with("cell_"): continue
		var box: AABB = node.mesh.get_aabb()
		var center := box.get_center()
		if box.size.y >= 0.08 and Vector2(center.x,center.z).distance_to(pilot) <= reference.MAX_SCENERY_RANGE:
			cells.append(node)
	var owners: Dictionary = reference.population_cell_owners(cells,population,pilot)
	var rows: Array = []
	var valid := true
	var population_triangles := 0
	for cell in cells:
		for pair in 8:
			var signatures: Array = [[],[]]
			for variant in ([0,1] if pair%2==0 else [1,0]):
				var script: Script = reference if variant==0 else candidate
				var begin := Time.get_ticks_usec()
				var shape: Dictionary = script.collect_cell_shape(cell,population,pilot,script.MAX_SCENERY_RANGE,0.04,owners)
				var elapsed := Time.get_ticks_usec()-begin
				signatures[variant] = _signature(shape)
				if pair==0 and variant==0: population_triangles += int(shape.get("population_triangles",0))
				rows.append({cell=str(cell.name),pair=pair,variant=variant,usec=elapsed,triangles=shape.get("triangles",0),population_triangles=shape.get("population_triangles",0)})
			valid = valid and signatures[0]==signatures[1]
	valid = valid and population_triangles > 0 and _synthetic_parity()
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,cells=cells.size(),population_triangles=population_triangles,rows=rows},"\t"))
	print("cells=",cells.size()," population triangles=",population_triangles," exact shape parity=",valid)
	scenery.free()
	await process_frame
	await process_frame
	quit(0 if valid else 1)

func _signature(shape: Dictionary) -> Array:
	if shape.is_empty(): return []
	return [shape.bounds,shape.triangles,shape.get("population_placements",0),shape.get("population_elevated_placements",0),shape.get("population_triangles",0),
		var_to_bytes(shape.mesh.surface_get_arrays(0))]

func _synthetic_parity() -> bool:
	var cell := MeshInstance3D.new()
	cell.name = "cell_0_0"
	cell.mesh = BoxMesh.new()
	var population := Node3D.new()
	var human := MultiMeshInstance3D.new()
	population.add_child(human)
	human.set_meta("source_asset","standing")
	human.multimesh = MultiMesh.new()
	human.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	human.multimesh.instance_count = 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,.04,0),Vector3(1,.04,0),Vector3(0,.04,1),Vector3(0,.041,0),Vector3(1,.041,0),Vector3(0,.041,1)])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	human.multimesh.mesh = mesh
	var original := var_to_bytes(mesh.surface_get_arrays(0))
	human.set_meta("placements",[{transform=Transform3D.IDENTITY,foot_height=.5}])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var valid := true
	for index in 256:
		var pose := Transform3D.IDENTITY
		if index > 0:
			pose = Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(-.7,1.3,.9)),Vector3(rng.randf_range(-4,4),rng.randf_range(-.2,.2),rng.randf_range(-4,4)))
		cell.transform = pose if index%3==0 else Transform3D.IDENTITY
		population.transform = pose if index%4==0 else Transform3D.IDENTITY
		human.transform = pose if index%5==0 else Transform3D.IDENTITY
		human.visible = index%13!=12
		human.set_meta("instance_transforms",[pose])
		var a: Dictionary = reference.collect_cell_shape(cell,population,Vector2.ZERO,100.0,.04,{})
		var b: Dictionary = candidate.collect_cell_shape(cell,population,Vector2.ZERO,100.0,.04,{})
		var equal := _signature(a)==_signature(b)
		if not equal: print("synthetic mismatch ",index," bounds ",a.bounds," / ",b.bounds," triangles ",a.get("population_triangles")," / ",b.get("population_triangles"))
		valid = valid and equal
		if index==0:
			print("cutoff fixture triangles: ",b.population_triangles)
			valid = valid and int(b.population_triangles)==1
	valid = valid and var_to_bytes(mesh.surface_get_arrays(0))==original
	population.free()
	cell.free()
	print("256 transformed/cutoff/hidden population cases; exact and source unchanged: ",valid)
	return valid
