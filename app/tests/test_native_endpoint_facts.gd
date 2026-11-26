extends SceneTree
## NK-5i: the native stage answers the statistics sample's evaluations of the accepted endpoint in one call:
## [air V, terrain height, slope north, slope east, collapsed, compressions...]. They must equal air_data(s, t).V,
## environment.ground(s[0], s[1]), gear_collapsed(s) and gear_compressions(s) bit for bit:
## - random endpoints (over the field and the lake, from 80 m up to 0.5 m into the ground, random attitudes and
##   velocities) in calm, gusty, turbulent and spatial weather for the whole fixed-wing fleet, and with retractable gear
##   in transit (posed contacts have no admitted travel);
## - every accepted tick of takeoffs, landings, gear cycles and weather flights, where the statistics sample built from
##   the answer is byte-identical to the one the reference evaluations build, with and without NK-5f's publication;
## - refusals: another tick, other state or aux bits, an RC track, a pending weather reset, no observations, the test
##   hook off, a contact-history reset. Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Weather := preload("res://physics/wind_config.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 500
const WEATHERS := ["calm", "gusty", "turbulent", "spatial"]
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _fleet: PackedStringArray = []
var _start_for := {}
var _geared := {} # wheels to publish: a gearless airframe keeps the reference sample


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 51519
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var start: String = Flight.START_RUNWAY
		var probe := _session(id, start, "calm")
		if probe == null:
			start = Flight.START_AIRBORNE
			probe = _session(id, start, "calm")
		if probe == null:
			print("NK5I_SKIP %s: no flyable fixed-wing session" % id)
			continue
		if probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE and probe._native_stage._facts_bound:
			_fleet.append(id)
			_start_for[id] = start
			_geared[id] = probe.wheel_count() > 0
		else:
			print("NK5I_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		probe.free()
	if _fleet.is_empty():
		print("NK5I_ENDPOINT_FACTS_SKIP no native fixed-wing session")
		print("native endpoint facts: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	for weather: String in WEATHERS:
		for id: String in _fleet:
			_direct(id, weather)
	for id: String in _fleet:
		_transit(id)
		if _start_for[id] == Flight.START_RUNWAY:
			_flight(id, "calm", "takeoff")
			_flight(id, "calm", "landing")
		_flight(id, "calm", "gear_cycle")
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "sebart-avanti-s-a200-p100rx"]:
		if id in _fleet and _start_for[id] == Flight.START_RUNWAY:
			for weather: String in ["gusty", "turbulent", "spatial"]:
				_flight(id, weather, "takeoff")
	_refusals()
	print("native endpoint facts: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _weather_config(weather: String) -> Variant:
	match weather:
		"gusty": return Weather.preset("gusty")
		"turbulent": return Weather.preset("turbulent")
		"spatial": return Weather.spatial_defaults()
	return null


func _session(id: String, start: String, weather: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.start_choice = start
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(str(Catalog.entry(id).data), id)
	if not s.aircraft.get("ok", false) or s.get_script() != Flight:
		s.free()
		return null
	s.set_field(_field)
	s.set_lake_context(_lake)
	var config: Variant = _weather_config(weather)
	if config != null and not s.setup_weather(config):
		print("NK5I weather %s refused for %s: %s" % [weather, id, s.weather_error])
		s.free()
		return null
	s.reset()
	if not s.is_flyable():
		s.free()
		return null
	s.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.4}
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## The reference evaluations in the answer's layout.
func _reference(s: Node, body: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([float(s.air_data(body, s.sim.time()).get("V", NAN))])
	out.append_array(s.environment.ground(body[0], body[1]))
	out.append(1.0 if s.gear_collapsed(body) else 0.0)
	out.append_array(s.gear_compressions(body))
	return out


## Publish `body` with `aux` as if the native observer had just measured it at the session's current tick.
func _publish(s: Node, body: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	s.sim.state = body.duplicate()
	s.sim.aux = aux.duplicate()
	s._cost_support_tick = s.sim.tick
	s._cost_support_state = body.duplicate()
	s._cost_support_aux = aux.duplicate()
	s._cost_support_previous = s.gear_compressions(body)
	s._native_facts_tick = s.sim.tick


func _random_body(s: Node, origin: PackedFloat64Array, i: int) -> PackedFloat64Array:
	var body := origin.duplicate()
	if i % 4 == 3:
		var shore: PackedFloat64Array = _lake.shoreline_ne_m
		body[RB.POS] = _centroid(shore, 0) + _rng.randf_range(-40.0, 40.0)
		body[RB.POS + 1] = _centroid(shore, 1) + _rng.randf_range(-40.0, 40.0)
	else:
		body[RB.POS] += _rng.randf_range(-200.0, 200.0)
		body[RB.POS + 1] += _rng.randf_range(-200.0, 200.0)
	var ground: float = Ground.Terrain.sample(body[RB.POS], body[RB.POS + 1], s.ground_surfaces, s._lake)[0]
	body[RB.POS + 2] = -ground + (_rng.randf_range(-80.0, -4.0) if i % 3 == 0 else _rng.randf_range(-4.0, 0.5))
	var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-0.6, 0.6)).normalized()
	body[RB.ATT] = q.w
	body[RB.ATT + 1] = q.x
	body[RB.ATT + 2] = q.y
	body[RB.ATT + 3] = q.z
	for k in 3:
		body[RB.VEL + k] += _rng.randf_range(-6.0, 6.0)
	return body


## Random endpoints at the session's last accepted tick context: every answer equals the reference.
func _direct(id: String, weather: String) -> void:
	var s := _session(id, _start_for[id], weather)
	if s == null:
		return
	for i in 6:
		_tick(s)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var aux: PackedFloat64Array = s.sim.aux.duplicate()
	if not _geared[id]:
		# No wheels: the stage has no contact table to sample, so the session keeps the reference evaluations.
		_publish(s, origin, aux)
		_check("%s %s: a gearless airframe keeps the reference" % [id, weather], s.published_endpoint_facts(origin).is_empty())
		s.free()
		return
	_sample_bodies(s, origin, aux, "%s %s" % [id, weather])
	s.free()


## Retractable gear stopped in transit: posed contacts carry no admitted travel, so any compression collapses them.
func _transit(id: String) -> void:
	var s := _session(id, Flight.START_AIRBORNE, "calm")
	if s == null or not s.gear_is_retractable():
		if s != null: s.free()
		return
	var index: int = s.gear_aux_index()
	s.set_gear_down(s.sim.aux[index] < 0.5) # the other way from the start pose
	for i in 2400:
		_tick(s)
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
		if s.sim.aux[index] > 0.2 and s.sim.aux[index] < 0.8:
			break
	var fraction: float = s.sim.aux[index]
	if fraction <= 0.0 or fraction >= 1.0:
		print("NK5I_TRANSIT_SKIP %s: extension %f" % [id, fraction])
		s.free()
		return
	var stats := _sample_bodies(s, s.sim.state.duplicate(), s.sim.aux.duplicate(), "%s in transit %.2f" % [id, fraction])
	_check(id + " gear in transit collapses on any compression", stats.collapsed > 0, str(stats))
	s.free()


func _sample_bodies(s: Node, origin: PackedFloat64Array, aux: PackedFloat64Array, label: String) -> Dictionary:
	var stats := {compared = 0, mismatched = 0, collapsed = 0, refused = 0, wrong_refusal = 0}
	var first := ""
	for i in SAMPLES:
		var body := _random_body(s, origin, i)
		_publish(s, body, aux)
		var facts: PackedFloat64Array = s.published_endpoint_facts(body)
		var reference := _reference(s, body)
		if facts.is_empty():
			stats.refused += 1
			# Only a refused spatial air sample (the reference's nonfinite V) may refuse here.
			if is_finite(reference[0]):
				stats.wrong_refusal += 1
			continue
		stats.compared += 1
		if facts[4] != 0.0:
			stats.collapsed += 1
		if var_to_bytes(facts) != var_to_bytes(reference) or (facts[4] != 0.0) != s.published_gear_collapsed(body):
			stats.mismatched += 1
			if first.is_empty():
				first = "%s / %s " % [str(facts), str(reference)]
	_check(label + ": every answer equals the reference bit for bit", stats.mismatched == 0, first + str(stats))
	_check(label + ": answers unless the reference air is invalid", stats.wrong_refusal == 0
		and stats.compared > SAMPLES / 2, str(stats))
	print("NK5I_DIRECT %s %s" % [label, str(stats)])
	return stats


## Fly a scripted start; on every accepted tick compare the answer with the reference and the statistics samples built
## from the answer, from NK-5f's publication and from the session's own evaluations.
func _flight(id: String, weather: String, scenario: String) -> void:
	var start: String = Flight.START_AIRBORNE if scenario == "gear_cycle" else _start_for[id]
	var s := _session(id, start, weather)
	if s == null:
		return
	if scenario == "gear_cycle" and not s.gear_is_retractable():
		s.free()
		return
	if scenario == "landing":
		var body: PackedFloat64Array = s.sim.state.duplicate()
		body[RB.POS + 2] -= 0.8
		body[RB.VEL] = 14.0
		body[RB.VEL + 2] = 2.5
		s.sim.reset(body)
	var throttle := 1.0 if scenario == "takeoff" else 0.4
	s.read_raw = func() -> Dictionary:
		return {roll = 0.0, pitch = 0.25 if s.sim.tick > 480 and scenario == "takeoff" else 0.0, yaw = 0.05, throttle = throttle}
	var adapter: RefCounted = Adapter.new()
	adapter.configure(s, id, func(_sample: Dictionary) -> void: pass)
	var ticks: int = {takeoff = 1440, gear_cycle = 2100}.get(scenario, 720)
	var stats := {ticks = 0, native = 0, answered = 0, compressed = 0, collapsed = 0, mismatched = 0, samples_differ = 0}
	var first := ""
	for tick in ticks:
		if scenario == "gear_cycle" and tick in [10, 1050]:
			s.set_gear_down(tick == 1050)
		_tick(s)
		if not s.crash.is_empty() or not s.sim.fault_reason.is_empty():
			break
		stats.ticks += 1
		if s._native_facts_tick == s.sim.tick:
			stats.native += 1 # the native stage measured this publication's endpoint
		var body: PackedFloat64Array = s.sim.state
		var facts: PackedFloat64Array = s.published_endpoint_facts(body)
		if not facts.is_empty():
			stats.answered += 1
			if facts[4] != 0.0:
				stats.collapsed += 1
			for k in range(5, facts.size()):
				if facts[k] > 0.0:
					stats.compressed += 1
					break
			if var_to_bytes(facts) != var_to_bytes(_reference(s, body)):
				stats.mismatched += 1
				if first.is_empty():
					first = "tick %d: %s / %s " % [s.sim.tick, str(facts), str(_reference(s, body))]
		var native_sample: Dictionary = adapter.sample(true)
		s.native_endpoint_facts_enabled = false
		var published_sample: Dictionary = adapter.sample(true)
		s.native_endpoint_facts_enabled = true
		var reference_sample: Dictionary = adapter.sample(false)
		if var_to_bytes(native_sample) != var_to_bytes(reference_sample) \
				or var_to_bytes(published_sample) != var_to_bytes(reference_sample):
			stats.samples_differ += 1
	var label := "%s %s %s" % [id, weather, scenario]
	_check(label + ": answers equal the reference on every tick", stats.mismatched == 0, first + str(stats))
	# Every natively measured publication answers; the spatial field may refuse a station (the reference air is then
	# invalid and the sample evaluates it). A gearless airframe never answers.
	if _geared[id]:
		_check(label + ": the native stage answers its publications", stats.ticks > 0 and stats.native > stats.ticks * 0.95
			and (stats.answered == stats.native or (weather == "spatial" and stats.answered > stats.native / 2)), str(stats))
	else:
		_check(label + ": a gearless airframe keeps the reference", stats.answered == 0, str(stats))
	_check(label + ": statistics samples are byte-identical", stats.samples_differ == 0, str(stats))
	if scenario == "takeoff" and _geared[id]:
		_check(label + ": the gear carried weight", stats.compressed > 0, str(stats))
	print("NK5I_FLIGHT %s %s" % [label, str(stats)])
	s.free()


func _refusals() -> void:
	var id: String = "f4u-corsair-250" if "f4u-corsair-250" in _fleet else _fleet[0]
	var s := _session(id, _start_for[id], "calm")
	for i in 6:
		_tick(s)
	var body: PackedFloat64Array = s.sim.state.duplicate()
	var aux: PackedFloat64Array = s.sim.aux.duplicate()
	_publish(s, body, aux)
	var before: int = s.native_endpoint_fact_answers
	_check(id + " the publication answers and counts", not s.published_endpoint_facts(body).is_empty()
		and s.native_endpoint_fact_answers == before + 1)
	var off := body.duplicate()
	off[RB.POS + 2] = body[RB.POS + 2] + 1e-12
	_check(id + " other state bits refuse", s.published_endpoint_facts(off).is_empty())
	var aux_off := aux.duplicate()
	aux_off[0] += 1.0
	s.sim.aux = aux_off
	_check(id + " other aux bits refuse", s.published_endpoint_facts(body).is_empty())
	_publish(s, body, aux)
	s._native_facts_tick = s.sim.tick - 1
	_check(id + " another tick's publication refuses", s.published_endpoint_facts(body).is_empty())
	_publish(s, body, aux)
	s.native_endpoint_facts_enabled = false
	_check(id + " the test hook refuses", s.published_endpoint_facts(body).is_empty())
	s.native_endpoint_facts_enabled = true
	s.cost_observations_enabled = false
	_check(id + " no observations, no answer", s.published_endpoint_facts(body).is_empty())
	s.cost_observations_enabled = true
	s._weather_pending_reset = true
	_check(id + " a pending weather reset refuses", s.published_endpoint_facts(body).is_empty())
	s._weather_pending_reset = false
	var track: Dictionary = s._rc_track
	s._rc_track = {"id": "fixture"}
	_check(id + " an RC track refuses", s.published_endpoint_facts(body).is_empty())
	s._rc_track = track
	_publish(s, body, aux)
	s._reset_contact_history()
	_check(id + " a contact-history reset withdraws the answer", s.published_endpoint_facts(body).is_empty())
	# The real publication: set by the session's own handler only for natively measured endpoints.
	_tick(s)
	_check(id + " the session marks its natively measured publication", s._native_facts_tick == s.sim.tick
		and not s.published_endpoint_facts(s.sim.state).is_empty())
	s.native_pre_step_enabled = false
	_tick(s)
	print("NK5I_REFUSALS after a reference pre-step: facts tick %d at tick %d" % [s._native_facts_tick, s.sim.tick])
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
