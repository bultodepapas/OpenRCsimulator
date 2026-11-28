## F1: the accident ledger serializes a released gear-support batch from per-wheel templates (Incident._support_texts).
## - Parity: the batch's JSON size and every event digest equal the engine's JSON.stringify() and _event_digest() for a
##   real rolling Stik and for adversarial batches (extreme compressions, large ticks, quotes, backslashes, control and
##   non-ASCII characters in contact IDs, wheels whose travel changes).
## - An invalid batch gets no texts, and an oversized valid batch is refused as an overflow on both paths.
## - Two ledgers fed the same rolling flight, with and without templates, end in the same state.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Incident := preload("res://economy/incident.gd")
const Events := preload("res://sim/aircraft_contact_events.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const STIK := "jensen-das-ugly-stik-60"

var checks := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)


## The engine's reference: [size, digests] of a batch.
func _reference(events: Array) -> Array:
	var digests := PackedStringArray()
	for event: Dictionary in events:
		digests.append(Incident._event_digest(event))
	return [JSON.stringify(events).to_utf8_buffer().size(), digests]


func _batch(bindings: Dictionary, tick: int, compressions: Array, travels: Array, previous := 0.01) -> Dictionary:
	var events: Array = []
	for index: int in compressions.size():
		var event := Events.support_event(index, compressions[index], previous, travels[index], tick, bindings)
		if not event.is_empty():
			events.append(event)
	return {tick = tick, events = events}


func _parity(label: String, ledger: Incident, snapshot: Dictionary, bindings: Dictionary) -> bool:
	var texts: Dictionary = ledger._support_texts(snapshot, bindings)
	var reference := _reference(snapshot.events)
	var same: bool = not texts.is_empty() and int(texts.size) == reference[0] and texts.digests == reference[1]
	check(label, same, "%s vs %s" % [str(texts.get("size")), str(reference[0])])
	return same


func _run() -> void:
	_adversarial()
	_refusals()
	_flight()
	print("accident support texts: %d checks, %d failed" % [checks, failed])
	quit(1 if failed > 0 or checks == 0 else 0)


func _adversarial() -> void:
	var ids := ["contact_main_left", "wheel \"quoted\" \\ back", "tab\tnew\nline\u0001", "rueda_ñandú_引擎_🛞", "x"]
	var bindings := {support_points = []}
	var renamed := {support_points = []}
	for id: String in ids:
		bindings.support_points.append({id = id})
		renamed.support_points.append({id = id + "_renamed"})
	var ledger := Incident.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var special := [0.0, 5e-324, 1e-300, 1.0e-12, 0.1, 0.019773364758360001, 1.0, 9.999999999999999, 1.0e15, 1.0e300,
		1.7976931348623157e308]
	var mismatches := 0
	var samples := 0
	var lifecycles := {}
	for round: int in 400:
		var tick: int = rng.randi_range(1, 2000000) if round % 4 else rng.randi_range(1, 9007199254740991)
		var compressions: Array = []
		var travels: Array = []
		for index: int in ids.size():
			compressions.append(special[rng.randi() % special.size()] if round % 3 == 0 else rng.randf_range(0.0, 0.2))
			travels.append(0.1 if round % 5 else special[1 + rng.randi() % (special.size() - 1)])
		# Every seventh round renames the contacts at the same indices; every sixth starts new contacts.
		var round_bindings: Dictionary = renamed if round % 7 == 0 else bindings
		var snapshot := _batch(round_bindings, tick, compressions, travels, 0.0 if round % 6 == 0 else 0.01)
		if snapshot.events.is_empty():
			continue
		samples += 1
		for event: Dictionary in snapshot.events:
			lifecycles[event.lifecycle] = true
		var texts: Dictionary = ledger._support_texts(snapshot, round_bindings)
		var reference := _reference(snapshot.events)
		if texts.is_empty() or int(texts.size) != reference[0] or texts.digests != reference[1]:
			mismatches += 1
	check("adversarial batches serialize exactly (%d batches)" % samples, mismatches == 0 and samples > 300,
		str(mismatches))
	check("the templates stayed enabled", ledger.support_templates)
	check("the batches cover the new, persistent and ended lifecycles", lifecycles.size() == 3, str(lifecycles.keys()))


func _refusals() -> void:
	var bindings := {support_points = [{id = "contact_main_left"}, {id = "contact_main_right"}]}
	var ledger := Incident.new()
	var snapshot := _batch(bindings, 40, [0.02, 0.03], [0.1, 0.1])
	_parity("a valid batch gets texts", ledger, snapshot, bindings)
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.events[0].policy = "forged"
	check("an invalid batch gets no texts", ledger._support_texts(invalid, bindings).is_empty())
	var wrong_tick: Dictionary = snapshot.duplicate(true)
	wrong_tick.tick = 41
	check("a batch at another tick gets no texts", ledger._support_texts(wrong_tick, bindings).is_empty())
	check("an empty batch gets no texts", ledger._support_texts({tick = 40, events = []}, bindings).is_empty())
	# 64 wheels with long non-ASCII IDs: valid, but larger than MAX_EVENT_BYTES. Both paths refuse it as an overflow.
	var wide := {support_points = []}
	var compressions: Array = []
	var travels: Array = []
	for index: int in Incident.MAX_EVENTS_PER_TICK:
		wide.support_points.append({id = "%03d" % index + "引".repeat(200)})
		compressions.append(0.02)
		travels.append(0.1)
	var big := _batch(wide, 50, compressions, travels)
	check("the oversized batch is valid", Events.validate_events(big.events, 50, wide))
	check("the oversized batch exceeds the bound", JSON.stringify(big.events).to_utf8_buffer().size() > Incident.MAX_EVENT_BYTES)
	var statuses: Array = []
	for templates: bool in [true, false]:
		var held := Incident.new()
		held.archive_path = "user://test_accident_support_texts_overflow.json"
		held.support_templates = templates
		held.begin(STIK, "support-texts-overflow")
		var texts: Dictionary = held._support_texts(big, wide) if templates else {}
		statuses.append(held._observe_now(big.duplicate(true), wide, false, false, texts).get("status"))
	check("both paths refuse the oversized batch as an overflow", statuses == ["overflow", "overflow"], str(statuses))


func _flight() -> void:
	var session := Session.new()
	session.soft_hull_contacts = true
	session.input_enabled = true
	session.crash_auto_restart = false
	session.start_choice = Session.START_RUNWAY
	session.setup(Catalog.data_for(STIK, Catalog.default_battery_mode(STIK)), STIK)
	session.set_field(FieldLoader.load_from().field)
	session.reset()
	session.cost_observations_enabled = true
	session.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.0, yaw = 0.2 if session.sim.tick % 600 > 300 else -0.2, throttle = 0.3}
	var bindings: Dictionary = session.contact_contract()
	var ledgers: Array = []
	for templates: bool in [true, false]:
		var ledger := Incident.new()
		ledger.archive_path = "user://test_accident_support_texts_%s.json" % ("templates" if templates else "engine")
		ledger.support_templates = templates
		ledger.begin(STIK, str(session.aircraft.input_identity.sha256))
		ledgers.append(ledger)
	var releases := 0
	var statuses: Array = [[], []]
	for tick in 2400:
		var dt: float = session.sim.dt()
		session._physics_process(dt)
		session.sim._physics_process(dt)
		var snapshot: Dictionary = session.contact_events()
		for k: int in ledgers.size():
			statuses[k].append(ledgers[k].observe(snapshot.duplicate(true), bindings, not session.crash.is_empty()))
		if tick % 4 == 3:
			if not ledgers[0]._held.is_empty():
				releases += 1
			for ledger: Incident in ledgers:
				ledger.release_held_samples()
	check("the flight released held support batches", releases > 300, str(releases))
	check("the templated ledger kept its templates", ledgers[0].support_templates)
	var states: Array = []
	for ledger: Incident in ledgers:
		states.append(var_to_bytes([ledger._seen, ledger._seen_order, ledger._summaries, ledger._assessment,
			ledger._open_contacts, ledger._last_tick, ledger._tick_event_count, ledger.journal, ledger._revision,
			ledger._journal_bytes, ledger._proof_floor_tick, ledger._evidence_overflow, ledger._held_refusal,
			ledger.terminal, ledger._confirmed_facts, ledger._fact_revisions, ledger._prior_history_unknown]))
	check("ledgers with and without templates end in the same state", states[0] == states[1])
	check("both ledgers answered every observation alike", statuses[0] == statuses[1])
	session.free()
