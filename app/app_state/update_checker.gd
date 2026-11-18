# Update notice (MENU-PLAN UI-16): the one network request of the interactive route. Added by app_root after the
# preferences are read (never on the direct route, never in a development run unless OPENRC_UPDATE_URL says so,
# never when [updates] check=false). It announces a cached newer release at once, asks GitHub at most once a day
# (app_state/update_check.gd owns the rules and the cache file) and never blocks Home: a timeout, an offline
# machine or a bad answer leave one line on the console and no notice.
# DT-UPD-04a: `automatic` false (the player turned automatic checks off) asks and announces nothing until
# check_now(); set_channel() switches between stable and preview releases; status() feeds Settings.
extends Node

const UpdateCheck := preload("res://app_state/update_check.gd")
const BuildInfo := preload("res://app_state/build_info.gd")

## A release newer than the running build is published and not hidden (UpdateCheck.notice): once per tag.
signal update_available(info: Dictionary)
## The release announced earlier no longer applies (a fresh answer says nothing is newer): Home hides the card.
signal update_withdrawn
## The check finished (`status` as stored in the cache: "200 ok", "304 not modified", "http 403", ...).
signal check_finished(status: String)
## A request started (automatic, Check now or a channel change); check_finished follows.
signal check_started

var url: String = UpdateCheck.RELEASES_URL
## The player's channel choice (UpdateCheck.CHANNELS); "" follows the running build.
var channel := ""
## False: no request or announcement at start-up; only check_now() asks.
var automatic := true
## PACKAGE_SUFFIXES key whose size Home shows; "" takes this machine's (UpdateCheck.platform_key).
var platform := ""
## Seconds after any request before check_now()/a channel change may ask again; tests shorten it.
var cooldown_s: float = UpdateCheck.MANUAL_COOLDOWN_S
var _last_request_msec := -1
var _effective_channel := ""
var state_path: String = UpdateCheck.STATE_PATH
## "" takes the running build's SemVer (app_state/build_info.gd); tests name one.
var running_version := ""
## -1 reads the system clock; tests set a time.
var now_unix := -1
## Seconds of processed frames before a stalled answer counts as a transport error; tests shorten it. Counted by
## _process with each frame capped at MAX_FRAME_S: a wall clock would expire during the long first frames of a
## cold start (shader compilation, scenery) before the request had a chance to run (seen on an exported build).
var timeout_s: float = UpdateCheck.TIMEOUT_S
const MAX_FRAME_S := 0.05
var _active_s := 0.0
var state: Dictionary = UpdateCheck.default_state()
var _announced_tag := ""
var _http: HTTPRequest


func _init() -> void:
	name = "UpdateChecker"
	set_process(false)


func _ready() -> void:
	if running_version == "":
		running_version = BuildInfo.current().parsed.semver
	if platform == "":
		platform = UpdateCheck.platform_key(OS.get_name(), Engine.get_architecture_name())
	_effective_channel = UpdateCheck.effective_channel(channel, UpdateCheck.parse_version(running_version))
	# Another build's or channel's cache never answers for this one.
	state = UpdateCheck.state_for(UpdateCheck.load_state(state_path), running_version, _effective_channel)
	if not automatic:
		return
	_announce()
	if UpdateCheck.due(state, _now()):
		_start()


## Check now: asks at once unless a request is running or the previous one began less than cooldown_s ago.
## Returns whether a request started.
func check_now() -> bool:
	if is_checking() or not cooldown_over():
		return false
	_start()
	return true


func is_checking() -> bool:
	return _http != null


func cooldown_over() -> bool:
	return _last_request_msec < 0 or Time.get_ticks_msec() - _last_request_msec >= int(cooldown_s * 1000.0)


## Turning automatic checks on announces the cached release and asks when a check is due; off stops future
## automatic requests (a running request still finishes).
func set_automatic(enabled: bool) -> void:
	if enabled == automatic:
		return
	automatic = enabled
	if enabled and is_inside_tree():
		_announce()
		if UpdateCheck.due(state, _now()) and not is_checking():
			_start()


## A new channel choice starts from a fresh answer for that channel (the old card is withdrawn when it does not
## apply) and asks at once when automatic checks are on and the cooldown allows; otherwise Check now asks.
func set_channel(choice: String) -> void:
	channel = choice if choice in UpdateCheck.CHANNELS else ""
	if not is_inside_tree():
		return
	var effective := UpdateCheck.effective_channel(channel, UpdateCheck.parse_version(running_version))
	if effective == _effective_channel:
		return
	if is_checking(): # its answer belongs to the old channel
		_http.cancel_request()
		_http.queue_free()
		_http = null
		set_process(false)
	_effective_channel = effective
	state = UpdateCheck.state_for(state, running_version, effective)
	UpdateCheck.save_state(state_path, state)
	_announce()
	if automatic and cooldown_over():
		_start()


## Settings' view: UpdateCheck.status() plus whether a request is running.
func status() -> Dictionary:
	var out := UpdateCheck.status(running_version, state, _effective_channel)
	out.checking = is_checking()
	return out


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
	_http.timeout = 0.0 # the engine's timeout is wall clock; ours counts processed frames (_process)
	_active_s = 0.0
	_last_request_msec = Time.get_ticks_msec()
	set_process(true)
	_http.body_size_limit = UpdateCheck.MAX_BODY_BYTES
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	var err := _http.request(url, UpdateCheck.headers(state.etag, running_version, OS.get_name()))
	if err != OK:
		_finish("request error %d" % err, false)
		return
	check_started.emit()


func _process(delta: float) -> void:
	if _http == null:
		set_process(false)
		return
	_active_s += minf(delta, MAX_FRAME_S)
	if _active_s >= timeout_s:
		_http.cancel_request() # unthreaded: a plain socket close, nothing to join
		_finish("transport error %d" % HTTPRequest.RESULT_TIMEOUT, false)


func _on_completed(result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish("transport error %d" % result, false)
		return
	if code == 304:
		state.last_success_unix = _now()
		_finish("304 not modified", true) # the cached latest release still stands
		return
	if code != 200:
		_finish("http %d" % code, true) # GitHub answered (rate limit, moved, down): be polite and wait a day
		return
	var releases: Variant = UpdateCheck.parse_response(body)
	if releases == null:
		_finish("unreadable answer", false)
		return
	var latest := UpdateCheck.newest(releases, UpdateCheck.parse_version(running_version), _effective_channel)
	var package: Dictionary = latest.get("packages", {}).get(platform, {})
	state.etag = UpdateCheck.etag_of(response_headers)
	state.latest_tag = latest.get("tag", "")
	state.latest_url = latest.get("url", "")
	state.latest_published = latest.get("published", "")
	state.latest_prerelease = latest.get("prerelease", false) == true
	state.latest_package = str(package.get("name", ""))
	state.latest_size = int(package.get("size", 0))
	state.latest_digest = str(package.get("digest", ""))
	state.for_version = running_version
	state.for_channel = _effective_channel
	state.last_success_unix = _now()
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
	set_process(false)
	if not checked:
		print("update check: ", status)
	_announce()
	check_finished.emit(status)


func _announce() -> void:
	var info := UpdateCheck.notice(running_version, state, _effective_channel)
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
