extends SceneTree
## NK-5f: the session publishes the contact observer's wheel compressions of the accepted endpoint for the `stepped`
## observers after it. Published compressions and collapse must equal gear_compressions/gear_collapsed exactly, refuse
## any other tick, state or aux bits (and an in-place write to the live state), and the statistics sample built from
## them must be byte-identical to the one built from the session's own evaluations, through real flights.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 2000
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 7215
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in ["f4u-corsair-250", "p51d-mustang-120", "jensen-das-ugly-stik-60"]:
		_direct(id)
		_flight(id, Flight.START_RUNWAY, "runway")
		_flight(id, Flight.START_RUNWAY, "landing")
		_flight(id, Flight.START_AIRBORNE, "gear_cycle")
	print("published compressions: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, start_choice: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = start_choice
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(str(Catalog.entry(id).data), id)
	s.set_field(_field)
	s.set_lake_context(_lake)
	s.reset()
	s.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.5}
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## Publish `body` with `aux` as if the observer had just measured it at the session's current tick.
func _publish(s: Node, body: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	s.sim.state = body.duplicate()
	s.sim.aux = aux.duplicate()
	s._cost_support_tick = s.sim.tick
	s._cost_support_state = body.duplicate()
	s._cost_support_aux = aux.duplicate()
	s._cost_support_previous = s.gear_compressions(body)


func _direct(id: String) -> void:
	var s := _session(id, Flight.START_RUNWAY)
	for i in 4:
		_tick(s)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var base_aux: PackedFloat64Array = s.sim.aux.duplicate()
	var index: int = s.gear_aux_index()
	var shore: PackedFloat64Array = _lake.shoreline_ne_m
	var stats := {compared = 0, mismatched = 0, collapsed = 0, refused = 0}
	var first := ""
	for i in SAMPLES:
		var aux := base_aux.duplicate()
		if index >= 0:
			aux[index] = [0.0, 1.0, _rng.randf()][_rng.randi_range(0, 2)]
			aux[index + 1] = 1.0 if _rng.randf() < 0.5 else 0.0
		var body := origin.duplicate()
		if i % 4 == 3:
			body[RB.POS] = _centroid(shore, 0) + _rng.randf_range(-40.0, 40.0)
			body[RB.POS + 1] = _centroid(shore, 1) + _rng.randf_range(-40.0, 40.0)
		else:
			body[RB.POS] += _rng.randf_range(-150.0, 150.0)
			body[RB.POS + 1] += _rng.randf_range(-150.0, 150.0)
		var ground: float = Ground.Terrain.sample(body[RB.POS], body[RB.POS + 1], s.ground_surfaces, s._lake)[0]
		# From 4 m up to 0.5 m into the ground: some contacts pass their travel.
		body[RB.POS + 2] = -ground + _rng.randf_range(-4.0, 0.5)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.5, 0.5)).normalized()
		body[RB.ATT] = q.w
		body[RB.ATT + 1] = q.x
		body[RB.ATT + 2] = q.y
		body[RB.ATT + 3] = q.z
		_publish(s, body, aux)
		var published: PackedFloat64Array = s.published_gear_compressions(body)
		var collapsed: bool = s.published_gear_collapsed(body)
		if published.is_empty():
			stats.refused += 1
			continue
		stats.compared += 1
		var reference: bool = s.gear_collapsed(body)
		if var_to_bytes(published) != var_to_bytes(s.gear_compressions(body)) or collapsed != reference:
			stats.mismatched += 1
			if first.is_empty():
				first = "%s collapsed %s/%s" % [str(published), str(collapsed), str(reference)]
		if reference:
			stats.collapsed += 1
	_check(id + " published compressions and collapse equal the reference", stats.mismatched == 0, first + str(stats))
	_check(id + " every publication answers, some collapsed", stats.refused == 0 and stats.collapsed > SAMPLES / 50
		and stats.collapsed < SAMPLES, str(stats))
	print("NK5F_DIRECT %s %s" % [id, str(stats)])
	# An invalid lake collapses the gear in Ground.collapsed before anything else.
	var body := origin.duplicate()
	_publish(s, body, base_aux)
	var lake: Dictionary = s._lake
	s._lake = {"water_level_down_m": "invalid"}
	_check(id + " an invalid lake collapses both ways", s.published_gear_collapsed(body) and s.gear_collapsed(body))
	s._lake = lake
	# Refusals: another tick, other state or aux bits, an in-place write to the live state, observations off.
	_publish(s, body, base_aux)
	_check(id + " the publication answers", not s.published_gear_compressions(body).is_empty())
	var off := body.duplicate()
	off[RB.POS + 2] = body[RB.POS + 2] + 1e-12
	_check(id + " other state bits refuse", s.published_gear_compressions(off).is_empty()
		and s.published_gear_collapsed(off) == s.gear_collapsed(off))
	# The publication stands in only where Ground.collapsed computes compressions: a planted publication that
	# claims every contact past its travel decides on the ground, and is never read above the reach shortcut.
	var standing := origin.duplicate()
	_publish(s, standing, base_aux)
	var planted := PackedFloat64Array()
	planted.resize(s._cost_support_previous.size())
	planted.fill(10.0)
	s._cost_support_previous = planted
	_check(id + " on the ground the published compressions decide", not s.gear_collapsed(standing)
		and s.published_gear_collapsed(standing))
	var high := origin.duplicate()
	high[RB.POS + 2] -= 50.0
	_publish(s, high, base_aux)
	s._cost_support_previous = planted
	_check(id + " above the reach shortcut they are not read", not s.published_gear_collapsed(high))
	var aux_off := base_aux.duplicate()
	aux_off[0] += 1.0
	s.sim.aux = aux_off
	_check(id + " other aux bits refuse", s.published_gear_compressions(body).is_empty())
	_publish(s, body, base_aux)
	s._cost_support_tick = s.sim.tick - 1
	_check(id + " another tick refuses", s.published_gear_compressions(body).is_empty())
	_publish(s, body, base_aux)
	var live: PackedFloat64Array = s.sim.state
	live[RB.POS + 2] -= 0.25 # packed arrays are shared by reference: this writes the session's live state
	_check(id + " an in-place write to the live state refuses", s.published_gear_compressions(s.sim.state).is_empty())
	_publish(s, body, base_aux)
	s._reset_contact_history()
	_check(id + " a contact-history reset withdraws the publication", s.published_gear_compressions(body).is_empty())
	_publish(s, body, base_aux)
	s._restore_contact_history({tick = s.sim.tick, events = [], active_hull_ids = PackedStringArray(), prop_strike = {}})
	_check(id + " a restored contact history publishes nothing until measured",
		s.published_gear_compressions(body).is_empty())
	_publish(s, body, base_aux)
	s.cost_observations_enabled = false
	_check(id + " no observations, no publication", s.published_gear_compressions(body).is_empty())
	s.cost_observations_enabled = true
	_publish(s, body, base_aux)
	var copy: PackedFloat64Array = s.published_gear_compressions(body)
	if not copy.is_empty():
		copy[0] = 99.0
	_check(id + " the answer is a copy", s._cost_support_previous.is_empty() or s._cost_support_previous[0] != 99.0)
	s.free()


## Fly a scripted start and compare, on every accepted tick, the published answers with the reference and the
## statistics sample built from them with the one built from the session's own evaluations.
func _flight(id: String, start: String, scenario: String) -> void:
	var s := _session(id, start)
	if scenario == "landing":
		var body: PackedFloat64Array = s.sim.state.duplicate()
		body[RB.POS + 2] -= 0.8
		body[RB.VEL] = 14.0
		body[RB.VEL + 2] = 2.5
		s.sim.reset(body)
	var throttle := 1.0 if scenario == "runway" else 0.4
	s.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.25 if s.sim.tick > 480 and scenario == "runway" else 0.0, yaw = 0.05, throttle = throttle}
	var adapter: RefCounted = Adapter.new()
	adapter.configure(s, id, func(_sample: Dictionary) -> void: pass)
	var ticks: int = {runway = 1440, gear_cycle = 2100}.get(scenario, 720)
	var stats := {ticks = 0, answered = 0, compressed = 0, mismatched = 0, samples_differ = 0}
	var first := ""
	for tick in ticks:
		if scenario == "gear_cycle" and tick in [10, 1050]:
			s.set_gear_down(tick == 1050)
		_tick(s)
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
		stats.ticks += 1
		var body: PackedFloat64Array = s.sim.state
		var published: PackedFloat64Array = s.published_gear_compressions(body)
		if published.is_empty():
			continue
		stats.answered += 1
		for value: float in published:
			if value > 0.0:
				stats.compressed += 1
				break
		if var_to_bytes(published) != var_to_bytes(s.gear_compressions(body)) \
				or s.published_gear_collapsed(body) != s.gear_collapsed(body):
			stats.mismatched += 1
			if first.is_empty():
				first = "tick %d: %s / %s" % [s.sim.tick, str(published), str(s.gear_compressions(body))]
		if var_to_bytes(adapter.sample(true)) != var_to_bytes(adapter.sample(false)):
			stats.samples_differ += 1
	_check("%s %s: published answers equal the reference on every tick" % [id, scenario], stats.mismatched == 0
		and stats.answered == stats.ticks and stats.ticks > 0, first + str(stats))
	_check("%s %s: statistics samples are byte-identical" % [id, scenario], stats.samples_differ == 0, str(stats))
	if scenario != "gear_cycle":
		_check("%s %s: the gear carried weight" % [id, scenario], stats.compressed > 0, str(stats))
	print("NK5F_FLIGHT %s %s %s" % [id, scenario, str(stats)])
	s.free()


func _centroid(points: PackedFloat64Array, offset: int) -> float:
	var sum := 0.0
	for i: int in range(offset, points.size(), 2):
		sum += points[i]
	return sum / float(points.size() / 2)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
