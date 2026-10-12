# Update notice (MENU-PLAN UI-16): is a newer release published? Pure functions over the GitHub Releases API JSON
# and a small cache file, so every rule is testable headless without a network; the request itself lives in
# app_state/update_checker.gd and the card in ui/update_notice.gd.
# Facts this relies on (probe of 2026-10-12, docs/research/menu-investigations/UI-16): every release so far is a
# prerelease, so GitHub's /releases/latest answers 404; the list endpoint returns prereleases and the newest is
# chosen here. Versions order by SemVer 2.0 precedence, with one deliberate reading: digits inside a prerelease
# identifier compare numerically (rc7 < rc10, as the tags are written). Build metadata (+5.gabc1234.dirty) never
# orders, so a CI build between two tags counts as its tag.
extends RefCounted

const RELEASES_URL := "https://api.github.com/repos/bultodepapas/OpenRCsimulator/releases?per_page=10"
const RELEASES_PAGE := "https://github.com/bultodepapas/OpenRCsimulator/releases"
## Only this origin may be opened in the browser from a notice (the API answer is data, not a command).
const TRUSTED_PAGE_PREFIX := "https://github.com/bultodepapas/OpenRCsimulator/"
const STATE_PATH := "user://update_check.cfg"
const STATE_FORMAT := 1
## One check a day is plenty: GitHub allows 60 anonymous requests an hour per address, and every launch within
## the day shows the cached answer at once.
const INTERVAL_S := 24 * 60 * 60
const TIMEOUT_S := 10.0
const MAX_BODY_BYTES := 2 * 1024 * 1024


## "v0.1.0-rc7", "0.1.0-rc7+5.gabc1234.dirty" or "1.2.3" -> { ok, major, minor, patch, prerelease (identifiers),
## text }. Build metadata is dropped. Anything else -> ok = false.
static func parse_version(text: String) -> Dictionary:
	var out := { ok = false, major = 0, minor = 0, patch = 0, prerelease = PackedStringArray(), text = text.strip_edges() }
	var s: String = out.text
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var plus := s.find("+")
	if plus >= 0:
		s = s.substr(0, plus)
	var dash := s.find("-")
	var core := s if dash < 0 else s.substr(0, dash)
	var pre := "" if dash < 0 else s.substr(dash + 1)
	var parts := core.split(".")
	if parts.size() != 3 or (dash >= 0 and pre == ""):
		return out
	for p in parts:
		if not _is_digits(p):
			return out
	var ids := PackedStringArray()
	if pre != "":
		var id_re := RegEx.create_from_string("^[0-9A-Za-z-]+$")
		for id in pre.split("."):
			if id_re.search(id) == null:
				return out
			ids.append(id)
	out.major = int(parts[0])
	out.minor = int(parts[1])
	out.patch = int(parts[2])
	out.prerelease = ids
	out.ok = true
	return out


## SemVer precedence: -1 when a < b, 0 when equal, 1 when a > b. A release outranks its prereleases; numeric
## identifiers rank below alphanumeric ones; digit runs inside an identifier compare numerically (rc7 < rc10).
static func compare(a: Dictionary, b: Dictionary) -> int:
	for key in ["major", "minor", "patch"]:
		if a[key] != b[key]:
			return -1 if a[key] < b[key] else 1
	var pa: PackedStringArray = a.prerelease
	var pb: PackedStringArray = b.prerelease
	if pa.is_empty() or pb.is_empty():
		if pa.is_empty() == pb.is_empty():
			return 0
		return 1 if pa.is_empty() else -1
	for i in range(mini(pa.size(), pb.size())):
		var c := _compare_identifier(pa[i], pb[i])
		if c != 0:
			return c
	if pa.size() == pb.size():
		return 0
	return -1 if pa.size() < pb.size() else 1


## The release to offer, or {} when none applies: drafts and unparsable tags are skipped, and someone running a
## release (no prerelease identifiers) is never offered a prerelease. `releases` is the API's JSON array.
## Returns { tag, version (parsed), url, published, prerelease, assets (platform name -> download URL) }.
static func newest(releases: Variant, running: Dictionary) -> Dictionary:
	var best := {}
	if not releases is Array or not running.get("ok", false):
		return best
	var running_pre: PackedStringArray = running.prerelease
	for r in releases:
		if not r is Dictionary or r.get("draft", false) == true:
			continue
		var v := parse_version(str(r.get("tag_name", "")))
		if not v.ok:
			continue
		var is_pre: bool = r.get("prerelease", false) == true or not v.prerelease.is_empty()
		if is_pre and running_pre.is_empty():
			continue
		if best.is_empty() or compare(v, best.version) > 0:
			best = {
				tag = str(r.get("tag_name", "")),
				version = v,
				url = str(r.get("html_url", "")),
				published = str(r.get("published_at", "")),
				prerelease = is_pre,
				assets = _assets(r),
			}
	return best


## What Home shows, from the cached state: {} unless the cached latest release is newer than `running_text` and
## was not hidden. Returns { tag, version (text without "v"), url (trusted page), published }.
static func notice(running_text: String, state: Dictionary) -> Dictionary:
	var running := parse_version(running_text)
	var latest := parse_version(str(state.get("latest_tag", "")))
	if not running.ok or not latest.ok or compare(latest, running) <= 0:
		return {}
	if str(state.get("latest_tag", "")) == str(state.get("hidden_tag", "")):
		return {}
	var url := str(state.get("latest_url", ""))
	return {
		tag = latest.text,
		version = latest.text.trim_prefix("v"),
		url = url if url.begins_with(TRUSTED_PAGE_PREFIX) else RELEASES_PAGE,
		published = str(state.get("latest_published", "")),
	}


static func default_state() -> Dictionary:
	return { last_check_unix = 0, etag = "", latest_tag = "", latest_url = "", latest_published = "", hidden_tag = "", last_status = "" }


## The cache file; anything unreadable, of another format or of a wrong type falls back to the default value
## (a broken cache only means one more check).
static func load_state(path: String) -> Dictionary:
	var state := default_state()
	if not FileAccess.file_exists(path):
		return state
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or cfg.get_value("meta", "format", -1) != STATE_FORMAT:
		return state
	var last: Variant = cfg.get_value("check", "last_check_unix", 0)
	if typeof(last) == TYPE_INT and last >= 0:
		state.last_check_unix = last
	for key in ["etag", "last_status"]:
		var v: Variant = cfg.get_value("check", key, "")
		if typeof(v) == TYPE_STRING:
			state[key] = v
	var tag: Variant = cfg.get_value("latest", "tag", "")
	if typeof(tag) == TYPE_STRING and parse_version(tag).ok:
		state.latest_tag = tag
		for key in ["url", "published"]:
			var v: Variant = cfg.get_value("latest", key, "")
			if typeof(v) == TYPE_STRING:
				state["latest_" + key] = v
	var hidden: Variant = cfg.get_value("latest", "hidden_tag", "")
	if typeof(hidden) == TYPE_STRING:
		state.hidden_tag = hidden
	return state


static func save_state(path: String, state: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", STATE_FORMAT)
	cfg.set_value("check", "last_check_unix", int(state.get("last_check_unix", 0)))
	cfg.set_value("check", "etag", str(state.get("etag", "")))
	cfg.set_value("check", "last_status", str(state.get("last_status", "")))
	cfg.set_value("latest", "tag", str(state.get("latest_tag", "")))
	cfg.set_value("latest", "url", str(state.get("latest_url", "")))
	cfg.set_value("latest", "published", str(state.get("latest_published", "")))
	cfg.set_value("latest", "hidden_tag", str(state.get("hidden_tag", "")))
	return cfg.save(path)


## True when no check succeeded in the last INTERVAL_S (a clock set back also counts as due).
static func due(state: Dictionary, now_unix: int) -> bool:
	var last := int(state.get("last_check_unix", 0))
	return last <= 0 or now_unix < last or now_unix - last >= INTERVAL_S


## What the request says about itself: the API version GitHub documents, our build and OS in the User-Agent
## (GitHub rejects requests without one), and the cached ETag so an unchanged list answers 304 without a body.
static func headers(etag: String, version_text: String, os_name: String) -> PackedStringArray:
	var out := PackedStringArray([
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: OpenRC-Simulator/%s (%s)" % [version_text if version_text != "" else "unknown", os_name],
	])
	if etag != "":
		out.append("If-None-Match: " + etag)
	return out


## The ETag response header, or "".
static func etag_of(response_headers: PackedStringArray) -> String:
	for h in response_headers:
		if h.to_lower().begins_with("etag:"):
			return h.substr(5).strip_edges()
	return ""


## The JSON array of releases, or null when the body is too large, not JSON or not an array. (A JSON instance
## reports a bad body as a return value; the static parse_string would print an engine error.)
static func parse_response(body: PackedByteArray) -> Variant:
	if body.size() > MAX_BODY_BYTES:
		return null
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return null
	return json.data if json.data is Array else null


static func _assets(release: Dictionary) -> Dictionary:
	var out := {}
	var assets: Variant = release.get("assets", [])
	if not assets is Array:
		return out
	for a in assets:
		if not a is Dictionary:
			continue
		var asset_name := str(a.get("name", "")).to_lower()
		var url := str(a.get("browser_download_url", ""))
		for platform in ["windows", "macos", "linux"]:
			if asset_name.contains("-%s-" % platform) and asset_name.ends_with(".zip"):
				out[platform] = url
	return out


static func _is_digits(s: String) -> bool:
	if s.is_empty():
		return false
	for c in s:
		if c < "0" or c > "9":
			return false
	return true


static func _compare_identifier(x: String, y: String) -> int:
	var xn := _is_digits(x)
	var yn := _is_digits(y)
	if xn and yn:
		return _compare_numbers(x, y)
	if xn != yn:
		return -1 if xn else 1
	var rx := _runs(x)
	var ry := _runs(y)
	for i in range(mini(rx.size(), ry.size())):
		var c: int
		if _is_digits(rx[i]) and _is_digits(ry[i]):
			c = _compare_numbers(rx[i], ry[i])
		else:
			c = 0 if rx[i] == ry[i] else (-1 if rx[i] < ry[i] else 1)
		if c != 0:
			return c
	if rx.size() == ry.size():
		return 0
	return -1 if rx.size() < ry.size() else 1


## Digit strings of any length, compared as numbers (no int overflow for absurd tags).
static func _compare_numbers(x: String, y: String) -> int:
	var a := x.lstrip("0")
	var b := y.lstrip("0")
	if a.length() != b.length():
		return -1 if a.length() < b.length() else 1
	return 0 if a == b else (-1 if a < b else 1)


## "rc10" -> ["rc", "10"]; "beta2a" -> ["beta", "2", "a"].
static func _runs(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	var digits := false
	for c in s:
		var d: bool = c >= "0" and c <= "9"
		if current != "" and d != digits:
			out.append(current)
			current = ""
		current += c
		digits = d
	if current != "":
		out.append(current)
	return out
