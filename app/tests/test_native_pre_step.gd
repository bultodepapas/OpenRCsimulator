extends SceneTree
## NK-5g: the native pre-step must return FlightSession._pre_step's next aux, and leave its sim.modes[1], bit for bit.
## - The RNG port draws exactly what the engine's RandomNumberGenerator draws from any raw state.
## - Random committed states, aux, inputs and wheel speeds for the whole fixed-wing fleet in calm, gusty, turbulent
##   and spatial weather: every native answer equals the pure GDScript reference (reference wing wake), and the
##   native pre-step refuses exactly where the reference returns an invalid aux (bad inputs, [NAN] results).
## - Paired sessions with and without the native pre-step fly byte-identical ticks through takeoffs with gear and
##   flap cycles, landings, glides with the engine off and turbulent or spatial weather, answering every tick.
## - Failures route to the reference. Skips (passes) without a verified native library.

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const Weather := preload("res://physics/wind_config.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")

const SAMPLES := 1200
const WEATHERS := ["calm", "gusty", "turbulent", "spatial"]
var _checks := 0
var _failures := 0
var _rng := RandomNumberGenerator.new()
var _field: Dictionary
var _lake: Dictionary
var _fleet: PackedStringArray = []
var _start_for := {} # runway where the aircraft can start there, else airborne


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _run() -> void:
	_rng.seed = 51517
	_field = FieldLoader.load_from().field
	_lake = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for id: String in Catalog.ids():
		var start: String = Flight.START_RUNWAY
		var probe := _session(id, start, "calm")
		if probe == null:
			start = Flight.START_AIRBORNE
			probe = _session(id, start, "calm")
		if probe == null:
			print("NK5G_SKIP %s: no flyable fixed-wing session" % id)
			continue
		if probe.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE and probe._native_stage._pre_step_bound:
			_fleet.append(id)
			_start_for[id] = start
		else:
			print("NK5G_SKIP %s: %s" % [id, str(probe.stage_backend_status())])
		probe.free()
	if _fleet.is_empty():
		print("NK5G_PRE_STEP_SKIP no native fixed-wing session")
		print("native pre-step: %d checks, %d failed" % [_checks, _failures])
		quit(0)
		return
	_rng_probe()
	for weather: String in WEATHERS:
		for id: String in _fleet:
			_direct(id, weather)
	for id: String in _fleet:
		if _start_for[id] == Flight.START_RUNWAY:
			_flight(id, "calm", "takeoff")
			_flight(id, "calm", "landing")
		_flight(id, "calm", "glide")
	for id: String in ["f4u-corsair-250", "jensen-das-ugly-stik-60", "sebart-avanti-s-a200-p100rx"]:
		if id in _fleet and _start_for[id] == Flight.START_RUNWAY:
			for weather: String in ["gusty", "turbulent", "spatial"]:
				_flight(id, weather, "takeoff")
	_routing()
	print("native pre-step: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _weather_config(weather: String) -> Variant:
	match weather:
		"gusty": return Weather.preset("gusty")
		"turbulent": return Weather.preset("turbulent")
		"spatial": return Weather.spatial_defaults()
	return null


func _session(id: String, start: String, weather: String, enabled := true) -> Node:
	var s: Node = Flight.new()
	s.input_enabled = true
	s.crash_auto_restart = false
	s.soft_hull_contacts = true
	s.cost_observations_enabled = true
	s.native_pre_step_enabled = enabled
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
		print("NK5G weather %s refused for %s: %s" % [weather, id, s.weather_error])
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


## The port draws what RandomNumberGenerator draws: WindTurbulence restores a raw state after any seed.
func _rng_probe() -> void:
	var probe: Node = _session(_fleet[0], _start_for[_fleet[0]], "calm")
	var kernel: Object = probe._native_stage._native
	var mismatched := 0
	for i in 400:
		var state: int = (_rng.randi() << 32) | _rng.randi()
		if i % 3 == 0:
			state = -state
		var engine := RandomNumberGenerator.new()
		engine.seed = _rng.randi()
		engine.state = state
		var expected := PackedInt64Array()
		for k in 24:
			expected.append(engine.randi())
		expected.append(engine.state)
		if kernel.pre_step_rng_probe(state, 24) != expected:
			mismatched += 1
	_check("the PCG32 port draws the engine RandomNumberGenerator's values and state", mismatched == 0,
		"%d of 400 states differ" % mismatched)
	probe.free()


## Random committed endpoints, aux and inputs around the field: native answers equal the pure reference.
func _direct(id: String, weather: String) -> void:
	var s := _session(id, _start_for[id], weather)
	if s == null:
		return
	if s.stage_backend_identity().backend != NativeStage.BACKEND_NATIVE or not s._native_stage._pre_step_bound:
		print("NK5G_DIRECT_SKIP %s %s: %s" % [id, weather, str(s.stage_backend_status())])
		s.free()
		return
	for i in 30:
		_tick(s)
	var dt: float = s.sim.dt()
	var base_aux: PackedFloat64Array = s.sim.aux.duplicate()
	var base_state: PackedFloat64Array = s.sim.state.duplicate()
	var base_continuous: PackedFloat64Array = s.sim.continuous.duplicate()
	var base_inputs: PackedFloat64Array = s.sim.inputs.duplicate()
	var base_modes: PackedInt64Array = s.sim.modes.duplicate()
	var shore: PackedFloat64Array = _lake.shoreline_ne_m
	var gear_index: int = s.gear_aux_index()
	var flap_aux: int = s.flap_aux_index()
	var flap_input: int = s.flap_input_index()
	var brake: int = s.wheel_brake_input_index()
	var lag: int = s.downwash_index()
	var turbulence: int = s.turbulence_index() if s._weather.has_turbulence() else -1
	var anchor_count: int = s.anchor_count()
	var stats := {answered = 0, refused = 0, invalid = 0, wrong_refusal = 0, mismatched = 0, held = 0, stuck = 0,
		weight_on_wheels = 0, rng = 0}
	var first := ""
	for i in SAMPLES:
		var aux := base_aux.duplicate()
		var body := base_state.duplicate()
		var continuous := base_continuous.duplicate()
		var inputs := base_inputs.duplicate()
		var modes := base_modes.duplicate()
		match i % 4:
			3:
				body[RB.POS] = _centroid(shore, 0) + _rng.randf_range(-40.0, 40.0)
				body[RB.POS + 1] = _centroid(shore, 1) + _rng.randf_range(-40.0, 40.0)
			2:
				body[RB.POS] = _rng.randf_range(-400.0, 400.0)
				body[RB.POS + 1] = _rng.randf_range(-400.0, 400.0)
			_:
				body[RB.POS] += _rng.randf_range(-60.0, 60.0)
				body[RB.POS + 1] += _rng.randf_range(-60.0, 60.0)
		var ground: float = Ground.Terrain.sample(body[RB.POS], body[RB.POS + 1], s.ground_surfaces, s._lake)[0]
		body[RB.POS + 2] = -ground - (_rng.randf_range(1.0, 40.0) if i % 5 == 0 else _rng.randf_range(-0.05, 0.6))
		# NED attitude [w, x, y, z]: a heading about down (z), then a small tilt about a random body axis.
		var heading := Quaternion(Vector3(0.0, 0.0, 1.0), _rng.randf_range(-PI, PI))
		var tilt := Quaternion(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			_rng.randf_range(-0.12, 0.12))
		var q := (heading * tilt).normalized()
		body[RB.ATT] = q.w
		body[RB.ATT + 1] = q.x
		body[RB.ATT + 2] = q.y
		body[RB.ATT + 3] = q.z
		var slow: bool = i % 3 == 0
		for axis: int in 3:
			body[RB.VEL + axis] = _rng.randf_range(-0.01, 0.01) if slow else _rng.randf_range(-6.0, 6.0)
			body[RB.RATE + axis] = _rng.randf_range(-0.001, 0.001) if slow else _rng.randf_range(-0.4, 0.4)
		aux[0] = _rng.randf_range(0.0, 12000.0)
		for k in 3:
			aux[1 + k] = _rng.randf_range(-1.0, 1.0)
			inputs[k] = _rng.randf_range(-1.0, 1.0)
		inputs[3] = _rng.randf()
		if gear_index >= 0:
			aux[gear_index] = [0.0, 1.0, 1.0, _rng.randf()][_rng.randi_range(0, 3)]
			aux[gear_index + 1] = 1.0 if _rng.randf() < 0.6 else 0.0
			inputs[4] = 0.0 if _rng.randf() < 0.6 else 1.0
			inputs[5] = _rng.randf()
		elif brake >= 0:
			inputs[brake] = _rng.randf()
		if flap_aux >= 0:
			aux[flap_aux] = [0.0, 1.0, _rng.randf()][_rng.randi_range(0, 2)]
			inputs[flap_input] = [0.0, 1.0, _rng.randf()][_rng.randi_range(0, 2)]
		if lag >= 0:
			aux[lag] = _rng.randf_range(-0.5, 1.5)
		# Anchors: sliding, stuck near the wheel's ground point, or far from it; rim speeds on or off the stick band.
		var gear: Dictionary = s.current_landing_gear(aux)
		for k in anchor_count:
			var at: int = s.AUX_ANCHORS + k * 3
			var choice: int = _rng.randi_range(0, 3)
			aux[at] = 0.0
			aux[at + 1] = 0.0
			aux[at + 2] = 0.0
			if choice > 0 and not gear.is_empty() and k < gear.contacts.size():
				var frame: Dictionary = Ground.Wheels.frame(body, gear.contacts[k], aux[3], s.ground_surfaces,
					PackedFloat64Array(), false, s._lake)
				var spread: float = [0.0, 0.004, 0.3][choice - 1]
				aux[at] = frame.position[0] + _rng.randf_range(-spread, spread)
				aux[at + 1] = frame.position[1] + _rng.randf_range(-spread, spread)
				aux[at + 2] = 1.0
				if s.wheel_count() > 0 and k < s.wheel_count():
					continuous[s.wheel_index() + k] = float(frame.long_speed) + (0.0 if _rng.randf() < 0.6 else _rng.randf_range(-0.05, 0.05))
		if turbulence >= 0:
			for k in 6:
				aux[turbulence + k] = _rng.randf_range(-3.0, 3.0)
			modes[1] = (_rng.randi() << 32) | _rng.randi()
		# A few invalid inputs: the reference returns [NAN] and the native pre-step must refuse.
		if i % 37 == 5:
			match _rng.randi_range(0, 3):
				0: if gear_index >= 0: inputs[4] = 0.5
				1: if brake >= 0: inputs[brake] = 1.5
				2: if flap_input >= 0: inputs[flap_input] = NAN
				3: if gear_index >= 0: aux[gear_index + 1] = 0.5
		var tick: int = _rng.randi_range(1, 200000)
		var running: bool = i % 5 != 1
		var owner: String = "simulator" if i % 2 == 0 else "external"
		var reference := _evaluate(s, body, continuous, aux, modes, tick, running, owner, func() -> PackedFloat64Array:
			s._native_wake_admitted = false
			return s._pre_step(aux.duplicate(), inputs.duplicate(), dt))
		var reference_modes: PackedInt64Array = s.sim.modes.duplicate()
		var native := _evaluate(s, body, continuous, aux, modes, tick, running, owner, func() -> PackedFloat64Array:
			return s._native_stage.pre_step(s, aux.duplicate(), inputs.duplicate(), dt))
		var native_modes: PackedInt64Array = s.sim.modes.duplicate()
		var valid := reference.size() == aux.size()
		for value: float in reference:
			valid = valid and is_finite(value)
		if not valid:
			stats.invalid += 1
		if native.is_empty():
			stats.refused += 1
			if valid:
				stats.wrong_refusal += 1
				if first.is_empty():
					first = "refused a valid reference at sample %d" % i
			continue
		stats.answered += 1
		if not valid or var_to_bytes(native) != var_to_bytes(reference) or var_to_bytes(native_modes) != var_to_bytes(reference_modes):
			stats.mismatched += 1
			if first.is_empty():
				first = "sample %d: %s / %s" % [i, str(native), str(reference)]
			continue
		for k in anchor_count:
			var at: int = s.AUX_ANCHORS + k * 3
			if aux[at + 2] == 1.0 and reference[at + 2] == 1.0:
				stats.held += 1
			elif aux[at + 2] != 1.0 and reference[at + 2] == 1.0:
				stats.stuck += 1
		if gear_index >= 0 and inputs[4] == 0.0 and reference[gear_index + 1] == 1.0:
			stats.weight_on_wheels += 1
		if turbulence >= 0 and native_modes != base_modes:
			stats.rng += 1
	_check("%s %s: every native pre-step equals the reference bit for bit" % [id, weather], stats.mismatched == 0,
		first + " " + str(stats))
	_check("%s %s: the native pre-step refuses only invalid references" % [id, weather], stats.wrong_refusal == 0
		and stats.answered + stats.invalid >= SAMPLES, first + " " + str(stats))
	if anchor_count > 0 and weather == "calm":
		_check("%s: anchors hold and stick in the samples" % id, stats.held > 0 and stats.stuck > 0, str(stats))
	if gear_index >= 0 and weather == "calm":
		_check("%s: the gear's weight-on-wheels interlock engages" % id, stats.weight_on_wheels > 0, str(stats))
	if turbulence >= 0:
		_check("%s %s: turbulence draws advance the RNG" % [id, weather], stats.rng > 0, str(stats))
	print("NK5G_DIRECT %s %s %s" % [id, weather, str(stats)])
	s.free()


## Install one sample in the session (as the kernel holds it at pre_tick) and evaluate `call` there.
func _evaluate(s: Node, body: PackedFloat64Array, continuous: PackedFloat64Array, aux: PackedFloat64Array,
		modes: PackedInt64Array, tick: int, running: bool, owner: String, call: Callable) -> PackedFloat64Array:
	s.sim.state = body.duplicate()
	s.sim.continuous = continuous.duplicate()
	s.sim.aux = aux.duplicate()
	s.sim.modes = modes.duplicate()
	s.sim.tick = tick
	s.engine_running = running
	s._flap_mix_owner = owner
	return call.call()


## Fly the same scripted flight with and without the native pre-step; every tick must match and answer natively.
func _flight(id: String, weather: String, scenario: String) -> void:
	var start: String = Flight.START_AIRBORNE if scenario == "glide" else Flight.START_RUNWAY
	var sessions: Array[Node] = [_session(id, start, weather, true), _session(id, start, weather, false)]
	if sessions[0] == null or sessions[1] == null:
		for s: Node in sessions:
			if s != null:
				s.free()
		return
	var ticks: int = {takeoff = 1680, landing = 720, glide = 1440}[scenario]
	for s: Node in sessions:
		if scenario == "landing":
			var body: PackedFloat64Array = s.sim.state.duplicate()
			body[RB.POS + 2] -= 0.8
			body[RB.VEL] = 14.0
			body[RB.VEL + 2] = 2.5
			s.sim.reset(body)
			s.set_flaps(1.0)
		if scenario == "glide":
			s.engine_running = false
		if scenario == "takeoff":
			s.set_flaps(0.5)
		var throttle: float = {takeoff = 1.0, landing = 0.2, glide = 0.0}[scenario]
		s.read_raw = func() -> Dictionary:
			var pitch := 0.0
			if scenario == "takeoff" and s.sim.tick > 360:
				pitch = 0.3
			elif scenario == "glide":
				pitch = 0.05
			return {roll = 0.02 if s.sim.tick % 400 < 200 else -0.02, pitch = pitch, yaw = 0.08, throttle = throttle}
	var identical := true
	var detail := ""
	var stepped := 0
	for tick in ticks:
		for s: Node in sessions:
			if scenario == "takeoff" and tick == 700:
				s.set_flaps(0.0)
			if scenario == "takeoff" and tick == 900:
				s.set_gear_down(false)
			if scenario == "glide" and tick in [20, 700]:
				s.set_gear_down(tick == 700)
				s.set_flaps(1.0 if tick == 20 else 0.0)
			_tick(s)
		var a: Node = sessions[0]
		var b: Node = sessions[1]
		if var_to_bytes([a.sim.tick, a.sim.state, a.sim.continuous, a.sim.aux, a.sim.modes, a.sim.fault_reason, a.crash.keys(),
				a._contact_events, a.sim.last_events]) != var_to_bytes([b.sim.tick, b.sim.state, b.sim.continuous, b.sim.aux,
				b.sim.modes, b.sim.fault_reason, b.crash.keys(), b._contact_events, b.sim.last_events]):
			identical = false
			detail = "tick %d: aux %s / %s" % [tick, str(a.sim.aux), str(b.sim.aux)]
			break
		stepped = a.sim.tick
		if not a.crash.is_empty() or not a.sim.fault_reason.is_empty():
			break
	var native: Node = sessions[0]
	var outcome: String = "crash" if not native.crash.is_empty() else ("fault" if not native.sim.fault_reason.is_empty() else "flying")
	_check("%s %s %s flies identically with and without the native pre-step (%d ticks, %s)" % [id, weather, scenario,
		stepped, outcome], identical, detail)
	_check("%s %s %s: every guarded pre-step answered natively" % [id, weather, scenario],
		native.native_pre_step_answers == stepped and stepped > 0 and sessions[1].native_pre_step_answers == 0,
		"answers %d stepped %d" % [native.native_pre_step_answers, stepped])
	print("NK5G_FLIGHT %s %s %s ticks=%d outcome=%s answers=%d height=%.1f" % [id, weather, scenario, stepped, outcome,
		native.native_pre_step_answers, -native.sim.state[2]])
	for s: Node in sessions:
		s.free()


## Active failures keep the reference pre-step (the incident module owns its inputs).
func _routing() -> void:
	var s := _session(_fleet[0], _start_for[_fleet[0]], "calm")
	var armed: bool = s.setup_failures({probability_percent = 100, include_catastrophic = false, notify = false}, 7)
	if armed:
		for i in 120:
			_tick(s)
		_check("active failures route every pre-step to the reference", s.native_pre_step_answers == 0
			and s.sim.tick > 0, "answers %d tick %d" % [s.native_pre_step_answers, s.sim.tick])
	else:
		print("NK5G_ROUTING failures not armed: %s" % s.failure_error)
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
