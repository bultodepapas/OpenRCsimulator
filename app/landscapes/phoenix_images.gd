extends RefCounted
## Decode a single scenery panel. The returned image is an owned, uncompressed image.

const JpegCheck := preload("res://workshop/creator/clearview/jpeg_check.gd")
const MAX_INPUT_BYTES := 64 * 1024 * 1024
const MAX_SOURCE_EDGE := 8192
const MAX_SOURCE_PIXELS := 32 * 1024 * 1024
const MAX_OUTPUT_EDGE := 4096
const DDS_HEADER_BYTES := 128
const DDS_PITCH := 0x8
const DDS_FOURCC := 0x4
const DDS_RGB := 0x40
const DDS_ALPHA_PIXELS := 0x1
const DDS_ALPHA_ONLY := 0x2
const DDS_CUBEMAP := 0x200
const DDS_VOLUME := 0x200000
const WRAPPER_MAGIC := [0xff, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02]


## Supports Phoenix 5.5.k wrapped DDS, ordinary DDS, and baseline JPEG.
## A cubemap, an unsupported format or an inconsistent header yields null.
static func decode_panel(raw: PackedByteArray, max_edge: int = 1024, cancelled := Callable()) -> Image:
	if raw.is_empty() or raw.size() > MAX_INPUT_BYTES or max_edge < 1:
		return null
	var image: Image
	if raw.size() >= 2 and raw[0] == 0xff and raw[1] == 0xd8:
		image = _decode_jpeg(raw, cancelled)
	else:
		image = _decode_dds(raw)
	if image == null or image.is_empty():
		return null
	var target_edge := mini(max_edge, MAX_OUTPUT_EDGE)
	var longest := maxi(image.get_width(), image.get_height())
	if longest > target_edge:
		var scale := float(target_edge) / float(longest)
		var width := maxi(1, roundi(image.get_width() * scale))
		var height := maxi(1, roundi(image.get_height() * scale))
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return image


static func _decode_jpeg(raw: PackedByteArray, cancelled: Callable) -> Image:
	var result := JpegCheck.inspect(raw, MAX_SOURCE_PIXELS, cancelled)
	if not result.ok:
		return null
	var image := Image.new()
	if image.load_jpg_from_buffer(raw) != OK:
		return null
	if image.get_width() != result.value.width or image.get_height() != result.value.height:
		return null
	return image


static func _decode_dds(raw: PackedByteArray) -> Image:
	var data := raw
	if raw.size() >= 1008 and raw.slice(0, 8) == PackedByteArray(WRAPPER_MAGIC):
		# The DDS header is 1000 bytes from EOF. Recover the header and restore
		# the displaced pixel payload.
		if raw.size() < 2008:
			return null
		data = raw.slice(raw.size() - 1000, raw.size() - 872)
		data.append_array(raw.slice(raw.size() - 2000, raw.size() - 1000))
		data.append_array(raw.slice(raw.size() - 872))
		data.append_array(raw.slice(8, raw.size() - 2000))
	if data.size() < DDS_HEADER_BYTES or data.slice(0, 4) != PackedByteArray([68, 68, 83, 32]):
		return null
	if data.decode_u32(4) != 124 or data.decode_u32(76) != 32:
		return null
	var width := data.decode_u32(16)
	var height := data.decode_u32(12)
	if width < 1 or height < 1 or width > MAX_SOURCE_EDGE or height > MAX_SOURCE_EDGE:
		return null
	if width * height > MAX_SOURCE_PIXELS:
		return null
	var caps2 := data.decode_u32(112)
	if (caps2 & (DDS_CUBEMAP | DDS_VOLUME)) != 0:
		return null
	var flags := data.decode_u32(80)
	var format := -1
	var block_bytes := 0
	var bytes_per_pixel := 0
	var has_alpha := false
	if (flags & DDS_FOURCC) != 0:
		match data.slice(84, 88).get_string_from_ascii():
			"DXT1":
				format = Image.FORMAT_DXT1
				block_bytes = 8
			"DXT3":
				format = Image.FORMAT_DXT3
				block_bytes = 16
			"DXT5":
				format = Image.FORMAT_DXT5
				block_bytes = 16
			_:
				return null
	elif (flags & DDS_RGB) != 0:
		var bits_per_pixel := data.decode_u32(88)
		if bits_per_pixel != 24 and bits_per_pixel != 32:
			return null
		bytes_per_pixel = bits_per_pixel >> 3
		if data.decode_u32(92) != 0x00ff0000 or data.decode_u32(96) != 0x0000ff00 or data.decode_u32(100) != 0x000000ff:
			return null
		var alpha_mask := data.decode_u32(104)
		if alpha_mask != 0 and alpha_mask != 0xff000000:
			return null
		has_alpha = (flags & DDS_ALPHA_PIXELS) != 0
		if bits_per_pixel == 24:
			# Phoenix RGB24 panels use tightly packed BGR pixels.
			if alpha_mask != 0 or (flags & (DDS_ALPHA_PIXELS | DDS_ALPHA_ONLY)) != 0:
				return null
			if (data.decode_u32(8) & DDS_PITCH) != 0 and data.decode_u32(20) != width * bytes_per_pixel:
				return null
		if has_alpha and alpha_mask != 0xff000000:
			return null
	else:
		return null
	var mip_count := maxi(1, data.decode_u32(28))
	var max_mips := 1
	var largest := maxi(width, height)
	while largest > 1:
		largest >>= 1
		max_mips += 1
	if mip_count > max_mips:
		return null
	var expected := DDS_HEADER_BYTES
	var mip_width := width
	var mip_height := height
	var first_size := 0
	for level: int in mip_count:
		var size := mip_width * mip_height * bytes_per_pixel
		if block_bytes > 0:
			size = ((mip_width + 3) >> 2) * ((mip_height + 3) >> 2) * block_bytes
		if level == 0:
			first_size = size
		expected += size
		mip_width = maxi(1, mip_width >> 1)
		mip_height = maxi(1, mip_height >> 1)
	if expected != data.size():
		return null
	var pixels := data.slice(DDS_HEADER_BYTES, DDS_HEADER_BYTES + first_size)
	if block_bytes > 0:
		var image := Image.create_from_data(width, height, false, format, pixels)
		if image == null or image.is_empty() or image.decompress() != OK:
			return null
		return image
	for i: int in range(0, pixels.size(), bytes_per_pixel):
		var blue := pixels[i]
		pixels[i] = pixels[i + 2]
		pixels[i + 2] = blue
		if bytes_per_pixel == 4 and not has_alpha:
			pixels[i + 3] = 255
	var rgb_format := Image.FORMAT_RGB8 if bytes_per_pixel == 3 else Image.FORMAT_RGBA8
	return Image.create_from_data(width, height, false, rgb_format, pixels)
