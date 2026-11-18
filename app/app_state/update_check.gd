# Update notice (MENU-PLAN UI-16): is a newer release published? Pure functions over the GitHub Releases API JSON
# and a small cache file, so every rule is testable headless without a network; the request itself lives in
# app_state/update_checker.gd and the card in ui/update_notice.gd.
# Facts this relies on (probe of 2026-10-12, docs/research/menu-investigations/UI-16): every release so far is a
# prerelease, so GitHub's /releases/latest answers 404; the list endpoint returns prereleases and the newest is
# chosen here. Versions order by SemVer 2.0 precedence, with one deliberate reading: digits inside a prerelease
# identifier compare numerically (rc7 < rc10, as the tags are written). Build metadata (+5.gabc1234.dirty) never
# orders, so a CI build between two tags counts as its tag.
# DT-UPD-04a (docs/plans/github-updates.md) added the stable/preview subscription, the exact per-platform package
# with its advertised size and digest, and distinct statuses for Settings. This is discovery only: the digest is
# GitHub's own observation, not publisher authentication, so nothing here downloads, verifies or installs.
extends RefCounted

## 30 per page (DT-UPD-04a): the stable channel filters prereleases out of this one page, so ten rc tags after a
## stable release must not push it out of view. 30 releases stay far below MAX_BODY_BYTES.
const RELEASES_URL := "https://api.github.com/repos/bultodepapas/OpenRCsimulator/releases?per_page=30"
const RELEASES_PAGE := "https://github.com/bultodepapas/OpenRCsimulator/releases"
## Only this origin may be opened in the browser from a notice (the API answer is data, not a command).
const TRUSTED_PAGE_PREFIX := "https://github.com/bultodepapas/OpenRCsimulator/"
const STATE_PATH := "user://update_check.cfg"
## 2 (DT-UPD-04a) adds the channel the cache answers for, the last successful check and this platform's exact
## package (name, bytes, GitHub digest). A format-1 cache keeps only the skipped version: one fresh check refills it.
const STATE_FORMAT := 2
## DT-UPD-04a subscription channels. Stable offers releases only; preview also offers prereleases (a preview
## subscriber may be offered the final stable successor). "" (no explicit choice) follows the running build, so
## a prerelease build keeps hearing about prereleases as before. tools/release/manifest.py names the same two.
const CHANNEL_STABLE := "stable"
const CHANNEL_PREVIEW := "preview"
const CHANNELS: Array[String] = [CHANNEL_STABLE, CHANNEL_PREVIEW]
## Release ZIP per platform, exactly as tools/release/manifest.py artifact_names() writes them:
## openrc-simulator-<tag>-<suffix>.zip. A filename substring is not enough to identify a package.
const PACKAGE_SUFFIXES := { windows = "windows-x86_64", linux = "linux-x86_64", macos = "macos-universal" }
## An advertised asset size beyond this is treated as unknown (GitHub's per-asset limit is 2 GiB).
const MAX_PACKAGE_BYTES := 4 * 1024 * 1024 * 1024
## Check now waits this long after the previous request (manual or automatic), so repeated presses or channel
## flips cannot spend GitHub's 60 anonymous requests an hour.
const MANUAL_COOLDOWN_S := 30.0
## status() kinds, kept distinct (a failed request never reads as "current").
const STATUS_NOT_CHECKED := "not_checked"
const STATUS_CURRENT := "current"
const STATUS_AVAILABLE := "available"
const STATUS_NO_PACKAGE := "no_package"
const STATUS_FAILED := "failed"
const SUCCESS_STATUSES: Array[String] = ["200 ok", "304 not modified"]
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
		if not _is_digits(p) or p.length() > 18: # beyond 18 digits int() saturates and prints an engine error
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


## The channel in effect: an explicit `choice` from CHANNELS, else the running build's own (preview for a
## prerelease build, stable otherwise and when the version is unknown).
static func effective_channel(choice: String, running: Dictionary) -> String:
	if choice in CHANNELS:
		return choice
	var pre: PackedStringArray = running.get("prerelease", PackedStringArray())
	return CHANNEL_PREVIEW if running.get("ok", false) and not pre.is_empty() else CHANNEL_STABLE


## The platform key of PACKAGE_SUFFIXES for an OS name (OS.get_name()) and the running build's architecture
## (Engine.get_architecture_name()), or "" when no official package fits (an ARM Linux or Windows build).
static func platform_key(os_name: String, architecture: String) -> String:
	match os_name:
		"Windows": return "windows" if architecture == "x86_64" else ""
		"Linux": return "linux" if architecture == "x86_64" else ""
		"macOS": return "macos" # one universal package for arm64 and x86_64
	return ""


## The release to offer, or {} when none applies: drafts and unparsable tags are skipped, and the stable channel
## is never offered a prerelease. `channel` "" follows the running build (effective_channel). `releases` is the
## API's JSON array. Returns { tag, version (parsed), url, published, prerelease, assets (platform -> download
## URL), packages (platform -> { name, url, size, digest }) }; only exactly named release ZIPs count.
static func newest(releases: Variant, running: Dictionary, channel := "") -> Dictionary:
	var best := {}
	if not releases is Array or not running.get("ok", false):
		return best
	var preview := effective_channel(channel, running) == CHANNEL_PREVIEW
	for r in releases:
		if not r is Dictionary or r.get("draft", false) == true:
			continue
		var v := parse_version(str(r.get("tag_name", "")))
		if not v.ok:
			continue
		var is_pre: bool = r.get("prerelease", false) == true or not v.prerelease.is_empty()
		if is_pre and not preview:
			continue
		if best.is_empty() or compare(v, best.version) > 0:
			var packages := _packages(r, str(r.get("tag_name", "")))
			var assets := {}
			for platform: String in packages:
				assets[platform] = packages[platform].url
			best = {
				tag = str(r.get("tag_name", "")),
				version = v,
				url = str(r.get("html_url", "")),
				published = str(r.get("published_at", "")),
				prerelease = is_pre,
				assets = assets,
				packages = packages,
			}
	return best


## What Home shows, from the cached state: {} unless the cached latest release is newer than `running_text`, was
## not skipped (`include_hidden` ignores that for Settings), and is not a prerelease offered on the stable channel
## (`channel` as in newest; the cache may come from another build, see `for_version`). Returns { tag, version
## (text without "v"), url (trusted page), published, package (this platform's ZIP name, "" when the release has
## none), size (its bytes, 0 when unknown) }.
static func notice(running_text: String, state: Dictionary, channel := "", include_hidden := false) -> Dictionary:
	var running := parse_version(running_text)
	var latest := parse_version(str(state.get("latest_tag", "")))
	if not running.ok or not latest.ok or compare(latest, running) <= 0:
		return {}
	if not include_hidden and str(state.get("latest_tag", "")) == str(state.get("hidden_tag", "")):
		return {}
	var is_pre: bool = state.get("latest_prerelease", false) == true or not latest.prerelease.is_empty()
	if is_pre and effective_channel(channel, running) != CHANNEL_PREVIEW:
		return {}
	return {
		tag = latest.text,
		version = latest.text.trim_prefix("v").trim_prefix("V"),
		url = trusted_page(str(state.get("latest_url", ""))),
		published = str(state.get("latest_published", "")),
		package = str(state.get("latest_package", "")),
		size = maxi(0, int(state.get("latest_size", 0))),
	}


## Settings' summary of the cached state: { kind (a STATUS_* value), channel (effective), version and size of an
## eligible newer release (skipped or not), last_success_unix, last_status }. An eligible release without a
## package for this platform is STATUS_NO_PACKAGE; a cached release outranks a later failed request; a failed
## request never reads as current, and neither does an answer for another build or channel.
static func status(running_text: String, state: Dictionary, channel := "") -> Dictionary:
	var running := parse_version(running_text)
	var last_status := str(state.get("last_status", ""))
	var out := {
		kind = STATUS_NOT_CHECKED,
		channel = effective_channel(channel, running),
		version = "",
		size = 0,
		last_success_unix = maxi(0, int(state.get("last_success_unix", 0))),
		last_status = last_status,
	}
	var info := notice(running_text, state, channel, true)
	if not info.is_empty():
		out.version = info.version
		out.size = info.size
		out.kind = STATUS_AVAILABLE if info.package != "" else STATUS_NO_PACKAGE
	elif last_status != "" and not last_status in SUCCESS_STATUSES:
		out.kind = STATUS_FAILED
	elif last_status in SUCCESS_STATUSES and str(state.get("for_version", "")) == running_text \
			and str(state.get("for_channel", "")) == out.channel:
		out.kind = STATUS_CURRENT # only an answer for this build and channel says "latest"
	return out


## Decimal units, as download pages and the research report state them: "1.50 GB", "39.6 MB", "512 KB".
static func format_bytes(bytes: int) -> String:
	if bytes >= 999_950_000: # would print "1000.0 MB"
		return "%.2f GB" % (bytes / 1.0e9)
	if bytes >= 999_000: # would print "1000 KB"
		return "%.1f MB" % (bytes / 1.0e6)
	return "%d KB" % maxi(1, int(ceil(bytes / 1.0e3)))


## `url` when it is a plain https page of the project (no whitespace or control characters: the string goes to
## the OS as it is), else the releases page.
static func trusted_page(url: String) -> String:
	if not url.begins_with(TRUSTED_PAGE_PREFIX) or url.length() > 512:
		return RELEASES_PAGE
	for c in url:
		if c <= " " or c >= "\u007f" or c == "\"" or c == "'" or c == "\\":
			return RELEASES_PAGE
	return url


## `for_version` is the running build the cache was computed for: the selection (and the ETag that would keep it
## through 304 answers) belongs to that build's channel, so another build starts from a fresh answer.
## `for_channel` likewise: a stable answer says nothing about preview releases and the reverse.
static func default_state() -> Dictionary:
	return { last_check_unix = 0, last_success_unix = 0, etag = "", for_version = "", for_channel = "", latest_tag = "",
		latest_url = "", latest_published = "", latest_prerelease = false, latest_package = "", latest_size = 0,
		latest_digest = "", hidden_tag = "", last_status = "" }


## The state another build or channel left behind, kept only where it still applies (the skipped version and
## when a check last succeeded; its status line answered another question, so the fresh state is "not checked").
## `channel` is the effective channel ("" for callers without one).
static func state_for(state: Dictionary, running_text: String, channel := "") -> Dictionary:
	if str(state.get("for_version", "")) == running_text and str(state.get("for_channel", "")) == channel:
		return state
	var fresh := default_state()
	fresh.for_version = running_text
	fresh.for_channel = channel
	fresh.hidden_tag = str(state.get("hidden_tag", ""))
	fresh.last_success_unix = maxi(0, int(state.get("last_success_unix", 0)))
	return fresh


## The cache file; anything unreadable, of another format or of a wrong type falls back to the default value
## (a broken cache only means one more check).
static func load_state(path: String) -> Dictionary:
	var state := default_state()
	if not FileAccess.file_exists(path):
		return state
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return state
	var format: Variant = cfg.get_value("meta", "format", -1)
	if format is int and format == 1:
		# Format 1 knew no package or channel: keep the player's skipped version, refill the rest with one check.
		var skipped: Variant = cfg.get_value("latest", "hidden_tag", "")
		if typeof(skipped) == TYPE_STRING:
			state.hidden_tag = skipped
		return state
	if format != STATE_FORMAT:
		return state
	for key in ["last_check_unix", "last_success_unix"]:
		var last: Variant = cfg.get_value("check", key, 0)
		if typeof(last) == TYPE_INT and last >= 0:
			state[key] = last
	for key in ["etag", "for_version", "for_channel", "last_status"]:
		var v: Variant = cfg.get_value("check", key, "")
		if typeof(v) == TYPE_STRING:
			state[key] = v
	var tag: Variant = cfg.get_value("latest", "tag", "")
	if typeof(tag) == TYPE_STRING and parse_version(tag).ok:
		state.latest_tag = tag
		for key in ["url", "published", "package", "digest"]:
			var v: Variant = cfg.get_value("latest", key, "")
			if typeof(v) == TYPE_STRING:
				state["latest_" + key] = v
		var pre: Variant = cfg.get_value("latest", "prerelease", false)
		if typeof(pre) == TYPE_BOOL:
			state.latest_prerelease = pre
		var size: Variant = cfg.get_value("latest", "size", 0)
		if typeof(size) == TYPE_INT and size >= 0 and size <= MAX_PACKAGE_BYTES:
			state.latest_size = size
	var hidden: Variant = cfg.get_value("latest", "hidden_tag", "")
	if typeof(hidden) == TYPE_STRING:
		state.hidden_tag = hidden
	return state


static func save_state(path: String, state: Dictionary) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", STATE_FORMAT)
	cfg.set_value("check", "last_check_unix", int(state.get("last_check_unix", 0)))
	cfg.set_value("check", "last_success_unix", int(state.get("last_success_unix", 0)))
	cfg.set_value("check", "etag", str(state.get("etag", "")))
	cfg.set_value("check", "for_version", str(state.get("for_version", "")))
	cfg.set_value("check", "for_channel", str(state.get("for_channel", "")))
	cfg.set_value("check", "last_status", str(state.get("last_status", "")))
	cfg.set_value("latest", "tag", str(state.get("latest_tag", "")))
	cfg.set_value("latest", "url", str(state.get("latest_url", "")))
	cfg.set_value("latest", "published", str(state.get("latest_published", "")))
	cfg.set_value("latest", "prerelease", state.get("latest_prerelease", false) == true)
	cfg.set_value("latest", "package", str(state.get("latest_package", "")))
	cfg.set_value("latest", "size", int(state.get("latest_size", 0)))
	cfg.set_value("latest", "digest", str(state.get("latest_digest", "")))
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


## platform -> { name, url, size, digest } for the release's exactly named ZIPs (PACKAGE_SUFFIXES). `url` is
## kept only when it is a plain page of this project (else ""); `size` is 0 when absent or implausible; `digest`
## is GitHub's "sha256:<64 hex>" or "". A duplicate name makes that platform's package ambiguous: dropped.
static func _packages(release: Dictionary, tag: String) -> Dictionary:
	var out := {}
	var assets: Variant = release.get("assets", [])
	if not assets is Array or tag == "":
		return out
	var ambiguous := {}
	var digest_re := RegEx.create_from_string("^sha256:[0-9a-f]{64}$")
	for a in assets:
		if not a is Dictionary:
			continue
		var asset_name := str(a.get("name", ""))
		for platform: String in PACKAGE_SUFFIXES:
			if asset_name != "openrc-simulator-%s-%s.zip" % [tag, PACKAGE_SUFFIXES[platform]]:
				continue
			if out.has(platform):
				ambiguous[platform] = true
			var url := str(a.get("browser_download_url", ""))
			var size: Variant = a.get("size", 0)
			var bytes := 0
			if (size is int or size is float) and size > 0 and size <= MAX_PACKAGE_BYTES and size == floorf(size):
				bytes = int(size)
			var digest := str(a.get("digest", "")) if a.get("digest") is String else ""
			out[platform] = {
				name = asset_name,
				url = url if trusted_page(url) == url else "",
				size = bytes,
				digest = digest if digest_re.search(digest) != null else "",
			}
	for platform: String in ambiguous:
		out.erase(platform)
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
