extends SceneTree
## UI-FS-03 independent account, aircraft, and session reset behavior.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var schema: Script = load("res://statistics/schema.gd")
	var reducer: Script = load("res://statistics/reducer.gd")
	if schema == null or reducer == null:
		_check("statistics schema and reducer load", false)
		_finish()
		return
	var source: Dictionary = _fixture(schema)
	_check("reset fixture validates", bool(schema.validate(source).ok))
	_test_reducer_rollups(source, reducer, schema)
	_test_account_and_aircraft_epochs(source, reducer, schema)
	_test_session_reset(source, reducer, schema)
	_test_invalid_resets_are_unchanged(source, reducer, schema)
	_finish()


func _test_reducer_rollups(source: Dictionary, reducer: Script, schema: Script) -> void:
	var current: Dictionary = source.duplicate(true)
	current.records[0].touch_and_go = 2
	current.records[2].failed_landings = 1
	current.records[2].unknown_landings = 1
	var summary: Dictionary = reducer.query(current, "", "lifetime")
	_check("rollup counts starts and completions", summary.started == 3 and summary.completed == 3)
	_check("rollup sums airborne time in seconds", absf(summary.airborne_seconds - 135.0) < 1e-9)
	_check("average excludes no fully observed closed flight", summary.average_count == 3 and absf(summary.average_seconds - 45.0) < 1e-9)
	_check("landings separate touch-and-go and full stops", summary.landings == 5 and summary.touch_and_go == 2 and summary.full_stops == 3)
	_check("landing rate excludes unknown episodes", summary.failed_landings == 1 and summary.unknown_landings == 1 and absf(summary.landing_rate - (5.0 / 6.0)) < 1e-9)
	_check("crash events count once without outcome double-counting", summary.crashes == 1)
	_check("speed maxima remain separate", absf(summary.max_tas_mps - 24.0) < 1e-9 and absf(summary.max_groundspeed_mps - 21.0) < 1e-9)
	_check("completed streaks break at the crash event", summary.current_streak == 2 and summary.best_streak == 2)
	_check("history preview counts records and flights distinctly", summary.history_count == 4 and summary.history_flight_count == 3 and summary.history_counts.crash == 1)
	_check("history preview reports date bounds", summary.first_history_date == current.records[0].utc and summary.last_history_date == current.records[-1].utc)

	var active: Dictionary = _flight("active-flight", 8, -1, "session-old", "stock:a", "A", "active", 4.5, 0)
	active.complete_observation = false
	current.records.append(active)
	current.sequence = 8
	_check("active fixture remains valid", bool(schema.validate(current).ok))
	var with_active: Dictionary = reducer.query(current, "", "lifetime")
	_check("active flight time is included but average excludes it", with_active.started == 4 and with_active.active == 1 and with_active.average_count == 3 and absf(with_active.average_seconds - 45.0) < 1e-9)
	_check("active duration is included in airborne total", absf(with_active.airborne_seconds - 139.5) < 1e-9)
	_check("zero denominator uses unknown rate", reducer.query(source, "", "session", "missing-session").landing_rate == -1.0)


func _test_account_and_aircraft_epochs(source: Dictionary, reducer: Script, schema: Script) -> void:
	var account_time: String = "2026-10-25T14:00:00"
	var account: Dictionary = reducer.reset(source, "account", "", "", account_time)
	_check("account reset returns a valid candidate", not account.is_empty() and bool(schema.validate(account).ok))
	_check("account reset advances only account epoch", account.epochs.account == 1 and account.epochs.aircraft["stock:a"] == 0 and account.epochs.aircraft["stock:b"] == 0)
	_check("account reset records its time", account.epochs.account_utc == account_time)
	_check("account reset preserves lifetime history", reducer.query(account, "", "lifetime").started == 3)
	_check("account since-reset view starts empty", reducer.query(account, "", "counters").started == 0)
	_check("account reset leaves aircraft counter windows independent", reducer.query(account, "stock:a", "counters").started == 2 and reducer.query(account, "stock:b", "counters").started == 1)
	_check("account period label exposes epoch time", str(reducer.query(account, "", "counters").period_label).contains(account_time))

	var aircraft_time: String = "2026-10-25T14:05:00"
	var aircraft: Dictionary = reducer.reset(source, "aircraft", "stock:a", "", aircraft_time)
	_check("aircraft reset returns a valid candidate", not aircraft.is_empty() and bool(schema.validate(aircraft).ok))
	_check("aircraft reset advances only its epoch", aircraft.epochs.account == 0 and aircraft.epochs.aircraft["stock:a"] == 1 and aircraft.epochs.aircraft["stock:b"] == 0)
	_check("aircraft reset records its time", aircraft.epochs.aircraft_utc["stock:a"] == aircraft_time)
	_check("aircraft since-reset view starts empty", reducer.query(aircraft, "stock:a", "counters").started == 0)
	_check("other aircraft counter window stays intact", reducer.query(aircraft, "stock:b", "counters").started == 1)
	_check("account counter view is unchanged by aircraft reset", reducer.query(aircraft, "", "counters").started == 3)
	_check("aircraft period label exposes epoch time", str(reducer.query(aircraft, "stock:a", "counters").period_label).contains(aircraft_time))


func _test_session_reset(source: Dictionary, reducer: Script, schema: Script) -> void:
	var new_time: String = "2026-10-25T15:00:00"
	var reset: Dictionary = reducer.reset(source, "session", "", "session-next", new_time)
	_check("session reset returns valid data", not reset.is_empty() and bool(schema.validate(reset).ok))
	_check("session reset selects the new session", reset.current_session == "session-next")
	_check("session reset closes the prior session", reset.sessions[0].status == "closed" and reset.sessions[0].closed_utc == new_time)
	_check("session reset appends an open session", reset.sessions[1].status == "open" and reset.sessions[1].opened_utc == new_time)
	_check("session reset does not advance counter epochs", reset.epochs.account == 0 and reset.epochs.aircraft["stock:a"] == 0)
	_check("new-session query is empty", reducer.query(reset, "", "session").started == 0)
	_check("explicit old-session history remains intact", reducer.query(reset, "", "session", "session-old").started == 3)
	_check("session period label includes its opening time", str(reducer.query(reset, "", "session").period_label).contains(new_time))


func _test_invalid_resets_are_unchanged(source: Dictionary, reducer: Script, schema: Script) -> void:
	_check("aircraft reset requires a scoped ID", reducer.reset(source, "aircraft").is_empty())
	_check("session reset requires a new session ID", reducer.reset(source, "session").is_empty())
	_check("unknown reset scope is rejected", reducer.reset(source, "lifetime").is_empty())
	_check("invalid input remains valid and unchanged", bool(schema.validate(source).ok) and source.epochs.account == 0 and source.current_session == "session-old")


func _fixture(schema: Script) -> Dictionary:
	var opened: String = "2026-10-25T12:00:00"
	var source: Dictionary = schema.create("pilot-test", opened)
	source.sessions = [{"id": "session-old", "opened_utc": opened, "closed_utc": "", "status": "open"}]
	source.current_session = "session-old"
	source.epochs.aircraft = {"stock:a": 0, "stock:b": 0}
	source.epochs.aircraft_utc = {"stock:a": opened, "stock:b": opened}
	source.records = [
		_flight("a-flight-1", 1, 2, "session-old", "stock:a", "A", "completed", 45.0, 1),
		_event("a-crash", 3, "session-old", "stock:a", "A", "crash"),
		_flight("a-flight-2", 4, 5, "session-old", "stock:a", "A", "completed", 30.0, 1),
		_flight("b-flight-1", 6, 7, "session-old", "stock:b", "B", "completed", 60.0, 1),
	]
	source.records[0].utc = "2026-10-25T12:10:00"
	source.records[1].utc = "2026-10-25T12:20:00"
	source.records[2].utc = "2026-10-25T12:30:00"
	source.records[3].utc = "2026-10-25T12:40:00"
	source.sequence = 7
	return source


func _flight(id: String, seq: int, end_seq: int, session_id: String, aircraft_id: String, name: String,
		outcome: String, seconds: float, full_stops: int) -> Dictionary:
	return {
		"kind": "flight", "id": id, "seq": seq, "end_seq": end_seq,
		"session_id": session_id, "aircraft_id": aircraft_id, "aircraft_name": name,
		"utc": "2026-10-25T12:10:00", "ended_utc": "2026-10-25T12:11:00",
		"account_epoch": 0, "aircraft_epoch": 0,
		"airborne_seconds": seconds, "outcome": outcome, "start_kind": "takeoff",
		"full_stops": full_stops, "touch_and_go": 0, "failed_landings": 0, "unknown_landings": 0,
		"max_tas_mps": 24.0, "max_groundspeed_mps": 21.0,
		"complete_observation": true, "config_hash": "", "rules_version": "flight-statistics-v1",
		"metadata": {},
	}


func _event(id: String, seq: int, session_id: String, aircraft_id: String, name: String, kind: String) -> Dictionary:
	return {
		"kind": kind, "id": id, "seq": seq, "session_id": session_id,
		"aircraft_id": aircraft_id, "aircraft_name": name, "utc": "2026-10-25T12:20:00",
		"account_epoch": 0, "aircraft_epoch": 0, "metadata": {},
	}


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s %s" % [label, detail])


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
