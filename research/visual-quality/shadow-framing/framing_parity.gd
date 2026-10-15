extends SceneTree
func _initialize() -> void:
	var reference: Script
	var candidate: Script
	var output: String
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference="): reference=load(arg.trim_prefix("--reference="))
		if arg.begins_with("--candidate="): candidate=load(arg.trim_prefix("--candidate="))
		if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
	var rng:=RandomNumberGenerator.new()
	rng.seed=20261015
	var valid:=true
	for index: int in 4096:
		var box:=AABB(Vector3(rng.randf_range(-10,10),rng.randf_range(-10,10),rng.randf_range(-10,10)),Vector3(rng.randf_range(-3,3),rng.randf_range(-3,3),rng.randf_range(-3,3)))
		var basis:=Basis.from_euler(Vector3(rng.randf(),rng.randf(),rng.randf())).scaled(Vector3(-2,.3,1.5))
		var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
		var blur: float=rng.randf_range(-.2,2)
		if index%16==0: direction.y=.05
		elif index%16==1: direction.y=0
		elif index%16==2: box=AABB()
		elif index%16==3: direction.x=NAN
		elif index%16==4: direction.y=INF
		elif index%16==5: blur=NAN
		valid=valid and var_to_bytes(reference.framing(box,basis,direction,blur))==var_to_bytes(candidate.framing(box,basis,direction,blur))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({valid=valid,cases=4096}))
	print("Framing formula: 4096 exact cases; valid=",valid)
	quit(0 if valid else 1)
