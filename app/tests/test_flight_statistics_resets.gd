extends SceneTree
## UI-FS-03 independent account, aircraft, and session reset behavior.

class FakeDetector:
	extends RefCounted
	var flight := {}

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
	var identity: Script = load("res://statistics/aircraft_identity.gd")
	_check("non-stock lookalikes remain distinct", not identity.matches("workshop:moonrunner-x99", "workshop:skywalker-x8") and not identity.matches("stock:moonrunner-x99", "moonrunner-x99"))
	_test_alias_migration(source, reducer, schema)
	_test_service_alias(source)
	_test_reducer_rollups(source, reducer, schema)
	_test_account_and_aircraft_epochs(source, reducer, schema)
	_test_session_reset(source, reducer, schema)
	_test_invalid_resets_are_unchanged(source, reducer, schema)
	_finish()


func _test_alias_migration(source: Dictionary, reducer: Script, schema: Script) -> void:
	for pair: Array in [["skywalker-x8", "moonrunner-x99"], ["stock:skywalker-x8", "stock:moonrunner-x99"]]:
		var legacy: String = pair[0]
		var current: String = pair[1]
		var data: Dictionary = source.duplicate(true)
		data.records[0].aircraft_id = legacy
		data.records[1].aircraft_id = legacy
		data.records[2].aircraft_id = current
		data.epochs.aircraft[legacy] = 1
		data.epochs.aircraft[current] = 2
		data.epochs.aircraft_utc[legacy] = "2026-10-25T12:10:00"
		data.epochs.aircraft_utc[current] = "2026-10-25T12:20:00"
		data.records[1].aircraft_epoch = 1
		data.records[2].aircraft_epoch = 2
		var original: Dictionary = data.duplicate(true)
		_check("alias fixture is valid " + legacy, bool(schema.validate(data).ok))
		var legacy_query: Dictionary = reducer.query(data, legacy, "lifetime")
		var merged: Dictionary = reducer.query(data, current, "lifetime")
		_check("both spellings select both histories without duplicates", merged.started == 2 and merged.crashes == 1 and merged == legacy_query.merged({"aircraft_id": current}, true))
		_check("combined streak follows original event order", merged.current_streak == 1 and merged.best_streak == 1)
		_check("all-aircraft lifetime stays unchanged", reducer.query(data, "", "lifetime").started == 3)
		_check("per-source reset epochs survive combined counter query", reducer.query(data, current, "counters").started == 1 and reducer.query(data, current, "counters").crashes == 1)
		_check("mixed reset dates are described as separate windows", reducer.query(data, current, "counters").period_label == "Since separate counter resets")
		var missing_date: Dictionary = data.duplicate(true)
		missing_date.epochs.aircraft_utc.erase(current)
		_check("undated alias history does not claim the other alias reset date", reducer.query(missing_date, current, "counters").period_label == "Since separate counter resets")
		var legacy_only: Dictionary = data.duplicate(true)
		legacy_only.records.remove_at(2)
		_check("legacy-only history remains discoverable under the new ID", reducer.query(legacy_only, current, "lifetime").started == 1)
		var current_only: Dictionary = data.duplicate(true)
		current_only.records.remove_at(1)
		current_only.records.remove_at(0)
		_check("new-only history remains discoverable under the legacy ID", reducer.query(current_only, legacy, "lifetime").started == 1)
		var reset: Dictionary = reducer.reset(data, "aircraft", current, "", "2026-10-25T15:00:00")
		_check("reset advances each existing epoch", not reset.is_empty() and reset.epochs.aircraft[legacy] == 2 and reset.epochs.aircraft[current] == 3)
		_check("reset preserves records and empties both counter windows", reset.records == data.records and reducer.query(reset, current, "counters").started == 0 and reducer.query(reset, current, "lifetime").started == 2)
		_check("reset retains other aircraft", reducer.query(reset, "stock:b", "counters").started == 1)
		var new_flight: Dictionary = _flight("alias-new-after-reset", 8, 9, "session-old", current, "MoonRunner X99", "completed", 13.0, 1)
		new_flight.aircraft_epoch = int(reset.epochs.aircraft[current])
		reset.records.append(new_flight)
		reset.sequence = 9
		_check("new post-reset flight is counted once in the combined window", reducer.query(reset, current, "counters").started == 1 and reducer.query(reset, legacy, "counters").started == 1)
		_check("query and reset do not mutate original", data == original)
		data.epochs.aircraft[legacy] = schema.MAX_SEQUENCE
		_check("one exhausted alias prevents partial reset", reducer.reset(data, "aircraft", current).is_empty())


func _test_service_alias(source: Dictionary) -> void:
	var service: Node = load("res://statistics/service.gd").new()
	service.data = source.duplicate(true)
	service.data.records[0].aircraft_id = "skywalker-x8"
	service.data.records[1].aircraft_id = "moonrunner-x99"
	var choices: Array = service.aircraft_choices()
	var catalog: Script = load("res://app_state/aircraft_catalog.gd")
	var installed_id: String = "moonrunner-x99" if catalog.has("moonrunner-x99") else "skywalker-x8"
	_check("service lists one installed catalog choice for both names", choices.size() == 3 and choices[0].id == installed_id and choices[0].name == "MoonRunner X99")
	_check("service query groups both histories", service.query("moonrunner-x99", "lifetime").history_count == 2)
	_check("service summary groups both histories", service.summary("moonrunner-x99", "lifetime").history_count == 2)
	# Bare and prefixed IDs are distinct entities, even when the display name matches.
	var prefixed: Dictionary = _flight("prefixed-flight", 8, 9, "session-old", "stock:skywalker-x8", "MoonRunner X99", "completed", 13.0, 1)
	service.data.records.append(prefixed)
	service.data.sequence = 9
	service._query_cache.clear()
	service._summary_cache.clear()
	choices = service.aircraft_choices()
	_check("coexisting namespaces get distinguishable choices", choices.size() == 4 and choices[0].name == "MoonRunner X99" and choices[-1].id == "stock:" + installed_id and choices[-1].name == "MoonRunner X99 · stock:" + installed_id)
	_check("bare and prefixed groups query independently", service.query("moonrunner-x99", "lifetime").history_count == 2 and service.query("stock:moonrunner-x99", "lifetime").history_count == 1 and service.query("", "lifetime").history_count == 5)
	var before_reset: Dictionary = service.data.duplicate(true)
	var reducer: Script = load("res://statistics/reducer.gd")
	var reset: Dictionary = reducer.reset(before_reset, "aircraft", "moonrunner-x99", "", "2026-10-25T15:00:00")
	_check("reset of bare group preserves prefixed counter window", reducer.query(reset, "moonrunner-x99", "counters").history_count == 0 and reducer.query(reset, "stock:moonrunner-x99", "counters").history_count == 1 and reset.epochs.aircraft.get("stock:skywalker-x8", 0) == 0)
	service._summary_cache.clear()
	service._aircraft_id = "skywalker-x8"
	service._active_record = service.data.records[0].duplicate(true)
	var detector := FakeDetector.new()
	detector.flight = {"airborne_seconds": 45.0, "max_tas_mps": 24.0, "max_groundspeed_mps": 21.0}
	service.detector = detector
	var before: Dictionary = service.summary("moonrunner-x99", "lifetime")
	detector.flight.airborne_seconds = 47.0
	var after: Dictionary = service.summary("moonrunner-x99", "lifetime")
	_check("summary tracks active legacy observation under new ID", is_equal_approx(after.airborne_seconds, before.airborne_seconds + 2.0))
	service.detector = null
	service.free()


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
	var summary_without_history: Dictionary = reducer.query(current, "", "lifetime", "", false)
	_check("history can be omitted without changing its record counts", summary_without_history.history.is_empty() and summary_without_history.history_count == summary.history_count and summary_without_history.history_total == summary.history_total)
	_check("history-free query preserves kind counts and date bounds", summary_without_history.history_counts == summary.history_counts and summary_without_history.first_history_date == summary.first_history_date and summary_without_history.last_history_date == summary.last_history_date)
	var unsupported: Dictionary = current.duplicate(true)
	unsupported.schema_version = int(schema.SCHEMA_VERSION) + 1
	_check("untrusted query rejects a newer schema", not bool(reducer.query(unsupported, "", "lifetime").ok))
	var trusted_summary: Dictionary = reducer.query(unsupported, "", "lifetime", "", false, true)
	_check("trusted query skips only schema validation", bool(trusted_summary.ok) and trusted_summary.started == summary.started and trusted_summary.history_count == summary.history_count and trusted_summary.history.is_empty())
	var with_failed_stop: Dictionary = current.duplicate(true)
	var failed_stop: Dictionary = _flight("failed-stop", 8, 9, "session-old", "stock:a", "A", "failed_stop", 15.0, 0)
	with_failed_stop.records.append(failed_stop)
	with_failed_stop.sequence = 9
	_check("failed stop is a valid closed outcome", bool(schema.validate(with_failed_stop).ok))
	var failed_stop_summary: Dictionary = reducer.query(with_failed_stop, "", "lifetime")
	_check("failed stop is mean-eligible without becoming a clean completion", failed_stop_summary.started == 4 and failed_stop_summary.completed == 3 and failed_stop_summary.closed == 4 and failed_stop_summary.average_count == 4 and absf(failed_stop_summary.average_seconds - 37.5) < 1e-9)
	_check("failed stop breaks the current clean streak", failed_stop_summary.current_streak == 0 and failed_stop_summary.best_streak == 2)

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
