extends SceneTree

var output := ""
var reference_path := ""
var candidate_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		if arg.begins_with("--reference="): reference_path = arg.trim_prefix("--reference=")
		if arg.begins_with("--candidate="): candidate_path = arg.trim_prefix("--candidate=")
	_run.call_deferred()

func _run() -> void:
	var wrecks: Array = [load(reference_path).new(), load(candidate_path).new()]
	for wreck in wrecks:
		root.add_child(wreck)
		wreck.set_process(false)
		for index in 24:
			wreck._bodies[index].freeze = true
			wreck._bodies[index].collision_layer = 0
			wreck._bodies[index].collision_mask = 0
	var valid := true
	# Compare complete projection output across rotation, height, hiding, size and parent changes.
	for step in 100:
		for wreck in wrecks:
			wreck.position = Vector3(step * 0.01, 0.0, step * -0.02)
			for index in 24:
				var body: RigidBody3D = wreck._bodies[index]
				body.visible = (step + index) % 7 != 0
				body.transform = Transform3D(Basis.from_euler(Vector3(step*.01, index*.1, step*.02)), Vector3(index, step*.1, -index))
				wreck._shape_nodes[index].shape.size = Vector3(.1+step*.01, .2, .5)
				wreck._update_contact_shadow(index)
		valid = valid and _signature(wrecks[0]) == _signature(wrecks[1])
	var rows: Array = []
	for scenario in ["stationary", "moving", "hidden"]:
		for repeat in 16:
			for variant in ([0, 1] if repeat % 2 == 0 else [1, 0]):
				var wreck: Node3D = wrecks[variant]
				for index in 24:
					wreck._bodies[index].visible = scenario != "hidden"
					wreck._bodies[index].position = Vector3(index, 1.0, 0.0)
					wreck._update_contact_shadow(index)
				var started := Time.get_ticks_usec()
				for frame in 300:
					for index in 24:
						if scenario == "moving": wreck._bodies[index].position.x = index + frame * .001
						wreck._update_contact_shadow(index)
				rows.append({scenario=scenario, repeat=repeat, variant=variant, frames=300, usec=Time.get_ticks_usec()-started})
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({valid=valid, rows=rows}, "\t"))
	print("2400 shadow comparisons (visibility, transform, opacity), exact: ", valid)
	for wreck in wrecks: wreck.free()
	quit(0 if valid else 1)

func _signature(wreck: Node3D) -> Array:
	var result: Array = []
	for index in 24:
		var shadow: MeshInstance3D = wreck._shadows[index]
		result.append([shadow.visible, shadow.global_transform, wreck._shadow_materials[index].get_shader_parameter("opacity")])
	return result
