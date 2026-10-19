extends SceneTree
const Strict := preload("res://workshop/strict_json.gd")
var failures := 0
func _initialize() -> void:
	for valid: String in ['{}', '[]', '{"a":[true,false,null,-1.25e+2,"\\uD834\\uDD1E"]}', '{"á":"雪"}']:
		check("valid " + valid, Strict.parse(valid.to_utf8_buffer()).ok)
	for invalid: String in ['{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '[1,]', '{"a":1,}', '01', '+1', '.1', '1.', '1e', '1e999', 'NaN', 'true false', '"bad\nline"', '"\\x22"', '"\\uD800"', '"\\uDC00"', '{/*x*/}', '[', '{']:
		check("reject " + invalid, not Strict.parse(invalid.to_utf8_buffer()).ok)
	check("byte cap", not Strict.parse('{}'.to_utf8_buffer(), 1).ok)
	check("depth cap", not Strict.parse('[[[0]]]'.to_utf8_buffer(), 100, 2).ok)
	check("node cap", not Strict.parse('[1,2,3]'.to_utf8_buffer(), 100, 10, 3).ok)
	check("bad UTF8", not Strict.parse(PackedByteArray([34,255,34])).ok)
	print("Workshop strict JSON: %d failures" % failures)
	quit(1 if failures else 0)
func check(label: String, passed: bool) -> void:
	if not passed:
		failures += 1
		printerr("FAIL: " + label)
