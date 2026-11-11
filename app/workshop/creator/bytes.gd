extends RefCounted
## Exact-byte identity for new Aircraft Creator records (AC-01).
##
## Writer policy `openrc-json-bytes-v1`: the pinned engine's sorted-key, full-precision JSON,
## valid UTF-8, no BOM, one final LF. A record is serialized once; its SHA-256 is taken over those
## exact bytes and the same bytes are parsed back through `decode`. Hash checks never reserialize.
## Equivalent JSON with other whitespace or number spelling is a different identity on purpose:
## no cross-producer canonical form is claimed. Existing Store and Trial v1 identities are untouched.

const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const StrictJSON := preload("res://workshop/strict_json.gd")

const WRITER_ID := "openrc-json-bytes-v1"
const _DIGITS := "0123456789"
const _MAX_SAFE_TEXT := "9007199254740991"
## Longest number token and largest exponent the quiet pre-scan lets through to the decoders.
const _NUMBER_CHARACTERS := 64
const _NUMBER_EXPONENT := 400


static func sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	# The engine refuses an empty update; the digest of no input is still well defined.
	if not bytes.is_empty() and hashing.update(bytes) != OK:
		return ""
	return hashing.finish().hex_encode()


static func is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or (value as String).length() != 64:
		return false
	for character: String in (value as String):
		if character not in "0123456789abcdef":
			return false
	return true


## Serializes a record once. Returns `{ok, value = {bytes, sha256}}`.
## Accepts only null, bool, int within +-(2^53 - 1), finite float, String, Array and Dictionary
## with String keys. Negative zero becomes positive zero. Anything else is refused, never coerced.
static func encode(record: Dictionary, max_bytes := Limits.RECORD_BYTES) -> Dictionary:
	var problems := PackedStringArray()
	var normalized: Variant = _normalize(record, "", problems, 0)
	if not problems.is_empty():
		return R.fail(R.RECORD_INVALID, "The record cannot be written: %s", "", "", [problems[0]])
	var bytes: PackedByteArray = (JSON.stringify(normalized, "", true, true) + "\n").to_utf8_buffer()
	if bytes.size() > max_bytes:
		return R.fail(R.SOURCE_LIMIT, "The record exceeds its size limit.")
	return R.ok({bytes = bytes, sha256 = sha256(bytes)})


## Strictly parses exact record bytes. `integer_paths` lists the paths whose value must be a
## plain decimal integer token in [0, 2^53 - 1]: no sign, fraction, exponent or leading zero.
## Path segments are joined with "/"; an array element or a dynamic object key is "*".
## Returns `{ok, value = {data, sha256}}`; `data` holds those fields as int.
static func decode(bytes: PackedByteArray, integer_paths: PackedStringArray = PackedStringArray(),
		max_bytes := Limits.RECORD_BYTES) -> Dictionary:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		return R.fail(R.RECORD_INVALID, "The record starts with a byte-order mark.")
	# Stored records are user-editable files: refuse here what would make an engine decoder log.
	if bytes.is_empty() or bytes.size() > max_bytes:
		return R.fail(R.RECORD_INVALID, "The record is not valid JSON: %s", "", "", ["it is empty or exceeds its size limit"])
	var problem := text_problem(bytes)
	if not problem.is_empty():
		return R.fail(R.RECORD_INVALID, "The record is not valid JSON: %s", "", "", [problem])
	var parsed: Dictionary = StrictJSON.parse(bytes, max_bytes, Limits.JSON_DEPTH, Limits.JSON_VALUES)
	if not parsed.ok:
		return R.fail(R.RECORD_INVALID, "The record is not valid JSON: %s", "", "", [str(parsed.errors[0])])
	if typeof(parsed.data) != TYPE_DICTIONARY:
		return R.fail(R.RECORD_INVALID, "The record must be a JSON object.")
	var wanted := {}
	for path: String in integer_paths:
		wanted[path] = true
	var walker := TokenWalker.new(bytes.get_string_from_utf8(), wanted)
	var data: Variant = walker.value("")
	if not walker.error.is_empty():
		return R.fail(R.RECORD_INVALID, "The record has an invalid number: %s", "", "", [walker.error])
	return R.ok({data = data, sha256 = sha256(bytes)})


## One pass over record bytes before any engine text or number decoder sees them, so a hostile
## file cannot fill the log. Returns "" or the reason: malformed UTF-8, a raw control character
## (JSON allows only tab, LF and CR between tokens), or a number token the engine's float parser
## warns about. The writer never emits such a token: a full-precision double needs 25 characters
## and an exponent within 308. Same rule as the GLB preflight.
static func text_problem(bytes: PackedByteArray) -> String:
	var pending := 0
	var low := 0x80
	var high := 0xBF
	var in_string := false
	var escaped := false
	var token := 0
	var exponent := -1
	for byte: int in bytes:
		if pending > 0:
			if byte < low or byte > high:
				return "it is not valid UTF-8 text"
			low = 0x80
			high = 0xBF
			pending -= 1
		elif byte >= 0x80:
			if byte >= 0xC2 and byte <= 0xDF:
				pending = 1
			elif byte >= 0xE0 and byte <= 0xEF:
				pending = 2
				if byte == 0xE0:
					low = 0xA0
				elif byte == 0xED:
					high = 0x9F
			elif byte >= 0xF0 and byte <= 0xF4:
				pending = 3
				if byte == 0xF0:
					low = 0x90
				elif byte == 0xF4:
					high = 0x8F
			else:
				return "it is not valid UTF-8 text"
		elif byte < 0x20 and byte != 0x09 and byte != 0x0A and byte != 0x0D:
			return "it holds a control character"
		elif in_string:
			if escaped:
				escaped = false
			elif byte == 0x5C:
				escaped = true
			elif byte == 0x22:
				in_string = false
		elif byte >= 0x30 and byte <= 0x39:
			token += 1
			if exponent >= 0:
				exponent = exponent * 10 + byte - 0x30
			if token > _NUMBER_CHARACTERS or exponent > _NUMBER_EXPONENT:
				return "it holds a number that is out of range"
		elif byte == 0x65 or byte == 0x45:
			token += 1
			exponent = 0
		elif byte == 0x2B or byte == 0x2D or byte == 0x2E:
			token += 1
		else:
			in_string = byte == 0x22
			token = 0
			exponent = -1
	return "it is not valid UTF-8 text" if pending != 0 else ""


static func _normalize(node: Variant, path: String, problems: PackedStringArray, depth: int) -> Variant:
	if depth > Limits.JSON_DEPTH:
		problems.append("%s is nested too deeply" % path)
		return null
	match typeof(node):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return node
		TYPE_STRING_NAME:
			return str(node)
		TYPE_INT:
			if absi(node) > Limits.MAX_SAFE_INTEGER:
				problems.append("%s is outside the exact integer range" % path)
			return node
		TYPE_FLOAT:
			if not is_finite(node):
				problems.append("%s is not finite" % path)
				return 0.0
			return 0.0 if node == 0.0 else node
		TYPE_ARRAY:
			var items := []
			for index: int in (node as Array).size():
				items.append(_normalize(node[index], "%s/%d" % [path, index], problems, depth + 1))
			return items
		TYPE_DICTIONARY:
			var fields := {}
			for key: Variant in (node as Dictionary):
				# GDScript `{name = value}` literals carry StringName keys; both spell the same JSON key.
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					problems.append("%s has a key that is not text" % path)
					continue
				fields[str(key)] = _normalize(node[key], "%s/%s" % [path, key], problems, depth + 1)
			return fields
	problems.append("%s has an unsupported value type" % path)
	return null


## Rebuilds the decoded tree from grammar-valid text while checking integer tokens lexically,
## before any numeric conversion can round a fraction or an out-of-range value into place.
class TokenWalker extends RefCounted:
	var source: String
	var offset := 0
	var error := ""
	var integer_paths: Dictionary

	func _init(text: String, wanted: Dictionary) -> void:
		source = text
		integer_paths = wanted

	func _skip() -> void:
		while offset < source.length() and source[offset] in [" ", "\t", "\r", "\n"]:
			offset += 1

	func value(path: String) -> Variant:
		_skip()
		if offset >= source.length():
			return null
		match source[offset]:
			"{":
				return _object(path)
			"[":
				return _array(path)
			"\"":
				return _string()
			"t":
				offset += 4
				return true
			"f":
				offset += 5
				return false
			"n":
				offset += 4
				return null
		return _number(path)

	func _object(path: String) -> Dictionary:
		var fields := {}
		offset += 1
		_skip()
		if source[offset] == "}":
			offset += 1
			return fields
		while offset < source.length() and error.is_empty():
			_skip()
			var key := _string()
			_skip()
			offset += 1  # colon
			var exact := key if path.is_empty() else path + "/" + key
			var wild := "*" if path.is_empty() else path + "/*"
			fields[key] = value(exact if _descends(exact) else wild)
			_skip()
			var closing := source[offset]
			offset += 1
			if closing == "}":
				break
		return fields

	func _array(path: String) -> Array:
		var items := []
		offset += 1
		_skip()
		if source[offset] == "]":
			offset += 1
			return items
		var element := "*" if path.is_empty() else path + "/*"
		while offset < source.length() and error.is_empty():
			items.append(value(element))
			_skip()
			var closing := source[offset]
			offset += 1
			if closing == "]":
				break
		return items

	## True when a declared path equals `prefix` or continues below it.
	func _descends(prefix: String) -> bool:
		if integer_paths.has(prefix):
			return true
		var below := prefix + "/"
		for path: String in integer_paths:
			if path.begins_with(below):
				return true
		return false

	func _string() -> String:
		var begin := offset
		offset += 1
		while offset < source.length():
			var code := source.unicode_at(offset)
			offset += 1
			if code == 92:
				offset += 1
			elif code == 34:
				break
		return str(JSON.parse_string(source.substr(begin, offset - begin)))

	func _number(path: String) -> Variant:
		var begin := offset
		while offset < source.length() and source[offset] in "+-0123456789.eE":
			offset += 1
		var token := source.substr(begin, offset - begin)
		if not integer_paths.has(path):
			return token.to_float()
		for character: String in token:
			if character not in _DIGITS:
				error = "%s must be a whole number without sign, fraction or exponent" % path
				return 0
		if token.length() > 1 and token[0] == "0":
			error = "%s has a leading zero" % path
			return 0
		if token.length() > _MAX_SAFE_TEXT.length() \
				or (token.length() == _MAX_SAFE_TEXT.length() and token > _MAX_SAFE_TEXT):
			error = "%s is outside the exact integer range" % path
			return 0
		return token.to_int()
