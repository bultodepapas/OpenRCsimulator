# CR-22c-R1: prepared geometry remains fresh, bounded and disposable.
extends SceneTree

const Scuffs := preload("res://render/crash/airframe_scuffs.gd")

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
	var first_root := Node3D.new()
	first_root.name = "scuff_cache_first_aircraft"
	root.add_child(first_root)
	var original_mesh := _mesh_at(0.0)
	var first_panel := _panel(first_root, original_mesh, "fuselage")
	var scuffs = Scuffs.new()
	scuffs.prepare(first_root)
	_check("prepare caches the selected aircraft mesh", scuffs._bvh_by_mesh.has(original_mesh))
	var original_bvh: TriangleMesh = scuffs._bvh_by_mesh[original_mesh]

	var first_mark: MeshInstance3D = scuffs.add(first_root, Vector3.ZERO, Vector3(0, 0, -4), 0.3, "mown")
	_check("prepared cache supports a live mark", first_mark != null and first_mark.get_parent() == first_panel)
	_check("add reuses the prepared BVH", scuffs._bvh_by_mesh.get(original_mesh) == original_bvh)
	scuffs.clear()
	_check("clear removes marks but retains the prepared BVH", scuffs.marks.is_empty()
		and scuffs._bvh_by_mesh.get(original_mesh) == original_bvh)

	first_panel.visible = false
	_check("static surface_hit observes live visibility", Scuffs.surface_hit(first_root, Vector3.ZERO).is_empty())
	_check("instance add skips a currently hidden surface", scuffs.add(first_root, Vector3.ZERO,
		Vector3(0, 0, -4), 0.3, "mown") == null)
	first_panel.visible = true
	_check("showing a prepared mesh makes it queryable again",
		Scuffs.surface_hit(first_root, Vector3.ZERO).get("node") == first_panel)

	first_panel.position.y = 0.1
	var moved_hit: Dictionary = Scuffs.surface_hit(first_root, Vector3(0, 0.09, 0))
	_check("surface_hit uses the panel's current transform", not moved_hit.is_empty()
		and absf((moved_hit.point as Vector3).y - 0.1) < 0.0005)

	# Rebuild this same ArrayMesh resource at a new local height, then announce the in-place edit.
	var bvh_before_edit: TriangleMesh = scuffs._bvh_by_mesh[original_mesh]
	original_mesh.clear_surfaces()
	_add_surface(original_mesh, 0.025)
	original_mesh.emit_changed()
	_check("Resource.changed invalidates an in-place mesh edit", not scuffs._bvh_by_mesh.has(original_mesh))
	var edited_mark: MeshInstance3D = scuffs.add(first_root, Vector3(0, 0.1, 0),
		Vector3(0, 0, -4), 0.3, "mown")
	_check("the edited mesh rebuilds a usable BVH", edited_mark != null
		and scuffs._bvh_by_mesh.has(original_mesh)
		and scuffs._bvh_by_mesh[original_mesh] != bvh_before_edit)
	if edited_mark != null:
		var edited_arrays: Array = edited_mark.mesh.surface_get_arrays(0)
		var edited_vertex: Vector3 = (edited_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]
		_check("the rebuilt BVH follows changed vertices", absf((edited_mark.global_transform * edited_vertex).y - 0.125) < 0.001)

	# Replacing MeshInstance3D.mesh changes the resource identity and drops the detached mesh from this aircraft cache.
	var replacement_mesh := _mesh_at(0.05)
	first_panel.mesh = replacement_mesh
	var replacement_mark: MeshInstance3D = scuffs.add(first_root, Vector3(0, 0.1, 0),
		Vector3(0, 0, -4), 0.3, "rough")
	_check("a replacement mesh gets its own BVH", replacement_mark != null
		and scuffs._bvh_by_mesh.has(replacement_mesh))
	_check("the detached mesh and its watcher leave the selected cache",
		not scuffs._bvh_by_mesh.has(original_mesh))

	# A new selected aircraft replaces the old bounded cache and disconnects old resource watchers.
	scuffs.clear()
	var second_root := Node3D.new()
	second_root.name = "scuff_cache_second_aircraft"
	root.add_child(second_root)
	var second_mesh := _mesh_at(0.2)
	var second_panel := _panel(second_root, second_mesh, "fuselage")
	scuffs.prepare(second_root)
	var second_bvh: TriangleMesh = scuffs._bvh_by_mesh[second_mesh]
	_check("prepare switches the cache to the selected aircraft",
		scuffs._bvh_by_mesh.size() == 1 and scuffs._bvh_by_mesh.has(second_mesh)
		and not scuffs._bvh_by_mesh.has(replacement_mesh))
	replacement_mesh.emit_changed()
	_check("an old aircraft resource cannot invalidate the new cache",
		scuffs._bvh_by_mesh.get(second_mesh) == second_bvh)
	var second_hit: Dictionary = Scuffs.surface_hit(second_root, Vector3(0, 0.19, 0))
	_check("the selected aircraft remains queryable after a root switch",
		second_hit.get("node") == second_panel and absf((second_hit.point as Vector3).y - 0.2) < 0.0005)

	scuffs.clear()
	root.remove_child(first_root)
	first_root.free()
	root.remove_child(second_root)
	second_root.free()
	scuffs = null
	await process_frame
	var lifetime_refs: Array[WeakRef] = _make_lifetime_probe()
	await process_frame
	_check("cache signal connections do not retain the scuff owner", lifetime_refs[0].get_ref() == null)
	_check("released scuff caches do not retain mesh resources", lifetime_refs[1].get_ref() == null)

	print("airframe scuff cache: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _mesh_at(y: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_surface(mesh, y)
	return mesh


func _add_surface(mesh: ArrayMesh, y: float) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, y, -1), Vector3(1, y, -1), Vector3(1, y, 1),
		Vector3(-1, y, -1), Vector3(1, y, 1), Vector3(-1, y, 1),
	])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _panel(parent: Node3D, mesh: Mesh, panel_name: String) -> MeshInstance3D:
	var panel := MeshInstance3D.new()
	panel.name = panel_name
	panel.mesh = mesh
	parent.add_child(panel)
	return panel


func _make_lifetime_probe() -> Array[WeakRef]:
	var probe_root := Node3D.new()
	root.add_child(probe_root)
	var probe_mesh := _mesh_at(0.0)
	_panel(probe_root, probe_mesh, "fuselage")
	var probe_scuffs = Scuffs.new()
	probe_scuffs.prepare(probe_root)
	var scuffs_ref: WeakRef = weakref(probe_scuffs)
	var mesh_ref: WeakRef = weakref(probe_mesh)
	probe_scuffs.clear()
	root.remove_child(probe_root)
	probe_root.free()
	probe_scuffs = null
	probe_mesh = null
	probe_root = null
	return [scuffs_ref, mesh_ref]
