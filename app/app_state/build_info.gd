# Build identity (MENU-PLAN §9, step UI-04a, research 21). Exported builds carry res://build_info.json, written into
# the pack by addons/build_info at export time from the values export.sh computes once (git describe, commit, dirty,
# commit date): the same string names the ZIP. Running from the source tree there is no such file: "development".
# Never identify a build by application/config/version alone: an override.cfg next to the binary can change it.
extends RefCounted

const PATH := "res://build_info.json"
const FORMAT := "openrc-build v1"


## The running build: { source ("export" | "development"), describe, commit, dirty, commit_date, version (numeric,
## project.godot), parsed (parse_describe of describe), label (short text for Home), godot }.
static func current(path := PATH) -> Dictionary:
	var numeric := str(ProjectSettings.get_setting("application/config/version", ""))
	var info := { source = "development", describe = "", commit = "", dirty = false, commit_date = "", version = numeric }
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("format", "") == FORMAT:
			info.source = "export"
			for key in ["describe", "commit", "commit_date"]:
				info[key] = str(data.get(key, ""))
			info.dirty = data.get("dirty", false) == true
	info.parsed = parse_describe(info.describe, numeric)
	info.label = info.parsed.semver if info.source == "export" else ""
	info.godot = Engine.get_version_info().string
	return info


## Reads `git describe --tags --always --dirty` output. `numeric_version` (x.y.z from project.godot) stands in when
## the describe has no tag (a bare SHA from a clone without tags, or a manual export).
## Returns { tag, base, prerelease, after (commits since the tag), sha, dirty, semver }, where semver follows
## SemVer 2.0: build metadata after "+" (commits, sha, dirty) never orders versions.
## "v0.1.0-rc2-5-gabc1234-dirty" -> semver "0.1.0-rc2+5.gabc1234.dirty"; "v0.1.0-rc2" -> "0.1.0-rc2".
static func parse_describe(describe: String, numeric_version := "") -> Dictionary:
	var out := { tag = "", base = numeric_version, prerelease = "", after = 0, sha = "", dirty = false, semver = "" }
	var text := describe.strip_edges()
	if text.ends_with("-dirty"):
		out.dirty = true
		text = text.trim_suffix("-dirty")
	var re := RegEx.create_from_string("^(v?(\\d+\\.\\d+\\.\\d+)(?:-([0-9A-Za-z.]+))?)(?:-(\\d+)-g([0-9a-f]{4,40}))?$")
	var m := re.search(text)
	if m != null:
		out.tag = m.get_string(1)
		out.base = m.get_string(2)
		out.prerelease = m.get_string(3)
		out.after = int(m.get_string(4)) if m.get_string(4) != "" else 0
		out.sha = m.get_string(5)
	elif RegEx.create_from_string("^[0-9a-f]{4,40}$").search(text) != null:
		out.sha = text # --always without a reachable tag
	var meta := PackedStringArray()
	if out.after > 0:
		meta.append(str(out.after))
	if out.sha != "":
		meta.append("g" + out.sha)
	if out.dirty:
		meta.append("dirty")
	if text != "" and m == null and out.sha == "":
		meta.append(text.to_lower().replace("/", "-")) # e.g. "export-manual": keep it visible, never hide it
	out.semver = (out.base if out.base != "" else "0.0.0") + ("-" + out.prerelease if out.prerelease != "" else "") \
		+ ("+" + ".".join(meta) if not meta.is_empty() else "")
	return out
