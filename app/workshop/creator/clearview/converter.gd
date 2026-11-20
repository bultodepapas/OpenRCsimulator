extends RefCounted
## AC3Db render scene → self-contained GLB. Never infers physics or placement.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const Package := preload("package.gd")
const Ac3d := preload("ac3d.gd")
const Images := preload("images.gd")
const Motion := preload("motion.gd")
const Observations := preload("observations.gd")
const VERSION := "openrc-clearview-visual-v1"
const MAX_POLYGON_WORK := 4000000
## A few self-intersecting slivers are omitted and reported; more indicates a damaged model.
const MAX_SELF_INTERSECTING := 16
const SELF_INTERSECTING_NOTE := "%s self-intersecting surfaces were omitted."
## Doubled triangle area below extent² × this is invisible (< ~0.03 mm square on a 1 m part).
const NEGLIGIBLE_AREA := 1.0e-9
const UNSUBDIVIDED_NOTE := "%s parts use AC3D subdivision. Their unsmoothed control shape is shown."
var _bin := PackedByteArray()
var _gltf := {}
var _materials := {}
var _textures := {}
var _texture_alpha := {}
var _markers: Array = []
var _marker_points := 0
var _marker_faces := 0
var _marker_refs := 0
var _texture_notes: Array = []
var _dependencies: Array = []
var _pixels := 0
var _triangles := 0
var _polygon_work := 0
var _dropped := 0
var _self_intersecting := 0
var _cancelling_face := false
var _error := {}
var _cancel := Callable()
var _package: Package
var _model := {}
var _scene := {}
var _parameters := {}

static func convert(package: Package, root: String, cancel := Callable()) -> Dictionary:
	if package == null:
		return R.fail(R.SOURCE_INVALID, "Choose a ClearView ZIP first.", "source", "import")
	var model := package.model(root)
	if model.is_empty():
		return R.fail(R.SOURCE_MISSING, "The selected model is not in this ZIP.", "source", "import")
	if not model.ok:
		return R.fail_all(model.diagnostics)
	var bytes := package.archive().read_member(model.visual_member, Ac3d.MAX_BYTES, cancel)
	if not bytes.ok:
		return bytes
	var scene := Ac3d.read(bytes.value, cancel)
	if not scene.ok:
		return scene
	var converter := new()
	converter._package = package
	converter._model = model
	converter._scene = scene.value
	converter._cancel = cancel
	var parameters := package.archive().read_member(model.params_member, Observations.Params.MAX_BYTES, cancel)
	if not parameters.ok:
		return parameters
	converter._parameters = Observations.parameter_payload(model.params_member,parameters.value)
	converter._dependencies = [{member = model.params_member, sha256 = model.params.sha256},
		{member = model.visual_member, sha256 = CreatorBytes.sha256(bytes.value), case_adjusted = model.case_adjusted}]
	return converter._convert()

## Presentation notes from an admitted, immutable GLB. Metadata grants no flight capability.
## Called on the import worker so reopening a model never parses a large receipt in the UI loop.
static func source_notes(source: InspectedSource) -> Array:
	if source == null or not source.is_admitted() or source.format() != "glb":
		return []
	var bytes := source.source_bytes()
	var length := bytes.decode_u32(12)
	if length > Limits.GLB_JSON_BYTES or 20 + length > bytes.size():
		return []
	var document: Variant = JSON.parse_string(bytes.slice(20,20 + length).get_string_from_utf8())
	if not document is Dictionary:
		return []
	var asset: Variant = document.get("asset",{})
	if not asset is Dictionary or not asset.get("extras",{}) is Dictionary:
		return []
	var receipt: Variant = asset.get("extras",{}).get("openrc_clearview",{})
	if not receipt is Dictionary or typeof(receipt.get("format")) != TYPE_STRING or receipt.format != VERSION \
			or typeof(receipt.get("physics_imported")) != TYPE_BOOL or receipt.physics_imported \
			or not CreatorBytes.is_sha256(receipt.get("archive_sha256")):
		return []
	var notes: Array = [R.diagnostic(R.UNSUPPORTED_CAPABILITY,
		"Only the ClearView appearance is imported. Define and validate its OpenRC flight configuration separately.",
		"source","import",[],R.SEVERITY_WARNING), R.diagnostic(R.SOURCE_UNSUPPORTED,
		"Legacy Phong materials use an approximate OpenRC finish. Original colours and texture mapping are retained.",
		"source","import",[],R.SEVERITY_INFO)]
	var dropped: Variant = receipt.get("dropped_degenerate_surfaces",0)
	if typeof(dropped) in [TYPE_FLOAT,TYPE_INT] and float(dropped) == floor(float(dropped)) and dropped > 0 and dropped <= Ac3d.MAX_SURFACES:
		notes.append(R.diagnostic(R.SOURCE_INVALID,"%s zero-area surfaces were omitted.","source","import",[str(int(dropped))],R.SEVERITY_INFO))
	var crossed: Variant = receipt.get("omitted_self_intersecting_surfaces",0)
	if typeof(crossed) in [TYPE_FLOAT,TYPE_INT] and float(crossed) == floor(float(crossed)) and crossed > 0 and crossed <= MAX_SELF_INTERSECTING:
		notes.append(R.diagnostic(R.SOURCE_INVALID,SELF_INTERSECTING_NOTE,"source","import",[str(int(crossed))],R.SEVERITY_INFO))
	var unsmoothed: Variant = receipt.get("unsubdivided_parts",0)
	if typeof(unsmoothed) in [TYPE_FLOAT,TYPE_INT] and float(unsmoothed) == floor(float(unsmoothed)) and unsmoothed > 0 and unsmoothed <= Ac3d.MAX_NODES:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,UNSUBDIVIDED_NOTE,"source","import",[str(int(unsmoothed))],R.SEVERITY_WARNING))
	var image_notes: Variant = receipt.get("image_notes",[])
	notes.append_array(_motion_notes(receipt.get("coordinate_frames")))
	if image_notes is Array:
		# Only fixed, known messages are re-shown; untrusted receipt text never reaches the UI.
		for known: String in ["JPEG comments were ignored.", Images.JpegCheck.METADATA_NOTE, Images.Gif.FRAME_NOTE]:
			for entry: Variant in image_notes.slice(0,Limits.GLB_IMAGES):
				if entry is Dictionary and typeof(entry.get("message")) == TYPE_STRING and entry.message == known:
					notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,known,"source","import",[],R.SEVERITY_INFO))
					break
	var archive_notes: Variant = receipt.get("archive_notes",[])
	if archive_notes is Array:
		for entry: Variant in archive_notes.slice(0,33):
			if not entry is Dictionary or typeof(entry.get("message")) != TYPE_STRING:
				continue
			if entry.message == "An empty legacy directory size hint was ignored: %s." \
					and entry.get("arguments") is Array and entry.arguments.size() == 1 \
					and typeof(entry.arguments[0]) == TYPE_STRING and Package.Archive.safe_name(entry.arguments[0]):
				notes.append(R.diagnostic(R.SOURCE_INVALID, entry.message, "source", "import", entry.arguments, R.SEVERITY_INFO))
			elif entry.message == "Ignored size hints for %s additional empty legacy directories." \
					and entry.get("arguments") is Array and entry.arguments.size() == 1 and typeof(entry.arguments[0]) == TYPE_STRING \
					and entry.arguments[0].is_valid_int() and entry.arguments[0].length() <= 4 \
					and entry.arguments[0].to_int() > 0 and entry.arguments[0].to_int() <= Package.Archive.MAX_ENTRIES:
				notes.append(R.diagnostic(R.SOURCE_INVALID, entry.message, "source", "import", entry.arguments, R.SEVERITY_INFO))
	return notes

func _convert() -> Dictionary:
	var frames := Motion.inspect(_scene,_model.params,_cancel)
	if not frames.ok:
		return frames
	_gltf = {asset = {version = "2.0", generator = VERSION}, scene = 0, scenes = [{nodes = _scene.roots}],
		nodes = [], meshes = [], materials = [], images = [], textures = [], samplers = [{wrapS = 10497, wrapT = 10497}],
		accessors = [], bufferViews = [], buffers = []}
	for node: Dictionary in _scene.nodes:
		if _cancelled():
			break
		var output := {name = node.name, matrix = _matrix(node), children = node.children}
		_capture_markers(node, _gltf.nodes.size())
		var primitives: Array = [] if frames.value.marked.has(_gltf.nodes.size()) else _mesh(node)
		if not primitives.is_empty():
			output.mesh = _gltf.meshes.size()
			_gltf.meshes.append({name = node.name, primitives = primitives})
		_gltf.nodes.append(output)
	if not _error.is_empty():
		return _error
	var static_nodes: Array = _gltf.nodes.duplicate(true)
	var static_roots: Array = _gltf.scenes[0].nodes.duplicate()
	var motion := Motion.prepare(_gltf,_scene,frames.value,_cancel)
	if not motion.ok:
		return motion
	var receipt := {format = VERSION, archive_sha256 = _package.archive().sha256(), archive_label = _package.archive().label(),
		model_root = _model.root, params_version = _model.params.version, model_type = _model.params.model_type,
		members = _dependencies, physics_imported = false, dropped_degenerate_surfaces = _dropped,
		material_conversion = "AC3D Phong to metallic-roughness approximation; ambient/specular originals retained below",
		original_materials = _scene.materials, observations = _model.params.records, markers = _markers,
		image_notes = _texture_notes, archive_notes = _package.archive().diagnostics(),coordinate_frames = motion.value}
	# Present only when nonzero, so earlier conversions keep their exact bytes.
	if _self_intersecting > 0:
		receipt.omitted_self_intersecting_surfaces = _self_intersecting
	var unsmoothed := 0
	for node: Dictionary in _scene.nodes:
		if int(node.get("subdiv", 0)) > 0 and not node.surfaces.is_empty():
			unsmoothed += 1
	if unsmoothed > 0:
		receipt.unsubdivided_parts = unsmoothed
	_gltf.asset.extras = {openrc_clearview = receipt}
	if not _parameters.is_empty():
		receipt.parameters = _parameters
	# Empty optional collections are omitted; Creator's validator admits the resulting closed subset.
	var no_images: bool = _gltf.images.is_empty()
	for key: String in ["images", "textures", "samplers"]:
		if no_images or _gltf[key].is_empty():
			_gltf.erase(key)
	_gltf.buffers = [{byteLength = _bin.size()}]
	var label := str(_model.name).validate_filename().left(200) + ".glb"
	var inspected := _admit(label)
	if not inspected.ok and receipt.has("parameters") and inspected.diagnostics[0].code == R.SOURCE_LIMIT:
		# An optional source member must not make an otherwise admitted visual unavailable.
		receipt.erase("parameters")
		receipt.parameters_omitted = "metadata_limit"
		_error = {}
		inspected = _admit(label)
	if not inspected.ok and not motion.value.prepared.is_empty():
		# Optional articulation must not make an otherwise admitted static model unavailable.
		_gltf.nodes = static_nodes
		_gltf.scenes[0].nodes = static_roots
		for entry: Dictionary in motion.value.prepared:
			motion.value.unresolved.append({group = entry.group,reason = "rig_admission",servos = entry.servos})
		motion.value.prepared = []
		receipt.coordinate_frames = motion.value
		_gltf.asset.extras.openrc_clearview = receipt
		_error = {}
		inspected = _admit(label)
	if not inspected.ok:
		return inspected
	var notes: Array = _model.diagnostics.duplicate(true)
	notes.append_array(_package.archive().diagnostics())
	notes.append_array(_texture_notes)
	notes.append_array(_motion_notes(motion.value))
	notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, "Legacy Phong materials use an approximate OpenRC finish. Original colours and texture mapping are retained.", "source", "import", [], R.SEVERITY_INFO))
	if _dropped > 0:
		notes.append(R.diagnostic(R.SOURCE_INVALID, "%s zero-area surfaces were omitted.", "source", "import", [str(_dropped)], R.SEVERITY_INFO))
	if _self_intersecting > 0:
		notes.append(R.diagnostic(R.SOURCE_INVALID, SELF_INTERSECTING_NOTE, "source", "import", [str(_self_intersecting)], R.SEVERITY_INFO))
	if unsmoothed > 0:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, UNSUBDIVIDED_NOTE, "source", "import", [str(unsmoothed)], R.SEVERITY_WARNING))
	return R.ok({source = inspected.value, receipt = receipt}, notes)

func _admit(label: String) -> Dictionary:
	var encoded := _glb()
	if not _error.is_empty():
		return _error
	if encoded.size() > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The converted model exceeds the 32 MiB Creator limit.", "source", "import")
	return Importer.inspect_bytes(encoded,label)

## Read only bounded counts from untrusted extras; never reconstruct or execute a rig from them.
static func _motion_notes(motion: Variant) -> Array:
	if not motion is Dictionary or typeof(motion.get("format")) != TYPE_STRING or motion.format != Motion.FORMAT:
		return []
	var notes: Array = []
	for field: String in ["frames","prepared","unresolved"]:
		if not motion.get(field) is Array or motion[field].size() > Limits.GLB_NODES:
			return []
	if not motion.frames.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,"%s coordinate markers were hidden and retained as source evidence.","source","import",[str(motion.frames.size())],R.SEVERITY_INFO))
	var unreadable: Variant = motion.get("unreadable_frames",[])
	if unreadable is Array and not unreadable.is_empty() and unreadable.size() <= Limits.GLB_NODES:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,Motion.UNREADABLE_NOTE,"source","import",[str(unreadable.size())],R.SEVERITY_WARNING))
	if not motion.prepared.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,"%s visual hinge proposals were prepared. Select their pivot groups in Moving parts; X follows the declared axis. Confirm each control and direction in the preview.","source","import",[str(motion.prepared.size())],R.SEVERITY_INFO))
	if not motion.unresolved.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,"%s servo mappings were left unprepared. Review their source declarations before binding those parts.","source","import",[str(motion.unresolved.size())],R.SEVERITY_WARNING))
		# Rebuild explanations from a closed reason table, never display arbitrary saved error text.
		for entry: Variant in motion.unresolved.slice(0,16):
			if not entry is Dictionary or typeof(entry.get("group")) != TYPE_STRING or typeof(entry.get("reason")) != TYPE_STRING:
				continue
			var label: String = entry.group
			if label.is_empty() or label.length() > 512:
				continue
			var printable := true
			for at: int in label.length():
				if label.unicode_at(at) < 32 or label.unicode_at(at) == 127:
					printable = false
			if not printable:
				continue
			var message := ""
			match entry.reason:
				"missing_or_duplicate_render_frame", "missing_render_group", "empty_or_whole_model_group":
					message = "Hinge \"%s\": provide one named render frame and a separate visible part group."
				"missing_or_conflicting_servo_mapping", "unsupported_or_conflicting_servo_movement", "unsupported_servo_target_type", "missing_or_conflicting_model_servos", "unlisted_servo_section", "missing_listed_servo", "multiple_servos_for_render_group":
					message = "Hinge \"%s\": use one listed rotation servo with an unambiguous surface, render group and axis."
				"multiple_render_parents", "foreign_render_descendant", "nested_coordinate_group", "overlapping_render_groups", "non_rigid_coordinate_frame":
					message = "Hinge \"%s\": separate unrelated or nested parts and apply rigid parent transforms."
				"hinge_limit", "node_limit", "depth_limit", "neutral_transform_mismatch", "render_precision":
					message = "Hinge \"%s\": reparenting exceeded precision or hierarchy limits. Simplify and recenter the source."
				"rig_admission":
					message = "Hinge \"%s\": the prepared model was refused. Its original static hierarchy was retained."
				"unreadable_render_frame":
					message = "Hinge \"%s\": its coordinate marker could not be read. Bind this part manually in Moving parts."
			if not message.is_empty():
				notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,message,"source","import",[label],R.SEVERITY_WARNING))
	return notes

func _mesh(node: Dictionary) -> Array:
	# Point/line-only helpers (e.g. COORD_* markers) render nothing; their float64 evidence is
	# retained separately, so render precision does not apply to them.
	if not node.surfaces.any(func(face: Dictionary) -> bool: return (int(face.flags) & 15) == 0 and face.refs.size() >= 3):
		# Polygons with fewer than three corners render nothing either (counted as zero-area).
		for face: Dictionary in node.surfaces:
			if (int(face.flags) & 15) == 0:
				_dropped += 1
		return []
	if not _precision_ok(node):
		return []
	var extent := _extent(node)
	var area_floor := extent * extent * NEGLIGIBLE_AREA
	var normals: Array[Vector3] = []
	var neighbours := {}
	var cancelling := {}
	for index: int in node.surfaces.size():
		if index % 128 == 0 and _cancelled():
			return []
		var face: Dictionary = node.surfaces[index]
		var normal := Vector3.ZERO
		if (int(face.flags) & 15) == 0:
			normal = _normal(node, face)
			if _cancelling_face:
				# Exactly cancelling bow-tie: no interior. Omitted and counted like any crossing.
				_cancelling_face = false
				cancelling[index] = true
				_self_intersecting += 1
				if _self_intersecting > MAX_SELF_INTERSECTING:
					_error = R.fail(R.SOURCE_INVALID, "Polygon %s in part \"%s\" has intersecting edges, and the model has too many such surfaces to omit.", "source", "import", [str(index),str(node.name)])
					return []
			for ref: Dictionary in face.refs:
				if not neighbours.has(ref.vertex):
					neighbours[ref.vertex] = []
				neighbours[ref.vertex].append(index)
		normals.append(normal.normalized())
	var groups := {}
	var crease := cos(deg_to_rad(float(node.crease)))
	for face_index: int in node.surfaces.size():
		if face_index % 128 == 0 and _cancelled():
			break
		var face: Dictionary = node.surfaces[face_index]
		if (int(face.flags) & 15) != 0:
			continue # Marker points and lines remain non-rendered scene nodes.
		if cancelling.has(face_index):
			continue
		var normal: Vector3 = normals[face_index]
		if normal == Vector3.ZERO:
			_dropped += 1
			continue
		var order := _triangulate(node, face, normal, face_index)
		if not _error.is_empty():
			break
		if order.is_empty():
			continue # An omitted self-intersecting surface, counted and reported.
		var material := _material(face.material, node.texture, bool(int(face.flags) & 32))
		if material < 0:
			break
		if not groups.has(material):
			groups[material] = {positions = [], normals = [], uv = []}
		var group: Dictionary = groups[material]
		for offset: int in range(0, order.size(), 3):
			var triangle: Array[int] = [order[offset], order[offset + 1], order[offset + 2]]
			var a := _vector(node.vertices[face.refs[triangle[0]].vertex])
			var b := _vector(node.vertices[face.refs[triangle[1]].vertex])
			var c := _vector(node.vertices[face.refs[triangle[2]].vertex])
			var source_cross := _triangle_cross(node.vertices[face.refs[triangle[0]].vertex],
				node.vertices[face.refs[triangle[1]].vertex],node.vertices[face.refs[triangle[2]].vertex])
			var render_cross := _triangle_cross([a.x,a.y,a.z],[b.x,b.y,b.z],[c.x,c.y,c.z])
			var preserved: float = source_cross[0]*render_cross[0] + source_cross[1]*render_cross[1] + source_cross[2]*render_cross[2]
			if preserved <= 0.0 or not is_finite(preserved):
				# Collinear outline corners can yield an ear with zero or rounding-level source area
				# (DR 107: |cross| ~1e-20 on a 1 m part) that collapses at render precision. It covers
				# nothing visible, so it is dropped. A visible triangle that flips still refuses.
				var doubled_area := sqrt(source_cross[0]*source_cross[0] + source_cross[1]*source_cross[1] + source_cross[2]*source_cross[2])
				if _is_zero(source_cross) or doubled_area <= area_floor:
					if order.size() == 3:
						_dropped += 1
					continue
				_error = R.fail(R.SOURCE_UNSUPPORTED, "A model triangle loses its area or winding at render precision. Recenter or rescale the source geometry before importing.", "source", "import")
				return []
			if source_cross[0]*normal.x + source_cross[1]*normal.y + source_cross[2]*normal.z < 0.0:
				var swap := triangle[1]
				triangle[1] = triangle[2]
				triangle[2] = swap
			_triangles += 1
			if _triangles > Limits.TRIANGLES:
				_error = R.fail(R.SOURCE_LIMIT, "The converted model exceeds the Creator triangle limit.", "source", "import")
				return []
			for corner: int in triangle:
				var ref: Dictionary = face.refs[corner]
				group.positions.append_array(node.vertices[ref.vertex])
				var smooth := normal
				if int(face.flags) & 16:
					var sum := Vector3.ZERO
					for adjacent: int in neighbours[ref.vertex]:
						_polygon_work += 1
						if _polygon_work > MAX_POLYGON_WORK:
							_error = R.fail(R.SOURCE_LIMIT, "The model exceeds the geometry conversion work limit.", "source", "import")
							return []
						if normals[adjacent].dot(normal) >= crease - 1.0e-6:
							sum += normals[adjacent]
					if sum != Vector3.ZERO:
						smooth = sum.normalized()
				group.normals.append_array([smooth.x, smooth.y, smooth.z])
				group.uv.append_array([ref.uv[0] * node.texrep[0] + node.texoff[0], 1.0 - (ref.uv[1] * node.texrep[1] + node.texoff[1])])
	var primitives: Array = []
	for material: int in groups:
		var group: Dictionary = groups[material]
		if group.positions.is_empty():
			continue # Every triangle of this material was a dropped sliver.
		var attributes := {POSITION = _accessor(group.positions, 3, true), NORMAL = _accessor(group.normals, 3)}
		if not str(node.texture).is_empty():
			attributes.TEXCOORD_0 = _accessor(group.uv, 2)
		primitives.append({attributes = attributes, mode = 4, material = material})
	return primitives

func _triangulate(node: Dictionary, face: Dictionary, normal: Vector3, face_index: int) -> PackedInt32Array:
	# Project onto the Newell plane rather than dropping one coordinate: a nonplanar gear
	# quad may have an edge parallel to a principal axis that would collapse in that projection.
	var helper := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	var u := normal.cross(helper).normalized()
	var v := normal.cross(u).normalized()
	# Coincident consecutive corners form a zero-length edge, which does not change the polygon's
	# shape. Collapse them (exact source coordinates) before the intersection test, then map the
	# triangulation back to the original corners so UVs and smoothing still come from the source.
	var ring: Array[int] = []
	for corner: int in face.refs.size():
		if ring.is_empty() or node.vertices[face.refs[ring[-1]].vertex] != node.vertices[face.refs[corner].vertex]:
			ring.append(corner)
	while ring.size() > 1 and node.vertices[face.refs[ring[-1]].vertex] == node.vertices[face.refs[ring[0]].vertex]:
		ring.pop_back()
	if ring.size() < 3:
		_error = R.fail(R.SOURCE_UNSUPPORTED, "An AC3D polygon cannot be triangulated without changing its shape.", "source", "import")
		return PackedInt32Array()
	var origin: Array = node.vertices[face.refs[ring[0]].vertex]
	var points := PackedVector2Array()
	var original: Array = []
	for corner: int in ring:
		var point: Array = node.vertices[face.refs[corner].vertex]
		var dx: float = point[0] - origin[0]
		var dy: float = point[1] - origin[1]
		var dz: float = point[2] - origin[2]
		var projected := [dx*u.x + dy*u.y + dz*u.z, dx*v.x + dy*v.y + dz*v.z]
		points.append(Vector2(projected[0],projected[1]))
		original.append(projected)
	for a: int in points.size():
		var next := (a + 1) % points.size()
		for b: int in range(a + 1, points.size()):
			if points[a] == points[b] and original[a] != original[b]:
				_error = R.fail(R.SOURCE_UNSUPPORTED, "The model loses detail at render precision. Recenter or rescale its source geometry before importing.", "source", "import")
				return PackedInt32Array()
			if b == next or (b + 1) % points.size() == a:
				continue
			_polygon_work += 1
			if _polygon_work > MAX_POLYGON_WORK:
				_error = R.fail(R.SOURCE_LIMIT, "The model exceeds the polygon conversion work limit.", "source", "import")
				return PackedInt32Array()
			if _intersects(original[a], original[next], original[b], original[(b + 1) % points.size()]):
				# A self-intersecting polygon has no defined interior; a fan would invent one.
				_self_intersecting += 1
				if _self_intersecting > MAX_SELF_INTERSECTING:
					_error = R.fail(R.SOURCE_INVALID, "Polygon %s in part \"%s\" has intersecting edges, and the model has too many such surfaces to omit.", "source", "import", [str(face_index),str(node.name)])
				return PackedInt32Array()
	var result := Geometry2D.triangulate_polygon(points)
	if result.size() != (points.size() - 2) * 3:
		_error = R.fail(R.SOURCE_UNSUPPORTED, "An AC3D polygon cannot be triangulated without changing its shape.", "source", "import")
		return PackedInt32Array()
	for index: int in result.size():
		result[index] = ring[result[index]]
	return result

func _material(index: int, texture: String, double_sided: bool) -> int:
	var key := "%d:%s:%s" % [index, texture, double_sided]
	if _materials.has(key):
		return _materials[key]
	if _gltf.materials.size() >= Limits.GLB_MATERIALS:
		_error = R.fail(R.SOURCE_LIMIT, "The model uses more materials than Creator supports.", "source", "import")
		return -1
	var source: Dictionary = _scene.materials[index]
	var pbr := {baseColorFactor = [source.rgb[0],source.rgb[1],source.rgb[2],source.opacity], metallicFactor = 0.0,
		roughnessFactor = clampf(sqrt(2.0 / (float(source.shininess) + 2.0)), 0.04, 1.0)}
	if not texture.is_empty():
		var image := _texture(texture)
		if image < 0:
			return -1
		pbr.baseColorTexture = {index = image}
	var output := {name = source.name, pbrMetallicRoughness = pbr, doubleSided = double_sided, emissiveFactor = source.emission}
	if source.opacity < 1.0:
		output.alphaMode = "BLEND"
	var result: int = _gltf.materials.size()
	if not texture.is_empty() and bool(_texture_alpha.get(str(pbr.baseColorTexture.index), false)):
		output.alphaMode = "BLEND"
	_gltf.materials.append(output)
	_materials[key] = result
	return result

func _texture(name: String) -> int:
	var resolved := _package.archive().resolve(_model.root, "data/" + name)
	if not resolved.ok:
		_error = resolved
		return -1
	var member: String = resolved.value.name
	if _textures.has(member):
		return _textures[member]
	if _textures.size() >= Limits.GLB_IMAGES:
		_error = R.fail(R.SOURCE_LIMIT, "The model uses too many texture images.", "source", "import")
		return -1
	var bytes := _package.archive().read_member(member, Limits.PNG_BYTES, _cancel)
	if not bytes.ok:
		_error = bytes
		return -1
	var image := Images.normalize(bytes.value, _cancel, Limits.PNG_AGGREGATE_PIXELS - _pixels)
	if not image.ok:
		_error = image
		return -1
	_texture_notes.append_array(image.diagnostics)
	_pixels += int(image.value.pixels)
	if _pixels > Limits.PNG_AGGREGATE_PIXELS:
		_error = R.fail(R.SOURCE_LIMIT, "The model exceeds the total texture pixel limit.", "source", "import")
		return -1
	var result: int = _gltf.images.size()
	_gltf.images.append({bufferView = _view(image.value.png), mimeType = "image/png"})
	_gltf.textures.append({source = result, sampler = 0})
	_textures[member] = result
	_texture_alpha[str(result)] = image.value.has_alpha
	_dependencies.append({member = member, sha256 = CreatorBytes.sha256(bytes.value), case_adjusted = resolved.value.case_adjusted})
	return result

func _accessor(values: Array, width: int, bounds := false) -> int:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	var low: Array = []
	var high: Array = []
	for axis: int in width:
		low.append(INF)
		high.append(-INF)
	for at: int in values.size():
		if at % 4096 == 0 and _cancelled():
			return -1
		bytes.encode_float(at * 4, float(values[at]))
		var value := bytes.decode_float(at * 4)
		low[at % width] = minf(low[at % width], value)
		high[at % width] = maxf(high[at % width], value)
	var accessor := {bufferView = _view(bytes), componentType = 5126, count = values.size() / width, type = "VEC%d" % width}
	if bounds:
		accessor.min = low
		accessor.max = high
	var index: int = _gltf.accessors.size()
	_gltf.accessors.append(accessor)
	return index

func _view(bytes: PackedByteArray) -> int:
	if _bin.size() + 3 + bytes.size() > Limits.MODEL_SOURCE_BYTES:
		_error = R.fail(R.SOURCE_LIMIT, "The converted model exceeds the Creator data limit.", "source", "import")
		return -1
	while _bin.size() % 4:
		_bin.append(0)
	var view := {buffer = 0, byteOffset = _bin.size(), byteLength = bytes.size()}
	_bin.append_array(bytes)
	var index: int = _gltf.bufferViews.size()
	_gltf.bufferViews.append(view)
	return index

func _glb() -> PackedByteArray:
	var json := JSON.stringify(_gltf, "", true, true).to_utf8_buffer()
	if json.size() > Limits.GLB_JSON_BYTES:
		_error = R.fail(R.SOURCE_LIMIT, "The converted model metadata exceeds the Creator limit.", "source", "import")
		return PackedByteArray()
	while json.size() % 4:
		json.append(32)
	while _bin.size() % 4:
		_bin.append(0)
	var bytes := PackedByteArray()
	bytes.resize(12)
	bytes.encode_u32(0, 0x46546C67)
	bytes.encode_u32(4, 2)
	bytes.encode_u32(8, 28 + json.size() + _bin.size())
	var header := PackedByteArray()
	header.resize(8)
	header.encode_u32(0, json.size())
	header.encode_u32(4, 0x4E4F534A)
	bytes.append_array(header)
	bytes.append_array(json)
	header.encode_u32(0, _bin.size())
	header.encode_u32(4, 0x004E4942)
	bytes.append_array(header)
	bytes.append_array(_bin)
	return bytes

## Preserve helper/degenerate geometry in a bounded sidecar, separate from rendered surfaces.
func _capture_markers(node: Dictionary, index: int) -> void:
	var faces: Array = []
	var used := {}
	for face: Dictionary in node.surfaces:
		if (int(face.flags) & 15) == 0 and face.refs.size() >= 3:
			continue
		faces.append(face)
		_marker_faces += 1
		_marker_refs += face.refs.size()
		if _marker_faces > 4096 or _marker_refs > 4096:
			_error = R.fail(R.SOURCE_LIMIT, "The model contains too many reference marker surfaces.", "source", "import")
			return
		for ref: Dictionary in face.refs:
			used[ref.vertex] = true
	if faces.is_empty():
		return
	_marker_points += used.size()
	if _marker_points > 4096:
		_error = R.fail(R.SOURCE_LIMIT, "The model contains too many marker points.", "source", "import")
		return
	var vertices: Array = []
	for vertex: int in used:
		vertices.append([vertex, node.vertices[vertex]])
	_markers.append({node = index, name = node.name, parent = node.parent, loc = node.loc, rot = node.rot,
		vertices = vertices, surfaces = faces})

## Double-precision source geometry determines degeneracy. A cancelling bow-tie is not collinear.
func _normal(node: Dictionary, face: Dictionary) -> Vector3:
	if face.refs.size() < 3:
		return Vector3.ZERO
	# Prove collinearity relative to one source point before Newell accumulation:
	# translated collinear faces can leave a nonzero cancellation residue in that sum.
	var origin: Array = node.vertices[face.refs[0].vertex]
	var direction: Array = origin
	var collinear := true
	for ref: Dictionary in face.refs:
		var point: Array = node.vertices[ref.vertex]
		if direction == origin:
			direction = point
		elif not _is_zero(_triangle_cross(origin,direction,point)):
			collinear = false
			break
	if collinear:
		return Vector3.ZERO
	var sum := [0.0,0.0,0.0]
	for index: int in face.refs.size():
		var a: Array = node.vertices[face.refs[index].vertex]
		var b: Array = node.vertices[face.refs[(index + 1) % face.refs.size()].vertex]
		sum[0] += (a[1]-b[1])*(a[2]+b[2])
		sum[1] += (a[2]-b[2])*(a[0]+b[0])
		sum[2] += (a[0]-b[0])*(a[1]+b[1])
	if _is_zero(sum):
		_cancelling_face = true
		return Vector3.ZERO
	var length := sqrt(float(sum[0]*sum[0]+sum[1]*sum[1]+sum[2]*sum[2]))
	return Vector3(sum[0]/length,sum[1]/length,sum[2]/length)

## Numeric zero test: Array equality distinguishes -0.0 from 0.0, which hid exactly
## collinear triangles whose cross product has negative-zero components.
static func _is_zero(value: Array) -> bool:
	return value[0] == 0.0 and value[1] == 0.0 and value[2] == 0.0

static func _cross(a: Array, b: Array, c: Array) -> float:
	return (float(b[0])-float(a[0]))*(float(c[1])-float(a[1])) - (float(b[1])-float(a[1]))*(float(c[0])-float(a[0]))

static func _on_segment(a: Array, b: Array, p: Array) -> bool:
	return p[0] >= minf(a[0],b[0]) and p[0] <= maxf(a[0],b[0]) and p[1] >= minf(a[1],b[1]) and p[1] <= maxf(a[1],b[1])

static func _intersects(a: Array, b: Array, c: Array, d: Array) -> bool:
	var ac := _cross(a,b,c)
	var ad := _cross(a,b,d)
	var ca := _cross(c,d,a)
	var cb := _cross(c,d,b)
	if ac == 0.0 and _on_segment(a,b,c) or ad == 0.0 and _on_segment(a,b,d) or ca == 0.0 and _on_segment(c,d,a) or cb == 0.0 and _on_segment(c,d,b):
		return true
	return ((ac < 0.0 and ad > 0.0) or (ac > 0.0 and ad < 0.0)) and ((ca < 0.0 and cb > 0.0) or (ca > 0.0 and cb < 0.0))

## Compare source and actual float32-rendered orientation before emitting a triangle.
static func _triangle_cross(a: Array, b: Array, c: Array) -> Array:
	var u := [float(b[0])-float(a[0]),float(b[1])-float(a[1]),float(b[2])-float(a[2])]
	var v := [float(c[0])-float(a[0]),float(c[1])-float(a[1]),float(c[2])-float(a[2])]
	return [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func _matrix(node: Dictionary) -> Array:
	var r: Array = node.rot
	return [r[0],r[3],r[6],0.0,r[1],r[4],r[7],0.0,r[2],r[5],r[8],0.0,node.loc[0],node.loc[1],node.loc[2],1.0]

func _cancelled() -> bool:
	if _cancel.is_valid() and bool(_cancel.call()):
		_error = R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", "import")
	return not _error.is_empty()

## Largest axis-aligned extent of a node's local vertices (0 when empty).
static func _extent(node: Dictionary) -> float:
	if node.vertices.is_empty():
		return 0.0
	var low := [INF,INF,INF]
	var high := [-INF,-INF,-INF]
	for point: Array in node.vertices:
		for axis: int in 3:
			low[axis] = minf(low[axis],point[axis])
			high[axis] = maxf(high[axis],point[axis])
	return maxf(high[0]-low[0],maxf(high[1]-low[1],high[2]-low[2]))

func _precision_ok(node: Dictionary) -> bool:
	if node.vertices.is_empty():
		return true
	var low := [INF,INF,INF]
	var high := [-INF,-INF,-INF]
	for point: Array in node.vertices:
		for axis: int in 3:
			low[axis] = minf(low[axis],point[axis])
			high[axis] = maxf(high[axis],point[axis])
	var extent := maxf(high[0]-low[0],maxf(high[1]-low[1],high[2]-low[2]))
	if extent == 0.0:
		return true
	var scratch := PackedByteArray()
	scratch.resize(4)
	for point: Array in node.vertices:
		for axis: int in 3:
			scratch.encode_float(0, point[axis])
			if absf(scratch.decode_float(0)-float(point[axis])) > extent * 0.00001:
				_error = R.fail(R.SOURCE_UNSUPPORTED, "Recenter or rescale this model to preserve its detail at render precision.", "source", "import")
				return false
	return true
