extends RefCounted
## Strict, bounded STL reader for untrusted player-supplied model files (AC-02).
##
## Static and pure: captured bytes in, result envelope out. No scene tree and no file access, so
## it is safe on a worker thread. The geometry is presentation data in source units and source
## axes with the authored winding. No repair and no unit, volume or watertightness inference.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")

const FORMAT_BINARY := "stl-binary"
const FORMAT_ASCII := "stl-ascii"

const _STEP := "import"
const _HEADER_BYTES := 84
const _FACET_BYTES := 50
# A chunk without a line feed therefore always holds an over-long line.
const _CHUNK_BYTES := 4 * Limits.STL_ASCII_LINE_BYTES
# 0x8080808080808080: the high bit of each byte in a little-endian int64 word.
const _HIGH_BITS := -9187201950435737472

# Decimal grammar of an ASCII STL number.
const _NUMBER := "[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?"
# Subset that `String.to_float()` converts quietly and without dropping digits: at most 18
# mantissa digits and a decimal exponent within +-99. It warns above 511 and ignores digits past
# the 18th, leading zeros included.
const _SAFE_NUMBER := "[+-]?(?=(?:[0-9]{1,18}|(?=[0-9]*\\.)[0-9.]{2,19})(?![0-9.]))" \
		+ "(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?0?[0-9]{1,2})?"
# Matches a whole normalized chunk made only of spaces, line feeds, lower-case words, safe numbers
# and the free text after `solid`/`endsolid`. A match proves every number token is safe, so the
# per-token check is skipped. No match, or a matcher resource limit, selects the checked path.
const _PROOF := "^(?>[ \\n]++|(?:end)?solid(?=[ \\n]|\\z)[^\\n]*+|[a-z]++(?=[ \\n]|\\z)|(?>" \
		+ _SAFE_NUMBER + "(?=[ \\n]|\\z)))*+\\z"

const _S_SOLID := 0
const _S_FACET := 1
const _S_NORMAL := 2
const _S_NUMBER := 3
const _S_OUTER := 4
const _S_LOOP := 5
const _S_VERTEX := 6
const _S_ENDLOOP := 7
const _S_ENDFACET := 8
const _KEYWORDS := ["solid", "facet", "normal", "", "outer", "loop", "vertex", "endloop", "endfacet"]


## Reads one captured STL file. Returns the `R` envelope; on success `value` is
## `{format, name, triangle_count, positions, bounds_min, bounds_max, dropped_degenerate,
## inconsistent_normals, nonzero_attributes}`. `positions` holds 9 float32 per kept triangle.
## `name` is the first ASCII solid name, or the printable ASCII start of a binary header.
## Every number is rounded to float32 first, in both formats, and must then be finite. Zero-area
## facets (exactly zero cross product) are dropped; attribute words are counted, never read as colour.
static func read(bytes: PackedByteArray) -> Dictionary:
	var size := bytes.size()
	if size == 0:
		return R.fail(R.SOURCE_LIMIT, "The model file is empty.", "", _STEP)
	if size > Limits.MODEL_SOURCE_BYTES:
		return R.fail(R.SOURCE_LIMIT, "The model file has %s bytes; the limit is %s bytes.", "", _STEP,
			[str(size), str(Limits.MODEL_SOURCE_BYTES)])
	var count := -1
	var expected := -1
	if size >= _HEADER_BYTES:
		# uint32 times 50 stays far inside int64.
		count = bytes.decode_u32(80)
		expected = _HEADER_BYTES + _FACET_BYTES * count
		if expected == size:
			return _read_binary(bytes, count)
	if _starts_with_solid(bytes):
		return _read_ascii(bytes)
	if expected < 0:
		return R.fail(R.SOURCE_INVALID, "This is not an STL file: it has %s bytes, fewer than a binary STL header, "
			+ "and its text does not start with \"solid\".", "", _STEP, [str(size)])
	var arguments := [str(count), str(expected), str(size)]
	if size < expected:
		return R.fail(R.SOURCE_INVALID, "This is not a valid STL file. Its text does not start with \"solid\", and as "
			+ "binary STL it declares %s facets, which needs %s bytes, but the file has only %s bytes. "
			+ "It may be truncated; export it again.", "", _STEP, arguments)
	return R.fail(R.SOURCE_INVALID, "This is not a valid STL file. Its text does not start with \"solid\", and as "
		+ "binary STL it declares %s facets, which needs %s bytes, but the file has %s bytes. "
		+ "Export it again as STL.", "", _STEP, arguments)


static func _read_binary(bytes: PackedByteArray, count: int) -> Dictionary:
	if count == 0:
		return R.fail(R.SOURCE_INVALID, "The STL file contains no facets.", "", _STEP)
	if count > Limits.TRIANGLES:
		return _facet_limit()
	var geometry := _Geometry.new()
	geometry.positions.resize(count * 9)
	var attributes := 0
	var offset := _HEADER_BYTES
	for index in count:
		var status := geometry.add(
			bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8),
			bytes.decode_float(offset + 12), bytes.decode_float(offset + 16), bytes.decode_float(offset + 20),
			bytes.decode_float(offset + 24), bytes.decode_float(offset + 28), bytes.decode_float(offset + 32),
			bytes.decode_float(offset + 36), bytes.decode_float(offset + 40), bytes.decode_float(offset + 44))
		if status > _Geometry.DROPPED:
			return _facet_failure(status, index + 1, 0)
		if bytes.decode_u16(offset + 48) != 0:
			attributes += 1
		offset += _FACET_BYTES
	var end := 0
	while end < 80 and bytes[end] >= 0x20 and bytes[end] <= 0x7E:
		end += 1
	return geometry.finish(FORMAT_BINARY, bytes.slice(0, end).get_string_from_ascii().strip_edges(), attributes)


static func _read_ascii(bytes: PackedByteArray) -> Dictionary:
	var nul := bytes.find(0)
	if nul >= 0:
		# Usually a binary file with a `solid` header and a wrong length.
		return R.fail(R.SOURCE_INVALID, "The file starts with \"solid\" but is not STL text: it has a NUL byte at "
			+ "offset %s. If it is a binary STL file, its length does not match its facet count; it may be "
			+ "truncated. Export it again.", "", _STEP, [str(nul)])
	var strict := RegEx.create_from_string("^" + _NUMBER + "\\z")
	var safe := RegEx.create_from_string("^" + _SAFE_NUMBER + "\\z")
	var proof := RegEx.create_from_string(_PROOF)
	var geometry := _Geometry.new()
	var facet := PackedFloat32Array()
	facet.resize(12)
	var state := _S_SOLID
	var filled := 0
	var solids := 0
	var facets := 0
	var name := ""
	var line_number := 0
	var max_line := Limits.STL_ASCII_LINE_BYTES
	var size := bytes.size()
	var position := 0
	while position < size:
		# Whole lines only: cut at the last line feed inside the chunk window.
		var cut := mini(position + _CHUNK_BYTES, size)
		var next := cut
		if cut < size:
			cut = bytes.rfind(10, cut - 1)
			if cut < position:
				return _line_limit(line_number + 1)
			next = cut + 1
		var chunk := bytes.slice(position, cut)
		position = next
		# The engine decoder logs on malformed input, so validate before decoding.
		if not _is_utf8(chunk):
			return _not_utf8(line_number + 1)
		var text := chunk.get_string_from_utf8()
		if text.to_utf8_buffer() != chunk:
			return _not_utf8(line_number + 1)
		var single_byte := text.length() == chunk.size()
		var normalized := text
		if chunk.has(9):
			normalized = normalized.replace("\t", " ")
		if chunk.has(13):
			normalized = normalized.replace("\r", " ")
		var proven := proof.search(normalized) != null
		var lines := normalized.split("\n")
		for index in lines.size():
			var line := lines[index]
			line_number += 1
			if line.is_empty():
				continue
			var length := line.length()
			if length > max_line or (not single_byte and length * 4 > max_line
					and line.to_utf8_buffer().size() > max_line):
				return _line_limit(line_number)
			var tokens := line.split(" ", false)
			var token_count := tokens.size()
			var at := 0
			while at < token_count:
				var token := tokens[at]
				at += 1
				if state == _S_NUMBER:
					var value := 0.0
					if proven:
						# In a proven chunk a token is a lower-case word or a safe number.
						if token >= "a":
							return _unexpected(state, line_number, token)
						value = token.to_float()
					else:
						value = _parse_number(token, strict, safe)
						if is_nan(value):
							return _unexpected(state, line_number, token)
					facet[filled] = value
					filled += 1
					if filled == 3:
						state = _S_OUTER
					elif filled == 12:
						state = _S_ENDLOOP
					elif filled % 3 == 0:
						state = _S_VERTEX
				elif state == _S_VERTEX:
					if token != "vertex":
						return _unexpected(state, line_number, token)
					state = _S_NUMBER
				elif state == _S_FACET:
					if token == "facet":
						if facets == Limits.TRIANGLES:
							return _facet_limit()
						facets += 1
						filled = 0
						state = _S_NORMAL
					elif token == "endsolid":
						# The rest of the line is free text.
						state = _S_SOLID
						break
					else:
						return _unexpected(state, line_number, token)
				elif state == _S_ENDFACET:
					if token != "endfacet":
						return _unexpected(state, line_number, token)
					var status := geometry.add(facet[0], facet[1], facet[2], facet[3], facet[4], facet[5],
						facet[6], facet[7], facet[8], facet[9], facet[10], facet[11])
					if status > _Geometry.DROPPED:
						return _facet_failure(status, facets, line_number)
					state = _S_FACET
				elif state == _S_SOLID:
					# Reached only at the start of a line: `endsolid` consumes the rest of its line.
					if token != "solid":
						return _unexpected(state, line_number, token, solids)
					if solids == Limits.STL_ASCII_SOLIDS:
						return R.fail(R.SOURCE_LIMIT, "The STL text has more than %s solids.", "", _STEP,
							[str(Limits.STL_ASCII_SOLIDS)])
					solids += 1
					if solids == 1:
						# The name keeps its own tabs; `solid` is the first token of the raw line too.
						name = text.split("\n")[index].strip_edges().substr(5).strip_edges()
					state = _S_FACET
					break
				else:
					if token != _KEYWORDS[state]:
						return _unexpected(state, line_number, token)
					state = _S_NUMBER if state == _S_NORMAL else state + 1
	if state != _S_SOLID:
		return R.fail(R.SOURCE_INVALID, "The STL text ends at line %s inside an unfinished solid. "
			+ "It looks truncated; export it again.", "", _STEP, [str(line_number)])
	return geometry.finish(FORMAT_ASCII, name, 0)


## Value of one number token, NAN when it breaks the grammar. May return INF: the caller rejects
## non-finite coordinates.
static func _parse_number(token: String, strict: RegEx, safe: RegEx) -> float:
	if safe.search(token) != null:
		return token.to_float()
	if strict.search(token) == null:
		return NAN
	return _convert_long_number(token)


## Converts a grammar-valid token the engine would truncate or warn about. Keeps 18 significant
## digits; a magnitude outside the float32 range saturates to INF or zero.
static func _convert_long_number(token: String) -> float:
	var negative := token.begins_with("-")
	var body := token.substr(1) if negative or token.begins_with("+") else token
	var exponent := 0
	var exponent_at := body.find("e")
	if exponent_at < 0:
		exponent_at = body.find("E")
	if exponent_at >= 0:
		var exponent_text := body.substr(exponent_at + 1)
		body = body.substr(0, exponent_at)
		var exponent_negative := exponent_text.begins_with("-")
		exponent_text = exponent_text.lstrip("+-").lstrip("0")
		if exponent_text.length() > 6:
			exponent = 9999999
		elif not exponent_text.is_empty():
			exponent = exponent_text.to_int()
		if exponent_negative:
			exponent = -exponent
	var point := body.find(".")
	if point >= 0:
		exponent -= body.length() - point - 1
		body = body.substr(0, point) + body.substr(point + 1)
	var digits := body.lstrip("0")
	if digits.is_empty():
		return 0.0
	if digits.length() > 18:
		exponent += digits.length() - 18
		digits = digits.substr(0, 18)
	# The value lies in [10^(magnitude - 1), 10^magnitude); float32 spans about 1e-45 to 3.4e38.
	var magnitude := exponent + digits.length()
	var value := 0.0
	if magnitude > 60:
		value = INF
	elif magnitude >= -60:
		value = ("%se%d" % [digits, exponent]).to_float()
	return -value if negative else value


static func _starts_with_solid(bytes: PackedByteArray) -> bool:
	var size := bytes.size()
	var at := 0
	while at < size and (bytes[at] == 32 or bytes[at] == 9 or bytes[at] == 13 or bytes[at] == 10):
		at += 1
	# "solid"
	return at + 5 <= size and bytes[at] == 115 and bytes[at + 1] == 111 and bytes[at + 2] == 108 \
			and bytes[at + 3] == 105 and bytes[at + 4] == 100


## Quiet UTF-8 check. Pure ASCII, the usual case, is settled eight bytes at a time.
static func _is_utf8(chunk: PackedByteArray) -> bool:
	var size := chunk.size()
	var aligned := size & ~7
	var at := aligned
	if aligned > 0:
		for word: int in chunk.slice(0, aligned).to_int64_array():
			if word & _HIGH_BITS:
				at = 0
				break
	while at < size:
		var lead := chunk[at]
		if lead < 0x80:
			at += 1
			continue
		# Shortest form only, no surrogates, nothing above U+10FFFF.
		var extra := 2
		var low := 0x80
		var high := 0xBF
		if lead >= 0xC2 and lead <= 0xDF:
			extra = 1
		elif lead == 0xE0:
			low = 0xA0
		elif lead == 0xED:
			high = 0x9F
		elif lead >= 0xE1 and lead <= 0xEF:
			pass
		elif lead == 0xF0:
			extra = 3
			low = 0x90
		elif lead >= 0xF1 and lead <= 0xF3:
			extra = 3
		elif lead == 0xF4:
			extra = 3
			high = 0x8F
		else:
			return false
		if at + extra >= size or chunk[at + 1] < low or chunk[at + 1] > high:
			return false
		for step in range(2, extra + 1):
			if chunk[at + step] < 0x80 or chunk[at + step] > 0xBF:
				return false
		at += extra + 1
	return true


## `closed_solids` is the number of solids already closed when `state` is `_S_SOLID`.
static func _unexpected(state: int, line: int, token: String, closed_solids := 0) -> Dictionary:
	var shown := token if token.length() <= 40 else token.substr(0, 40) + "..."
	var arguments := [str(line), shown]
	if state == _S_NUMBER:
		return R.fail(R.SOURCE_INVALID, "Line %s of the STL text: \"%s\" is not a plain decimal number.",
			"", _STEP, arguments)
	if state == _S_FACET:
		return R.fail(R.SOURCE_INVALID, "Line %s of the STL text: \"%s\" found where \"facet\" or \"endsolid\" "
			+ "is required.", "", _STEP, arguments)
	if closed_solids > 0:
		return R.fail(R.SOURCE_INVALID, "Line %s of the STL text: unexpected \"%s\" after the end of the solid.",
			"", _STEP, arguments)
	arguments.append(_KEYWORDS[state])
	return R.fail(R.SOURCE_INVALID, "Line %s of the STL text: \"%s\" found where \"%s\" is required.",
		"", _STEP, arguments)


static func _not_utf8(line: int) -> Dictionary:
	return R.fail(R.SOURCE_INVALID, "The STL text is not valid UTF-8 at or after line %s.", "", _STEP, [str(line)])


static func _line_limit(line: int) -> Dictionary:
	return R.fail(R.SOURCE_LIMIT, "Line %s of the STL text is longer than %s bytes.", "", _STEP,
		[str(line), str(Limits.STL_ASCII_LINE_BYTES)])


static func _facet_limit() -> Dictionary:
	return R.fail(R.SOURCE_LIMIT, "The STL file has more than %s facets. Simplify the model and export it again.",
		"", _STEP, [str(Limits.TRIANGLES)])


## `line` is the ASCII line of the closing `endfacet`, or 0 for a binary file.
static func _facet_failure(status: int, facet_number: int, line: int) -> Dictionary:
	var place := "Facet %s of the STL file" if line == 0 else "Facet %s of the STL file (ending at line %s)"
	var arguments := [str(facet_number)] if line == 0 else [str(facet_number), str(line)]
	if status == _Geometry.NON_FINITE:
		return R.fail(R.SOURCE_INVALID, place + " has a value that is not a finite 32-bit number.",
			"", _STEP, arguments)
	return R.fail(R.SOURCE_INVALID, place + " is too large to process. Rescale the model to sensible units "
		+ "and export it again.", "", _STEP, arguments)


## Accumulates kept triangles, bounds and counters for one read.
class _Geometry extends RefCounted:
	const KEPT := 0
	const DROPPED := 1
	const NON_FINITE := 2
	const OVERFLOW := 3
	const _GROWTH_FLOATS := 9 * 4096

	var positions := PackedFloat32Array()
	var kept := 0
	var dropped := 0
	var inconsistent := 0
	var min_x := INF
	var min_y := INF
	var min_z := INF
	var max_x := -INF
	var max_y := -INF
	var max_z := -INF

	## Takes float32-valued numbers: the supplied normal, then three vertices.
	func add(n0: float, n1: float, n2: float, x0: float, y0: float, z0: float,
			x1: float, y1: float, z1: float, x2: float, y2: float, z2: float) -> int:
		# Finite float32 terms cannot overflow a float64 sum; any INF or NAN makes it non-finite.
		if not is_finite(n0 + n1 + n2 + x0 + y0 + z0 + x1 + y1 + z1 + x2 + y2 + z2):
			return NON_FINITE
		var ax := x1 - x0
		var ay := y1 - y0
		var az := z1 - z0
		var bx := x2 - x0
		var by := y2 - y0
		var bz := z2 - z0
		var cx := ay * bz - az * by
		var cy := az * bx - ax * bz
		var cz := ax * by - ay * bx
		if cx == 0.0 and cy == 0.0 and cz == 0.0:
			dropped += 1
			return DROPPED
		# Unreachable for finite float32 input in float64; kept as the stated guard.
		if not is_finite(cx + cy + cz):
			return OVERFLOW
		if n0 * cx + n1 * cy + n2 * cz < 0.0:
			inconsistent += 1
		var write := kept * 9
		if write + 9 > positions.size():
			positions.resize(mini(maxi(positions.size() * 2, _GROWTH_FLOATS), Limits.TRIANGLES * 9))
		positions[write] = x0
		positions[write + 1] = y0
		positions[write + 2] = z0
		positions[write + 3] = x1
		positions[write + 4] = y1
		positions[write + 5] = z1
		positions[write + 6] = x2
		positions[write + 7] = y2
		positions[write + 8] = z2
		kept += 1
		min_x = minf(min_x, minf(x0, minf(x1, x2)))
		min_y = minf(min_y, minf(y0, minf(y1, y2)))
		min_z = minf(min_z, minf(z0, minf(z1, z2)))
		max_x = maxf(max_x, maxf(x0, maxf(x1, x2)))
		max_y = maxf(max_y, maxf(y0, maxf(y1, y2)))
		max_z = maxf(max_z, maxf(z0, maxf(z1, z2)))
		return KEPT

	func finish(format: String, name: String, attributes: int) -> Dictionary:
		if kept == 0:
			if dropped > 0:
				return R.fail(R.SOURCE_INVALID, "The STL file has no usable facet: all %s have zero area.", "", _STEP,
					[str(dropped)])
			return R.fail(R.SOURCE_INVALID, "The STL file contains no facets.", "", _STEP)
		positions.resize(kept * 9)
		var diagnostics: Array = []
		if dropped > 0:
			diagnostics.append(R.diagnostic(R.SOURCE_INVALID, "%s zero-area facets were left out.", "", _STEP,
				[str(dropped)], R.SEVERITY_WARNING))
		if inconsistent > 0:
			diagnostics.append(R.diagnostic(R.SOURCE_INVALID, "%s facets have a stored normal that points "
				+ "against their vertex order. The vertex order was kept.", "", _STEP,
				[str(inconsistent)], R.SEVERITY_WARNING))
		if attributes > 0:
			diagnostics.append(R.diagnostic(R.SOURCE_UNSUPPORTED, "%s facets carry attribute data, which was "
				+ "ignored. STL colour is not supported.", "", _STEP, [str(attributes)], R.SEVERITY_INFO))
		return R.ok({
			format = format,
			name = name,
			triangle_count = kept,
			positions = positions,
			bounds_min = PackedFloat64Array([min_x, min_y, min_z]),
			bounds_max = PackedFloat64Array([max_x, max_y, max_z]),
			dropped_degenerate = dropped,
			inconsistent_normals = inconsistent,
			nonzero_attributes = attributes,
		}, diagnostics)
