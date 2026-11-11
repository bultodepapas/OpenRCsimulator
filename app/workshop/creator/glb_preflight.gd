extends RefCounted
## Strict preflight of an untrusted, self-contained GLB 2.0 model (AC-04). Pure data.
##
## `inspect` validates the whole file and never calls `GLTFDocument`: a file is handed to the engine
## importer only after it passed here. In particular the node graph is proven to be a forest (no
## cycle, no shared child) with an explicit queue, so the importer never walks a cyclic graph.
##
## Admitted subset: one JSON chunk and at most one BIN chunk; one embedded buffer; rigid node trees
## with TRS or shear-free, non-reflecting matrices; triangle-list primitives with POSITION and
## optional NORMAL, TANGENT, TEXCOORD_0/1 and COLOR_0; core metallic-roughness materials; embedded
## PNG textures that pass `png_check.gd` and one real decode at admission. Everything else is refused, including object properties
## this file does not know, so nothing reaches the importer unchecked.
##
## Extensions: `extensionsRequired` must be empty. `ALLOWED_EXTENSIONS` lists the only names
## accepted in `extensionsUsed`; each is one scalar on a material with no index, data or behaviour.
## `extras` are skipped everywhere and never interpreted.
##
## Tolerances: `QUATERNION_TOLERANCE` on the rotation length, `SHEAR_TOLERANCE` on the cosine
## between matrix axes, and `BOUND_SLACK` (two float32 ulps, relative to max(1, |bound|)) between
## POSITION data and the accessor's declared min/max.
##
## Reported `bounds_min`/`bounds_max` come from the measured POSITION extrema (which the check
## proves lie inside the declared min/max) taken through the node transforms of the selected scene.
## Reported triangle and vertex counts cover the selected scene; the ceilings are applied to every
## node of the file plus each unreferenced mesh once, because the importer builds all of them.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const StrictJSON := preload("res://workshop/strict_json.gd")
const PngCheck := preload("res://workshop/creator/png_check.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")

const ALLOWED_EXTENSIONS: Array[String] = ["KHR_materials_emissive_strength", "KHR_materials_ior"]
const QUATERNION_TOLERANCE := 1.0e-4
const SHEAR_TOLERANCE := 1.0e-4
const BOUND_SLACK := 1.0 / 4194304.0

const _MAGIC := 0x46546C67
const _CHUNK_JSON := 0x4E4F534A
const _CHUNK_BIN := 0x004E4942
const _FLOAT32_MAX := 3.4028234663852886e38
## JSON number tokens beyond these make the engine's float parser log a warning; no real export
## writes them (a full-precision double needs 25 characters and an exponent within 308).
const _NUMBER_CHARACTERS := 64
const _NUMBER_EXPONENT := 400
const _FLOAT := 5126
const _UNSIGNED_BYTE := 5121
const _UNSIGNED_SHORT := 5123
const _UNSIGNED_INT := 5125
const _COMPONENT_BYTES := {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
const _TYPE_WIDTH := {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
const _ATTRIBUTES: Array[String] = ["POSITION", "NORMAL", "TANGENT", "TEXCOORD_0", "TEXCOORD_1", "COLOR_0"]
const _SELF_CONTAINED := "Export a self-contained GLB with embedded PNG textures."
const _RIGID := "Export a rigid model: apply modifiers and remove armatures, shape keys and animations."
const _EXTENSION_ADVICE := {
	"KHR_draco_mesh_compression": "Turn off mesh compression in the export settings.",
	"EXT_meshopt_compression": "Turn off mesh compression in the export settings.",
	"KHR_mesh_quantization": "Turn off mesh quantization in the export settings.",
	"KHR_texture_basisu": "Export the textures as PNG.",
	"EXT_texture_webp": "Export the textures as PNG.",
	"KHR_lights_punctual": "Remove the lights from the export.",
}

const _ROOT_KEYS: Array[String] = ["asset", "scene", "scenes", "nodes", "meshes", "materials", "textures", "images",
	"samplers", "accessors", "bufferViews", "buffers", "extensionsUsed", "extensionsRequired", "extensions", "extras"]
const _ASSET_KEYS: Array[String] = ["version", "minVersion", "generator", "copyright", "extensions", "extras"]
const _SCENE_KEYS: Array[String] = ["nodes", "name", "extensions", "extras"]
const _NODE_KEYS: Array[String] = ["name", "children", "mesh", "matrix", "translation", "rotation", "scale",
	"extensions", "extras"]
const _MESH_KEYS: Array[String] = ["primitives", "name", "extensions", "extras"]
const _PRIMITIVE_KEYS: Array[String] = ["attributes", "indices", "material", "mode", "extensions", "extras"]
const _ACCESSOR_KEYS: Array[String] = ["bufferView", "byteOffset", "componentType", "normalized", "count", "type",
	"max", "min", "name", "extensions", "extras"]
const _VIEW_KEYS: Array[String] = ["buffer", "byteOffset", "byteLength", "byteStride", "target", "name",
	"extensions", "extras"]
const _BUFFER_KEYS: Array[String] = ["byteLength", "name", "extensions", "extras"]
const _IMAGE_KEYS: Array[String] = ["bufferView", "mimeType", "name", "extensions", "extras"]
const _TEXTURE_KEYS: Array[String] = ["sampler", "source", "name", "extensions", "extras"]
const _SAMPLER_KEYS: Array[String] = ["magFilter", "minFilter", "wrapS", "wrapT", "name", "extensions", "extras"]
const _MATERIAL_KEYS: Array[String] = ["name", "pbrMetallicRoughness", "normalTexture", "occlusionTexture",
	"emissiveTexture", "emissiveFactor", "alphaMode", "alphaCutoff", "doubleSided", "extensions", "extras"]
const _PBR_KEYS: Array[String] = ["baseColorFactor", "baseColorTexture", "metallicFactor", "roughnessFactor",
	"metallicRoughnessTexture", "extensions", "extras"]


## Validates the whole file. On success `value` is plain data:
## `{json_sha256, counts = {nodes, meshes, primitives, materials, textures, images, accessors,
## buffer_views, mesh_instances, triangles, vertices}, scene, scene_roots: Array[int], bounds_min,
## bounds_max: PackedFloat64Array(3), images: [{index, width, height, pixels, has_alpha}],
## node_names: Array[String], has_uv, all_uv, materials: [{name, has_base_color_texture,
## base_color_image}], extensions_used: Array[String]}`.
## `triangles`, `vertices` and `mesh_instances` count the selected scene, once per instancing node.
static func inspect(bytes: PackedByteArray) -> Dictionary:
	var scan := Scan.new()
	if scan.run(bytes):
		return R.ok(scan.report)
	return scan.failure


class Scan extends RefCounted:
	var failure := {}
	var report := {}
	var bytes: PackedByteArray
	var root := {}
	var json_size := 0
	var has_bin := false
	var bin_at := 0
	var bin_size := 0
	var buffer_bytes := 0
	var used_extensions: Array[String] = []
	## Per buffer view: `{at, size, stride, target}`; `at` is an offset into the file.
	var views: Array[Dictionary] = []
	## Per accessor: `{at, count, component, width, normalized, tight, step, element, strided, target,
	## low, high}`; `at` is an offset into the file, `low`/`high` the declared min/max (or empty).
	var accessors: Array[Dictionary] = []
	## Per image: the `png_check` header value plus `view`.
	var images: Array[Dictionary] = []
	var sampler_count := 0
	var texture_sources := PackedInt32Array()
	var materials: Array[Dictionary] = []
	## Per mesh: `{triangles, vertices, primitives: [{position, indices, floats, vertices, uv}]}`.
	var meshes: Array[Dictionary] = []
	var primitive_count := 0
	## Triangles and vertices of every surface in the file, each counted once.
	var defined_triangles := 0
	var defined_vertices := 0
	var node_names: Array[String] = []
	var node_mesh := PackedInt32Array()
	var node_parent := PackedInt32Array()
	var node_children: Array[PackedInt32Array] = []
	## Local transforms as 3 x 4 row-major affine matrices.
	var node_local: Array[PackedFloat64Array] = []
	var scene_index := 0
	var scene_roots: Array[int] = []
	## Measured POSITION boxes per accessor: `[low, high]`.
	var boxes := {}
	var finite_checked := {}
	var index_highest := {}

	func run(source: PackedByteArray) -> bool:
		bytes = source
		return _container() and _json() and _root() and _extensions() and _buffers() and _views() \
			and _accessors() and _image_headers() and _textures() and _materials() and _meshes() \
			and _nodes() and _graph() and _scenes() and _budget() and _mesh_data() and _image_data() \
			and _summary()

	# --- container and JSON ---------------------------------------------------------------

	func _container() -> bool:
		var size := bytes.size()
		if size > Limits.MODEL_SOURCE_BYTES:
			return _limit("The model file is larger than %s MiB. Reduce its detail or texture size and export it again.",
				"", [str(Limits.MODEL_SOURCE_BYTES / Limits.MIB)])
		if size < 20 or bytes.decode_u32(0) != _MAGIC:
			return _invalid("The file is not a binary glTF model. Export the model as glTF Binary (.glb).")
		if bytes.decode_u32(4) != 2:
			return _unsupported("The model uses glTF container version %s. Export it as glTF 2.0 Binary (.glb).", "",
				[str(bytes.decode_u32(4))])
		if bytes.decode_u32(8) != size:
			return _invalid("The model file is damaged: its declared length does not match its size.")
		json_size = bytes.decode_u32(12)
		if bytes.decode_u32(16) != _CHUNK_JSON:
			return _invalid("The model file is damaged: it does not start with its JSON chunk.")
		if json_size > Limits.GLB_JSON_BYTES:
			return _limit("The model description is larger than %s MiB. Simplify the model and export it again.", "",
				[str(Limits.GLB_JSON_BYTES / Limits.MIB)])
		if json_size == 0 or json_size % 4 != 0 or json_size > size - 20:
			return _invalid("The model file is damaged: its JSON chunk has an invalid length.")
		var next := 20 + json_size
		if next == size:
			return true
		if size - next < 8:
			return _invalid("The model file is damaged: stray bytes follow its JSON chunk.")
		var length := bytes.decode_u32(next)
		var kind := bytes.decode_u32(next + 4)
		if kind == _CHUNK_JSON:
			return _invalid("The model file is damaged: it holds more than one JSON chunk.")
		if kind != _CHUNK_BIN:
			return _unsupported("The model file holds a chunk of an unknown type. " + _SELF_CONTAINED)
		if length % 4 != 0 or length > size - next - 8:
			return _invalid("The model file is damaged: its binary chunk has an invalid length.")
		var after := next + 8 + length
		if after != size:
			if size - after >= 8 and bytes.decode_u32(after + 4) not in [_CHUNK_JSON, _CHUNK_BIN]:
				return _unsupported("The model file holds a chunk of an unknown type. " + _SELF_CONTAINED)
			return _invalid("The model file is damaged: data follows its binary chunk.")
		has_bin = true
		bin_at = next + 8
		bin_size = length
		return true

	func _json() -> bool:
		var text := bytes.slice(20, 20 + json_size)
		var problem := _text_problem(text)
		if not problem.is_empty():
			return _invalid("The model description cannot be read: %s.", "", [problem])
		var parsed: Dictionary = StrictJSON.parse(text, Limits.GLB_JSON_BYTES, Limits.JSON_DEPTH, Limits.JSON_VALUES)
		if not parsed.ok:
			var reason := str(parsed.errors[0])
			if reason.begins_with("JSON nesting or node limit"):
				return _limit("The model description is too large or too deeply nested. Simplify the model and export it again.")
			return _invalid("The model description is not valid JSON: %s", "", [reason])
		if typeof(parsed.data) != TYPE_DICTIONARY:
			return _invalid("The model description is not a JSON object.")
		root = parsed.data
		report.json_sha256 = CreatorBytes.sha256(text)
		return true

	func _root() -> bool:
		for key: String in ["animations", "skins"]:
			if root.has(key):
				return _unsupported("The model holds %s, which are not supported. " + _RIGID, key, [key])
		if root.has("cameras"):
			return _unsupported("The model holds cameras, which are not supported. Remove them from the export.", "cameras")
		if not _only(root, _ROOT_KEYS, ""):
			return false
		var asset: Variant = root.get("asset")
		if not asset is Dictionary:
			return _invalid("The model has no asset description.", "asset")
		if not _only(asset, _ASSET_KEYS, "asset"):
			return false
		if typeof(asset.get("version")) != TYPE_STRING or typeof(asset.get("minVersion", "")) != TYPE_STRING:
			return _invalid("The model does not state its glTF version.", "asset/version")
		if asset.version != "2.0" or asset.get("minVersion", "2.0") != "2.0":
			return _unsupported("The model uses glTF version %s. Export it as glTF 2.0 Binary (.glb).", "asset/version",
				[str(asset.get("minVersion", asset.version))])
		for key: String in ["generator", "copyright"]:
			if asset.has(key) and typeof(asset[key]) != TYPE_STRING:
				return _invalid("The model has an invalid asset description.", "asset/" + key)

		var required: Variant = root.get("extensionsRequired", [])
		if not required is Array:
			return _invalid("The model has an invalid list of required extensions.", "extensionsRequired")
		if not (required as Array).is_empty():
			var first: Variant = required[0]
			if typeof(first) != TYPE_STRING:
				return _invalid("The model has an invalid list of required extensions.", "extensionsRequired")
			return _extension_refused(first, "extensionsRequired")
		var used: Variant = root.get("extensionsUsed", [])
		if not used is Array:
			return _invalid("The model has an invalid list of extensions.", "extensionsUsed")
		for entry: Variant in used:
			if typeof(entry) != TYPE_STRING or entry in used_extensions:
				return _invalid("The model has an invalid list of extensions.", "extensionsUsed")
			if entry not in ALLOWED_EXTENSIONS:
				return _extension_refused(entry, "extensionsUsed")
			used_extensions.append(entry)
		return true

	## Finds every `extensions` object in the file. Only a material may carry one, only with
	## allow-listed names that `extensionsUsed` declares. `extras` subtrees are not visited.
	func _extensions() -> bool:
		# Tags: 0 elsewhere, 1 the top-level `materials` array, 2 one of its materials, 3 the root.
		var pending: Array = [[root, 3]]
		while not pending.is_empty():
			var entry: Array = pending.pop_back()
			var node: Variant = entry[0]
			var tag := int(entry[1])
			if node is Array:
				for child: Variant in node:
					if child is Dictionary or child is Array:
						pending.append([child, 2 if tag == 1 else 0])
				continue
			for key: Variant in node:
				var child: Variant = node[key]
				if key == "extras":
					continue
				if key == "extensions":
					if not child is Dictionary:
						return _invalid("The model has an invalid extensions object.", "extensions")
					for name: Variant in child:
						if tag != 2 or name not in ALLOWED_EXTENSIONS:
							return _extension_refused(str(name), "extensions")
						if name not in used_extensions:
							return _invalid("The model uses the extension %s without declaring it.", "extensionsUsed", [name])
					continue
				if child is Dictionary or child is Array:
					pending.append([child, 1 if tag == 3 and key == "materials" else 0])
		return true

	# --- buffers, views, accessors ----------------------------------------------------------

	func _buffers() -> bool:
		var list := _items("buffers", Limits.JSON_VALUES)
		if not failure.is_empty():
			return false
		if list.size() > 1:
			return _unsupported("The model uses more than one data buffer. " + _SELF_CONTAINED, "buffers")
		if list.is_empty():
			if has_bin:
				return _invalid("The model file holds binary data that no buffer describes.", "buffers")
			return true
		var buffer: Dictionary = list[0]
		if buffer.has("uri"):
			return _unsupported("The model refers to an external or inline data file. " + _SELF_CONTAINED, "buffers/0/uri")
		if not _only(buffer, _BUFFER_KEYS, "buffers/0") or not _named(buffer, "buffers/0"):
			return false
		if not has_bin:
			return _invalid("The model describes a data buffer that the file does not contain.", "buffers/0")
		buffer_bytes = _whole(buffer.get("byteLength"), bin_size)
		# The BIN chunk may only add the padding that aligns it to four bytes.
		if buffer_bytes < 1 or bin_size - buffer_bytes > 3:
			return _invalid("The model's data buffer does not match the binary data in the file.", "buffers/0/byteLength")
		return true

	func _views() -> bool:
		var list := _items("bufferViews", Limits.GLB_BUFFER_VIEWS)
		if not failure.is_empty():
			return false
		for index: int in list.size():
			var view: Dictionary = list[index]
			var field := "bufferViews/%d" % index
			if not _only(view, _VIEW_KEYS, field) or not _named(view, field):
				return false
			# Offsets are whole numbers below 2^25 here, so sums cannot overflow 64-bit ints.
			if _whole(view.get("buffer"), 0) != 0 or buffer_bytes == 0:
				return _invalid("A buffer view refers to a buffer that does not exist.", field + "/buffer")
			var offset := _whole(view.get("byteOffset", 0), buffer_bytes)
			var length := _whole(view.get("byteLength"), buffer_bytes)
			if offset < 0 or length < 1 or offset + length > buffer_bytes:
				return _invalid("A buffer view reaches outside the model's data.", field)
			var stride := 0
			if view.has("byteStride"):
				stride = _whole(view.byteStride, 252)
				if stride < 4 or stride % 4 != 0:
					return _invalid("A buffer view has an invalid byte stride.", field + "/byteStride")
			var target := 0
			if view.has("target"):
				target = _whole(view.target, 65535)
				if target != 34962 and target != 34963:
					return _invalid("A buffer view has an invalid target.", field + "/target")
			views.append({at = bin_at + offset, offset = offset, size = length, stride = stride, target = target})
		return true

	func _accessors() -> bool:
		var list := _items("accessors", Limits.GLB_ACCESSORS)
		if not failure.is_empty():
			return false
		for index: int in list.size():
			var accessor: Dictionary = list[index]
			var field := "accessors/%d" % index
			if accessor.has("sparse"):
				return _unsupported("The model uses sparse accessors, which are not supported. " + _RIGID, field + "/sparse")
			if not _only(accessor, _ACCESSOR_KEYS, field) or not _named(accessor, field):
				return false
			if not accessor.has("bufferView"):
				return _unsupported("The model has an accessor without data. " + _SELF_CONTAINED, field)
			var view_index := _whole(accessor.bufferView, views.size() - 1)
			if view_index < 0:
				return _invalid("An accessor refers to a buffer view that does not exist.", field + "/bufferView")
			var view: Dictionary = views[view_index]
			var component := _whole(accessor.get("componentType"), 65535)
			if not _COMPONENT_BYTES.has(component):
				return _invalid("An accessor has an invalid component type.", field + "/componentType")
			var type: Variant = accessor.get("type")
			if typeof(type) == TYPE_STRING and type in ["MAT2", "MAT3", "MAT4"]:
				return _unsupported("The model uses matrix accessors, which are not supported. " + _RIGID, field + "/type")
			if typeof(type) != TYPE_STRING or not _TYPE_WIDTH.has(type):
				return _invalid("An accessor has an invalid type.", field + "/type")
			var normalized: Variant = accessor.get("normalized", false)
			if typeof(normalized) != TYPE_BOOL or (normalized and (component == _FLOAT or component == _UNSIGNED_INT)):
				return _invalid("An accessor has an invalid normalized flag.", field + "/normalized")
			var width := int(_TYPE_WIDTH[type])
			var unit := int(_COMPONENT_BYTES[component])
			var element := unit * width
			var size := int(view.size)
			var count := _whole(accessor.get("count"), size)
			var offset := _whole(accessor.get("byteOffset", 0), size)
			if count < 1 or offset < 0:
				return _invalid("An accessor has an invalid count or offset.", field)
			if offset % unit != 0 or (int(view.offset) + offset) % unit != 0:
				return _invalid("An accessor is not aligned to its component size.", field + "/byteOffset")
			var stride := int(view.stride)
			if stride != 0 and stride < element:
				return _invalid("A buffer view's byte stride is smaller than its elements.", field)
			var step := stride if stride != 0 else element
			# count <= 2^25 and step <= 252: the product stays far below 2^63.
			if offset + step * (count - 1) + element > size:
				return _invalid("An accessor reaches outside its buffer view.", field + "/count")
			var low := PackedFloat64Array()
			var high := PackedFloat64Array()
			if accessor.has("min") or accessor.has("max"):
				low = _numbers(accessor.get("min"), width)
				high = _numbers(accessor.get("max"), width)
				if (accessor.has("min") and low.is_empty()) or (accessor.has("max") and high.is_empty()):
					return _invalid("An accessor has invalid min or max values.", field)
			accessors.append({at = int(view.at) + offset, count = count, component = component, width = width,
				normalized = normalized, tight = step == element, step = step, element = element,
				strided = stride != 0, target = int(view.target), low = low, high = high})
		return true

	# --- images, textures, materials ----------------------------------------------------------

	## IHDR-only pass: every image is bounded and the aggregate budget enforced before any
	## image data is inflated.
	func _image_headers() -> bool:
		var list := _items("images", Limits.GLB_IMAGES)
		if not failure.is_empty():
			return false
		var total := 0
		for index: int in list.size():
			var image: Dictionary = list[index]
			var field := "images/%d" % index
			if image.has("uri"):
				return _unsupported("The model refers to an external or inline image file. " + _SELF_CONTAINED, field + "/uri")
			if not _only(image, _IMAGE_KEYS, field) or not _named(image, field):
				return false
			var view_index := _whole(image.get("bufferView"), views.size() - 1)
			if view_index < 0:
				return _invalid("An image refers to a buffer view that does not exist.", field + "/bufferView")
			if int(views[view_index].stride) != 0:
				return _invalid("An image buffer view has a byte stride.", field + "/bufferView")
			if typeof(image.get("mimeType")) != TYPE_STRING:
				return _invalid("An embedded image does not state its type.", field + "/mimeType")
			# The declared type decides; the bytes are never sniffed for another format.
			if image.mimeType != "image/png":
				return _unsupported("The model embeds an image of type %s. " + _SELF_CONTAINED, field + "/mimeType",
					[image.mimeType])
			var head: Dictionary = PngCheck.header(_view_bytes(view_index))
			if not head.ok:
				return _forward(head, field)
			var info: Dictionary = head.value
			info.view = view_index
			total += PngCheck.decoded_pixels(info)
			if total > Limits.PNG_AGGREGATE_PIXELS:
				return _limit("The model's textures hold more than %s pixels in total. Reduce the texture sizes.", "images",
					[str(Limits.PNG_AGGREGATE_PIXELS)])
			images.append(info)
		return true

	func _textures() -> bool:
		var samplers := _items("samplers", Limits.JSON_VALUES)
		if not failure.is_empty():
			return false
		for index: int in samplers.size():
			var sampler: Dictionary = samplers[index]
			var field := "samplers/%d" % index
			if not _only(sampler, _SAMPLER_KEYS, field) or not _named(sampler, field):
				return false
			if not _one_of(sampler, "magFilter", [9728, 9729]) \
					or not _one_of(sampler, "minFilter", [9728, 9729, 9984, 9985, 9986, 9987]) \
					or not _one_of(sampler, "wrapS", [33071, 33648, 10497]) \
					or not _one_of(sampler, "wrapT", [33071, 33648, 10497]):
				return _invalid("A texture sampler has an invalid filter or wrap mode.", field)
		sampler_count = samplers.size()
		var textures := _items("textures", Limits.JSON_VALUES)
		if not failure.is_empty():
			return false
		for index: int in textures.size():
			var texture: Dictionary = textures[index]
			var field := "textures/%d" % index
			if not _only(texture, _TEXTURE_KEYS, field) or not _named(texture, field):
				return false
			var source := _whole(texture.get("source"), images.size() - 1)
			if source < 0:
				return _invalid("A texture refers to an image that does not exist.", field + "/source")
			if texture.has("sampler") and _whole(texture.sampler, sampler_count - 1) < 0:
				return _invalid("A texture refers to a sampler that does not exist.", field + "/sampler")
			texture_sources.append(source)
		return true

	func _materials() -> bool:
		var list := _items("materials", Limits.GLB_MATERIALS)
		if not failure.is_empty():
			return false
		for index: int in list.size():
			var material: Dictionary = list[index]
			var field := "materials/%d" % index
			if not _only(material, _MATERIAL_KEYS, field) or not _named(material, field):
				return false
			var base_texture := -1
			if material.has("pbrMetallicRoughness"):
				var pbr: Variant = material.pbrMetallicRoughness
				if not pbr is Dictionary:
					return _invalid("A material has invalid surface settings.", field + "/pbrMetallicRoughness")
				if not _only(pbr, _PBR_KEYS, field + "/pbrMetallicRoughness"):
					return false
				if not _unit_numbers(pbr, "baseColorFactor", 4) or not _unit_number(pbr, "metallicFactor") \
						or not _unit_number(pbr, "roughnessFactor"):
					return _invalid("A material has a colour or factor outside 0 to 1.", field + "/pbrMetallicRoughness")
				if pbr.has("baseColorTexture"):
					base_texture = _texture_info(pbr.baseColorTexture, field + "/pbrMetallicRoughness/baseColorTexture", "")
				if failure.is_empty() and pbr.has("metallicRoughnessTexture"):
					_texture_info(pbr.metallicRoughnessTexture, field + "/pbrMetallicRoughness/metallicRoughnessTexture", "")
			if failure.is_empty() and material.has("normalTexture"):
				_texture_info(material.normalTexture, field + "/normalTexture", "scale")
			if failure.is_empty() and material.has("occlusionTexture"):
				_texture_info(material.occlusionTexture, field + "/occlusionTexture", "strength")
			if failure.is_empty() and material.has("emissiveTexture"):
				_texture_info(material.emissiveTexture, field + "/emissiveTexture", "")
			if not failure.is_empty():
				return false
			if not _unit_numbers(material, "emissiveFactor", 3):
				return _invalid("A material has a colour or factor outside 0 to 1.", field + "/emissiveFactor")
			if material.has("alphaMode") and (typeof(material.alphaMode) != TYPE_STRING
					or material.alphaMode not in ["OPAQUE", "MASK", "BLEND"]):
				return _invalid("A material has an invalid alpha mode.", field + "/alphaMode")
			if material.has("alphaCutoff") and (not _is_number(material.alphaCutoff) or float(material.alphaCutoff) < 0.0):
				return _invalid("A material has an invalid alpha cutoff.", field + "/alphaCutoff")
			if material.has("doubleSided") and typeof(material.doubleSided) != TYPE_BOOL:
				return _invalid("A material has an invalid double-sided flag.", field + "/doubleSided")
			if not _material_extensions(material.get("extensions", {}), field + "/extensions"):
				return false
			materials.append({name = str(material.get("name", "")), has_base_color_texture = base_texture >= 0,
				base_color_image = texture_sources[base_texture] if base_texture >= 0 else -1})
		return true

	## The allow-listed extensions are single scalars; anything else inside them is refused.
	func _material_extensions(extensions: Dictionary, field: String) -> bool:
		for name: String in extensions:
			var body: Variant = extensions[name]
			var key := "emissiveStrength" if name == "KHR_materials_emissive_strength" else "ior"
			if not body is Dictionary:
				return _invalid("A material has an invalid %s extension.", field, [name])
			if not _only(body, [key, "extras"], field + "/" + name):
				return false
			if not body.has(key):
				continue
			if not _is_number(body[key]):
				return _invalid("A material has an invalid %s extension.", field, [name])
			var number := float(body[key])
			if number < 0.0 or (key == "ior" and number != 0.0 and number < 1.0):
				return _invalid("A material has an invalid %s extension.", field, [name])
		return true

	## Returns the texture index, or -1 after recording a failure.
	func _texture_info(info: Variant, field: String, scalar: String) -> int:
		if not info is Dictionary:
			_invalid("A material has an invalid texture reference.", field)
			return -1
		var allowed: Array[String] = ["index", "texCoord", "extensions", "extras"]
		if not scalar.is_empty():
			allowed.append(scalar)
		if not _only(info, allowed, field):
			return -1
		var index := _whole(info.get("index"), texture_sources.size() - 1)
		if index < 0:
			_invalid("A material refers to a texture that does not exist.", field + "/index")
			return -1
		if info.has("texCoord"):
			var set_index := _whole(info.texCoord, 65535)
			if set_index < 0:
				_invalid("A material has an invalid texture coordinate set.", field + "/texCoord")
				return -1
			if set_index > 1:
				_unsupported("A material uses texture coordinate set %s; only sets 0 and 1 are supported. "
					+ "Use the first UV map and export again.", field + "/texCoord", [str(set_index)])
				return -1
		if not scalar.is_empty() and info.has(scalar) and not _is_number(info[scalar]):
			_invalid("A material has an invalid texture reference.", field + "/" + scalar)
			return -1
		return index

	# --- meshes -----------------------------------------------------------------------------------

	## Structure only: attribute kinds, counts and index layout. No vertex data is read here.
	func _meshes() -> bool:
		var list := _items("meshes", Limits.GLB_MESHES)
		if not failure.is_empty():
			return false
		for index: int in list.size():
			var mesh: Dictionary = list[index]
			var field := "meshes/%d" % index
			if mesh.has("weights"):
				return _unsupported("The model uses shape keys (morph targets), which are not supported. " + _RIGID,
					field + "/weights")
			if not _only(mesh, _MESH_KEYS, field) or not _named(mesh, field):
				return false
			var primitives: Variant = mesh.get("primitives")
			if not primitives is Array or (primitives as Array).is_empty():
				return _invalid("A mesh has no geometry.", field + "/primitives")
			primitive_count += (primitives as Array).size()
			if primitive_count > Limits.GLB_PRIMITIVES:
				return _limit("The model has more than %s mesh surfaces. Join meshes or reduce the material count.",
					"meshes", [str(Limits.GLB_PRIMITIVES)])
			var summary := {triangles = 0, vertices = 0, primitives = []}
			for slot: int in (primitives as Array).size():
				if not _primitive(primitives[slot], "%s/primitives/%d" % [field, slot], summary):
					return false
			meshes.append(summary)
		return true

	func _primitive(primitive: Variant, field: String, summary: Dictionary) -> bool:
		if not primitive is Dictionary:
			return _invalid("A mesh has an invalid surface.", field)
		if primitive.has("targets"):
			return _unsupported("The model uses shape keys (morph targets), which are not supported. " + _RIGID,
				field + "/targets")
		if not _only(primitive, _PRIMITIVE_KEYS, field):
			return false
		var mode := _whole(primitive.get("mode", 4), 6)
		if mode < 0:
			return _invalid("A mesh surface has an invalid drawing mode.", field + "/mode")
		if mode != 4:
			return _unsupported("A mesh surface is made of points, lines, strips or fans. Triangulate the mesh and export again.",
				field + "/mode")
		if primitive.has("material") and _whole(primitive.material, materials.size() - 1) < 0:
			return _invalid("A mesh surface refers to a material that does not exist.", field + "/material")
		var attributes: Variant = primitive.get("attributes")
		if not attributes is Dictionary or not (attributes as Dictionary).has("POSITION"):
			return _invalid("A mesh surface has no vertex positions.", field + "/attributes")
		var vertices := -1
		var floats := PackedInt32Array()
		for name: String in attributes:
			var path := "%s/attributes/%s" % [field, name]
			if name not in _ATTRIBUTES:
				if name.begins_with("JOINTS_") or name.begins_with("WEIGHTS_"):
					return _unsupported("The model is skinned (%s). " + _RIGID, path, [name])
				return _unsupported("A mesh surface uses the vertex attribute %s, which is not supported. "
					+ "Remove extra UV maps, colour layers and custom attributes and export again.", path, [name])
			var accessor_index := _whole(attributes[name], accessors.size() - 1)
			if accessor_index < 0:
				return _invalid("A mesh surface refers to an accessor that does not exist.", path)
			var accessor: Dictionary = accessors[accessor_index]
			if int(accessor.target) == 34963:
				return _invalid("A mesh surface reads vertex data from an index buffer view.", path)
			var kind := _attribute_kind(name, accessor)
			if kind == 2:
				return _unsupported("A mesh surface stores %s as integers. Export without mesh quantization.", path, [name])
			if kind != 0:
				return _invalid("A mesh surface has %s data of the wrong type.", path, [name])
			# glTF pads every vertex attribute element to four bytes (3 or 6 byte colours need a stride).
			if not bool(accessor.strided) and int(accessor.element) % 4 != 0:
				return _invalid("A mesh surface has %s data that is not padded to four bytes.", path, [name])
			if vertices >= 0 and int(accessor.count) != vertices:
				return _invalid("A mesh surface has vertex attributes of different lengths.", path)
			vertices = int(accessor.count)
			if name != "POSITION" and int(accessor.component) == _FLOAT:
				floats.append(accessor_index)
		var position := _whole(attributes.POSITION, accessors.size() - 1)
		if (accessors[position].low as PackedFloat64Array).is_empty() or (accessors[position].high as PackedFloat64Array).is_empty():
			return _invalid("A mesh surface does not declare the bounds of its vertex positions.", field + "/attributes/POSITION")
		for axis: int in 3:
			if accessors[position].low[axis] > accessors[position].high[axis]:
				return _invalid("A mesh surface declares inverted bounds for its vertex positions.",
					field + "/attributes/POSITION")
		var indices := -1
		var corners := vertices
		if primitive.has("indices"):
			indices = _whole(primitive.indices, accessors.size() - 1)
			if indices < 0:
				return _invalid("A mesh surface refers to an accessor that does not exist.", field + "/indices")
			var accessor: Dictionary = accessors[indices]
			if int(accessor.width) != 1 or bool(accessor.normalized) or bool(accessor.strided) or int(accessor.target) == 34962 \
					or int(accessor.component) not in [_UNSIGNED_BYTE, _UNSIGNED_SHORT, _UNSIGNED_INT]:
				return _invalid("A mesh surface has index data of the wrong type.", field + "/indices")
			corners = int(accessor.count)
		if corners % 3 != 0:
			return _invalid("A mesh surface does not hold whole triangles.", field)
		summary.triangles += corners / 3
		summary.vertices += vertices
		# Each surface is built by the importer at least once: bound the file before reading data.
		defined_triangles += corners / 3
		defined_vertices += vertices
		if not _within_budget(defined_triangles, defined_vertices):
			return false
		summary.primitives.append({position = position, indices = indices, floats = floats, vertices = vertices,
			uv = attributes.has("TEXCOORD_0")})
		return true

	## 0: accepted, 1: illegal for this attribute, 2: legal glTF outside the admitted subset.
	func _attribute_kind(name: String, accessor: Dictionary) -> int:
		var component := int(accessor.component)
		var width := int(accessor.width)
		var packed := bool(accessor.normalized) and (component == _UNSIGNED_BYTE or component == _UNSIGNED_SHORT)
		match name:
			"POSITION", "NORMAL":
				return 0 if component == _FLOAT and width == 3 else 1
			"TANGENT":
				return 0 if component == _FLOAT and width == 4 else 1
			"COLOR_0":
				return 0 if (component == _FLOAT or packed) and (width == 3 or width == 4) else 1
		if width != 2:
			return 1
		return 0 if component == _FLOAT else (2 if packed else 1)

	# --- nodes, graph, scenes -------------------------------------------------------------------------

	func _nodes() -> bool:
		var list := _items("nodes", Limits.GLB_NODES)
		if not failure.is_empty():
			return false
		var count := list.size()
		node_parent.resize(count)
		node_parent.fill(-1)
		for index: int in count:
			var node: Dictionary = list[index]
			var field := "nodes/%d" % index
			if node.has("skin") or node.has("weights"):
				return _unsupported("The model uses armatures or shape keys, which are not supported. " + _RIGID, field)
			if node.has("camera"):
				return _unsupported("The model holds cameras, which are not supported. Remove them from the export.", field)
			if not _only(node, _NODE_KEYS, field) or not _named(node, field):
				return false
			node_names.append(str(node.get("name", "")))
			var mesh := -1
			if node.has("mesh"):
				mesh = _whole(node.mesh, meshes.size() - 1)
				if mesh < 0:
					return _invalid("A node refers to a mesh that does not exist.", field + "/mesh")
			node_mesh.append(mesh)
			var children := PackedInt32Array()
			if node.has("children"):
				if not node.children is Array:
					return _invalid("A node has an invalid list of children.", field + "/children")
				for entry: Variant in node.children:
					var child := _whole(entry, count - 1)
					if child < 0:
						return _invalid("A node refers to a child that does not exist.", field + "/children")
					if child == index:
						return _invalid("A node is its own child.", field + "/children")
					if node_parent[child] == index:
						return _invalid("A node lists the same child twice.", field + "/children")
					if node_parent[child] != -1:
						return _invalid("A node has more than one parent.", "nodes/%d" % child)
					node_parent[child] = index
					children.append(child)
			node_children.append(children)
			if not _transform(node, field):
				return false
		return true

	## Every node has at most one parent here, so the graph is a forest exactly when a walk from
	## the parentless nodes reaches all of them. Uses a queue; depth 1 is a parentless node.
	func _graph() -> bool:
		var count := node_parent.size()
		var depth := PackedInt32Array()
		depth.resize(count)
		var queue := PackedInt32Array()
		for index: int in count:
			if node_parent[index] == -1:
				queue.append(index)
				depth[index] = 1
		var head := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			if depth[index] > Limits.GLB_DEPTH:
				return _limit("The model's node tree is deeper than %s levels. Flatten the hierarchy and export again.",
					"nodes/%d" % index, [str(Limits.GLB_DEPTH)])
			for child: int in node_children[index]:
				depth[child] = depth[index] + 1
				queue.append(child)
		if queue.size() != count:
			return _invalid("The model's node tree contains a loop.", "nodes")
		return true

	func _scenes() -> bool:
		var list := _items("scenes", Limits.JSON_VALUES)
		if not failure.is_empty():
			return false
		if list.is_empty():
			return _invalid("The model has no scene. Export the model with its objects selected or visible.", "scenes")
		# Without a default scene the engine importer picks one itself and logs a warning on
		# every build. Exporters write the key; a file without it is asked for again.
		if not root.has("scene"):
			return _unsupported("The model does not say which scene to show. Export it again as a self-contained GLB from your modelling tool.", "scene")
		scene_index = _whole(root.get("scene", 0), list.size() - 1)
		if scene_index < 0:
			return _invalid("The model selects a scene that does not exist.", "scene")
		for index: int in list.size():
			var scene: Dictionary = list[index]
			var field := "scenes/%d" % index
			if not _only(scene, _SCENE_KEYS, field) or not _named(scene, field):
				return false
			var roots: Variant = scene.get("nodes", [])
			if not roots is Array:
				return _invalid("A scene has an invalid list of nodes.", field + "/nodes")
			var seen := {}
			for entry: Variant in roots:
				var node := _whole(entry, node_parent.size() - 1)
				if node < 0:
					return _invalid("A scene refers to a node that does not exist.", field + "/nodes")
				if seen.has(node):
					return _invalid("A scene lists the same node twice.", field + "/nodes")
				if node_parent[node] != -1:
					return _invalid("A scene lists a node that is another node's child.", field + "/nodes")
				seen[node] = true
				if index == scene_index:
					scene_roots.append(node)
		if scene_roots.is_empty():
			return _invalid("The model's scene is empty. Export the model with its objects selected or visible.",
				"scenes/%d" % scene_index)
		return true

	func _transform(node: Dictionary, field: String) -> bool:
		var has_trs := node.has("translation") or node.has("rotation") or node.has("scale")
		var matrix := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
		if node.has("matrix"):
			if has_trs:
				return _invalid("A node has both a matrix and separate translation, rotation or scale.", field)
			var values := _numbers(node.matrix, 16)
			if values.is_empty():
				return _invalid("A node has an invalid matrix.", field + "/matrix")
			# glTF matrices are column-major.
			for row: int in 3:
				for column: int in 4:
					matrix[row * 4 + column] = values[column * 4 + row]
			if values[3] != 0.0 or values[7] != 0.0 or values[11] != 0.0 or values[15] != 1.0 or not _is_rigid_scale(matrix):
				return _unsupported("A node's matrix is sheared, mirrored, flattened or not affine. "
					+ "Apply transforms and re-export.", field + "/matrix")
			node_local.append(matrix)
			return true
		var translation := PackedFloat64Array([0.0, 0.0, 0.0])
		var rotation := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
		var scale := PackedFloat64Array([1.0, 1.0, 1.0])
		if node.has("translation"):
			translation = _numbers(node.translation, 3)
			if translation.is_empty():
				return _invalid("A node has an invalid translation.", field + "/translation")
		if node.has("rotation"):
			rotation = _numbers(node.rotation, 4)
			if rotation.is_empty():
				return _invalid("A node has an invalid rotation.", field + "/rotation")
			var length := sqrt(rotation[0] * rotation[0] + rotation[1] * rotation[1] + rotation[2] * rotation[2]
				+ rotation[3] * rotation[3])
			if not (absf(length - 1.0) <= QUATERNION_TOLERANCE):
				return _invalid("A node's rotation is not a unit quaternion.", field + "/rotation")
			for axis: int in 4:
				rotation[axis] /= length
		if node.has("scale"):
			scale = _numbers(node.scale, 3)
			if scale.is_empty():
				return _invalid("A node has an invalid scale.", field + "/scale")
			for axis: int in 3:
				if scale[axis] == 0.0:
					return _invalid("A node has a zero scale.", field + "/scale")
				if scale[axis] < 0.0:
					return _unsupported("A node has a negative (mirroring) scale. Apply transforms and re-export.",
						field + "/scale")
		var x := rotation[0]
		var y := rotation[1]
		var z := rotation[2]
		var w := rotation[3]
		var turn := PackedFloat64Array([
			1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w),
			2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w),
			2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)])
		for row: int in 3:
			for column: int in 3:
				matrix[row * 4 + column] = turn[row * 3 + column] * scale[column]
			matrix[row * 4 + 3] = translation[row]
		node_local.append(matrix)
		return true

	## True when the 3 x 3 part is a rotation times a positive scale: non-zero axes, pairwise
	## perpendicular within `SHEAR_TOLERANCE`, positive determinant.
	func _is_rigid_scale(matrix: PackedFloat64Array) -> bool:
		var axes: Array[PackedFloat64Array] = []
		var lengths := PackedFloat64Array()
		for column: int in 3:
			var axis := PackedFloat64Array([matrix[column], matrix[4 + column], matrix[8 + column]])
			var length := sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2])
			if not (length > 0.0 and is_finite(length)):
				return false
			axes.append(axis)
			lengths.append(length)
		for pair: Array in [[0, 1], [0, 2], [1, 2]]:
			var first: PackedFloat64Array = axes[pair[0]]
			var second: PackedFloat64Array = axes[pair[1]]
			var cosine := (first[0] * second[0] + first[1] * second[1] + first[2] * second[2]) \
				/ (lengths[pair[0]] * lengths[pair[1]])
			if not (absf(cosine) <= SHEAR_TOLERANCE):
				return false
		var a: PackedFloat64Array = axes[0]
		var b: PackedFloat64Array = axes[1]
		var c: PackedFloat64Array = axes[2]
		var determinant := a[0] * (b[1] * c[2] - b[2] * c[1]) - b[0] * (a[1] * c[2] - a[2] * c[1]) \
			+ c[0] * (a[1] * b[2] - a[2] * b[1])
		return determinant > 0.0

	# --- budgets and data --------------------------------------------------------------------------

	## Instantiated totals over every node of the file; a mesh no node uses still counts once.
	func _budget() -> bool:
		var uses := PackedInt32Array()
		uses.resize(meshes.size())
		for mesh: int in node_mesh:
			if mesh >= 0:
				uses[mesh] += 1
		var triangles := 0
		var vertices := 0
		for index: int in meshes.size():
			var times := maxi(1, uses[index])
			triangles += int(meshes[index].triangles) * times
			vertices += int(meshes[index].vertices) * times
			if not _within_budget(triangles, vertices):
				return false
		return true

	func _within_budget(triangles: int, vertices: int) -> bool:
		if triangles > Limits.TRIANGLES:
			return _limit("The model has more than %s triangles. Reduce its detail and export again.", "meshes",
				[str(Limits.TRIANGLES)])
		if vertices > Limits.EXPANDED_VERTICES:
			return _limit("The model has more than %s vertices. Reduce its detail and export again.", "meshes",
				[str(Limits.EXPANDED_VERTICES)])
		return true

	## Reads the vertex and index data. The budget above bounds the total work: every surface
	## was counted at least once, and each accessor is read once.
	func _mesh_data() -> bool:
		for index: int in meshes.size():
			var primitives: Array = meshes[index].primitives
			for slot: int in primitives.size():
				var primitive: Dictionary = primitives[slot]
				var field := "meshes/%d/primitives/%d" % [index, slot]
				if not _position_box(int(primitive.position), field):
					return false
				for accessor_index: int in primitive.floats:
					if not finite_checked.has(accessor_index):
						var values := _floats(accessors[accessor_index])
						var probe := 0.0
						for value: float in values:
							probe += value * 0.0
						if is_nan(probe):
							return _invalid("A mesh surface holds vertex data that is not a finite number.", field)
						finite_checked[accessor_index] = true
				if int(primitive.indices) >= 0 and _highest_index(int(primitive.indices)) >= int(primitive.vertices):
					return _invalid("A mesh surface refers to a vertex that does not exist.", field + "/indices")
		return true

	func _position_box(accessor_index: int, field: String) -> bool:
		if boxes.has(accessor_index):
			return true
		var accessor: Dictionary = accessors[accessor_index]
		var values := _floats(accessor)
		var low_x := INF
		var low_y := INF
		var low_z := INF
		var high_x := -INF
		var high_y := -INF
		var high_z := -INF
		var probe := 0.0
		for index: int in range(0, values.size(), 3):
			var x := values[index]
			var y := values[index + 1]
			var z := values[index + 2]
			probe += (x + y + z) * 0.0
			if x < low_x: low_x = x
			if x > high_x: high_x = x
			if y < low_y: low_y = y
			if y > high_y: high_y = y
			if z < low_z: low_z = z
			if z > high_z: high_z = z
		if is_nan(probe):
			return _invalid("A mesh surface holds a vertex position that is not a finite number.", field)
		var low := PackedFloat64Array([low_x, low_y, low_z])
		var high := PackedFloat64Array([high_x, high_y, high_z])
		var declared_low: PackedFloat64Array = accessor.low
		var declared_high: PackedFloat64Array = accessor.high
		for axis: int in 3:
			if low[axis] < declared_low[axis] - BOUND_SLACK * maxf(1.0, absf(declared_low[axis])) \
					or high[axis] > declared_high[axis] + BOUND_SLACK * maxf(1.0, absf(declared_high[axis])):
				return _invalid("A mesh surface has vertex positions outside its declared bounds.", field)
		boxes[accessor_index] = [low, high]
		return true

	## float32 accessor data as one flat array. Tightly packed data converts natively.
	func _floats(accessor: Dictionary) -> PackedFloat32Array:
		var at := int(accessor.at)
		var count := int(accessor.count)
		var width := int(accessor.width)
		if bool(accessor.tight):
			return bytes.slice(at, at + count * width * 4).to_float32_array()
		var values := PackedFloat32Array()
		values.resize(count * width)
		var step := int(accessor.step)
		for index: int in count:
			for part: int in width:
				values[index * width + part] = bytes.decode_float(at + index * step + part * 4)
		return values

	## Largest index an index accessor holds (2^32 for any value at or above 2^31).
	func _highest_index(accessor_index: int) -> int:
		if index_highest.has(accessor_index):
			return int(index_highest[accessor_index])
		var accessor: Dictionary = accessors[accessor_index]
		var at := int(accessor.at)
		var count := int(accessor.count)
		var highest := 0
		match int(accessor.component):
			_UNSIGNED_INT:
				for value: int in bytes.slice(at, at + count * 4).to_int32_array():
					if value < 0:
						highest = 0x100000000
						break
					if value > highest:
						highest = value
			_UNSIGNED_SHORT:
				for index: int in count:
					var value := bytes.decode_u16(at + index * 2)
					if value > highest:
						highest = value
			_:
				for index: int in count:
					if bytes[at + index] > highest:
						highest = bytes[at + index]
		index_highest[accessor_index] = highest
		return highest

	## Full PNG check of every embedded image; one buffer view shared by images is checked once.
	func _image_data() -> bool:
		var checked := {}
		for index: int in images.size():
			var view_index := int(images[index].view)
			if checked.has(view_index):
				images[index] = (checked[view_index] as Dictionary).duplicate()
				continue
			# Structural check first, then one real decode: an image the decoder refuses must refuse
			# the model here, not fail silently later inside the scene importer. The decoded pixels
			# are dropped at once; the aggregate pixel budget was enforced before this point.
			var result: Dictionary = PngCheck.decode(_view_bytes(view_index))
			if not result.ok:
				return _forward(result, "images/%d" % index)
			checked[view_index] = result.value.info
			images[index] = (result.value.info as Dictionary).duplicate()
		return true

	# --- report -----------------------------------------------------------------------------------

	func _summary() -> bool:
		var world: Array[PackedFloat64Array] = []
		world.resize(node_parent.size())
		var queue := PackedInt32Array(scene_roots)
		var low := PackedFloat64Array([INF, INF, INF])
		var high := PackedFloat64Array([-INF, -INF, -INF])
		var instances := 0
		var triangles := 0
		var vertices := 0
		var head := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			var matrix := node_local[index]
			if node_parent[index] != -1:
				matrix = _compose(world[node_parent[index]], matrix)
			for value: float in matrix:
				if not (absf(value) <= _FLOAT32_MAX):
					return _invalid("A node's transform is too large to represent. Apply transforms and re-export.",
						"nodes/%d" % index)
			world[index] = matrix
			for child: int in node_children[index]:
				queue.append(child)
			if node_mesh[index] < 0:
				continue
			var mesh: Dictionary = meshes[node_mesh[index]]
			instances += 1
			triangles += int(mesh.triangles)
			vertices += int(mesh.vertices)
			for primitive: Dictionary in mesh.primitives:
				var box: Array = boxes[int(primitive.position)]
				for corner: int in 8:
					var x: float = box[corner & 1][0]
					var y: float = box[(corner >> 1) & 1][1]
					var z: float = box[(corner >> 2) & 1][2]
					for axis: int in 3:
						var value := matrix[axis * 4] * x + matrix[axis * 4 + 1] * y + matrix[axis * 4 + 2] * z \
							+ matrix[axis * 4 + 3]
						if not (absf(value) <= _FLOAT32_MAX):
							return _invalid("The model's geometry is too large to represent. Apply transforms and re-export.",
								"nodes/%d" % index)
						low[axis] = minf(low[axis], value)
						high[axis] = maxf(high[axis], value)
		if instances == 0:
			return _invalid("The model's scene has no mesh. Export the model with its objects selected or visible.",
				"scenes/%d" % scene_index)

		var has_uv := false
		var all_uv := true
		for mesh: Dictionary in meshes:
			for primitive: Dictionary in mesh.primitives:
				has_uv = has_uv or bool(primitive.uv)
				all_uv = all_uv and bool(primitive.uv)
		var image_report: Array[Dictionary] = []
		for index: int in images.size():
			var info: Dictionary = images[index]
			image_report.append({index = index, width = int(info.width), height = int(info.height),
				pixels = int(info.pixels), has_alpha = bool(info.has_alpha)})
		report.counts = {nodes = node_parent.size(), meshes = meshes.size(), primitives = primitive_count,
			materials = materials.size(), textures = texture_sources.size(), images = images.size(),
			accessors = accessors.size(), buffer_views = views.size(), mesh_instances = instances,
			triangles = triangles, vertices = vertices}
		report.scene = scene_index
		report.scene_roots = scene_roots
		report.bounds_min = low
		report.bounds_max = high
		report.images = image_report
		report.node_names = node_names
		report.has_uv = has_uv
		report.all_uv = all_uv
		report.materials = materials
		report.extensions_used = used_extensions
		return true

	## `parent * child` for 3 x 4 row-major affine matrices.
	func _compose(parent: PackedFloat64Array, child: PackedFloat64Array) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		out.resize(12)
		for row: int in 3:
			for column: int in 4:
				var value := parent[row * 4] * child[column] + parent[row * 4 + 1] * child[4 + column] \
					+ parent[row * 4 + 2] * child[8 + column]
				out[row * 4 + column] = value + parent[row * 4 + 3] if column == 3 else value
		return out

	# --- helpers ----------------------------------------------------------------------------------

	func _fail(code: String, message: String, field: String, arguments: Array) -> bool:
		if failure.is_empty():
			failure = R.fail(code, message, field, "", arguments)
		return false

	func _invalid(message: String, field := "", arguments: Array = []) -> bool:
		return _fail(R.SOURCE_INVALID, message, field, arguments)

	func _unsupported(message: String, field := "", arguments: Array = []) -> bool:
		return _fail(R.SOURCE_UNSUPPORTED, message, field, arguments)

	func _limit(message: String, field := "", arguments: Array = []) -> bool:
		return _fail(R.SOURCE_LIMIT, message, field, arguments)

	func _extension_refused(name: String, field: String) -> bool:
		return _unsupported("The model uses the glTF extension %s, which is not supported. %s", field,
			[name, str(_EXTENSION_ADVICE.get(name, "Turn it off in the export settings and export again."))])

	## Reuses another check's diagnostics, pointing them at this file's field.
	func _forward(result: Dictionary, field: String) -> bool:
		var diagnostics: Array = (result.diagnostics as Array).duplicate(true)
		for entry: Variant in diagnostics:
			if entry is Dictionary:
				entry.field = field
		failure = R.fail_all(diagnostics)
		return false

	## A top-level array of objects, at most `limit` long. Check `failure` after the call.
	func _items(key: String, limit: int) -> Array:
		var list: Variant = root.get(key, [])
		if not list is Array:
			_invalid("The model's %s list is invalid.", key, [key])
			return []
		if (list as Array).size() > limit:
			_limit("The model has more than %s %s. Simplify the model and export it again.", key, [str(limit), key])
			return []
		for entry: Variant in list:
			if not entry is Dictionary:
				_invalid("The model's %s list is invalid.", key, [key])
				return []
		return list

	## Refuses any property outside `allowed`: the importer never sees a property unchecked here.
	func _only(object: Dictionary, allowed: Array, field: String) -> bool:
		for key: Variant in object:
			if key not in allowed:
				return _unsupported("The model uses the glTF property %s, which is not supported. "
					+ "Export a plain rigid model with the exporter's default settings.", field, [str(key)])
		return true

	func _named(object: Dictionary, field: String) -> bool:
		if object.has("name") and typeof(object.name) != TYPE_STRING:
			return _invalid("The model has a name that is not text.", field + "/name")
		return true

	func _is_number(value: Variant) -> bool:
		return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

	## The JSON decoder returns every number as a float. This accepts only a finite whole number
	## in [0, high] and returns -1 for anything else (fraction, negative, out of range, not a number).
	func _whole(value: Variant, high: int) -> int:
		if not _is_number(value):
			return -1
		var number := float(value)
		if number < 0.0 or number > float(high) or number != floor(number):
			return -1
		return int(number)

	## `count` finite numbers, or an empty array.
	func _numbers(value: Variant, count: int) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		if not value is Array or (value as Array).size() != count:
			return out
		for entry: Variant in value:
			if not _is_number(entry):
				return PackedFloat64Array()
			out.append(float(entry))
		return out

	func _one_of(object: Dictionary, key: String, allowed: Array) -> bool:
		return not object.has(key) or _whole(object[key], 65535) in allowed

	func _unit_number(object: Dictionary, key: String) -> bool:
		return not object.has(key) or (_is_number(object[key]) and float(object[key]) >= 0.0 and float(object[key]) <= 1.0)

	func _unit_numbers(object: Dictionary, key: String, count: int) -> bool:
		if not object.has(key):
			return true
		var values := _numbers(object[key], count)
		for value: float in values:
			if value < 0.0 or value > 1.0:
				return false
		return not values.is_empty()

	func _view_bytes(view_index: int) -> PackedByteArray:
		var at := int(views[view_index].at)
		return bytes.slice(at, at + int(views[view_index].size))

	## One pass over the JSON bytes before any engine text or number decoder sees them, so those
	## decoders have nothing to log. Returns "" or the reason: malformed UTF-8, a raw control
	## character (JSON allows only tab, LF and CR), or a number token the engine's float parser
	## warns about (over `_NUMBER_CHARACTERS` long or with an exponent beyond `_NUMBER_EXPONENT`).
	func _text_problem(data: PackedByteArray) -> String:
		var pending := 0
		var low := 0x80
		var high := 0xBF
		var in_string := false
		var escaped := false
		var token := 0
		var exponent := -1
		for byte: int in data:
			if pending > 0:
				if byte < low or byte > high:
					return "it is not valid UTF-8 text"
				low = 0x80
				high = 0xBF
				pending -= 1
			elif byte >= 0x80:
				if byte >= 0xC2 and byte <= 0xDF:
					pending = 1
				elif byte >= 0xE0 and byte <= 0xEF:
					pending = 2
					if byte == 0xE0:
						low = 0xA0
					elif byte == 0xED:
						high = 0x9F
				elif byte >= 0xF0 and byte <= 0xF4:
					pending = 3
					if byte == 0xF0:
						low = 0x90
					elif byte == 0xF4:
						high = 0x8F
				else:
					return "it is not valid UTF-8 text"
			elif byte < 0x20 and byte != 0x09 and byte != 0x0A and byte != 0x0D:
				return "it holds a control character"
			elif in_string:
				if escaped:
					escaped = false
				elif byte == 0x5C:
					escaped = true
				elif byte == 0x22:
					in_string = false
			elif byte >= 0x30 and byte <= 0x39:
				token += 1
				if exponent >= 0:
					exponent = exponent * 10 + byte - 0x30
				if token > _NUMBER_CHARACTERS or exponent > _NUMBER_EXPONENT:
					return "it holds a number that is out of range"
			elif byte == 0x65 or byte == 0x45:
				token += 1
				exponent = 0
			elif byte == 0x2B or byte == 0x2D or byte == 0x2E:
				token += 1
			else:
				in_string = byte == 0x22
				token = 0
				exponent = -1
		return "it is not valid UTF-8 text" if pending != 0 else ""
