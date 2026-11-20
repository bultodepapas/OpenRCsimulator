extends SceneTree

const Images := preload("res://landscapes/phoenix_images.gd")
var failures := 0

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		print("FAIL ", description)

func _fixture(format: String, size: int = 64) -> PackedByteArray:
	var block_bytes := 8 if format == "DXT1" else 16
	var blocks_per_row := size >> 2
	var data := PackedByteArray()
	data.resize(128 + blocks_per_row * blocks_per_row * block_bytes)
	data[0] = 68
	data[1] = 68
	data[2] = 83
	data[3] = 32
	data.encode_u32(4, 124)
	data.encode_u32(8, 0x81007)
	data.encode_u32(12, size)
	data.encode_u32(16, size)
	data.encode_u32(20, data.size() - 128)
	data.encode_u32(76, 32)
	data.encode_u32(80, 4)
	for i: int in 4:
		data[84 + i] = format.to_ascii_buffer()[i]
	data.encode_u32(108, 0x1000)
	for block in blocks_per_row * blocks_per_row:
		var at := 128 + block * block_bytes
		var colour := at
		if block_bytes == 16:
			if format == "DXT3":
				for i: int in 8:
					data[at + i] = 0xff
			else:
				data[at] = 0xff
			colour += 8
		var column := block % blocks_per_row
		data.encode_u16(colour, 0xf800 if column < (blocks_per_row >> 1) else 0x001f)
		data.encode_u16(colour + 2, 0x001f)
	return data

func _initialize() -> void:
	for format: String in ["DXT1", "DXT3", "DXT5"]:
		var bytes := _fixture(format)
		var image: Image = Images.decode_panel(bytes, 16)
		_check(image != null, format + " accepted")
		if image != null:
			_check(image.get_width() == 16 and image.get_height() == 16, format + " resized")
			_check(image.get_pixel(0, 0).r > 0.95, format + " red block")
			_check(image.get_pixel(15, 0).b > 0.95, format + " blue block")
		var stored := bytes.slice(0, 128)
		stored.append_array(bytes.slice(1128))
		stored.append_array(bytes.slice(128, 1128))
		var wrapped := PackedByteArray([255,128,64,32,16,8,4,2])
		wrapped.append_array(stored.slice(1000))
		wrapped.append_array(stored.slice(0, 1000))
		var wrapped_image: Image = Images.decode_panel(wrapped, 16)
		_check(wrapped_image != null, format + " wrapped")
		if wrapped_image != null:
			_check(wrapped_image.get_pixel(0, 0).r > 0.95, format + " wrapped red block")
			_check(wrapped_image.get_pixel(15, 0).b > 0.95, format + " wrapped blue block")
		_check(Images.decode_panel(bytes.slice(0, bytes.size() - 1)) == null, format + " truncation")
	var jpeg := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	jpeg.fill(Color.RED)
	_check(Images.decode_panel(jpeg.save_jpg_to_buffer()) != null, "generated JPEG")
	var rgba := PackedByteArray()
	rgba.resize(132)
	for i: int in 4:
		rgba[i] = [68, 68, 83, 32][i]
	rgba.encode_u32(4, 124)
	rgba.encode_u32(8, 0x100f)
	rgba.encode_u32(12, 1)
	rgba.encode_u32(16, 1)
	rgba.encode_u32(20, 4)
	rgba.encode_u32(76, 32)
	rgba.encode_u32(80, 0x41)
	rgba.encode_u32(88, 32)
	rgba.encode_u32(92, 0x00ff0000)
	rgba.encode_u32(96, 0x0000ff00)
	rgba.encode_u32(100, 0x000000ff)
	rgba.encode_u32(104, 0xff000000)
	rgba.encode_u32(108, 0x1000)
	rgba[128] = 10
	rgba[129] = 20
	rgba[130] = 30
	rgba[131] = 40
	var rgb_image: Image = Images.decode_panel(rgba)
	_check(rgb_image != null, "uncompressed DDS")
	if rgb_image != null:
		var color := rgb_image.get_pixel(0, 0)
		_check(is_equal_approx(color.r, 30.0 / 255.0), "DDS red mask")
		_check(is_equal_approx(color.b, 10.0 / 255.0), "DDS blue mask")
		_check(is_equal_approx(color.a, 40.0 / 255.0), "DDS alpha mask")
	var rgb24 := rgba.slice(0, 128)
	rgb24.encode_u32(8, 0x81007)
	rgb24.encode_u32(16, 2)
	rgb24.encode_u32(20, 6)
	rgb24.encode_u32(80, 0x40)
	rgb24.encode_u32(88, 24)
	rgb24.encode_u32(104, 0)
	rgb24.append_array(PackedByteArray([10, 20, 30, 40, 50, 60]))
	var rgb24_image: Image = Images.decode_panel(rgb24)
	_check(rgb24_image != null, "packed 24-bit DDS")
	if rgb24_image != null:
		_check(rgb24_image.get_format() == Image.FORMAT_RGB8, "24-bit DDS has no alpha")
		_check(rgb24_image.get_data() == PackedByteArray([30, 20, 10, 60, 50, 40]), "24-bit DDS BGR stride")
	_check(Images.decode_panel(rgb24.slice(0, rgb24.size() - 1)) == null, "24-bit DDS truncation")
	rgb24.encode_u32(80, 0x41)
	_check(Images.decode_panel(rgb24) == null, "24-bit DDS alpha flag refused")
	rgb24.encode_u32(80, 0x40)
	rgb24.encode_u32(8, 0x100f)
	rgb24.encode_u32(20, 8)
	_check(Images.decode_panel(rgb24) == null, "24-bit DDS contradictory row pitch refused")
	_check(Images.decode_panel(_fixture("DXT1"), 0) == null, "invalid output size")
	var cube := _fixture("DXT1")
	cube.encode_u32(112, 0x200)
	_check(Images.decode_panel(cube) == null, "cube refused")
	_check(Images.decode_panel(PackedByteArray([0, 1])) == null, "unsupported data")
	print("Phoenix image tests: ", failures, " failed")
	quit(0 if failures == 0 else 1)
