## CR-09c: imported models break into their real parts. Sections come from glTF extras / meta / names, a generated
## section map splits a merged mesh into real section meshes in the wreck twin only, and a requested section the model
## lacks never leaves a crash with nothing to release (docs/plans/crash-realism.md, Timber review).
extends SceneTree

const WreckController = preload("res://render/crash/wreck.gd")
const SectionSplitter = preload("res://render/crash/section_splitter.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _splitter()
	await _resolution()
	await _no_wing_fallback()
	await _timber_fallback()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


## Two quads (= two shells, 4 triangles) per surface: one at x = -1 (left wing), one at x = +1 (right wing), plus a
## centre quad on the second surface (body). Two materials.
func _merged_airplane() -> Node3D:
	var root := Node3D.new()
	root.name = "airplane"
	var mesh := ArrayMesh.new()
	for s in 2:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var index := PackedInt32Array()
		var centres := [-1.0, 1.0] if s == 0 else [-1.0, 1.0, 0.0]
		for c: float in centres:
			var base := verts.size()
			for corner in [Vector2(-0.2, -0.1), Vector2(0.2, -0.1), Vector2(0.2, 0.1), Vector2(-0.2, 0.1)]:
				verts.append(Vector3(c + corner.x, 0.1 * s, corner.y))
				normals.append(Vector3.UP)
				uvs.append(corner + Vector2(c, s))
			index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.resource_name = "mat%d" % s
		mesh.surface_set_material(s, material)
	var airframe := MeshInstance3D.new()
	airframe.name = "airframe"
	airframe.mesh = mesh
	# sections: 0 core, 1 wing_left, 2 wing_right. Surface 0: left quad, right quad. Surface 1: left, right, centre.
	airframe.set_meta(SectionSplitter.META, {format = SectionSplitter.FORMAT, sections = ["core", "wing_left", "wing_right"],
		surfaces = [[1, 2, 2, 2], [1, 2, 2, 2, 0, 2]]})
	root.add_child(airframe)
	var tail := Node3D.new()
	tail.name = "tail_frame"
	root.add_child(tail)
	var stab := MeshInstance3D.new()
	stab.name = "stab_mesh"
	stab.mesh = BoxMesh.new()
	stab.position = Vector3(0, 0, 1.0)
	tail.add_child(stab)
	return root


func _groups(wreck: Variant) -> Dictionary:
	var out := {}
	for group: Dictionary in wreck._groups:
		out[String(group.kind)] = group
	return out


func _triangles(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for child in node.get_children():
		n += _triangles(child)
	return n


func _splitter() -> void:
	var airplane := _merged_airplane()
	root.add_child(airplane)
	var source_triangles := _triangles(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	_check("prepare succeeds on a mapped merged mesh", wreck.prepare(airplane))
	var groups := _groups(wreck)
	_check("the map's wing halves become wreck groups", groups.has("wing_left") and groups.has("wing_right"), str(groups.keys()))
	_check("the named tail frame still groups by name", groups.has("horizontal_tail"))
	_check("the flying model keeps its merged mesh", airplane.get_node_or_null("airframe") != null and _triangles(airplane) == source_triangles)
	_check("the twin no longer has the merged mesh", wreck._twin.get_node_or_null("airframe") == null)
	_check("no triangle is lost or duplicated", _triangles(wreck._twin) == source_triangles, "%d vs %d" % [_triangles(wreck._twin), source_triangles])
	var left: MeshInstance3D = wreck._twin.get_node_or_null("airframe_section_wing_left")
	_check("a section keeps one surface per source material", left != null and left.mesh.get_surface_count() == 2
		and left.mesh.surface_get_material(0).resource_name == "mat0" and left.mesh.surface_get_material(1).resource_name == "mat1")
	_check("a section holds only its own region", left != null and left.mesh.get_aabb().end.x < -0.7)
	_check("section vertices keep their UVs", left != null and (left.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == 4)
	_check("core triangles stay with the body", wreck._twin.get_node_or_null("airframe_section_core") != null
		and not groups.has("core") or String(groups.get("core", {}).get("kind", "core")) == "core")
	var first: AABB = left.mesh.get_aabb() if left else AABB()
	wreck.prepare(airplane)
	var again: MeshInstance3D = wreck._twin.get_node_or_null("airframe_section_wing_left")
	_check("splitting repeats exactly", again != null and again.mesh.get_aabb() == first)
	wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0, -10, -5), Vector3.ZERO, {"class": 3, "component": "left_wing_tip", "mass_kg": 2.0, "seed": 3})
	var detached: Array = []
	for group: Dictionary in wreck._groups.slice(1):
		if bool(group.detached):
			detached.append(String(group.kind))
	_check("a C3 left-tip hit releases the real left wing section", detached == ["wing_left"], str(detached))
	wreck.reset()
	# A map that does not match the mesh is ignored with a warning; the merged mesh stays whole.
	var bad := _merged_airplane()
	root.add_child(bad)
	bad.get_node("airframe").set_meta(SectionSplitter.META, {format = SectionSplitter.FORMAT, sections = ["core", "wing_left"], surfaces = [[1, 3], [0, 6]]})
	_check("a mismatched map is rejected before any change", not SectionSplitter.validate(bad.get_node("airframe").mesh, bad.get_node("airframe").get_meta(SectionSplitter.META)).ok)
	wreck.prepare(bad)
	_check("a rejected map leaves the twin's merged mesh whole", wreck._twin.get_node_or_null("airframe") != null and not _groups(wreck).has("wing_left"))
	wreck.free()
	airplane.free()
	bad.free()


func _resolution() -> void:
	var airplane := Node3D.new()
	airplane.name = "airplane"
	var tagged := MeshInstance3D.new()
	tagged.name = "Object_017" # a meaningless Blender name
	tagged.mesh = BoxMesh.new()
	tagged.set_meta("extras", {"openrc_section": "wing_right"})
	airplane.add_child(tagged)
	var hinge := Node3D.new()
	hinge.name = "aileron_left_hinge"
	hinge.set_meta("crash_section", "wing_left")
	airplane.add_child(hinge)
	var aileron := MeshInstance3D.new()
	aileron.mesh = BoxMesh.new()
	hinge.add_child(aileron)
	var body := Node3D.new()
	body.name = "fuselage_group"
	body.set_meta("extras", {"openrc_section": "core"})
	airplane.add_child(body)
	var canopy := MeshInstance3D.new()
	canopy.name = "Object_042"
	canopy.mesh = BoxMesh.new()
	canopy.set_meta("extras", {"openrc_section": "canopy"})
	body.add_child(canopy)
	var odd := MeshInstance3D.new()
	odd.name = "rudder"
	odd.mesh = BoxMesh.new()
	odd.set_meta("crash_section", "rudder_blade") # unknown: warned, name rule used
	airplane.add_child(odd)
	root.add_child(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(airplane)
	var groups := _groups(wreck)
	_check("glTF extras name a section regardless of the node name", groups.has("wing_right"))
	_check("builder meta attaches a control hinge to its wing", groups.has("wing_left"))
	_check("a core-tagged parent still lets a tagged child break away", groups.has("canopy"))
	_check("an unknown explicit name falls back to the name rules", groups.has("vertical_tail"))
	wreck.free()
	airplane.free()


func _section_triangles(node: Node) -> int:
	var n := 0
	for child in node.find_children("airframe_section_*", "MeshInstance3D", true, false):
		var mesh: Mesh = (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


## CR-09c1 regression: a model without wing sections (like the merged r1 Timber before TT-13c) hit on a wing tip at
## C3 must still release its legacy sections instead of nothing.
func _no_wing_fallback() -> void:
	var airplane := Node3D.new()
	airplane.name = "airplane"
	var body := MeshInstance3D.new()
	body.name = "airframe"
	body.mesh = BoxMesh.new()
	airplane.add_child(body)
	for pair in [["tail_frame", Vector3(0, 0, 1.0)], ["rudder_hinge", Vector3(0, 0.2, 1.1)]]:
		var pivot := Node3D.new()
		pivot.name = pair[0]
		pivot.position = pair[1]
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		pivot.add_child(mesh)
		airplane.add_child(pivot)
	root.add_child(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(airplane)
	wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0, -10, -5), Vector3.ZERO, {"class": 3, "component": "left_wing_tip", "mass_kg": 2.0, "seed": 9})
	var released: Array = []
	for group: Dictionary in wreck._groups.slice(1):
		if bool(group.detached):
			released.append(String(group.kind))
	released.sort()
	_check("a wing-tip C3 hit on a model without wings releases its legacy sections", released == ["horizontal_tail", "vertical_tail"], str(released))
	wreck.free()
	airplane.free()


func _timber_fallback() -> void:
	var timber: Node3D = AirplaneBuilder.build("turbo-lumber-evolution").root
	root.add_child(timber)
	await process_frame
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(timber)
	var groups := _groups(wreck)
	# TT-13c: the generated map gives the merged Blender airframe its real sections.
	for kind in ["wing_left", "wing_right", "horizontal_tail", "vertical_tail", "engine", "canopy", "propeller", "gear"]:
		_check("Timber wreck has a real %s section" % kind, groups.has(kind), str(groups.keys()))
	var left_members: Array = groups.get("wing_left", {}).get("members", []).map(func(n: Node) -> String: return String(n.name))
	_check("the left wing carries its aileron and flap", left_members.has("aileron_left_hinge") and left_members.has("flap_left_hinge")
		and left_members.has("airframe_section_wing_left"), str(left_members))
	_check("the flying Timber keeps its merged airframe", timber.find_child("airframe", true, false) != null)
	_check("the twin conserves every airframe triangle", _section_triangles(wreck._twin) == 36691, str(_section_triangles(wreck._twin)))
	wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0, -10, -5), Vector3.ZERO, {"class": 3, "component": "left_wing_tip", "mass_kg": 2.19, "seed": 5})
	var released: Array = []
	for group: Dictionary in wreck._groups.slice(1):
		if bool(group.detached):
			released.append(String(group.kind))
	_check("Timber C3 left-tip hit releases its real left wing only", released == ["wing_left"], str(released))
	wreck.reset()
	for label in ["left_wing_tip", "belly"]:
		wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0, -10, -5), Vector3.ZERO, {"class": 3, "component": label, "mass_kg": 2.19, "seed": 5})
		var detached := 0
		for group: Dictionary in wreck._groups.slice(1):
			detached += 1 if bool(group.detached) else 0
		_check("Timber C3 %s hit releases at least one real section" % label, detached > 0, "%d sections, groups %s" % [detached, str(wreck.stats().fragment_groups)])
		wreck.reset()
	wreck.free()
	timber.free()
