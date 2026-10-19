extends RefCounted
## Bounded RFC 8259 grammar guard before Godot's deliberately permissive JSON decoder.
## External data never becomes a Resource, script, object or filesystem path here.

static func parse(bytes: PackedByteArray, max_bytes := 1048576, max_depth := 32, max_nodes := 20000) -> Dictionary:
	if bytes.is_empty() or bytes.size() > max_bytes:
		return {ok = false, errors = ["JSON is empty or exceeds its byte limit."]}
	var source := bytes.get_string_from_utf8()
	if source.to_utf8_buffer() != bytes:
		return {ok = false, errors = ["JSON must be valid UTF-8."]}
	var scan := Grammar.new(source, max_depth, max_nodes)
	scan.value(0)
	scan.whitespace()
	if scan.error.is_empty() and scan.offset != source.length(): scan.fail("Unexpected trailing data")
	if not scan.error.is_empty(): return {ok = false, errors = [scan.error]}
	var decoder := JSON.new()
	if decoder.parse(source) != OK: return {ok = false, errors = ["JSON decoding failed."]}
	return {ok = true, errors = [], data = decoder.data}


class Grammar extends RefCounted:
	var source: String
	var offset := 0
	var error := ""
	var depth_limit: int
	var node_limit: int
	var nodes := 0
	func _init(text: String, depth: int, count: int) -> void:
		source = text
		depth_limit = depth
		node_limit = count
	func fail(reason: String) -> void:
		if error.is_empty(): error = "%s at character %d." % [reason, offset]
	func peek() -> String:
		return source.substr(offset, 1)
	func whitespace() -> void:
		while offset < source.length() and peek() in [" ", "\t", "\r", "\n"]: offset += 1
	func consume(token: String) -> bool:
		whitespace()
		if source.substr(offset, token.length()) != token: return false
		offset += token.length()
		return true
	func value(depth: int) -> void:
		if not error.is_empty(): return
		nodes += 1
		if depth > depth_limit or nodes > node_limit:
			fail("JSON nesting or node limit exceeded")
			return
		whitespace()
		match peek():
			"{": object(depth)
			"[": array(depth)
			"\"": string_token()
			"t":
				if not consume("true"): fail("Invalid literal")
			"f":
				if not consume("false"): fail("Invalid literal")
			"n":
				if not consume("null"): fail("Invalid literal")
			_: number()
	func object(depth: int) -> void:
		offset += 1
		var keys := {}
		if consume("}"): return
		while error.is_empty():
			whitespace()
			if peek() != "\"":
				fail("Expected object key")
				return
			var key := string_token()
			if keys.has(key): fail("Duplicate object key")
			keys[key] = true
			if not consume(":"): fail("Expected colon")
			value(depth + 1)
			if consume("}"): return
			if not consume(","): fail("Expected comma or object end")
	func array(depth: int) -> void:
		offset += 1
		if consume("]"): return
		while error.is_empty():
			value(depth + 1)
			if consume("]"): return
			if not consume(","): fail("Expected comma or array end")
	func string_token() -> String:
		var begin := offset
		offset += 1
		while offset < source.length() and error.is_empty():
			var code := source.unicode_at(offset)
			offset += 1
			if code == 34: return str(JSON.parse_string(source.substr(begin, offset - begin)))
			if code < 32:
				fail("Unescaped control character")
				return ""
			if code != 92: continue
			var escape := peek()
			offset += 1
			if escape in ["\"", "\\", "/", "b", "f", "n", "r", "t"]: continue
			if escape != "u":
				fail("Invalid string escape")
				return ""
			var first := hex4()
			if first >= 0xD800 and first <= 0xDBFF:
				if source.substr(offset, 2) != "\\u":
					fail("Unpaired high surrogate")
					return ""
				offset += 2
				var second := hex4()
				if second < 0xDC00 or second > 0xDFFF: fail("Invalid surrogate pair")
			elif first >= 0xDC00 and first <= 0xDFFF: fail("Unpaired low surrogate")
		fail("Unterminated string")
		return ""
	func hex4() -> int:
		var token := source.substr(offset, 4)
		if token.length() != 4:
			fail("Incomplete Unicode escape")
			return -1
		for character in token:
			if character not in "0123456789abcdefABCDEF":
				fail("Invalid Unicode escape")
				return -1
		offset += 4
		return token.hex_to_int()
	func digit() -> bool:
		return offset < source.length() and peek() in "0123456789"
	func number() -> void:
		var begin := offset
		if peek() == "-": offset += 1
		if peek() == "0": offset += 1
		elif offset < source.length() and peek() in "123456789":
			while digit(): offset += 1
		else:
			fail("Expected JSON value")
			return
		if peek() == ".":
			offset += 1
			if not digit(): fail("Expected fractional digit")
			while digit(): offset += 1
		if peek() in ["e", "E"]:
			offset += 1
			if peek() in ["+", "-"]: offset += 1
			if not digit(): fail("Expected exponent digit")
			while digit(): offset += 1
		if not is_finite(source.substr(begin, offset - begin).to_float()): fail("Non-finite number")
