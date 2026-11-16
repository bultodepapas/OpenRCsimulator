extends RefCounted
## Texture normalization. PNG uses Creator's strict validator; uncompressed 24-bit BMP is
## decoded here without a native bitmap parser. Other source formats require their own gate.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const PngCheck := preload("res://workshop/creator/png_check.gd")
const JpegCheck := preload("jpeg_check.gd")

static func normalize(bytes: PackedByteArray, cancel := Callable(), remaining_pixels := Limits.PNG_AGGREGATE_PIXELS) -> Dictionary:
	if bytes.is_empty() or bytes.size() > Limits.PNG_BYTES:
		return R.fail(R.SOURCE_LIMIT, "A model texture is empty or larger than 16 MiB.", "source", "import")
	if bytes.size() >= 8 and bytes.slice(0, 8) == PackedByteArray(PngCheck.SIGNATURE):
		var header := PngCheck.header(bytes)
		if not header.ok:
			return header
		if header.value.pixels > remaining_pixels:
			return R.fail(R.SOURCE_LIMIT, "The model exceeds its total texture pixel limit.", "source", "import")
		var checked := PngCheck.decode(bytes)
		if not checked.ok:
			return checked
		return R.ok({png = bytes, width = checked.value.info.width, height = checked.value.info.height,
			pixels = checked.value.info.pixels, has_alpha = checked.value.info.has_alpha})
	if bytes.size() >= 2 and bytes[0] == 66 and bytes[1] == 77:
		return _bmp(bytes, cancel, remaining_pixels)
	if bytes.size() >= 2 and bytes[0] == 255 and bytes[1] == 0xD8:
		var checked := JpegCheck.inspect(bytes, remaining_pixels, cancel)
		if not checked.ok:
			return checked
		if cancel.is_valid() and bool(cancel.call()):
			return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", "import")
		var image := Image.new()
		if image.load_jpg_from_buffer(bytes) != OK or image.get_width() != checked.value.width or image.get_height() != checked.value.height or image.get_format() != Image.FORMAT_RGB8:
			return R.fail(R.SOURCE_INVALID, "The JPEG decoder did not produce the validated image.", "source", "import")
		return R.ok({png = image.save_png_to_buffer(), width = checked.value.width, height = checked.value.height,
			pixels = checked.value.pixels, has_alpha = false}, checked.diagnostics)
	return R.fail(R.SOURCE_UNSUPPORTED, "This texture format is not supported yet. Convert the texture to a standard PNG or 24-bit uncompressed BMP and update its model reference.", "source", "import")

static func _bmp(bytes: PackedByteArray, cancel: Callable, remaining_pixels: int) -> Dictionary:
	if bytes.size() < 54 or bytes.decode_u32(14) != 40 or bytes.decode_u16(26) != 1 or bytes.decode_u16(28) != 24 or bytes.decode_u32(30) != 0:
		return R.fail(R.SOURCE_UNSUPPORTED, "Only 24-bit uncompressed BITMAPINFOHEADER textures are supported.", "source", "import")
	var width := bytes.decode_s32(18)
	var signed_height := bytes.decode_s32(22)
	var height := absi(signed_height)
	if width < 1 or height < 1 or width > Limits.PNG_SIDE_PIXELS or height > Limits.PNG_SIDE_PIXELS or width * height > mini(remaining_pixels, Limits.PNG_AGGREGATE_PIXELS):
		return R.fail(R.SOURCE_LIMIT, "The bitmap dimensions exceed the texture limits.", "source", "import")
	var stride := (width * 3 + 3) & ~3
	var offset := bytes.decode_u32(10)
	if bytes.decode_u32(2) != bytes.size() or bytes.decode_u32(6) != 0 or offset != 54 or offset + stride * height != bytes.size() or bytes.decode_u32(34) not in [0, stride * height] or bytes.decode_u32(46) != 0:
		return R.fail(R.SOURCE_INVALID, "The bitmap header, row sizes or pixel data are inconsistent.", "source", "import")
	var pixels := PackedByteArray()
	pixels.resize(width * height * 3)
	for row: int in height:
		if cancel.is_valid() and bool(cancel.call()):
			return R.fail(R.SOURCE_INVALID, "The import was cancelled.", "source", "import")
		var source := offset + stride * (height - row - 1 if signed_height > 0 else row)
		var destination := row * width * 3
		for column: int in width:
			pixels[destination] = bytes[source + 2]
			pixels[destination + 1] = bytes[source + 1]
			pixels[destination + 2] = bytes[source]
			destination += 3
			source += 3
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGB8, pixels)
	return R.ok({png = image.save_png_to_buffer(), width = width, height = height, pixels = width * height, has_alpha = false})
