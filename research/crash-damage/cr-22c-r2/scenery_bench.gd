extends SceneTree
const Flight = preload("res://main.gd")
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
	var flight := Flight.new()
	root.add_child(flight)
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	var world: Dictionary = flight.session.collision_world(true)
	var before := var_to_bytes(world)
	var scripts := [load(reference_path), load(candidate_path)]
	var rows: Array = []
	var valid := true
	for kind in ["vehicle", "building", "tree_trunk", "lamp", "parked_aircraft"]:
		var target: Dictionary = world.proxies.filter(func(p): return p.kind == kind)[0]
		var point := PackedFloat64Array([target.north, target.east, target.down])
		var reference_signature: Array = []
		for repeat in 12:
			for variant in ([0, 1] if repeat % 2 == 0 else [1, 0]):
				var started := Time.get_ticks_usec()
				var bodies: Node3D = scripts[variant].build_near(world, point)
				var elapsed := Time.get_ticks_usec() - started
				var signature := _signature(bodies)
				if reference_signature.is_empty(): reference_signature = signature
				valid = valid and signature == reference_signature
				rows.append({kind=kind, point=Array(point), repeat=repeat, variant=variant,
					usec=elapsed, bodies=bodies.get_child_count(), identical=signature == reference_signature})
				bodies.free()
	valid = valid and var_to_bytes(world) == before
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({valid=valid, world_identity=world.identity, proxies=world.proxies.size(), rows=rows}, "\t"))
	print("scenery builds: 120 paired samples; geometry/order/layers/material values and input unchanged: ", valid)
	flight.free()
	await process_frame
	quit(0 if valid else 1)

func _signature(bodies: Node3D) -> Array:
	var rows: Array = []
	for body: StaticBody3D in bodies.get_children():
		var shape: Shape3D = body.get_child(0).shape
		var size: Variant = shape.size if shape is BoxShape3D else Vector2(shape.radius, shape.height)
		rows.append([body.name, body.get_meta("obstacle_id"), body.transform, body.collision_layer,
			body.collision_mask, body.physics_material_override.friction, body.physics_material_override.bounce,
			shape.get_class(), size])
	return rows
