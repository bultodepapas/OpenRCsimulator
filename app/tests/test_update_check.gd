# UI-16: the update check without the internet: version precedence, the release to offer, the cache file, the
# once-a-day rule, and the checker node end to end against a local fake of the GitHub Releases API (200, 304 with
# the ETag, a hidden version, a newly published one, a withdrawn one, another build's cache, a 403, a server that
# accepts and never answers, and an offline machine). UI-16-R1 added the last five after the independent review.
# Run: godot --headless --path . --script res://tests/test_update_check.gd
extends SceneTree

const UpdateCheck := preload("res://app_state/update_check.gd")
const UpdateChecker := preload("res://app_state/update_checker.gd")
const FakeReleases := preload("res://tests/fake_releases.gd")
const FIXTURE := "res://tests/fixtures/github_releases.json"
const STATE := "user://test_update_check.cfg"
const T0 := 1_800_000_000 # 2027-01-15, any fixed instant

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_versions()
	_selection()
	_state_file()
	await _checker()
	_remove(STATE)
	print("all update check checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _versions() -> void:
	var p := UpdateCheck.parse_version("v0.1.0-rc7")
	_check("parse v0.1.0-rc7", p.ok and p.major == 0 and p.minor == 1 and p.patch == 0 and p.prerelease == PackedStringArray(["rc7"]), str(p))
	p = UpdateCheck.parse_version("0.1.0-rc7+5.gabc1234.dirty")
	_check("build metadata is dropped", p.ok and p.prerelease == PackedStringArray(["rc7"]), str(p))
	for bad in ["", "1.2", "v1.2.3.4", "1.2.3-", "abc", "1.2.3-rc_1", "1.2.x", "+1.2.3", "1.-2.3", "v99999999999999999999.0.0", "1.0000000000000000000.0"]:
		_check("rejects \"%s\"" % bad, not UpdateCheck.parse_version(bad).ok)
	# Ascending, as the project tags (rc7 < rc10) and as SemVer 2.0 §11 orders its own examples.
	var ascending := ["0.0.9", "0.1.0-alpha", "0.1.0-alpha.1", "0.1.0-alpha.beta", "0.1.0-beta", "0.1.0-beta.2",
		"0.1.0-beta.11", "0.1.0-rc.1", "0.1.0-rc.9", "0.1.0-rc.10", "0.1.0-rc1", "0.1.0-rc7", "0.1.0-rc10",
		"0.1.0", "0.1.1-rc1", "0.1.1", "0.2.0", "1.0.0-rc1", "1.0.0", "1.0.10", "10.0.0"]
	var disorder := 0
	for i in range(ascending.size()):
		for j in range(ascending.size()):
			var a := UpdateCheck.parse_version(ascending[i])
			var b := UpdateCheck.parse_version(ascending[j])
			var expected := signi(i - j)
			if UpdateCheck.compare(a, b) != expected:
				disorder += 1
				printerr("  %s vs %s: %d, expected %d" % [ascending[i], ascending[j], UpdateCheck.compare(a, b), expected])
	_check("every pair of %d versions orders as listed" % ascending.size(), disorder == 0, "%d pairs out of order" % disorder)
	_check("v prefix and metadata never order", UpdateCheck.compare(UpdateCheck.parse_version("v0.1.0-rc7+12.gdeadbeef"), UpdateCheck.parse_version("0.1.0-rc7")) == 0)


func _selection() -> void:
	var releases: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_check("fixture: the real list of 2026-10-12, seven prereleases", releases is Array and releases.size() == 7)
	var rc6 := UpdateCheck.parse_version("0.1.0-rc6")
	var latest := UpdateCheck.newest(releases, rc6)
	_check("rc6 is offered rc7, the release page and the three ZIPs", latest.get("tag", "") == "v0.1.0-rc7"
		and latest.url == "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7" and latest.prerelease
		and latest.assets.keys().size() == 3 and str(latest.assets.windows).ends_with("-windows-x86_64.zip")
		and str(latest.assets.macos).ends_with("-macos-universal.zip") and str(latest.assets.linux).ends_with("-linux-x86_64.zip"), str(latest))
	_check("a release build (0.1.0) is never offered a prerelease", UpdateCheck.newest(releases, UpdateCheck.parse_version("0.1.0")).is_empty())
	_check("garbage instead of a list offers nothing", UpdateCheck.newest({ message = "Not Found" }, rc6).is_empty()
		and UpdateCheck.newest([1, "x", null], rc6).is_empty() and UpdateCheck.newest(releases, UpdateCheck.parse_version("?")).is_empty())
	var mixed := [
		{ tag_name = "v9.9.9", draft = true, prerelease = false, html_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v9.9.9" },
		{ tag_name = "nightly", draft = false, prerelease = true, html_url = "" },
		{ tag_name = "v0.1.0", draft = false, prerelease = false, html_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0", published_at = "2026-11-01T00:00:00Z" },
		{ tag_name = "v0.2.0-rc1", draft = false, prerelease = true, html_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.2.0-rc1" },
		{ tag_name = "v0.1.0-rc7", draft = false, prerelease = true, html_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7" },
	]
	_check("drafts and unparsable tags are skipped; a prerelease build sees the newest prerelease",
		UpdateCheck.newest(mixed, UpdateCheck.parse_version("0.1.0-rc7")).tag == "v0.2.0-rc1")
	_check("a release build sees only releases", UpdateCheck.newest(mixed, UpdateCheck.parse_version("0.0.9")).tag == "v0.1.0"
		and UpdateCheck.newest(mixed, UpdateCheck.parse_version("0.1.0")).tag == "v0.1.0")
	# The notice, from the cached state.
	var state := UpdateCheck.default_state()
	state.latest_tag = "v0.1.0-rc7"
	state.latest_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7"
	state.latest_published = "2026-10-11T20:14:00Z"
	var n := UpdateCheck.notice("0.1.0-rc6", state)
	_check("notice for rc6: rc7, version text without v, the release page", n.get("tag", "") == "v0.1.0-rc7" and n.version == "0.1.0-rc7"
		and n.url == state.latest_url and n.published == state.latest_published, str(n))
	_check("a CI build after the rc6 tag is still rc6", not UpdateCheck.notice("0.1.0-rc6+3.gabc1234", state).is_empty())
	_check("no notice for the same or a newer build", UpdateCheck.notice("0.1.0-rc7", state).is_empty()
		and UpdateCheck.notice("0.1.0-rc7+9.g1234567.dirty", state).is_empty() and UpdateCheck.notice("0.1.0", state).is_empty())
	_check("no notice without a running version or a cached release", UpdateCheck.notice("", state).is_empty()
		and UpdateCheck.notice("0.1.0-rc6", UpdateCheck.default_state()).is_empty())
	state.hidden_tag = "v0.1.0-rc7"
	_check("a hidden version stays hidden", UpdateCheck.notice("0.1.0-rc6", state).is_empty())
	state.latest_tag = "v0.1.0-rc8"
	state.latest_url = "https://evil.example/download"
	n = UpdateCheck.notice("0.1.0-rc6", state)
	_check("a newer version shows again; an untrusted page URL falls back to the releases page",
		n.get("tag", "") == "v0.1.0-rc8" and n.url == UpdateCheck.RELEASES_PAGE, str(n))
	state.latest_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8 rm -rf"
	_check("a page URL with whitespace falls back too", UpdateCheck.notice("0.1.0-rc6", state).url == UpdateCheck.RELEASES_PAGE)
	state.latest_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8"
	state.latest_tag = "V0.1.0-rc8"
	_check("a capital V tag shows without it", UpdateCheck.notice("0.1.0-rc6", state).version == "0.1.0-rc8")
	# Another build's cache: a release build must not be offered the prerelease an rc build cached (UI-16-R1 review).
	state.latest_tag = "v0.2.0-rc1"
	state.latest_prerelease = true
	_check("a cached prerelease is never offered to a release build", UpdateCheck.notice("0.1.0", state).is_empty()
		and not UpdateCheck.notice("0.1.0-rc7", state).is_empty())
	state.latest_tag = "v0.2.0-rc1"
	state.latest_prerelease = false # the flag was lost: the tag itself still says prerelease
	_check("the tag's own identifiers count as prerelease", UpdateCheck.notice("0.1.0", state).is_empty())
	var other := UpdateCheck.default_state()
	other.for_version = "0.1.0-rc6"
	other.etag = "W/\"x\""
	other.latest_tag = "v0.1.0-rc7"
	other.hidden_tag = "v0.1.0-rc5"
	other.last_check_unix = T0
	_check("state_for: the same build keeps its cache", UpdateCheck.state_for(other, "0.1.0-rc6") == other)
	var fresh := UpdateCheck.state_for(other, "0.1.0-rc7")
	_check("state_for: another build starts fresh, keeping only the hidden tag", fresh.for_version == "0.1.0-rc7"
		and fresh.etag == "" and fresh.latest_tag == "" and fresh.last_check_unix == 0 and fresh.hidden_tag == "v0.1.0-rc5", str(fresh))


func _state_file() -> void:
	_remove(STATE)
	_check("no file: defaults", UpdateCheck.load_state(STATE) == UpdateCheck.default_state())
	var state := UpdateCheck.default_state()
	state.last_check_unix = T0
	state.etag = "W/\"abc\""
	state.for_version = "0.1.0-rc6"
	state.latest_tag = "v0.1.0-rc7"
	state.latest_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7"
	state.latest_published = "2026-10-11T20:14:00Z"
	state.latest_prerelease = true
	state.hidden_tag = "v0.1.0-rc6"
	state.last_status = "200 ok"
	_check("save", UpdateCheck.save_state(STATE, state) == OK)
	_check("round trip", UpdateCheck.load_state(STATE) == state, str(UpdateCheck.load_state(STATE)))
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	f.store_string("this is not a config file\n[[[")
	f.close()
	_check("garbage: defaults", UpdateCheck.load_state(STATE) == UpdateCheck.default_state())
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", 99)
	cfg.set_value("latest", "tag", "v0.1.0-rc7")
	cfg.save(STATE)
	_check("another format: defaults", UpdateCheck.load_state(STATE) == UpdateCheck.default_state())
	cfg = ConfigFile.new()
	cfg.set_value("meta", "format", UpdateCheck.STATE_FORMAT)
	cfg.set_value("check", "last_check_unix", "yesterday")
	cfg.set_value("check", "etag", 12)
	cfg.set_value("latest", "tag", "not-a-version")
	cfg.set_value("latest", "url", "https://github.com/bultodepapas/OpenRCsimulator/releases")
	cfg.set_value("latest", "hidden_tag", "v0.1.0-rc5")
	cfg.save(STATE)
	var loaded := UpdateCheck.load_state(STATE)
	_check("wrong types fall back one by one", loaded.last_check_unix == 0 and loaded.etag == "" and loaded.latest_tag == ""
		and loaded.latest_url == "" and loaded.hidden_tag == "v0.1.0-rc5", str(loaded))
	_remove(STATE)
	# Once a day.
	var fresh := UpdateCheck.default_state()
	_check("never checked: due", UpdateCheck.due(fresh, T0))
	fresh.last_check_unix = T0
	_check("just checked: not due", not UpdateCheck.due(fresh, T0) and not UpdateCheck.due(fresh, T0 + UpdateCheck.INTERVAL_S - 1))
	_check("a day later: due", UpdateCheck.due(fresh, T0 + UpdateCheck.INTERVAL_S))
	_check("clock set back: due", UpdateCheck.due(fresh, T0 - 1))
	# Request and answer plumbing.
	var h := UpdateCheck.headers("", "0.1.0-rc6", "Windows")
	_check("headers name the API version, build and OS, no ETag", h.size() == 3 and h[0] == "Accept: application/vnd.github+json"
		and h[1] == "X-GitHub-Api-Version: 2022-11-28" and h[2] == "User-Agent: OpenRC-Simulator/0.1.0-rc6 (Windows)", str(h))
	h = UpdateCheck.headers("W/\"abc\"", "", "macOS")
	_check("a cached ETag is sent back; an unknown version is said so", h.size() == 4 and h[3] == "If-None-Match: W/\"abc\""
		and h[2] == "User-Agent: OpenRC-Simulator/unknown (macOS)", str(h))
	_check("etag_of", UpdateCheck.etag_of(PackedStringArray(["Server: GitHub.com", "etag: W/\"xyz\" "])) == "W/\"xyz\""
		and UpdateCheck.etag_of(PackedStringArray(["Server: x"])) == "")
	_check("parse_response: an array, else null", UpdateCheck.parse_response("[{\"tag_name\": \"v1.0.0\"}]".to_utf8_buffer()) is Array
		and UpdateCheck.parse_response("{\"message\": \"rate limited\"}".to_utf8_buffer()) == null
		and UpdateCheck.parse_response("not json".to_utf8_buffer()) == null)
	var huge := PackedByteArray()
	huge.resize(UpdateCheck.MAX_BODY_BYTES + 1)
	_check("parse_response: an oversized body is refused", UpdateCheck.parse_response(huge) == null)


## The checker node against the fake API. Every launch is a fresh node with the shared cache file.
func _checker() -> void:
	var fixture := FileAccess.get_file_as_string(FIXTURE)
	var server := FakeReleases.new()
	if not server.start(fixture):
		_check("fake releases server listens on 127.0.0.1", false)
		return
	_remove(STATE)
	# Launch 1 (running rc6, first time): one request, 200, rc7 offered, cache written.
	var r := await _launch(server, "0.1.0-rc6", T0)
	_check("launch 1: one request, 200 ok", server.requests.size() == 1 and r.status == "200 ok", str(r))
	var head: String = server.requests[0] if not server.requests.is_empty() else ""
	_check("launch 1: the request names the API version, our build and OS, without an ETag",
		head.begins_with("GET /repos/x/y/releases?per_page=10 HTTP/1.1") and head.contains("Accept: application/vnd.github+json")
		and head.contains("X-GitHub-Api-Version: 2022-11-28") and head.contains("User-Agent: OpenRC-Simulator/0.1.0-rc6 (%s)" % OS.get_name())
		and not head.contains("If-None-Match"), head)
	_check("launch 1: rc7 offered once", r.notices.size() == 1 and r.notices[0].tag == "v0.1.0-rc7" and r.notices[0].version == "0.1.0-rc7"
		and r.notices[0].url == "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc7", str(r.notices))
	var st := UpdateCheck.load_state(STATE)
	_check("launch 1: cache written", st.last_check_unix == T0 and st.etag == server.etag and st.latest_tag == "v0.1.0-rc7"
		and st.last_status == "200 ok", str(st))
	r.checker.queue_free()
	# Launch 2, an hour later: no request; the cached notice at once.
	r = await _launch(server, "0.1.0-rc6", T0 + 3600)
	_check("launch 2 (+1 h): no request, the cached notice shows at once", server.requests.size() == 1 and r.status == ""
		and r.notices.size() == 1 and r.notices[0].tag == "v0.1.0-rc7", str(r))
	r.checker.queue_free()
	# Launch 3, a day later: the ETag goes back, 304, the date moves, the notice stays.
	r = await _launch(server, "0.1.0-rc6", T0 + 25 * 3600)
	_check("launch 3 (+25 h): one more request with the ETag, 304", server.requests.size() == 2
		and server.requests[1].contains("If-None-Match: " + server.etag) and r.status == "304 not modified", str(r))
	st = UpdateCheck.load_state(STATE)
	_check("launch 3: date moved, latest kept, notice shown", st.last_check_unix == T0 + 25 * 3600 and st.latest_tag == "v0.1.0-rc7"
		and r.notices.size() == 1, str(st))
	# Hide rc7: remembered in the cache; the next launch says nothing.
	r.checker.hide("v0.1.0-rc7")
	_check("hide: remembered", UpdateCheck.load_state(STATE).hidden_tag == "v0.1.0-rc7")
	r.checker.queue_free()
	r = await _launch(server, "0.1.0-rc6", T0 + 26 * 3600)
	_check("launch 4: hidden rc7 is not offered", r.notices.is_empty() and server.requests.size() == 2, str(r))
	r.checker.queue_free()
	# rc8 is published: a day later the list changes (200, new ETag) and the hidden rc7 no longer matters.
	var releases: Array = JSON.parse_string(fixture)
	var rc8: Dictionary = releases[0].duplicate(true)
	rc8.tag_name = "v0.1.0-rc8"
	rc8.html_url = "https://github.com/bultodepapas/OpenRCsimulator/releases/tag/v0.1.0-rc8"
	releases.push_front(rc8)
	server.publish(JSON.stringify(releases), "W/\"fixture-2\"")
	r = await _launch(server, "0.1.0-rc6", T0 + 50 * 3600)
	_check("launch 5 (rc8 published): 200, rc8 offered", server.requests.size() == 3 and r.status == "200 ok"
		and r.notices.size() == 1 and r.notices[0].tag == "v0.1.0-rc8", str(r))
	_check("launch 5: the new ETag is cached", UpdateCheck.load_state(STATE).etag == "W/\"fixture-2\"")
	r.checker.queue_free()
	# The list changes so that nothing newer than rc6 remains: the card announced from the cache is withdrawn.
	var older: Array = JSON.parse_string(fixture).filter(func(r: Dictionary) -> bool: return r.tag_name != "v0.1.0-rc7")
	server.publish(JSON.stringify(older), "W/\"fixture-3\"")
	r = await _launch(server, "0.1.0-rc6", T0 + 75 * 3600)
	_check("launch 6 (rc8 and rc7 gone): the cached rc8 shows at once, then the fresh answer withdraws it",
		r.notices.size() == 1 and r.notices[0].tag == "v0.1.0-rc8" and r.withdrawn == 1 and r.status == "200 ok"
		and UpdateCheck.load_state(STATE).latest_tag == "v0.1.0-rc6", str(r))
	r.checker.queue_free()
	# Another build (rc8) with rc6's cache: the cache is not for it, so a fresh request without the ETag, nothing to say.
	r = await _launch(server, "0.1.0-rc8", T0 + 76 * 3600)
	_check("launch 7 (running rc8, cache from rc6): fresh request without ETag, no notice", server.requests.size() == 5
		and not server.requests[4].contains("If-None-Match") and r.status == "200 ok" and r.notices.is_empty() and r.withdrawn == 0
		and UpdateCheck.load_state(STATE).for_version == "0.1.0-rc8", str(r))
	r.checker.queue_free()
	# GitHub answers an error status (rate limit): recorded, waits a day, no notice.
	server.status_code = 403
	_remove(STATE)
	r = await _launch(server, "0.1.0-rc6", T0 + 100 * 3600)
	st = UpdateCheck.load_state(STATE)
	_check("http 403: recorded, the next check waits a day, no notice", r.status == "http 403" and r.notices.is_empty()
		and st.last_check_unix == T0 + 100 * 3600 and st.last_status == "http 403", str(r) + " " + str(st))
	r.checker.queue_free()
	r = await _launch(server, "0.1.0-rc6", T0 + 101 * 3600)
	_check("an hour after a 403: no request", r.status == "" and server.requests.size() == 6, str(server.requests.size()))
	r.checker.queue_free()
	server.status_code = 200
	# A peer that accepts and never answers (UI-16-R1 review): the timeout fires, frames keep running, no notice,
	# and the next launch tries again. With use_threads this would hang the process on the thread join.
	server.silent = true
	_remove(STATE)
	r = await _launch(server, "0.1.0-rc6", T0 + 130 * 3600, "", 2.0)
	st = UpdateCheck.load_state(STATE)
	_check("silent server: transport error %d (timeout) after about 2 s, frames kept running, retry next launch" % HTTPRequest.RESULT_TIMEOUT,
		r.status == "transport error %d" % HTTPRequest.RESULT_TIMEOUT and r.elapsed_ms >= 1500 and r.elapsed_ms < 8000
		and r.frames >= 60 and r.notices.is_empty() and st.last_check_unix == 0, "%s elapsed %d ms, %d frames" % [str(r), r.elapsed_ms, r.frames])
	r.checker.queue_free()
	server.silent = false
	server.stop()
	# Offline (a closed port): no notice, the cache keeps no date so the next launch tries again, no engine error.
	_remove(STATE)
	var closed := TCPServer.new()
	closed.listen(0, "127.0.0.1")
	var closed_port := closed.get_local_port()
	closed.stop()
	r = await _launch(server, "0.1.0-rc6", T0 + 150 * 3600, "http://127.0.0.1:%d/releases" % closed_port)
	st = UpdateCheck.load_state(STATE)
	_check("offline: transport error reported, no notice, next launch checks again", r.status.begins_with("transport error")
		and r.notices.is_empty() and st.last_check_unix == 0 and st.last_status == r.status, str(r) + " " + str(st))
	r.checker.queue_free()
	await process_frame


## One launch of the checker; waits for its request (if any) while serving the fake API.
func _launch(server: FakeReleases, version: String, now: int, url := "", timeout_s := 0.0) -> Dictionary:
	var out := { notices = [], withdrawn = 0, status = "", checker = null, frames = 0, elapsed_ms = 0 }
	var checker := UpdateChecker.new()
	checker.url = url if url != "" else server.url()
	checker.state_path = STATE
	checker.running_version = version
	checker.now_unix = now
	if timeout_s > 0.0:
		checker.timeout_s = timeout_s
	checker.update_available.connect(func(info: Dictionary) -> void: out.notices.append(info))
	checker.update_withdrawn.connect(func() -> void: out.withdrawn += 1)
	checker.check_finished.connect(func(status: String) -> void: out.status = status)
	out.checker = checker
	root.add_child(checker)
	await process_frame
	var started := Time.get_ticks_msec()
	# Wall-clock cap (frame counts are not seconds headless): 15 s, past the longest timeout used here.
	while checker.get_node_or_null("Request") != null and Time.get_ticks_msec() - started < 15000:
		server.poll()
		await process_frame
		out.frames += 1
	out.elapsed_ms = Time.get_ticks_msec() - started
	server.poll()
	await process_frame
	return out


static func _remove(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
