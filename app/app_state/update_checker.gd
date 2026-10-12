# Update notice (MENU-PLAN UI-16): the one network request of the interactive route. Added by app_root after the
# preferences are read (never on the direct route, never in a development run unless OPENRC_UPDATE_URL says so,
# never when [updates] check=false). It announces a cached newer release at once, asks GitHub at most once a day
# (app_state/update_check.gd owns the rules and the cache file) and never blocks Home: a timeout, an offline
# machine or a bad answer leave one line on the console and no notice.
extends Node

const UpdateCheck := preload("res://app_state/update_check.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

## A release newer than the running build is published and not hidden (UpdateCheck.notice): once per tag.
signal update_available(info: Dictionary)
## The release announced earlier no longer applies (a fresh answer says nothing is newer): Home hides the card.
signal update_withdrawn
## The check finished (`status` as stored in the cache: "200 ok", "304 not modified", "http 403", ...).
signal check_finished(status: String)

var url: String = UpdateCheck.RELEASES_URL
var state_path: String = UpdateCheck.STATE_PATH
## "" takes the running build's SemVer (app_state/build_info.gd); tests name one.
var running_version := ""
## -1 reads the system clock; tests set a time.
var now_unix := -1
## Seconds before a stalled answer counts as a transport error; tests shorten it.
var timeout_s: float = UpdateCheck.TIMEOUT_S
var state: Dictionary = UpdateCheck.default_state()
var _announced_tag := ""
var _http: HTTPRequest


func _init() -> void:
	name = "UpdateChecker"


func _ready() -> void:
	if running_version == "":
		running_version = BuildInfo.current().parsed.semver
	state = UpdateCheck.state_for(UpdateCheck.load_state(state_path), running_version) # another build's cache never answers for this one
	_announce()
	if UpdateCheck.due(state, _now()):
		_start()


## Remember that the player does not want to hear about `tag` again (a newer one still shows).
func hide(tag: String) -> void:
	state.hidden_tag = tag
	UpdateCheck.save_state(state_path, state)


func _start() -> void:
	_http = HTTPRequest.new()
	_http.name = "Request"
	# Never use_threads: the worker reads in blocking mode, so a peer that accepts and then stays silent makes the
	# 10 s timeout (and quitting the app) wait forever on the thread join (UI-16-R1 review). Unthreaded, HTTPRequest
	# resolves, handshakes and reads a little per frame: Home keeps drawing and the timeout really fires.
	_http.use_threads = false
	_http.timeout = timeout_s
	_http.body_size_limit = UpdateCheck.MAX_BODY_BYTES
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	var err := _http.request(url, UpdateCheck.headers(state.etag, running_version, OS.get_name()))
	if err != OK:
		_finish("request error %d" % err, false)


func _on_completed(result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish("transport error %d" % result, false)
		return
	if code == 304:
		_finish("304 not modified", true) # the cached latest release still stands
		return
	if code != 200:
		_finish("http %d" % code, true) # GitHub answered (rate limit, moved, down): be polite and wait a day
		return
	var releases: Variant = UpdateCheck.parse_response(body)
	if releases == null:
		_finish("unreadable answer", false)
		return
	var latest := UpdateCheck.newest(releases, UpdateCheck.parse_version(running_version))
	state.etag = UpdateCheck.etag_of(response_headers)
	state.latest_tag = latest.get("tag", "")
	state.latest_url = latest.get("url", "")
	state.latest_published = latest.get("published", "")
	state.latest_prerelease = latest.get("prerelease", false) == true
	state.for_version = running_version
	_finish("200 ok", true)


## `checked` true means the server answered (200, 304 or an error status): the next check waits a day. A transport
## failure keeps the previous date so the next launch tries again.
func _finish(status: String, checked: bool) -> void:
	state.last_status = status
	if checked:
		state.last_check_unix = _now()
	UpdateCheck.save_state(state_path, state) # a failed save only means one more check next time
	if _http != null:
		_http.queue_free()
		_http = null
	if not checked:
		print("update check: ", status)
	_announce()
	check_finished.emit(status)


func _announce() -> void:
	var info := UpdateCheck.notice(running_version, state)
	if info.is_empty():
		if _announced_tag != "":
			_announced_tag = ""
			update_withdrawn.emit()
		return
	if info.tag == _announced_tag:
		return
	_announced_tag = info.tag
	update_available.emit(info)


func _now() -> int:
	return now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
