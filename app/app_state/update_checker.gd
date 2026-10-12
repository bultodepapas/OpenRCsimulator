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
## The check finished (`status` as stored in the cache: "200 ok", "304 not modified", "http 403", ...).
signal check_finished(status: String)

var url: String = UpdateCheck.RELEASES_URL
var state_path: String = UpdateCheck.STATE_PATH
## "" takes the running build's SemVer (app_state/build_info.gd); tests name one.
var running_version := ""
## -1 reads the system clock; tests set a time.
var now_unix := -1
var state: Dictionary = UpdateCheck.default_state()
var _announced_tag := ""
var _http: HTTPRequest


func _init() -> void:
	name = "UpdateChecker"


func _ready() -> void:
	if running_version == "":
		running_version = BuildInfo.current().parsed.semver
	state = UpdateCheck.load_state(state_path)
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
	_http.use_threads = true # the TLS handshake and the download stay off the frame that draws Home
	_http.timeout = UpdateCheck.TIMEOUT_S
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
		_finish("http %d" % code, false)
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
	_finish("200 ok", true)


## `checked` true means GitHub answered: the next check waits a day. A failure keeps the previous date so the next
## launch tries again.
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
	if info.is_empty() or info.tag == _announced_tag:
		return
	_announced_tag = info.tag
	update_available.emit(info)


func _now() -> int:
	return now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
