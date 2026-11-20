extends RefCounted
## Strict first-frame GIF87a/GIF89a decoder returning RGBA8. ClearView uses GIF for translucent
## propeller disks. Frame 1 is composed onto the logical screen: pixels outside the frame and pixels
## of the Graphic Control transparency index get alpha 0. LZW data after the last pixel is not
## interpreted. Work is bounded by file size, pixel budget, block and code counts. No engine
## decoding or string conversion touches untrusted bytes.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const FRAME_NOTE := "Only the first GIF frame was imported."
const MAX_BLOCKS := 1024
const MAX_SUB_BLOCKS := 65536
const TABLE_CODES := 4096
var _data := PackedByteArray()
var _cancel := Callable()
var _budget := 0
var _pos := 0
var _message := ""
var _code := R.SOURCE_INVALID
var _sub_blocks := 0
var _lz := PackedByteArray()
var _width := 0
var _height := 0
var _rgba := PackedByteArray()
var _has_alpha := false
var _more_frames := false

static func is_gif(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 6 and bytes[0] == 71 and bytes[1] == 73 and bytes[2] == 70 and bytes[3] == 56 \
		and (bytes[4] == 55 or bytes[4] == 57) and bytes[5] == 97

static func decode(bytes: PackedByteArray, remaining_pixels: int, cancel := Callable()) -> Dictionary:
	if bytes.size() > Limits.PNG_BYTES or remaining_pixels < 0:
		return R.fail(R.SOURCE_LIMIT, "The GIF exceeds the image byte or pixel limit.", "source", "import")
	var reader := new()
	reader._data = bytes
	reader._cancel = cancel
	reader._budget = mini(remaining_pixels, Limits.PNG_AGGREGATE_PIXELS)
	if not reader._run():
		return R.fail(reader._code, reader._message, "source", "import")
	var notes: Array = []
	if reader._more_frames:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, FRAME_NOTE, "source", "import", [], R.SEVERITY_INFO))
	return R.ok({rgba = reader._rgba, width = reader._width, height = reader._height,
		pixels = reader._width * reader._height, has_alpha = reader._has_alpha}, notes)

func _reject(message: String, code := R.SOURCE_INVALID) -> bool:
	if _message.is_empty():
		_message = message
		_code = code
	return false

func _poll() -> bool:
	if _cancel.is_valid() and bool(_cancel.call()):
		return _reject("The import was cancelled.")
	return true

## Reads a colour table at `_pos`; an empty result means it was truncated (already rejected).
func _table(flags: int) -> PackedByteArray:
	var length := 3 << ((flags & 7) + 1)
	if length > _data.size() - _pos:
		_reject("The GIF colour table is truncated.")
		return PackedByteArray()
	var table := _data.slice(_pos, _pos + length)
	_pos += length
	return table

## Skips (or collects into `_lz`) data sub-blocks up to the zero terminator.
func _read_blocks(collect := false) -> bool:
	while true:
		if _pos >= _data.size():
			return _reject("The GIF data blocks are truncated.")
		var length: int = _data[_pos]
		_pos += 1
		if length == 0:
			return true
		_sub_blocks += 1
		if _sub_blocks > MAX_SUB_BLOCKS:
			return _reject("The GIF has too many data blocks.", R.SOURCE_LIMIT)
		if (_sub_blocks & 4095) == 0 and not _poll():
			return false
		if length > _data.size() - _pos:
			return _reject("The GIF data blocks are truncated.")
		if collect:
			_lz.append_array(_data.slice(_pos, _pos + length))
		_pos += length
	return false

func _run() -> bool:
	if not _poll():
		return false
	if _data.size() < 14 or not is_gif(_data):
		return _reject("The image does not start with a GIF header.")
	_width = _data.decode_u16(6)
	_height = _data.decode_u16(8)
	if _width < 1 or _height < 1:
		return _reject("The GIF dimensions are invalid.")
	if _width > Limits.PNG_SIDE_PIXELS or _height > Limits.PNG_SIDE_PIXELS or _width * _height > _budget:
		return _reject("The GIF exceeds the image pixel limit.", R.SOURCE_LIMIT)
	var flags: int = _data[10]
	_pos = 13
	var global := PackedByteArray()
	if (flags & 0x80) != 0:
		global = _table(flags)
		if global.is_empty():
			return false
	var transparent := -1
	for _block: int in MAX_BLOCKS:
		if _pos >= _data.size():
			return _reject("The GIF ends before its first image.")
		var kind: int = _data[_pos]
		_pos += 1
		if kind == 0x2C:
			return _image(global, transparent)
		if kind != 0x21:
			return _reject("The GIF has no image." if kind == 0x3B else "The GIF contains an unknown block.")
		if _pos >= _data.size():
			return _reject("The GIF extension is truncated.")
		var label: int = _data[_pos]
		_pos += 1
		if label == 0xF9:
			# Block size 4, packed flags, delay (2), transparent index, terminator.
			if _data.size() - _pos < 6 or _data[_pos] != 4 or _data[_pos + 5] != 0:
				return _reject("The GIF graphic control block is invalid.")
			transparent = _data[_pos + 4] if (_data[_pos + 1] & 1) != 0 else -1
			_pos += 6
		elif not _read_blocks():
			return false
	return _reject("The GIF has too many blocks before its first image.", R.SOURCE_LIMIT)

func _image(global: PackedByteArray, transparent: int) -> bool:
	if _data.size() - _pos < 10:
		return _reject("The GIF image descriptor is truncated.")
	var left := _data.decode_u16(_pos)
	var top := _data.decode_u16(_pos + 2)
	var width := _data.decode_u16(_pos + 4)
	var height := _data.decode_u16(_pos + 6)
	var flags: int = _data[_pos + 8]
	_pos += 9
	if width < 1 or height < 1 or left + width > _width or top + height > _height:
		return _reject("The first GIF frame is empty or outside its logical screen.")
	var table := global
	if (flags & 0x80) != 0:
		table = _table(flags)
		if table.is_empty():
			return false
	if table.is_empty():
		return _reject("The GIF has no colour table.")
	if _pos >= _data.size():
		return _reject("The GIF image data is truncated.")
	var min_size: int = _data[_pos]
	_pos += 1
	if min_size < 2 or min_size > 8:
		return _reject("The GIF LZW code size is invalid.")
	if not _read_blocks(true):
		return false
	var indices := _lzw(min_size, width * height)
	if indices.is_empty():
		return false
	if not _compose(indices, table, left, top, width, height, (flags & 0x40) != 0, transparent):
		return false
	return _scan_after()

func _compose(indices: PackedByteArray, table: PackedByteArray, left: int, top: int, width: int, height: int, interlaced: bool, transparent: int) -> bool:
	var rows := PackedInt32Array()
	var phases: Array = [[0, 8], [4, 8], [2, 4], [1, 2]] if interlaced else [[0, 1]]
	for phase: Array in phases:
		for row: int in range(int(phase[0]), height, int(phase[1])):
			rows.append(row)
	@warning_ignore("integer_division")
	var colours: int = table.size() / 3
	_rgba.resize(_width * _height * 4)
	_has_alpha = width * height < _width * _height
	var source := 0
	for stored: int in height:
		if not _poll():
			return false
		var at := ((top + rows[stored]) * _width + left) * 4
		for _column: int in width:
			var index: int = indices[source]
			source += 1
			if index >= colours:
				return _reject("The GIF refers to a colour outside its table.")
			var base := index * 3
			_rgba[at] = table[base]
			_rgba[at + 1] = table[base + 1]
			_rgba[at + 2] = table[base + 2]
			if index == transparent:
				_has_alpha = true
			else:
				_rgba[at + 3] = 255
			at += 4
	return true

## Frame 1 is complete. Only look for another image descriptor; a missing trailer at a block
## boundary is tolerated and bytes after the trailer are not examined.
func _scan_after() -> bool:
	for _block: int in MAX_BLOCKS:
		if _pos >= _data.size():
			return true
		var kind: int = _data[_pos]
		_pos += 1
		if kind == 0x3B:
			return true
		if kind == 0x2C:
			_more_frames = true
			return true
		if kind != 0x21 or _pos >= _data.size():
			return _reject("The GIF has an invalid block after its first image.")
		_pos += 1
		if not _read_blocks():
			return false
	return _reject("The GIF has too many blocks after its first image.", R.SOURCE_LIMIT)

## GIF LZW: LSB-first codes, 3..12 bits, deferred clear (a full table adds no entries).
## Returns an empty array after rejecting.
func _lzw(min_size: int, total: int) -> PackedByteArray:
	var empty := PackedByteArray()
	var pixels := PackedByteArray()
	pixels.resize(total)
	var clear := 1 << min_size
	var end_code := clear + 1
	var prefix := PackedInt32Array()
	prefix.resize(TABLE_CODES)
	var suffix := PackedByteArray()
	suffix.resize(TABLE_CODES)
	var first := PackedByteArray()
	first.resize(TABLE_CODES)
	var lengths := PackedInt32Array()
	lengths.resize(TABLE_CODES)
	for root: int in clear:
		first[root] = root
		lengths[root] = 1
	var size := min_size + 1
	var next := clear + 2
	var previous := -1
	var filled := 0
	var polled := 0
	var codes := 0
	var limit := 2 * total + 64
	var accumulator := 0
	var held := 0
	var at := 0
	while filled < total:
		while held < size:
			if at >= _lz.size():
				_reject("The GIF image data is truncated.")
				return empty
			accumulator |= _lz[at] << held
			at += 1
			held += 8
		var code := accumulator & ((1 << size) - 1)
		accumulator >>= size
		held -= size
		codes += 1
		if codes > limit:
			_reject("The GIF image data has too many codes.", R.SOURCE_LIMIT)
			return empty
		if (codes & 4095) == 0 and not _poll():
			return empty
		if code == clear:
			size = min_size + 1
			next = clear + 2
			previous = -1
			continue
		if code == end_code:
			_reject("The GIF image data ends before every pixel.")
			return empty
		if previous < 0:
			if code >= clear:
				_reject("The GIF image data starts with an invalid code.")
				return empty
		elif code > next:
			_reject("The GIF image data contains an invalid code.")
			return empty
		elif next < TABLE_CODES:
			# KwKwK: an unknown code (== next) repeats the previous string plus its first symbol.
			prefix[next] = previous
			suffix[next] = first[code if code < next else previous]
			first[next] = first[previous]
			lengths[next] = lengths[previous] + 1
			next += 1
			if next == (1 << size) and size < 12:
				size += 1
		var length := lengths[code]
		if length < 1 or length > total - filled:
			_reject("The GIF image data has more pixels than its frame.")
			return empty
		var cursor := code
		var write := filled + length - 1
		while cursor >= clear:
			pixels[write] = suffix[cursor]
			write -= 1
			cursor = prefix[cursor]
		pixels[filled] = cursor
		filled += length
		previous = code
		if filled - polled >= 4096:
			polled = filled
			if not _poll():
				return empty
	return pixels
