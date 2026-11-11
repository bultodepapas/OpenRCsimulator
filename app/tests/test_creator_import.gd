extends SceneTree
## AC-07/AC-08: capture-once admission, source-to-structural placement and the preview builder.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Placement := preload("res://workshop/creator/placement.gd")
const Builder := preload("res://workshop/creator/visual_builder.gd")

var failures := 0


func _initialize() -> void:
	_placement()
	_admission()
	_preview()
	_glb()
	print("Creator import: %d failures" % failures)
	quit(1 if failures else 0)


## A flat "airplane" drawn in millimetres with the nose along +y and up along +z:
## fuselage from y = -300 (tail) to y = 500 (nose), wing tips at x = +-750, wing leading edge at y = 200.
func _plane_stl() -> PackedByteArray:
	var triangles: Array = [
		[[0, 500, 0], [-40, -300, 0], [40, -300, 0]],        # fuselage, counter-clockwise seen from +z
		[[-750, 100, 0], [750, 100, 0], [0, 200, 0]],        # wing
		[[0, -300, 0], [0, -220, 0], [0, -300, 120]],        # fin, in the plane of symmetry
	]
	var bytes := PackedByteArray()
	bytes.resize(84 + 50 * triangles.size())
	bytes.encode_u32(80, triangles.size())
	var offset := 84
	for triangle: Array in triangles:
		offset += 12  # zero normal: the reader derives it from the winding
		for vertex: Array in triangle:
			for component: int in 3:
				bytes.encode_float(offset, float(vertex[component]))
				offset += 4
		offset += 2
	return bytes


func _placement() -> void:
	check("unresolved placement refused", not Placement.resolve(Placement.unresolved()).ok)
	check("unresolved names the datum", _has_code(Placement.resolve(Placement.unresolved()), R.DATUM_UNRESOLVED))
	check("same axis for nose and up refused", not Placement.resolve(
		{nose_axis = "+y", up_axis = "-y", unit_scale = 1.0, datum = [0.0, 0.0, 0.0]}).ok)
	check("zero scale refused", not Placement.resolve(
		{nose_axis = "+y", up_axis = "+z", unit_scale = 0.0, datum = [0.0, 0.0, 0.0]}).ok)
	check("non-finite datum refused", not Placement.resolve(
		{nose_axis = "+y", up_axis = "+z", unit_scale = 1.0, datum = [0.0, NAN, 0.0]}).ok)

	# Nose +y, up +z, millimetres, datum at the wing leading edge (0, 200, 0).
	var placed: Dictionary = Placement.resolve({nose_axis = "+y", up_axis = "+z", unit_scale = 0.001, datum = [0.0, 200.0, 0.0]})
	check("placement resolves", placed.ok)
	if not placed.ok:
		return
	var resolved: Dictionary = placed.value
	# Expected by hand: aft = -(y - 200) mm, right = +x (nose +y, up +z => right is +x), up = z.
	check("datum maps to the origin", _near(Placement.to_structural(resolved, PackedFloat64Array([0.0, 200.0, 0.0])), [0.0, 0.0, 0.0]))
	check("nose is ahead (negative aft)", _near(Placement.to_structural(resolved, PackedFloat64Array([0.0, 500.0, 0.0])), [-0.3, 0.0, 0.0]))
	check("tail is aft", _near(Placement.to_structural(resolved, PackedFloat64Array([0.0, -300.0, 0.0])), [0.5, 0.0, 0.0]))
	check("right tip is +y_right", _near(Placement.to_structural(resolved, PackedFloat64Array([750.0, 100.0, 0.0])), [0.1, 0.75, 0.0]))
	check("fin top is up", _near(Placement.to_structural(resolved, PackedFloat64Array([0.0, -300.0, 120.0])), [0.5, 0.0, 0.12]))
	var bounds: Dictionary = Placement.structural_bounds(resolved, PackedFloat64Array([-750.0, -300.0, 0.0]), PackedFloat64Array([750.0, 500.0, 120.0]))
	check("structural bounds", _near(bounds.min, [-0.3, -0.75, 0.0]) and _near(bounds.max, [0.5, 0.75, 0.12]))

	# The same aircraft exported rotated (nose -x, up +y) and translated must land on the same frame.
	var other: Dictionary = Placement.resolve({nose_axis = "-x", up_axis = "+y", unit_scale = 0.001, datum = [1000.0, 50.0, 7.0]})
	check("rotated export resolves", other.ok)
	if other.ok:
		# In that export the right tip sits 100 mm aft (+x) and 750 mm to the right, which is -z there.
		check("rotated export maps the same landmark", _near(Placement.to_structural(other.value,
			PackedFloat64Array([1100.0, 50.0, 7.0 - 750.0])), [0.1, 0.75, 0.0]))
	for nose: String in Placement.AXES:
		for up: String in Placement.AXES:
			if nose.substr(1) == up.substr(1):
				continue
			var frame: Dictionary = Placement.resolve({nose_axis = nose, up_axis = up, unit_scale = 1.0, datum = [0.0, 0.0, 0.0]})
			var rows: Array = frame.value.rows
			var determinant: float = rows[0][0] * (rows[1][1] * rows[2][2] - rows[1][2] * rows[2][1]) \
				- rows[0][1] * (rows[1][0] * rows[2][2] - rows[1][2] * rows[2][0]) \
				+ rows[0][2] * (rows[1][0] * rows[2][1] - rows[1][1] * rows[2][0])
			check("placement %s/%s is a proper rotation" % [nose, up], is_equal_approx(determinant, 1.0))

	var scale: float = Placement.scale_for_wingspan({nose_axis = "+y", up_axis = "+z"},
		PackedFloat64Array([-750.0, -300.0, 0.0]), PackedFloat64Array([750.0, 500.0, 120.0]), 1.5)
	check("scale from a known wingspan", is_equal_approx(scale, 0.001))
	check("no scale without axes", Placement.scale_for_wingspan({}, PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 1.0, 1.0]), 1.5) == 0.0)


func _admission() -> void:
	var bytes := _plane_stl()
	var admitted: Dictionary = Importer.inspect_bytes(bytes, "plane.stl")
	check("STL admitted", admitted.ok)
	if not admitted.ok:
		printerr("\n".join(R.texts(admitted)))
		return
	var source: InspectedSource = admitted.value
	check("format from content", source.format() == InspectedSource.FORMAT_STL_BINARY)
	check("triangle count", source.triangle_count() == 3)
	check("identity is the hash of the captured bytes", source.sha256() == CreatorBytes.sha256(bytes))
	check("source bounds", _near(source.bounds_min(), [-750.0, -300.0, 0.0]) and _near(source.bounds_max(), [750.0, 500.0, 120.0]))
	var copy := source.source_bytes()
	copy[0] = 255
	check("captured bytes are not exposed for mutation", source.source_bytes() == bytes)
	var positions := source.stl_positions()
	positions[0] = 12345.0
	check("positions are not exposed for mutation", source.stl_positions()[0] != 12345.0)
	source.adopt({bytes = PackedByteArray([1]), sha256 = "", format = "", file_name = "", triangles = 0,
		bounds_min = PackedFloat64Array(), bounds_max = PackedFloat64Array()})
	check("an admitted source cannot be re-adopted", source.triangle_count() == 3)

	# The extension is only a hint: content decides.
	check("content decides, not the extension", Importer.inspect_bytes(bytes, "plane.glb").ok)
	check("picture refused", _has_code(Importer.inspect_bytes(bytes, "plane.png"), R.SOURCE_UNSUPPORTED))
	check("other model format refused with guidance", _has_code(Importer.inspect_bytes("v 0 0 0\n".to_utf8_buffer(), "plane.obj"), R.SOURCE_UNSUPPORTED))
	check("garbage refused", not Importer.inspect_bytes(PackedByteArray([1, 2, 3, 4, 5]), "plane.stl").ok)
	check("empty refused", not Importer.inspect_bytes(PackedByteArray(), "plane.stl").ok)
	var refused: Dictionary = Importer.inspect_bytes(PackedByteArray([1, 2, 3, 4, 5]), "plane.stl")
	check("refusals are routed to the import step", not refused.diagnostics.is_empty() and str(refused.diagnostics[0].step) == "import")

	# A flat model (no extent along one axis) cannot be oriented or sized.
	var flat := PackedByteArray()
	flat.resize(84 + 50)
	flat.encode_u32(80, 1)
	for index: int in 3:
		flat.encode_float(84 + 12 + index * 12, float(index))
		flat.encode_float(84 + 12 + index * 12 + 4, float(index * index))
	check("flat model refused", not Importer.inspect_bytes(flat, "flat.stl").ok)

	# Capture once: a file that changes after capture does not change the admitted identity.
	var path := "user://creator-import-test-%d.stl" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var captured: Dictionary = Importer.capture_and_inspect(path)
	check("file admitted", captured.ok)
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0, 1, 2]))
	file.close()
	if captured.ok:
		check("identity survives a later change of the file", (captured.value as InspectedSource).sha256() == CreatorBytes.sha256(bytes))
		check("file name is a label only", (captured.value as InspectedSource).file_name() == path.get_file())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check("missing file refused", _has_code(Importer.capture_and_inspect(path), R.SOURCE_MISSING))


func _preview() -> void:
	check("no source, no preview", not Builder.build_preview(null).ok)
	var admitted: Dictionary = Importer.inspect_bytes(_plane_stl(), "plane.stl")
	if not admitted.ok:
		return
	var source: InspectedSource = admitted.value
	var loose: Dictionary = Builder.build_preview(source)
	check("preview before placement", loose.ok and not loose.value.placed)
	var placement := {nose_axis = "+y", up_axis = "+z", unit_scale = 0.001, datum = [0.0, 200.0, 0.0]}
	var first: Dictionary = Builder.build_preview(source, placement)
	var second: Dictionary = Builder.build_preview(source, placement)
	check("placed preview", first.ok and first.value.placed)
	if not (loose.ok and first.ok and second.ok):
		return
	var root: Node3D = first.value.root
	root_node().add_child(root)
	check("root is named airplane", root.name == "airplane")
	check("propeller marker exists", root.get_node_or_null("propeller") is Node3D)
	var mesh_node: MeshInstance3D = root.find_child("stl_mesh", true, false) as MeshInstance3D
	check("mesh instance", mesh_node != null and mesh_node.mesh.get_surface_count() == 1)
	check("fresh instances per build", first.value.root != second.value.root
		and mesh_node.mesh != (second.value.root as Node3D).find_child("stl_mesh", true, false).mesh)
	check("fresh material per build", mesh_node.mesh.surface_get_material(0)
		!= (second.value.root as Node3D).find_child("stl_mesh", true, false).mesh.surface_get_material(0))
	if mesh_node != null:
		# Model frame: +x right, +y up, -z nose, leading edge at the origin.
		var to_root: Transform3D = (first.value.model as Node3D).transform
		check("nose points to -z", (to_root * Vector3(0, 500, 0)).is_equal_approx(Vector3(0, 0, -0.3)))
		check("right tip is +x", (to_root * Vector3(750, 100, 0)).is_equal_approx(Vector3(0.75, 0, 0.1)))
		check("fin is +y", (to_root * Vector3(0, -300, 120)).is_equal_approx(Vector3(0, 0.12, 0.5)))
		check("model point of a structural point", Builder.structural_to_model(PackedFloat64Array([0.5, 0.0, 0.12])).is_equal_approx(Vector3(0, 0.12, 0.5)))
		var arrays: Array = mesh_node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check("all vertices kept", vertices.size() == 9 and normals.size() == 9)
		# The fuselage and wing facets wind counter-clockwise seen from source +z, so their outward
		# normal is source +z, which is model +y after placement.
		var upward := 0
		for normal: Vector3 in normals:
			# Stored normals are compressed, so compare the direction with a tolerance.
			if (to_root.basis * normal).normalized().dot(Vector3.UP) > 0.999:
				upward += 1
		check("outward normals follow the authored winding", upward == 6)
	for built: Dictionary in [loose, first, second]:
		(built.value.root as Node3D).free()


## A minimal self-contained GLB: one tetrahedron, 4 vertices and 4 indexed triangles, in metres.
func _tetra_glb() -> PackedByteArray:
	var positions: Array = [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 3.0]]
	var indices: Array = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]
	var bin := PackedByteArray()
	bin.resize(48 + 24)
	for vertex: int in 4:
		for component: int in 3:
			bin.encode_float(vertex * 12 + component * 4, float(positions[vertex][component]))
	for index: int in 12:
		bin.encode_u16(48 + index * 2, int(indices[index]))
	var json := {
		"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0, "name": "body"}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0.0, 0.0, 0.0], "max": [1.0, 2.0, 3.0]},
			{"bufferView": 1, "componentType": 5123, "count": 12, "type": "SCALAR"}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": 0, "byteLength": 48, "target": 34962},
			{"buffer": 0, "byteOffset": 48, "byteLength": 24, "target": 34963}],
		"buffers": [{"byteLength": 72}],
	}
	var text: PackedByteArray = JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var glb := PackedByteArray()
	glb.resize(12 + 8 + text.size() + 8 + bin.size())
	glb.encode_u32(0, 0x46546C67)
	glb.encode_u32(4, 2)
	glb.encode_u32(8, glb.size())
	glb.encode_u32(12, text.size())
	glb.encode_u32(16, 0x4E4F534A)
	for index: int in text.size():
		glb[20 + index] = text[index]
	var at := 20 + text.size()
	glb.encode_u32(at, bin.size())
	glb.encode_u32(at + 4, 0x004E4942)
	for index: int in bin.size():
		glb[at + 8 + index] = bin[index]
	return glb


func _glb() -> void:
	var bytes := _tetra_glb()
	var admitted: Dictionary = Importer.inspect_bytes(bytes, "tetra.stl")
	check("GLB admitted by content, whatever the extension", admitted.ok)
	if not admitted.ok:
		printerr("\n".join(R.texts(admitted)))
		return
	var source: InspectedSource = admitted.value
	check("GLB format and counts", source.format() == InspectedSource.FORMAT_GLB and source.triangle_count() == 4 and not source.is_stl())
	check("GLB bounds", _near(source.bounds_min(), [0.0, 0.0, 0.0]) and _near(source.bounds_max(), [1.0, 2.0, 3.0]))
	# glTF convention: +y up; this fixture's nose is +z.
	var built: Dictionary = Builder.build_preview(source, {nose_axis = "+z", up_axis = "+y", unit_scale = 1.0, datum = [0.0, 0.0, 0.0]})
	check("GLB preview builds", built.ok and built.value.placed)
	if built.ok:
		var root: Node3D = built.value.root
		var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
		check("GLB preview holds the mesh under the model node", meshes.size() == 1 and (built.value.model as Node3D).is_ancestor_of(meshes[0]))
		check("GLB nose maps to -z", ((built.value.model as Node3D).transform * Vector3(0, 0, 3)).is_equal_approx(Vector3(0, 0, -3)))
		var flight: Dictionary = Builder.build_flight(source, {nose_axis = "+z", up_axis = "+y", unit_scale = 1.0, datum = [0.0, 0.0, 0.0]})
		check("GLB flight visual", not flight.is_empty() and str(flight.root.name) == "airplane" and flight.root != root)
		if not flight.is_empty():
			(flight.root as Node3D).free()
		root.free()
	# A truncated copy is refused before any engine loader is involved.
	check("truncated GLB refused", not Importer.inspect_bytes(bytes.slice(0, bytes.size() - 8), "tetra.glb").ok)


func root_node() -> Node:
	return root


func _has_code(result: Dictionary, code: String) -> bool:
	for entry: Variant in result.get("diagnostics", []):
		if entry is Dictionary and str((entry as Dictionary).get("code", "")) == code:
			return true
	return false


func _near(actual: Variant, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index: int in expected.size():
		if absf(float(actual[index]) - float(expected[index])) > 1e-9:
			return false
	return true


func check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
