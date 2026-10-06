# UI-04a: the build identity parser and loader (MENU-PLAN §9, research 21). The exported end of the chain (the pack
# really contains build_info.json and the binary reports it) is checked by export.sh on the exported binary.
# Run: godot --headless --path . --script res://tests/test_build_info.gd
extends SceneTree

const BuildInfo := preload("res://app_state/build_info.gd")
const TMP := "user://test_build_info.json"

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var cases := [
		# describe, numeric, expected semver, tag, after, sha, dirty
		["v0.1.0-rc2", "0.1.0", "0.1.0-rc2", "v0.1.0-rc2", 0, "", false],
		["v0.1.0-rc2-5-gabc1234", "0.1.0", "0.1.0-rc2+5.gabc1234", "v0.1.0-rc2", 5, "abc1234", false],
		["v0.1.0-rc2-5-gabc1234-dirty", "0.1.0", "0.1.0-rc2+5.gabc1234.dirty", "v0.1.0-rc2", 5, "abc1234", true],
		["v0.1.0-rc2-dirty", "0.1.0", "0.1.0-rc2+dirty", "v0.1.0-rc2", 0, "", true],
		["v1.2.3", "1.2.3", "1.2.3", "v1.2.3", 0, "", false],
		["v0.2.0-rc.10-12-g0123456789ab", "0.2.0", "0.2.0-rc.10+12.g0123456789ab", "v0.2.0-rc.10", 12, "0123456789ab", false],
		["ee1f7d6", "0.1.0", "0.1.0+gee1f7d6", "", 0, "ee1f7d6", false], # --always, no tag (shallow clone)
		["ee1f7d6-dirty", "0.1.0", "0.1.0+gee1f7d6.dirty", "", 0, "ee1f7d6", true],
		["export-manual", "0.1.0", "0.1.0+export-manual", "", 0, "", false], # exported by hand from the editor
		["main", "0.1.0", "0.1.0+main", "", 0, "", false], # an old CI branch name: visible, never mistaken for a tag
		["", "0.1.0", "0.1.0", "", 0, "", false],
	]
	for c in cases:
		var p := BuildInfo.parse_describe(c[0], c[1])
		var ok: bool = p.semver == c[2] and p.tag == c[3] and p.after == c[4] and p.sha == c[5] and p.dirty == c[6]
		_check("parse \"%s\" -> %s" % [c[0], p.semver], ok, str(p))

	# Loader: from the source tree there is no build_info.json.
	var dev := BuildInfo.current()
	_check("source tree: development build, numeric version from project.godot (%s)" % dev.version,
		dev.source == "development" and dev.version.count(".") == 2 and dev.label == "")
	# An exported pack's file (written by addons/build_info), read from a test path.
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({ format = "openrc-build v1", describe = "v0.1.0-rc2-5-gabc1234-dirty",
		commit = "abc1234def", dirty = true, commit_date = "2026-10-06T00:00:00+00:00" }))
	f.close()
	var exported := BuildInfo.current(TMP)
	_check("exported: label is the SemVer of the describe", exported.source == "export" and exported.label == "0.1.0-rc2+5.gabc1234.dirty"
		and exported.commit == "abc1234def" and exported.dirty, str(exported))
	f = FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{\"format\": \"something else\"}")
	f.close()
	_check("a file of another format is ignored (development)", BuildInfo.current(TMP).source == "development")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))

	print("all build info checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)
