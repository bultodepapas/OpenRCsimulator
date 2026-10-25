# GP-07a hull coverage, step 1: dump the convex hull of every visible mesh part of an airplane's rendered model in body
# FRD about the CG (the frame of AircraftData crash_hull and landing-gear contacts), plus those physics contact points.
# hull_coverage.py sweeps ground directions over this dump and reports how deep the drawn airframe can sink into flat
# ground before any physics contact touches. Mesh parts are tagged with their node path so the report names them.
# Run: godot --headless --path app --script "$PWD/research/ground-physics/gp07/hull_coverage_dump.gd" -- \
#        --aircraft=jensen-das-ugly-stik-60 --out=tmp/gp07/stik-dump.json
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Airplane := preload("res://render/airplane.gd")


func _initialize() -> void:
	var aircraft_id := Airplane.STIK_ID
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft_id = arg.trim_prefix("--aircraft=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var entry: Dictionary = {}
	for candidate: Dictionary in Catalog.airplane_flyable_entries():
		if str(candidate.id) == aircraft_id:
			entry = candidate
	if entry.is_empty() or out_path.is_empty():
		printerr("usage: hull_coverage_dump.gd -- --aircraft=<catalog id> --out=<file.json>")
		quit(2)
		return
	var loaded: Dictionary = AircraftData.load_file(str(entry.data))
	if not loaded.ok:
		printerr("data refused: %s" % str(loaded.errors))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var visual: Dictionary = Airplane.build(aircraft_id)
	if visual.is_empty() or not (visual.get("root") is Node3D):
		printerr("visual model did not build")
		quit(1)
		return
	var root: Node3D = visual.root
	var datum: Vector2 = Airplane.datum(aircraft_id) # (model_z_le, model_y_thrust)
	var cg: PackedFloat64Array = model.cg_le
	var parts: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is MeshInstance3D) or not _visible(node, root):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var shape: ConvexPolygonShape3D = mesh.create_convex_shape(true, false)
		if shape == null or shape.points.is_empty():
			continue
		var to_model: Transform3D = _in_model_frame(node as Node3D, root)
		var points := PackedFloat64Array()
		for p: Vector3 in shape.points:
			var m: Vector3 = to_model * p
			# Model frame (x right, y up, z aft) -> LE frame [x_aft, y_right, z_up] -> body FRD about the CG.
			var le := PackedFloat64Array([m.z - datum.x, m.x, m.y - datum.y])
			points.append_array(PackedFloat64Array([cg[0] - le[0], le[1] - cg[1], cg[2] - le[2]]))
		parts.append({path = str(root.get_path_to(node)), points = Array(points)})
	var gear := []
	for contact: Dictionary in model.get("landing_gear", {}).get("contacts", []):
		gear.append({name = contact.name, position = Array(contact.position),
			wheel_radius = contact.get("wheel_radius", null), max_compression = contact.max_compression})
	var propeller := {}
	for key in ["offset", "diameter", "axis"]:
		if model.propulsion.has(key):
			propeller[key] = Array(model.propulsion[key]) if model.propulsion[key] is PackedFloat64Array else model.propulsion[key]
	var result := {format = "openrc-gp07-hull-coverage-dump v1", aircraft = aircraft_id, data = str(entry.data),
		mass_kg = model.mass_kg, cg_le = Array(cg), inertia = Array(model.inertia), hull = Array(model.crash_hull),
		hull_components = Array(model.crash_hull_components), gear = gear, propeller = propeller, parts = parts}
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result) + "\n")
	file.close()
	print("GP-07a dump: %d visible mesh parts -> %s" % [parts.size(), out_path])
	root.free()
	quit(0)


func _visible(node: Node, top: Node3D) -> bool:
	var at: Node = node
	while at != null:
		if at is Node3D and not (at as Node3D).visible:
			return false
		if at == top:
			return true
		at = at.get_parent()
	return true


func _in_model_frame(node: Node3D, top: Node3D) -> Transform3D:
	var t: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != top:
		if parent is Node3D:
			t = (parent as Node3D).transform * t
		parent = parent.get_parent()
	return t
