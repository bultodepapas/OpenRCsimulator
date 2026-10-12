# SC/LU: unobstructed flight rows stay identical; collision-enabled traces identify their layout.
# The explicit legacy route also retains the original visual-only trace contract.
extends SceneTree

var _failures := 0

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])

func _trace(mode: String, upgrade: bool = true) -> Dictionary:
	var path := ProjectSettings.globalize_path("user://scenery_trace_%s.csv" % mode)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "--", "--scenery=%s" % mode, "--scenery_audio=off",
		"--landscape-upgrade=%s" % ("on" if upgrade else "off"), "--trace=%s" % path, "--t=2"], output, true)
	_check("app ran with scenery %s, collision integration %s" % [mode, upgrade],
		code == 0 and not str(output).contains("ERROR:"), "exit %d; %s" % [code, output])
	var lines := FileAccess.get_file_as_string(path).split("\n")
	DirAccess.remove_absolute(path)
	var kept := PackedStringArray()
	var identity := ""
	for line: String in lines:
		if line.begins_with("# collision_world_identity: "):
			identity = line.trim_prefix("# collision_world_identity: ")
		elif not line.begins_with("# created_utc"):
			kept.append(line)
	return {lines = kept, identity = identity}

func _initialize() -> void:
	var off := _trace("off")
	var on := _trace("on")
	_check("collision-enabled traces have rows", off.lines.size() > 100 and on.lines.size() > 100)
	var sha := RegEx.create_from_string("^[0-9a-f]{64}$")
	_check("both visible inventories have explicit SHA-256 identities",
		sha.search(off.identity) != null and sha.search(on.identity) != null)
	_check("scenery on/off identifies different obstacle inventories", off.identity != on.identity)
	_check("unobstructed rows and all remaining metadata match with scenery on/off",
		off.lines == on.lines, "%d vs %d lines" % [off.lines.size(), on.lines.size()])
	var legacy_off := _trace("off", false)
	var legacy_on := _trace("on", false)
	_check("legacy visual-only traces contain no collision identity",
		legacy_off.identity.is_empty() and legacy_on.identity.is_empty())
	_check("legacy trace rows and metadata remain identical with scenery on/off",
		legacy_off.lines.size() > 100 and legacy_off.lines == legacy_on.lines)
	print("all scenery trace checks passed" if _failures == 0 else "%d scenery trace checks failed" % _failures)
	quit(1 if _failures > 0 else 0)
