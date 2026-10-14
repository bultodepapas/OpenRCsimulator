# US-V12: scuffs on the Stik's airframe from soft contacts. A belly touch marks the fuselage underside, a wingtip
# brush the wing (and a trailing-edge one the aileron, which carries the mark when it moves), every mark lies on the
# struck surface facing the ground, nothing is marked away from the airframe, the count is capped, colours follow
# the field surface and clear() removes everything.
# Run: godot --headless --path . --script res://tests/test_airframe_scuffs.gd
extends SceneTree

const Builder := preload("res://render/airplane.gd")
const Scuffs := preload("res://render/crash/airframe_scuffs.gd")
const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var plane: Dictionary = Builder.build(Builder.STIK_ID)
	root.add_child(plane.root)
	await process_frame
	var scuffs := Scuffs.new()
	var d: Dictionary = Geometry.DATA
	var stations: Array = d.fuselage_stations
	var station: Array = stations[2]
	var belly_point := Vector3(0.0, float(station[3]) - 0.004, float(station[0]))
	var started := Time.get_ticks_usec()
	var belly := scuffs.add(plane.root, belly_point, Vector3(0, 0, -12), 0.5, "mown")
	var cost_ms := (Time.get_ticks_usec() - started) / 1000.0
	_check("a belly touch marks the fuselage", belly != null and belly.get_parent().name == "fuselage", str(belly.get_parent().name if belly else "none"))
	if belly != null:
		_check("the belly scuff lies on the underside within 1.5 mm and faces the ground", _on_surface(belly, 0.0015) and _faces_down(belly))
		_check("the scuff runs along the slide", _long_axis(belly).abs().z > 0.9, str(_long_axis(belly)))
	_check("one scuff costs %.1f ms (on contact only)" % cost_ms, cost_ms < 250.0)

	var wing: Dictionary = d.wing
	var tip_x: float = -0.5 * float(wing.span) + 0.06
	var mid_z: float = float(wing.leading_z) + 0.45 * float(wing.chord)
	var tip := scuffs.add(plane.root, Vector3(tip_x, 0.0, mid_z), Vector3(0, 0, -15), 0.3, "mown")
	_check("a wingtip brush marks the left wing", tip != null and _ancestor(tip, "wing_frame_left"), _path(tip))
	if tip != null:
		_check("the wingtip scuff lies on the wing's underside", _on_surface(tip, 0.0015) and _faces_down(tip),
			"on %s, down %s, n %s" % [_on_surface(tip, 0.0015), _faces_down(tip), (tip.global_basis * (tip.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]).normalized()])
	# Near the leading edge the underside curves away: the scuff must follow it, not lie on a tangent plane.
	var nose_z: float = float(wing.leading_z) + 0.10 * float(wing.chord)
	var curved := scuffs.add(plane.root, Vector3(-0.40, 0.0, nose_z), Vector3(0, 0, -15), 0.8, "mown")
	_check("a scuff near the leading edge follows the curved skin within 1 mm", curved != null and _on_surface(curved, 0.001, 0), _path(curved))
	var te_z: float = float(wing.leading_z) + 0.96 * float(wing.chord)
	var aileron_scuff := scuffs.add(plane.root, Vector3(tip_x - 0.08, -0.05, te_z), Vector3(0, 0, -15), 0.3, "mown")
	_check("a trailing-edge brush near the tip marks the aileron", aileron_scuff != null and _ancestor(aileron_scuff, "aileron_left_hinge"), _path(aileron_scuff))
	if aileron_scuff != null:
		var hinge := plane.root.find_child("aileron_left_hinge", true, false) as Node3D
		var corner: Vector3 = (aileron_scuff.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
		var before := aileron_scuff.global_transform * corner
		hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(15.0))
		_check("the aileron carries its scuff when it moves", (aileron_scuff.global_transform * corner).distance_to(before) > 0.002)
		hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(-15.0))

	_check("nothing is marked away from the airframe", scuffs.add(plane.root, Vector3(3.0, 0.0, 3.0), Vector3.ZERO, 1.0, "mown") == null)
	var runway := Scuffs.material("runway").albedo_color
	var grass := Scuffs.material("mown").albedo_color
	_check("a runway scuff is abraded film, lighter than a grass stain", runway.get_luminance() > grass.get_luminance() + 0.3)
	_check("an unknown surface falls back to soil", Scuffs.material("water").albedo_color == Scuffs.material("rough").albedo_color)
	for i in Scuffs.MAX_SCUFFS + 6:
		scuffs.add(plane.root, belly_point + Vector3(0, 0, 0.01 * (i % 5)), Vector3(0, 0, -8), 0.4, "rough")
	await process_frame
	_check("the scuff count is capped at %d" % Scuffs.MAX_SCUFFS, scuffs.marks.size() == Scuffs.MAX_SCUFFS
		and _scuff_nodes(plane.root) == Scuffs.MAX_SCUFFS, "%d nodes" % _scuff_nodes(plane.root))
	scuffs.clear()
	_check("clear() removes every scuff", scuffs.marks.is_empty() and _scuff_nodes(plane.root) == 0)
	print("US-V12 airframe scuffs: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


## Scuff vertices lie within `tolerance` of the struck mesh or its sibling meshes (neighbouring panels) along the
## scuff normal.
func _on_surface(scuff: MeshInstance3D, tolerance: float, allowed_off := 4) -> bool:
	var meshes: Array = (scuff.get_parent().get_parent() as Node).get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and not n.has_meta(Scuffs.SCUFF_META))
	var arrays := scuff.mesh.surface_get_arrays(0)
	var normal: Vector3 = (scuff.global_basis * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]).normalized()
	var on := 0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:
		var w := scuff.global_transform * v
		var best := INF
		for mesh_node: MeshInstance3D in meshes:
			var faces := mesh_node.mesh.get_faces()
			var to_mesh := mesh_node.global_transform.affine_inverse()
			var a := to_mesh * (w + normal * 0.01)
			var b := to_mesh * (w - normal * 0.01)
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(a * 1000.0, b * 1000.0, faces[i] * 1000.0, faces[i + 1] * 1000.0, faces[i + 2] * 1000.0)
				if hit != null:
					best = minf(best, (mesh_node.global_transform * ((hit as Vector3) / 1000.0)).distance_to(w))
		if best <= tolerance:
			on += 1
	# Grid points beyond a mesh edge keep the plane: at least the interior must sit on the surface.
	return on >= verts.size() - allowed_off


func _scuff_nodes(airplane: Node) -> int:
	return airplane.find_children("*", "MeshInstance3D", true, false).filter(func(n: Node) -> bool: return n.has_meta(Scuffs.SCUFF_META)).size()


func _faces_down(scuff: MeshInstance3D) -> bool:
	var n: Vector3 = (scuff.global_basis * (scuff.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]).normalized()
	return n.dot(Vector3.DOWN) > 0.8


func _long_axis(scuff: MeshInstance3D) -> Vector3:
	var verts: PackedVector3Array = scuff.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return (scuff.global_transform * verts[Scuffs.GRID_U - 1] - scuff.global_transform * verts[0]).normalized()


func _ancestor(node: Node, label: String) -> bool:
	var cursor := node
	while cursor != null:
		if String(cursor.name) == label:
			return true
		cursor = cursor.get_parent()
	return false


func _path(node: Node) -> String:
	return "none" if node == null else str(node.get_path())
