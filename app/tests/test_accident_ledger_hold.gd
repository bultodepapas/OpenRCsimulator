## F1 (owner decision 2026-11-26): the accident ledger holds ticks whose only events are persistent gear-support samples
## and observes them once per frame with each wheel's peak compression. A real Stik rolls and drops onto its gear while
## two ledgers observe every accepted tick, one holding samples and one per tick; frames evaluate every second tick.
## Peaks, recommendations, assessed components and damage agree; the held ledger records far fewer samples.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Incident := preload("res://economy/incident.gd")
const Events := preload("res://sim/aircraft_contact_events.gd")
const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
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


func _ledger(session: Node, hold: bool) -> Incident:
	var ledger := Incident.new()
	ledger.archive_path = "user://test_accident_ledger_hold_%s.json" % ("held" if hold else "tick")
	ledger.hold_support_samples = hold
	ledger.begin(STIK, str(session.aircraft.input_identity.sha256))
	return ledger


## Per component: [peak compression, recommendation]; and the assessed dispositions.
func _evidence(ledger: Incident) -> Dictionary:
	var summaries := {}
	for id: String in ledger._summaries:
		var summary: Dictionary = ledger._summaries[id]
		summaries[id] = [summary.peaks.get("compression_m", -1.0), summary.recommendation]
	var components := {}
	for id: String in ledger._assessment.components:
		components[id] = ledger._assessment.components[id].get("disposition", "")
	return {summaries = summaries, components = components, damage = ledger.has_damage(), open = ledger._open_contacts.keys()}


func _run() -> void:
	var session := Session.new()
	session.soft_hull_contacts = true
	session.input_enabled = false
	session.crash_auto_restart = false
	session.start_choice = Session.START_RUNWAY
	session.setup(Catalog.data_for(STIK, Catalog.default_battery_mode(STIK)), STIK)
	session.set_field(FieldLoader.load_from().field)
	session.set_lake_context(LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake)
	session.reset()
	root.add_child(session)
	session.set_physics_process(false)
	session.cost_observations_enabled = true
	var held := _ledger(session, true)
	var tick := _ledger(session, false)
	var held_results: Array = []
	var bindings: Dictionary = session.contact_contract()
	session.contact_events_changed.connect(func() -> void:
		var crashed: bool = not session.crash.is_empty()
		held_results.append(held.observe(session.contact_events(), bindings, crashed))
		tick.observe(session.contact_events(), bindings, crashed))
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	inputs[3] = 0.6
	session.sim.inputs = inputs
	for step in 1200:
		session.sim.step()
		if step % 2 == 1: # a frame
			held.evaluate_pending()
			tick.evaluate_pending()
		if step == 600: # a hard drop onto the gear: new, persistent and ended samples
			var state: PackedFloat64Array = session.sim.state.duplicate()
			state[RB.POS + 2] -= 0.6
			session.sim.state = state
	held.evaluate_pending()
	tick.evaluate_pending()
	var a := _evidence(held)
	var b := _evidence(tick)
	check("the flight touched and rolled on its gear", not b.summaries.is_empty(), str(b))
	check("held samples keep every peak and recommendation", a.summaries == b.summaries, str([a.summaries, b.summaries]))
	check("held samples assess the same components and damage", a.components == b.components and a.damage == b.damage
		and a.open == b.open, str([a, b]))
	check("every held observation was accepted", held_results.all(func(r: Dictionary) -> bool: return r.get("ok", false)))
	var held_count := held_results.filter(func(r: Dictionary) -> bool: return r.get("status") == "held").size()
	check("most rolling samples were held for the frame", held_count > 400, str(held_count))
	# A peak inside a frame: compressions rise and fall between two evaluations.
	var peak_held := _ledger(session, true)
	var peak_tick := _ledger(session, false)
	var travel: float = session.current_landing_gear().contacts[0].max_compression
	var base_tick: int = session.sim.tick + 100
	var series := [0.0, 0.2, 0.9, 0.4, 0.3, 0.95, 0.5, 0.1]
	for index in range(1, series.size()):
		var events: Array = []
		for leg in session.current_landing_gear().contacts.size():
			var event := Events.support_event(leg, travel * series[index], travel * series[index - 1],
				float(session.current_landing_gear().contacts[leg].max_compression), base_tick + index, bindings)
			if not event.is_empty():
				events.append(event)
		var snapshot := {format = "openrc-aircraft-contact-state v1", tick = base_tick + index, active_hull_ids = [],
			events = events, prop_strike = {}}
		peak_held.observe(snapshot.duplicate(true), bindings, false)
		peak_tick.observe(snapshot.duplicate(true), bindings, false)
		if index % 3 == 0:
			peak_held.evaluate_pending()
	peak_held.evaluate_pending()
	peak_tick.evaluate_pending()
	check("a peak between frames is kept", _evidence(peak_held).summaries == _evidence(peak_tick).summaries
		and not _evidence(peak_tick).summaries.is_empty(), str([_evidence(peak_held).summaries, _evidence(peak_tick).summaries]))
	# A checkpoint observes the held samples first.
	session.sim.step()
	check("a tick is held before the checkpoint", not held._held.is_empty())
	var ledger_checkpoint: Dictionary = held.checkpoint(session.sim.tick, bindings)
	check("a checkpoint releases the held samples first", held._held.is_empty(), str(ledger_checkpoint.size()))
	# A new incident (reload, restart) drops samples of the previous one.
	session.sim.step()
	check("a later tick is held again", not held._held.is_empty())
	held.begin(STIK, str(session.aircraft.input_identity.sha256))
	check("a new incident drops held samples", held._held.is_empty())
	# A held sample that fails validation is refused when released, and the next observe() reports it.
	var support := Events.support_event(0, 0.01, 0.01, 0.1, session.sim.tick + 10, bindings)
	support.lifecycle = "persistent"
	support.contact_id = "not_a_bound_contact"
	var bad := {format = "openrc-aircraft-contact-state v1", tick = session.sim.tick + 10, active_hull_ids = [],
		events = [support], prop_strike = {}}
	check("a structurally plain support sample is held", held.observe(bad, bindings, false).get("status") == "held")
	held.release_held_samples()
	var next := held.observe({format = bad.format, tick = session.sim.tick + 11, active_hull_ids = [], events = [],
		prop_strike = {}}, bindings, false)
	check("the refusal of a released sample reaches the next observe()", not next.get("ok", true), str(next))
	print("Accident ledger hold: %d checks, %d failed" % [checks, failed])
	session.queue_free()
	quit(1 if failed > 0 else 0)
