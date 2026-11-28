extends RefCounted
## Phoenix RC stock `.bmp` texture reader (AC-PX). Pure data apart from the engine `Image` result.
##
## A stock texture is an ordinary uncompressed BMP file behind an 8-byte signature. When the BMP holds at
## least two 1000-byte blocks, its first 2000 bytes are stored at the end with the two blocks exchanged:
##
##     stored = signature + bmp[2000:] + bmp[1000:2000] + bmp[0:1000]
##
## so the BMP header sits 1000 bytes before the end of the file. A smaller BMP follows the signature
## unchanged. The installation's DDS images use the same wrapper. All 365 stock aircraft textures rebuild
## to a BMP whose header declares exactly the rebuilt length, and the GEO texture coordinates land on the
## painted islands (evidence: section 3.2 of docs/research/aircraft-creator/phoenix-stock-format-2026-11-20.md).
## That declared length selects the layout: a signed file that does not rebuild as wrapped is tried as
## plain. A plain BMP without the signature (a player's repaint) is read the same way.
##
## Only uncompressed 24-bit (BGR) and 32-bit (BGRA) images are admitted. The header is validated here; the
## pixel rows are then handed to Godot's BMP loader behind a canonical header written here, never the
## stored one. Phoenix uses the fourth byte of 32-bit images as alpha, but some textures leave it zero
## throughout, so `alpha` classifies it here (not with the engine's own thresholds): "none" (24-bit, or
## every pixel at least `ALPHA_OPAQUE_MIN`), "zero" (every pixel at most `ALPHA_CLEAR_MAX`: an unused
## byte), "mask" (only those two ranges, both present) or "blend". "none" and "zero" images are returned
## as RGB8 and `has_alpha` is false; `mean` still reports the stored alpha.
##
## `decode` returns `{image: Image (FORMAT_RGB8 or FORMAT_RGBA8, top row first), profile, sha256, mean,
## has_alpha, alpha}`. `mean` is the average RGBA colour in [0, 1]: exact up to `MEAN_SAMPLES` pixels,
## above that an evenly spread sample of at most that many pixels.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")

const PROFILE := "openrc-phoenix-texture-v2"
const MAX_INPUT := 64 << 20
const KIND_WRAPPED := "phoenix wrapped"
const KIND_PLAIN := "phoenix plain"
const KIND_BMP := "standard BMP"
const ALPHA_NONE := "none"
const ALPHA_ZERO := "zero"
const ALPHA_MASK := "mask"
const ALPHA_BLEND := "blend"
## Stored alpha at or below this is clear, at or above `ALPHA_OPAQUE_MIN` opaque.
const ALPHA_CLEAR_MAX := 3
const ALPHA_OPAQUE_MIN := 252
const MEAN_SAMPLES := 16384
const STEP := "import"
const SIGNATURE: PackedByteArray = [0xFF, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02]
## Size of each of the two exchanged blocks at the start of a wrapped BMP.
const BLOCK := 1000
const _HEADER := 54
const _INFO_HEADER := 40
const _BI_RGB := 0


## `value` is `{kind, width, height, channels, top_down, pixel_offset, stride, bmp_bytes, segments}`: the
## image geometry read from the validated BMP header, with `pixel_offset` and `bmp_bytes` in the rebuilt
## BMP. `segments` maps the rebuilt BMP onto `data` (`[bmp_start, data_start, length]` in BMP order).
static func texture_profile(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_INPUT:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix texture is larger than %s MiB.", "source", STEP, [str(MAX_INPUT >> 20)])
	var layouts := _layouts(data)
	if layouts.is_empty():
		if data.size() >= 2 and data[0] == 0x42 and data[1] == 0x4D:
			return R.fail(R.SOURCE_INVALID, "The Phoenix texture has an invalid image header.", "source", STEP)
		if data.size() < 8 or data.slice(0, 8) != SIGNATURE:
			return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix texture has an unrecognized file signature.", "source", STEP)
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix texture has an unrecognized layout (%s bytes).", "source", STEP,
			[str(data.size())])
	var first: Dictionary = {}
	for layout: Dictionary in layouts:
		var profile := _profile(data, layout)
		if profile.ok:
			return profile
		if first.is_empty():
			first = profile
	return first


## Decodes a stock texture (or a plain BMP) into an image with its top row first.
static func decode(data: PackedByteArray) -> Dictionary:
	var profile := texture_profile(data)
	if not profile.ok:
		return profile
	var found: Dictionary = profile.value
	var width: int = found.width
	var height: int = found.height
	var stride: int = found.stride
	var pixels := _slice(data, found.segments, found.pixel_offset, found.pixel_offset + stride * height)
	if found.top_down:
		var rows := PackedByteArray()
		for row: int in range(height - 1, -1, -1):
			rows.append_array(pixels.slice(row * stride, (row + 1) * stride))
		pixels = rows
	var image := Image.new()
	if image.load_bmp_from_buffer(_canonical_header(width, height, found.channels * 8, pixels.size()) + pixels) != OK \
			or image.is_empty() or image.get_width() != width or image.get_height() != height:
		return R.fail(R.SOURCE_INVALID, "The Phoenix texture could not be built into an image.", "source", STEP)
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var alpha := _alpha_class(image) if found.channels == 4 else ALPHA_NONE
	var mean := _mean(image)
	if alpha == ALPHA_NONE or alpha == ALPHA_ZERO:
		image.convert(Image.FORMAT_RGB8)
	return R.ok({image = image, profile = found, sha256 = CreatorBytes.sha256(data), mean = mean,
		has_alpha = alpha == ALPHA_MASK or alpha == ALPHA_BLEND, alpha = alpha})


## Candidate layouts `{kind, length, segments}` in preference order.
static func _layouts(data: PackedByteArray) -> Array:
	var size := data.size()
	if size >= _HEADER and data[0] == 0x42 and data[1] == 0x4D:
		return [{kind = KIND_BMP, length = size, segments = [[0, 0, size]]}]
	if size < 8 or data.slice(0, 8) != SIGNATURE:
		return []
	var length := size - 8
	var out: Array = []
	if length >= 2 * BLOCK and _is_bmp_at(data, size - BLOCK):
		out.append({kind = KIND_WRAPPED, length = length, segments = [[0, size - BLOCK, BLOCK],
			[BLOCK, size - 2 * BLOCK, BLOCK], [2 * BLOCK, 8, length - 2 * BLOCK]]})
	if length >= _HEADER and _is_bmp_at(data, 8):
		out.append({kind = KIND_PLAIN, length = length, segments = [[0, 8, length]]})
	return out


static func _profile(data: PackedByteArray, layout: Dictionary) -> Dictionary:
	var segments: Array = layout.segments
	var length: int = layout.length
	var kind: String = layout.kind
	var header := _slice(data, segments, 0, _HEADER)
	# The wrapped and plain layouts are proven by the header declaring exactly the rebuilt length.
	if kind != KIND_BMP and header.decode_u32(2) != length:
		return R.fail(R.SOURCE_INVALID, "The Phoenix texture header does not match its file size.", "source", STEP)
	var pixel_offset := header.decode_u32(10)
	var info_size := header.decode_u32(14)
	var width := header.decode_s32(18)
	var signed_height := header.decode_s32(22)
	var bits := header.decode_u16(28)
	if info_size < _INFO_HEADER or pixel_offset < 14 + info_size or pixel_offset > length:
		return R.fail(R.SOURCE_INVALID, "The Phoenix texture has an invalid image header.", "source", STEP)
	if header.decode_u16(26) != 1 or (bits != 24 and bits != 32) or header.decode_u32(30) != _BI_RGB:
		return R.fail(R.SOURCE_UNSUPPORTED, "Only uncompressed 24-bit and 32-bit Phoenix textures are converted.", "source", STEP)
	var height := absi(signed_height)
	if width < 1 or height < 1 or width > Limits.PNG_SIDE_PIXELS or height > Limits.PNG_SIDE_PIXELS \
			or width * height > Limits.PNG_AGGREGATE_PIXELS:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix texture exceeds the image size limit.", "source", STEP)
	var channels := bits / 8
	var stride := (width * channels + 3) & ~3
	if pixel_offset + stride * height > length:
		return R.fail(R.SOURCE_INVALID, "The Phoenix texture is shorter than its image header declares.", "source", STEP)
	return R.ok({kind = kind, width = width, height = height, channels = channels, top_down = signed_height < 0,
		pixel_offset = pixel_offset, stride = stride, bmp_bytes = length, segments = segments})


static func _is_bmp_at(data: PackedByteArray, at: int) -> bool:
	return at >= 0 and at + _HEADER <= data.size() and data[at] == 0x42 and data[at + 1] == 0x4D


## Bytes `[from, to)` of the rebuilt BMP.
static func _slice(data: PackedByteArray, segments: Array, from: int, to: int) -> PackedByteArray:
	var out := PackedByteArray()
	for segment: Array in segments:
		var start := maxi(from, int(segment[0]))
		var end := mini(to, int(segment[0]) + int(segment[2]))
		if start < end:
			var shift := int(segment[1]) - int(segment[0])
			out.append_array(data.slice(start + shift, end + shift))
	return out


## A bottom-up BITMAPINFOHEADER for `bytes` of padded pixel rows.
static func _canonical_header(width: int, height: int, bits: int, bytes: int) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(_HEADER)
	header[0] = 0x42
	header[1] = 0x4D
	header.encode_u32(2, _HEADER + bytes)
	header.encode_u32(10, _HEADER)
	header.encode_u32(14, _INFO_HEADER)
	header.encode_s32(18, width)
	header.encode_s32(22, height)
	header.encode_u16(26, 1)
	header.encode_u16(28, bits)
	header.encode_u32(30, _BI_RGB)
	header.encode_u32(34, bytes)
	return header


## Alpha class of an RGBA8 image; stops at the first graded value.
static func _alpha_class(image: Image) -> String:
	var data := image.get_data()
	var clear := false
	var opaque := false
	for index: int in range(3, data.size(), 4):
		var alpha := data[index]
		if alpha <= ALPHA_CLEAR_MAX:
			clear = true
		elif alpha >= ALPHA_OPAQUE_MIN:
			opaque = true
		else:
			return ALPHA_BLEND
	if not opaque:
		return ALPHA_ZERO
	return ALPHA_MASK if clear else ALPHA_NONE


## Average RGBA of an RGBA8 image. Above `MEAN_SAMPLES` pixels an odd stride spreads the sample over every
## column of power-of-two widths.
static func _mean(image: Image) -> Array:
	var data := image.get_data()
	var count := image.get_width() * image.get_height()
	var step := maxi(1, ceili(float(count) / MEAN_SAMPLES))
	if step > 1 and step % 2 == 0:
		step += 1
	var sums := [0, 0, 0, 0]
	var taken := 0
	for pixel: int in range(0, count, step):
		var at := pixel * 4
		for channel: int in 4:
			sums[channel] += data[at + channel]
		taken += 1
	var scale := float(taken) * 255.0
	return [sums[0] / scale, sums[1] / scale, sums[2] / scale, sums[3] / scale]
