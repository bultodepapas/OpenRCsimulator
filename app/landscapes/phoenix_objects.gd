extends RefCounted
## Structural validation for the installed panoramic descriptor profiles.
## These offsets identify records and embedded images. They do not assign physical meanings.

const MAX_OBJECTS := 4096
const MAX_AREA_ELEMENTS := 65536
const SMALL_BITMAP_BYTES := 262200
const LARGE_BITMAP_BYTES := 16777272


static func inspect(data: PackedByteArray, offset: int, profile: int) -> Dictionary:
	var counts := PackedInt32Array([0, 0, 0, 0, 0])
	if not _fits(data, offset, 4) or profile not in [1, 2, 3, 4]:
		return {complete = false, counts = counts}
	var declared := data.decode_u32(offset)
	if declared > MAX_OBJECTS:
		return {complete = false, counts = counts}
	var delta := 1 if profile < 3 else 0
	var cursor := offset + 4
	for ordinal in declared:
		var name := cursor + 4
		var base := name + 0xf0 - delta
		if not _fits(data, cursor, base - cursor):
			return {complete = false, counts = counts, stop = ordinal}
		var tag := data.decode_u32(cursor)
		if tag > 4 or tag != data.decode_u32(name + 0x44 - delta) \
				or data.slice(name, name + 64).find(0) < 0:
			return {complete = false, counts = counts, stop = ordinal}
		var following := _next_offset(data, tag, name, base, delta)
		if following < base or following > data.size():
			return {complete = false, counts = counts, stop = ordinal}
		counts[tag] += 1
		cursor = following
	return {complete = true, counts = counts, end = cursor, embedded = _bitmaps(data, cursor)}


static func _next_offset(data: PackedByteArray, tag: int, name: int, base: int, delta: int) -> int:
	match tag:
		0:
			return name + 0x104 - delta
		1:
			var dimension_offset := name + 0x108 - delta
			if not _fits(data, dimension_offset, 4) or data.decode_u32(dimension_offset) != 50:
				return -1
			return dimension_offset + 4 + 48 * 50 * 50
		2:
			if not _fits(data, base, 8):
				return -1
			var subtype := data.decode_u32(base)
			var points := data.decode_u32(base + 4)
			if subtype > 2 or points > MAX_AREA_ELEMENTS:
				return -1
			var secondary := base + 8 + 12 * points
			if not _fits(data, secondary, 4) or data.decode_u32(secondary) > MAX_AREA_ELEMENTS:
				return -1
			return secondary + 4 + 72 * data.decode_u32(secondary) + (16 if subtype == 2 else 0)
		3:
			return base if delta == 1 else -1
		4:
			if not _fits(data, base, 4) or data.decode_u32(base) > MAX_AREA_ELEMENTS:
				return -1
			return base + 4 + 24 * data.decode_u32(base)
		_:
			return -1


static func _bitmaps(data: PackedByteArray, offset: int) -> Array[Dictionary]:
	var bitmaps: Array[Dictionary] = []
	if not _bitmap_at(data, offset, SMALL_BITMAP_BYTES, 256):
		return bitmaps
	bitmaps.append({offset = offset + 4, bytes = SMALL_BITMAP_BYTES, edge = 256})
	var second := offset + 4 + SMALL_BITMAP_BYTES + 13
	if _bitmap_at(data, second, LARGE_BITMAP_BYTES, 2048):
		bitmaps.append({offset = second + 4, bytes = LARGE_BITMAP_BYTES, edge = 2048})
	return bitmaps


static func _bitmap_at(data: PackedByteArray, offset: int, length: int, side: int) -> bool:
	if not _fits(data, offset, 4 + length) or data.decode_u32(offset) != length:
		return false
	var bmp := offset + 4
	return data.decode_u16(bmp) == 0x4d42 and data.decode_u32(bmp + 2) == length \
		and data.decode_u32(bmp + 10) == 54 and data.decode_u32(bmp + 14) == 40 \
		and data.decode_s32(bmp + 18) == side and data.decode_s32(bmp + 22) == side \
		and data.decode_u16(bmp + 26) == 1 and data.decode_u16(bmp + 28) == 32 and data.decode_u32(bmp + 30) == 0


static func _fits(data: PackedByteArray, offset: int, size: int) -> bool:
	return offset >= 0 and offset <= data.size() and size <= data.size() - offset
