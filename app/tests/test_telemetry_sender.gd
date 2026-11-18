# TELEM-06: the real HTTPRequest path of the telemetry sender against a local collector: exact body and headers,
# status/Retry-After reporting, no redirect following, a silent peer timing out on the monotonic deadline, silent
# cancellation and a refused connection. Loopback only.
# Run: godot --headless --path . --script res://tests/test_telemetry_sender.gd
extends SceneTree

const Sender := preload("res://telemetry/telemetry_sender.gd")
const Collector := preload("res://tests/fake_telemetry_collector.gd")

var _failures := 0
var _results: Array[Array] = []
var _clock_offset := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	await process_frame
	_parsing()
	var collector := Collector.new()
	_check("collector listens on loopback", collector.start())
	var sender := Sender.new()
	sender.clock_msec = func() -> int: return Time.get_ticks_msec() + _clock_offset
	sender.finished.connect(func(serial: int, status: int, retry_after_s: float) -> void:
		_results.append([serial, status, retry_after_s]))
	root.add_child(sender)
	var body := "{\"schema_version\":1,\"x\":\"é\"}".to_utf8_buffer()

	_check("send starts", sender.send(collector.url(), body, 1) and sender.busy())
	_check("one request at a time", not sender.send(collector.url(), body, 99))
	await _until(collector, 1)
	_check("202 is reported", _results.back() == [1, 202, -1.0], str(_results))
	var request: Dictionary = collector.requests.back()
	_check("the exact body bytes arrive", request.body == body)
	var head: String = request.head
	_check("POST with JSON and a fixed user agent, no compression offer", head.begins_with("POST /v1/batches HTTP/1.1")
		and head.contains("Content-Type: application/json") and head.contains("User-Agent: OpenRC-Telemetry/1")
		and not head.to_lower().contains("accept-encoding"), head)

	collector.status_code = 429
	collector.extra_headers = PackedStringArray(["Retry-After: 120"])
	sender.send(collector.url(), body, 2)
	await _until(collector, 2)
	_check("429 reports its Retry-After", _results.back() == [2, 429, 120.0], str(_results.back()))

	collector.status_code = 302
	collector.extra_headers = PackedStringArray(["Location: " + collector.url("/elsewhere")])
	sender.send(collector.url(), body, 3)
	await _until(collector, 3)
	_check("a redirect is refused, never followed", _results.back() == [3, Sender.REDIRECT_REFUSED, -1.0]
		and collector.requests.size() == 3, str(_results.back()))

	collector.extra_headers = PackedStringArray()
	collector.status_code = 202
	collector.silent = true
	sender.send(collector.url(), body, 4)
	for i: int in 20:
		collector.poll()
		await process_frame
	_check("a silent peer has not answered", _results.size() == 3)
	_clock_offset = Sender.TIMEOUT_MS + 1
	await process_frame
	await process_frame
	_check("the monotonic deadline reports a transport failure", _results.back() == [4, 0, -1.0] and not sender.busy(),
		str(_results.back()))
	_clock_offset = 0
	collector.silent = false

	sender.send(collector.url(), body, 5)
	sender.cancel()
	for i: int in 40:
		collector.poll()
		await process_frame
	_check("cancel is silent", _results.size() == 4 and not sender.busy(), str(_results))

	var refused := TCPServer.new()
	refused.listen(0, "127.0.0.1")
	var closed_port := refused.get_local_port()
	refused.stop()
	sender.send("http://127.0.0.1:%d/v1/batches" % closed_port, body, 6)
	# Windows retries a refused loopback connect for ~2 s; the 5 s deadline bounds it either way.
	var started := Time.get_ticks_msec()
	while _results.size() <= 4 and Time.get_ticks_msec() - started < 8000:
		await process_frame
	_check("a refused connection is a retryable transport failure", _results.size() == 5 and _results.back() == [6, 0, -1.0],
		str(_results))

	collector.stop()
	sender.queue_free()
	print("all telemetry sender checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _until(collector: RefCounted, count: int) -> void:
	for i: int in 600:
		collector.poll()
		if _results.size() >= count:
			return
		await process_frame


func _parsing() -> void:
	var cases := [
		[["Retry-After: 30"], 30.0],
		[["content-type: x", "retry-after:  5 "], 5.0],
		[["Retry-After: Wed, 21 Oct 2015 07:28:00 GMT"], -1.0],
		[["Retry-After: -3"], -1.0],
		[["Retry-After: 99999999"], -1.0],
		[[], -1.0],
	]
	for c: Array in cases:
		_check("Retry-After %s -> %s" % [str(c[0]), c[1]], Sender.retry_after(PackedStringArray(c[0])) == c[1])
