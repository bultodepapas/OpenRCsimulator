# Research probe only: JSON/ConfigFile round trips and native numeric controls.
# Run from repo root with --headless --path app --script <absolute path to this file>.
extends SceneTree

var checks: Array[Dictionary] = []
var signal_count := 0


func check(label: String, passed: bool, observed: Variant) -> void:
	checks.append({label = label, passed = passed, observed = observed})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var number := 1.2345678901234567
	var short_json := JSON.stringify({value = number})
	var precise_json := JSON.stringify({value = number}, "", true, true)
	check("float64 full_precision round trip", JSON.parse_string(precise_json).value == number, precise_json)
	check("default encoding loses digits for fixture", JSON.parse_string(short_json).value != number, short_json)
	var seed := "9007199254740993"
	var numeric: float = JSON.parse_string(seed)
	check("numeric JSON loses integer above 2^53", int(numeric) != int(seed), str(int(numeric)))
	check("string seed remains exact", JSON.parse_string(JSON.stringify(seed)) == seed, seed)
	var parser := JSON.new()
	check("parser permits trailing comma", parser.parse("{\"speed\":2,}") == OK, "domain validation still required")
	var cfg := ConfigFile.new()
	cfg.set_value("wind", "rng_state", 9223372036854775807)
	var restored := ConfigFile.new()
	var config_error := restored.parse(cfg.encode_to_text())
	var state: Variant = restored.get_value("wind", "rng_state", null)
	check("ConfigFile preserves signed int64 fixture", config_error == OK and typeof(state) == TYPE_INT and state == 9223372036854775807, str(state))
	var control := SpinBox.new()
	control.min_value = 0.0
	control.max_value = 12.0
	control.step = 0.1
	root.add_child(control)
	control.value_changed.connect(func(_v: float) -> void: signal_count += 1)
	control.value = 0.26
	check("setting value emits and snaps", signal_count == 1 and absf(control.value - 0.3) < 1e-12, {signals = signal_count, value = control.value})
	control.set_value_no_signal(0.37)
	check("silent setting still snaps", signal_count == 1 and absf(control.value - 0.4) < 1e-12, {signals = signal_count, value = control.value})
	control.get_line_edit().text = "1.3"
	check("uncommitted text differs from value", absf(control.value - 0.4) < 1e-12, control.get_line_edit().text)
	control.apply()
	check("apply commits pending text", absf(control.value - 1.3) < 1e-12, control.value)
	control.free()
	var failed := 0
	for c in checks:
		if not c.passed:
			failed += 1
	var result := {engine = Engine.get_version_info().string, checks = checks, failed = failed}
	var output := JSON.stringify(result, "\t", true, true)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		if file == null:
			push_error("cannot save probe: %s" % args[0])
			quit(2)
			return
		file.store_string(output + "\n")
		file.close()
	print(output)
	quit(1 if failed else 0)
