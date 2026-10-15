extends SceneTree
const Model = preload("res://aircraft/hx700_model.gd")
const Exposure = preload("res://render/world/exposure.gd")
const Clock = preload("res://render/shader_clock.gd")
var reference: Script
var candidate: Script
var output := ""
var reverse := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference = load(arg.trim_prefix("--reference="))
		if arg.begins_with("--candidate="): candidate = load(arg.trim_prefix("--candidate="))
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		reverse = reverse or arg == "--reverse"
	_run.call_deferred()

func _geometry(node: Node) -> Array:
	var result := []
	for child in node.get_children():
		var item := [str(child.name)]
		if child is Node3D: item.append(child.transform)
		if child is MeshInstance3D:
			for surface in child.mesh.get_surface_count():
				item.append(var_to_bytes(child.mesh.surface_get_arrays(surface)))
		item.append(_geometry(child))
		result.append(item)
	return result

func _run() -> void:
	Exposure.register()
	Clock.register()
	var model: Dictionary = Model.build()
	var canopy := model.root.find_child("Carenado",true,false) as MeshInstance3D
	var triangles: PackedVector3Array = reference._triangles(model.root,canopy)
	var original := var_to_bytes(triangles)
	var rows := []
	var valid := not triangles.is_empty()
	for workload in ["geometry","kit_build"]:
		for pair in 6:
			var signatures := [[],[]]
			for variant in ([0,1] if (pair%2==0)!=reverse else [1,0]):
				var script: Script = reference if variant==0 else candidate
				var begin := Time.get_ticks_usec()
				if workload=="geometry":
					var lines: PackedVector3Array = script._triangles(model.root,canopy)
					rows.append({workload=workload,pair=pair,variant=variant,usec=Time.get_ticks_usec()-begin})
					signatures[variant] = [var_to_bytes(lines)]
				else:
					var kit: Node3D = script.new()
					kit.model = model
					kit._build()
					rows.append({workload=workload,pair=pair,variant=variant,usec=Time.get_ticks_usec()-begin})
					signatures[variant] = _geometry(kit)
					kit.free()
			valid = valid and signatures[0]==signatures[1]
	var synthetic := _synthetic()
	valid = valid and synthetic and var_to_bytes(triangles)==original
	var result := {valid=valid,triangles=triangles.size()/3,rows=rows,synthetic_cases=256}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("Canopy exact geometry/kit pairs: 12; synthetic cases: 256; valid=",valid)
	model.root.free()
	await process_frame
	await process_frame
	quit(0 if valid else 1)

func _synthetic() -> bool:
	var rng:=RandomNumberGenerator.new()
	rng.seed=20261015
	var valid:=true
	for case: int in 256:
		var body:=Node3D.new()
		var pivot:=Node3D.new()
		var node:=MeshInstance3D.new()
		body.add_child(pivot); pivot.add_child(node)
		body.position=Vector3(100,200,300)
		pivot.transform=Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(-2,.4,1.3)),Vector3(-.5,.2,3))
		node.transform=Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(.3,2,1)),Vector3(.7,-.9,.1))
		var mesh:=ArrayMesh.new()
		for surface: int in 2:
			var vertices:=PackedVector3Array()
			for point: int in 21: vertices.append(Vector3(rng.randf_range(-3,3),rng.randf_range(-3,3),rng.randf_range(-3,3)))
			var arrays: Array=[]
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices
			if surface==0:
				# Repeated, reversed and degenerate indices; an unreferenced vertex.
				arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,1,0,0,1,2,3,3,3,12,19,7])
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		node.mesh=mesh
		var before: Array=[var_to_bytes(mesh.surface_get_arrays(0)),var_to_bytes(mesh.surface_get_arrays(1))]
		var expected: PackedVector3Array=_scalar_triangles(body,node)
		var actual: PackedVector3Array=candidate._triangles(body,node)
		valid=valid and var_to_bytes(expected)==var_to_bytes(actual)
		actual[0]=Vector3(99,99,99)
		valid=valid and before==[var_to_bytes(mesh.surface_get_arrays(0)),var_to_bytes(mesh.surface_get_arrays(1))]
		valid=valid and var_to_bytes(expected)==var_to_bytes(candidate._triangles(body,node))
		# No persistent geometry cache: moved mounts must be reflected immediately.
		pivot.position.x+=.125
		valid=valid and var_to_bytes(_scalar_triangles(body,node))==var_to_bytes(candidate._triangles(body,node))
		body.free()
	return valid

func _scalar_triangles(body: Node3D,node: MeshInstance3D) -> PackedVector3Array:
	# Original per-element arithmetic, with an explicit null-index fallback:
	# Godot returns null for non-indexed ArrayMesh surfaces, which the old typed
	# assignment rejected before reaching its intended unindexed branch.
	var transform_value: Transform3D=reference.Relative.relative(body,node)
	var result:=PackedVector3Array()
	for surface: int in node.mesh.get_surface_count():
		var arrays: Array=node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if indices.is_empty():
			for vertex: Vector3 in vertices: result.append(transform_value*vertex)
		else:
			for index: int in indices: result.append(transform_value*vertices[index])
	return result

