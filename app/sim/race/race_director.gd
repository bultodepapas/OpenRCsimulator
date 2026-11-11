# DR-25/DR-26: the pure race state machine of ruleset `openrc-local-race-v1` (FPV/02 §8, FPV/04 §3).
# Two static pure transitions over the bounded race suffix (9 float64 + 10 int64 values):
#   stage(race, action, facts, course, rules, clock)  in the sampled callback: start/cancel requests and the GO
#     decision at countdown tick 720 from the fresh pre-inhibit sample; it records a one-tick staging code that the
#     endpoint consumes, so a refused kernel tick commits neither the decision nor its event;
#   advance(race, piece, physical_events, course, rules, context)  in the endpoint: countdown progress, gate crossings
#     of the accepted path piece, terminal adjudication and ONE ordered event list (physical and race events).
# No state outside the arguments, no clock other than the supplied times, no randomness.
#
# Accepted-path policy `openrc-chord-path-v1`: the plant integrates each 1/240 s tick with one RK4 step and publishes
# only accepted endpoints, so the accepted piece of a tick is the straight chord between the previous and the candidate
# accepted CG positions, valid only when the endpoint did not jump (no legacy body filter, no endpoint body correction).
# Its in-plane uncertainty is eps = A·dt²/8 with the declared envelope A = 250 m/s² (about 0.54 mm at 240 Hz). A chord
# whose measured velocity change implies more than A is unqualified: every crossing on it is unresolved. A crossing with
# normal speed below 1 m/s is unresolved (near grazing). Unresolved crossings never score; they count in a checkpointed
# counter and never abort the attempt. This is declared, bounded evidence for local practice timing, not a proof that
# the true path stayed within the envelope, and not FAI/MultiGP compliance.
extends RefCounted

const Gates := preload("res://sim/race/gate_crossing.gd")

## Aux suffix (float64), offsets relative to the suffix start.
const AUX_SIZE := 9
const A_GO_TIME := 0
const A_LAP_START := 1
const A_LAP_DURATION := 2 # three slots: lap 1..3 durations (s), zero until the lap is completed
const A_LAST_GATE_TIME := 5
const A_ATTEMPT_START := 6
const A_FINISH_TIME := 7
## The reserved slot pins the course: the first 52 bits of the course identity as an exact float64. The validator
## refuses a frame (reset, restore, step) whose tag differs from the installed course.
const A_COURSE_TAG := 8
const LAP_SLOTS := 3

## Modes suffix (int64), offsets relative to the suffix start.
const MODES_SIZE := 10
const D_PHASE := 0
const D_COUNTDOWN := 1
const D_NEXT_GATE := 2
const D_VALID_LAPS := 3
const D_ATTEMPT := 4
const D_REASON := 5
const D_UNRESOLVED := 6
const D_GATES_TOTAL := 7
const D_EVENT_SEQUENCE := 8
## Reserved slot: a one-tick staging code written by stage() and cleared by advance(); always 0 in accepted frames.
const D_STAGED := 9

const PHASE_IDLE := 0
const PHASE_READY := 1 # declared; v1 evaluates the ready checks inside the start sample and never stores it
const PHASE_COUNTDOWN := 2
const PHASE_RACING := 3
const PHASE_FINISHED := 4
const PHASE_ABORTED := 5
const PHASE_NAMES := ["IDLE", "READY", "COUNTDOWN", "RACING", "FINISHED", "ABORTED"]

const REASON_NONE := 0
const REASON_CRASH := 1
const REASON_DEPLETED := 2
const REASON_GO_THROTTLE := 3
const REASON_GO_SOURCE := 4
const REASON_GO_NOT_ARMED := 5
const REASON_START_NOT_ON_PAD := 6
const REASON_START_MOVING := 7
const REASON_START_TERMINAL := 8
const REASON_CANCELLED := 9
const REASON_NAMES := ["none", "crash", "pack_depleted", "go_refused_throttle", "go_refused_source",
	"go_refused_not_armed", "start_refused_not_on_pad", "start_refused_moving", "start_refused_terminal", "cancelled"]

const ACTION_NONE := 0
const ACTION_START := 1
const ACTION_CANCEL := 2

const STAGED_NONE := 0
const STAGED_START := 1
const STAGED_START_REFUSED := 2
const STAGED_GO := 3
const STAGED_GO_REFUSED := 4
const STAGED_CANCEL_COUNTDOWN := 5
const STAGED_CANCEL_RACE := 6
const STAGED_CLEARED := 7

const TERMINAL_TYPES := ["crash", "pack_depleted"]


static func empty_aux(course_tag: float) -> PackedFloat64Array:
	var aux := PackedFloat64Array()
	aux.resize(AUX_SIZE)
	aux[A_COURSE_TAG] = course_tag
	return aux


static func empty_modes() -> PackedInt64Array:
	var modes := PackedInt64Array()
	modes.resize(MODES_SIZE)
	return modes


## Every attempt slot cleared; the attempt generation and the course tag are kept.
static func _clear(aux: PackedFloat64Array, modes: PackedInt64Array) -> void:
	for i in AUX_SIZE:
		if i != A_COURSE_TAG:
			aux[i] = 0.0
	for i in MODES_SIZE:
		if i != D_ATTEMPT:
			modes[i] = 0


## Sampled staging. race = {aux, modes} of the accepted start-of-tick frame. facts (prepared by the model wrapper):
##   north, east, down, speed_mps          accepted start-of-tick CG position (NED) and world speed
##   terminal                              accepted motor lifecycle is crashed or depleted
##   armed                                 the controller's candidate motor state of THIS sample is armed
##   throttle, collective, arm_low_throttle  fresh pre-inhibit throttle input, the sampled collective, the arm threshold
##   source_ready                          the fresh pilot frame's source is ready
## clock = the kernel's {tick, time_s, dt}. Returns {aux, modes, force_disarm}: force_disarm asks the wrapper to drop the
## controller's arm authorization in this same sample (refused GO).
static func stage(race: Dictionary, action: int, facts: Dictionary, course: Dictionary, rules: Dictionary,
		clock: Dictionary) -> Dictionary:
	var aux: PackedFloat64Array = race.aux.duplicate()
	var modes: PackedInt64Array = race.modes.duplicate()
	modes[D_STAGED] = STAGED_NONE
	var phase: int = modes[D_PHASE]
	var now: float = float(clock.time_s)
	var force_disarm := false
	if action == ACTION_CANCEL:
		if phase == PHASE_READY or phase == PHASE_COUNTDOWN:
			_clear(aux, modes)
			modes[D_REASON] = REASON_CANCELLED
			modes[D_STAGED] = STAGED_CANCEL_COUNTDOWN
		elif phase == PHASE_RACING:
			modes[D_PHASE] = PHASE_ABORTED
			modes[D_REASON] = REASON_CANCELLED
			modes[D_STAGED] = STAGED_CANCEL_RACE
		elif phase == PHASE_FINISHED or phase == PHASE_ABORTED:
			_clear(aux, modes)
			modes[D_STAGED] = STAGED_CLEARED
	elif action == ACTION_START and phase in [PHASE_IDLE, PHASE_FINISHED, PHASE_ABORTED]:
		var reason: int = REASON_NONE
		var pad: Dictionary = course.pad
		var dn: float = float(facts.north) - float(pad.north)
		var de: float = float(facts.east) - float(pad.east)
		if facts.terminal:
			reason = REASON_START_TERMINAL
		elif sqrt(dn * dn + de * de) > float(rules.pad_radius_m) \
				or absf(float(facts.down) - float(pad.down)) > float(rules.pad_rest_height_m):
			reason = REASON_START_NOT_ON_PAD
		elif not (float(facts.speed_mps) < float(rules.pad_rest_speed_mps)):
			reason = REASON_START_MOVING
		_clear(aux, modes)
		if reason != REASON_NONE:
			modes[D_REASON] = reason
			modes[D_STAGED] = STAGED_START_REFUSED
		else:
			modes[D_ATTEMPT] = modes[D_ATTEMPT] + 1
			modes[D_PHASE] = PHASE_COUNTDOWN
			aux[A_ATTEMPT_START] = now
			modes[D_STAGED] = STAGED_START
	elif phase == PHASE_COUNTDOWN and modes[D_COUNTDOWN] >= int(rules.countdown_ticks):
		var reason: int = REASON_NONE
		if not facts.source_ready:
			reason = REASON_GO_SOURCE
		elif not facts.armed:
			reason = REASON_GO_NOT_ARMED
		elif not (float(facts.throttle) <= float(facts.arm_low_throttle)) \
				or not (float(facts.collective) <= float(facts.arm_low_throttle)):
			reason = REASON_GO_THROTTLE
		if reason == REASON_NONE:
			modes[D_PHASE] = PHASE_RACING
			modes[D_COUNTDOWN] = 0
			modes[D_NEXT_GATE] = 0
			aux[A_GO_TIME] = now
			aux[A_LAP_START] = now
			modes[D_STAGED] = STAGED_GO
		else:
			_clear(aux, modes)
			modes[D_REASON] = reason
			modes[D_STAGED] = STAGED_GO_REFUSED
			force_disarm = true
	return {aux = aux, modes = modes, force_disarm = force_disarm}


## Endpoint adjudication. race = {aux, modes}: the staged candidate suffix of this tick. piece = {p0, t0, p1, t1,
## qualified}: the accepted CG chord of this tick (NED, s). physical_events: the physical endpoint's events of this tick
## (crash / pack_depleted carry their time_s). context: the kernel endpoint context (tick is the accepted tick number).
## Returns {aux_suffix, modes_suffix, events}: events are the physical events and the race events in one list sorted by
## time; at equal times physical events come first, race events keep their adjudication order.
static func advance(race: Dictionary, piece: Dictionary, physical_events: Array, course: Dictionary, rules: Dictionary,
		context: Dictionary) -> Dictionary:
	var aux: PackedFloat64Array = race.aux.duplicate()
	var modes: PackedInt64Array = race.modes.duplicate()
	var t0: float = float(piece.t0)
	var t1: float = float(piece.t1)
	var raised: Array = [] # race events in adjudication order
	var staged: int = modes[D_STAGED]
	modes[D_STAGED] = STAGED_NONE
	match staged:
		STAGED_START:
			raised.append({type = "race_countdown", time_s = t0, countdown_ticks = int(rules.countdown_ticks)})
		STAGED_START_REFUSED, STAGED_GO_REFUSED:
			raised.append({type = "race_refused", time_s = t0, stage = "start" if staged == STAGED_START_REFUSED else "go",
				reason = REASON_NAMES[modes[D_REASON]], reason_code = int(modes[D_REASON])})
		STAGED_GO:
			raised.append({type = "race_go", time_s = clampf(aux[A_GO_TIME], t0, t1)})
		STAGED_CANCEL_COUNTDOWN:
			raised.append({type = "race_cancelled", time_s = t0})
		STAGED_CANCEL_RACE:
			raised.append({type = "race_abort", time_s = t0, reason = REASON_NAMES[REASON_CANCELLED],
				reason_code = REASON_CANCELLED, lap = int(modes[D_VALID_LAPS]) + 1})
	var terminals: Array = []
	for event: Variant in physical_events:
		if typeof(event) == TYPE_DICTIONARY and str(event.get("type", "")) in TERMINAL_TYPES:
			terminals.append({time_s = float(event.time_s), kind = 0, gate = -1, seq = terminals.size(),
				code = REASON_CRASH if str(event.type) == "crash" else REASON_DEPLETED, detail = str(event.get("reason", ""))})
	var phase: int = modes[D_PHASE]
	if phase == PHASE_COUNTDOWN:
		if terminals.is_empty():
			modes[D_COUNTDOWN] = mini(modes[D_COUNTDOWN] + 1, int(rules.countdown_ticks))
		else:
			terminals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a, b))
			_abort(modes, terminals[0], raised)
	elif phase == PHASE_RACING:
		_score(aux, modes, piece, terminals, course, rules, raised)
	var attempt: int = modes[D_ATTEMPT]
	var tick: int = int(context.get("tick", 0))
	var ordered: Array = []
	for event: Variant in physical_events:
		ordered.append({time_s = float(event.time_s), rank = 0, seq = ordered.size(), event = event.duplicate(true)})
	for index: int in raised.size():
		var event: Dictionary = raised[index]
		event.attempt = attempt
		event.event_id = "race-%d-%d-%d" % [attempt, tick, index]
		ordered.append({time_s = float(event.time_s), rank = 1, seq = ordered.size(), event = event})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.time_s != b.time_s:
			return a.time_s < b.time_s
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.seq < b.seq)
	var events: Array = []
	for item: Dictionary in ordered:
		events.append(item.event)
	modes[D_EVENT_SEQUENCE] = modes[D_EVENT_SEQUENCE] + raised.size()
	return {aux_suffix = aux, modes_suffix = modes, events = events}


## Strict total order of candidate items: time, then terminal before crossing, then gate index, then sequence.
static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.time_s != b.time_s:
		return a.time_s < b.time_s
	if a.kind != b.kind:
		return a.kind < b.kind
	if a.gate != b.gate:
		return a.gate < b.gate
	return a.seq < b.seq


static func _abort(modes: PackedInt64Array, terminal: Dictionary, raised: Array) -> void:
	modes[D_PHASE] = PHASE_ABORTED
	modes[D_COUNTDOWN] = 0
	modes[D_REASON] = int(terminal.code)
	raised.append({type = "race_abort", time_s = float(terminal.time_s), reason = REASON_NAMES[int(terminal.code)],
		reason_code = int(terminal.code), detail = str(terminal.detail), lap = int(modes[D_VALID_LAPS]) + 1})


## RACING: candidate crossings of every gate on the chord plus the terminal events, sorted, grouped by the tie window
## anchored at each group's earliest item. A terminal in a group suppresses that group's crossings and every later one.
static func _score(aux: PackedFloat64Array, modes: PackedInt64Array, piece: Dictionary, terminals: Array,
		course: Dictionary, rules: Dictionary, raised: Array) -> void:
	var t0: float = float(piece.t0)
	var t1: float = float(piece.t1)
	var epsilon: float = Gates.chord_bound_m(float(rules.acceleration_envelope_mps2), t1 - t0)
	var items: Array = terminals.duplicate(true)
	var gates: Array = course.gates
	for index: int in gates.size():
		var found: Dictionary = Gates.crossing(gates[index], piece.p0, t0, piece.p1, t1, epsilon)
		if not found.crossed or not found.direction_ok:
			continue
		var status: String = found.status
		if not piece.qualified or not (float(found.normal_speed_mps) >= float(rules.min_normal_speed_mps)):
			status = Gates.STATUS_UNRESOLVED
		items.append({time_s = float(found.time_s), kind = 1, gate = index, seq = items.size(), status = status,
			u_m = float(found.u_m), v_m = float(found.v_m)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _before(a, b))
	var tie: float = float(rules.tie_window_s)
	var laps: int = int(course.laps)
	var start := 0
	while start < items.size() and modes[D_PHASE] == PHASE_RACING:
		var anchor: float = float(items[start].time_s)
		var stop: int = start
		var terminal: Dictionary = {}
		while stop < items.size() and float(items[stop].time_s) - anchor <= tie:
			if items[stop].kind == 0 and terminal.is_empty():
				terminal = items[stop]
			stop += 1
		if not terminal.is_empty():
			_abort(modes, terminal, raised)
			return
		for i in range(start, stop):
			var item: Dictionary = items[i]
			if modes[D_PHASE] != PHASE_RACING or item.gate != modes[D_NEXT_GATE]:
				continue
			if item.status == Gates.STATUS_UNRESOLVED:
				modes[D_UNRESOLVED] = modes[D_UNRESOLVED] + 1
				continue
			if item.status != Gates.STATUS_INSIDE:
				continue
			var time_s: float = float(item.time_s)
			var lap: int = modes[D_VALID_LAPS] + 1
			modes[D_GATES_TOTAL] = modes[D_GATES_TOTAL] + 1
			aux[A_LAST_GATE_TIME] = time_s
			raised.append({type = "race_gate", time_s = time_s, gate = int(item.gate), gate_id = str(gates[item.gate].id),
				lap = lap, u_m = float(item.u_m), v_m = float(item.v_m)})
			if item.gate == gates.size() - 1:
				var duration: float = time_s - aux[A_LAP_START]
				aux[A_LAP_DURATION + lap - 1] = duration
				modes[D_VALID_LAPS] = lap
				modes[D_NEXT_GATE] = 0
				aux[A_LAP_START] = time_s
				raised.append({type = "race_lap", time_s = time_s, lap = lap, duration_s = duration})
				if lap == laps:
					modes[D_PHASE] = PHASE_FINISHED
					aux[A_FINISH_TIME] = time_s
					raised.append({type = "race_finish", time_s = time_s, laps = lap, total_s = time_s - aux[A_GO_TIME],
						lap_durations_s = aux.slice(A_LAP_DURATION, A_LAP_DURATION + LAP_SLOTS)})
			else:
				modes[D_NEXT_GATE] = modes[D_NEXT_GATE] + 1
		start = stop


## Race-domain validation of an accepted frame's suffix against the installed course at the validated clock time.
static func validate(aux: PackedFloat64Array, modes: PackedInt64Array, course: Dictionary, rules: Dictionary,
		time_s: float) -> bool:
	if aux.size() != AUX_SIZE or modes.size() != MODES_SIZE or not is_finite(time_s):
		return false
	if aux[A_COURSE_TAG] != float(course.tag):
		return false
	for i in AUX_SIZE:
		if not is_finite(aux[i]) or aux[i] < 0.0:
			return false
	var phase: int = modes[D_PHASE]
	var countdown: int = modes[D_COUNTDOWN]
	var next_gate: int = modes[D_NEXT_GATE]
	var valid_laps: int = modes[D_VALID_LAPS]
	var laps: int = int(course.laps)
	var gate_count: int = int(course.gate_count)
	if phase < PHASE_IDLE or phase > PHASE_ABORTED or countdown < 0 or countdown > int(rules.countdown_ticks) \
			or next_gate < 0 or next_gate >= gate_count or valid_laps < 0 or valid_laps > laps or laps > LAP_SLOTS \
			or modes[D_ATTEMPT] < 0 or modes[D_REASON] < REASON_NONE or modes[D_REASON] > REASON_CANCELLED \
			or modes[D_UNRESOLVED] < 0 or modes[D_EVENT_SEQUENCE] < 0 or modes[D_STAGED] != STAGED_NONE:
		return false
	if (phase == PHASE_FINISHED) != (valid_laps == laps):
		return false
	if countdown != 0 and phase != PHASE_COUNTDOWN:
		return false
	if modes[D_GATES_TOTAL] != valid_laps * gate_count + next_gate:
		return false
	if phase != PHASE_IDLE and modes[D_ATTEMPT] < 1:
		return false
	for i in LAP_SLOTS:
		if i >= valid_laps and aux[A_LAP_DURATION + i] != 0.0:
			return false
	var times: Array = [aux[A_GO_TIME], aux[A_LAP_START], aux[A_LAST_GATE_TIME], aux[A_ATTEMPT_START], aux[A_FINISH_TIME]]
	for value: float in times:
		if value > time_s:
			return false
	if phase in [PHASE_IDLE, PHASE_READY, PHASE_COUNTDOWN]:
		if valid_laps != 0 or next_gate != 0 or aux[A_GO_TIME] != 0.0 or aux[A_LAP_START] != 0.0 \
				or aux[A_LAST_GATE_TIME] != 0.0 or aux[A_FINISH_TIME] != 0.0 or modes[D_UNRESOLVED] != 0:
			return false
	if phase == PHASE_IDLE and aux[A_ATTEMPT_START] != 0.0:
		return false
	if phase in [PHASE_RACING, PHASE_FINISHED] and aux[A_LAP_START] < aux[A_GO_TIME]:
		return false
	if (aux[A_FINISH_TIME] != 0.0 and phase != PHASE_FINISHED) or (phase == PHASE_FINISHED and aux[A_FINISH_TIME] < aux[A_GO_TIME]):
		return false
	return true
