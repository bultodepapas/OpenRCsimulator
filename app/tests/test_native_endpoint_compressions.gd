extends SceneTree
## NK-5e: the native endpoint compressions must equal the session's gear_compressions bit for bit. Random endpoints
## over the runway, grass and lake, with random retractable gear poses, compare the native stage against the
## reference; mismatched gear bits and invalid states must refuse. Paired sessions with and without the native
## answer must then fly identically (state, aux, support history and contact events) through a runway roll, a gear
## cycle, a hard landing and a lake ditching, and the observer must take the native answer on every accepted tick.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 3000
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _world: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 6152
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	var built: Dictionary = CollisionSetup.build(_field)
	_check("collision world builds", built.get("ok", false))
	_world = built.world
	for id: String in ["f4u-corsair-250", "p51d-mustang-120", "jensen-das-ugly-stik-60"]:
		var probe := _session(id, true, Flight.START_AIRBORNE)
		if probe.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE:
			print("NK5E_ENDPOINT_COMPRESSIONS_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
			probe.free()
			continue
		_direct(probe, id)
		_refusals(probe, id)
		probe.free()
		_equivalence(id, "runway")
		_equivalence(id, "gear_cycle")
		_equivalence(id, "landing")
		_equivalence(id, "lake")
	print("native endpoint compressions: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _session(id: String, enabled: bool, start_choice: String) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.native_endpoint_compressions_enabled = enabled
	s.start_choice = start_choice
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(str(Catalog.entry(id).data), id)
	s.set_field(_field)
	s.set_collision_world(_world)
	s.set_lake_context(_lake)
	s.reset()
	return s


## The reference gear_compressions with an explicit aux (current_landing_gear(aux) instead of sim.aux).
func _reference(s: Node, body: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	return Ground.compressions(body, s.current_landing_gear(aux),
		s.ground_surfaces if s.wheel_count() > 0 else PackedFloat64Array(), s._lake, s._rc_track)


## Install a tick context for `aux` as the guarded pre-step would.
func _context(s: Node, aux: PackedFloat64Array) -> bool:
	return s._native_stage.tick_context(s, aux, s.sim.inputs)


func _random_aux(s: Node) -> PackedFloat64Array:
	var aux: PackedFloat64Array = s.sim.aux.duplicate()
	var index: int = s.gear_aux_index()
	if index >= 0:
		var pick := _rng.randi_range(0, 3)
		aux[index] = [0.0, 1.0, _rng.randf(), 0.5][pick]
		aux[index + 1] = 1.0 if _rng.randf() < 0.5 else 0.0
	return aux


func _direct(s: Node, id: String) -> void:
	var shore: PackedFloat64Array = _lake.shoreline_ne_m
	var lake_n := _centroid(shore, 0)
	var lake_e := _centroid(shore, 1)
	var origin: PackedFloat64Array = s.sim.state.duplicate()
	var stats := {answered = 0, refused = 0, mismatched = 0, compressed = 0, wet = 0}
	var first := ""
	for i: int in SAMPLES:
		var aux := _random_aux(s)
		if not _context(s, aux):
			stats.refused += 1
			continue
		var position := PackedFloat64Array([0.0, 0.0, 0.0])
		match i % 3:
			0:
				# Around the start over the runway and grass, from 3 m up to 0.6 m into the ground.
				position[0] = origin[RB.POS] + _rng.randf_range(-150.0, 150.0)
				position[1] = origin[RB.POS + 1] + _rng.randf_range(-150.0, 150.0)
			1:
				position[0] = lake_n + _rng.randf_range(-40.0, 40.0)
				position[1] = lake_e + _rng.randf_range(-40.0, 40.0)
			2:
				position[0] = _rng.randf_range(-400.0, 400.0)
				position[1] = _rng.randf_range(-400.0, 400.0)
		var ground: float = Ground.Terrain.sample(position[0], position[1], s.ground_surfaces, s._lake)[0]
		position[2] = -ground + _rng.randf_range(-3.0, 0.6)
		var body := _state(position, 0.35 if i % 5 else PI)
		var native: PackedFloat64Array = s._native_stage.endpoint_compressions(body, aux)
		var reference := _reference(s, body, aux)
		if native.is_empty():
			stats.refused += 1
			continue
		stats.answered += 1
		if var_to_bytes(native) != var_to_bytes(reference):
			stats.mismatched += 1
			if first.is_empty():
				first = "%s / %s" % [str(native), str(reference)]
		for value: float in native:
			if value > 0.0:
				stats.compressed += 1
				break
		if i % 3 == 1:
			stats.wet += 1
	_check(id + " native endpoint compressions match the reference bit for bit", stats.mismatched == 0, first + " " + str(stats))
	_check(id + " every valid endpoint is answered natively, with compressed and lake samples", stats.refused == 0
		and stats.compressed > SAMPLES / 20 and stats.wet > SAMPLES / 4, str(stats))
	print("NK5E_DIRECT %s %s" % [id, str(stats)])


func _refusals(s: Node, id: String) -> void:
	var aux: PackedFloat64Array = s.sim.aux.duplicate()
	var body: PackedFloat64Array = s.sim.state.duplicate()
	_check(id + " context installs", _context(s, aux))
	_check(id + " the installed context answers", not s._native_stage.endpoint_compressions(body, aux).is_empty())
	var nan_state := body.duplicate()
	nan_state[RB.VEL + 1] = NAN
	_check(id + " a nonfinite state refuses", s._native_stage.endpoint_compressions(nan_state, aux).is_empty())
	var flat := body.duplicate()
	for axis: int in 4:
		flat[RB.ATT + axis] = 0.0
	_check(id + " a zero attitude refuses", s._native_stage.endpoint_compressions(flat, aux).is_empty())
	_check(id + " a short state refuses", s._native_stage.endpoint_compressions(body.slice(0, 12), aux).is_empty())
	var index: int = s.gear_aux_index()
	if index >= 0:
		var near := aux.duplicate()
		near[index] = 0.5
		_check(id + " a half pose installs", _context(s, near))
		var off := near.duplicate()
		off[index] = 0.5000000000000001
		_check(id + " gear extension one ulp off refuses", s._native_stage.endpoint_compressions(body, off).is_empty())
		off = near.duplicate()
		off[index + 1] = 1.0 - near[index + 1]
		_check(id + " a different gear flag refuses", s._native_stage.endpoint_compressions(body, off).is_empty())
		_check(id + " a short aux refuses", s._native_stage.endpoint_compressions(body, near.slice(0, index + 1)).is_empty())
		var zero := aux.duplicate()
		zero[index] = 0.0
		_check(id + " a retracted pose installs", _context(s, zero))
		var negative := zero.duplicate()
		var unsigned := 0.0
		negative[index] = -unsigned # a literal -0.0 folds to +0.0
		_check(id + " the probe really carries -0.0", negative.to_byte_array() != zero.to_byte_array())
		_check(id + " a negative zero extension refuses", s._native_stage.endpoint_compressions(body, negative).is_empty())
	# Without a surface table, lake or track the reference takes its flat-ground formula: the native stage refuses.
	# (This re-prepares the probe's kernel, so it runs last before the token checks; the probe is then discarded.)
	var config: Dictionary = s._native_stage._config.duplicate()
	config.surfaces = PackedFloat64Array()
	config.lake = {}
	config.lake_valid = true
	var kernel: Object = s._native_stage._native
	var prepared: Dictionary = kernel.prepare_stage(config)
	_check(id + " a stage without a surface table prepares", prepared.get("ok", false), str(prepared.get("error", "")))
	var d: Dictionary = s._deflections(aux)
	_check(id + " its tick context installs", kernel.set_tick_context(aux, s.sim.inputs,
		PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)]), s.sim.time()))
	_check(id + " an empty surface table refuses", kernel.stage_compressions(body, aux).is_empty())
	var restored: Dictionary = kernel.prepare_stage(s._native_stage._config)
	_check(id + " the session's own stage prepares again", restored.get("ok", false))
	# The token: a guarded pre-step admits exactly the next endpoint; every fact drop withdraws it.
	s._native_endpoint_tick = -1
	var next: PackedFloat64Array = s._kernel_pre_step(s.sim.aux, s.sim.inputs, s.sim.dt())
	_check(id + " a guarded pre-step admits the next endpoint", not next.is_empty() and s._native_endpoint_tick == s.sim.tick + 1)
	s._drop_tick_facts()
	_check(id + " a fact drop withdraws the admission", s._native_endpoint_tick == -1)


## Fly the same scripted start with and without the native answer and require identical ticks and observations.
func _equivalence(id: String, scenario: String) -> void:
	var start: String = Flight.START_AIRBORNE if scenario in ["gear_cycle", "lake"] else Flight.START_RUNWAY
	var sessions: Array[Node] = [_session(id, true, start), _session(id, false, start)]
	var ticks: int = {runway = 1440, gear_cycle = 2100}.get(scenario, 720)
	for s: Node in sessions:
		var body: PackedFloat64Array = s.sim.state.duplicate()
		match scenario:
			"landing":
				# The runway start lifted 0.8 m, sinking at 2.5 m/s and rolling forward at 14 m/s.
				body[RB.POS + 2] -= 0.8
				body[RB.VEL] = 14.0
				body[RB.VEL + 2] = 2.5
				s.sim.reset(body)
			"lake":
				var shore: PackedFloat64Array = _lake.shoreline_ne_m
				body[RB.POS] = _centroid(shore, 0)
				body[RB.POS + 1] = _centroid(shore, 1)
				body[RB.POS + 2] = float(_lake.water_level_down_m) - 1.2
				_level(body, 15.0, 2.0)
				s.sim.reset(body)
		var pitch := 0.0
		if scenario == "runway":
			pitch = 0.25
		s.read_raw = func() -> Dictionary:
			return {roll = 0.0, pitch = pitch if s.sim.tick > 480 else 0.0, yaw = 0.05, throttle = 1.0 if scenario == "runway" else 0.4}
	var identical := true
	var detail := ""
	var stepped := 0
	var supported := 0
	var events := 0
	var lowest := 1.0
	var direct := 0
	var direct_first := ""
	for tick: int in ticks:
		if scenario == "gear_cycle" and tick in [10, 1050]:
			for s: Node in sessions:
				s.set_gear_down(tick == 1050)
		for s: Node in sessions:
			var dt: float = s.sim.dt()
			s._physics_process(dt)
			s.sim._physics_process(dt)
		var a: Node = sessions[0]
		var b: Node = sessions[1]
		if var_to_bytes([a.sim.tick, a.sim.state, a.sim.continuous, a.sim.aux, a.sim.fault_reason, a.crash.keys(),
				a._contact_events, a._cost_support_previous, a._cost_support_tick, a.sim.last_events]) \
				!= var_to_bytes([b.sim.tick, b.sim.state, b.sim.continuous, b.sim.aux, b.sim.fault_reason, b.crash.keys(),
				b._contact_events, b._cost_support_previous, b._cost_support_tick, b.sim.last_events]):
			identical = false
			detail = "tick %d: %s / %s" % [tick, str(a._cost_support_previous), str(b._cost_support_previous)]
			break
		stepped = a.sim.tick
		# The endpoint context still belongs to this tick: the native stage must answer it exactly.
		var answer: PackedFloat64Array = a._native_stage.endpoint_compressions(a.sim.state, a.sim.aux)
		if answer.is_empty() or var_to_bytes(answer) != var_to_bytes(a.gear_compressions(a.sim.state)):
			direct += 1
			if direct_first.is_empty():
				direct_first = "tick %d: %s / %s" % [a.sim.tick, str(answer), str(a.gear_compressions(a.sim.state))]
		for value: float in a._cost_support_previous:
			if value > 0.0:
				supported += 1
				break
		events += a._contact_events.size()
		if a.gear_aux_index() >= 0:
			lowest = minf(lowest, a.sim.aux[a.gear_aux_index()])
		if not a.crash.is_empty() or not a.sim.fault_reason.is_empty():
			break
	var native: Node = sessions[0]
	var reference: Node = sessions[1]
	var outcome: String = "crash" if not native.crash.is_empty() else ("fault" if not native.sim.fault_reason.is_empty() else "flying")
	_check("%s %s observes identically with and without the native answer (%d ticks, %s)" % [id, scenario, stepped, outcome],
		identical, detail)
	_check("%s %s: the observer took the native answer on every accepted tick" % [id, scenario],
		native.native_endpoint_answers == stepped and stepped > 0,
		"answers %d stepped %d" % [native.native_endpoint_answers, stepped])
	_check("%s %s: the reference session never took it" % [id, scenario], reference.native_endpoint_answers == 0)
	_check("%s %s: every endpoint answer equals gear_compressions" % [id, scenario], direct == 0, direct_first)
	if scenario == "gear_cycle" and native.gear_aux_index() >= 0:
		_check("%s gear cycle retracts and extends the gear" % id, lowest < 0.05
			and native.sim.aux[native.gear_aux_index()] > lowest, "lowest %f" % lowest)
	if scenario in ["runway", "landing"]:
		_check("%s %s supports weight on the gear" % [id, scenario], supported > 0 and events > 0,
			"supported %d events %d" % [supported, events])
	print("NK5E_EQUIVALENCE %s %s ticks=%d outcome=%s supported=%d events=%d answers=%d" % [id, scenario, stepped, outcome,
		supported, events, native.native_endpoint_answers])
	for s: Node in sessions:
		s.free()


func _state(position: PackedFloat64Array, max_tilt: float) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(RB.SIZE)
	for axis: int in 3:
		s[RB.POS + axis] = position[axis]
		s[RB.VEL + axis] = _rng.randf_range(-20.0, 20.0)
		s[RB.RATE + axis] = _rng.randf_range(-2.0, 2.0)
	var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
		_rng.randf_range(-max_tilt, max_tilt)).normalized()
	s[RB.ATT] = q.w
	s[RB.ATT + 1] = q.x
	s[RB.ATT + 2] = q.y
	s[RB.ATT + 3] = q.z
	return s


## Level attitude heading north, body velocity (forward, 0, sink), no rotation.
func _level(body: PackedFloat64Array, forward: float, sink: float) -> void:
	body[RB.ATT] = 1.0
	body[RB.ATT + 1] = 0.0
	body[RB.ATT + 2] = 0.0
	body[RB.ATT + 3] = 0.0
	body[RB.VEL] = forward
	body[RB.VEL + 1] = 0.0
	body[RB.VEL + 2] = sink
	for axis: int in 3:
		body[RB.RATE + axis] = 0.0


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
