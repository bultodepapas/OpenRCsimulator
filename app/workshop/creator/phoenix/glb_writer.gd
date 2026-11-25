extends RefCounted
## Self-contained GLB writer for a parsed Phoenix model (AC-PX). Pure data.
##
## Port of `export_glb` in `research/aircraft-creator/phoenix/inspect_geo.py`, visual nodes only.
## Phoenix GEO space already matches glTF (+X left, +Y up, +Z forward, counter-clockwise), so no
## axis change is made. Texture rows are flipped top-down by `texture.gd`, so texture coordinates are
## written unchanged (no V flip). The Phoenix flight model is never imported (`physics_imported = false`);
## the receipt may carry the reduced physics block that `physics.gd` turns into labelled OpenRC packages.
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
## Untextured glass: tinted, smooth and translucent. Stock glass textures are almost clear (alpha ~0.1),
## which reads as missing in a sunlit scene, so translucency keeps a visible minimum.
const _GLASS_COLOR := [0.12, 0.15, 0.18, 0.45]
const _GLASS_ROUGHNESS := 0.08
const _GLASS_MIN_ALPHA := 0.3
const _ALPHA_CUTOFF := 0.5
const _PART_HINT := "openrc-creator-part-hint-v1"


## Builds a GLB from `geo` (the value of `geo.gd` `parse`) and an optional decoded texture (the value of
## `texture.gd` `decode`; pass `{}` for none). `value` is `{bytes, merged, meshes, primitives, triangles,
## visual_nodes}`.
##
## `texture` may instead map lower-case GEO texture names to decoded textures: each material then uses
## its own image, and materials whose texture is absent keep their diffuse colour. `receipt` fields are
## merged into `asset.extras.openrc_phoenix` (the format and `physics_imported = false` always win).
##
## `articulation` lists rigid moving groups `{role, nodes: [GEO node names], origin: [x, y, z] GEO units,
## hinge: [x, y, z] (direction; empty for a propeller), axis: "x"|"z", sign}`. Each group becomes a pivot
## node at `origin` whose local `axis` is the hinge (or the forward axis for a propeller), with the
## member meshes expressed in that frame so the neutral pose is unchanged. `value.pivots` returns
## `{role, node, axis, sign}` per built group. Groups are skipped when meshes are merged. `markers` adds
## asset extras keys such as the fixed-wing provider marker read by `source_installation.gd`.
static func build(geo: Dictionary, texture := {}, scale := 1.0, receipt := {}, articulation: Array = [],
		markers: Array = []) -> Dictionary:
	if not (scale > 0.0 and scale <= MAX_SCALE):
		return R.fail(R.FIELD_INVALID, "The model scale must be greater than zero and at most %s.", "scale", STEP,
			[str(MAX_SCALE)])
	var writer := Writer.new()
	return writer.run(geo, texture, scale, receipt, articulation, markers)


class Writer extends RefCounted:
	var geo := {}
	var vertices := PackedFloat32Array()
	var scale := 1.0
	var gltf := {}
	var bin := PackedByteArray()
	var error := {}

	func run(source: Dictionary, texture: Dictionary, factor: float, receipt: Dictionary, articulation: Array,
			markers: Array) -> Dictionary:
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
		# Provider markers are separate asset extras keys (Creator records extras key names, never values).
		for marker: Variant in markers:
			if typeof(marker) == TYPE_STRING and str(marker) != "openrc_phoenix":
				gltf.asset.extras[str(marker)] = {format = str(marker) + "-v1"}
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
			if bool(by_name[key].get("uniform", false)):
				continue  # A small alpha texture (glass) becomes a flat translucent colour instead.
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
			var entry := {name = material.name, pbrMetallicRoughness = pbr, doubleSided = false}
			var key := str(material.texture).to_lower() if material.texture != null else ""
			var decoded: Dictionary = by_name.get("", by_name.get(key, {})) if material.texture != null else {}
			var slot := -1
			if material.texture != null:
				slot = int(image_index.get("", image_index.get(key, -1)))
			if slot >= 0:
				pbr.baseColorFactor = [1.0, 1.0, 1.0, 1.0]
				pbr.baseColorTexture = {index = slot}
				# Cut-outs test against the cutoff and keep depth sorting; only graded alpha blends.
				# A texture whose alpha is unused ("none"/"zero") stays opaque.
				match _alpha_class(decoded):
					"mask":
						entry.alphaMode = "MASK"
						entry.alphaCutoff = _ALPHA_CUTOFF
					"blend":
						entry.alphaMode = "BLEND"
			elif bool(decoded.get("uniform", false)):
				var mean: Array = decoded.mean
				if float(mean[3]) < _GLASS_MIN_ALPHA:
					pbr.baseColorFactor = _GLASS_COLOR.duplicate()  # Nearly clear glass: a visible tinted canopy.
				else:
					pbr.baseColorFactor = [clampf(mean[0], 0.0, 1.0), clampf(mean[1], 0.0, 1.0), clampf(mean[2], 0.0, 1.0),
						clampf(float(mean[3]), 0.0, 1.0)]
				if float(pbr.baseColorFactor[3]) < 0.98:
					entry.alphaMode = "BLEND"
					pbr.roughnessFactor = _GLASS_ROUGHNESS
			elif _is_glass(material):
				pbr.baseColorFactor = _GLASS_COLOR.duplicate()
				pbr.roughnessFactor = _GLASS_ROUGHNESS
				entry.alphaMode = "BLEND"
			else:
				var color: Array = []
				for channel: int in 3:
					var value: float = material.diffuse[channel]
					color.append(clampf(value, 0.0, 1.0) if is_finite(value) else _DEFAULT_COLOR)
				color.append(1.0)
				pbr.baseColorFactor = color
			gltf.materials.append(entry)
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
		var pivots: Array = []
		if merged and not articulation.is_empty():
			notes.append(R.diagnostic(R.SOURCE_LIMIT, "Moving parts were not prepared because the model's parts were merged.",
				"source", STEP, [], R.SEVERITY_WARNING))
		if not merged:
			var visual_by_name := {}
			for entry: Dictionary in visual:
				visual_by_name[str(entry.node.name)] = entry
			# Each visual node joins at most one moving group; the rest stay static scene roots.
			var claimed := {}
			var groups: Array = []
			for group: Dictionary in articulation:
				var members: Array = []
				for name: Variant in group.get("nodes", []):
					if visual_by_name.has(str(name)) and not claimed.has(str(name)) and not str(name) in members:
						members.append(str(name))
				var frame := _frame(group)
				if members.is_empty() or frame.is_empty():
					continue
				for name: String in members:
					claimed[name] = true
				groups.append({group = group, members = members, frame = frame})
			for entry: Dictionary in visual:
				if claimed.has(str(entry.node.name)):
					continue
				var made := _node_mesh(entry, {}, true)
				if made < 0:
					return error
				triangles += made
			for built: Dictionary in groups:
				var children: Array = []
				for name: String in built.members:
					var made := _node_mesh(visual_by_name[name], built.frame, false)
					if made < 0:
						return error
					triangles += made
					children.append(gltf.nodes.size() - 1)
				var axis := str(built.group.get("axis", "x"))
				var x: Array = built.frame.axes[0]
				var y: Array = built.frame.axes[1]
				var z: Array = built.frame.axes[2]
				var o: Array = built.frame.origin
				gltf.nodes.append({name = "pivot_%s_%d" % [str(built.group.role), pivots.size()],
					matrix = [x[0], x[1], x[2], 0.0, y[0], y[1], y[2], 0.0, z[0], z[1], z[2], 0.0, o[0], o[1], o[2], 1.0],
					children = children, extras = {openrc_creator_part = {format = _PART_HINT, axis = axis}}})
				gltf.scenes[0].nodes.append(gltf.nodes.size() - 1)
				pivots.append({role = str(built.group.role), node = gltf.nodes.size() - 1, axis = axis,
					sign = 1 if int(built.group.get("sign", 1)) >= 0 else -1})
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
			triangles = triangles, visual_nodes = visual.size(), pivots = pivots}, notes)

	## Orthonormal pivot frame for a group: X along the hinge (Y/Z completed right-handed), or the
	## model axes for a propeller. `{origin (metres), axes: [x, y, z]}`; empty when degenerate.
	func _frame(group: Dictionary) -> Dictionary:
		var origin: Variant = group.get("origin")
		if not origin is Array or (origin as Array).size() != 3:
			return {}
		var o := [float(origin[0]) * scale, float(origin[1]) * scale, float(origin[2]) * scale]
		for value: float in o:
			if not is_finite(value):
				return {}
		var hinge: Variant = group.get("hinge", [])
		if not hinge is Array or (hinge as Array).is_empty():
			return {origin = o, axes = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]}
		var d := Vector3(float(hinge[0]), float(hinge[1]), float(hinge[2]))
		if not d.is_finite() or d.length() < 1.0e-6:
			return {}
		var x := d.normalized()
		var helper := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.BACK
		var z := x.cross(helper).normalized()
		var y := z.cross(x)
		return {origin = o, axes = [[x.x, x.y, x.z], [y.x, y.y, y.z], [z.x, z.y, z.z]]}

	## "none", "zero", "mask" or "blend" (see `texture.gd`); a texture decoded without a class blends when
	## it has alpha.
	static func _alpha_class(decoded: Dictionary) -> String:
		var alpha: Variant = decoded.get("alpha")
		if alpha is String:
			return alpha
		return "blend" if bool(decoded.get("has_alpha", false)) else "none"

	## Untextured materials named as glass (the shared glass texture was not found) render translucent.
	static func _is_glass(material: Dictionary) -> bool:
		var named := (str(material.get("name", "")) + " " + str(material.get("texture", ""))).to_lower()
		return named.contains("glass")

	func _node_mesh(entry: Dictionary, frame: Dictionary, root: bool) -> int:
		var node: Dictionary = entry.node
		var parts: Array = []
		for sub: Dictionary in entry.ranges:
			parts.append({material = int(sub.material), ranges = [sub]})
		return _mesh(str(node.name), parts, {index = node.index, role = node.role}, frame, root)

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
	func _mesh(label: String, parts: Array, extras: Dictionary, frame := {}, root := true) -> int:
		var primitives: Array = []
		var triangles := 0
		var axes: Array = frame.get("axes", [])
		var origin: Array = frame.get("origin", [0.0, 0.0, 0.0])
		for part: Dictionary in parts:
			var corners := 0
			for sub: Dictionary in part.ranges:
				corners += int(sub.end) - int(sub.first)
			var position := PackedFloat32Array()
			var normal := PackedFloat32Array()
			var uv := PackedFloat32Array()
			var indices := PackedInt32Array()
			indices.resize(corners)
			var low := [INF, INF, INF]
			var high := [-INF, -INF, -INF]
			var probe := 0.0
			var out := 0
			var corner := 0
			# Identical corners (position, normal, UV) are welded: GEO stores one unindexed triangle list.
			var welded := {}
			for sub: Dictionary in part.ranges:
				for index: int in range(int(sub.first), int(sub.end)):
					var base := index * Geo.VERTEX_STRIDE_FLOATS
					var x: float = vertices[base] * scale - float(origin[0])
					var y: float = vertices[base + 1] * scale - float(origin[1])
					var z: float = vertices[base + 2] * scale - float(origin[2])
					var nx: float = vertices[base + 3]
					var ny: float = vertices[base + 4]
					var nz: float = vertices[base + 5]
					if not axes.is_empty():
						var ax: Array = axes[0]
						var ay: Array = axes[1]
						var az: Array = axes[2]
						var px: float = x * ax[0] + y * ax[1] + z * ax[2]
						var py: float = x * ay[0] + y * ay[1] + z * ay[2]
						var pz: float = x * az[0] + y * az[1] + z * az[2]
						var qx: float = nx * ax[0] + ny * ax[1] + nz * ax[2]
						var qy: float = nx * ay[0] + ny * ay[1] + nz * ay[2]
						var qz: float = nx * az[0] + ny * az[1] + nz * az[2]
						x = px
						y = py
						z = pz
						nx = qx
						ny = qy
						nz = qz
					probe += (x + y + z) * 0.0
					var length := sqrt(nx * nx + ny * ny + nz * nz)
					if length == 0.0:
						length = 1.0
					var key := [x, y, z, nx, ny, nz, vertices[base + 6], vertices[base + 7]]
					var found: Variant = welded.get(key)
					if found == null:
						position.append_array(PackedFloat32Array([x, y, z]))
						normal.append_array(PackedFloat32Array([nx / length, ny / length, nz / length]))
						uv.append_array(PackedFloat32Array([vertices[base + 6], vertices[base + 7]]))
						welded[key] = out
						found = out
						out += 1
					indices[corner] = int(found)
					corner += 1
			var count := out
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
			var attributes := {
				POSITION = _accessor(position.to_byte_array(), _FLOAT, count, "VEC3", _ARRAY_BUFFER, low, high),
				NORMAL = _accessor(normal.to_byte_array(), _FLOAT, count, "VEC3", _ARRAY_BUFFER),
				TEXCOORD_0 = _accessor(uv.to_byte_array(), _FLOAT, count, "VEC2", _ARRAY_BUFFER)}
			var primitive := {attributes = attributes, indices = _accessor(indices.to_byte_array(), _UNSIGNED_INT, corners,
				"SCALAR", _ELEMENT_ARRAY_BUFFER), mode = 4}
			if int(part.material) >= 0:
				primitive.material = int(part.material)
			primitives.append(primitive)
			triangles += corners / 3
		gltf.meshes.append({name = label, primitives = primitives})
		gltf.nodes.append({name = label, mesh = gltf.meshes.size() - 1, extras = {openrc_phoenix_node = extras}})
		if root:
			gltf.scenes[0].nodes.append(gltf.nodes.size() - 1)
		return triangles
