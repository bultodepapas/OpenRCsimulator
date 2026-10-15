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

func _lines(script: Script, triangles: PackedVector3Array) -> Array:
	var result := []
	for side in [-1.0,1.0]:
		for fraction in [.43,.83]:
			result.append(script.canopy_line(triangles,side,fraction))
	return result

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
	for workload in ["four_lines","kit_build"]:
		for pair in 6:
			var signatures := [[],[]]
			for variant in ([0,1] if (pair%2==0)!=reverse else [1,0]):
				var script: Script = reference if variant==0 else candidate
				var begin := Time.get_ticks_usec()
				if workload=="four_lines":
					var lines := _lines(script,triangles)
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
	print("Canopy exact line/kit geometry pairs: 12; synthetic cases: 256; valid=",valid)
	model.root.free()
	await process_frame
	await process_frame
	quit(0 if valid else 1)

func _synthetic() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var valid := true
	for case in 256:
		var triangles := PackedVector3Array()
		for index in 60:
			triangles.append(Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)))
		# Exact station boundaries, coplanar/degenerate edges and near-parallel edges.
		var station := lerpf(-.355,.045,float(case%17)/16.0)
		for offset in [0.0,1e-9,-1e-9,1e-7,-1e-7]:
			triangles.append_array(PackedVector3Array([Vector3(-1,0,station),Vector3(1,1,station+offset),Vector3(0,-1,station-offset)]))
		# Existing behavior ignores an incomplete final triangle.
		if case%2: triangles.append(Vector3.ZERO)
		valid = valid and var_to_bytes(_lines(reference,triangles))==var_to_bytes(_lines(candidate,triangles))
	valid = valid and var_to_bytes(_lines(reference,PackedVector3Array()))==var_to_bytes(_lines(candidate,PackedVector3Array()))
	return valid
