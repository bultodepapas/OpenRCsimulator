extends RefCounted
## Self-contained GLB writer for a parsed Phoenix model (AC-PX). Pure data.
##
## Port of `export_glb` in `research/aircraft-creator/phoenix/inspect_geo.py`, visual nodes only.
## Phoenix GEO space already matches glTF (+X left, +Y up, +Z forward, counter-clockwise), so no
## axis change is made. Texture rows are flipped top-down by `texture.gd`, so texture coordinates are
## written unchanged (no V flip). Physics is never imported: the receipt says so.
##
## The result respects the Creator admission limits. When the visual nodes would exceed the mesh or
## primitive ceiling, geometry that shares a material is merged into one mesh per material and a
## warning diagnostic reports it; otherwise one mesh per node is kept.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Geo := preload("res://workshop/creator/phoenix/geo.gd")

const FORMAT_ID := "openrc-phoenix-visual-v1"
const MAX_SCALE := 1.0e6
const STEP := "import"
const _FLOAT := 5126
const _UNSIGNED_INT := 5125
const _ARRAY_BUFFER := 34962
const _ELEMENT_ARRAY_BUFFER := 34963
const _MAGIC := 0x46546C67
const _CHUNK_JSON := 0x4E4F534A
const _CHUNK_BIN := 0x004E4942
const _DEFAULT_COLOR := 0.8


## Builds a GLB from `geo` (the value of `geo.gd` `parse`) and an optional decoded texture (the value of
## `texture.gd` `decode`; pass `{}` for none). `value` is `{bytes, merged, meshes, primitives, triangles,
## visual_nodes}`.
##
## `texture` may instead map lower-case GEO texture names to decoded textures: each material then uses
## its own image, and materials whose texture is absent keep their diffuse colour. `receipt` fields are
## merged into `asset.extras.openrc_phoenix` (the format and `physics_imported = false` always win).
static func build(geo: Dictionary, texture := {}, scale := 1.0, receipt := {}) -> Dictionary:
	if not (scale > 0.0 and scale <= MAX_SCALE):
		return R.fail(R.FIELD_INVALID, "The model scale must be greater than zero and at most %s.", "scale", STEP,
			[str(MAX_SCALE)])
	var writer := Writer.new()
	return writer.run(geo, texture, scale, receipt)


class Writer extends RefCounted:
	var geo := {}
	var vertices := PackedFloat32Array()
	var scale := 1.0
	var gltf := {}
	var bin := PackedByteArray()
	var error := {}

	func run(source: Dictionary, texture: Dictionary, factor: float, receipt: Dictionary) -> Dictionary:
		geo = source
		scale = factor
		vertices = source.vertex_data
		var extras := receipt.duplicate(true)
		var single_sha: Variant = texture.get("sha256") if texture.get("image") is Image else null
		extras.merge({geo_sha256 = source.sha256, texture_sha256 = single_sha, scale = scale})
		extras.format = FORMAT_ID
		extras.physics_imported = false
		gltf = {asset = {version = "2.0", generator = Geo.PROFILE, extras = {openrc_phoenix = extras}},
			scene = 0, scenes = [{nodes = []}], nodes = [], meshes = [], accessors = [],
			bufferViews = [], materials = [], buffers = []}
		# One decoded texture for every textured material, or a map of lower-case texture name -> texture.
		var by_name := {}
		if texture.get("image") is Image:
			by_name[""] = texture
		else:
			for key: Variant in texture:
				if texture[key] is Dictionary and texture[key].get("image") is Image:
					by_name[str(key).to_lower()] = texture[key]
		var image_index := {}
		for key: String in by_name:
			if image_index.size() >= Limits.GLB_IMAGES:
				break
			var png: PackedByteArray = (by_name[key].image as Image).save_png_to_buffer()
			if png.is_empty() or png.size() > Limits.PNG_BYTES:
				return R.fail(R.SOURCE_LIMIT, "The converted texture is empty or larger than %s MiB.", "source", STEP,
					[str(Limits.PNG_BYTES / Limits.MIB)])
			_align()
			gltf.bufferViews.append({buffer = 0, byteOffset = bin.size(), byteLength = png.size()})
			bin.append_array(png)
			if not gltf.has("images"):
				gltf.images = []
				gltf.samplers = [{magFilter = 9729, minFilter = 9987, wrapS = 10497, wrapT = 10497}]
				gltf.textures = []
			gltf.images.append({bufferView = gltf.bufferViews.size() - 1, mimeType = "image/png"})
			gltf.textures.append({sampler = 0, source = gltf.images.size() - 1})
			image_index[key] = gltf.textures.size() - 1
		for material: Dictionary in geo.materials:
			var pbr := {metallicFactor = 0.0, roughnessFactor = 0.6}
			var slot := -1
			if material.texture != null:
				slot = int(image_index.get("", image_index.get(str(material.texture).to_lower(), -1)))
			if slot >= 0:
				pbr.baseColorFactor = [1.0, 1.0, 1.0, 1.0]
				pbr.baseColorTexture = {index = slot}
			else:
				var color: Array = []
				for channel: int in 3:
					var value: float = material.diffuse[channel]
					color.append(clampf(value, 0.0, 1.0) if is_finite(value) else _DEFAULT_COLOR)
				color.append(1.0)
				pbr.baseColorFactor = color
			gltf.materials.append({name = material.name, pbrMetallicRoughness = pbr, doubleSided = false})
		var visual: Array = []
		var primitive_total := 0
		for node: Dictionary in geo.nodes:
			if node.role != Geo.ROLE_VISUAL:
				continue
			var ranges: Array = []
			for sub: Dictionary in node.subs:
				if int(sub.end) > int(sub.first):
					ranges.append(sub)
			if ranges.is_empty():
				continue
			visual.append({node = node, ranges = ranges})
			primitive_total += ranges.size()
		var notes: Array = []
		var merged := visual.size() > Limits.GLB_MESHES or primitive_total > Limits.GLB_PRIMITIVES
		if visual.is_empty():
			return R.fail(R.SOURCE_INVALID, "The Phoenix model has no visual geometry.", "source", STEP)
		var triangles := 0
		if merged:
			notes.append(R.diagnostic(R.SOURCE_LIMIT,
				"The model has %s visual parts; parts that share a material were merged into one mesh each to stay within the %s mesh limit.",
				"source", STEP, [str(visual.size()), str(Limits.GLB_MESHES)], R.SEVERITY_WARNING))
			var groups := {}
			var order: Array = []
			for entry: Dictionary in visual:
				for sub: Dictionary in entry.ranges:
					var key: int = sub.material
					if not groups.has(key):
						groups[key] = []
						order.append(key)
					groups[key].append(sub)
			order.sort()
			for key: int in order:
				var label := "phoenix_merged_none" if key < 0 else "phoenix_merged_%s" % str(geo.materials[key].name)
				var made := _mesh(label, [{material = key, ranges = groups[key]}], {merged_parts = groups[key].size()})
				if made < 0:
					return error
				triangles += made
		else:
			for entry: Dictionary in visual:
				var node: Dictionary = entry.node
				var parts: Array = []
				for sub: Dictionary in entry.ranges:
					parts.append({material = int(sub.material), ranges = [sub]})
				var made := _mesh(str(node.name), parts, {index = node.index, role = node.role})
				if made < 0:
					return error
				triangles += made
		_align()
		gltf.buffers = [{byteLength = bin.size()}]
		var json := JSON.stringify(gltf, "", true, true).to_utf8_buffer()
		if json.size() > Limits.GLB_JSON_BYTES:
			return R.fail(R.SOURCE_LIMIT, "The converted model metadata exceeds the Creator limit.", "source", STEP)
		while json.size() % 4 != 0:
			json.append(32)
		if 28 + json.size() + bin.size() > Limits.MODEL_SOURCE_BYTES:
			return R.fail(R.SOURCE_LIMIT, "The converted model exceeds the Creator data limit.", "source", STEP)
		var out := PackedByteArray()
		out.resize(20)
		out.encode_u32(0, _MAGIC)
		out.encode_u32(4, 2)
		out.encode_u32(8, 28 + json.size() + bin.size())
		out.encode_u32(12, json.size())
		out.encode_u32(16, _CHUNK_JSON)
		out.append_array(json)
		var chunk := PackedByteArray()
		chunk.resize(8)
		chunk.encode_u32(0, bin.size())
		chunk.encode_u32(4, _CHUNK_BIN)
		out.append_array(chunk)
		out.append_array(bin)
		return R.ok({bytes = out, merged = merged, meshes = gltf.meshes.size(), primitives = _primitive_count(),
			triangles = triangles, visual_nodes = visual.size()}, notes)

	func _primitive_count() -> int:
		var total := 0
		for mesh: Dictionary in gltf.meshes:
			total += (mesh.primitives as Array).size()
		return total

	func _align() -> void:
		while bin.size() % 4 != 0:
			bin.append(0)

	func _view(blob: PackedByteArray, target: int) -> int:
		_align()
		gltf.bufferViews.append({buffer = 0, byteOffset = bin.size(), byteLength = blob.size(), target = target})
		bin.append_array(blob)
		return gltf.bufferViews.size() - 1

	func _accessor(blob: PackedByteArray, component: int, count: int, type: String, target: int,
			low: Array = [], high: Array = []) -> int:
		var accessor := {bufferView = _view(blob, target), componentType = component, count = count, type = type}
		if not low.is_empty():
			accessor.min = low
			accessor.max = high
		gltf.accessors.append(accessor)
		return gltf.accessors.size() - 1

	## Appends one mesh node holding one primitive per part `{material, ranges}`; a part with several ranges
	## joins them into one primitive. Returns the triangle count, or -1 with `error` set.
	func _mesh(label: String, parts: Array, extras: Dictionary) -> int:
		var primitives: Array = []
		var triangles := 0
		for part: Dictionary in parts:
			var count := 0
			for sub: Dictionary in part.ranges:
				count += int(sub.end) - int(sub.first)
			var position := PackedFloat32Array()
			var normal := PackedFloat32Array()
			var uv := PackedFloat32Array()
			position.resize(count * 3)
			normal.resize(count * 3)
			uv.resize(count * 2)
			var low := [INF, INF, INF]
			var high := [-INF, -INF, -INF]
			var probe := 0.0
			var out := 0
			for sub: Dictionary in part.ranges:
				for index: int in range(int(sub.first), int(sub.end)):
					var base := index * Geo.VERTEX_STRIDE_FLOATS
					var x: float = vertices[base] * scale
					var y: float = vertices[base + 1] * scale
					var z: float = vertices[base + 2] * scale
					position[out * 3] = x
					position[out * 3 + 1] = y
					position[out * 3 + 2] = z
					probe += (x + y + z) * 0.0
					var nx: float = vertices[base + 3]
					var ny: float = vertices[base + 4]
					var nz: float = vertices[base + 5]
					var length := sqrt(nx * nx + ny * ny + nz * nz)
					if length == 0.0:
						length = 1.0
					normal[out * 3] = nx / length
					normal[out * 3 + 1] = ny / length
					normal[out * 3 + 2] = nz / length
					uv[out * 2] = vertices[base + 6]
					uv[out * 2 + 1] = vertices[base + 7]
					out += 1
			# Float32 values read back, so the declared bounds match the stored data exactly.
			for index: int in count:
				for axis: int in 3:
					var value := position[index * 3 + axis]
					if value < low[axis]:
						low[axis] = value
					if value > high[axis]:
						high[axis] = value
			if is_nan(probe) or not (absf(low[0]) < 3.0e38 and absf(low[1]) < 3.0e38 and absf(low[2]) < 3.0e38
					and absf(high[0]) < 3.0e38 and absf(high[1]) < 3.0e38 and absf(high[2]) < 3.0e38):
				error = R.fail(R.SOURCE_INVALID, "The scaled Phoenix geometry is not representable.", "scale", STEP)
				return -1
			var indices := PackedInt32Array()
			indices.resize(count)
			for index: int in count:
				indices[index] = index
			var attributes := {
				POSITION = _accessor(position.to_byte_array(), _FLOAT, count, "VEC3", _ARRAY_BUFFER, low, high),
				NORMAL = _accessor(normal.to_byte_array(), _FLOAT, count, "VEC3", _ARRAY_BUFFER),
				TEXCOORD_0 = _accessor(uv.to_byte_array(), _FLOAT, count, "VEC2", _ARRAY_BUFFER)}
			var primitive := {attributes = attributes, indices = _accessor(indices.to_byte_array(), _UNSIGNED_INT, count,
				"SCALAR", _ELEMENT_ARRAY_BUFFER), mode = 4}
			if int(part.material) >= 0:
				primitive.material = int(part.material)
			primitives.append(primitive)
			triangles += count / 3
		gltf.meshes.append({name = label, primitives = primitives})
		gltf.nodes.append({name = label, mesh = gltf.meshes.size() - 1, extras = {openrc_phoenix_node = extras}})
		gltf.scenes[0].nodes.append(gltf.nodes.size() - 1)
		return triangles
