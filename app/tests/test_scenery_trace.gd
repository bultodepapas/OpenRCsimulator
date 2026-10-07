# SCENERY-PLAN rule 3: scenery is invisible to the simulation. Runs the real app headless twice, with scenery off and on,
# and requires identical trace rows (only the creation timestamp may differ).
# Run: godot --headless --path . --script res://tests/test_scenery_trace.gd
extends SceneTree

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _trace(mode: String) -> PackedStringArray:
	var path := ProjectSettings.globalize_path("user://scenery_trace_%s.csv" % mode)
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "--", "--scenery=%s" % mode, "--scenery_audio=off", "--trace=%s" % path, "--t=2"], out, true)
	_check("app ran with scenery %s" % mode, code == 0, "exit %d" % code)
	var lines := FileAccess.get_file_as_string(path).split("\n")
	DirAccess.remove_absolute(path)
	var kept := PackedStringArray()
	for l: String in lines:
		if not l.begins_with("# created_utc"):
			kept.append(l)
	return kept


func _initialize() -> void:
	var off := _trace("off")
	var on := _trace("on")
	_check("traces have rows", off.size() > 100)
	_check("trace rows are identical with scenery on and off", off == on, "%d vs %d lines" % [off.size(), on.size()])
	print("all scenery trace checks passed" if _failures == 0 else "%d scenery trace checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
