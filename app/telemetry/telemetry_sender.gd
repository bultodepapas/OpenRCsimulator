## TELEM-06: one HTTPS POST at a time. Like the update checker, the request is unthreaded (a silent peer can then
## never hold a worker thread or delay quitting), but its 5 s deadline is monotonic wall time, redirects are never
## followed and the answer is capped at 4 KiB. finished() reports the HTTP status, or 0 for any transport failure
## or timeout (retryable); a redirect or oversized answer is reported as a non-retryable status. cancel() is
## silent: a cancelled request never reports.
extends Node

signal finished(serial: int, status: int, retry_after_s: float)

const TIMEOUT_MS := 5000
const MAX_RESPONSE_BYTES := 4096
const HEADERS: PackedStringArray = ["Content-Type: application/json", "Accept: application/json",
	"User-Agent: OpenRC-Telemetry/1"]
## Statuses reported for answers that are not retryable transport failures.
const REDIRECT_REFUSED := 310
const RESPONSE_TOO_LARGE := 413

var _http: HTTPRequest
var _serial := -1
var _deadline_msec := 0
## Monotonic milliseconds; tests replace it.
var clock_msec: Callable = func() -> int: return Time.get_ticks_msec()


func _init() -> void:
	name = "TelemetrySender"
	set_process(false)


func busy() -> bool:
	return _http != null


func send(endpoint: String, body: PackedByteArray, serial: int) -> bool:
	if busy() or not is_inside_tree():
		return false
	_http = HTTPRequest.new()
	_http.name = "Request"
	_http.use_threads = false
	_http.timeout = 0.0 # the deadline below is monotonic wall time
	_http.max_redirects = 0
	_http.accept_gzip = false
	_http.body_size_limit = MAX_RESPONSE_BYTES
	add_child(_http)
	_http.request_completed.connect(_on_completed.bind(serial))
	_serial = serial
	_deadline_msec = int(clock_msec.call()) + TIMEOUT_MS
	if _http.request_raw(endpoint, HEADERS, HTTPClient.METHOD_POST, body) != OK:
		_finish(serial, 0, -1.0)
		return true
	set_process(true)
	return true


func cancel() -> void:
	if _http != null:
		_http.cancel_request()
		_http.queue_free()
	_http = null
	_serial = -1
	set_process(false)


func _process(_delta: float) -> void:
	if _http == null:
		set_process(false)
		return
	if int(clock_msec.call()) >= _deadline_msec:
		var serial := _serial
		cancel()
		finished.emit(serial, 0, -1.0)


func _exit_tree() -> void:
	cancel() # quitting drops the request; there is no final flush


func _on_completed(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray, serial: int) -> void:
	if serial != _serial:
		return # a cancelled request's late answer
	match result:
		HTTPRequest.RESULT_SUCCESS:
			_finish(serial, code, retry_after(headers))
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			_finish(serial, REDIRECT_REFUSED, -1.0)
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			_finish(serial, RESPONSE_TOO_LARGE, -1.0)
		_:
			_finish(serial, 0, -1.0)


func _finish(serial: int, status: int, retry_after_s: float) -> void:
	if _http != null:
		_http.queue_free()
	_http = null
	_serial = -1
	set_process(false)
	finished.emit(serial, status, retry_after_s)


## Delay-seconds Retry-After only (an HTTP-date is ignored: the computed backoff applies). -1 when absent.
static func retry_after(headers: PackedStringArray) -> float:
	for header: String in headers:
		var colon := header.find(":")
		if colon <= 0 or header.substr(0, colon).strip_edges().to_lower() != "retry-after":
			continue
		var value := header.substr(colon + 1).strip_edges()
		if value.is_valid_int() and value.length() <= 7 and int(value) >= 0:
			return float(int(value))
	return -1.0
