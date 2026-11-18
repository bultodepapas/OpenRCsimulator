# TELEM-06: the memory-only queue and send budget, with injected time and jitter (research/telemetry/reference.py).
# Run: godot --headless --path . --script res://tests/test_telemetry_queue.gd
extends SceneTree

const Queue := preload("res://telemetry/telemetry_queue.gd")

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_bounds()
	_cadence_and_budget()
	_retries()
	_statuses()
	print("all telemetry queue checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _queue(jitter := 0.5) -> Queue:
	var q := Queue.new()
	q.random = func() -> float: return jitter
	return q


func _body(size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	return out


func _bounds() -> void:
	var q := _queue()
	for i: int in 40:
		q.push(_body(100), 1, float(i))
	_check("at most 32 batches, oldest evicted", q.items.size() == 32 and q.items[0].created == 8.0 and q.dropped == 8)
	q = _queue()
	for i: int in 9:
		q.push(_body(32768), 1, 0.0)
	_check("at most 256 KiB", q.bytes() <= Queue.MAX_BYTES and q.items.size() == 8, str(q.bytes()))
	q = _queue()
	q.push(_body(10), 1, 0.0)
	q.push(_body(10), 1, 100.0)
	q.expire(600.0)
	_check("a batch expires at ten minutes", q.items.size() == 1 and q.items[0].created == 100.0)
	q = _queue()
	q.push(_body(10), 1, 0.0)
	var item := q.begin(0.0, 1)
	q.push(_body(10), 1, 700.0)
	_check("expiring the active batch releases the request slot", not q.is_active(int(item.serial)) and q.items.size() == 1)


func _cadence_and_budget() -> void:
	var q := _queue(0.0)
	q.push(_body(100), 1, 0.0)
	q.push(_body(100), 1, 0.0)
	var first := q.begin(0.0, 1)
	_check("first send is immediate", not first.is_empty())
	_check("one request at a time", q.begin(0.0, 1).is_empty())
	_check("accepted", q.complete(int(first.serial), 202, 1.0) == Queue.ACCEPTED and q.sent_ok == 1)
	_check("normal cadence waits 60 s", q.begin(59.0, 1).is_empty() and not q.begin(60.0, 1).is_empty())
	q = _queue(1.0)
	q.push(_body(100), 1, 0.0)
	q.push(_body(100), 1, 0.0)
	q.complete(int(q.begin(0.0, 1).serial), 202, 0.0)
	_check("jitter adds up to 10 s", q.begin(69.0, 1).is_empty() and not q.begin(70.0, 1).is_empty())
	_check("another generation's batch is never sent", _queue_with_generation(1).begin(0.0, 2).is_empty())
	q = _queue(0.0)
	var sent := 0
	var now := 0.0
	for i: int in 100:
		q.push(_body(100), 1, now)
		var it := q.begin(now, 1)
		if not it.is_empty():
			sent += 1
			q.complete(int(it.serial), 202, now)
		now += 30.0
	# 100 pushes over 3,000 s at a 60 s cadence: ~50 sends, never above the 90-attempt hour budget.
	_check("hour attempts never exceed 90", q.hour_attempts <= Queue.HOUR_ATTEMPTS and sent > 0, str(q.hour_attempts))
	q = _queue(0.0)
	for i: int in 10:
		q.push(_body(32768), 1, 0.0)
	var bytes_sent := 0
	now = 0.0
	for i: int in 20:
		var it := q.begin(now, 1)
		if not it.is_empty():
			bytes_sent += it.body.size()
			q.complete(int(it.serial), 202, now)
		now += 61.0
	_check("hour bytes never exceed 256 KiB within a fixed window", bytes_sent <= Queue.HOUR_BYTES * 2 and q.hour_bytes <= Queue.HOUR_BYTES, str(bytes_sent))
	q = _queue(0.0)
	q.push(_body(100), 1, 0.0)
	q.complete(int(q.begin(0.0, 1).serial), 202, 0.0)
	var attempts := q.hour_attempts
	q.purge()
	_check("turning off keeps the hourly budget", q.hour_attempts == attempts and q.items.is_empty())


func _queue_with_generation(generation: int) -> Queue:
	var q := _queue()
	q.push(_body(10), generation, 0.0)
	return q


func _retries() -> void:
	var q := _queue(1.0)
	q.push(_body(10), 1, 0.0)
	var delays: Array[float] = []
	var now := 0.0
	for i: int in 6:
		var it := q.begin(now, 1)
		if it.is_empty():
			break
		var before: float = now
		var outcome := q.complete(int(it.serial), 503, now)
		if outcome != Queue.RETRY:
			break
		now = float(q.items[0].due)
		delays.append(now - before)
	_check("full-jitter backoff caps 5·2^n (5, 10, 20, 40, 80 s)", delays == [5.0, 10.0, 20.0, 40.0, 80.0], str(delays))
	_check("the sixth failure drops the batch", q.items.is_empty() and q.dropped == 1)
	q = _queue(0.0)
	q.push(_body(10), 1, 0.0)
	q.complete(int(q.begin(0.0, 1).serial), 0, 0.0)
	_check("a zero jitter still waits at least 1 s", q.items[0].due == 1.0)
	q = _queue(0.0)
	q.push(_body(10), 1, 0.0)
	_check("Retry-After within the lifetime is honored", q.complete(int(q.begin(0.0, 1).serial), 429, 0.0, 120.0) == Queue.RETRY
		and q.items[0].due == 120.0)
	q = _queue(0.0)
	q.push(_body(10), 1, 0.0)
	_check("Retry-After beyond the ten-minute lifetime drops instead of retrying early",
		q.complete(int(q.begin(0.0, 1).serial), 429, 0.0, 900.0) == Queue.DROPPED and q.items.is_empty())
	q = _queue(0.5)
	q.push(_body(10), 1, 0.0)
	q.push(_body(10), 1, 0.0)
	var it := q.begin(0.0, 1)
	q.complete(int(it.serial), 500, 0.0)
	_check("a retry is not held back by the normal cadence", not q.begin(2.5, 1).is_empty())


func _statuses() -> void:
	for status: int in [400, 404, 409, 413, 415, 422, 310, 200, 204]:
		var q := _queue()
		q.push(_body(10), 1, 0.0)
		_check("status %d drops the batch" % status, q.complete(int(q.begin(0.0, 1).serial), status, 0.0) == Queue.DROPPED and q.items.is_empty())
	for status: int in [401, 403, 410]:
		var q := _queue()
		q.push(_body(10), 1, 0.0)
		_check("status %d suspends" % status, q.complete(int(q.begin(0.0, 1).serial), status, 0.0) == Queue.SUSPEND)
	for status: int in [0, 408, 429, 500, 599]:
		var q := _queue()
		q.push(_body(10), 1, 0.0)
		_check("status %d retries" % status, q.complete(int(q.begin(0.0, 1).serial), status, 0.0) == Queue.RETRY)
	var q := _queue()
	q.push(_body(10), 1, 0.0)
	var it := q.begin(0.0, 1)
	q.purge()
	_check("a late answer after purge is stale", q.complete(int(it.serial), 202, 1.0) == Queue.STALE and q.sent_ok == 0)
