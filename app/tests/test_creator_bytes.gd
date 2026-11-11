extends SceneTree
## AC-01: exact-byte record identity and lexical integer tokens.
const CreatorBytes := preload("res://workshop/creator/bytes.gd")
const R := preload("res://workshop/creator/result.gd")

var failures := 0


func _initialize() -> void:
	check("sha256 known answer", CreatorBytes.sha256("abc".to_utf8_buffer())
		== "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	check("sha256 shape", CreatorBytes.is_sha256(CreatorBytes.sha256(PackedByteArray())))
	check("sha256 rejects upper case", not CreatorBytes.is_sha256("BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD"))

	var record := {format = "openrc-test v1", revision = 3, name = "Ñandú 雪", zero = -0.0,
		third = 1.0 / 3.0, items = [{count = 2, mass = 0.25}, {count = 0, mass = 1e-7}], flag = true, none = null}
	var written: Dictionary = CreatorBytes.encode(record)
	check("encode ok", written.ok)
	var bytes: PackedByteArray = written.value.bytes
	var text := bytes.get_string_from_utf8()
	check("one final LF", text.ends_with("\n") and not text.ends_with("\n\n"))
	check("no BOM", bytes[0] == 0x7B)
	check("sorted keys", text.find("\"flag\"") < text.find("\"format\"") and text.find("\"format\"") < text.find("\"items\""))
	check("negative zero normalized", text.contains("\"zero\":0.0") and not text.contains("-0.0"))
	check("hash is over exact bytes", written.value.sha256 == CreatorBytes.sha256(bytes))
	check("same record, same bytes", CreatorBytes.encode(record).value.bytes == bytes)

	var paths := PackedStringArray(["revision", "items/*/count"])
	var read: Dictionary = CreatorBytes.decode(bytes, paths)
	check("decode ok", read.ok)
	check("decode keeps hash", read.ok and read.value.sha256 == written.value.sha256)
	if read.ok:
		var data: Dictionary = read.value.data
		check("integer path is int", typeof(data.revision) == TYPE_INT and data.revision == 3)
		check("nested integer path", typeof(data.items[1].count) == TYPE_INT and data.items[0].count == 2)
		check("float survives exactly", data.third == 1.0 / 3.0 and data.items[1].mass == 1e-7)
		check("unicode preserved", data.name == "Ñandú 雪")
		check("round trip is byte identical", CreatorBytes.encode(data).value.bytes == bytes)

	for bad: String in ['{"revision":1.0}', '{"revision":1e0}', '{"revision":-1}', '{"revision":01}',
			'{"revision":9007199254740992}', '{"revision":0.5}', '{"revision":"1"}' ]:
		var refused: Dictionary = CreatorBytes.decode(bad.to_utf8_buffer(), PackedStringArray(["revision"]))
		check("integer token refused " + bad, not refused.ok or typeof(refused.value.data.revision) != TYPE_INT)
	check("largest exact integer accepted", CreatorBytes.decode('{"revision":9007199254740991}'.to_utf8_buffer(),
		PackedStringArray(["revision"])).ok)
	check("zero accepted", CreatorBytes.decode('{"revision":0}'.to_utf8_buffer(), PackedStringArray(["revision"])).ok)
	check("map wildcard", not CreatorBytes.decode('{"entities":{"a":{"generation":1.5}}}'.to_utf8_buffer(),
		PackedStringArray(["entities/*/generation"])).ok)
	check("undeclared numbers stay floats", CreatorBytes.decode('{"mass":1}'.to_utf8_buffer()).value.data.mass == 1.0)

	check("duplicate key refused", not CreatorBytes.decode('{"a":1,"a":2}'.to_utf8_buffer()).ok)
	check("BOM refused", not CreatorBytes.decode(PackedByteArray([0xEF, 0xBB, 0xBF, 0x7B, 0x7D])).ok)
	check("array root refused", not CreatorBytes.decode("[]".to_utf8_buffer()).ok)
	check("byte cap", not CreatorBytes.decode('{"a":1}'.to_utf8_buffer(), PackedStringArray(), 3).ok)

	# Quiet pre-scan: stored records are user-editable, so hostile bytes are refused before an engine
	# decoder can log (the checked runner fails this test on any engine error or warning line).
	check("empty refused", not CreatorBytes.decode(PackedByteArray()).ok)
	for hostile: String in ['{"a":1e999}', '{"a":-1E+999}', '{"a":1e-999}', '{"a":1e400}', '{"a":[0.5,2e0000000000401]}',
			'{"a":1' + "0".repeat(64) + '}', '{"a":0.' + "0".repeat(70) + '1}']:
		check("number refused " + hostile.left(24), not CreatorBytes.decode(hostile.to_utf8_buffer()).ok)
	var extremes: Dictionary = CreatorBytes.decode('{"a":-1.7976931348623157e+308,"b":5e-324,"c":1e-07}'.to_utf8_buffer())
	check("writer extremes accepted", extremes.ok and extremes.value.data.a == -1.7976931348623157e+308
		and extremes.value.data.c == 1e-7)
	var quoted: Dictionary = CreatorBytes.decode(('{"a":"1e999 ' + "9".repeat(80) + ' \\" 2e999"}').to_utf8_buffer())
	check("number-like text inside a string kept", quoted.ok and str(quoted.value.data.a).begins_with("1e999 9"))
	var wide: Dictionary = CreatorBytes.decode('{"a":"Ñandú 雪 😀"}'.to_utf8_buffer())
	check("multi-byte text accepted", wide.ok and wide.value.data.a == "Ñandú 雪 😀")
	var malformed := {
		"stray continuation": [0x80], "truncated sequence": [0xC3], "bad continuation": [0xC3, 0x28],
		"overlong": [0xC0, 0x80], "overlong three bytes": [0xE0, 0x80, 0x80], "surrogate": [0xED, 0xA0, 0x80],
		"beyond U+10FFFF": [0xF4, 0x90, 0x80, 0x80], "invalid lead": [0xFF], "raw control": [0x01], "NUL": [0x00],
		"raw line feed in text": [0x0A],
	}
	for label: String in malformed:
		var fixture := '{"a":"'.to_utf8_buffer()
		fixture.append_array(PackedByteArray(malformed[label]))
		fixture.append_array('"}'.to_utf8_buffer())
		check("text refused: " + label, not CreatorBytes.decode(fixture).ok)
	var cut := '{"a":"x'.to_utf8_buffer()
	cut.append(0xE9)
	check("text refused: sequence cut at the end", not CreatorBytes.decode(cut).ok)
	check("pre-scan passes writer output", CreatorBytes.text_problem(bytes).is_empty())

	check("NaN refused", not CreatorBytes.encode({x = NAN}).ok)
	check("infinity refused", not CreatorBytes.encode({x = [1.0, INF]}).ok)
	check("unsafe integer refused", not CreatorBytes.encode({x = 9007199254740992}).ok)
	check("packed array refused", not CreatorBytes.encode({x = PackedFloat64Array([1.0])}).ok)
	check("non-text key refused", not CreatorBytes.encode({1: "x"}).ok)
	check("object value refused", not CreatorBytes.encode({x = RefCounted.new()}).ok)
	check("size cap", not CreatorBytes.encode({x = "0123456789"}, 8).ok)

	var failure: Dictionary = R.fail(R.FIELD_INVALID, "Wing span must be between %s and %s m.", "wing/span", "aircraft_layout", ["0.3", "4"])
	check("failure has no value", not failure.ok and not failure.has("value"))
	check("diagnostic text", R.texts(failure)[0] == "FIELD_INVALID: Wing span must be between 0.3 and 4 m.")
	check("warnings do not block", not R.has_errors([R.diagnostic(R.SOURCE_INVALID, "note", "", "", [], R.SEVERITY_WARNING)]))

	print("Creator bytes: %d failures" % failures)
	quit(1 if failures else 0)


func check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
