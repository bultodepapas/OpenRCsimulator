extends SceneTree

const FlightSession = preload("res://sim/flight_session.gd")
const Ground = preload("res://physics/ground_contact.gd")
const HullContact = preload("res://physics/hull_contact.gd")
const RB = preload("res://physics/rigid_body.gd")

const BATCH_CALLS := 4000
const WARM_CALLS := 300

func _measure(label: String, fn: Callable) -> void:
	for i in WARM_CALLS:
		fn.call()
	var samples: Array = []
	for batch in 3:
		var started := Time.get_ticks_usec()
		for i in BATCH_CALLS:
			fn.call()
		samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	print("%s: %0.3f us/call; batches=%s" % [label, float(samples[1]) / BATCH_CALLS, str(samples)])

func _initialize() -> void:
	var session = FlightSession.new()
	session.setup("res://data/aircraft/jensen_ugly_stik_60.json", "jensen-das-ugly-stik-60")
	root.add_child(session)
	if not session.aircraft.get("ok", false):
		push_error("FlightSession setup failed: %s" % str(session.aircraft.get("errors", [])))
		quit(2)
		return

	var gear: Dictionary = session.aircraft.model.landing_gear
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var compressions: PackedFloat64Array = Ground.compressions(state, gear, session.ground_surfaces, session._lake)
	var deepest := -INF
	for compression in compressions:
		deepest = maxf(deepest, compression)
	if not is_finite(deepest):
		push_error("No landing gear compressions available")
		quit(3)
		return
	state[RB.POS + 2] += 0.01 - deepest
	var aux: PackedFloat64Array = session.sim.aux
	var values: PackedFloat64Array = session.sim.continuous
	var prepared: Dictionary = session._hull_contact
	if prepared.is_empty():
		push_error("HullContact preparation missing")
		quit(4)
		return
	var anchors: PackedFloat64Array = aux.slice(session.AUX_ANCHORS, session.AUX_ANCHORS + session.anchor_count() * Ground.ANCHOR_STRIDE)
	var steer: float = aux[session.AUX_SERVO + 2]
	var surfaces: PackedFloat64Array = session.ground_surfaces
	var lake: Dictionary = session._lake
	print("setup: model=%s gear_contacts=%d hull_points=%d ground_surfaces=%d lake=%s hull_reach=%.3f altitude=%.3f deepest_gear_compression=%.3f aux=%d values=%d" % [
		str(session.aircraft.model.get("id", "")), gear.get("contacts", []).size(),
		prepared.get("points", PackedFloat64Array()).size() / 3, surfaces.size(), str(not lake.is_empty()),
		float(prepared.get("reach", 0.0)), -state[RB.POS + 2], deepest + 0.01, aux.size(), values.size()
	])

	var ground_fn := func() -> PackedFloat64Array:
		return Ground.loads(state, gear, steer, surfaces, anchors, PackedFloat64Array(), 0.0, lake)
	var hull_fn := func() -> PackedFloat64Array:
		return HullContact.loads(state, prepared)
	var session_ground_fn := func() -> Dictionary:
		return session._ground_evaluation(state, aux, values, {}, {})
	_measure("Ground.loads (dry/reference field inputs)", ground_fn)
	_measure("HullContact.loads (near ground)", hull_fn)
	session.soft_hull_contacts = false
	_measure("FlightSession._ground_evaluation soft_hull_contacts=false", session_ground_fn)
	session.soft_hull_contacts = true
	_measure("FlightSession._ground_evaluation soft_hull_contacts=true", session_ground_fn)
	session.queue_free()
	quit()
