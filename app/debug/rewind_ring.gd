# PT1h-R9: rewindable flight history for the debug bridge ("temporal debugging", after Mark Wesley, GDC 2013).
# While armed, the bridge stores the session's exact physics checkpoint (FlightSession.checkpoint(), the same
# boundary flight logs replay from) every `every_ticks` ticks into a bounded ring. `rewind` restores one through
# FlightSession.restore_checkpoint(): physics, inputs, weather, failures and contacts return bit-exactly; the
# presentation resets as on a restart (camera history, smoke, particles; a running flight log stops). A reset of the
# simulation clock (restart, crash auto-restart) starts a new attempt, so the moments before a crash stay reachable.
# Restoring cuts the timeline: later snapshots of that attempt, and later attempts, are dropped.
# Guide: tools/debug/README.md#rewind-pt1h-r9.
extends RefCounted

var armed := false
var every_ticks := 60
var capacity := 240
var refused := 0 # checkpoints the session declined (not ready, crash transition, unsupported state)
var capture_usec := 0.0 # smoothed cost of one checkpoint
var _entries: Array[Dictionary] = [] # {attempt, tick, time_s, height_m, speed_mps, snapshot}
var _attempt := 0
var _session_id := 0
var _session_ref: WeakRef
var _last_tick := -1
var _restoring := false


func arm(every: int, keep: int) -> void:
	armed = true
	every_ticks = maxi(1, every)
	capacity = clampi(keep, 1, 100000)
	while _entries.size() > capacity:
		_entries.pop_front()


func disarm() -> void:
	armed = false
	_unbind_session()
	_session_id = 0
	clear()


func clear() -> void:
	_entries.clear()
	_attempt = 0
	_last_tick = -1
	refused = 0
	capture_usec = 0.0


func size() -> int:
	return _entries.size()


func attempt() -> int:
	return _attempt


## Once per physics tick, before the simulation steps (bridge priority -10): a tick boundary.
func capture(session: Node) -> void:
	if not armed or session == null or not is_instance_valid(session):
		return
	if session.get_instance_id() != _session_id:
		_unbind_session()
		clear() # another flight: its checkpoints would be refused by the configuration fingerprint anyway
		_session_id = session.get_instance_id()
		_session_ref = weakref(session)
		if session.has_signal("resetting") and not session.is_connected("resetting", _on_session_resetting):
			session.connect("resetting", _on_session_resetting)
	var sim: Node = session.sim
	if sim.paused:
		return
	var tick: int = sim.tick
	if tick == _last_tick:
		return
	if tick < _last_tick:
		_attempt += 1 # restart or crash auto-restart: a new attempt; the previous one stays rewindable
	_last_tick = tick
	var newest := _newest(_attempt)
	if not newest.is_empty() and tick - int(newest.tick) < every_ticks:
		return
	var started := Time.get_ticks_usec()
	var snapshot: Dictionary = session.checkpoint()
	capture_usec = lerpf(capture_usec, float(Time.get_ticks_usec() - started), 0.1) if capture_usec > 0.0 \
		else float(Time.get_ticks_usec() - started)
	if snapshot.is_empty():
		refused += 1
		return
	var state: PackedFloat64Array = sim.state
	_entries.append({attempt = _attempt, tick = tick, time_s = sim.time(), height_m = -state[2],
		speed_mps = sqrt(state[3] * state[3] + state[4] * state[4] + state[5] * state[5]), snapshot = snapshot})
	while _entries.size() > capacity:
		_entries.pop_front()


## Accepted start/restore/configuration boundary, including equal or increasing ticks.
## Several boundaries before the next observation still represent one unsampled attempt.
func _on_session_resetting() -> void:
	if armed and not _restoring and _last_tick >= 0:
		_attempt += 1
		_last_tick = -1


func _unbind_session() -> void:
	if _session_ref != null:
		var previous: Object = _session_ref.get_ref()
		if previous != null and previous.has_signal("resetting") and previous.is_connected("resetting", _on_session_resetting):
			previous.disconnect("resetting", _on_session_resetting)
	_session_ref = null


func _newest(of_attempt: int) -> Dictionary:
	for i in range(_entries.size() - 1, -1, -1):
		if int(_entries[i].attempt) == of_attempt:
			return _entries[i]
	return {}


## Summary per attempt (no snapshot payloads).
func summary() -> Dictionary:
	var attempts := {}
	for entry: Dictionary in _entries:
		var key := int(entry.attempt)
		if not attempts.has(key):
			attempts[key] = {attempt = key, snapshots = 0, first_tick = entry.tick, first_time_s = entry.time_s}
		attempts[key].snapshots += 1
		attempts[key].last_tick = entry.tick
		attempts[key].last_time_s = entry.time_s
		attempts[key].last_height_m = snappedf(entry.height_m, 0.01)
	return {armed = armed, every_ticks = every_ticks, capacity = capacity, snapshots = _entries.size(),
		current_attempt = _attempt, refused = refused, capture_usec = snappedf(capture_usec, 0.1),
		bytes_estimate = _entries.size() * (var_to_bytes(_entries[0].snapshot).size() if not _entries.is_empty() else 0),
		attempts = attempts.values()}


## The snapshot to restore. attempt: "current" (default), "previous" or a number. tick=<t>: the newest snapshot
## at or before t; seconds=<s>: the newest at or before s seconds before now (current attempt) or before that
## attempt's last snapshot (an earlier attempt, e.g. the seconds before a crash that has since auto-restarted).
func find(request: Dictionary, now_tick: int, dt: float) -> Dictionary:
	if _entries.is_empty():
		return {error = "no snapshots yet: rewind arm=true, then fly (one every %d ticks)" % every_ticks}
	var which: Variant = request.get("attempt", "current")
	var wanted := _attempt
	if str(which) == "previous":
		wanted = _attempt - 1
		while wanted >= 0 and _newest(wanted).is_empty():
			wanted -= 1
	elif which is float or which is int:
		wanted = int(which) # JSON numbers arrive as floats
	elif str(which) != "current":
		wanted = int(which) if str(which).is_valid_int() else -1
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if int(entry.attempt) == wanted:
			candidates.append(entry)
	if candidates.is_empty():
		return {error = "no snapshots of attempt %s; attempts kept: %s" % [str(which), summary().attempts.map(
			func(a: Dictionary) -> int: return a.attempt)]}
	var target_tick: int
	if request.has("tick"):
		target_tick = int(request.tick)
	else:
		var reference: int = now_tick if wanted == _attempt else int(candidates[candidates.size() - 1].tick)
		target_tick = reference - roundi(float(request.get("seconds", 1.0)) / dt)
	for i in range(candidates.size() - 1, -1, -1):
		if int(candidates[i].tick) <= target_tick:
			return candidates[i]
	return {error = "attempt %d keeps ticks %d..%d (%.1f..%.1f s); tick %d is older" % [wanted, candidates[0].tick,
		candidates[candidates.size() - 1].tick, candidates[0].time_s, candidates[candidates.size() - 1].time_s, target_tick]}


## Restore `entry` and cut the timeline after it. Returns the session's verdict.
func restore(session: Node, entry: Dictionary) -> bool:
	if session == null or not is_instance_valid(session) or session.get_instance_id() != _session_id:
		return false
	_restoring = true
	var restored: bool = session.restore_checkpoint(entry.snapshot)
	_restoring = false
	if not restored:
		return false
	var at_attempt := int(entry.attempt)
	var at_tick := int(entry.tick)
	var kept: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if int(e.attempt) < at_attempt or (int(e.attempt) == at_attempt and int(e.tick) <= at_tick):
			kept.append(e)
	_entries = kept
	_attempt = at_attempt
	_last_tick = at_tick
	return true


static func describe(entry: Dictionary) -> Dictionary:
	return {attempt = entry.attempt, tick = entry.tick, time_s = snappedf(entry.time_s, 0.0001),
		height_m = snappedf(entry.height_m, 0.01), speed_mps = snappedf(entry.speed_mps, 0.01)}
