extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const World := preload("res://scenery/collision_world.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	for path: String in ["res://data/aircraft/stik_glow_55ax_2t.json", "res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json"]:
		print("Finite contact fixture: ", path)
		_test_glow_contact_rollback(path)
	_test_mass_contact_checkpoint_marker()
	print("R05-B FlightSession integration review: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: %s %s" % [label, detail])
	else:
		print("PASS: %s" % label)


func _glow_session(path: String = "res://data/aircraft/stik_glow_55ax_2t.json") -> Node:
	var session: Node = Flight.new()
	session.setup(path)
	session.input_enabled = false
	return session


## Place the 0.07 m flood pole so the forward-most centreline hull probe crosses it mid-way through the first
## 0.5 m tick. A fixed north = 1.0 sat at the very end of the sweep and broke when the datum moved (FUEL-05a).
func _install_obstacle(session: Node) -> bool:
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var forward := -INF
	for index: int in range(0, hull.size(), 3):
		if absf(hull[index + 1]) < 0.07:
			forward = maxf(forward, hull[index])
	var pole_north: float = forward + 0.07 + 0.25
	var built: Dictionary = World.build({pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []},
		{groups = []}, {fixtures = [{id = "r05b-contact", type = "flood", north = pole_north, east = 0.0, height = 8.0}]})
	return bool(built.get("ok", false)) and bool(session.set_collision_world(built.world))


func _collision_state() -> PackedFloat64Array:
	# Move the estimated tail probe across the pole at 120 m/s, avoiding the Glow model's invalid 2,400 m/s stage.
	return RB.make_state(PackedFloat64Array([0.0, 0.0, -4.0]), PackedFloat64Array([120.0, 0.0, 0.0]),
		M.q_identity(), PackedFloat64Array([0.0, 0.0, 0.0]))


func _test_glow_contact_rollback(path: String) -> void:
	var session: Node = _glow_session(path)
	_check("finite session is flyable and dynamic-mass joint hook is installed",
		session.is_flyable() and session.finite_fuel_is_active() and session.sim.model.post_tick_joint.is_valid()
		and not session.sim.model.post_tick.is_valid())
	if not session.is_flyable():
		session.free()
		return
	_check("deterministic obstacle installs", _install_obstacle(session))
	var initial := _collision_state()
	_check("interior-sweep collision start resets", session.sim.reset(initial), str(session.sim.fault_reason))
	var start_checkpoint: Dictionary = session.checkpoint()
	_check("Glow contact fixture has a restorable pre-impact checkpoint", not start_checkpoint.is_empty())
	var before := _session_bytes(session)
	var staged: Array[Dictionary] = []
	var filter_calls: Array[Dictionary] = []
	var step_signals := [0]
	var contact_signals := [0]
	session.sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array,
			_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
		step_signals[0] += 1)
	session.contact_events_changed.connect(func() -> void: contact_signals[0] += 1)
	var production_filter: Callable = session.sim.model.post_tick_joint
	var production_aux: Callable = session.sim.model.block_aux
	session.sim.model.post_tick_joint = func(previous: PackedFloat64Array, candidate: PackedFloat64Array,
			next_tick: int, previous_continuous: PackedFloat64Array,
			candidate_continuous: PackedFloat64Array) -> PackedFloat64Array:
			filter_calls.append({tick = next_tick, previous_north = previous[RB.POS], candidate_north = candidate[RB.POS],
				previous_fuel = previous_continuous[1], candidate_fuel = candidate_continuous[1],
				hit_probe = session._scenery_hit(previous, candidate, next_tick,
					session._contact_mass_sampler(previous_continuous, candidate_continuous))})
			var accepted_candidate: PackedFloat64Array = production_filter.call(previous, candidate, next_tick,
				previous_continuous, candidate_continuous)
			if session._pending_scenery_event != null:
				var event: Variant = session._pending_scenery_event
				staged.append({tick = session._pending_contact_tick, obstacle_id = event.obstacle_id,
					fraction = event.time_fraction, properties = event.contact_mass_properties.duplicate(true)})
			elif session._pending_crash != null:
				staged.append({tick = session._pending_contact_tick, obstacle_id = session._pending_crash.obstacle_id,
					fraction = session._pending_crash.crossing.fraction if session._pending_crash.crossing != null else 0.0})
			return accepted_candidate
	# Inject only after the real contact hook runs; same-size NaN makes the final projection fail closed.
	var bad_aux := PackedFloat64Array()
	for _i in session.sim.aux.size():
		bad_aux.append(NAN)
	session.sim.model.block_aux = func(_extra: PackedFloat64Array, _sampled: PackedFloat64Array) -> PackedFloat64Array:
		return bad_aux.duplicate()
	session.sim.step()
	if staged.size() == 1:
		print("Provisional Glow impact sample: ", staged[0])
	_check("real mass-aware filter staged one interior-fraction contact with an event-time sample",
		staged.size() == 1 and staged[0].tick == 1 and float(staged[0].fraction) > 0.0
		and float(staged[0].fraction) < 1.0 and staged[0].properties is Dictionary
		and float(staged[0].properties.mass_kg) > 0.0,
		str("staged=", staged, " filter_calls=", filter_calls, " fault=", session.sim.fault_reason))
	if staged.size() == 1 and staged[0].has("properties"):
		var sample: Dictionary = staged[0].properties
		_check("impact mass and typed fuel share one interpolated inventory and time",
			sample.get("format") == "openrc-mass-sample v1" and sample.stores.size() > 0
			and sample.tick == 1 and sample.time_s == float(staged[0].fraction) * session.sim.dt()
			and sample.sample_boundary == "swept_contact_linear_inventory" and sample.fuel_remaining_kg > 0.0)
	_check("post-contact projection failure faults before the flight tick commits",
		not session.sim.fault_reason.is_empty() and session.sim.tick == 0 and session.sim.paused,
		str(session.sim.fault_reason))
	_check("Glow body, fuel tail, auxiliary and contact history roll back byte-exactly",
		_session_bytes(session) == before,
		str("state=", session.sim.state, " fuel=", session.sim.continuous[1], " history=", session.contact_events()))
	_check("pending impact, crash, scenery damage and accepted event publication are cleared",
		session._pending_contact_tick == -1 and session._pending_scenery_event == null
		and session._pending_crash == null and session._pending_lake_event == null
		and session._pending_scenery_damage.is_empty() and session.crash.is_empty()
		and session.last_scenery_event() == null and session.scenery_damage().is_empty()
		and session.contact_events().events.is_empty() and step_signals[0] == 0 and contact_signals[0] == 0,
		str("pending tick=", session._pending_contact_tick, " stepped=", step_signals[0],
			" event signals=", contact_signals[0]))
	if staged.size() == 1 and not start_checkpoint.is_empty():
		var rejected_stage: Dictionary = staged[0].duplicate(true)
		session.sim.model.block_aux = production_aux
		var restore_ok: bool = session.restore_checkpoint(start_checkpoint)
		session.sim.set_paused(false)
		staged.clear()
		filter_calls.clear()
		session.sim.step()
		_check("same Glow state retries and commits exactly one impact",
			restore_ok and session.sim.tick == 1 and session.sim.fault_reason.is_empty()
			and staged.size() == 1 and not session.crash.is_empty()
			and session.contact_events().events.size() == 1 and step_signals[0] == 1,
			str("restore=", restore_ok, " tick=", session.sim.tick, " staged=", staged,
				" events=", session.contact_events().events.size()))
		if staged.size() == 1:
			_check("accepted retry reuses identical deterministic TOI and sampled properties",
				float(staged[0].fraction) == float(rejected_stage.fraction)
				and var_to_bytes(staged[0].properties) == var_to_bytes(rejected_stage.properties),
				str("rejected=", rejected_stage, " retry=", staged[0]))
	session.free()


func _test_mass_contact_checkpoint_marker() -> void:
	var glow: Node = _glow_session()
	var glow_checkpoint: Dictionary = glow.checkpoint()
	_check("Glow checkpoint records the separate mass-contact law",
		glow.is_flyable() and glow_checkpoint.get("mass_contact_law") == "fixed-datum-live-mass-contact-linear-fuel-v1")
	if not glow_checkpoint.is_empty():
		var glow_before := _session_bytes(glow)
		var missing: Dictionary = glow_checkpoint.duplicate(true)
		missing.erase("mass_contact_law")
		_check("Glow restore refuses a checkpoint missing the mass-contact marker",
			not glow.restore_checkpoint(missing) and _session_bytes(glow) == glow_before)
		var wrong: Dictionary = glow_checkpoint.duplicate(true)
		wrong.mass_contact_law = "unknown-mass-contact-law"
		_check("Glow restore refuses a different mass-contact marker atomically",
			not glow.restore_checkpoint(wrong) and _session_bytes(glow) == glow_before)
	glow.free()
	var legacy: Node = Flight.new()
	legacy.input_enabled = false
	legacy.setup()
	var legacy_checkpoint: Dictionary = legacy.checkpoint()
	_check("non-Glow checkpoint does not claim the Glow mass-contact law",
		legacy.is_flyable() and not legacy.glow_is_active() and not legacy_checkpoint.has("mass_contact_law"))
	if not legacy_checkpoint.is_empty():
		var with_marker: Dictionary = legacy_checkpoint.duplicate(true)
		with_marker.mass_contact_law = "fixed-datum-live-mass-contact-linear-fuel-v1"
		var legacy_before := _session_bytes(legacy)
		_check("non-Glow restore refuses an unexpected mass-contact marker atomically",
			not legacy.restore_checkpoint(with_marker) and _session_bytes(legacy) == legacy_before)
	legacy.free()


func _session_bytes(session: Node) -> PackedByteArray:
	return var_to_bytes([session.sim.state, session.sim.previous, session.sim.continuous, session.sim.aux,
		session.sim.modes, session.sim.last_loads, session.sim.tick, session.contact_events(),
		session.prop_strike, session.crash, session.scenery_damage()])
