extends RefCounted
class_name FlightStatisticsReducer
## Pure, rebuildable rollups over canonical statistics records.

static func query(data: Dictionary, aircraft_id: String = "", period: String = "session", session_id: String = "") -> Dictionary:
	var result: Dictionary = _empty_result(period, aircraft_id, session_id)
	var schema_script: Script = load("res://statistics/schema.gd")
	if schema_script == null:
		result.ok = false
		result.available = false
		result.errors = PackedStringArray(["Statistics schema is unavailable."])
		return result
	var validation: Dictionary = schema_script.validate(data)
	if not bool(validation.get("ok", false)):
		result.ok = false
		result.available = false
		result.errors = validation.get("errors", PackedStringArray())
		return result
	var resolved_period: String = period.to_lower()
	if resolved_period == "since_reset":
		resolved_period = "counters"
	if resolved_period not in ["session", "lifetime", "counters"]:
		result.ok = false
		result.available = false
		result.errors = PackedStringArray(["Statistics period is invalid."])
		return result
	result.period_label = _period_label(data, aircraft_id, resolved_period, session_id)
	var selected: Array[Dictionary] = []
	var visible_history: Array[Dictionary] = []
	var history_counts: Dictionary = {"flight": 0, "crash": 0, "restart": 0, "gap": 0}
	var resolved_session: String = session_id
	if resolved_period == "session" and resolved_session.is_empty():
		resolved_session = str(data.get("current_session", ""))
	var account_epoch: int = int(data.get("epochs", {}).get("account", 0))
	var aircraft_epochs: Dictionary = data.get("epochs", {}).get("aircraft", {})
	for record_value: Variant in data.get("records", []):
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		if not aircraft_id.is_empty() and str(record.get("aircraft_id", "")) != aircraft_id:
			continue
		if resolved_period == "session" and (resolved_session.is_empty() or str(record.get("session_id", "")) != resolved_session):
			continue
		if resolved_period == "counters":
			if aircraft_id.is_empty():
				if int(record.get("account_epoch", -1)) != account_epoch:
					continue
			else:
				var aircraft_epoch: int = int(aircraft_epochs.get(aircraft_id, 0))
				if int(record.get("aircraft_epoch", -1)) != aircraft_epoch:
					continue
		selected.append(record)
		_accumulate(result, record)
		var kind: String = str(record.get("kind", ""))
		if history_counts.has(kind):
			history_counts[kind] = int(history_counts[kind]) + 1
		if kind != "gap":
			visible_history.append(record.duplicate(true))
	result.history = visible_history
	result.history_count = visible_history.size()
	result.history_record_count = visible_history.size()
	result.history_flight_count = int(history_counts.get("flight", 0))
	result.history_counts = history_counts
	result.history_count_label = "records"
	result.history_total = visible_history.size()
	result.history_has_more = false
	if not visible_history.is_empty():
		result.first_history_date = str(visible_history.front().get("utc", ""))
		result.last_history_date = str(visible_history.back().get("utc", ""))
	_finalize_averages(result)
	_compute_runs(result, selected)
	return result


static func reset(data: Dictionary, scope: String, aircraft_id: String = "", new_session_id: String = "", opened_utc: String = "") -> Dictionary:
	var schema_script: Script = load("res://statistics/schema.gd")
	if schema_script == null or not bool(schema_script.validate(data).get("ok", false)):
		return {}
	var candidate: Dictionary = schema_script.canonicalize(data.duplicate(true))
	var epochs: Dictionary = candidate.epochs
	match scope.to_lower():
		"account", "pilot":
			if int(epochs.account) >= schema_script.MAX_SEQUENCE:
				return {}
			epochs.account = int(epochs.account) + 1
			var account_time: String = opened_utc if not opened_utc.is_empty() else schema_script.utc_now()
			if not schema_script._valid_utc(account_time):
				return {}
			epochs.account_utc = account_time
		"aircraft":
			if aircraft_id.is_empty() or not schema_script._safe_id(aircraft_id):
				return {}
			var next_epoch: int = int(epochs.aircraft.get(aircraft_id, 0))
			if next_epoch >= schema_script.MAX_SEQUENCE:
				return {}
			epochs.aircraft[aircraft_id] = next_epoch + 1
			var aircraft_time: String = opened_utc if not opened_utc.is_empty() else schema_script.utc_now()
			if not schema_script._valid_utc(aircraft_time):
				return {}
			if not epochs.has("aircraft_utc"):
				epochs.aircraft_utc = {}
			epochs.aircraft_utc[aircraft_id] = aircraft_time
		"session":
			if not schema_script._safe_id(new_session_id) or not schema_script._valid_utc(opened_utc):
				return {}
			for existing: Dictionary in candidate.sessions:
				if str(existing.id) == new_session_id:
					return {}
				if str(existing.id) == str(candidate.current_session) and str(existing.status) == "open":
					existing.status = "closed"
					existing.closed_utc = opened_utc
			candidate.sessions.append({
				"id": new_session_id,
				"opened_utc": opened_utc,
				"closed_utc": "",
				"status": "open",
			})
			candidate.current_session = new_session_id
			candidate.clean_exit = false
		_:
			return {}
	return candidate if bool(schema_script.validate(candidate).get("ok", false)) else {}


static func _empty_result(period: String, aircraft_id: String, session_id: String) -> Dictionary:
	return {
		"ok": true,
		"available": true,
		"errors": PackedStringArray(),
		"started": 0,
		"completed": 0,
		"airborne_seconds": 0.0,
		"average_seconds": -1.0,
		"average_count": 0,
		"landings": 0,
		"touch_and_go": 0,
		"full_stops": 0,
		"failed_landings": 0,
		"unknown_landings": 0,
		"crashes": 0,
		"restarts": 0,
		"max_tas_mps": -1.0,
		"max_groundspeed_mps": -1.0,
		"landing_rate": -1.0,
		"current_streak": 0,
		"best_streak": 0,
		"current_clean_seconds": 0.0,
		"best_clean_seconds": 0.0,
		"closed": 0,
		"active": 0,
		"partial": 0,
		"history": [],
		"history_count": 0,
		"history_record_count": 0,
		"history_flight_count": 0,
		"history_counts": {"flight": 0, "crash": 0, "restart": 0, "gap": 0},
		"history_count_label": "records",
		"first_history_date": "",
		"last_history_date": "",
		"history_total": 0,
		"history_has_more": false,
		"period_label": "",
		"aircraft_id": aircraft_id,
		"period": period,
		"session_id": session_id,
	}


static func _accumulate(result: Dictionary, record: Dictionary) -> void:
	match str(record.get("kind", "")):
		"crash":
			result.crashes += 1
			return
		"restart":
			result.restarts += 1
			return
		"gap":
			return
		"flight":
			pass
		_:
			return
	result.started += 1
	var outcome: String = str(record.get("outcome", ""))
	if outcome == "completed":
		result.completed += 1
	if outcome == "active":
		result.active += 1
	else:
		result.closed += 1
		if not bool(record.get("complete_observation", false)) or outcome == "interrupted":
			result.partial += 1
	result.airborne_seconds += maxf(0.0, float(record.get("airborne_seconds", 0.0)))
	result.full_stops += int(record.get("full_stops", 0))
	result.touch_and_go += int(record.get("touch_and_go", 0))
	result.landings = int(result.full_stops) + int(result.touch_and_go)
	result.failed_landings += int(record.get("failed_landings", 0))
	result.unknown_landings += int(record.get("unknown_landings", 0))
	var tas: float = float(record.get("max_tas_mps", -1.0))
	var groundspeed: float = float(record.get("max_groundspeed_mps", -1.0))
	if tas >= 0.0:
		result.max_tas_mps = maxf(float(result.max_tas_mps), tas)
	if groundspeed >= 0.0:
		result.max_groundspeed_mps = maxf(float(result.max_groundspeed_mps), groundspeed)
	if outcome != "active" and bool(record.get("complete_observation", false)):
		result._average_seconds_sum = float(result.get("_average_seconds_sum", 0.0)) + float(record.airborne_seconds)
		result.average_count += 1


static func _finalize_averages(result: Dictionary) -> void:
	if int(result.average_count) > 0:
		result.average_seconds = float(result.get("_average_seconds_sum", 0.0)) / float(result.average_count)
	else:
		result.average_seconds = -1.0
	result.erase("_average_seconds_sum")
	var denominator: int = int(result.landings) + int(result.failed_landings)
	result.landing_rate = float(result.landings) / float(denominator) if denominator > 0 else -1.0


static func _compute_runs(result: Dictionary, selected: Array[Dictionary]) -> void:
	var ordered: Array[Dictionary] = []
	for record: Dictionary in selected:
		var terminal_seq: int = int(record.get("seq", 0))
		if record.get("kind") == "flight" and str(record.get("outcome", "")) != "active":
			terminal_seq = int(record.get("end_seq", terminal_seq))
		ordered.append({"order": terminal_seq, "record": record})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.order) == int(b.order):
			return int(a.record.seq) < int(b.record.seq)
		return int(a.order) < int(b.order)
	)
	var running_streak: int = 0
	var best_streak: int = 0
	var clean_seconds: float = 0.0
	var best_clean: float = 0.0
	for item: Dictionary in ordered:
		var record: Dictionary = item.record
		var kind: String = str(record.get("kind", ""))
		if kind == "gap" or kind == "crash" or kind == "restart":
			running_streak = 0
			clean_seconds = 0.0
			continue
		if kind != "flight":
			continue
		var outcome: String = str(record.get("outcome", ""))
		var seconds: float = maxf(0.0, float(record.get("airborne_seconds", 0.0)))
		var complete: bool = bool(record.get("complete_observation", false))
		if outcome == "active":
			clean_seconds += seconds
			best_clean = maxf(best_clean, clean_seconds)
			continue
		if outcome == "completed" and complete:
			running_streak += 1
			best_streak = maxi(best_streak, running_streak)
			clean_seconds += seconds
			best_clean = maxf(best_clean, clean_seconds)
			continue
		if complete and outcome in ["crashed", "restarted", "abandoned"]:
			best_clean = maxf(best_clean, clean_seconds + seconds)
		running_streak = 0
		clean_seconds = 0.0
	result.current_streak = running_streak
	result.best_streak = best_streak
	result.current_clean_seconds = clean_seconds
	result.best_clean_seconds = best_clean


static func _period_label(data: Dictionary, aircraft_id: String, period: String, session_id: String) -> String:
	match period:
		"lifetime": return "Lifetime history"
		"counters":
			var epochs: Dictionary = data.get("epochs", {})
			var timestamp: String = ""
			if aircraft_id.is_empty():
				timestamp = str(epochs.get("account_utc", ""))
			else:
				timestamp = str(epochs.get("aircraft_utc", {}).get(aircraft_id, ""))
			return "Since counter reset" if timestamp.is_empty() else "Since counter reset · " + timestamp
		"session":
			var chosen: String = session_id if not session_id.is_empty() else str(data.get("current_session", ""))
			for session: Dictionary in data.get("sessions", []):
				if str(session.get("id", "")) == chosen:
					return "This session · " + str(session.get("opened_utc", "")) if chosen == str(data.get("current_session", "")) else "Session %s · %s" % [chosen, str(session.get("opened_utc", ""))]
			return "This session" if chosen == str(data.get("current_session", "")) else ("Session " + chosen if not chosen.is_empty() else "This session")
	return ""
