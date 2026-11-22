## TELEM-06: the sealed-batch queue and send budget (research/telemetry/reference.py ClientModel). Memory only:
## at most 32 batches / 256 KiB, each kept at most ten minutes, oldest evicted first. One request at a time, normal
## sends at most every 60 s (+0..10 s jitter), up to five retries with full-jitter backoff, and a fixed 3,600 s
## budget of 90 attempts / 256 KiB anchored at the first counted request. The budget survives purge() (turning
## telemetry off and on again) and resets only with a new process. Time is injected (seconds, monotonic).
extends RefCounted

const MAX_BATCHES := 32
const MAX_BYTES := 262144
const TTL_S := 600.0
const TTL_USEC := int(TTL_S * 1000000.0)
const NORMAL_INTERVAL_S := 60.0
const NORMAL_JITTER_S := 10.0
const MAX_RETRIES := 5
const BACKOFF_BASE_S := 5.0
const BACKOFF_CAP_S := 300.0
const HOUR_S := 3600.0
const HOUR_ATTEMPTS := 90
const HOUR_BYTES := 262144

## Outcomes of complete().
const ACCEPTED := "accepted"
const RETRY := "retry"
const DROPPED := "dropped"
const SUSPEND := "suspend"
const STALE := "stale"

## Each item: {body: PackedByteArray, generation: int, created: float, observed: float, due: float, retries: int, serial: int}
var items: Array[Dictionary] = []
var active_serial := -1
var hour_start := -1.0
var hour_attempts := 0
var hour_bytes := 0
var next_normal := 0.0
var sent_ok := 0
var dropped := 0
var _serial := 0
var _oldest_observed := INF
## Uniform [0, 1) source; tests replace it.
var random: Callable = func() -> float: return randf()


func push(body: PackedByteArray, generation: int, now: float, observed := -1.0) -> void:
	expire(now)
	if observed < 0.0:
		observed = now
	if _deadline_passed(observed, now):
		dropped += 1
		return
	while not items.is_empty() and (items.size() >= MAX_BATCHES or bytes() + body.size() > MAX_BYTES):
		var victim: Dictionary = items.pop_front()
		dropped += 1
		if victim.serial == active_serial:
			active_serial = -1 # the owner cancels that request (see is_active)
	_serial += 1
	items.append({"body": body, "generation": generation, "created": now, "observed": observed,
		"due": now, "retries": 0, "serial": _serial})
	_oldest_observed = minf(_oldest_observed, observed)


func bytes() -> int:
	var total := 0
	for item: Dictionary in items:
		total += item.body.size()
	return total


func expire(now: float) -> void:
	# Activity summaries can seal later than newer observations. Expire by age, preserving FIFO delivery.
	if not _deadline_passed(_oldest_observed, now):
		return
	_oldest_observed = INF
	for index: int in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		if _deadline_passed(float(item.observed), now):
			items.remove_at(index)
			dropped += 1
			if item.serial == active_serial:
				active_serial = -1
		else:
			_oldest_observed = minf(_oldest_observed, float(item.observed))


## The next item to send now for `generation`, counting it against the budget, or {} (nothing due, a request
## already active, cadence or budget not yet available).
func begin(now: float, generation: int) -> Dictionary:
	expire(now)
	if active_serial >= 0 or items.is_empty():
		return {}
	var item: Dictionary = items[0]
	if int(item.generation) != generation:
		return {}
	if now < float(item.due) or (int(item.retries) == 0 and now < next_normal):
		return {}
	if hour_start < 0.0 or now - hour_start >= HOUR_S:
		hour_start = now
		hour_attempts = 0
		hour_bytes = 0
	if hour_attempts >= HOUR_ATTEMPTS or hour_bytes + item.body.size() > HOUR_BYTES:
		return {}
	hour_attempts += 1
	hour_bytes += item.body.size()
	active_serial = int(item.serial)
	if int(item.retries) == 0:
		next_normal = now + NORMAL_INTERVAL_S + NORMAL_JITTER_S * clampf(float(random.call()), 0.0, 1.0)
	return item


func is_active(serial: int) -> bool:
	return serial >= 0 and serial == active_serial


## `status` is the HTTP status, or 0 for a transport failure/timeout. `retry_after_s` < 0 means none was given.
func complete(serial: int, status: int, now: float, retry_after_s: float = -1.0) -> String:
	if serial < 0 or serial != active_serial:
		return STALE
	active_serial = -1
	var index := _index_of(serial)
	if index < 0:
		return STALE
	var item: Dictionary = items[index]
	if _deadline_passed(float(item.observed), now):
		items.remove_at(index)
		dropped += 1
		return DROPPED
	if status == 202:
		items.remove_at(index)
		sent_ok += 1
		return ACCEPTED
	if status in [401, 403, 410]:
		return SUSPEND
	var retryable := status == 0 or status == 408 or status == 429 or (status >= 500 and status <= 599)
	if retryable and int(item.retries) < MAX_RETRIES:
		var delay := maxf(1.0, minf(BACKOFF_CAP_S, BACKOFF_BASE_S * pow(2.0, int(item.retries))) \
			* clampf(float(random.call()), 0.0, 1.0))
		if is_finite(retry_after_s) and retry_after_s >= 0.0:
			delay = maxf(delay, retry_after_s)
		item.retries = int(item.retries) + 1
		item.due = now + delay
		if not _deadline_passed(float(item.observed), float(item.due)):
			return RETRY
	items.remove_at(index)
	dropped += 1
	return DROPPED


## Turning telemetry off: every pending byte goes; the hourly budget does not reset.
func purge() -> void:
	items.clear()
	active_serial = -1
	_oldest_observed = INF


func _deadline_passed(created: float, now: float) -> bool:
	# The monotonic clock has microsecond resolution. Allow half a microsecond for conversion to seconds.
	return now - created >= TTL_S - 0.0000005


func _index_of(serial: int) -> int:
	for index: int in items.size():
		if int(items[index].serial) == serial:
			return index
	return -1
