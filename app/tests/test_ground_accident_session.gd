## GP-14a: real accepted belly contacts, observer noninterference and durable accident identity.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Service := preload("res://statistics/service.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Rules := preload("res://statistics/rules.gd")
const AVANTI := "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID := "sebart-avanti-s-a200-p100rx"

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_belly_continues()
	_rejected_interval()
	_persistent_escalation()
	print("GP-14 live sessions: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _session() -> Node:
	var session := Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(AVANTI, AVANTI_ID)
	return session


func _belly(session: Node, clearance: float) -> PackedFloat64Array:
	var lowest := -INF
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	for i in range(2, hull.size(), 3):
		lowest = maxf(lowest, hull[i])
	return RB.make_state(M.v3(0, 0, -(lowest + clearance)), M.v3(12, 0, 1),
		PackedFloat64Array([1, 0, 0, 0]), M.v3(0, 0, 0))


func _crash_rows(data: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in data.records:
		if record.kind == "crash": rows.append(record)
	return rows


func _belly_continues() -> void:
	var player := _session()
	var reference := _session()
	check("real retractable Avanti loaded", player.aircraft.get("ok", false) and player.gear_is_retractable())
	check("air start has fully retracted gear", player.sim.aux[player.gear_aux_index()] == 0.0)
	check("controlled belly initial state installs", player.sim.reset(_belly(player, 0.01))
		and reference.sim.reset(_belly(reference, 0.01)))
	var service := Service.new()
	check("memory-only statistics opens", service.setup("", false))
	service.begin_activity(player, AVANTI_ID, "Avanti")
	check("persistent episode namespace uses activity UUID, not a reused session counter",
		service.detector.snapshot().profile.generation_id == service._generation
		and service._generation.length() == 32)
	check("tick zero cannot invent an accident", not player.accident_observation().gear_up_contact
		and service.query().crashes == 0)
	var first_tick := -1
	var first_x := 0.0
	var touching_ticks := 0
	var exact := true
	for tick in 900:
		player._physics_process(player.sim.dt())
		reference._physics_process(reference.sim.dt())
		player.sim.step()
		reference.sim.step()
		var observation: Dictionary = player.accident_observation()
		if observation.gear_up_contact:
			touching_ticks += 1
			if first_tick < 0:
				first_tick = player.sim.tick
				first_x = player.sim.state[RB.POS]
		exact = exact and player.sim.state.to_byte_array() == reference.sim.state.to_byte_array()
	check("actual gear-up belly contact observed over accepted intervals", first_tick > 0 and touching_ticks > 100)
	check("gentle belly contact preserves physical continuation", player.crash.is_empty()
		and not player.sim.paused and player.sim.tick == 900 and player.sim.fault_reason.is_empty())
	check("aircraft moves after belly contact", player.sim.state[RB.POS] > first_x + 1.0)
	check("statistics and receipt reads leave every body state byte-exact", exact)
	check("observation leaves entire simulation checkpoint byte-exact",
		var_to_bytes(player.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint()))
	var rows := _crash_rows(service.data)
	check("persistent scrape records one nonterminal crash with factual cause", rows.size() == 1
		and rows[0].metadata.kind == "gear_up_contact" and not rows[0].metadata.terminal
		and rows[0].metadata.rules_version == Rules.VERSION)
	check("real accident ledger validates and counts exactly once", service.query().ok and service.query().crashes == 1)
	check("gear-up contact cannot earn a successful landing", service.query().completed == 0)
	var receipt: Dictionary = player.accident_observation()
	var before_receipt := var_to_bytes(receipt)
	receipt.gear_up_contact = not receipt.gear_up_contact
	check("receipt is detached from session", var_to_bytes(player.accident_observation()) == before_receipt)
	var saved: Dictionary = player.checkpoint()
	check("contact checkpoint retains v1 envelope", not saved.is_empty()
		and saved.contact_state.format == "openrc-aircraft-contact-state v1" and saved.contact_state.size() == 5)
	check("checkpoint restore succeeds without extra accident", player.restore_checkpoint(saved)
		and service.query().crashes == 1)
	player.sim.set_paused(false)
	for tick in 12: player.sim.step()
	check("checkpoint experiments do not count replayed scrape", service.query().crashes == 1)
	var generation: int = player.statistics_generation
	player.reset()
	check("committed reset clears physical accident receipt", not player.accident_observation().gear_up_contact
		and player.accident_observation().tick == 0 and player.statistics_generation == generation + 1
		and not service._branch and service.detector.snapshot().profile.generation_id == service._generation)
	check("session closure succeeds", service.end_activity())
	service.close()
	service.free()
	player.free()
	reference.free()
	var fixed := Session.new()
	fixed.input_enabled = false
	fixed.soft_hull_contacts = true
	fixed.setup()
	fixed.sim.reset(_belly(fixed, -0.01))
	fixed.sim.step()
	check("accepted fixed-gear hull contact is not classified as gear-up", fixed.sim.tick == 1
		and fixed.accident_observation().ground_contact and not fixed.gear_is_retractable()
		and not fixed.accident_observation().gear_up_contact)
	fixed.free()


func _rejected_interval() -> void:
	var session := _session()
	session.sim.reset(_belly(session, -0.00001))
	var service := Service.new()
	service.setup("", false)
	service.begin_activity(session, AVANTI_ID, "Avanti")
	var before := var_to_bytes(session.accident_observation())
	session.sim.model.post_tick = func(_previous: PackedFloat64Array, _candidate: PackedFloat64Array,
			_tick: int) -> PackedFloat64Array: return PackedFloat64Array([NAN])
	session.sim.step()
	check("rejected physical interval has no accepted accident receipt", session.sim.tick == 0
		and not session.sim.fault_reason.is_empty() and var_to_bytes(session.accident_observation()) == before)
	check("rejected interval cannot persist a crash", service.query().crashes == 0)
	service.end_activity()
	service.close()
	service.free()
	session.free()


func _persistent_escalation() -> void:
	var path := "user://gp14_accident_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var service := Service.new()
	check("isolated durable ledger opens", service.setup(path, true))
	var player := _session()
	service.begin_activity(player, AVANTI_ID, "Avanti")
	# This is a persistence fixture, separate from the real physical slide above.
	# The detector's real event sequence is covered by test_ground_accidents.gd.
	var event := {type = "crash", accident_id = "g0:a1:t12", event_id = "g0:a1:t12:m7",
		kind = "gear_up_contact", tick = 12, terminal = false, ground = true, rules_version = Rules.VERSION}
	service._ingest([event])
	var snapshot: Dictionary = service._write_snapshot()
	var snapshot_bytes := var_to_bytes(snapshot)
	service._ingest([{type = "accident_updated", accident_id = event.accident_id,
		event_id = "g0:a1:t12:terminal", tick = 18, terminal = true, ground = true, rules_version = Rules.VERSION}])
	var rows := _crash_rows(service.data)
	check("escalation replaces record without changing an in-flight writer snapshot",
		var_to_bytes(snapshot) == snapshot_bytes and not _crash_rows(snapshot)[0].metadata.terminal)
	check("escalation retains exactly one crash, cause and original identity", rows.size() == 1
		and rows[0].metadata.terminal and rows[0].metadata.kind == "gear_up_contact"
		and rows[0].metadata.event_id == event.event_id and rows[0].metadata.terminal_event_id == "g0:a1:t12:terminal")
	check("escalated ledger saves", service.end_activity())
	service.close()
	service.free()
	var reopened := Service.new()
	check("durable accident ledger reopens", reopened.setup(path, true))
	var restored := _crash_rows(reopened.data)
	check("saved cause, terminal state and rules survive restart", reopened.query().ok and restored.size() == 1
		and restored[0].metadata.terminal and restored[0].metadata.kind == "gear_up_contact"
		and restored[0].metadata.rules_version == Rules.VERSION)
	reopened.close()
	reopened.free()
	player.free()
	# Only remove this fixture's explicitly enumerated files; never player statistics.
	var absolute := ProjectSettings.globalize_path(path)
	for file: String in DirAccess.get_files_at(absolute):
		DirAccess.remove_absolute(absolute.path_join(file))
	DirAccess.remove_absolute(absolute)
