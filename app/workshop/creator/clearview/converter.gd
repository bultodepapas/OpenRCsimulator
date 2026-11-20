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
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "bmp", "gif"]
const SUBSTITUTED_NOTE := "Texture %s is missing; the same-named %s was used."
## Largest float32 vertex rounding accepted, relative to the part's own size (0.1 mm on a 1 m part).
## RN Buccaneer: a 14.5 mm aerial 5 m from its origin rounds by 1.6e-5 of its size, invisibly.
const RENDER_PRECISION := 1.0e-4
## Rounding below 1 µm is invisible on any RC model (Blade mSR: 0.24 µm on a 1.6 mm part 6 m out).
const RENDER_FLOOR_M := 1.0e-6
## Doubled triangle area below extent² × this is invisible (< ~0.03 mm square on a 1 m part).
const NEGLIGIBLE_AREA := 1.0e-9
const NO_TEXTURE := -2
const EXTERNAL_NOTE := "Texture %s points outside the ZIP and is not included. Those parts use their plain colour."
const MERGED_NOTE := "%s static parts were merged to fit the Creator mesh limit. They cannot be bound as moving parts."
const ROTORCRAFT_NAMESPACE := "openrc_clearview_rotorcraft"
const UNSUBDIVIDED_NOTE := "%s parts use AC3D subdivision. Their unsmoothed control shape is shown."
## Share of an AC3D emission kept on a textured surface (as the texture-modulated emissive colour).
## ClearView's weak fixed lighting needed it; under OpenRC's sun the full value overexposes liveries.
const TEXTURED_EMISSION := 0.35
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
var _merged: Array = []
var _shared_materials := 0
var _external := {}
## First pass: node indices that emitted a mesh, set only when they exceed the mesh limit.
var _emitted_over_limit := {}
## Second pass: the emitting nodes from the first pass, used to plan an exact merge.
var _merge_emitting := {}
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
	var result := converter._convert()
	if not converter._emitted_over_limit.is_empty():
		# Only a model whose actual meshes exceed the limit is converted again with merging, so
		# every model that fitted before keeps its exact bytes (Wee Jock: 142 meshes).
		var merged := new()
		merged._package = package
		merged._model = model
		merged._scene = scene.value
		merged._cancel = cancel
		merged._parameters = converter._parameters
		merged._dependencies = [converter._dependencies[0], converter._dependencies[1]]
		merged._merge_emitting = converter._emitted_over_limit
		return merged._convert()
	return result

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
	var merged: Variant = receipt.get("merged_static_parts",0)
	if typeof(merged) in [TYPE_FLOAT,TYPE_INT] and float(merged) == floor(float(merged)) and merged > 0 and merged <= Ac3d.MAX_NODES:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED,MERGED_NOTE,"source","import",[str(int(merged))],R.SEVERITY_WARNING))
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
	var merge := _merge_plan() if not _merge_emitting.is_empty() else {}
	var shared := {}
	var emitting := {}
	for node: Dictionary in _scene.nodes:
		if _cancelled():
			break
		var index: int = _gltf.nodes.size()
		var output := {name = node.name, matrix = _matrix(node), children = node.children}
		_capture_markers(node, index)
		var primitives: Array = []
		if merge.has(index):
			var parent: int = merge[index]
			if not shared.has(parent):
				shared[parent] = {}
			_mesh(node, shared[parent], [node.rot, node.loc])
		elif not frames.value.marked.has(index):
			primitives = _mesh(node)
		if not primitives.is_empty():
			output.mesh = _gltf.meshes.size()
			_gltf.meshes.append({name = node.name, primitives = primitives})
			emitting[index] = true
		_gltf.nodes.append(output)
	if not _error.is_empty():
		return _error
	if _merge_emitting.is_empty() and _gltf.meshes.size() > Limits.GLB_MESHES:
		_emitted_over_limit = emitting
		return R.fail(R.SOURCE_LIMIT, "The model has more than %s meshes. Simplify the model and export it again.", "source", "import", [str(Limits.GLB_MESHES)])
	for parent: int in shared:
		var primitives := _primitives(shared[parent])
		if primitives.is_empty():
			continue
		var owner: String = _scene.nodes[parent].name if parent >= 0 else "Model"
		_gltf.meshes.append({name = owner + " merged parts", primitives = primitives})
		_merged.append({parent = parent, node = {name = owner + " [merged static parts]", mesh = _gltf.meshes.size() - 1}})
	var static_nodes: Array = _gltf.nodes.duplicate(true)
	var static_roots: Array = _gltf.scenes[0].nodes.duplicate()
	var motion := Motion.prepare(_gltf,_scene,frames.value,_cancel)
	if not motion.ok:
		return motion
	_attach_merged()
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
	if not merge.is_empty():
		receipt.merged_static_parts = merge.size()
	_gltf.asset.extras = {openrc_clearview = receipt}
	# Helicopters (ClearView modelType 0) are a visual-only import: no airplane configuration.
	if int(_model.params.model_type) == 0:
		_gltf.asset.extras[ROTORCRAFT_NAMESPACE] = {format = "openrc-clearview-rotorcraft-v1"}
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
		_attach_merged()
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
	if not merge.is_empty():
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, MERGED_NOTE, "source", "import", [str(merge.size())], R.SEVERITY_WARNING))
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

## `into`/`bake`: when the model exceeds the mesh limit, a static leaf part is merged into its
## parent's shared groups with its rigid local transform baked in float64 (see _merge_plan).
func _mesh(node: Dictionary, into = null, bake: Array = []) -> Array:
	# Point/line-only helpers (e.g. COORD_* markers) render nothing; their float64 evidence is
	# retained separately, so render precision does not apply to them.
	if not node.surfaces.any(func(face: Dictionary) -> bool: return (int(face.flags) & 15) == 0 and _corners(node, face) >= 3):
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
	var groups: Dictionary = into if into is Dictionary else {}
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
			groups[material] = {positions = [], normals = [], uv = [], textured = not str(node.texture).is_empty()}
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
				group.positions.append_array(node.vertices[ref.vertex] if bake.is_empty() else _baked(bake, node.vertices[ref.vertex], true))
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
				group.normals.append_array([smooth.x, smooth.y, smooth.z] if bake.is_empty() else _baked(bake, [smooth.x, smooth.y, smooth.z], false))
				group.uv.append_array([ref.uv[0] * node.texrep[0] + node.texoff[0], 1.0 - (ref.uv[1] * node.texrep[1] + node.texoff[1])])
	return [] if into is Dictionary else _primitives(groups)

func _primitives(groups: Dictionary) -> Array:
	var primitives: Array = []
	for material: int in groups:
		var group: Dictionary = groups[material]
		if group.positions.is_empty():
			continue # Every triangle of this material was a dropped sliver.
		var attributes := {POSITION = _accessor(group.positions, 3, true), NORMAL = _accessor(group.normals, 3)}
		if group.textured:
			attributes.TEXCOORD_0 = _accessor(group.uv, 2)
		primitives.append({attributes = attributes, mode = 4, material = material})
	return primitives

## Applies an AC3D local transform (row-major `rot`, then `loc`) in float64. Directions skip `loc`.
static func _baked(transform: Array, value: Array, point: bool) -> Array:
	var r: Array = transform[0]
	var out := [0.0, 0.0, 0.0]
	for row: int in 3:
		out[row] = r[row * 3] * value[0] + r[row * 3 + 1] * value[1] + r[row * 3 + 2] * value[2]
		if point:
			out[row] += float(transform[1][row])
	return out

## Distinct renderable faces: at least one polygon with three distinct corners.
static func _renders(node: Dictionary) -> bool:
	return node.surfaces.any(func(face: Dictionary) -> bool: return (int(face.flags) & 15) == 0 and _corners(node, face) >= 3)

## Second pass only, after the first pass emitted more meshes than the Creator limit: merge
## static leaf parts that actually emitted a mesh (no children, no group-style dotted name, rigid
## rotation) per parent. Returns node index -> parent index, or {} when the result would not fit.
func _merge_plan() -> Dictionary:
	var candidates := {}
	var parents := {}
	for index: int in _merge_emitting:
		var node: Dictionary = _scene.nodes[index]
		if node.children.is_empty() and not "." in str(node.name) and _rigid_rot(node.rot):
			candidates[index] = int(node.parent)
			parents[int(node.parent)] = true
	if _merge_emitting.size() - candidates.size() + parents.size() > Limits.GLB_MESHES \
			or _scene.nodes.size() + parents.size() > Limits.GLB_NODES:
		return {}
	return candidates

static func _rigid_rot(r: Array) -> bool:
	var rows := [Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]), Vector3(r[6], r[7], r[8])]
	for a: int in 3:
		# AC3D prints rotations with six decimals; 1e-5 accepts that rounding, not shear.
		if absf(rows[a].length() - 1.0) > 1.0e-5:
			return false
		for b: int in range(a + 1, 3):
			if absf(rows[a].dot(rows[b])) > 1.0e-5:
				return false
	return rows[0].cross(rows[1]).dot(rows[2]) > 0.0

## Adds the merged-part nodes under their parents. Called again after a rig-fallback restore.
func _attach_merged() -> void:
	for entry: Dictionary in _merged:
		var index: int = _gltf.nodes.size()
		_gltf.nodes.append(entry.node.duplicate(true))
		if entry.parent < 0:
			_gltf.scenes[0].nodes = _gltf.scenes[0].nodes + [index]
		else:
			_gltf.nodes[entry.parent].children = _gltf.nodes[entry.parent].children + [index]

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
	# Consecutive corners that project to the same render point already form a zero-length edge
	# on the GPU (Honey Bee: corners 1e-9 m apart). Collapse them like exact duplicates; a face
	# left with fewer than three corners covers nothing and is counted as zero-area.
	var kept: Array[int] = []
	for slot: int in points.size():
		if kept.is_empty() or points[kept[-1]] != points[slot]:
			kept.append(slot)
	while kept.size() > 1 and points[kept[-1]] == points[kept[0]]:
		kept.pop_back()
	if kept.size() != points.size():
		if kept.size() < 3:
			_dropped += 1
			return PackedInt32Array()
		var narrowed: Array[int] = []
		var narrowed_points := PackedVector2Array()
		var narrowed_original: Array = []
		for slot: int in kept:
			narrowed.append(ring[slot])
			narrowed_points.append(points[slot])
			narrowed_original.append(original[slot])
		ring = narrowed
		points = narrowed_points
		original = narrowed_original
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
	var source: Dictionary = _scene.materials[index]
	var pbr := {baseColorFactor = [source.rgb[0],source.rgb[1],source.rgb[2],source.opacity], metallicFactor = 0.0,
		roughnessFactor = clampf(sqrt(2.0 / (float(source.shininess) + 2.0)), 0.04, 1.0)}
	if not texture.is_empty():
		var image := _texture(texture)
		if image == NO_TEXTURE:
			pass # An external texture absent from the ZIP: the plain material colour, reported once.
		elif image < 0:
			return -1
		else:
			pbr.baseColorTexture = {index = image}
	var output := {name = source.name, pbrMetallicRoughness = pbr, doubleSided = double_sided, emissiveFactor = source.emission}
	# ClearView's fixed-function lighting multiplies the whole lit colour, emission included, by the
	# texture (GL_MODULATE); authors use emission to brighten textured skins. A flat emissive factor
	# would add untextured grey and wash the livery out, so a textured surface's emission is the
	# texture itself, scaled down for OpenRC's physically lit sun.
	if pbr.has("baseColorTexture"):
		var emission: Array = source.emission
		output.emissiveFactor = [float(emission[0]) * TEXTURED_EMISSION, float(emission[1]) * TEXTURED_EMISSION, float(emission[2]) * TEXTURED_EMISSION]
		if float(emission[0]) + float(emission[1]) + float(emission[2]) > 0.0:
			output.emissiveTexture = {index = pbr.baseColorTexture.index}
	if source.opacity < 1.0:
		output.alphaMode = "BLEND"
	if pbr.has("baseColorTexture") and bool(_texture_alpha.get(str(pbr.baseColorTexture.index), false)):
		output.alphaMode = "BLEND"
	if _gltf.materials.size() >= Limits.GLB_MATERIALS:
		# Only past the limit: reuse an identical emitted material (AC names differ, values match).
		for existing: int in _gltf.materials.size():
			var other: Dictionary = _gltf.materials[existing].duplicate(true)
			other.name = output.name
			if other == output:
				_materials[key] = existing
				_shared_materials += 1
				return existing
		_error = R.fail(R.SOURCE_LIMIT, "The model uses more materials than Creator supports.", "source", "import")
		return -1
	var result: int = _gltf.materials.size()
	_gltf.materials.append(output)
	_materials[key] = result
	return result

func _texture(reference: String) -> int:
	# An absolute path names a file on the author's PC (Cobra: "C:/Program Files/.../mapping.jpg").
	# Look for that file name in the model's own data folder; never outside the package.
	var external := reference.is_absolute_path() or ":" in reference or reference.begins_with("\\")
	var name := reference.replace("\\", "/").get_file() if external else reference
	if external and _external.has(name):
		return NO_TEXTURE
	var resolved := {ok = false}
	if not external or Package.Archive.safe_name(name, false):
		resolved = _package.archive().resolve(_model.root, "data/" + name)
	if not resolved.ok and external:
		_external[name] = true
		_texture_notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, EXTERNAL_NOTE, "source", "import", [name], R.SEVERITY_WARNING))
		return NO_TEXTURE
	if not resolved.ok:
		# Repaints sometimes ship the same image under another extension (SU-31 Matador: .bmp
		# referenced, .jpg present). Use it only when exactly one same-named image exists.
		var alternatives: Array = []
		for extension: String in IMAGE_EXTENSIONS:
			var candidate := name.get_basename() + "." + extension
			if candidate.to_lower() == name.to_lower():
				continue
			var found := _package.archive().resolve(_model.root, "data/" + candidate)
			if found.ok:
				alternatives.append(found)
		if alternatives.size() != 1:
			_error = resolved
			return -1
		resolved = alternatives[0]
		_texture_notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, SUBSTITUTED_NOTE, "source", "import",
			[name.get_file(), str(resolved.value.name).get_file()], R.SEVERITY_WARNING))
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

## Distinct corner positions of a face (a 4-reference face over two points renders nothing).
static func _corners(node: Dictionary, face: Dictionary) -> int:
	var unique := {}
	for ref: Dictionary in face.refs:
		unique[node.vertices[ref.vertex]] = true
		if unique.size() >= 3:
			break
	return unique.size()

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
			if absf(scratch.decode_float(0)-float(point[axis])) > maxf(extent * RENDER_PRECISION, RENDER_FLOOR_M):
				_error = R.fail(R.SOURCE_UNSUPPORTED, "Recenter or rescale this model to preserve its detail at render precision.", "source", "import")
				return false
	return true
