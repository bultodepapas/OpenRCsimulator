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
		var triangles: PackedVector3Array = reference.triangles(model.root)
		var half: float = reference.span_half(reference.vertices(model.root))
		for workload in ["wing_skins","kit_build"]:
			for pair in 6:
				var outputs := [PackedByteArray(),PackedByteArray()]
				for variant in ([0,1] if (pair%2==0)!=reverse else [1,0]):
					var script: Script = reference if variant==0 else candidate
					var begin := Time.get_ticks_usec()
					if workload=="wing_skins":
						var skins := _skins(script,triangles,half)
						rows.append({aircraft=id,workload=workload,pair=pair,variant=variant,usec=Time.get_ticks_usec()-begin,triangle_vertices=triangles.size()})
						outputs[variant] = var_to_bytes(skins)
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

func _skins(script: Script, triangles: PackedVector3Array, half: float) -> Dictionary:
	if script==candidate: return script.wing_skin_lines(triangles,half)
	return {lower=script.underwing_lines(triangles,half),upper=script.underwing_lines(triangles,half,true)}

func _synthetic() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var valid := true
	for sample in 256:
		var triangles := PackedVector3Array()
		for index in 90:
			triangles.append(Vector3(rng.randf_range(-2,2),rng.randf_range(-.2,.2),rng.randf_range(-1,1)))
		# Repeated equal-start segments, exact station edges, zero-area and steep faces.
		triangles.append_array(PackedVector3Array([Vector3(-1,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(-1,.1,0),Vector3(1,.1,0),Vector3(1,.1,1),Vector3(.35,0,0),Vector3(.35,1,0),Vector3(.35,0,1),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]))
		if sample%2: triangles.append(Vector3.ZERO)
		var half: float = [1.0,-1.0,0.0,.3684210526315789][sample%4]
		var original := var_to_bytes(triangles)
		var expected := _skins(reference,triangles,half)
		var result := _skins(candidate,triangles,half)
		valid = valid and var_to_bytes(expected)==var_to_bytes(result)
		valid = valid and var_to_bytes(candidate.underwing_lines(triangles,half))==var_to_bytes(expected.lower)
		valid = valid and var_to_bytes(candidate.underwing_lines(triangles,half,true))==var_to_bytes(expected.upper)
		valid = valid and original==var_to_bytes(triangles)
	valid = valid and var_to_bytes(_skins(reference,PackedVector3Array(),1))==var_to_bytes(_skins(candidate,PackedVector3Array(),1))
	print("256 grouped/single skin cases exact and input unchanged: ",valid)
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
