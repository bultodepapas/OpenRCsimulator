extends RefCounted
## T.81 baseline, single interleaved Huffman scan. Validates entropy, not just image headers.
## This is a conservative subset; native decoding still needs target-engine qualification.
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const MAX_NON_RESTART_MARKERS := 4096
const MAX_MARKERS := MAX_NON_RESTART_MARKERS + 262144
const MAX_COMMENT_BYTES := 256 * 1024
## EXIF (APP1), ICC colour profiles (APP2), Photoshop data (APP13) and other APPn segments are
## skipped as opaque metadata. They never change the validated baseline image data.
const MAX_METADATA_BYTES := 1024 * 1024
const METADATA_NOTE := "JPEG metadata (camera, colour profile or editor data) was ignored."
const MAX_SYMBOLS := 8 * 1024 * 1024
const MAX_READ_BITS := 64 * 1024 * 1024
var _data := PackedByteArray()
var _cancel := Callable()
var _budget := 0
var _pos := 0
var _message := ""
var _code := R.SOURCE_INVALID
var _markers := 0
var _non_restart_markers := 0
var _comment_count := 0
var _comment_bytes := 0
var _metadata_count := 0
var _metadata_bytes := 0
var _jfif := false
var _adobe := false
var _adobe_transform := -1
var _frame := false
var _dri_seen := false
var _restart_interval := 0
var _width := 0
var _height := 0
var _sampling := 0
var _quant_ids: Array[int] = []
var _quant := {}
var _huffman := {}
var _dc_tables: Array = []
var _ac_tables: Array = []
var _current_byte := 0
var _remaining_bits := 0
var _read_bits := 0
var _symbols := 0
var _predictors: Array[int] = [0,0,0]

static func inspect(bytes: PackedByteArray, remaining_pixels: int, cancel := Callable()) -> Dictionary:
	if bytes.size() > Limits.PNG_BYTES or remaining_pixels < 0:
		return R.fail(R.SOURCE_LIMIT, "The JPEG exceeds the image byte or pixel limit.", "source", "import")
	var reader := new()
	reader._data = bytes
	reader._budget = mini(remaining_pixels, Limits.PNG_AGGREGATE_PIXELS)
	reader._cancel = cancel
	if not reader._run():
		return R.fail(reader._code, reader._message, "source", "import")
	var notes: Array = []
	if reader._comment_count > 0:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, "JPEG comments were ignored.", "source", "import", [], R.SEVERITY_INFO))
	if reader._metadata_count > 0:
		notes.append(R.diagnostic(R.SOURCE_UNSUPPORTED, METADATA_NOTE, "source", "import", [], R.SEVERITY_INFO))
	return R.ok({width = reader._width, height = reader._height, pixels = reader._width * reader._height}, notes)

func _reject(message: String, code := R.SOURCE_INVALID) -> bool:
	if _message.is_empty():
		_message = message
		_code = code
	return false

func _poll() -> bool:
	if _cancel.is_valid() and bool(_cancel.call()):
		return _reject("The import was cancelled.")
	return true

func _u16(at: int) -> int:
	return (_data[at] << 8) | _data[at + 1]

func _marker() -> int:
	_markers += 1
	if _markers > MAX_MARKERS:
		_reject("The JPEG has too many markers.", R.SOURCE_LIMIT)
		return -1
	if _pos >= _data.size() or _data[_pos] != 255:
		_reject("The JPEG is missing an expected marker.")
		return -1
	while _pos < _data.size() and _data[_pos] == 255:
		_pos += 1
		if (_pos & 4095) == 0 and not _poll():
			return -1
	if _pos >= _data.size() or _data[_pos] == 0:
		_reject("The JPEG has a truncated or invalid marker.")
		return -1
	var value: int = _data[_pos]
	_pos += 1
	return value

func _count_non_restart() -> bool:
	_non_restart_markers += 1
	if _non_restart_markers > MAX_NON_RESTART_MARKERS:
		return _reject("The JPEG has too many header markers.", R.SOURCE_LIMIT)
	return _poll()

func _segment_end() -> int:
	if _data.size() - _pos < 2:
		_reject("The JPEG segment length is truncated.")
		return -1
	var length := _u16(_pos)
	if length < 2 or length > _data.size() - _pos:
		_reject("The JPEG segment length is invalid.")
		return -1
	var end := _pos + length
	_pos += 2
	return end

func _run() -> bool:
	if not _poll():
		return false
	if _data.size() < 4 or _data[0] != 255 or _data[1] != 0xD8:
		return _reject("The image does not start with a JPEG marker.")
	_pos = 2
	while true:
		var marker := _marker()
		if marker < 0 or not _count_non_restart():
			return false
		var metadata := marker >= 0xE1 and marker <= 0xEF and marker != 0xEE
		if marker not in [0xC0,0xC4,0xDA,0xDB,0xDD,0xE0,0xEE,0xFE] and not metadata:
			return _reject("This JPEG encoding or metadata is not supported. Re-export it as a standard baseline JPEG or PNG.", R.SOURCE_UNSUPPORTED)
		var end := _segment_end()
		if end < 0:
			return false
		var ok := false
		if metadata:
			ok = _read_metadata(end)
		match marker:
			0xC0: ok = _read_frame(end)
			0xC4: ok = _read_huffman(end)
			0xDB: ok = _read_quant(end)
			0xDD: ok = _read_restart_interval(end)
			0xE0: ok = _read_jfif(end)
			0xEE: ok = _read_adobe(end)
			0xFE: ok = _read_comment(end)
			0xDA:
				if not _read_scan_header(end):
					return false
				_pos = end
				return _scan()
		if not ok:
			return false
		_pos = end
	return false

func _read_frame(end: int) -> bool:
	if _frame or end - _pos != 15:
		return _reject("The JPEG frame header is invalid or duplicated.")
	if _data[_pos] != 8 or _data[_pos + 5] != 3:
		return _reject("Only eight-bit three-component baseline JPEG textures are supported.", R.SOURCE_UNSUPPORTED)
	_height = _u16(_pos + 1)
	_width = _u16(_pos + 3)
	if _width < 1 or _height < 1:
		return _reject("The JPEG dimensions are invalid.")
	if _width > Limits.PNG_SIDE_PIXELS or _height > Limits.PNG_SIDE_PIXELS or _width * _height > _budget:
		return _reject("The JPEG exceeds the image pixel limit.", R.SOURCE_LIMIT)
	for component: int in 3:
		var at := _pos + 6 + component * 3
		if _data[at] != component + 1:
			return _reject("The JPEG component identifiers are unsupported.", R.SOURCE_UNSUPPORTED)
		var sample: int = _data[at + 1]
		if component == 0:
			if sample not in [0x11,0x22]:
				return _reject("The JPEG sampling is unsupported.", R.SOURCE_UNSUPPORTED)
			_sampling = sample
		elif sample != 0x11:
			return _reject("The JPEG sampling is unsupported.", R.SOURCE_UNSUPPORTED)
		var table: int = _data[at + 2]
		if table > 3:
			return _reject("The JPEG quantization selector is invalid.")
		_quant_ids.append(table)
	_frame = true
	return true

func _read_quant(end: int) -> bool:
	if _pos == end:
		return _reject("The JPEG quantization segment is empty.")
	var at := _pos
	while at < end:
		if end - at < 65:
			return _reject("The JPEG quantization table is truncated.")
		var spec: int = _data[at]
		at += 1
		var id := spec & 15
		if (spec >> 4) != 0 or id > 3:
			return _reject("The JPEG quantization table is unsupported.", R.SOURCE_UNSUPPORTED)
		if _quant.has(id):
			return _reject("The JPEG redefines a quantization table.")
		for index: int in 64:
			if _data[at + index] == 0:
				return _reject("The JPEG quantization table contains zero.")
		_quant[id] = true
		at += 64
	return true

func _read_huffman(end: int) -> bool:
	if _pos == end:
		return _reject("The JPEG Huffman segment is empty.")
	var at := _pos
	while at < end:
		if end - at < 17:
			return _reject("The JPEG Huffman table is truncated.")
		var spec: int = _data[at]
		at += 1
		var kind := spec >> 4
		var id := spec & 15
		if kind > 1 or id > 1:
			return _reject("The JPEG Huffman table is unsupported.", R.SOURCE_UNSUPPORTED)
		var table_id := (kind << 4) | id
		if _huffman.has(table_id):
			return _reject("The JPEG redefines a Huffman table.")
		var counts := PackedByteArray()
		var total := 0
		for index: int in 16:
			var count: int = _data[at + index]
			counts.append(count)
			total += count
		at += 16
		if total == 0 or total > (12 if kind == 0 else 162) or total > end - at:
			return _reject("The JPEG Huffman table has an invalid symbol count.")
		var codes := {}
		var seen := {}
		var code := 0
		for length: int in range(1,17):
			var count: int = counts[length - 1]
			if code + count >= (1 << length):
				return _reject("The JPEG Huffman code lengths are invalid.")
			for entry: int in count:
				var symbol: int = _data[at]
				at += 1
				if seen.has(symbol):
					return _reject("The JPEG Huffman table repeats a symbol.")
				seen[symbol] = true
				if kind == 0:
					if symbol > 11:
						return _reject("The JPEG DC category is invalid.")
				elif symbol not in [0,0xF0] and ((symbol & 15) < 1 or (symbol & 15) > 10):
					return _reject("The JPEG AC symbol is invalid.")
				codes[(length << 16) | code] = symbol
				code += 1
			code <<= 1
		_huffman[table_id] = codes
	return true

func _read_restart_interval(end: int) -> bool:
	if _dri_seen or end - _pos != 2:
		return _reject("The JPEG restart interval is invalid or duplicated.")
	_dri_seen = true
	_restart_interval = _u16(_pos)
	return true

func _read_jfif(end: int) -> bool:
	if _jfif or _non_restart_markers != 1 or end - _pos < 14:
		return _reject("The JPEG JFIF marker is invalid or misplaced.")
	if _data.slice(_pos,_pos + 5) != PackedByteArray([74,70,73,70,0]):
		return _reject("The JPEG APP0 marker is unsupported.", R.SOURCE_UNSUPPORTED)
	if _data[_pos + 5] != 1 or _data[_pos + 6] > 2:
		return _reject("The JPEG JFIF version is unsupported.", R.SOURCE_UNSUPPORTED)
	if _data[_pos + 7] > 2 or _u16(_pos + 8) == 0 or _u16(_pos + 10) == 0:
		return _reject("The JPEG JFIF density is invalid.")
	var tw: int = _data[_pos + 12]
	var th: int = _data[_pos + 13]
	if (tw == 0) != (th == 0) or end - _pos != 14 + 3 * tw * th:
		return _reject("The JPEG JFIF thumbnail length is invalid.")
	_jfif = true
	return true

func _read_adobe(end: int) -> bool:
	if _adobe or end - _pos != 12:
		return _reject("The JPEG Adobe marker is invalid or duplicated.")
	if _data.slice(_pos,_pos + 5) != PackedByteArray([65,100,111,98,101]):
		return _reject("The JPEG APP14 marker is unsupported.", R.SOURCE_UNSUPPORTED)
	# Flags0/flags1 are encoder hints (e.g. 0x8000 "blend"); only the colour transform affects decoding.
	if _u16(_pos + 5) not in [100,101] or _data[_pos + 11] > 1:
		return _reject("The JPEG Adobe marker is unsupported.", R.SOURCE_UNSUPPORTED)
	_adobe_transform = _data[_pos + 11]
	if _jfif and _adobe_transform == 0:
		return _reject("The JPEG has conflicting colour declarations.")
	_adobe = true
	return true

func _read_comment(end: int) -> bool:
	_comment_count += 1
	_comment_bytes += end - _pos
	if _comment_bytes > MAX_COMMENT_BYTES:
		return _reject("The JPEG comments exceed the metadata limit.", R.SOURCE_LIMIT)
	return true

## Opaque APPn metadata, bounded in total size. Its contents are never interpreted.
func _read_metadata(end: int) -> bool:
	_metadata_count += 1
	_metadata_bytes += end - _pos
	if _metadata_bytes > MAX_METADATA_BYTES:
		return _reject("The JPEG metadata exceeds its size limit.", R.SOURCE_LIMIT)
	return true

func _read_scan_header(end: int) -> bool:
	if not _frame or end - _pos != 10 or _data[_pos] != 3:
		return _reject("The JPEG scan header is invalid or unsupported.")
	for component: int in 3:
		var at := _pos + 1 + component * 2
		if _data[at] != component + 1:
			return _reject("The JPEG scan component order is unsupported.", R.SOURCE_UNSUPPORTED)
		var selectors: int = _data[at + 1]
		var dc := selectors >> 4
		var ac := selectors & 15
		if dc > 1 or ac > 1 or not _huffman.has(dc) or not _huffman.has(0x10 | ac) or not _quant.has(_quant_ids[component]):
			return _reject("The JPEG scan refers to a missing or invalid table.")
		_dc_tables.append(_huffman[dc])
		_ac_tables.append(_huffman[0x10 | ac])
	if _data[_pos + 7] != 0 or _data[_pos + 8] != 63 or _data[_pos + 9] != 0:
		return _reject("The JPEG scan parameters are unsupported.", R.SOURCE_UNSUPPORTED)
	return true

## Fetch only the next needed byte; a data FF must be escaped as FF00.
func _bit() -> int:
	if not _message.is_empty():
		return 0
	if _read_bits >= MAX_READ_BITS:
		_reject("The JPEG entropy work limit was exceeded.", R.SOURCE_LIMIT)
		return 0
	if (_read_bits & 4095) == 0 and not _poll():
		return 0
	if _remaining_bits == 0:
		if _pos >= _data.size():
			_reject("The JPEG entropy data is truncated.")
			return 0
		_current_byte = _data[_pos]
		_pos += 1
		if _current_byte == 255:
			if _pos >= _data.size() or _data[_pos] != 0:
				_reject("The JPEG entropy data has an unexpected marker.")
				return 0
			_pos += 1
		_remaining_bits = 8
	_read_bits += 1
	_remaining_bits -= 1
	return (_current_byte >> _remaining_bits) & 1

func _bits(count: int) -> int:
	var value := 0
	for index: int in count:
		value = (value << 1) | _bit()
		if not _message.is_empty():
			break
	return value

func _symbol(table: Dictionary) -> int:
	_symbols += 1
	if _symbols > MAX_SYMBOLS:
		_reject("The JPEG symbol work limit was exceeded.", R.SOURCE_LIMIT)
		return -1
	var code := 0
	for length: int in range(1,17):
		code = (code << 1) | _bit()
		if not _message.is_empty():
			return -1
		var key := (length << 16) | code
		if table.has(key):
			return table[key]
	_reject("The JPEG contains an invalid Huffman code.")
	return -1

func _block(component: int) -> bool:
	var category := _symbol(_dc_tables[component])
	if category < 0:
		return false
	var difference := _bits(category)
	if not _message.is_empty():
		return false
	if category > 0 and difference < (1 << (category - 1)):
		difference -= (1 << category) - 1
	_predictors[component] += difference
	if _predictors[component] < -1024 or _predictors[component] > 1023:
		return _reject("The JPEG DC coefficient is outside the accepted range.")
	var coefficient := 1
	while coefficient < 64:
		var symbol := _symbol(_ac_tables[component])
		if symbol < 0:
			return false
		if symbol == 0:
			break
		if symbol == 0xF0:
			if coefficient + 16 > 64:
				return _reject("The JPEG zero run exceeds its block.")
			coefficient += 16
			continue
		coefficient += symbol >> 4
		if coefficient >= 64:
			return _reject("The JPEG coefficient run exceeds its block.")
		_bits(symbol & 15)
		if not _message.is_empty():
			return false
		coefficient += 1
	return true

func _align() -> bool:
	if _remaining_bits > 0:
		var mask := (1 << _remaining_bits) - 1
		if (_current_byte & mask) != mask:
			return _reject("The JPEG entropy padding bits are invalid.")
	_remaining_bits = 0
	return true

func _scan() -> bool:
	var side := 16 if _sampling == 0x22 else 8
	var columns := (_width + side - 1) / side
	var rows := (_height + side - 1) / side
	var total := columns * rows
	var next_restart := 0
	for mcu: int in total:
		for component: int in 3:
			var blocks := 4 if component == 0 and _sampling == 0x22 else 1
			for index: int in blocks:
				if not _block(component):
					return false
		if _restart_interval > 0 and mcu + 1 < total and (mcu + 1) % _restart_interval == 0:
			if not _align():
				return false
			var marker := _marker()
			if marker < 0:
				return false
			if marker != 0xD0 + next_restart:
				return _reject("The JPEG restart marker is missing or out of sequence.")
			next_restart = (next_restart + 1) & 7
			_predictors = [0,0,0]
	if not _align():
		return false
	while true:
		var marker := _marker()
		if marker < 0 or not _count_non_restart():
			return false
		if marker == 0xD9:
			if _pos != _data.size():
				return _reject("Bytes follow the JPEG end marker.")
			return true
		if marker != 0xFE:
			return _reject("The JPEG has an unexpected marker after its scan.")
		var end := _segment_end()
		if end < 0 or not _read_comment(end):
			return false
		_pos = end
	return false
