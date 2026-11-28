extends SceneTree
## NK-6v: a contact step the native stage proves clear (FlightSession._clear_contact_step) leaves exactly what the
## reference step leaves. On the production field, lake and scenery collision world with soft hull contacts, for two
## liquid, two glow and one electric aircraft (the electric one takes the sampler-free post_tick):
## - 3,000 random tick pairs (airborne, low over the field, over the lake bank, rolling, tilted into the ground, with
##   valid and broken stores, and accepted scenery and lake events carried in or not) give the same returned state
##   and the same contact bookkeeping with the proof on and off; also without the lake, and without lake and world;
## - a takeoff roll, a hard landing and a nose-over fly byte-identical with the proof on and off, with the same
##   contact events and the same count of quiet hull terminals.
## Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")
const SceneryCollision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 3000
const TICKS := 1500
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _world: Dictionary


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
	else:
		print("ok ", label)


func _run() -> void:
	if not NativeStage.library_status().get("ok", false) \
			or not ClassDB.class_has_method(&"OpenRCNativeKernel", &"stage_contact_clear"):
		print("NK6V_SKIP no native library with the clear contact proof")
		quit(0)
		return
	_rng.seed = 6226
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	_world = CollisionSetup.build(_field).get("world", {})
	for id: String in ["f4u-corsair-250", "p51d-mustang-120", "stik-glow-61fx-2t", "stik-glow-fs64v-4t", "stik-electric-6s"]:
		var a := _session(id, true)
		var b := _session(id, false)
		var ready: bool = a != null and b != null and a.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE \
			and a._native_stage._clear_contact_bound and not a._collision_world.is_empty()
		_check("%s: a native session on the field, lake and scenery world" % id, ready)
		if ready:
			_oracle(a, b, id, true)
		for s: Node in [a, b]:
			if s != null:
				s.free()
		if not ready:
			continue
		for scenario: String in ["roll", "hard_landing", "nose_over"]:
			_pair(id, scenario)
		if id in ["f4u-corsair-250", "stik-glow-61fx-2t", "stik-electric-6s"]:
			for config: Array in [[false, true, "without the lake"], [false, false, "without lake and world"]]:
				var c := _session(id, true, config[0], config[1])
				var d := _session(id, false, config[0], config[1])
				_oracle(c, d, "%s %s" % [id, config[2]], false)
				c.free()
				d.free()
	print("native clear contact: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 or _checks == 0 else 0)


func _session(id: String, enabled: bool, lake := true, world := true) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.native_clear_contact_enabled = enabled
	s.start_choice = Flight.START_RUNWAY
	s.setup_stage_backend(NativeStage.BACKEND_NATIVE)
	s.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
	if not s.aircraft.get("ok", false):
		s.free()
		return null
	s.set_field(_field)
	if lake:
		s.set_lake_context(_lake)
	if world:
		s.set_collision_world(_world)
	s.reset()
	if s.glow_is_active() and not bool(s.glow_state().get("running", false)):
		s.glow_start()
	return s


func _tick(s: Node) -> void:
	var dt: float = s.sim.dt()
	s._physics_process(dt)
	s.sim._physics_process(dt)


## The contact step's observable result and bookkeeping.
func _outcome(s: Node, returned: PackedFloat64Array) -> PackedByteArray:
	var events := []
	for event: Variant in [s._pending_scenery_event, s._pending_lake_event, s._last_scenery_event, s._last_lake_event,
			s._pending_crash]:
		events.append(null if event == null else [event.get_class(), event.get("time_fraction"), event.get("point_index"),
			event.get("response_status"), event.get("trigger")])
	return var_to_bytes([returned, s._pending_contact_tick, s._pending_crash_state, s._pending_scenery_damage,
		s._pending_scenery_tick, s._resolving_contact, s._terminal_before_values, s.native_terminal_quiet_answers,
		s.crash, events])


func _oracle(a: Node, b: Node, id: String, require_fallbacks: bool) -> void:
	for i in 20:
		_tick(a)
		_tick(b)
	var sampled: bool = a.sim.model.post_tick_joint.is_valid()
	var index: int = a._liquid_index() if a.liquid_fuel_is_active() else 1
	var bank := LakeCollision._polygon_bounds(_lake.bank_ne_m)
	var origin: PackedFloat64Array = a.sim.state.duplicate()
	var values: PackedFloat64Array = a.sim.continuous.duplicate()
	var mismatched := 0
	var first := ""
	var before: int = a.native_clear_contact_answers
	for i in SAMPLES:
		var previous := origin.duplicate()
		var kind := i % 6
		if kind == 0: # over the lake bank, low
			previous[RB.POS] = lerpf(bank[0], bank[1], _rng.randf())
			previous[RB.POS + 1] = lerpf(bank[2], bank[3], _rng.randf())
			previous[RB.POS + 2] = -_rng.randf_range(-0.5, 4.0)
		elif kind == 1: # anywhere on the field, low enough for trees and buildings
			previous[RB.POS] += _rng.randf_range(-250.0, 250.0)
			previous[RB.POS + 1] += _rng.randf_range(-250.0, 250.0)
			previous[RB.POS + 2] = -_rng.randf_range(0.0, 25.0)
		elif kind == 2: # airborne
			previous[RB.POS] += _rng.randf_range(-200.0, 200.0)
			previous[RB.POS + 1] += _rng.randf_range(-200.0, 200.0)
			previous[RB.POS + 2] = -_rng.randf_range(25.0, 150.0)
		else: # rolling or touching near the start
			previous[RB.POS] += _rng.randf_range(-30.0, 30.0)
			previous[RB.POS + 2] += _rng.randf_range(-0.3, 0.3) if kind == 3 else _rng.randf_range(-0.02, 0.02)
		var q := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.8, 0.8) if kind == 3 else _rng.randf_range(-0.05, 0.05)).normalized() \
			* Quaternion(previous[RB.ATT + 1], previous[RB.ATT + 2], previous[RB.ATT + 3], previous[RB.ATT])
		var c := [float(q.w), float(q.x), float(q.y), float(q.z)]
		var n: float = sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2] + c[3] * c[3])
		for k in 4:
			previous[RB.ATT + k] = c[k] / n
		for k in 3:
			previous[RB.VEL + k] = _rng.randf_range(-30.0, 30.0) if kind != 4 else 0.0
		var candidate := previous.duplicate()
		for k in 3:
			candidate[RB.POS + k] += previous[RB.VEL + k] / 240.0
		candidate[RB.POS + 2] += _rng.randf_range(-0.05, 0.08)
		var before_values := values.duplicate()
		var after_values := values.duplicate()
		if sampled and i % 13 == 0:
			after_values[index] = [-1.0, NAN, 1.0e6][i % 3]
		elif sampled:
			after_values[index] = maxf(0.0, before_values[index] - _rng.randf_range(0.0, 0.001))
		var outcomes: Array[PackedByteArray] = []
		var carried: bool = i % 5 == 1 # accepted events of an earlier tick, carried into this step
		for s: Node in [a, b]:
			var scenery_event: SceneryCollision.Event = null
			var lake_event: LakeCollision.WaterEvent = null
			if carried:
				scenery_event = SceneryCollision.Event.new()
				scenery_event.time_fraction = float(i) / SAMPLES
				lake_event = LakeCollision.WaterEvent.new()
				lake_event.time_fraction = 0.5 + float(i) / SAMPLES
			s._last_scenery_event = scenery_event
			s._last_lake_event = lake_event
			s._native_endpoint_tick = s.sim.tick + 1 # as the guarded pre-step leaves it
			var returned: PackedFloat64Array = s._resolve_mass_contact_step(previous, candidate, s.sim.tick + 1,
				before_values, after_values) if sampled else s._resolve_collision_step(previous, candidate, s.sim.tick + 1)
			s._native_endpoint_tick = -1
			outcomes.append(_outcome(s, returned))
		if outcomes[0] != outcomes[1]:
			mismatched += 1
			if first.is_empty():
				first = "sample %d (kind %d)" % [i, kind]
	var answered: int = a.native_clear_contact_answers - before
	_check("%s: %d random contact steps leave the reference's result and bookkeeping (%d proved clear)" % [id, SAMPLES,
		answered], mismatched == 0 and answered > SAMPLES / 10 		and (not require_fallbacks or answered < SAMPLES - SAMPLES / 10), first)


func _pair(id: String, scenario: String) -> void:
	var a := _session(id, true)
	var b := _session(id, false)
	var raw := func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 1.0}
	if scenario == "hard_landing":
		for s: Node in [a, b]:
			var state: PackedFloat64Array = s.sim.state.duplicate()
			state[RB.POS + 2] -= 1.2
			state[RB.VEL + 2] = 7.0
			s.sim.state = state
			s.sim.previous = state.duplicate()
		raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	elif scenario == "nose_over":
		raw = func() -> Dictionary: return {roll = 0.0, pitch = -1.0, yaw = 0.0, throttle = 1.0}
	elif scenario == "roll":
		raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.25, yaw = 0.0, throttle = 1.0}
	a.read_raw = raw
	b.read_raw = raw
	var same := true
	var first := ""
	for i in TICKS:
		_tick(a)
		_tick(b)
		if var_to_bytes(a.checkpoint()) != var_to_bytes(b.checkpoint()) \
				or var_to_bytes(a.contact_events()) != var_to_bytes(b.contact_events()):
			same = false
			first = "tick %d" % a.sim.tick
			break
		if not a.crash.is_empty():
			break
	_check("%s %s: byte-identical with the clear proof on and off (%d ticks, %d proved clear, %d quiet terminals, alt %.1f m)" % [
		id, scenario, a.sim.tick, a.native_clear_contact_answers, a.native_terminal_quiet_answers, -a.sim.state[2]],
		same and a.native_terminal_quiet_answers == b.native_terminal_quiet_answers \
		and (scenario != "roll" or a.native_clear_contact_answers > TICKS / 2), first)
	a.free()
	b.free()
