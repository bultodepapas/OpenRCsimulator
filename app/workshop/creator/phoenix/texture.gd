extends RefCounted
## Phoenix RC stock `.bmp` texture reader (AC-PX). Pure data apart from the engine `Image` result.
##
## Port of the `texture_profile` / `png_from_texture` rule in `research/aircraft-creator/phoenix/inspect_geo.py`.
## The stock file has an 8-byte magic, an overwritten BMP header and BGR(A) rows stored bottom-up.
## The colour phase was fixed on known liveries: pixel data begins one byte before
## `size - width * height * channels`. Dimensions are not stored: they are inferred from the size
## (power-of-two sides) and, between non-square candidates or several squares, by adjacent-row
## similarity. Only 3-channel (BGR) files are decoded: 4-channel layouts are unverified and refused.
##
## `decode` returns `{image: Image (FORMAT_RGB8, top row first), profile, sha256}`.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const CreatorBytes := preload("res://workshop/creator/bytes.gd")

const MAX_INPUT := 64 << 20
const MIN_SIDE := 4
const MAX_SIDE := 4096
const ROUGHNESS_ROWS := 64
const ROUGHNESS_STRIDE := 7
const KIND_RAW := "phoenix raw"
const KIND_BMP := "standard BMP"
const STEP := "import"
const _MAGIC: PackedByteArray = [0xFF, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02]
const _CHANNELS: Array[int] = [3, 4]
const _HEADERS: Array[int] = [54, 56]


## `value` is `{kind: "standard BMP"}` or `{kind: "phoenix raw", width, height, channels, pixel_offset,
## candidates}`.
static func texture_profile(data: PackedByteArray) -> Dictionary:
	if data.size() > MAX_INPUT:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix texture is larger than %s MiB.", "source", STEP, [str(MAX_INPUT >> 20)])
	if data.size() >= 2 and data[0] == 0x42 and data[1] == 0x4D:
		return R.ok({kind = KIND_BMP})
	if data.size() < 8 or data.slice(0, 8) != _MAGIC:
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix texture has an unrecognized file signature.", "source", STEP)
	var candidates: Array[Array] = []
	for channels: int in _CHANNELS:
		for header: int in _HEADERS:
			var size := data.size() - 8 - header
			if size <= 0 or size % channels != 0:
				continue
			var pixels := size / channels
			var width := MIN_SIDE
			while width <= MAX_SIDE:
				if pixels % width == 0:
					var height := pixels / width
					if height >= MIN_SIDE and height <= MAX_SIDE and (height & (height - 1)) == 0:
						candidates.append([width, height, channels, data.size() - size - 1])
				width *= 2
	if candidates.is_empty():
		return R.fail(R.SOURCE_UNSUPPORTED, "The Phoenix texture has an unrecognized layout (%s bytes).", "source", STEP,
			[str(data.size())])
	var square: Array[Array] = []
	var near: Array[Array] = []
	for entry: Array in candidates:
		if entry[0] == entry[1]:
			square.append(entry)
		if maxi(entry[0], entry[1]) <= 2 * mini(entry[0], entry[1]):
			near.append(entry)
	var pool: Array[Array] = square if not square.is_empty() else (near if not near.is_empty() else candidates)
	var best: Array = pool[0]
	if pool.size() > 1:
		var lowest := -1
		for entry: Array in pool:
			var rough := _roughness(data, entry)
			if lowest < 0 or rough < lowest:
				lowest = rough
				best = entry
	return R.ok({kind = KIND_RAW, width = best[0], height = best[1], channels = best[2], pixel_offset = best[3],
		candidates = candidates.size()})


## Decodes a verified BGR texture to an RGB8 image with its top row first.
static func decode(data: PackedByteArray) -> Dictionary:
	var profile := texture_profile(data)
	if not profile.ok:
		return profile
	var found: Dictionary = profile.value
	if found.kind != KIND_RAW:
		return R.fail(R.SOURCE_UNSUPPORTED, "Only the observed raw Phoenix texture layout is converted.", "source", STEP)
	var width: int = found.width
	var height: int = found.height
	var channels: int = found.channels
	if channels != 3:
		return R.fail(R.SOURCE_UNSUPPORTED, "Four-channel Phoenix textures are not verified and are not converted.",
			"source", STEP)
	if width > Limits.PNG_SIDE_PIXELS or height > Limits.PNG_SIDE_PIXELS or width * height > Limits.PNG_AGGREGATE_PIXELS:
		return R.fail(R.SOURCE_LIMIT, "The Phoenix texture exceeds the image size limit.", "source", STEP)
	var offset: int = found.pixel_offset
	var stride: int = width * 3
	var out := PackedByteArray()
	out.resize(stride * height)
	for y: int in height: # stored bottom-up as BGR
		var from := offset + (height - 1 - y) * stride
		var to := y * stride
		for x: int in range(0, stride, 3):
			out[to + x] = data[from + x + 2]
			out[to + x + 1] = data[from + x + 1]
			out[to + x + 2] = data[from + x]
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGB8, out)
	if image == null or image.is_empty():
		return R.fail(R.SOURCE_INVALID, "The Phoenix texture could not be built into an image.", "source", STEP)
	return R.ok({image = image, profile = found, sha256 = CreatorBytes.sha256(data)})


## Sum of absolute differences of every seventh byte of adjacent rows, as the Python probe measures it.
static func _roughness(data: PackedByteArray, entry: Array) -> int:
	var width: int = entry[0]
	var height: int = entry[1]
	var offset: int = entry[3]
	var channels: int = entry[2]
	var stride: int = width * channels
	var rows := mini(height - 1, ROUGHNESS_ROWS)
	var step := maxi(1, (height - 1) / rows)
	var total := 0
	for y: int in range(0, height - 1, step):
		var upper: int = offset + y * stride
		var lower: int = offset + (y + 1) * stride
		for x: int in range(0, stride, ROUGHNESS_STRIDE):
			total += absi(data[upper + x] - data[lower + x])
	return total
