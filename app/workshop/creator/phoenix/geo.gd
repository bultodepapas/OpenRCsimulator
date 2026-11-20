extends RefCounted
## Bounded reader for Phoenix RC stock `.geo` geometry (AC-PX). Pure data.
##
## Port of `research/aircraft-creator/phoenix/inspect_geo.py`, profile `openrc-phoenix-geo-observed-v1`
## (220 of 221 stock aircraft files consume exactly). The whole file must be consumed exactly, the
## sub-ranges of all nodes must tile the vertex array contiguously, and a material index of
## 0xFFFFFFFF means no material. Fields whose meaning is unresolved are kept verbatim; the ones the
## Python probe reads without a finiteness check are read the same way here.
##
## `parse` returns `{profile, sha256, header, materials, vertex_count, vertex_offset, vertex_data,
## nodes}`. `vertex_data` holds `VERTEX_STRIDE_FLOATS` floats per vertex (position, normal, u, v and
## five unresolved floats); the writer reads the first eight.

const R := preload("res://workshop/creator/result.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")

const PROFILE := "openrc-phoenix-geo-observed-v1"
const MAX_INPUT := 64 << 20
const MAX_MATERIALS := 64
const MAX_NODES := 512
const MAX_SUBS := 256
const MAX_TRIANGLES := 200000
const MATERIAL_BYTES := 716
const VERTEX_BYTES := 52
const VERTEX_STRIDE_FLOATS := 13
const SUB_BYTES := 74
const NODE_HEAD_BYTES := 124
const NAME_FIELD := 28
const NAME_SEARCH := 56
const NO_MATERIAL := 0xFFFFFFFF
const ROLE_VISUAL := "visual"
const ROLE_COLLISION := "collision"
const ROLE_HELPER := "helper"
const STEP := "import"


static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_INPUT:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix model is larger than %s MiB.", "source", STEP, [str(MAX_INPUT >> 20)])
	var c := Cursor.new()
	c.data = data
	var version := c.u32()
	var node_count := c.u32()
	var h2 := c.u32()
	var triangles := c.u32()
	var flag := c.u8()
	if not c.error.is_empty():
		return c.failure()
	if version != 1:
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix model has unsupported version %s.", "source", STEP, [str(version)])
	if node_count <= 0 or node_count > MAX_NODES or triangles <= 0 or triangles > MAX_TRIANGLES:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix model header counts are outside the supported profile.", "source", STEP)
	var bbox := c.floats(6, true)
	var material_count := c.u32()
	if not c.error.is_empty():
		return c.failure()
	if material_count > MAX_MATERIALS:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix model has more than %s materials.", "source", STEP, [str(MAX_MATERIALS)])
	var materials: Array = []
	for index: int in material_count:
		var record := c.take(MATERIAL_BYTES)
		if not c.error.is_empty():
			return c.failure()
		var named := c_name(record, 0)
		if not named.ok:
			return named
		var has_texture := record.decode_u32(128)
		if has_texture != 0 and has_texture != 1:
			return R.fail(R.SOURCE_INVALID, "Phoenix material %s has an invalid texture flag.", "source", STEP, [str(index)])
		var texture: Variant = null
		if has_texture == 1:
			var texture_name := c_name(record, 132)
			if not texture_name.ok:
				return texture_name
			texture = texture_name.value.name
		materials.append({name = named.value.name, name_hex = named.value.hex, name_overflow = named.value.overflow,
			texture = texture, diffuse = _floats_at(record, 680, 3), specular = _floats_at(record, 692, 3),
			unresolved_704 = _floats_at(record, 704, 3)})
	var vertex_count := c.u32()
	if not c.error.is_empty():
		return c.failure()
	if vertex_count != triangles * 3:
		return R.fail(R.SOURCE_INVALID, "The Phoenix model vertex count %s does not equal three times its triangle count.",
			"source", STEP, [str(vertex_count)])
	var vertex_start := c.pos
	var vertex_bytes := c.take(vertex_count * VERTEX_BYTES)
	if not c.error.is_empty():
		return c.failure()
	var vertex_data := vertex_bytes.to_float32_array()
	var probe := 0.0
	for index: int in vertex_count:
		var base := index * VERTEX_STRIDE_FLOATS
		for part: int in 8:
			probe += vertex_data[base + part] * 0.0
	if is_nan(probe):
		return R.fail(R.SOURCE_INVALID, "The Phoenix model holds a vertex that is not a finite number.", "source", STEP)
	var recorded_nodes := c.u32()
	if not c.error.is_empty():
		return c.failure()
	if recorded_nodes != node_count:
		return R.fail(R.SOURCE_INVALID, "The Phoenix model node count %s differs from its header.", "source", STEP,
			[str(recorded_nodes)])
	var nodes: Array = []
	var cursor_end := 0
	for index: int in recorded_nodes:
		var start := c.pos
		var head := c.take(NODE_HEAD_BYTES)
		if not c.error.is_empty():
			return c.failure()
		var named := c_name(head, 0)
		if not named.ok:
			return named
		var unresolved := c.floats(2, false)
		var node_bbox := c.floats(6, true)
		var matrix := c.floats(16, true)
		var sub_count := c.u32()
		if not c.error.is_empty():
			return c.failure()
		if sub_count > MAX_SUBS:
			return R.fail(R.SOURCE_LIMIT, "Phoenix node %s has more than %s sub-meshes.", "source", STEP,
				[str(index), str(MAX_SUBS)])
		var subs: Array = []
		for sub_index: int in sub_count:
			var sub_bbox := c.floats(6, false)
			var material := c.u32()
			var u1 := c.u32()
			var u2 := c.u32()
			var u3 := c.u16()
			c.u32() # writer heap pointer: never interpreted
			c.floats(6, false)
			var first := c.u32()
			var end := c.u32()
			if not c.error.is_empty():
				return c.failure()
			if first != cursor_end or end < first or end > vertex_count or (end - first) % 3 != 0:
				return R.fail(R.SOURCE_INVALID, "Phoenix node %s sub-mesh %s has an invalid vertex range %s to %s.",
					"source", STEP, [str(index), str(sub_index), str(first), str(end)])
			if material != NO_MATERIAL and material >= material_count:
				return R.fail(R.SOURCE_INVALID, "Phoenix node %s sub-mesh %s uses a material that does not exist.",
					"source", STEP, [str(index), str(sub_index)])
			cursor_end = end
			subs.append({material = -1 if material == NO_MATERIAL else material, first = first, end = end,
				bbox = sub_bbox, unresolved = [u1, u2, u3]})
		var tail := c.u32()
		if not c.error.is_empty():
			return c.failure()
		nodes.append({index = index, name = named.value.name, name_hex = named.value.hex,
			name_overflow = named.value.overflow, role = role_of(named.value.name), bbox = node_bbox, matrix = matrix,
			subs = subs, unresolved_124 = unresolved, unresolved_tail = tail, offset = start})
	if cursor_end != vertex_count:
		return R.fail(R.SOURCE_INVALID, "The Phoenix model sub-meshes end at vertex %s of %s.", "source", STEP,
			[str(cursor_end), str(vertex_count)])
	if c.pos != data.size():
		return R.fail(R.SOURCE_INVALID, "The Phoenix model has %s unconsumed bytes.", "source", STEP,
			[str(data.size() - c.pos)])
	return R.ok({profile = PROFILE, sha256 = CreatorBytes.sha256(data), header = {version = version, nodes = node_count,
		unresolved_h2 = h2, triangles = triangles, flag = flag, bbox = bbox}, materials = materials,
		vertex_count = vertex_count, vertex_offset = vertex_start, vertex_data = vertex_data, nodes = nodes})


static func role_of(name: String) -> String:
	var lower := name.to_lower()
	if lower.begins_with("__col"):
		return ROLE_COLLISION
	if lower.begins_with("__"):
		return ROLE_HELPER
	return ROLE_VISUAL


## Phoenix writes 28-byte c_str() fields; names of 28 or more characters overflow into the next field.
## `value` is `{name, hex, overflow}` for the NUL-terminated text within the first 56 bytes at `start`.
static func c_name(field: PackedByteArray, start: int) -> Dictionary:
	var end := mini(start + NAME_SEARCH, field.size())
	var zero := -1
	for index: int in range(start, end):
		if field[index] == 0:
			zero = index - start
			break
	if zero < 0:
		return R.fail(R.SOURCE_INVALID, "The Phoenix model has an unterminated name.", "source", STEP)
	var raw := field.slice(start, start + zero)
	var text := ""
	for value: int in raw:
		text += String.chr(value)
	return R.ok({name = text, hex = raw.hex_encode(), overflow = zero >= NAME_FIELD})


static func _floats_at(bytes: PackedByteArray, offset: int, count: int) -> Array:
	var out: Array = []
	for index: int in count:
		out.append(bytes.decode_float(offset + index * 4))
	return out


class Cursor extends RefCounted:
	var data := PackedByteArray()
	var pos := 0
	var error := ""
	var arguments: Array = []

	func failure() -> Dictionary:
		return R.fail(R.SOURCE_INVALID, error, "source", STEP, arguments)

	func _short(length: int) -> bool:
		if length < 0 or pos + length > data.size():
			if error.is_empty():
				error = "The Phoenix model is truncated at byte %s."
				arguments = [str(pos)]
			return true
		return false

	func take(length: int) -> PackedByteArray:
		if _short(length):
			return PackedByteArray()
		var piece := data.slice(pos, pos + length)
		pos += length
		return piece

	func u8() -> int:
		if _short(1):
			return 0
		pos += 1
		return data[pos - 1]

	func u16() -> int:
		if _short(2):
			return 0
		pos += 2
		return data.decode_u16(pos - 2)

	func u32() -> int:
		if _short(4):
			return 0
		pos += 4
		return data.decode_u32(pos - 4)

	func floats(count: int, check: bool) -> Array:
		var out: Array = []
		if _short(4 * count):
			return out
		for index: int in count:
			var value := data.decode_float(pos + index * 4)
			if check and not is_finite(value):
				error = "The Phoenix model holds a non-finite number before byte %s."
				arguments = [str(pos + count * 4)]
			out.append(value)
		pos += 4 * count
		return out
