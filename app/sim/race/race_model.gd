# DR-25/DR-26: composition of one controlled multirotor plant (physics/multirotor/controlled_plant.gd) and the local race
# director into ONE framed sampled VehicleModel (sim/vehicle_model.gd, protocol framed-sampled-v1). The plant's blocks
# come first and are passed to the plant unchanged; a bounded race suffix follows in aux and modes, and the pilot frame
# gains one race action input. The plant's physics, controller and arming rules are reused exactly; the wrapper only:
#   sample:   runs the plant sample, then the director's start/cancel/GO staging (a refused GO also drops the
#             controller's arm authorization in that same candidate sample: motor DISARMED, no OFF observed);
#   stage:    hands the plant a NEW sampled context whose held motor commands are zero while the race phase inhibits
#             drive (READY/COUNTDOWN); the commands the controller sampled stay in aux as evidence;
#   endpoint: runs the plant's physical endpoint first, builds the tick's accepted chord piece (policy
#             openrc-chord-path-v1, race_director.gd) and lets the director adjudicate; it returns one ordered event list
#             (physical and race events) — the plant has no step policy, so the kernel adds no located events of its own;
#   validator: the plant validator on the plant slices AND the race domains, including the course tag.
# Every value the race needs between ticks lives in the kernel's checkpointed arrays; nothing on this object changes
# after wrap(). Local practice rules only: no FAI/MultiGP compliance, no timing accuracy beyond the declared
# chord-path envelope. 64-bit floats only.
extends RefCounted

const VehicleModel := preload("res://sim/vehicle_model.gd")
const Director := preload("res://sim/race/race_director.gd")
const Track := preload("res://sim/race/track.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const LAYOUT_SUFFIX := "+openrc-local-race-v1"

## Plant block sizes this wrapper is written for (checked against the plant's model at wrap()).
const PLANT_INPUT_SIZE := 9
const PLANT_AUX_SIZE := 31
const PLANT_MODES_SIZE := 8

## Pilot frame: the plant's nine values, then the race action (0 none, 1 start request, 2 cancel).
const INPUT_SIZE := 10
const IN_RACE_ACTION := 9

## Aux: plant 0..30, race suffix 31..39.
const AUX_RACE := 31
const AUX_SIZE := 40
const AUX_GO_TIME := 31
const AUX_LAP_START := 32
const AUX_LAP_DURATION := 33 # 33, 34, 35
const AUX_LAST_GATE_TIME := 36
const AUX_ATTEMPT_START := 37
const AUX_FINISH_TIME := 38
const AUX_COURSE_TAG := 39

## Modes: plant 0..7, race suffix 8..17.
const MODES_RACE := 8
const MODES_SIZE := 18
const MODE_PHASE := 8
const MODE_COUNTDOWN := 9
const MODE_NEXT_GATE := 10
const MODE_VALID_LAPS := 11
const MODE_ATTEMPT := 12
const MODE_REASON := 13
const MODE_UNRESOLVED := 14
const MODE_GATES_TOTAL := 15
const MODE_EVENT_SEQUENCE := 16
const MODE_STAGED := 17

const RESULT_FORMAT := "openrc-race-result v1"

var plant: RefCounted
var plant_model: VehicleModel
var plant_validator: Callable
var course: Dictionary
var rules: Dictionary
var arm_low_throttle: float = 0.0
var kernel_validator: bool = true


## {ok, errors, model, wrapper}. `plant` is a created controlled multirotor plant; `course` a Track.prepare() course.
## The caller keeps `wrapper` for the frame helpers; the model's callbacks hold it alive on their own.
## kernel_validator = false leaves the kernel's per-step validator hook unset (its guarded frame copies run twice a
## tick): the same check then runs inside the endpoint transition on every accepted tick, and the owning session
## must call validate() before it commits a reset or a restore.
static func wrap(source_plant: RefCounted, prepared_course: Dictionary, kernel_validator: bool = true) -> Dictionary:
	var errors := PackedStringArray()
	if source_plant == null or not source_plant.has_method("build") or not source_plant.has_method("initial_frame"):
		return {ok = false, errors = PackedStringArray(["race: the plant is not a controlled multirotor plant"]), model = null,
			wrapper = null}
	var inner: VehicleModel = source_plant.build()
	if inner.callback_protocol != VehicleModel.PROTOCOL_FRAMED_SAMPLED or inner.input_size != PLANT_INPUT_SIZE \
			or inner.aux_size != PLANT_AUX_SIZE or inner.modes_size != PLANT_MODES_SIZE or inner.continuous_size <= 0 \
			or inner.state_layout_identity.is_empty():
		errors.append("race: the plant model's protocol or layout is not the controlled multirotor layout this wrapper composes")
	if inner.step_policy.is_valid() or not inner.events.is_empty() or inner.post_tick.is_valid() \
			or inner.post_tick_joint.is_valid() or inner.block_aux.is_valid():
		errors.append("race: plant step policies, kernel events, body filters and aux projection are not composed in v1")
	if not inner.endpoint_transition.is_valid():
		errors.append("race: the plant must supply an endpoint transition")
	# The plant may run its domain check inside its endpoint instead of installing it; the race validator always
	# applies it (reset, restore and every accepted tick), together with the race domains.
	var validator: Callable = inner.state_validator if inner.state_validator.is_valid() \
		else (Callable(source_plant, "state_validator") if source_plant.has_method("state_validator") else Callable())
	if not validator.is_valid():
		errors.append("race: the plant must supply a state validator")
	var pinned_rules: Dictionary = Track.ruleset()
	if prepared_course.is_empty() or typeof(prepared_course.get("gates")) != TYPE_ARRAY \
			or typeof(prepared_course.get("identity")) != TYPE_STRING or typeof(prepared_course.get("tag")) != TYPE_FLOAT \
			or prepared_course.get("ruleset", {}) != pinned_rules or int(prepared_course.get("gate_count", 0)) != prepared_course.gates.size() \
			or prepared_course.gates.size() < Track.MIN_GATES or prepared_course.gates.size() > Track.MAX_GATES \
			or int(prepared_course.get("laps", 0)) != int(pinned_rules.laps):
		errors.append("race: the course is not a prepared %s course" % Track.RULESET)
	var low: Variant = source_plant.get("config").get("arm_low_throttle") if typeof(source_plant.get("config")) == TYPE_DICTIONARY else null
	if typeof(low) != TYPE_FLOAT or not is_finite(low):
		errors.append("race: the plant controller exposes no arm_low_throttle")
	if not errors.is_empty():
		return {ok = false, errors = errors, model = null, wrapper = null}
	var wrapper: RefCounted = (load("res://sim/race/race_model.gd") as GDScript).new()
	wrapper.plant = source_plant
	wrapper.plant_model = inner
	wrapper.plant_validator = validator
	wrapper.course = prepared_course.duplicate(true)
	wrapper.rules = pinned_rules
	wrapper.arm_low_throttle = low
	var vehicle := VehicleModel.new()
	vehicle.callback_protocol = VehicleModel.PROTOCOL_FRAMED_SAMPLED
	vehicle.state_layout_identity = inner.state_layout_identity + LAYOUT_SUFFIX
	vehicle.input_size = INPUT_SIZE
	vehicle.aux_size = AUX_SIZE
	vehicle.modes_size = MODES_SIZE
	vehicle.continuous_size = inner.continuous_size
	# Contact substeps read only body and continuous state, which the wrapper passes unchanged: reuse them as declared.
	vehicle.substeps = inner.substeps
	vehicle.substeps_joint = inner.substeps_joint
	var identity: Dictionary = inner.identity.duplicate(true)
	identity.race_ruleset = Track.RULESET
	identity.race_course = str(prepared_course.identity)
	identity.race_path_policy = Track.PATH_POLICY
	vehicle.identity = identity
	# Lambdas capture the wrapper so the installed model keeps it (and the plant) alive.
	vehicle.sample_tick = func(frame: Dictionary, pilot_frame: PackedFloat64Array, clock: Dictionary) -> Dictionary:
		return wrapper._sample(frame, pilot_frame, clock)
	vehicle.stage_sampled = func(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float, context: Dictionary) -> Dictionary:
		return wrapper._stage(body, continuous, t, context)
	vehicle.endpoint_transition = func(previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
		return wrapper._endpoint(previous, candidate, context)
	wrapper.kernel_validator = kernel_validator
	if kernel_validator:
		vehicle.state_validator = func(frame: Dictionary, context: Dictionary) -> bool:
			return wrapper._validate(frame, context)
	var contract: Dictionary = VehicleModel.validate(vehicle)
	if not contract.ok:
		return {ok = false, errors = PackedStringArray(["race: " + str(contract.message)]), model = null, wrapper = null}
	return {ok = true, errors = errors, model = vehicle, wrapper = wrapper}


## The plant's prepared start frame plus a zeroed race suffix in IDLE (course tag set).
func initial_frame(body: PackedFloat64Array, source_generation: int = 0, soc: float = -1.0) -> Dictionary:
	var frame: Dictionary = plant.initial_frame(body, source_generation, soc)
	var aux: PackedFloat64Array = frame.aux.duplicate()
	aux.append_array(Director.empty_aux(float(course.tag)))
	var modes: PackedInt64Array = frame.modes.duplicate()
	modes.append_array(Director.empty_modes())
	return {body = frame.body.duplicate(), continuous = frame.continuous.duplicate(), aux = aux, modes = modes}


## The ten-value pilot frame for the kernel.
func input(pilot: PackedFloat64Array, race_action: int = Director.ACTION_NONE) -> PackedFloat64Array:
	var frame: PackedFloat64Array = pilot.duplicate()
	frame.append(float(race_action))
	return frame


## The plant's slices of a wrapped frame (plant telemetry, plant validator).
func plant_frame(frame: Dictionary) -> Dictionary:
	return {body = frame.body.duplicate(), continuous = frame.continuous.duplicate(),
		aux = frame.aux.slice(0, PLANT_AUX_SIZE), modes = frame.modes.slice(0, PLANT_MODES_SIZE)}


func _race(frame: Dictionary) -> Dictionary:
	return {aux = frame.aux.slice(AUX_RACE), modes = frame.modes.slice(MODES_RACE)}


## Decoded race state. now_s >= 0 (the accepted frame's clock) adds elapsed lap and attempt times while racing.
func race_state(frame: Dictionary, now_s: float = -1.0) -> Dictionary:
	var race: Dictionary = _race(frame)
	var aux: PackedFloat64Array = race.aux
	var modes: PackedInt64Array = race.modes
	var phase: int = modes[Director.D_PHASE]
	var valid_laps: int = modes[Director.D_VALID_LAPS]
	var laps: Array = []
	for i in int(course.laps):
		laps.append({lap = i + 1, duration_s = aux[Director.A_LAP_DURATION + i], valid = i < valid_laps})
	var countdown: int = modes[Director.D_COUNTDOWN]
	var next_gate: int = modes[Director.D_NEXT_GATE]
	var state := {phase = Director.PHASE_NAMES[phase], phase_code = phase, countdown_ticks = countdown,
		countdown_s_left = float(int(rules.countdown_ticks) - countdown) / float(rules.sample_hz) if phase == Director.PHASE_COUNTDOWN else 0.0,
		next_gate = next_gate, next_gate_id = str(course.gates[next_gate].id), gate_count = int(course.gate_count),
		valid_laps = valid_laps, laps = laps, attempt = int(modes[Director.D_ATTEMPT]),
		reason = Director.REASON_NAMES[modes[Director.D_REASON]], reason_code = int(modes[Director.D_REASON]),
		unresolved = int(modes[Director.D_UNRESOLVED]), gates_passed = int(modes[Director.D_GATES_TOTAL]),
		go_time_s = aux[Director.A_GO_TIME], lap_start_time_s = aux[Director.A_LAP_START],
		last_gate_time_s = aux[Director.A_LAST_GATE_TIME], attempt_start_time_s = aux[Director.A_ATTEMPT_START],
		finish_time_s = aux[Director.A_FINISH_TIME], elapsed_lap_s = 0.0, elapsed_total_s = 0.0}
	if phase == Director.PHASE_RACING and now_s >= aux[Director.A_LAP_START]:
		state.elapsed_lap_s = now_s - aux[Director.A_LAP_START]
		state.elapsed_total_s = now_s - aux[Director.A_GO_TIME]
	elif phase == Director.PHASE_FINISHED:
		state.elapsed_total_s = aux[Director.A_FINISH_TIME] - aux[Director.A_GO_TIME]
	return state


## Terminal record projection of a FINISHED or ABORTED attempt (plain bounded values; deterministic). Other phases
## return {terminal = false} with the same keys so the shape is fixed.
func result(frame: Dictionary) -> Dictionary:
	var race: Dictionary = _race(frame)
	var aux: PackedFloat64Array = race.aux
	var modes: PackedInt64Array = race.modes
	var phase: int = modes[Director.D_PHASE]
	var valid_laps: int = modes[Director.D_VALID_LAPS]
	var laps: Array = []
	for i in valid_laps:
		laps.append({lap = i + 1, duration_s = aux[Director.A_LAP_DURATION + i], valid = true})
	var finished: bool = phase == Director.PHASE_FINISHED
	return {format = RESULT_FORMAT, terminal = finished or phase == Director.PHASE_ABORTED,
		attempt = int(modes[Director.D_ATTEMPT]), phase = Director.PHASE_NAMES[phase], valid = finished,
		valid_laps = valid_laps, laps_required = int(course.laps), laps = laps,
		total_s = aux[Director.A_FINISH_TIME] - aux[Director.A_GO_TIME] if finished else 0.0,
		go_time_s = aux[Director.A_GO_TIME], finish_time_s = aux[Director.A_FINISH_TIME],
		reason = Director.REASON_NAMES[modes[Director.D_REASON]], reason_code = int(modes[Director.D_REASON]),
		unresolved = int(modes[Director.D_UNRESOLVED]), gates_passed = int(modes[Director.D_GATES_TOTAL]),
		course_identity = str(course.identity), track_id = str(course.track_id), field_id = str(course.field_id),
		ruleset = Track.RULESET, path_policy = Track.PATH_POLICY,
		acceleration_envelope_mps2 = float(rules.acceleration_envelope_mps2),
		tie_window_s = float(rules.tie_window_s)}


## A nonfinite candidate of the declared size: the kernel refuses the tick.
static func _refused_sample() -> Dictionary:
	var aux := PackedFloat64Array()
	aux.resize(AUX_SIZE)
	aux[0] = NAN
	var modes := PackedInt64Array()
	modes.resize(MODES_SIZE)
	return {aux = aux, modes = modes}


static func _world_velocity(body: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_rotate(M.quat(body[RB.ATT], body[RB.ATT + 1], body[RB.ATT + 2], body[RB.ATT + 3]),
		M.v3(body[RB.VEL], body[RB.VEL + 1], body[RB.VEL + 2]))


func _sample(frame: Dictionary, pilot_frame: PackedFloat64Array, clock: Dictionary) -> Dictionary:
	if pilot_frame.size() != INPUT_SIZE or frame.aux.size() != AUX_SIZE or frame.modes.size() != MODES_SIZE:
		return _refused_sample()
	var action: float = pilot_frame[IN_RACE_ACTION]
	if not is_finite(action) or action not in [0.0, 1.0, 2.0]:
		return _refused_sample()
	var pilot: PackedFloat64Array = pilot_frame.slice(0, PLANT_INPUT_SIZE)
	var sampled: Variant = plant_model.sample_tick.call(plant_frame(frame), pilot, clock)
	if typeof(sampled) != TYPE_DICTIONARY or typeof(sampled.get("aux")) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(sampled.get("modes")) != TYPE_PACKED_INT64_ARRAY or sampled.aux.size() != PLANT_AUX_SIZE \
			or sampled.modes.size() != PLANT_MODES_SIZE:
		return _refused_sample()
	var plant_aux: PackedFloat64Array = sampled.aux.duplicate()
	var plant_modes: PackedInt64Array = sampled.modes.duplicate()
	for value: float in plant_aux:
		if not is_finite(value):
			return _refused_sample()
	var body: PackedFloat64Array = frame.body
	var velocity: PackedFloat64Array = _world_velocity(body)
	var previous_motor: int = frame.modes[FC.MODE_MOTOR]
	var facts := {north = body[RB.POS], east = body[RB.POS + 1], down = body[RB.POS + 2], speed_mps = M.norm(velocity),
		terminal = previous_motor == FC.MOTOR_CRASHED or previous_motor == FC.MOTOR_DEPLETED,
		armed = plant_modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED, throttle = pilot[FC.IN_THROTTLE],
		collective = plant_aux[FC.AUX_COLLECTIVE], arm_low_throttle = arm_low_throttle,
		source_ready = pilot[FC.IN_SOURCE_READY] == 1.0}
	var staged: Dictionary = Director.stage(_race(frame), int(action), facts, course, rules, clock)
	if staged.force_disarm and plant_modes[FC.MODE_MOTOR] != FC.MOTOR_CRASHED and plant_modes[FC.MODE_MOTOR] != FC.MOTOR_DEPLETED:
		plant_modes[FC.MODE_MOTOR] = FC.MOTOR_DISARMED
		plant_modes[FC.MODE_OFF_OBSERVED] = 0
		if plant_modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_NONE:
			plant_modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_THROTTLE
	plant_aux.append_array(staged.aux)
	plant_modes.append_array(staged.modes)
	return {aux = plant_aux, modes = plant_modes}


func _stage(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float, context: Dictionary) -> Variant:
	var aux: PackedFloat64Array = context.aux.slice(0, PLANT_AUX_SIZE)
	var phase: int = context.modes[MODE_PHASE] if context.modes.size() == MODES_SIZE else -1
	if phase == Director.PHASE_READY or phase == Director.PHASE_COUNTDOWN:
		for i in 4:
			aux[FC.AUX_COMMAND + i] = 0.0
	var plant_context := {aux = aux, modes = context.modes.slice(0, PLANT_MODES_SIZE), sample_tick = context.sample_tick,
		sample_time_s = context.sample_time_s}
	return plant_model.stage_sampled.call(body, continuous, t, plant_context)


func _endpoint(previous: Dictionary, candidate: Dictionary, context: Dictionary) -> Dictionary:
	var plant_candidate := {body = candidate.body.duplicate(), continuous = candidate.continuous.duplicate(),
		aux = candidate.aux.slice(0, PLANT_AUX_SIZE), modes = candidate.modes.slice(0, PLANT_MODES_SIZE)}
	var inner: Variant = plant_model.endpoint_transition.call(plant_frame(previous), plant_candidate, context.duplicate(true))
	if typeof(inner) != TYPE_DICTIONARY or not inner.has_all(["body", "continuous", "aux", "modes", "events"]) \
			or typeof(inner.body) != TYPE_PACKED_FLOAT64_ARRAY or typeof(inner.aux) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(inner.modes) != TYPE_PACKED_INT64_ARRAY or typeof(inner.events) != TYPE_ARRAY \
			or inner.body.size() != RB.SIZE:
		var refused: Dictionary = _refused_sample()
		return {body = candidate.body, continuous = candidate.continuous, aux = refused.aux, modes = candidate.modes, events = []}
	var accepted_body: PackedFloat64Array = inner.body
	var dt: float = float(context.dt)
	var t0: float = float(int(context.tick) - 1) * dt # the kernel's start-of-tick clock, tick * dt
	var t1: float = float(context.time_s)
	var qualified: bool = not bool(context.get("body_filtered", true)) \
		and accepted_body.to_byte_array() == candidate.body.to_byte_array()
	if qualified:
		var dv: PackedFloat64Array = M.sub(_world_velocity(accepted_body), _world_velocity(previous.body))
		qualified = M.norm(dv) / dt <= float(rules.acceleration_envelope_mps2)
	var piece := {p0 = previous.body.slice(RB.POS, RB.POS + 3), t0 = t0, p1 = accepted_body.slice(RB.POS, RB.POS + 3),
		t1 = t1, qualified = qualified}
	var adjudicated: Dictionary = Director.advance(_race(candidate), piece, inner.events, course, rules, context)
	var aux: PackedFloat64Array = inner.aux.duplicate()
	aux.append_array(adjudicated.aux_suffix)
	var modes: PackedInt64Array = inner.modes.duplicate()
	modes.append_array(adjudicated.modes_suffix)
	var accepted := {body = accepted_body.duplicate(), continuous = inner.continuous.duplicate(), aux = aux, modes = modes}
	if not kernel_validator and not _validate(accepted, {tick = int(context.tick), time_s = t1, dt = dt}):
		var invalid: Dictionary = _refused_sample()
		return {body = candidate.body, continuous = candidate.continuous, aux = invalid.aux, modes = candidate.modes, events = []}
	accepted.events = adjudicated.events
	return accepted


## The frame domain check (plant domains and race domains) for an owner that wrapped without the kernel hook.
func validate(frame: Dictionary, context: Dictionary) -> bool:
	return _validate(frame, context)


func _validate(frame: Dictionary, context: Dictionary) -> bool:
	if typeof(frame.get("aux")) != TYPE_PACKED_FLOAT64_ARRAY or typeof(frame.get("modes")) != TYPE_PACKED_INT64_ARRAY \
			or frame.aux.size() != AUX_SIZE or frame.modes.size() != MODES_SIZE:
		return false
	var plant_ok: Variant = plant_validator.call(plant_frame(frame), context)
	if typeof(plant_ok) != TYPE_BOOL or not plant_ok:
		return false
	var race: Dictionary = _race(frame)
	return Director.validate(race.aux, race.modes, course, rules, float(context.get("time_s", NAN)))
