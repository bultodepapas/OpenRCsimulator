extends SceneTree
const Builder = preload("res://render/airplane.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
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
		reverse = reverse or arg=="--reverse"
	_run.call_deferred()

func _run() -> void:
	Clock.register()
	var rows := []
	var valid := true
	for id in Catalog.airplane_visual_families():
		var model: Dictionary = Builder.build(id)
		if model.is_empty():
			push_error("Cannot build "+id)
			quit(1)
			return
		for workload in ["geometry","kit_build"]:
			for pair in 6:
				var outputs := [PackedByteArray(),PackedByteArray()]
				for variant in ([0,1] if (pair%2==0)!=reverse else [1,0]):
					var script: Script = reference if variant==0 else candidate
					var begin := Time.get_ticks_usec()
					if workload=="geometry":
						var geometry := _geometry(script,model.root)
						var vertices: PackedVector3Array = geometry.points
						var triangles: PackedVector3Array = geometry.triangles
						rows.append({aircraft=id,workload=workload,pair=pair,variant=variant,usec=Time.get_ticks_usec()-begin,vertices=vertices.size(),triangle_vertices=triangles.size()})
						outputs[variant] = var_to_bytes([vertices,triangles])
					else:
						var kit: Node3D = script.attach(model.root)
						rows.append({aircraft=id,workload=workload,pair=pair,variant=variant,usec=Time.get_ticks_usec()-begin})
						outputs[variant] = var_to_bytes(snapshot(kit))
						model.root.remove_child(kit)
						kit.free()
				valid = valid and outputs[0]==outputs[1]
		model.root.free()
		print("Completed ",id," exact=",valid)
	valid = _synthetic() and valid
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,rows=rows,synthetic_cases=256},"\t"))
	await process_frame
	await process_frame
	quit(0 if valid else 1)

func _geometry(script: Script, model: Node3D) -> Dictionary:
	if script==candidate: return script._geometry_arrays(model)
	return {points=script.vertices(model),triangles=script.triangles(model)}

func _synthetic() -> bool:
	var model := Node3D.new()
	var parent := Node3D.new()
	model.add_child(parent)
	var indexed := MeshInstance3D.new()
	var plain := MeshInstance3D.new()
	var primitive := MeshInstance3D.new()
	var empty := MeshInstance3D.new()
	parent.add_child(indexed)
	parent.add_child(plain)
	parent.add_child(primitive)
	parent.add_child(empty)
	primitive.mesh = BoxMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,0),Vector3(1,.1,0),Vector3(0,0,1),Vector3(4,7,9)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2,0,1,1,0,2])
	indexed.mesh = ArrayMesh.new()
	indexed.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,0,0),Vector3(1,.1,0),Vector3(0,0,1)])
	arrays[Mesh.ARRAY_INDEX] = null
	plain.mesh = ArrayMesh.new()
	plain.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,0),Vector3(2,0,0)])
	plain.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	var original := var_to_bytes(indexed.mesh.surface_get_arrays(0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var valid := true
	for sample in 256:
		var pose := Transform3D(Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(-.7,1.3,.9)),Vector3(rng.randf_range(-4,4),rng.randf_range(-4,4),rng.randf_range(-4,4)))
		model.transform = pose
		parent.transform = pose if sample%2 else Transform3D.IDENTITY
		indexed.transform = pose
		plain.transform = pose if sample%3 else Transform3D.IDENTITY
		indexed.visible = sample%5!=0
		valid = valid and var_to_bytes(_geometry(reference,model))==var_to_bytes(_geometry(candidate,model))
		for method in [&"vertices",&"triangles"]:
			valid = valid and var_to_bytes(reference.call(method,model))==var_to_bytes(candidate.call(method,model))
	valid = valid and original==var_to_bytes(indexed.mesh.surface_get_arrays(0))
	model.free()
	print("256 nested-transform/indexed/unindexed/mixed-surface cases: ",valid)
	return valid

func snapshot(kit: Node3D) -> Array:
	var rows := []
	for child in kit.get_children():
		var row := {name = child.name, transform = child.transform, visible = child.visible, meta = {}}
		for key in child.get_meta_list():
			row.meta[key] = child.get_meta(key)
		if child is MeshInstance3D:
			row["surfaces"] = []
			row["shadow"] = child.cast_shadow
			row["margin"] = child.extra_cull_margin
			for surface in child.mesh.get_surface_count():
				var mat: ShaderMaterial = child.mesh.surface_get_material(surface)
				var params := {}
				for param in mat.shader.get_shader_uniform_list():
					params[param.name] = mat.get_shader_parameter(param.name)
				row.surfaces.append({arrays = child.mesh.surface_get_arrays(surface), shader = mat.shader.code, params = params})
		if child is SpotLight3D:
			row["light"] = [child.light_energy, child.spot_range, child.spot_angle, child.light_color, child.shadow_enabled]
		rows.append(row)
	return rows
