## UI-FS: detached accepted-tick observations; never evaluates forces or writes state.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Terrain = preload("res://physics/ground_terrain.gd")
var profile: Dictionary = {}
var session: Node
var _consumer: Callable
var _attached := false
var _lake: Dictionary = {}


func configure(owner: Node, aircraft_id: String, consumer: Callable) -> void:
	session = owner
	_consumer = consumer
	profile = load("res://statistics/profiles.gd").resolve(aircraft_id, session.aircraft.model, session.contact_contract())
	profile.initial_tick = int(session.sim.tick)
	profile.generation_id = str(session.statistics_generation)
	_lake = session.lake_context()


func attach() -> void:
	if _attached or not is_instance_valid(session):
		return
	session.sim.stepped.connect(_stepped)
	session.contact_events_changed.connect(_contacts)
	_attached = true


func detach() -> void:
	if _attached and is_instance_valid(session):
		if session.sim.stepped.is_connected(_stepped): session.sim.stepped.disconnect(_stepped)
		if session.contact_events_changed.is_connected(_contacts): session.contact_events_changed.disconnect(_contacts)
	_attached = false


func _stepped(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	# Simulation.reset also publishes stepped at tick zero. It is not an accepted
	# physics interval; only the session's later committed receipt changes generation.
	if _tick == 0: return
	_consumer.call(sample())


func _contacts() -> void:
	# A terminal guard may fire without a new accepted tick. The detector deduplicates its clock.
	if not session.crash.is_empty():
		_consumer.call(sample())


func sample() -> Dictionary:
	var s: PackedFloat64Array = session.sim.state
	if s.size() != 13:
		return {tick = int(session.sim.tick), dt = float(session.sim.dt()), valid = false}
	var q: PackedFloat64Array = s.slice(RB.ATT, RB.ATT + 4)
	var velocity: PackedFloat64Array = M.q_rotate(q, s.slice(RB.VEL, RB.VEL + 3))
	var rates: PackedFloat64Array = s.slice(RB.RATE, RB.RATE + 3)
	var speed: float = sqrt(velocity[0] ** 2 + velocity[1] ** 2 + velocity[2] ** 2)
	var angular: float = sqrt(rates[0] ** 2 + rates[1] ** 2 + rates[2] ** 2)
	var air: Dictionary = session.air_data(s, session.sim.time())
	var terrain: PackedFloat64Array = Terrain.sample(s[0], s[1], session.ground_surfaces, _lake)
	var normal: PackedFloat64Array = M.v3(-terrain[1], -terrain[2], -1.0)
	var body_normal: PackedFloat64Array = M.q_rotate(M.q_conj(q), normal)
	var bank: float = atan2(body_normal[1], -body_normal[2])
	var pitch: float = atan2(body_normal[0], sqrt(body_normal[1] ** 2 + body_normal[2] ** 2))
	var compression: PackedFloat64Array = session.gear_compressions(s)
	var physical := false
	var intended := false
	var stop := bool(profile.get("landing_available", false))
	for i: int in compression.size():
		var contact: bool = compression[i] > 0.00001
		physical = physical or contact
		if i in profile.get("main_indices", []): intended = intended or contact
		if i in profile.get("stop_indices", []) and not contact: stop = false
	var contacts: Dictionary = session.contact_events()
	var observation := _accident_observation(contacts)
	var uses_hull: bool = profile.get("support_kind", "") == "authored_hull" and bool(profile.get("landing_available", false))
	var hull := _hull_support_observation(contacts) if uses_hull else {}
	var hull_valid: bool = not uses_hull or (not hull.is_empty() and not observation.is_empty()
		and hull.facts.intended_support == observation.intended_support)
	var gear_up := bool(observation.get("gear_up_contact", false))
	var incident: bool = gear_up or not contacts.get("prop_strike", {}).is_empty()
	if uses_hull and not hull.is_empty():
		# Accepted active IDs, not optional compact event detail, disqualify mixed
		# or wrong-pose contacts even after an earlier clean support window.
		incident = incident or (hull.facts.touching and not hull.facts.intended_support)
	var ground_contact: bool = physical or not contacts.get("active_hull_ids", []).is_empty()
	for event: Dictionary in contacts.get("events", []):
		if event.get("lifecycle") != "ended":
			incident = incident or event.get("source") in ["scenery", "lake", "propeller"] \
				or (event.get("source") == "hull" and not bool(observation.get("intended_support", false))) \
				or event.get("response") == "terminal"
			if event.get("source") in ["hull", "gear", "lake"]: ground_contact = true
	ground_contact = ground_contact or bool(observation.get("ground_contact", false))
	physical = physical or ground_contact
	intended = intended or bool(observation.get("intended_support", false))
	var deployed := true
	if session.gear_is_retractable():
		deployed = float(session.sim.aux[session.gear_aux_index()]) >= 0.95
	var controlled: bool = absf(bank) <= deg_to_rad(15.0) \
		and absf(pitch - float(profile.get("rest_pitch_rad", 0.0))) <= deg_to_rad(20.0) \
		and angular <= 1.0 and deployed and not session.gear_collapsed(s)
	if uses_hull:
		intended = bool(hull.facts.intended_support) if not hull.is_empty() else false
		stop = bool(hull.facts.stop_support) if not hull.is_empty() else false
		controlled = bool(hull.facts.controlled) if not hull.is_empty() else false
	var reference_height: float = 0.0 if uses_hull else terrain[0]
	return {tick = int(session.sim.tick), dt = float(session.sim.dt()), valid = is_finite(terrain[0]) \
		and is_finite(float(air.get("V", NAN))) and session.sim.fault_reason.is_empty() and hull_valid,
		supported = physical, intended_support = intended and bool(profile.get("landing_available", false)),
		stop_support = stop, clearance_ok = not physical and -s[2] - reference_height >= \
		float(profile.get("rest_height_m", 0.0)) + float(profile.get("clearance_m", 0.25)),
		controlled = controlled, ground_speed_3d = speed, angular_speed = angular,
		tas = float(air.get("V", NAN)), groundspeed = sqrt(velocity[0] ** 2 + velocity[1] ** 2),
		position = s.slice(RB.POS, RB.POS + 3), velocity_ned = velocity,
		incident = incident, gear_up_contact = gear_up,
		terminal = not session.crash.is_empty() or bool(observation.get("terminal", false)),
		ground_contact = ground_contact}


## Only an accepted physical receipt may open a nonterminal accident. Missing legacy
## packets keep terminal-only compatibility; malformed/stale data cannot invent one.
func _accident_observation(contacts: Dictionary) -> Dictionary:
	var value: Variant = session.accident_observation() if session.has_method("accident_observation") \
		else contacts.get("accident_observation", {})
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var observation: Dictionary = value
	if observation.size() != 8 or typeof(observation.get("schema")) != TYPE_STRING \
		or observation.schema != "openrc-aircraft-accident-observation" \
		or typeof(observation.get("version")) != TYPE_INT or observation.version != 1:
		return {}
	if typeof(observation.get("tick")) != TYPE_INT or observation.tick < 0 or observation.tick != int(session.sim.tick) \
		or typeof(observation.get("generation")) != TYPE_INT \
		or observation.generation < 0 or observation.generation != int(session.statistics_generation):
		return {}
	for key: String in ["gear_up_contact", "ground_contact", "intended_support", "terminal"]:
		if typeof(observation.get(key)) != TYPE_BOOL:
			return {}
	if observation.gear_up_contact and (not observation.ground_contact \
		or observation.intended_support or observation.tick <= 0):
		return {}
	return observation.duplicate(true)


## Strict optional packet. This checks a shared classifier's factual output; it
## neither reruns contact detection nor owns a second landing/timing rule.
func _hull_support_observation(contacts: Dictionary) -> Dictionary:
	if not session.has_method("hull_support_observation"): return {}
	var packet: Variant = session.hull_support_observation()
	var keys := ["schema", "version", "tick", "generation", "available", "identity", "facts", "reason"]
	if not packet is Dictionary or packet.size() != keys.size() or not packet.has_all(keys): return {}
	if typeof(contacts.get("tick")) != TYPE_INT or contacts.tick != int(session.sim.tick): return {}
	if typeof(packet.schema) != TYPE_STRING or packet.schema != "openrc-aircraft-hull-support-observation" \
		or typeof(packet.version) != TYPE_INT or packet.version != 1 or typeof(packet.available) != TYPE_BOOL or not packet.available \
		or typeof(packet.tick) != TYPE_INT or packet.tick <= 0 or packet.tick != int(session.sim.tick) \
		or typeof(packet.generation) != TYPE_INT or packet.generation < 0 or packet.generation != int(session.statistics_generation) \
		or typeof(packet.identity) != TYPE_STRING or packet.identity != profile.get("hull_support_identity", "") \
		or typeof(packet.reason) != TYPE_STRING or not packet.reason.is_empty(): return {}
	var fact_keys := ["ok", "identity", "touching", "role_coverage", "role_covered", "intended_support", "stop_support",
		"controlled", "pose_within_envelope", "matched_stop_group_index", "intended_contact_ids", "incidental_contact_ids", "pose_facts"]
	var facts: Variant = packet.facts
	if not facts is Dictionary or facts.size() != fact_keys.size() or not facts.has_all(fact_keys): return {}
	for key: String in ["ok", "touching", "role_covered", "intended_support", "stop_support", "controlled", "pose_within_envelope"]:
		if typeof(facts[key]) != TYPE_BOOL: return {}
	if not facts.ok or typeof(facts.identity) != TYPE_STRING or facts.identity != packet.identity \
		or typeof(facts.matched_stop_group_index) != TYPE_INT or facts.matched_stop_group_index < -1 \
		or facts.matched_stop_group_index >= int(profile.get("hull_stop_group_count", 0)) \
		or typeof(facts.intended_contact_ids) != TYPE_PACKED_STRING_ARRAY or typeof(facts.incidental_contact_ids) != TYPE_PACKED_STRING_ARRAY \
		or typeof(contacts.get("active_hull_ids")) != TYPE_PACKED_STRING_ARRAY: return {}
	var seen := {}
	for ids: PackedStringArray in [facts.intended_contact_ids, facts.incidental_contact_ids]:
		for contact_id: String in ids:
			if seen.has(contact_id) or not contacts.active_hull_ids.has(contact_id): return {}
			seen[contact_id] = true
	if seen.size() != contacts.active_hull_ids.size() or facts.touching != not seen.is_empty(): return {}
	var covered: bool = facts.touching and facts.incidental_contact_ids.is_empty()
	var coverage := "empty" if not facts.touching else ("intended_only" if facts.incidental_contact_ids.is_empty() \
		else ("incidental_only" if facts.intended_contact_ids.is_empty() else "mixed"))
	if typeof(facts.role_coverage) != TYPE_STRING or facts.role_coverage != coverage or facts.role_covered != covered \
		or facts.intended_support != (covered and facts.pose_within_envelope) \
		or facts.stop_support != (facts.intended_support and facts.matched_stop_group_index >= 0) \
		or (facts.controlled and not facts.pose_within_envelope): return {}
	var pose: Variant = facts.pose_facts
	var pose_keys := ["roll_rad", "pitch_rad", "roll_error_rad", "pitch_error_rad", "angular_speed_radps"]
	if not pose is Dictionary or pose.size() != pose_keys.size() or not pose.has_all(pose_keys): return {}
	for key: String in pose_keys:
		if typeof(pose[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(pose[key])): return {}
	if pose.angular_speed_radps < 0.0: return {}
	return packet.duplicate(true)
