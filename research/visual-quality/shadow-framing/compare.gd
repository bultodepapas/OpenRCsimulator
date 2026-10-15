extends SceneTree
var reference: Script
var candidate: Script
var output: String
var reverse:=false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference=load(arg.trim_prefix("--reference="))
		if arg.begins_with("--candidate="): candidate=load(arg.trim_prefix("--candidate="))
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
		reverse=reverse or arg=="--reverse"
	_run.call_deferred()

func _snapshot(shadow: Node) -> PackedByteArray:
	var material: ShaderMaterial=shadow.receiver.material_override
	var values: Array=[shadow.receiver.visible,shadow.receiver.transform,shadow.viewport.render_target_update_mode,shadow._last_signature,shadow._last_request]
	for param: String in ["opacity","blur_uv"]: values.append(material.get_shader_parameter(param))
	for param: String in ["aircraft_basis","light_direction","frame_center","frame_size"]: values.append(shadow.mask_material.get_shader_parameter(param))
	return var_to_bytes(values)

func _run() -> void:
	var shadows: Array[Node]=[]
	var hosts: Array[Node3D]=[]
	var models: Array[Node3D]=[]
	var mesh:=BoxMesh.new()
	mesh.size=Vector3(3,.6,2)
	var shape: Dictionary={mesh=mesh,bounds=mesh.get_aabb(),triangles=12}
	for script: Script in [reference,candidate]:
		var host:=Node3D.new()
		root.add_child(host); hosts.append(host)
		var model:=Node3D.new()
		host.add_child(model); models.append(model)
		var shadow: Node=script.new()
		host.add_child(shadow)
		shadow.setup(model,shape,32,Viewport.MSAA_DISABLED)
		shadows.append(shadow)
	var valid:=true
	var pairs:=0
	for index: int in 1024:
		var stage: int=index%16
		var basis:=Basis.from_euler(Vector3(.1,.2,.3)*float(index%7))
		var direction:=Vector3(.3,1,-.2)
		if stage==4: direction=Vector3(-.5,.01,.4)
		var height: float=float(index%60)
		var box: AABB=shape.bounds
		if stage==5: box.size.x+=.001*float(index+1)
		for variant: int in 2:
			var model: Node3D=models[variant]
			model.transform=Transform3D(basis,Vector3(index*.1,height,-index*.2))
			model.visible=stage!=6
			hosts[variant].visible=stage!=7
			shadows[variant].bounds=box
			shadows[variant].refresh(height,direction,float(index%9)/10.0,stage!=8)
			# Repeated inputs test actual reuse after all invalidation combinations.
			shadows[variant].refresh(height,direction,float(index%9)/10.0,stage!=8)
		valid=valid and _snapshot(shadows[0])==_snapshot(shadows[1])
		pairs+=1
	# Simulate an already consumed UPDATE_ONCE; reveal must still schedule redraw.
	for variant: int in 2:
		hosts[variant].visible=true; models[variant].visible=true
		shadows[variant].refresh(3.0,Vector3.UP,.5,true)
		shadows[variant].viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		shadows[variant].refresh(3.0,Vector3.UP,.5,false)
		shadows[variant].refresh(3.0,Vector3.UP,.5,true)
	valid=valid and _snapshot(shadows[0])==_snapshot(shadows[1]) and shadows[1].viewport.render_target_update_mode==SubViewport.UPDATE_ONCE
	pairs+=1
	var rows: Array=[]
	for workload: String in ["steady","translation","rotation","light"]:
		for pair: int in 6:
			for variant: int in ([0,1] if (pair%2==0)!=reverse else [1,0]):
				var model: Node3D=models[variant]
				var shadow: Node=shadows[variant]
				shadow.bounds=shape.bounds
				model.transform=Transform3D.IDENTITY
				var begin:=Time.get_ticks_usec()
				for frame: int in 4000:
					var direction:=Vector3(.3,1,-.2)
					if workload=="translation": model.position=Vector3(frame*.01,3,-frame*.02)
					elif workload=="rotation": model.basis=Basis.from_euler(Vector3(0,float(frame)*.001,0))
					elif workload=="light": direction.x=float(frame)*.0001
					shadow.refresh(3.0,direction,.5,true)
				rows.append({workload=workload,pair=pair,variant=variant,usec_per_update=float(Time.get_ticks_usec()-begin)/4000.0})
			valid=valid and _snapshot(shadows[0])==_snapshot(shadows[1])
			pairs+=1
	for model: Node3D in models: model.free()
	for shadow: Node in shadows: shadow.refresh(3,Vector3.UP,.5,true)
	valid=valid and _snapshot(shadows[0])==_snapshot(shadows[1]) and not shadows[1].receiver.visible
	pairs+=1
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,exact_pairs=pairs,rows=rows},"\t"))
	print("Projected shadow: ",pairs," exact pairs; valid=",valid)
	for host: Node3D in hosts: host.free()
	await process_frame
	await process_frame
	quit(0 if valid else 1)
