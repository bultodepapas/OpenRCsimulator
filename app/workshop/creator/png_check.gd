extends RefCounted
## Strict, bounded PNG check for untrusted images (AC-03). Pure data until `decode`.
##
## `inspect` proves the whole file before any engine decoder sees it: signature, every chunk CRC,
## a closed chunk allow-list, chunk order, and that the IDAT stream inflates to exactly the scanline
## bytes IHDR implies, with a legal filter byte on every scanline. Only `decode` calls the engine.
##
## Refused on purpose: `iCCP`, `zTXt` and `iTXt` (metadata that expands independently of the image
## size) and every chunk outside the allow-list, so nothing reaches the decoder unchecked.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Inflate := preload("res://workshop/creator/inflate.gd")

const SIGNATURE: Array[int] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
## Signature, IHDR chunk (25 bytes) and the smallest IEND chunk.
const _HEADER_BYTES := 33
## Colour type -> legal bit depths and channel count.
const _DEPTHS := {0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]}
const _CHANNELS := {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
## Ancillary chunks admitted once, before IDAT, with their exact payload length.
const _ANCILLARY := {"sRGB": 1, "gAMA": 4, "cHRM": 32, "pHYs": 9}
const _EXPANDING := ["iCCP", "zTXt", "iTXt"]
## Passive metadata common image editors write. It is bounded, never expands and does not change
## the decoded pixels, so it is admitted and ignored: plain text, modification time, background.
const _PASSIVE := ["tEXt", "tIME", "bKGD"]
const _TEXT_CHUNK_BYTES := 65536
## Adam7 passes: first column, first row, column step, row step.
const _ADAM7 := [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]
## Below this size the table CRC beats the engine's gzip call.
const _CRC_NATIVE_BYTES := 256
const _REEXPORT := "Re-export the image as a standard PNG without colour profiles or text metadata."

static var _crc_table := PackedInt64Array()


## Full structural check. `value = {width, height, bit_depth, color_type, channels, interlaced,
## has_alpha, pixels, decoded_bytes}`; `decoded_bytes` is the exact size the IDAT stream inflates
## to (scanlines with their filter bytes), which is what the check bounds.
static func inspect(bytes: PackedByteArray) -> Dictionary:
	var head := header(bytes)
	if not head.ok:
		return head
	var info: Dictionary = head.value
	var size := bytes.size()
	var color_type := int(info.color_type)
	var seen := {}
	var palette_entries := 0
	var data_state := 0  # 0: before IDAT, 1: inside the IDAT run, 2: after it
	var parts: Array[PackedByteArray] = []
	var ended := false
	var chunks := 1
	var offset := _HEADER_BYTES
	while offset < size:
		if size - offset < 12:
			return _invalid("The image file is truncated inside a chunk.")
		chunks += 1
		if chunks > Limits.PNG_CHUNKS:
			return R.fail(R.SOURCE_LIMIT, "The image has more than %s chunks. " + _REEXPORT, "", "",
				[str(Limits.PNG_CHUNKS)])
		var length := _be32(bytes, offset)
		if length > size - offset - 12:
			return _invalid("The image file is truncated inside a chunk.")
		var kind := _chunk_type(bytes, offset + 4)
		if kind.is_empty():
			return _invalid("The image has a chunk with an invalid type.")
		if kind in _EXPANDING:
			return R.fail(R.SOURCE_UNSUPPORTED, "The image holds metadata of type %s, which is not accepted. " + _REEXPORT,
				"", "", [kind])
		if kind not in ["IHDR", "PLTE", "tRNS", "IDAT", "IEND"] and not _ANCILLARY.has(kind) and kind not in _PASSIVE:
			return R.fail(R.SOURCE_UNSUPPORTED, "The image holds a chunk of type %s, which is not supported. " + _REEXPORT,
				"", "", [kind])
		if crc32(bytes.slice(offset + 4, offset + 8 + length)) != _be32(bytes, offset + 8 + length):
			return _invalid("The image is damaged: its %s chunk fails its checksum.", [kind])
		# Every chunk the allow-list admits after IDAT is refused or ends the file, so IDAT chunks
		# are consecutive already; the explicit state keeps that true if the list ever changes.
		if kind != "IDAT" and data_state == 1:
			data_state = 2
		if kind in _PASSIVE:
			var passive := _passive_problem(kind, length, seen, data_state)
			if not passive.is_empty():
				return _invalid(passive, [kind])
			seen[kind] = true
			offset += 12 + length
			continue
		match kind:
			"IHDR":
				return _invalid("The image has more than one header chunk.")
			"IDAT":
				if data_state == 2:
					return _invalid("The image data chunks are not consecutive.")
				if color_type == 3 and not seen.has("PLTE"):
					return _invalid("The indexed image has no palette before its data.")
				data_state = 1
				if length > 0:
					parts.append(bytes.slice(offset + 8, offset + 8 + length))
			"IEND":
				if length != 0:
					return _invalid("The image end chunk is not empty.")
				if data_state == 0:
					return _invalid("The image has no image data.")
				if offset + 12 != size:
					return _invalid("Extra bytes follow the end of the image.")
				ended = true
			_:
				if seen.has(kind):
					return _invalid("The image has more than one %s chunk.", [kind])
				if data_state != 0:
					return _invalid("The image has its %s chunk after the image data.", [kind])
				seen[kind] = true
				var problem := ""
				if kind == "PLTE":
					palette_entries = length / 3
					problem = _palette_problem(color_type, int(info.bit_depth), length, seen)
				elif kind == "tRNS":
					problem = _transparency_problem(color_type, length, seen, palette_entries)
				else:
					problem = _ancillary_problem(kind, bytes, offset + 8, length, seen)
				if not problem.is_empty():
					return _invalid(problem, [kind] if problem.contains("%s") else [])
		if ended:
			break
		offset += 12 + length
	if not ended:
		return _invalid("The image file ends without its end chunk.")

	var layout := scanline_layout(int(info.width), int(info.height), int(info.bit_depth) * int(info.channels),
		bool(info.interlaced))
	var rows := RowScan.new(layout)
	var report: Dictionary = Inflate.zlib_scan(parts, int(info.decoded_bytes), false, rows.feed)
	match str(report.status):
		Inflate.STATUS_OK:
			pass
		Inflate.STATUS_SINK:
			return _invalid("The image data uses an invalid scanline filter.")
		Inflate.STATUS_HEADER:
			return _invalid("The image data is not a valid zlib stream.")
		Inflate.STATUS_SHORT, Inflate.STATUS_TRUNCATED:
			return _invalid("The image data is truncated: it holds less than the image size requires.")
		Inflate.STATUS_EXCESS:
			return _invalid("The image data holds more than the image size allows.")
		Inflate.STATUS_TRAILING:
			return _invalid("Extra bytes follow the compressed image data.")
		Inflate.STATUS_WINDOW:
			return R.fail(R.SOURCE_UNSUPPORTED, "The image is compressed with an unusual window size. " + _REEXPORT)
		_:
			return _invalid("The image data is corrupt. " + _REEXPORT)
	info.has_alpha = color_type == 4 or color_type == 6 or seen.has("tRNS")
	return R.ok(info)


## Cheap first look: size ceiling, signature and a CRC-checked IHDR. It bounds the image before
## any larger work, so callers can enforce an aggregate budget before `inspect` inflates anything.
## Same `value` as `inspect`, with `has_alpha` covering the colour type only.
static func header(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > Limits.PNG_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The image file is larger than %s MiB. Reduce its resolution and re-export it.",
			"", "", [str(Limits.PNG_BYTES / Limits.MIB)])
	if bytes.size() < _HEADER_BYTES + 12:
		return _invalid("The file is too short to be a PNG image.")
	for index: int in SIGNATURE.size():
		if bytes[index] != SIGNATURE[index]:
			return _invalid("The file is not a PNG image. Export the texture as PNG.")
	if _be32(bytes, 8) != 13 or _chunk_type(bytes, 12) != "IHDR":
		return _invalid("The image does not start with a valid header chunk.")
	if crc32(bytes.slice(12, 29)) != _be32(bytes, 29):
		return _invalid("The image is damaged: its %s chunk fails its checksum.", ["IHDR"])
	var width := _be32(bytes, 16)
	var height := _be32(bytes, 20)
	if width < 1 or height < 1:
		return _invalid("The image has a zero width or height.")
	if width > Limits.PNG_SIDE_PIXELS or height > Limits.PNG_SIDE_PIXELS:
		return R.fail(R.SOURCE_LIMIT, "The image is %s x %s pixels; the largest accepted side is %s pixels.",
			"", "", [str(width), str(height), str(Limits.PNG_SIDE_PIXELS)])
	var bit_depth := int(bytes[24])
	var color_type := int(bytes[25])
	if not _DEPTHS.has(color_type) or bit_depth not in _DEPTHS[color_type]:
		return _invalid("The image has an invalid colour type or bit depth.")
	if bytes[26] != 0 or bytes[27] != 0 or bytes[28] > 1:
		return _invalid("The image has an invalid compression, filter or interlace method.")
	var channels := int(_CHANNELS[color_type])
	var interlaced := bytes[28] == 1
	var decoded_bytes := 0
	var layout := scanline_layout(width, height, bit_depth * channels, interlaced)
	for index: int in range(0, layout.size(), 2):
		decoded_bytes += layout[index] * layout[index + 1]
	return R.ok({width = width, height = height, bit_depth = bit_depth, color_type = color_type,
		channels = channels, interlaced = interlaced, has_alpha = color_type == 4 or color_type == 6,
		pixels = width * height, decoded_bytes = decoded_bytes})


## Runs `inspect`, and only then the engine decoder. `value = {image: Image, info}`.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var checked := inspect(bytes)
	if not checked.ok:
		return checked
	var info: Dictionary = checked.value
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.get_width() != int(info.width) \
			or image.get_height() != int(info.height):
		return _invalid("The image could not be decoded. " + _REEXPORT)
	return R.ok({image = image, info = info})


## Pixels one inspected image decodes to; sum them against `Limits.PNG_AGGREGATE_PIXELS`.
static func decoded_pixels(value: Dictionary) -> int:
	return int(value.get("pixels", 0))


## Total pixels of several `inspect`/`header` values.
static func aggregate_pixels(values: Array) -> int:
	var total := 0
	for value: Variant in values:
		if value is Dictionary:
			total += decoded_pixels(value)
	return total


## Scanline groups as flat pairs `[row_bytes, rows, ...]`; `row_bytes` includes the filter byte.
## One pair without interlace, otherwise one per non-empty Adam7 pass.
static func scanline_layout(width: int, height: int, bits_per_pixel: int, interlaced: bool) -> PackedInt64Array:
	var layout := PackedInt64Array()
	if not interlaced:
		layout.append(1 + (width * bits_per_pixel + 7) / 8)
		layout.append(height)
		return layout
	for step: Array in _ADAM7:
		var columns: int = (width - step[0] + step[2] - 1) / step[2]
		var rows: int = (height - step[1] + step[3] - 1) / step[3]
		if columns > 0 and rows > 0:
			layout.append(1 + (columns * bits_per_pixel + 7) / 8)
			layout.append(rows)
	return layout


## PNG/zlib CRC-32. Large inputs use the trailer of the engine's gzip writer (native speed, same
## polynomial); small ones and any unexpected gzip result use the table.
static func crc32(bytes: PackedByteArray) -> int:
	if bytes.size() >= _CRC_NATIVE_BYTES:
		var packed := bytes.compress(FileAccess.COMPRESSION_GZIP)
		if packed.size() >= 18 and packed.decode_u32(packed.size() - 4) == (bytes.size() & 0xFFFFFFFF):
			return packed.decode_u32(packed.size() - 8)
	return crc32_table(bytes)


## Table-driven CRC-32 (reflected polynomial 0xEDB88320).
static func crc32_table(bytes: PackedByteArray) -> int:
	if _crc_table.is_empty():
		var table := PackedInt64Array()
		table.resize(256)
		for index: int in 256:
			var entry := index
			for _bit: int in 8:
				entry = ((entry >> 1) ^ 0xEDB88320) if (entry & 1) != 0 else (entry >> 1)
			table[index] = entry
		_crc_table = table
	var crc := 0xFFFFFFFF
	for byte: int in bytes:
		crc = _crc_table[(crc ^ byte) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


static func _palette_problem(color_type: int, bit_depth: int, length: int, seen: Dictionary) -> String:
	if color_type == 0 or color_type == 4:
		return "The greyscale image holds a palette."
	if length == 0 or length % 3 != 0 or length / 3 > 256:
		return "The image palette has an invalid size."
	if color_type == 3 and length / 3 > (1 << bit_depth):
		return "The image palette has more entries than its bit depth can address."
	if seen.has("tRNS"):
		return "The image transparency chunk comes before its palette."
	return ""


static func _transparency_problem(color_type: int, length: int, seen: Dictionary, palette_entries: int) -> String:
	match color_type:
		0:
			return "" if length == 2 else "The image transparency chunk has an invalid size."
		2:
			return "" if length == 6 else "The image transparency chunk has an invalid size."
		3:
			if not seen.has("PLTE"):
				return "The image transparency chunk comes before its palette."
			return "" if length >= 1 and length <= palette_entries else "The image transparency chunk has an invalid size."
	return "The image has both an alpha channel and a transparency chunk."


static func _ancillary_problem(kind: String, bytes: PackedByteArray, at: int, length: int, seen: Dictionary) -> String:
	if length != int(_ANCILLARY[kind]):
		return "The image's %s chunk has the wrong size."
	if kind != "pHYs" and seen.has("PLTE"):
		return "The image's %s chunk comes after its palette."
	if kind == "sRGB" and bytes[at] > 3:
		return "The image has an invalid sRGB rendering intent."
	if kind == "gAMA" and _be32(bytes, at) == 0:
		return "The image has a zero gamma value."
	if kind == "pHYs" and bytes[at + 8] > 1:
		return "The image has an invalid pixel-size unit."
	return ""


static func _passive_problem(kind: String, length: int, seen: Dictionary, data_state: int) -> String:
	match kind:
		"tEXt":
			return "" if length <= _TEXT_CHUNK_BYTES else "The image's %s chunk is too large."
		"tIME":
			return "" if length == 7 and not seen.has(kind) else "The image's %s chunk is invalid."
		"bKGD":
			return "" if length in [1, 2, 6] and not seen.has(kind) and data_state == 0 else "The image's %s chunk is invalid."
	return "The image's %s chunk is invalid."


static func _invalid(message: String, arguments: Array = []) -> Dictionary:
	return R.fail(R.SOURCE_INVALID, message, "", "", arguments)


## Big-endian uint32. GDScript ints are 64-bit, so the value is never negative.
static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## The four-letter chunk type, or "" when a byte is not an ASCII letter.
static func _chunk_type(bytes: PackedByteArray, at: int) -> String:
	for index: int in 4:
		var code := bytes[at + index]
		if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
			return ""
	return bytes.slice(at, at + 4).get_string_from_ascii()


## Inflate sink: checks the filter byte that starts every scanline without keeping the output.
class RowScan extends RefCounted:
	var refused := false
	var _layout: PackedInt64Array
	var _group := -2
	var _row_bytes := 0
	var _rows_left := 0
	## Stream offset of the next filter byte; -1 once every scanline has been seen.
	var _next := 0

	func _init(layout: PackedInt64Array) -> void:
		_layout = layout
		_advance_group()

	func feed(chunk: PackedByteArray, offset: int) -> bool:
		var end := offset + chunk.size()
		while _next >= 0 and _next < end:
			if chunk[_next - offset] > 4:
				refused = true
				return false
			_next += _row_bytes
			_rows_left -= 1
			if _rows_left == 0:
				_advance_group()
		return true

	func _advance_group() -> void:
		_group += 2
		if _group >= _layout.size():
			_next = -1
			return
		_row_bytes = _layout[_group]
		_rows_left = _layout[_group + 1]
