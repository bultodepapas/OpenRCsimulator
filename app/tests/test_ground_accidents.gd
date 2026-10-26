extends SceneTree

const Detector := preload("res://statistics/detector.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Rules := preload("res://statistics/rules.gd")

class PacketSession:
	extends Node
	var statistics_generation := 7
	var sim := {"tick": 3}


var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_survivable_scrape_and_terminal_escalation()
	_test_damaged_hull_stop_without_landing_geometry()
	_test_accident_departure_without_landing_geometry()
	_test_rearm_distinct_accidents_and_previous_success()
	_test_snapshot_replay_and_legacy_coverage()
	_test_snapshot_rejects_inconsistent_groups()
	_test_rejected_and_duplicate_ticks()
	_test_packet_identity_and_no_gear_exemption()
	print("GP-14 accidents: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func _profile() -> Dictionary:
	return {"landing_available": true, "initial_tick": 0, "generation_id": "7",
		"rules": {"liftoff_clearance_s": 0.2, "stable_support_s": 0.2,
			"full_stop_s": 0.4, "rearm_clearance_s": 0.3}}


func _sample(tick: int, changes: Dictionary = {}) -> Dictionary:
	var sample := {"tick": tick, "dt": 0.1, "valid": true, "supported": false,
		"ground_contact": false, "intended_support": false, "stop_support": false,
		"controlled": true, "clearance_ok": true, "incident": false,
		"gear_up_contact": false, "terminal": false, "ground_speed_3d": 5.0,
		"angular_speed": 0.0}
	sample.merge(changes, true)
	return sample


func _scrape(tick: int) -> Dictionary:
	return _sample(tick, {"supported": true, "ground_contact": true,
		"clearance_ok": false, "gear_up_contact": true, "controlled": false})


func _start(profile: Dictionary = {}) -> RefCounted:
	var detector: RefCounted = Detector.new()
	detector.configure(_profile() if profile.is_empty() else profile, true)
	detector.observe(_sample(1))
	detector.observe(_sample(2))
	return detector


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if event.get("type") == type:
			result.append(event)
	return result


func _test_survivable_scrape_and_terminal_escalation() -> void:
	var detector := _start()
	var before := float(detector.flight.airborne_seconds)
	var events: Array[Dictionary] = detector.observe(_scrape(3))
	var accidents := _of(events, "accident")
	_check("first gear-up contact emits semantic accident and exactly one M7",
		accidents.size() == 1 and _of(events, "crash").size() == 1)
	_check("survivable accident retains active flight and has no close",
		detector.flight.get("outcome") == "active" and _of(events, "closed").is_empty())
	_check("contact tick does not add airborne time", detector.flight.airborne_seconds == before)
	_check("nonterminal receipt reports gear-up independently of severity",
		accidents.size() == 1 and not accidents[0].terminal and accidents[0].kind == "gear_up_contact")
	var accident_id: String = str(accidents[0].get("accident_id", "")) if not accidents.is_empty() else ""
	var repeated: Array[Dictionary] = []
	for tick in range(4, 104):
		repeated.append_array(detector.observe(_scrape(tick)))
	_check("100 persistent scrape ticks produce no duplicate accident or M7",
		_of(repeated, "accident").is_empty() and _of(repeated, "crash").is_empty())
	_check("continued sliding remains an active flight", detector.flight.get("outcome") == "active")
	detector.observe(_sample(104))
	_check("unsupported accepted interval still adds airborne time after accident",
		absf(float(detector.flight.airborne_seconds) - before - 0.1) < 1e-12)
	var terminal := _scrape(104)
	terminal.terminal = true
	var escalated: Array[Dictionary] = detector.observe(terminal)
	var updates := _of(escalated, "accident_updated")
	_check("same-tick terminal escalation updates same semantic incident",
		updates.size() == 1 and updates[0].accident_id == accident_id and updates[0].terminal)
	_check("escalation closes crashed without a second M7",
		_of(escalated, "crash").is_empty() and _of(escalated, "closed").size() == 1
		and _of(escalated, "closed")[0].outcome == "crashed")
	_check("repeated terminal guard is silent", detector.observe(terminal).is_empty())
	var severe := _start()
	var first_terminal := _scrape(3)
	first_terminal.terminal = true
	var severe_events: Array[Dictionary] = severe.observe(first_terminal)
	var taxi: RefCounted = Detector.new()
	taxi.configure(_profile())
	var ground_events: Array[Dictionary] = taxi.observe(_scrape(1))
	_check("ground accident M7 retains factual cause before flight starts",
		_of(ground_events, "crash").size() == 1 and _of(ground_events, "crash")[0].kind == "gear_up_contact"
		and taxi.flight.is_empty())
	_check("first terminal gear-up contact emits one terminal incident without fake escalation",
		_of(severe_events, "accident").size() == 1 and _of(severe_events, "accident")[0].terminal
		and _of(severe_events, "accident_updated").is_empty())


func _test_damaged_hull_stop_without_landing_geometry() -> void:
	var profile := _profile()
	profile.landing_available = false
	var detector := _start(profile)
	var events: Array[Dictionary] = []
	for tick in range(3, 108):
		var stopped := _scrape(tick)
		stopped.ground_speed_3d = 0.0
		events.append_array(detector.observe(stopped))
	var landing := _of(events, "landing")
	var closed := _of(events, "closed")
	_check("physical hull rest closes as damaged_stop without a wheel stop set",
		closed.size() == 1 and closed[0].outcome == "damaged_stop")
	_check("accepted accident disqualifies landing even when success geometry is unavailable",
		landing.size() == 1 and landing[0].outcome == "failed"
		and int(landing[0].flight.failed_landings) == 1 and int(landing[0].flight.unknown_landings) == 0)
	_check("damaged full stop is neither completed nor successful",
		closed.size() == 1 and closed[0].flight.full_stops == 0 and closed[0].flight.touch_and_go == 0)
	_check("stopped scrape still has one M7", _of(events, "crash").size() == 1)
	_check("100 persistent rested scrape ticks retain one semantic accident", _of(events, "accident").size() == 1)


func _test_accident_departure_without_landing_geometry() -> void:
	var profile := _profile()
	profile.landing_available = false
	var accident := _start(profile)
	var events: Array[Dictionary] = accident.observe(_scrape(3))
	for tick in range(4, 7):
		events.append_array(accident.observe(_sample(tick)))
	var landing := _of(events, "landing")
	_check("known accident rearm fails landing despite unavailable success geometry",
		landing.size() == 1 and landing[0].outcome == "failed"
		and landing[0].reason == "disqualifying_incident")
	_check("accident departure updates failed coverage without inventing unknown or success",
		int(accident.flight.get("failed_landings", -1)) == 1
		and int(accident.flight.get("unknown_landings", -1)) == 0
		and int(accident.flight.get("touch_and_go", -1)) == 0)
	_check("accident departure continues flight with one M7 and no close",
		accident.flight.get("outcome") == "active" and _of(events, "closed").is_empty()
		and _of(events, "crash").size() == 1)
	var unclassified := _start(profile)
	unclassified.observe(_sample(3, {"supported": true, "ground_contact": true,
		"clearance_ok": false}))
	var clean_events: Array[Dictionary] = []
	for tick in range(4, 7):
		clean_events.append_array(unclassified.observe(_sample(tick)))
	var unknown := _of(clean_events, "landing")
	_check("unavailable geometry without a known incident still yields unknown departure",
		unknown.size() == 1 and unknown[0].outcome == "unknown"
		and unknown[0].reason == "classification_unavailable"
		and int(unclassified.flight.get("failed_landings", -1)) == 0)


func _test_rearm_distinct_accidents_and_previous_success() -> void:
	var detector := _start()
	for tick in range(3, 6):
		detector.observe(_sample(tick, {"supported": true, "ground_contact": true,
			"intended_support": true, "clearance_ok": false}))
	var events: Array[Dictionary] = []
	for tick in range(6, 9):
		events.append_array(detector.observe(_sample(tick)))
	_check("clean contact window followed by rearm earns one touch-and-go",
		_of(events, "landing").size() == 1 and int(detector.flight.touch_and_go) == 1)
	var first: Array[Dictionary] = detector.observe(_scrape(9))
	var id: String = str(_of(first, "accident")[0].accident_id)
	# A short bounce remains the same accident.
	detector.observe(_sample(10))
	var bounced: Array[Dictionary] = detector.observe(_scrape(11))
	_check("brief bounce and recontact share accident", _of(bounced, "accident").is_empty())
	for tick in range(12, 15):
		detector.observe(_sample(tick))
	var second: Array[Dictionary] = detector.observe(_scrape(15))
	var later := _of(second, "accident")
	_check("confirmed rearm permits distinct deterministic accident ID",
		later.size() == 1 and later[0].accident_id != id)
	_check("later distinct accident leaves generation M7 latched",
		_of(first, "crash").size() == 1 and _of(second, "crash").is_empty())
	_check("later accident preserves previously earned touch-and-go", int(detector.flight.touch_and_go) == 1)


func _test_snapshot_replay_and_legacy_coverage() -> void:
	var detector := _start()
	detector.observe(_scrape(3))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(detector.snapshot()))
	var restored: RefCounted = Detector.new()
	_check("v2 accepted accident snapshot restores through JSON", restored.restore(snapshot))
	var terminal := _scrape(4)
	terminal.terminal = true
	var original: Array[Dictionary] = detector.observe(terminal)
	var replayed: Array[Dictionary] = restored.observe(terminal)
	_check("restored accident latch and escalation emit exactly the same events",
		JSON.stringify(original) == JSON.stringify(replayed))
	_check("restored accident cannot count M7 again", _of(replayed, "crash").is_empty())
	var rolled_back: RefCounted = Detector.new()
	rolled_back.configure(_profile())
	rolled_back.observe(_sample(1))
	var before: Dictionary = rolled_back.snapshot()
	var candidate: Array[Dictionary] = rolled_back.observe(_scrape(2))
	_check("transaction can restore pre-candidate detector snapshot", rolled_back.restore(before))
	_check("rollback retry yields same ID and exactly one event batch",
		var_to_bytes(candidate) == var_to_bytes(rolled_back.observe(_scrape(2))))
	var legacy: Dictionary = before.duplicate(true)
	legacy.version = 1
	legacy.erase("accident_serial")
	legacy.erase("accident_id")
	legacy.erase("accident_terminal")
	var migrated: RefCounted = Detector.new()
	_check("legacy v1 checkpoint loads without invented accidents", migrated.restore(legacy)
		and migrated.snapshot().accident_serial == 0 and migrated.snapshot().accident_id == "")
	_check("new rules explicitly version the widened M7 meaning", Rules.VERSION == "flight-statistics-rules-v2")


func _test_rejected_and_duplicate_ticks() -> void:
	var detector := _start()
	_check("duplicate nonterminal tick cannot publish accident", detector.observe(_scrape(2)).is_empty())
	var rejected := _scrape(3)
	rejected.valid = false
	_check("invalid observation cannot publish survivable accident", detector.observe(rejected).is_empty())
	_check("invalid observation leaves M7 latch clear", not detector.snapshot().crash_emitted)
	var skipped := _start()
	_check("tick gap cannot publish nonterminal accident", skipped.observe(_scrape(4)).is_empty())
	_check("gap freezes classification rather than credit missing intervals", not skipped.snapshot().crash_emitted)
	var ended := _start()
	ended.end("abandoned")
	_check("ended detector cannot publish a late survivable accident", ended.observe(_scrape(3)).is_empty())


func _test_snapshot_rejects_inconsistent_groups() -> void:
	var detector := _start()
	detector.observe(_scrape(3))
	var before: Dictionary = detector.snapshot()
	for mutation: String in ["fractional_version", "string_version", "zero_serial", "missing_count_latch",
			"missing_incident_latch", "premature_terminal", "terminal_without_id"]:
		var bad: Dictionary = before.duplicate(true)
		match mutation:
			"fractional_version": bad.version = 2.5
			"string_version": bad.version = "2"
			"zero_serial": bad.accident_serial = 0
			"missing_count_latch": bad.crash_emitted = false
			"missing_incident_latch": bad.incident_latched = false
			"premature_terminal": bad.accident_terminal = true
			"terminal_without_id":
				bad.accident_terminal = true
				bad.phase = "terminal"
				bad.accident_id = ""
		_check("inconsistent accident snapshot rejected atomically: " + mutation,
			not detector.restore(bad) and var_to_bytes(before) == var_to_bytes(detector.snapshot()))
	var terminal := _scrape(4)
	terminal.terminal = true
	_check("rejected snapshot cannot suppress the later terminal update",
		_of(detector.observe(terminal), "accident_updated").size() == 1)


func _test_packet_identity_and_no_gear_exemption() -> void:
	var adapter: RefCounted = Adapter.new()
	var session := PacketSession.new()
	adapter.session = session
	var packet := {"schema": "openrc-aircraft-accident-observation", "version": 1,
		"tick": 3, "generation": 7, "gear_up_contact": true, "ground_contact": true,
		"intended_support": false, "terminal": false}
	_check("adapter accepts current accepted physical packet",
		adapter._accident_observation({"accident_observation": packet}).get("gear_up_contact", false))
	packet.generation = 6
	_check("adapter rejects stale generation", adapter._accident_observation({"accident_observation": packet}).is_empty())
	packet.generation = 7
	packet.tick = 2
	_check("adapter rejects stale tick", adapter._accident_observation({"accident_observation": packet}).is_empty())
	packet.tick = 3
	packet.gear_up_contact = "true"
	_check("adapter rejects coercible malformed accident flag",
		adapter._accident_observation({"accident_observation": packet}).is_empty())
	packet.gear_up_contact = true
	packet.extra = false
	_check("adapter rejects extra unversioned fields", adapter._accident_observation({"accident_observation": packet}).is_empty())
	packet.erase("extra")
	session.statistics_generation = -1
	packet.generation = -1
	_check("adapter rejects matching negative generation", adapter._accident_observation({"accident_observation": packet}).is_empty())
	session.statistics_generation = 7
	packet.generation = 7
	packet.gear_up_contact = false
	packet.intended_support = true
	_check("authored intended belly support does not become gear-up",
		not adapter._accident_observation({"accident_observation": packet}).gear_up_contact)
	var detector := _start()
	var normal := _sample(3, {"supported": true, "ground_contact": true,
		"intended_support": true, "clearance_ok": false})
	var events: Array[Dictionary] = detector.observe(normal)
	_check("intended no-gear contact has no accident or M7",
		_of(events, "crash").is_empty() and _of(events, "accident").is_empty())
	session.free()
