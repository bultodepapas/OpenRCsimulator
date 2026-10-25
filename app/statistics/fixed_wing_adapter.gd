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
	var incident: bool = not contacts.get("prop_strike", {}).is_empty()
	var ground_contact: bool = physical or not contacts.get("active_hull_ids", []).is_empty()
	for event: Dictionary in contacts.get("events", []):
		if event.get("lifecycle") != "ended":
			incident = incident or event.get("source") in ["hull", "scenery", "lake", "propeller"] \
				or event.get("response") == "terminal"
			if event.get("source") in ["hull", "gear", "lake"]: ground_contact = true
	physical = physical or ground_contact
	var deployed := true
	if session.gear_is_retractable():
		deployed = float(session.sim.aux[session.gear_aux_index()]) >= 0.95
	var controlled: bool = absf(bank) <= deg_to_rad(15.0) \
		and absf(pitch - float(profile.get("rest_pitch_rad", 0.0))) <= deg_to_rad(20.0) \
		and angular <= 1.0 and deployed and not session.gear_collapsed(s)
	return {tick = int(session.sim.tick), dt = float(session.sim.dt()), valid = is_finite(terrain[0]) \
		and is_finite(float(air.get("V", NAN))) and session.sim.fault_reason.is_empty(),
		supported = physical, intended_support = intended and bool(profile.get("landing_available", false)),
		stop_support = stop, clearance_ok = not physical and -s[2] - terrain[0] >= \
		float(profile.get("rest_height_m", 0.0)) + float(profile.get("clearance_m", 0.25)),
		controlled = controlled, ground_speed_3d = speed, angular_speed = angular,
		tas = float(air.get("V", NAN)), groundspeed = sqrt(velocity[0] ** 2 + velocity[1] ** 2),
		position = s.slice(RB.POS, RB.POS + 3), velocity_ned = velocity,
		incident = incident, terminal = not session.crash.is_empty(), ground_contact = ground_contact}
