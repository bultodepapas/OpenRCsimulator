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

	# Bit-exact floats: the engine's text-to-float conversion alone reads some tokens one unit in
	# the last place off, which would change a record that is decoded and written again.
	var seed_state := 20261111
	var doubles: Array = [0.36497120000000005, 0.24924999999999997, 0.1, 2.0 / 3.0, 1e-7, 123456.789e3,
		4.35, 0.30000000000000004, 9007199254740993.0, 0.1 + 0.2, 1.0 / 3.0, 100.0 / 7.0]
	var scratch := PackedByteArray()
	scratch.resize(8)
	for _index: int in 4000:
		seed_state = (seed_state * 6364136223846793005 + 1442695040888963407)
		scratch.encode_s64(0, seed_state)
		var candidate := scratch.decode_double(0)
		if is_finite(candidate):
			doubles.append(candidate)
			doubles.append(float(seed_state % 1000003) / 977.0)
			doubles.append(float(seed_state % 100000007) / 9973.0 * pow(10.0, float((_index % 13) - 6)))
	var wide_record: Dictionary = CreatorBytes.encode({values = doubles})
	var reread: Dictionary = CreatorBytes.decode(wide_record.value.bytes) if wide_record.ok else {ok = false}
	check("many doubles encode and decode", wide_record.ok and reread.ok)
	if reread.ok:
		var inexact := 0
		for index: int in doubles.size():
			scratch.encode_double(0, doubles[index] if doubles[index] != 0.0 else 0.0)
			var wanted := scratch.decode_s64(0)
			scratch.encode_double(0, reread.value.data.values[index])
			if scratch.decode_s64(0) != wanted:
				inexact += 1
		check("every decoded float is bit-identical to the one written (%d of %d differ)" % [inexact, doubles.size()], inexact == 0)
		check("decoding and encoding again gives the same bytes", CreatorBytes.encode(reread.value.data).value.bytes == wide_record.value.bytes)
	# A source literal goes through the same engine conversion, so known tokens are checked by spelling.
	for token: String in ["0.36497120000000005", "-0.003381266352646314", "5.000786261358126e-295", "5e-324",
			"1.7976931348623157e+308", "-1.0641820432928002e-296", "0.1", "1e-07", "123456789.0"]:
		check("token reads as the double spelled " + token, JSON.stringify(CreatorBytes.exact_float(token), "", true, true) == token)
	check("a foreign spelling reads within one unit in the last place",
		absf(CreatorBytes.exact_float("3.6497120000000005e-1") - CreatorBytes.exact_float("0.36497120000000005")) < 1e-16
		and CreatorBytes.exact_float("0.50") == 0.5 and CreatorBytes.exact_float("-0e0") == 0.0 and CreatorBytes.exact_float("25E-1") == 2.5)
	check("text that is not a number does not loop", CreatorBytes.exact_float("abc") == 0.0 and CreatorBytes.exact_float("") == 0.0)

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

	# The writer never emits bytes its own reader refuses: the engine's JSON writer leaves some control
	# characters raw and spells U+000B as an escape JSON does not have.
	for code: int in 0x20:
		var sample := "a" + String.chr(code) + "b" if code != 0 else "ab"
		var control: Dictionary = CreatorBytes.encode({s = sample})
		var writable: bool = code in [0, 0x08, 0x09, 0x0A, 0x0C, 0x0D]
		check("control character U+%04X is %s" % [code, "written and read back" if writable else "refused when writing"],
			control.ok == writable and (not writable or (CreatorBytes.decode(control.value.bytes).ok
			and CreatorBytes.decode(control.value.bytes).value.data.s == sample)))
	check("a control character in a key is refused", not CreatorBytes.encode({"a" + String.chr(1): 1.0}).ok)
	check("DEL and other text survive", CreatorBytes.decode(CreatorBytes.encode({s = "x" + String.chr(0x7F) + "\u2028 y"}).value.bytes).ok)
	# A record made of numbers that need the exact search is refused, not searched for seconds.
	var slow_started := Time.get_ticks_msec()
	var many := PackedStringArray()
	for _index: int in 60000:
		many.append("2.225073858507201e-308")
	var flood: Dictionary = CreatorBytes.decode(('{"a":[' + ",".join(many) + "]}").to_utf8_buffer())
	check("a flood of slow number tokens is refused", not flood.ok)
	var few := PackedStringArray()
	for index: int in 2000:
		few.append(JSON.stringify(2.225073858507201e-308 * (1.0 + float(index) / 4096.0), "", true, true))
	var tiny: Dictionary = CreatorBytes.decode(('{"a":[' + ",".join(few) + "]}").to_utf8_buffer())
	check("a few thousand tiny numbers still decode exactly", tiny.ok
		and JSON.stringify(tiny.value.data.a[1999], "", true, true) == few[1999])
	var slow_ms := Time.get_ticks_msec() - slow_started
	check("the exact number path is bounded (%d ms)" % slow_ms, slow_ms < 4000)

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
