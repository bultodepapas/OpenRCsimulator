extends SceneTree
## AC-03: bounded zlib inflate and strict PNG check before any engine decoder.
## Every fixture is built here from code; hostile ones must be refused without an engine log line.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Inflate := preload("res://workshop/creator/inflate.gd")
const PngCheck := preload("res://workshop/creator/png_check.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_crc()
	_test_inflate()
	_test_valid_images()
	_test_structure_refusals()
	_test_data_refusals()
	_test_limits()
	print("Creator PNG: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_crc() -> void:
	var digits := "123456789".to_ascii_buffer()
	check("crc table known vector", PngCheck.crc32_table(digits) == 0xCBF43926)
	check("crc known vector", PngCheck.crc32(digits) == 0xCBF43926)
	check("crc of nothing", PngCheck.crc32(PackedByteArray()) == 0 and PngCheck.crc32_table(PackedByteArray()) == 0)
	check("crc fox", PngCheck.crc32("The quick brown fox jumps over the lazy dog".to_ascii_buffer()) == 0x414FA339)
	check("test crc known vector", crc_bitwise(digits) == 0xCBF43926)
	# The native (gzip trailer) path starts at 256 bytes; compare it with two other implementations.
	for size: int in [255, 256, 257, 70000]:
		var data := noise(size, 7)
		var expected := crc_bitwise(data)
		check("crc native equals bitwise at %d" % size, PngCheck.crc32(data) == expected)
		check("crc table equals bitwise at %d" % size, PngCheck.crc32_table(data) == expected)


func _test_inflate() -> void:
	var raw := noise(200000, 3)
	var stream := zlib(raw)
	check("fixture is a zlib stream", stream[0] == 0x78 and Inflate.is_zlib_header(stream[0], stream[1]))
	var whole: Dictionary = Inflate.zlib_exact([stream], raw.size(), true)
	check("inflate exact", whole.ok and whole.value.bytes_out == raw.size() and whole.value.output == raw)
	var quiet: Dictionary = Inflate.zlib_exact([stream], raw.size())
	check("inflate without output", quiet.ok and not quiet.value.has("output"))
	# The header split over a one-byte part, an empty part and the rest.
	var split: Array[PackedByteArray] = [stream.slice(0, 1), PackedByteArray(), stream.slice(1, 5000), stream.slice(5000)]
	var joined: Dictionary = Inflate.zlib_exact(split, raw.size(), true)
	check("inflate across parts", joined.ok and joined.value.output == raw)
	check("inflate empty stream", Inflate.zlib_exact([zlib_empty()], 0).ok)

	expect_code("inflate expects more", Inflate.zlib_exact([stream], raw.size() + 1), R.SOURCE_INVALID)
	expect_code("inflate expects less", Inflate.zlib_exact([stream], raw.size() - 1), R.SOURCE_INVALID)
	check("status excess", Inflate.zlib_scan([stream], raw.size() - 1).status == Inflate.STATUS_EXCESS)
	check("status short", Inflate.zlib_scan([stream], raw.size() + 1).status == Inflate.STATUS_SHORT)
	check("cut stream is short", Inflate.zlib_scan([stream.slice(0, stream.size() / 2)], raw.size()).status
		== Inflate.STATUS_SHORT)
	# All data present but the 4-byte checksum removed: the stream is not terminated.
	check("missing checksum", Inflate.zlib_scan([stream.slice(0, stream.size() - 4)], raw.size()).status
		== Inflate.STATUS_TRUNCATED)
	var padded := stream.duplicate()
	padded.append_array(PackedByteArray([1, 2, 3]))
	check("trailing bytes", Inflate.zlib_scan([padded], raw.size()).status == Inflate.STATUS_TRAILING)
	var tail: Array[PackedByteArray] = [stream, PackedByteArray([0])]
	check("trailing part", Inflate.zlib_scan(tail, raw.size()).status == Inflate.STATUS_TRAILING)
	check("negative size", Inflate.zlib_scan([stream], -1).status == Inflate.STATUS_HEADER)
	check("no input", Inflate.zlib_scan([], 0).status == Inflate.STATUS_HEADER)
	check("one byte", Inflate.zlib_scan([PackedByteArray([0x78])], 0).status == Inflate.STATUS_HEADER)

	# Header rules: bad check bits, wrong method, oversized window, preset dictionary, gzip.
	check("header 78 9c", Inflate.is_zlib_header(0x78, 0x9C))
	check("header 78 01", Inflate.is_zlib_header(0x78, 0x01))
	check("header check bits", not Inflate.is_zlib_header(0x78, 0x9D))
	check("header method", not Inflate.is_zlib_header(0x77, 0x09) and (0x7709 % 31) == 0)
	check("header window", not Inflate.is_zlib_header(0x88, 0x1C) and (0x881C % 31) == 0)
	check("header dictionary", not Inflate.is_zlib_header(0x78, 0x20) and (0x7820 % 31) == 0)
	check("gzip is not zlib", Inflate.zlib_scan([raw.compress(FileAccess.COMPRESSION_GZIP)], raw.size()).status
		== Inflate.STATUS_HEADER)
	expect_code("garbage header", Inflate.zlib_exact([PackedByteArray([0x50, 0x4B, 3, 4, 5, 6, 7, 8])], 64), R.SOURCE_INVALID)

	# Expansion bomb: 8 MiB of zeros in a few KiB. Inflation stops within one scratch buffer.
	var zeros := PackedByteArray()
	zeros.resize(8 * Limits.MIB)
	var bomb := zlib(zeros)
	check("bomb is small", bomb.size() < 16 * Limits.KIB)
	var started := Time.get_ticks_msec()
	var stopped: Dictionary = Inflate.zlib_scan([bomb], 1000)
	check("bomb refused", stopped.status == Inflate.STATUS_EXCESS)
	check("bomb stopped at the bound", int(stopped.bytes_out) <= 1000 + Limits.INFLATE_SCRATCH_BYTES)
	check("bomb stopped early", Time.get_ticks_msec() - started < 1000)
	check("bomb keeps nothing", (stopped.output as PackedByteArray).is_empty())

	# A sink sees every chunk in order and can stop the stream.
	var seen := [0, 0]
	var counting := func(chunk: PackedByteArray, offset: int) -> bool:
		if offset == seen[0]:
			seen[1] += 1
		seen[0] += chunk.size()
		return true
	check("sink sees all bytes", Inflate.zlib_exact([stream], raw.size(), false, counting).ok and seen[0] == raw.size()
		and seen[1] >= 3)
	var refusing := func(_chunk: PackedByteArray, offset: int) -> bool:
		return offset == 0
	var refused: Dictionary = Inflate.zlib_scan([stream], raw.size(), false, refusing)
	check("sink stops the stream", refused.status == Inflate.STATUS_SINK
		and int(refused.bytes_out) <= 2 * Limits.INFLATE_SCRATCH_BYTES)


func _test_valid_images() -> void:
	# Engine-written images: the encoder's CRCs and zlib streams are an independent reference.
	var formats := {Image.FORMAT_L8: [0, 1, false], Image.FORMAT_LA8: [4, 2, true], Image.FORMAT_RGB8: [2, 3, false],
		Image.FORMAT_RGBA8: [6, 4, true]}
	for format: int in formats:
		var image := Image.create(5, 3, false, format)
		image.fill(Color(0.2, 0.4, 0.6, 0.8))
		image.set_pixel(4, 2, Color(1.0, 0.0, 0.0, 1.0))
		var bytes := image.save_png_to_buffer()
		var result: Dictionary = PngCheck.inspect(bytes)
		var label := "engine png type %d" % formats[format][0]
		check(label + " ok", result.ok)
		if result.ok:
			var info: Dictionary = result.value
			check(label + " size", info.width == 5 and info.height == 3 and info.pixels == 15)
			check(label + " type", info.color_type == formats[format][0] and info.bit_depth == 8
				and info.channels == formats[format][1] and not info.interlaced)
			check(label + " alpha", info.has_alpha == formats[format][2])
			check(label + " decoded bytes", info.decoded_bytes == 3 * (1 + 5 * int(formats[format][1])))
		var decoded: Dictionary = PngCheck.decode(bytes)
		check(label + " decode", decoded.ok and (decoded.value.image as Image).get_width() == 5
			and (decoded.value.image as Image).get_height() == 3 and decoded.value.info.width == 5)

	# Hand-built greyscale, 1 bit, 9 x 2: two bytes per row plus the filter byte.
	var grey := build(9, 2, 1, 0, PackedByteArray([0, 0xAA, 0x80, 1, 0xFF, 0x00]))
	var grey_result: Dictionary = PngCheck.inspect(grey)
	check("grey 1 bit", grey_result.ok and grey_result.value.decoded_bytes == 6 and grey_result.value.channels == 1
		and not grey_result.value.has_alpha)
	check("grey 1 bit decodes", PngCheck.decode(grey).ok)

	# Every legal filter type, RGB 8 bit, 2 x 5.
	var rgb_raw := PackedByteArray()
	for row: int in 5:
		rgb_raw.append(row)
		rgb_raw.append_array(PackedByteArray([10, 20, 30, 40, 50, 60]))
	var rgb: Dictionary = PngCheck.inspect(build(2, 5, 8, 2, rgb_raw))
	check("rgb all filters", rgb.ok and rgb.value.decoded_bytes == 35 and rgb.value.width == 2 and rgb.value.height == 5)

	# 16-bit RGBA, 3 x 2: eight bytes per pixel.
	var deep_raw := PackedByteArray()
	deep_raw.resize(2 * (1 + 3 * 8))
	var deep: Dictionary = PngCheck.inspect(build(3, 2, 16, 6, deep_raw))
	check("rgba 16 bit", deep.ok and deep.value.decoded_bytes == 50 and deep.value.has_alpha and deep.value.bit_depth == 16)
	check("rgb all filters decodes", PngCheck.decode(build(2, 5, 8, 2, rgb_raw)).ok)
	check("rgba 16 bit decodes", PngCheck.decode(build(3, 2, 16, 6, deep_raw)).ok)

	# Indexed with palette and transparency, 2 x 2.
	var palette := PackedByteArray([255, 0, 0, 0, 255, 0, 0, 0, 255])
	var indexed := assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette), chunk("tRNS", PackedByteArray([255, 128])),
		chunk("IDAT", zlib(PackedByteArray([0, 0, 1, 0, 2, 0]))), iend()])
	var indexed_result: Dictionary = PngCheck.decode(indexed)
	check("indexed ok", indexed_result.ok and indexed_result.value.info.color_type == 3 and indexed_result.value.info.has_alpha)
	if indexed_result.ok:
		var picture: Image = indexed_result.value.image
		check("indexed pixels", picture.get_pixel(0, 0).r8 == 255 and picture.get_pixel(1, 0).g8 == 255
			and picture.get_pixel(0, 1).b8 == 255 and picture.get_pixel(1, 0).a8 == 128)
	var opaque := assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette),
		chunk("IDAT", zlib(PackedByteArray([0, 0, 1, 0, 2, 0]))), iend()])
	check("indexed without tRNS has no alpha", PngCheck.inspect(opaque).ok and not PngCheck.inspect(opaque).value.has_alpha)

	# Ancillary chunks of the allow-list, in a legal order, and data split over several IDAT chunks.
	var stream := zlib(rgb_raw)
	var dressed := assemble([ihdr(2, 5, 8, 2), chunk("gAMA", be32(45455)), chunk("cHRM", noise(32, 1)),
		chunk("sRGB", PackedByteArray([0])), chunk("pHYs", PackedByteArray([0, 0, 0x0E, 0xC4, 0, 0, 0x0E, 0xC4, 1])),
		chunk("IDAT", stream.slice(0, 1)), chunk("IDAT", PackedByteArray()), chunk("IDAT", stream.slice(1, 7)),
		chunk("IDAT", stream.slice(7)), iend()])
	check("ancillary chunks and split data", PngCheck.inspect(dressed).ok)
	check("ancillary chunks decode", PngCheck.decode(dressed).ok)

	# Adam7: scanline sizes come from the seven passes; the engine decoder confirms the layout.
	for size: Vector2i in [Vector2i(8, 8), Vector2i(5, 3), Vector2i(1, 1), Vector2i(3, 9), Vector2i(17, 2)]:
		var raw := adam7_raw(size.x, size.y)
		var interlaced := build(size.x, size.y, 8, 0, raw, 1)
		var result: Dictionary = PngCheck.decode(interlaced)
		var label := "adam7 %dx%d" % [size.x, size.y]
		check(label + " ok", result.ok and result.value.info.interlaced and result.value.info.decoded_bytes == raw.size())
		if result.ok:
			var picture: Image = result.value.image
			var same := true
			for y: int in size.y:
				for x: int in size.x:
					same = same and picture.get_pixel(x, y).r8 == shade(x, y)
			check(label + " pixels", same)
		# The same bytes declared as non-interlaced do not have the right size.
		expect_code(label + " as plain", PngCheck.inspect(build(size.x, size.y, 8, 0, raw, 0)), R.SOURCE_INVALID,
			size != Vector2i(1, 1))

	var first: Dictionary = PngCheck.inspect(grey).value
	var second: Dictionary = PngCheck.header(build(2, 5, 8, 2, rgb_raw)).value
	check("decoded pixels", PngCheck.decoded_pixels(first) == 18 and PngCheck.decoded_pixels(second) == 10)
	check("aggregate pixels", PngCheck.aggregate_pixels([first, second]) == 28)
	check("aggregate budget is a square of the side limit", Limits.PNG_AGGREGATE_PIXELS
		== Limits.PNG_SIDE_PIXELS * Limits.PNG_SIDE_PIXELS)


func _test_structure_refusals() -> void:
	var raw := PackedByteArray([0, 1, 2, 3, 0, 4, 5, 6])  # grey 8 bit, 3 x 2
	var data := chunk("IDAT", zlib(raw))
	var good := assemble([ihdr(3, 2, 8, 0), data, iend()])
	check("baseline ok", PngCheck.inspect(good).ok)

	var wrong_signature := good.duplicate()
	wrong_signature[1] = 0x51
	expect_code("bad signature", PngCheck.inspect(wrong_signature), R.SOURCE_INVALID)
	expect_code("jpeg bytes", PngCheck.inspect(noise(100, 5)), R.SOURCE_INVALID)
	expect_code("empty file", PngCheck.inspect(PackedByteArray()), R.SOURCE_INVALID)
	expect_code("signature only", PngCheck.inspect(good.slice(0, 8)), R.SOURCE_INVALID)

	expect_code("zero width", PngCheck.inspect(assemble([ihdr(0, 2, 8, 0), data, iend()])), R.SOURCE_INVALID)
	expect_code("zero height", PngCheck.inspect(assemble([ihdr(3, 0, 8, 0), data, iend()])), R.SOURCE_INVALID)
	expect_code("width over limit", PngCheck.inspect(assemble([ihdr(Limits.PNG_SIDE_PIXELS + 1, 2, 8, 0), data, iend()])),
		R.SOURCE_LIMIT)
	expect_code("height over limit", PngCheck.inspect(assemble([ihdr(3, Limits.PNG_SIDE_PIXELS + 1, 8, 0), data, iend()])),
		R.SOURCE_LIMIT)
	expect_code("huge width", PngCheck.inspect(assemble([ihdr(0xFFFFFFFF, 2, 8, 0), data, iend()])), R.SOURCE_LIMIT)
	expect_code("rgb depth 4", PngCheck.inspect(assemble([ihdr(3, 2, 4, 2), data, iend()])), R.SOURCE_INVALID)
	expect_code("colour type 5", PngCheck.inspect(assemble([ihdr(3, 2, 8, 5), data, iend()])), R.SOURCE_INVALID)
	expect_code("depth 3", PngCheck.inspect(assemble([ihdr(3, 2, 3, 0), data, iend()])), R.SOURCE_INVALID)
	expect_code("indexed depth 16", PngCheck.inspect(assemble([ihdr(3, 2, 16, 3), data, iend()])), R.SOURCE_INVALID)
	expect_code("compression method", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0, 0, 1), data, iend()])), R.SOURCE_INVALID)
	expect_code("filter method", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0, 0, 0, 1), data, iend()])), R.SOURCE_INVALID)
	expect_code("interlace method 2", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0, 2), data, iend()])), R.SOURCE_INVALID)
	var short_header := assemble([chunk("IHDR", ihdr(3, 2, 8, 0).slice(8, 20)), data, iend()])
	expect_code("12-byte IHDR", PngCheck.inspect(short_header), R.SOURCE_INVALID)
	expect_code("first chunk is not IHDR", PngCheck.inspect(assemble([chunk("gAMA", noise(13, 2)), data, iend()])),
		R.SOURCE_INVALID)

	for at: int in [29, good.size() - 13]:  # the IHDR CRC and the IDAT CRC
		var damaged := good.duplicate()
		damaged[at] ^= 0x01
		expect_code("bad crc at %d" % at, PngCheck.inspect(damaged), R.SOURCE_INVALID)
	var flipped := good.duplicate()
	flipped[good.size() - 20] ^= 0x40  # a data byte under an unchanged CRC
	expect_code("data changed under crc", PngCheck.inspect(flipped), R.SOURCE_INVALID)
	var bad_end := good.duplicate()
	bad_end[good.size() - 1] ^= 0xFF
	expect_code("bad IEND crc", PngCheck.inspect(bad_end), R.SOURCE_INVALID)

	expect_code("truncated in chunk data", PngCheck.inspect(good.slice(0, good.size() - 20)), R.SOURCE_INVALID)
	expect_code("truncated in chunk header", PngCheck.inspect(good.slice(0, good.size() - 7)), R.SOURCE_INVALID)
	expect_code("missing IEND", PngCheck.inspect(good.slice(0, good.size() - 12)), R.SOURCE_INVALID)
	var oversized := assemble([ihdr(3, 2, 8, 0), data, iend()])
	oversized.encode_u32(33, 0xFFFFFF7F)  # IDAT length rewritten to 0x7FFFFFFF (big-endian)
	expect_code("chunk length overruns file", PngCheck.inspect(oversized), R.SOURCE_INVALID)
	var wrapped := assemble([ihdr(3, 2, 8, 0), data, iend()])
	wrapped.encode_u32(33, 0xFFFFFFFF)
	expect_code("chunk length 2^32 - 1", PngCheck.inspect(wrapped), R.SOURCE_INVALID)

	var after := good.duplicate()
	after.append(0)
	expect_code("byte after IEND", PngCheck.inspect(after), R.SOURCE_INVALID)
	expect_code("chunk after IEND", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), data, iend(), iend()])), R.SOURCE_INVALID)
	expect_code("IEND with data", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), data, chunk("IEND", PackedByteArray([0]))])),
		R.SOURCE_INVALID)
	expect_code("duplicate IHDR", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), ihdr(3, 2, 8, 0), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("no IDAT", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("sRGB", PackedByteArray([0])), iend()])),
		R.SOURCE_INVALID)
	expect_code("empty IDAT only", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("IDAT", PackedByteArray()), iend()])),
		R.SOURCE_INVALID)

	for kind: String in ["iCCP", "zTXt", "iTXt"]:
		expect_code("forbidden " + kind, PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk(kind, noise(20, 4)), data, iend()])),
			R.SOURCE_UNSUPPORTED)
	for kind: String in ["eXIf", "acTL", "prVt"]:
		expect_code("unknown " + kind, PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk(kind, noise(7, 4)), data, iend()])),
			R.SOURCE_UNSUPPORTED)
	expect_code("unknown chunk after data", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), data, chunk("eXIf", noise(7, 4)),
		iend()])), R.SOURCE_UNSUPPORTED)

	# Passive metadata that common editors write is admitted and ignored: it is bounded, never
	# expands and does not change the pixels.
	var edited := assemble([ihdr(3, 2, 8, 0), chunk("tEXt", keyword_text("Software", "An editor")),
		chunk("bKGD", PackedByteArray([0, 0])), chunk("tIME", noise(7, 4)), data,
		chunk("tEXt", keyword_text("Comment", "after the data")), iend()])
	check("passive text, time and background chunks are admitted", PngCheck.inspect(edited).ok)
	check("an image with passive metadata decodes", PngCheck.decode(edited).ok)
	expect_code("second tIME", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tIME", noise(7, 4)), chunk("tIME", noise(7, 4)),
		data, iend()])), R.SOURCE_INVALID)
	expect_code("tIME with a wrong size", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tIME", noise(6, 4)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("bKGD with a wrong size", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("bKGD", noise(7, 4)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("bKGD after the data", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), data, chunk("bKGD", PackedByteArray([0, 0])),
		iend()])), R.SOURCE_INVALID)
	expect_code("oversized tEXt", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tEXt", noise(65537, 4)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("data split by a passive chunk", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("IDAT", stream_head(data)),
		chunk("tEXt", noise(7, 4)), chunk("IDAT", PackedByteArray([0])), iend()])), R.SOURCE_INVALID)

	# Parser differential: the engine's inflater ignores the window the zlib header declares, while
	# the PNG decoder enforces it. A stream that declares a window smaller than its content is
	# refused here, so it cannot pass admission and then fail inside the decoder.
	var small_raw := noise(8, 9)
	for row: int in 2:
		small_raw[row * 4] = 0
	var small_window := assemble([ihdr(3, 2, 8, 0), chunk("IDAT", with_window(zlib(small_raw), 0)), iend()])
	check("a small declared window that still holds the whole image is admitted", PngCheck.inspect(small_window).ok)
	check("and the engine decodes it", PngCheck.decode(small_window).ok)
	var large_raw := PackedByteArray()
	large_raw.resize(64 * 65)
	var undersized := assemble([ihdr(64, 64, 8, 0), chunk("IDAT", with_window(zlib(large_raw), 0)), iend()])
	expect_code("a declared window smaller than the image data", PngCheck.inspect(undersized), R.SOURCE_UNSUPPORTED)
	expect_code("the same through the decode entry point", PngCheck.decode(undersized), R.SOURCE_UNSUPPORTED)
	check("the full 32 KiB window is always admitted", PngCheck.inspect(assemble([ihdr(64, 64, 8, 0),
		chunk("IDAT", zlib(large_raw)), iend()])).ok)
	check("window sizes", Inflate.declared_window(0x08) == 256 and Inflate.declared_window(0x68) == 16384
		and Inflate.declared_window(0x78) > 1 << 40)
	var odd_type := assemble([ihdr(3, 2, 8, 0), chunk("ID1T", noise(4, 4)), data, iend()])
	expect_code("chunk type with a digit", PngCheck.inspect(odd_type), R.SOURCE_INVALID)

	var stream := zlib(raw)
	var split := assemble([ihdr(3, 2, 8, 0), chunk("IDAT", stream.slice(0, 4)), chunk("sRGB", PackedByteArray([0])),
		chunk("IDAT", stream.slice(4)), iend()])
	expect_code("non-consecutive IDAT", PngCheck.inspect(split), R.SOURCE_INVALID)
	expect_code("ancillary after IDAT", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), data, chunk("pHYs", noise(9, 1).slice(0, 8)
		+ PackedByteArray([1])), iend()])), R.SOURCE_INVALID)
	expect_code("duplicate sRGB", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("sRGB", PackedByteArray([0])),
		chunk("sRGB", PackedByteArray([0])), data, iend()])), R.SOURCE_INVALID)
	expect_code("sRGB length", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("sRGB", PackedByteArray([0, 0])), data,
		iend()])), R.SOURCE_INVALID)
	expect_code("sRGB intent", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("sRGB", PackedByteArray([4])), data,
		iend()])), R.SOURCE_INVALID)
	expect_code("gAMA length", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("gAMA", noise(5, 1)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("gAMA zero", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("gAMA", be32(0)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("cHRM length", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("cHRM", noise(31, 1)), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("pHYs length", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("pHYs", noise(8, 1)), data, iend()])),
		R.SOURCE_INVALID)

	# Palette and transparency rules.
	var index_data := chunk("IDAT", zlib(PackedByteArray([0, 0, 1, 0, 1, 0])))
	var palette := PackedByteArray([1, 2, 3, 4, 5, 6])
	check("indexed baseline", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette), index_data, iend()])).ok)
	expect_code("indexed without PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), index_data, iend()])), R.SOURCE_INVALID)
	expect_code("PLTE after IDAT", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), index_data, chunk("PLTE", palette), iend()])),
		R.SOURCE_INVALID)
	expect_code("PLTE not a multiple of 3", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette.slice(0, 5)),
		index_data, iend()])), R.SOURCE_INVALID)
	expect_code("empty PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", PackedByteArray()), index_data,
		iend()])), R.SOURCE_INVALID)
	expect_code("PLTE with 257 entries", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", noise(771, 1)),
		index_data, iend()])), R.SOURCE_INVALID)
	check("PLTE with 256 entries", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", noise(768, 1)), index_data,
		iend()])).ok)
	var two_bit := chunk("IDAT", zlib(PackedByteArray([0, 0, 0, 0])))
	expect_code("PLTE larger than the bit depth", PngCheck.inspect(assemble([ihdr(2, 2, 1, 3), chunk("PLTE", noise(9, 1)),
		two_bit, iend()])), R.SOURCE_INVALID)
	expect_code("duplicate PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette), chunk("PLTE", palette),
		index_data, iend()])), R.SOURCE_INVALID)
	expect_code("PLTE in greyscale", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("PLTE", palette), data, iend()])),
		R.SOURCE_INVALID)
	expect_code("tRNS before PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("tRNS", PackedByteArray([1])),
		chunk("PLTE", palette), index_data, iend()])), R.SOURCE_INVALID)
	expect_code("tRNS longer than PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette),
		chunk("tRNS", PackedByteArray([1, 2, 3])), index_data, iend()])), R.SOURCE_INVALID)
	expect_code("sRGB after PLTE", PngCheck.inspect(assemble([ihdr(2, 2, 8, 3), chunk("PLTE", palette),
		chunk("sRGB", PackedByteArray([0])), index_data, iend()])), R.SOURCE_INVALID)
	check("grey tRNS", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tRNS", PackedByteArray([0, 7])), data, iend()])).ok
		and PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tRNS", PackedByteArray([0, 7])), data, iend()])).value.has_alpha)
	expect_code("grey tRNS size", PngCheck.inspect(assemble([ihdr(3, 2, 8, 0), chunk("tRNS", PackedByteArray([0, 7, 1])), data,
		iend()])), R.SOURCE_INVALID)
	var alpha_raw := PackedByteArray()
	alpha_raw.resize(2 * (1 + 3 * 4))
	expect_code("tRNS with an alpha channel", PngCheck.inspect(assemble([ihdr(3, 2, 8, 6),
		chunk("tRNS", PackedByteArray([0, 7])), chunk("IDAT", zlib(alpha_raw)), iend()])), R.SOURCE_INVALID)

	expect_code("decode refuses before the engine", PngCheck.decode(wrong_signature), R.SOURCE_INVALID)
	check("header refuses what inspect refuses", not PngCheck.header(wrong_signature).ok)


func _test_data_refusals() -> void:
	var width := 64
	var height := 64
	var raw := PackedByteArray()
	for y: int in height:
		raw.append(y % 5)
		raw.append_array(noise(width, y + 1))
	var stream := zlib(raw)
	check("data baseline", PngCheck.inspect(build(width, height, 8, 0, raw)).ok)

	# One scanline too few, one too many, and one byte either way.
	expect_code("one row short", PngCheck.inspect(build(width, height, 8, 0, raw.slice(0, raw.size() - width - 1))),
		R.SOURCE_INVALID)
	expect_code("one byte short", PngCheck.inspect(build(width, height, 8, 0, raw.slice(0, raw.size() - 1))), R.SOURCE_INVALID)
	var long := raw.duplicate()
	long.append(0)
	expect_code("one byte long", PngCheck.inspect(build(width, height, 8, 0, long)), R.SOURCE_INVALID)
	expect_code("truncated zlib stream", PngCheck.inspect(assemble([ihdr(width, height, 8, 0),
		chunk("IDAT", stream.slice(0, stream.size() / 2)), iend()])), R.SOURCE_INVALID)
	expect_code("zlib stream without checksum", PngCheck.inspect(assemble([ihdr(width, height, 8, 0),
		chunk("IDAT", stream.slice(0, stream.size() - 4)), iend()])), R.SOURCE_INVALID)
	var padded := stream.duplicate()
	padded.append_array(PackedByteArray([0, 0]))
	expect_code("bytes after the zlib stream", PngCheck.inspect(assemble([ihdr(width, height, 8, 0), chunk("IDAT", padded),
		iend()])), R.SOURCE_INVALID)
	expect_code("bytes after the zlib stream in another IDAT", PngCheck.inspect(assemble([ihdr(width, height, 8, 0),
		chunk("IDAT", stream), chunk("IDAT", PackedByteArray([0])), iend()])), R.SOURCE_INVALID)

	# Expansion bomb: a 1 x 1 header in front of megabytes of zeros.
	var zeros := PackedByteArray()
	zeros.resize(8 * Limits.MIB)
	var started := Time.get_ticks_msec()
	expect_code("expansion bomb", PngCheck.inspect(assemble([ihdr(1, 1, 8, 0), chunk("IDAT", zlib(zeros)), iend()])),
		R.SOURCE_INVALID)
	check("expansion bomb refused quickly", Time.get_ticks_msec() - started < 2000)

	# Filter bytes: 0..4 are legal, 5 is not, wherever the scanline starts in the stream.
	for row: int in [0, 1, height - 1]:
		var bad := raw.duplicate()
		bad[row * (width + 1)] = 5
		expect_code("filter 5 on row %d" % row, PngCheck.inspect(build(width, height, 8, 0, bad)), R.SOURCE_INVALID)
	var high := raw.duplicate()
	high[(width + 1) * 7] = 255
	expect_code("filter 255", PngCheck.inspect(build(width, height, 8, 0, high)), R.SOURCE_INVALID)
	# A tall image whose scanlines cross the scratch buffer boundary many times.
	var tall := PackedByteArray()
	tall.resize(4096 * 101)
	check("tall image", PngCheck.inspect(build(100, 4096, 8, 0, tall)).ok)
	tall[4095 * 101] = 9
	expect_code("filter on the last of 4096 rows", PngCheck.inspect(build(100, 4096, 8, 0, tall)), R.SOURCE_INVALID)
	var adam := adam7_raw(9, 9)
	adam[adam.size() - 10] = 6  # the filter byte of the last pass-7 scanline
	expect_code("filter in an Adam7 pass", PngCheck.inspect(build(9, 9, 8, 0, adam, 1)), R.SOURCE_INVALID)

	# zlib header rules reach the caller as an invalid image, without an engine call.
	for header: Array in [[0x78, 0x9D], [0x77, 0x09], [0x88, 0x1C], [0x78, 0x20], [0x1F, 0x8B]]:
		var bad_stream := stream.duplicate()
		bad_stream[0] = header[0]
		bad_stream[1] = header[1]
		expect_code("zlib header %02x %02x" % header, PngCheck.inspect(assemble([ihdr(width, height, 8, 0),
			chunk("IDAT", bad_stream), iend()])), R.SOURCE_INVALID)
	expect_code("one-byte IDAT", PngCheck.inspect(assemble([ihdr(width, height, 8, 0), chunk("IDAT", PackedByteArray([0x78])),
		iend()])), R.SOURCE_INVALID)


func _test_limits() -> void:
	var too_big := PackedByteArray()
	too_big.resize(Limits.PNG_BYTES + 1)
	expect_code("file over the byte limit", PngCheck.inspect(too_big), R.SOURCE_LIMIT)
	expect_code("header over the byte limit", PngCheck.header(too_big), R.SOURCE_LIMIT)

	# Largest side, 1-bit greyscale: 4096 x 2.
	var wide := PackedByteArray()
	wide.resize(2 * (1 + Limits.PNG_SIDE_PIXELS / 8))
	var widest: Dictionary = PngCheck.inspect(build(Limits.PNG_SIDE_PIXELS, 2, 1, 0, wide))
	check("side at the limit", widest.ok and widest.value.pixels == 2 * Limits.PNG_SIDE_PIXELS)

	# Chunk ceiling: IHDR + data + empty IDAT chunks + IEND.
	var raw := PackedByteArray([0, 9])
	for total: int in [Limits.PNG_CHUNKS, Limits.PNG_CHUNKS + 1]:
		var parts: Array = [ihdr(1, 1, 8, 0), chunk("IDAT", zlib(raw))]
		var filler := chunk("IDAT", PackedByteArray())
		for _index: int in total - 3:
			parts.append(filler)
		parts.append(iend())
		var result: Dictionary = PngCheck.inspect(assemble(parts))
		if total <= Limits.PNG_CHUNKS:
			check("chunks at the limit", result.ok)
		else:
			expect_code("chunks over the limit", result, R.SOURCE_LIMIT)


# --- fixture helpers -------------------------------------------------------------------------

func be32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF])


## Bitwise CRC-32, written independently of the module's table and gzip paths.
func crc_bitwise(bytes: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for byte: int in bytes:
		crc ^= byte
		for _bit: int in 8:
			crc = (crc >> 1) ^ (0xEDB88320 * (crc & 1))
	return crc ^ 0xFFFFFFFF


func chunk(kind: String, data: PackedByteArray) -> PackedByteArray:
	var body := kind.to_ascii_buffer()
	body.append_array(data)
	var out := be32(data.size())
	out.append_array(body)
	out.append_array(be32(crc_bitwise(body)))
	return out


func ihdr(width: int, height: int, depth: int, color_type: int, interlace := 0, compression := 0, filter := 0) -> PackedByteArray:
	var data := be32(width)
	data.append_array(be32(height))
	data.append_array(PackedByteArray([depth, color_type, compression, filter, interlace]))
	return chunk("IHDR", data)


func iend() -> PackedByteArray:
	return chunk("IEND", PackedByteArray())


func assemble(chunks: Array) -> PackedByteArray:
	var out := PackedByteArray(PngCheck.SIGNATURE)
	for part: PackedByteArray in chunks:
		out.append_array(part)
	return out


## zlib stream written by the engine (header 78 9c), an independent encoder for these fixtures.
func zlib(raw: PackedByteArray) -> PackedByteArray:
	return raw.compress(FileAccess.COMPRESSION_DEFLATE)


## The same stream with another declared window (CINFO 0..7) and matching header check bits.
func with_window(stream: PackedByteArray, window_bits_code: int) -> PackedByteArray:
	var rewritten := stream.duplicate()
	rewritten[0] = (window_bits_code << 4) | 8
	rewritten[1] = 0
	rewritten[1] = (31 - ((rewritten[0] << 8) % 31)) % 31
	return rewritten


## A tEXt payload: keyword, a NUL separator, then the text.
func keyword_text(keyword: String, text: String) -> PackedByteArray:
	var payload := keyword.to_utf8_buffer()
	payload.append(0)
	payload.append_array(text.to_utf8_buffer())
	return payload


## The payload of an IDAT chunk built by `chunk("IDAT", ...)`.
func stream_head(idat_chunk: PackedByteArray) -> PackedByteArray:
	return idat_chunk.slice(8, idat_chunk.size() - 4)


## The engine refuses to compress nothing; this is the canonical empty zlib stream.
func zlib_empty() -> PackedByteArray:
	return PackedByteArray([0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01])


func build(width: int, height: int, depth: int, color_type: int, raw: PackedByteArray, interlace := 0) -> PackedByteArray:
	return assemble([ihdr(width, height, depth, color_type, interlace), chunk("IDAT", zlib(raw)), iend()])


## Deterministic bytes that do not compress well.
func noise(size: int, seed_value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	var state := seed_value * 2654435761 + 12345
	for index: int in size:
		state = (state * 1103515245 + 12345) & 0x7FFFFFFF
		out[index] = (state >> 16) & 0xFF
	return out


func shade(x: int, y: int) -> int:
	return (x * 7 + y * 13 + 3) % 256


## 8-bit greyscale Adam7 scanlines, enumerated pixel by pixel (not from the module's size formula).
func adam7_raw(width: int, height: int) -> PackedByteArray:
	var raw := PackedByteArray()
	for pass_step: Array in [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]:
		var y: int = pass_step[1]
		while y < height:
			if pass_step[0] < width:
				raw.append(0)
				var x: int = pass_step[0]
				while x < width:
					raw.append(shade(x, y))
					x += pass_step[2]
			y += pass_step[3]
	return raw


func expect_code(label: String, result: Dictionary, code: String, active := true) -> void:
	if not active:
		return
	var got := "ok"
	if not result.ok:
		got = str(result.diagnostics[0].code) if result.diagnostics.size() == 1 else "several diagnostics"
	check("%s -> %s (got %s)" % [label, code, got], got == code and not result.has("value"))


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
