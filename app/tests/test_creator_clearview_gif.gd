extends SceneTree
## GIF first-frame decoder (AC-CV-03): independent palette oracles, LZW edge cases, refusals, limits.
const R := preload("res://workshop/creator/result.gd")
const Gif := preload("res://workshop/creator/clearview/gif.gd")
const Images := preload("res://workshop/creator/clearview/images.gd")
const PngCheck := preload("res://workshop/creator/png_check.gd")
const PALETTE: Array = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [10, 20, 30]]
var checks := 0
var failures := 0

func _initialize() -> void:
	_basic()
	_layout()
	_lzw_cases()
	_refusals()
	_limits_and_cancel()
	print("ClearView GIF: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL: ", label)

func _basic() -> void:
	var indices := [0, 1, 2, 3]
	_expect("2x2 opaque", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, indices)]), 2, 2, _expected(PALETTE, indices), false)
	_expect("GIF87a header", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, indices)], "GIF87a"), 2, 2, _expected(PALETTE, indices), false)
	var transparent := _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, indices, 2, {transparent = 2})])
	_expect("2x2 transparency index 2", transparent, 2, 2, _expected(PALETTE, indices, 2), true)
	_expect("unused transparency index gives no alpha", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [0, 1, 2, 2], 2, {transparent = 3})]), 2, 2, _expected(PALETTE, [0, 1, 2, 2], 3), false)
	var normalized := Images.normalize(transparent)
	check("GIF normalized to PNG", normalized.ok and normalized.value.has_alpha and normalized.value.width == 2 and normalized.value.pixels == 4)
	if normalized.ok:
		var decoded := PngCheck.decode(normalized.value.png)
		check("normalized PNG decodes", decoded.ok)
		if decoded.ok:
			var image: Image = decoded.value.image
			check("PNG size", image.get_width() == 2 and image.get_height() == 2)
			check("PNG opaque pixel (1,1)=index 3", image.get_pixel(1, 1).is_equal_approx(Color8(10, 20, 30, 255)))
			check("PNG opaque pixel (0,0)=index 0", image.get_pixel(0, 0).is_equal_approx(Color8(255, 0, 0, 255)))
			check("PNG transparent pixel (0,1)=index 2", is_zero_approx(image.get_pixel(0, 1).a))
	check("normalize honours the pixel budget", not Images.normalize(transparent, Callable(), 3).ok)
	check("normalize honours cancellation", not Images.normalize(transparent, func() -> bool: return true).ok)
	var two := _gif(1, 1, PALETTE, [_frame(0, 0, 1, 1, [1]), _frame(0, 0, 1, 1, [2], 2, {transparent = 2})])
	var multi := _expect("multi-frame keeps first frame", two, 1, 1, _expected(PALETTE, [1]), false)
	check("multi-frame info note", multi.ok and multi.diagnostics.size() == 1 and multi.diagnostics[0].severity == R.SEVERITY_INFO and multi.diagnostics[0].message == Gif.FRAME_NOTE)
	check("single frame has no note", Gif.decode(_gif(1, 1, PALETTE, [_frame(0, 0, 1, 1, [1])]), 1).diagnostics.is_empty())
	check("normalize passes the note through", Images.normalize(two).diagnostics.size() == 1)
	var comment := _ext(0xFE, [PackedByteArray([104, 105])])
	var application := _ext(0xFF, ["NETSCAPE2.0".to_ascii_buffer(), PackedByteArray([1, 0, 0])])
	var plain := PackedByteArray()
	plain.resize(12)
	var plain_text := _ext(0x01, [plain, PackedByteArray([104, 105])])
	_expect("comment, application and plain-text extensions skipped", _gif(2, 2, PALETTE, [comment, application, plain_text, _frame(0, 0, 2, 2, indices)]), 2, 2, _expected(PALETTE, indices), false)
	var missing_trailer := _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, indices)])
	check("missing trailer after a complete frame is tolerated", Gif.decode(missing_trailer.slice(0, missing_trailer.size() - 1), 4).ok)

func _layout() -> void:
	var palette8 := _palette8()
	var stored_rows := [0, 4, 2, 6, 1, 3, 5, 7] # interlace passes for 8 rows: 0 / 4 / 2,6 / 1,3,5,7
	var stored: Array = []
	var shown: Array = []
	for row: int in stored_rows:
		for _column: int in 3:
			stored.append(row)
	for row: int in 8:
		for _column: int in 3:
			shown.append(row)
	_expect("interlaced 3x8", _gif(3, 8, palette8, [_frame(0, 0, 3, 8, stored, 3, {interlaced = true})]), 3, 8, _expected(palette8, shown), false)
	_expect("same rows non-interlaced stay in stored order", _gif(3, 8, palette8, [_frame(0, 0, 3, 8, shown, 3)]), 3, 8, _expected(palette8, shown), false)
	# Local table overrides global; frame 2x1 at (1,1) in a 3x2 screen; the rest is transparent black.
	var local := [[1, 2, 3], [4, 5, 6]]
	var expected := PackedByteArray()
	expected.resize(24)
	for pixel: Array in [[16, 4, 5, 6], [20, 1, 2, 3]]:
		expected[pixel[0]] = pixel[1]
		expected[pixel[0] + 1] = pixel[2]
		expected[pixel[0] + 2] = pixel[3]
		expected[pixel[0] + 3] = 255
	_expect("sub-rectangle with local table", _gif(3, 2, PALETTE, [_frame(1, 1, 2, 1, [1, 0], 2, {local = local})]), 3, 2, expected, true)

func _lzw_cases() -> void:
	_expect("KwKwK chain", _gif(6, 1, PALETTE, [_frame(0, 0, 6, 1, [], 2, {codes = [[4, 3], [1, 3], [6, 3], [7, 3], [5, 4]]})]), 6, 1, _expected(PALETTE, [1, 1, 1, 1, 1, 1]), false)
	_expect("codes after the last pixel are tolerated", _gif(2, 1, PALETTE, [_frame(0, 0, 2, 1, [], 2, {codes = [[4, 3], [1, 3], [1, 3], [0, 3], [5, 3]]})]), 2, 1, _expected(PALETTE, [1, 1]), false)
	var sixteen := [0, 1, 2, 3, 3, 2, 1, 0, 0, 2, 1, 3, 1, 0, 3, 2]
	_expect("clear code every two codes", _gif(4, 4, PALETTE, [_frame(0, 0, 4, 4, sixteen, 2, {clear_every = 2})]), 4, 4, _expected(PALETTE, sixteen), false)
	var palette8 := _palette8()
	var eight: Array = []
	for index: int in 40:
		eight.append((index * 5 + (index >> 2)) & 7)
	_expect("8 colours, size growth, clear every 6 codes", _gif(8, 5, palette8, [_frame(0, 0, 8, 5, eight, 3, {clear_every = 6})]), 8, 5, _expected(palette8, eight), false)
	_expect("8 colours, size growth without clear", _gif(8, 5, palette8, [_frame(0, 0, 8, 5, eight, 3)]), 8, 5, _expected(palette8, eight), false)
	var palette256: Array = []
	var identity: Array = []
	for index: int in 256:
		palette256.append([index, 255 - index, (index * 7) & 255])
		identity.append(index)
	_expect("256 colours, minimum code size 8", _gif(16, 16, palette256, [_frame(0, 0, 16, 16, identity, 8)]), 16, 16, _expected(palette256, identity), false)
	var large := _large_indices()
	_expect("full table without clear keeps decoding (deferred clear)", _gif(70, 60, PALETTE, [_frame(0, 0, 70, 60, large)]), 70, 60, _expected(PALETTE, large), false)

func _refusals() -> void:
	var good := _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [0, 1, 2, 3])])
	for size: int in good.size() - 1:
		_refuse("truncated prefix of %d bytes" % size, good.slice(0, size))
	_refuse("wrong magic version", "GIF88a".to_ascii_buffer() + good.slice(6))
	_refuse("not a GIF", PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0, 0, 0, 0, 0]))
	_refuse("code beyond the next table entry", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [], 2, {codes = [[4, 3], [1, 3], [7, 3], [1, 3], [5, 3]]})]))
	_refuse("first code after clear is not a root", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [], 2, {codes = [[4, 3], [6, 3], [1, 3], [1, 3], [5, 3]]})]))
	_refuse("end code before every pixel", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [], 2, {codes = [[4, 3], [1, 3], [5, 3]]})]))
	_refuse("data ends without end code", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [], 2, {codes = [[4, 3], [1, 3]]})]))
	_refuse("string longer than the frame", _gif(2, 1, PALETTE, [_frame(0, 0, 2, 1, [], 2, {codes = [[4, 3], [1, 3], [6, 3], [5, 3]]})]))
	_refuse("minimum code size 1", _gif(2, 1, [[0, 0, 0], [255, 255, 255]], [_frame(0, 0, 2, 1, [0, 1], 1)]))
	_refuse("minimum code size 9", _gif(2, 1, PALETTE, [_frame(0, 0, 2, 1, [0, 1], 9)]))
	_refuse("pixel index outside the colour table", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [0, 1, 2, 5], 3)]))
	_refuse("no colour table", _gif(2, 2, [], [_frame(0, 0, 2, 2, [0, 1, 2, 3])]))
	_refuse("frame outside the logical screen", _gif(3, 1, PALETTE, [_frame(2, 0, 2, 1, [0, 1])]))
	_refuse("empty frame", _gif(2, 1, PALETTE, [_frame(0, 0, 0, 1, [])]))
	_refuse("zero-width screen", _gif(0, 1, PALETTE, [_frame(0, 0, 1, 1, [0])]))
	_refuse("no image", _gif(1, 1, PALETTE, []))
	_refuse("unknown block", _gif(1, 1, PALETTE, [PackedByteArray([0x99])]))
	_refuse("truncated extension sub-block", _gif(1, 1, PALETTE, [PackedByteArray([0x21, 0xFE, 5, 1])]))
	_refuse("invalid graphic control block", _gif(1, 1, PALETTE, [PackedByteArray([0x21, 0xF9, 3, 0, 0, 0, 0]), _frame(0, 0, 1, 1, [0])]))
	_refuse("garbage after frame 1", _gif(1, 1, PALETTE, [_frame(0, 0, 1, 1, [0]), PackedByteArray([0x99])]))
	var spam: Array = []
	for _index: int in 200:
		spam.append([4, 3])
	spam.append([5, 3])
	_refuse("clear-code flood is bounded", _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [], 2, {codes = spam})]), R.SOURCE_LIMIT)

func _limits_and_cancel() -> void:
	_refuse("pixels above the remaining budget", _gif(100, 100, PALETTE, []), R.SOURCE_LIMIT, 9999)
	_refuse("pixels equal to the budget pass the limit gate", _gif(100, 100, PALETTE, []), R.SOURCE_INVALID, 10000)
	_refuse("width above the side limit", _gif(4097, 1, PALETTE, []), R.SOURCE_LIMIT)
	_refuse("height above the side limit", _gif(1, 4097, PALETTE, []), R.SOURCE_LIMIT)
	_refuse("negative budget", _gif(1, 1, PALETTE, []), R.SOURCE_LIMIT, -1)
	var good := _gif(2, 2, PALETTE, [_frame(0, 0, 2, 2, [0, 1, 2, 3])])
	var cancelled := Gif.decode(good, 4, func() -> bool: return true)
	check("cancellation at start", not cancelled.ok and cancelled.diagnostics[0].message == "The import was cancelled.")
	# Cancel on the second poll: only reachable by polling inside the LZW or compose loops.
	var calls := [0]
	var late := func() -> bool:
		calls[0] += 1
		return calls[0] > 1
	var large := _gif(70, 60, PALETTE, [_frame(0, 0, 70, 60, _large_indices())])
	var result := Gif.decode(large, 4200, late)
	check("cancellation while decoding", not result.ok and result.diagnostics[0].message == "The import was cancelled." and calls[0] >= 2)

func _expect(label: String, bytes: PackedByteArray, width: int, height: int, rgba: PackedByteArray, alpha: bool) -> Dictionary:
	var result := Gif.decode(bytes, width * height)
	check(label + ": accepted", result.ok)
	if result.ok:
		check(label + ": dimensions", result.value.width == width and result.value.height == height and result.value.pixels == width * height)
		check(label + ": RGBA", result.value.rgba == rgba)
		check(label + ": alpha flag", result.value.has_alpha == alpha)
	else:
		printerr(R.texts(result))
	return result

func _refuse(label: String, bytes: PackedByteArray, code := "", remaining := 1 << 20) -> void:
	var result := Gif.decode(bytes, remaining)
	check(label, not result.ok and (code.is_empty() or result.diagnostics[0].code == code))

static func _large_indices() -> Array:
	var values: Array = []
	for index: int in 4200:
		values.append((index * 7 + (index >> 4)) % 4)
	return values

static func _palette8() -> Array:
	var palette: Array = []
	for index: int in 8:
		palette.append([index * 30 + 5, 250 - index * 20, index * 9])
	return palette

## Independent oracle: palette colour with alpha 255, or alpha 0 for the transparent index.
static func _expected(palette: Array, indices: Array, transparent := -1) -> PackedByteArray:
	var out := PackedByteArray()
	for index: int in indices:
		var colour: Array = palette[index]
		out.append_array(PackedByteArray([colour[0], colour[1], colour[2], 0 if index == transparent else 255]))
	return out

static func _size_field(count: int) -> int:
	var field := 0
	while (2 << field) < count:
		field += 1
	return field

static func _flatten(palette: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for colour: Array in palette:
		out.append_array(PackedByteArray([colour[0], colour[1], colour[2]]))
	return out

static func _gif(width: int, height: int, palette: Array, parts: Array, version := "GIF89a") -> PackedByteArray:
	var bytes := version.to_ascii_buffer()
	var packed := 0
	if not palette.is_empty():
		packed = 0x80 | 0x70 | _size_field(palette.size())
	bytes.append_array(PackedByteArray([width & 255, width >> 8, height & 255, height >> 8, packed, 0, 0]))
	if not palette.is_empty():
		bytes.append_array(_flatten(palette))
	for part: PackedByteArray in parts:
		bytes.append_array(part)
	bytes.append(0x3B)
	return bytes

static func _ext(label: int, blocks: Array) -> PackedByteArray:
	var bytes := PackedByteArray([0x21, label])
	for block: PackedByteArray in blocks:
		bytes.append(block.size())
		bytes.append_array(block)
	bytes.append(0)
	return bytes

## Options: transparent (GCE index), interlaced, local (palette), clear_every, codes (raw [code, bits]).
static func _frame(left: int, top: int, width: int, height: int, indices: Array, mcs := 2, options := {}) -> PackedByteArray:
	var bytes := PackedByteArray()
	if options.has("transparent"):
		bytes.append_array(PackedByteArray([0x21, 0xF9, 4, 1, 0, 0, int(options.transparent), 0]))
	var local: Array = options.get("local", [])
	var flags := 0
	if options.get("interlaced", false):
		flags |= 0x40
	if not local.is_empty():
		flags |= 0x80 | _size_field(local.size())
	bytes.append_array(PackedByteArray([0x2C, left & 255, left >> 8, top & 255, top >> 8,
		width & 255, width >> 8, height & 255, height >> 8, flags]))
	if not local.is_empty():
		bytes.append_array(_flatten(local))
	bytes.append(mcs)
	var codes: Array = options["codes"] if options.has("codes") else _literals(indices, mcs, int(options.get("clear_every", 0)))
	bytes.append_array(_blocks(_pack(codes)))
	return bytes

## Test-side LZW encoder: literal codes only (no dictionary reuse), tracking the code-size growth
## the GIF specification prescribes (the table gains an entry per code except the first after a clear).
static func _literals(indices: Array, mcs: int, clear_every := 0) -> Array:
	var clear := 1 << mcs
	var codes: Array = [[clear, mcs + 1]]
	var size := mcs + 1
	var next := clear + 2
	var since := 0
	for index: int in indices:
		if clear_every > 0 and since == clear_every:
			codes.append([clear, size])
			size = mcs + 1
			next = clear + 2
			since = 0
		codes.append([index, size])
		since += 1
		if since > 1 and next < 4096:
			next += 1
			if next == (1 << size) and size < 12:
				size += 1
	codes.append([clear + 1, size])
	return codes

static func _pack(codes: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	var accumulator := 0
	var held := 0
	for pair: Array in codes:
		accumulator |= int(pair[0]) << held
		held += int(pair[1])
		while held >= 8:
			bytes.append(accumulator & 255)
			accumulator >>= 8
			held -= 8
	if held > 0:
		bytes.append(accumulator & 255)
	return bytes

static func _blocks(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	for at: int in range(0, data.size(), 255):
		var chunk := data.slice(at, mini(at + 255, data.size()))
		out.append(chunk.size())
		out.append_array(chunk)
	out.append(0)
	return out
