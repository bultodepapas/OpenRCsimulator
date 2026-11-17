extends SceneTree
const State := preload("res://app_state/creator_selection_state.gd")
const Selection := preload("res://app_state/creator_selection.gd")
const SourceRef := preload("res://workshop/creator/source_ref.gd")
const Resolver := preload("res://workshop/creator/source_resolver.gd")
const Store := preload("res://workshop/creator/store.gd")
const Publication := preload("res://workshop/creator/compiled_publication.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const Definition := preload("res://workshop/creator/definition.gd")
const AuthoringFixture := preload("res://tests/creator_authoring_fixture.gd")
const Fixture := preload("res://tests/creator_fixtures.gd")
var checks := 0
var failures := 0


func check(label: String, good: bool) -> void:
	checks += 1
	if not good:
		failures += 1
		printerr("FAIL selection state: ", label)


func _initialize() -> void:
	_run()
	print("Creator selection state: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _owners() -> Dictionary:
	var inspected: Dictionary = Importer.inspect_bytes(Fixture.airplane_glb(), "state.glb")
	check("state fixture source admitted", inspected.ok)
	if not inspected.ok:
		return {}
	var doc: RefCounted = AuthoringFixture.populated(inspected.value)
	doc.name = "State A"
	doc.set_servo_integration(Definition.ServoLaw.LAW)
	var root := "user://creator_selection_state_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = Store.open(root)
	check("state fixture writer opens", opened.ok and opened.value.is_writer())
	if not opened.ok:
		return {}
	var out := {}
	for index: int in 2:
		if index == 1:
			doc.name = "State B"
			doc.set_value("controls/servo_time_s", 0.2)
		var captured: Dictionary = Publication.capture(doc, "review_test")
		check("state fixture captures", captured.ok)
		if not captured.ok:
			opened.value.close()
			return {}
		var saved: Dictionary = opened.value.publish_compiled_aircraft(captured.value, index)
		check("state fixture publishes exact revision", saved.ok)
		if not saved.ok:
			opened.value.close()
			return {}
		var ref: Dictionary = SourceRef.make(doc.aircraft_uuid(), index + 1, saved.value.record_sha256).value
		var resolved: Dictionary = Resolver.resolve(root, ref)
		check("state fixture resolves", resolved.ok)
		if not resolved.ok:
			opened.value.close()
			return {}
		out["a" if index == 0 else "b"] = resolved.value
	opened.value.close()
	return out


func _run() -> void:
	var owners := _owners()
	if owners.is_empty():
		return
	var a: Dictionary = Selection.make(owners.a.source_ref(), "airborne").value
	var b: Dictionary = Selection.make(owners.b.source_ref(), "airborne").value
	var state := State.new(a)
	check("restored exact selection starts resolving without stock fallback", state.has_creator() and not state.is_stock()
		and not state.is_unknown() and state.selection() == a and state.source_status() == "loading" and state.source_owner() == null)
	var ticket_a: Dictionary = state.source_ticket()
	var replacement := State.new(a)
	check("rebuilt state refuses a prior instance callback with the same ref and generation",
		replacement.source_ticket().generation == ticket_a.generation
		and not replacement.finish_resolution(ticket_a, {ok = true, value = owners.a})
		and replacement.source_status() == "loading" and replacement.source_owner() == null)
	check("rebuilt state accepts only its own callback", replacement.finish_resolution(replacement.source_ticket(), {ok = true, value = owners.a})
		and replacement.source_owner() == owners.a)
	check("explicit B replaces A and clears its source", state.select_creator(b) and state.selection() == b and state.source_owner() == null)
	var ticket_b: Dictionary = state.source_ticket()
	check("reverse completion cannot show A under selected B", not state.finish_resolution(ticket_a, {ok = true, value = owners.a})
		and state.selection() == b and state.source_status() == "loading" and state.source_owner() == null)
	check("matching callback with wrong real owner remains unavailable", state.finish_resolution(ticket_b, {ok = true, value = owners.a})
		and state.source_status() == "unavailable" and state.selection() == b and state.source_owner() == null)
	check("same callback cannot run twice", not state.finish_resolution(ticket_b, {ok = true, value = owners.b}))
	check("retry creates a fresh source generation", state.retry_source() and state.source_ticket().generation != ticket_b.generation)
	ticket_b = state.source_ticket()
	check("matching exact B becomes preview ready", state.finish_resolution(ticket_b, {ok = true, value = owners.b})
		and state.source_status() == "ready" and state.source_owner() == owners.b)
	check("late duplicate failure cannot clear ready B", not state.finish_resolution(ticket_b, {ok = false}) and state.source_owner() == owners.b)
	check("start-only choice retains exact source owner", state.select_start("hand_launch") and state.source_owner() == owners.b
		and state.source_ticket().generation == ticket_b.generation and state.selection().start_choice == "hand_launch")
	check("unsupported start preserves selected choice", not state.select_start("runway") and state.selection().start_choice == "hand_launch")
	var b_hand: Dictionary = state.selection()
	var intent: Dictionary = state.change_intent().value
	check("explicit transition pins prior acknowledged A and requested B", intent.before == a and intent.after == b_hand)
	check("successful save advances only acknowledged state", state.acknowledge_saved(intent) and state.persisted_selection() == b_hand)
	state.select_stock()
	check("explicit stock invalidates in-flight source callbacks", state.is_stock() and state.source_owner() == null
		and not state.finish_resolution(ticket_b, {ok = true, value = owners.b}))
	check("unsaved stock choice retains prior disk expectation", state.change_intent().value.before == b_hand and state.change_intent().value.after.is_empty())
	check("next explicit choice can retry after a save failure", state.select_creator(a)
		and state.change_intent().value.before == b_hand and state.change_intent().value.after == a)
	intent = state.change_intent().value
	state.select_creator(b)
	check("reentrant UI choice does not erase an acknowledged disk receipt", state.acknowledge_saved(intent)
		and state.persisted_selection() == a and state.selection() == b)
	check("next intent uses acknowledged A while retaining current B", state.change_intent().value.before == a and state.change_intent().value.after == b)
	check("stale disk receipt cannot acknowledge twice", not state.acknowledge_saved(intent) and state.persisted_selection() == a)
	var before_reconcile: Dictionary = state.source_ticket()
	check("fresh disk reconciliation retains unsaved UI choice and source generation", state.reconcile_persisted(b_hand)
		and state.selection() == b and state.source_ticket() == before_reconcile
		and state.change_intent().value.before == b_hand and state.change_intent().value.after == b)
	check("malformed reconciliation cannot change disk expectation", not state.reconcile_persisted(false)
		and state.persisted_selection() == b_hand and state.selection() == b)
	var copy: Dictionary = state.selection()
	copy.source_ref.revision = 999
	check("choice getter is detached", state.selection() == b)
	var ticket: Dictionary = state.source_ticket()
	var original_ticket: Dictionary = ticket.duplicate(true)
	ticket.source_ref.revision = 999
	check("ticket getter is detached", state.source_ticket() == original_ticket)
	for bad: Variant in [null, false, {}, [], {"generation": 1.0, "source_ref": b.source_ref},
			{"generation": original_ticket.generation, "source_ref": false}]:
		check("malformed callback ticket refuses quietly", not state.finish_resolution(bad, {ok = true, value = owners.b}) and state.source_status() == "loading")
	check("malformed successful result stays unavailable without fallback", state.finish_resolution(original_ticket, {ok = 1, value = owners.b})
		and state.source_status() == "unavailable" and state.selection() == b and not state.is_stock())
	var unknown := State.new(a, true)
	check("unknown preference state is neither active stock nor a loadable Creator", unknown.is_unknown() and not unknown.is_stock()
		and not unknown.has_creator() and unknown.source_ticket().is_empty() and unknown.source_owner() == null)
	check("invalid selection cannot clear unknown state", not unknown.select_creator({}) and unknown.is_unknown())
	unknown.select_stock()
	check("only an explicit known stock choice clears unknown state", unknown.is_stock() and not unknown.is_unknown())
	var malformed := State.new({"invalid": true})
	check("malformed restored choice stays unknown", malformed.is_unknown() and not malformed.is_stock())
