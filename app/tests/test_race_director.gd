# DR-25/DR-26 RACE-07, RACE-08, RACE-12, RACE-13 on synthetic accepted pieces (no kernel): the pure race director of
# `openrc-local-race-v1` over a square course of four upright gates — ordered laps with exact times, two gates in one
# piece, out-of-order and wrong-way crossings, missed-gate return, crash/crossing tie adjudication within 1 µs,
# unresolved evidence, exactly three laps, a new attempt and determinism. Local practice rules; no federation claims.
extends SceneTree

const Track := preload("res://sim/race/track.gd")
const Director := preload("res://sim/race/race_director.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")

const DT := 1.0 / 240.0

var _count := 0
var _failures := 0
var _course: Dictionary
var _rules: Dictionary


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


static func square_document() -> Dictionary:
	return {format = Track.FORMAT, id = "synthetic-square", name = "Synthetic square", field_id = "synthetic",
		ruleset = Track.RULESET, laps = 3, origin = "pilot", pad = {north_m = -10.0, east_m = -6.0, heading_deg = 90.0},
		gates = [
			{id = "s", north_m = -10.0, east_m = 0.0, center_height_m = 2.0, heading_deg = 90.0, width_m = 3.0, height_m = 2.0},
			{id = "e", north_m = 0.0, east_m = 10.0, center_height_m = 2.0, heading_deg = 0.0, width_m = 3.0, height_m = 2.0},
			{id = "n", north_m = 10.0, east_m = 0.0, center_height_m = 2.0, heading_deg = 270.0, width_m = 3.0, height_m = 2.0},
			{id = "w", north_m = 0.0, east_m = -10.0, center_height_m = 2.0, heading_deg = 180.0, width_m = 3.0, height_m = 2.0}]}


static func synthetic_field() -> Dictionary:
	return {id = "synthetic", pilot = {north = 0.0, east = 0.0, down = 0.0, eye_height = 1.7},
		surfaces = [{id = "flat", type = "rough", center_north = 0.0, center_east = 0.0, length_east_west = 1000.0,
			width_north_south = 1000.0}], objects = []}


func _run() -> void:
	var flat := func(_n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	var loaded: Dictionary = Track.load_document(square_document(), "square")
	var prepared: Dictionary = Track.prepare(loaded.track, synthetic_field(), flat) if loaded.ok else {ok = false, errors = loaded.errors}
	_check("the synthetic square course loads and prepares", prepared.ok, str(prepared.get("errors", "")))
	if not prepared.ok:
		quit(1)
		return
	_course = prepared.course
	_rules = Track.ruleset()
	_ordered_laps()
	_two_in_one_piece()
	_order_and_direction()
	_missed_gate_return()
	_crash_ties()
	_unresolved()
	_new_attempt_and_go()
	_determinism()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _racing(go_s: float) -> Dictionary:
	var aux: PackedFloat64Array = Director.empty_aux(float(_course.tag))
	aux[Director.A_GO_TIME] = go_s
	aux[Director.A_LAP_START] = go_s
	var modes: PackedInt64Array = Director.empty_modes()
	modes[Director.D_PHASE] = Director.PHASE_RACING
	modes[Director.D_ATTEMPT] = 1
	return {aux = aux, modes = modes}


## A straight piece of one tick through gate `index` along its normal (reverse: against it), offset across the aperture.
func _through(index: int, tick: int, length := 0.1, offset_u := 0.0, reverse := false, qualified := true) -> Dictionary:
	var gate: Dictionary = _course.gates[index]
	var c: PackedFloat64Array = gate.c
	var a := PackedFloat64Array()
	var b := PackedFloat64Array()
	for i in 3:
		a.append(c[i] + offset_u * gate.u[i] - 0.5 * length * gate.n[i])
		b.append(c[i] + offset_u * gate.u[i] + 0.5 * length * gate.n[i])
	var t0: float = float(tick) * DT
	return {p0 = b if reverse else a, t0 = t0, p1 = a if reverse else b, t1 = t0 + DT, qualified = qualified}


func _still(tick: int) -> Dictionary:
	var p := PackedFloat64Array([-10.0, -6.0, 0.0])
	return {p0 = p, t0 = float(tick) * DT, p1 = p.duplicate(), t1 = float(tick + 1) * DT, qualified = true}


func _advance(race: Dictionary, piece: Dictionary, physical: Array = []) -> Dictionary:
	var out: Dictionary = Director.advance(race, piece, physical, _course, _rules, {tick = int(round(piece.t1 / DT))})
	out.race = {aux = out.aux_suffix, modes = out.modes_suffix}
	out.valid = Director.validate(out.aux_suffix, out.modes_suffix, _course, _rules, piece.t1)
	return out


func _types(events: Array) -> String:
	var names := PackedStringArray()
	for event: Dictionary in events:
		names.append(str(event.type))
	return ",".join(names)


func _ordered_laps() -> void:
	var race: Dictionary = _racing(3.0)
	var crossing_times: Array = []
	var all_valid := true
	var gate_events := 0
	var times_exact := true
	var finished_early := false
	var finish_event: Dictionary = {}
	for i in 12:
		var tick: int = 800 + 100 * i
		var out: Dictionary = _advance(race, _through(i % 4, tick))
		race = out.race
		all_valid = all_valid and out.valid
		var expected: float = float(tick) * DT + 0.5 * DT
		crossing_times.append(expected)
		for event: Dictionary in out.events:
			if event.type == "race_gate":
				gate_events += 1
				times_exact = times_exact and absf(event.time_s - expected) < 1e-12 and event.gate == i % 4 \
					and event.lap == floori(i / 4.0) + 1
			elif event.type == "race_finish":
				finish_event = event
		if i < 11 and race.modes[Director.D_PHASE] != Director.PHASE_RACING:
			finished_early = true
	var aux: PackedFloat64Array = race.aux
	var modes: PackedInt64Array = race.modes
	var lap1: float = crossing_times[3] - 3.0
	var lap2: float = crossing_times[7] - crossing_times[3]
	var lap3: float = crossing_times[11] - crossing_times[7]
	_check("RACE-07 twelve ordered crossings score twelve gates at the exact chord times, laps numbered 1..3",
		gate_events == 12 and times_exact and all_valid)
	_check("RACE-07 lap durations: first from GO, then from the previous finish crossing", absf(aux[Director.A_LAP_DURATION] - lap1) < 1e-12
		and absf(aux[Director.A_LAP_DURATION + 1] - lap2) < 1e-12 and absf(aux[Director.A_LAP_DURATION + 2] - lap3) < 1e-12,
		"%.9f %.9f %.9f" % [aux[Director.A_LAP_DURATION], aux[Director.A_LAP_DURATION + 1], aux[Director.A_LAP_DURATION + 2]])
	_check("finish after exactly three laps and not before", not finished_early and modes[Director.D_PHASE] == Director.PHASE_FINISHED
		and modes[Director.D_VALID_LAPS] == 3 and not finish_event.is_empty() and absf(finish_event.total_s - (crossing_times[11] - 3.0)) < 1e-12
		and absf(aux[Director.A_FINISH_TIME] - crossing_times[11]) < 1e-12)
	var after: Dictionary = _advance(race, _through(0, 2100))
	_check("a finished attempt ignores further crossings", after.events.is_empty() and after.race.modes == race.modes
		and after.race.aux == race.aux and after.valid)


func _two_in_one_piece() -> void:
	var race: Dictionary = _racing(3.0)
	var piece := {p0 = PackedFloat64Array([-10.2, -1.0, -2.0]), t0 = 1000.0 * DT, p1 = PackedFloat64Array([1.0, 10.5, -2.0]),
		t1 = 1001.0 * DT, qualified = true}
	var out: Dictionary = _advance(race, piece)
	var gates: Array = []
	var times: Array = []
	for event: Dictionary in out.events:
		if event.type == "race_gate":
			gates.append(event.gate)
			times.append(event.time_s)
	_check("RACE-07 two successive gates crossed in one piece advance twice, in time order", gates == [0, 1]
		and times[0] < times[1] and out.race.modes[Director.D_NEXT_GATE] == 2 and out.valid, _types(out.events))
	var ids := {}
	for event: Dictionary in out.events:
		ids[event.event_id] = true
	_check("race event ids are unique within the tick and carry the attempt and tick", ids.size() == out.events.size()
		and str(out.events[0].event_id) == "race-1-1001-0")


func _order_and_direction() -> void:
	var race: Dictionary = _racing(3.0)
	var skipped: Dictionary = _advance(race, _through(1, 900))
	var backwards: Dictionary = _advance(race, _through(0, 900, 0.1, 0.0, true))
	var outside: Dictionary = _advance(race, _through(0, 900, 0.1, 1.6))
	var edge: Dictionary = _advance(race, _through(0, 900, 0.1, 1.5))
	_check("RACE-12 an out-of-order crossing has no progress effect", skipped.events.is_empty()
		and skipped.race.modes[Director.D_NEXT_GATE] == 0)
	_check("RACE-12 a wrong-way crossing of the required gate does not score", backwards.events.is_empty()
		and backwards.race.modes[Director.D_NEXT_GATE] == 0 and backwards.race.modes[Director.D_UNRESOLVED] == 0)
	_check("an outside crossing neither scores nor counts as unresolved", outside.events.is_empty()
		and outside.race.modes[Director.D_NEXT_GATE] == 0 and outside.race.modes[Director.D_UNRESOLVED] == 0)
	_check("an exact-edge crossing never scores: inside the declared chord band it is unresolved", edge.events.is_empty()
		and edge.race.modes[Director.D_NEXT_GATE] == 0 and edge.race.modes[Director.D_UNRESOLVED] == 1)


func _missed_gate_return() -> void:
	var race: Dictionary = _racing(3.0)
	race = _advance(race, _through(0, 800)).race
	var missed: Dictionary = _advance(race, _through(2, 900))
	var returned: Dictionary = _advance(missed.race, _through(1, 1000))
	var onward: Dictionary = _advance(returned.race, _through(2, 1100))
	_check("RACE-12 a missed gate, then the correct return, continues the lap", missed.events.is_empty()
		and missed.race.modes[Director.D_NEXT_GATE] == 1 and returned.race.modes[Director.D_NEXT_GATE] == 2
		and onward.race.modes[Director.D_NEXT_GATE] == 3 and onward.race.modes[Director.D_VALID_LAPS] == 0
		and onward.race.modes[Director.D_GATES_TOTAL] == 3 and onward.valid)


## RACING at gate 3 of lap 2 with lap 1 completed in 10 s.
func _lap_two_at_finish_gate() -> Dictionary:
	var race: Dictionary = _racing(3.0)
	race.aux[Director.A_LAP_DURATION] = 10.0
	race.aux[Director.A_LAP_START] = 13.0
	race.aux[Director.A_LAST_GATE_TIME] = 13.0
	race.modes[Director.D_VALID_LAPS] = 1
	race.modes[Director.D_NEXT_GATE] = 3
	race.modes[Director.D_GATES_TOTAL] = 7
	return race


func _crash_ties() -> void:
	var tick := 5000
	var crossing: float = float(tick) * DT + 0.5 * DT
	var base: Dictionary = _lap_two_at_finish_gate()
	_check("the crash fixture state is valid", Director.validate(base.aux, base.modes, _course, _rules, float(tick) * DT))
	var cases := {"crash 2 us before": -2.0e-6, "crash 2 us after": 2.0e-6, "crash 0.5 us after": 0.5e-6,
		"crash 0.5 us before": -0.5e-6}
	var results := {}
	for label: String in cases:
		var crash := {type = "crash", time_s = crossing + float(cases[label]), reason = "Hard impact"}
		results[label] = _advance(base, _through(3, tick), [crash])
	var before: Dictionary = results["crash 2 us before"]
	_check("RACE-08 a crash earlier than the crossing by more than 1 us suppresses it; the attempt aborts, slots retained",
		_types(before.events) == "crash,race_abort" and before.race.modes[Director.D_PHASE] == Director.PHASE_ABORTED
		and before.race.modes[Director.D_REASON] == Director.REASON_CRASH and before.race.modes[Director.D_VALID_LAPS] == 1
		and before.race.aux[Director.A_LAP_DURATION] == 10.0 and before.valid, _types(before.events))
	var after: Dictionary = results["crash 2 us after"]
	_check("RACE-08/13 a crossing earlier than the crash by more than 1 us completes lap 2, then the attempt aborts",
		_types(after.events) == "race_gate,race_lap,crash,race_abort" and after.race.modes[Director.D_PHASE] == Director.PHASE_ABORTED
		and after.race.modes[Director.D_VALID_LAPS] == 2 and after.race.aux[Director.A_LAP_DURATION] == 10.0
		and absf(after.race.aux[Director.A_LAP_DURATION + 1] - (crossing - 13.0)) < 1e-12 and after.valid, _types(after.events))
	var tie_after: Dictionary = results["crash 0.5 us after"]
	var tie_before: Dictionary = results["crash 0.5 us before"]
	_check("RACE-08 a crash within 1 us of the crossing wins on either side and suppresses it",
		_types(tie_after.events) == "crash,race_abort" and _types(tie_before.events) == "crash,race_abort"
		and tie_after.race.modes[Director.D_VALID_LAPS] == 1 and tie_before.race.modes[Director.D_VALID_LAPS] == 1
		and tie_after.race.modes[Director.D_GATES_TOTAL] == 7)
	var abort_event: Dictionary = after.events[3]
	_check("the abort event carries the physical time, reason and current lap", abort_event.time_s == crossing + 2.0e-6
		and abort_event.reason == "crash" and abort_event.detail == "Hard impact" and abort_event.lap == 3)
	var depleted: Dictionary = _advance(base, _still(tick), [{type = "pack_depleted", time_s = float(tick + 1) * DT}])
	_check("RACE-13 pack depletion during the race aborts with its reason", depleted.race.modes[Director.D_PHASE] == Director.PHASE_ABORTED
		and depleted.race.modes[Director.D_REASON] == Director.REASON_DEPLETED and depleted.valid)
	var countdown := {aux = Director.empty_aux(float(_course.tag)), modes = Director.empty_modes()}
	countdown.modes[Director.D_PHASE] = Director.PHASE_COUNTDOWN
	countdown.modes[Director.D_COUNTDOWN] = 300
	countdown.modes[Director.D_ATTEMPT] = 1
	var crashed_in_countdown: Dictionary = _advance(countdown, _still(tick), [{type = "crash", time_s = float(tick + 1) * DT, reason = "Hard impact"}])
	_check("a terminal event during the countdown aborts the attempt", crashed_in_countdown.race.modes[Director.D_PHASE] == Director.PHASE_ABORTED
		and crashed_in_countdown.race.modes[Director.D_COUNTDOWN] == 0 and crashed_in_countdown.valid)


func _unresolved() -> void:
	var race: Dictionary = _racing(3.0)
	var unqualified: Dictionary = _advance(race, _through(0, 900, 0.1, 0.0, false, false))
	var grazing: Dictionary = _advance(race, _through(0, 900, 0.5 * DT))
	var epsilon: float = Gates.chord_bound_m(float(_rules.acceleration_envelope_mps2), DT)
	var banded: Dictionary = _advance(race, _through(0, 900, 0.1, 1.5 - 0.5 * epsilon))
	var clear: Dictionary = _advance(race, _through(0, 900, 0.1, 1.5 - 2.0 * epsilon))
	_check("RACE-06/10 a crossing on an unqualified chord is unresolved: no progress, the counter increments",
		unqualified.events.is_empty() and unqualified.race.modes[Director.D_NEXT_GATE] == 0
		and unqualified.race.modes[Director.D_UNRESOLVED] == 1 and unqualified.valid)
	_check("RACE-06 a crossing below 1 m/s normal speed is unresolved", grazing.events.is_empty()
		and grazing.race.modes[Director.D_UNRESOLVED] == 1)
	_check("RACE-06 a crossing within the declared chord band of an edge is unresolved; 2 eps inside scores",
		banded.race.modes[Director.D_UNRESOLVED] == 1 and banded.race.modes[Director.D_NEXT_GATE] == 0
		and clear.race.modes[Director.D_NEXT_GATE] == 1, "eps %.6f m" % epsilon)
	_check("an unresolved crossing does not abort the attempt", unqualified.race.modes[Director.D_PHASE] == Director.PHASE_RACING)


func _facts(armed := true, throttle := 0.0, ready := true) -> Dictionary:
	return {north = -10.0, east = -6.0, down = -0.018, speed_mps = 0.0, terminal = false, armed = armed, throttle = throttle,
		collective = throttle, arm_low_throttle = 0.05, source_ready = ready}


func _new_attempt_and_go() -> void:
	var race: Dictionary = _racing(3.0)
	for i in 12:
		race = _advance(race, _through(i % 4, 800 + 100 * i)).race
	var clock := {tick = 3000, time_s = 3000.0 * DT, dt = DT}
	var staged: Dictionary = Director.stage(race, Director.ACTION_START, _facts(), _course, _rules, clock)
	var cleared := true
	for i in Director.AUX_SIZE:
		if i != Director.A_COURSE_TAG and i != Director.A_ATTEMPT_START:
			cleared = cleared and staged.aux[i] == 0.0
	_check("RACE-13 a new start request clears every slot and increments the attempt generation", cleared
		and staged.modes[Director.D_ATTEMPT] == 2 and staged.modes[Director.D_PHASE] == Director.PHASE_COUNTDOWN
		and staged.modes[Director.D_VALID_LAPS] == 0 and staged.modes[Director.D_GATES_TOTAL] == 0
		and staged.aux[Director.A_ATTEMPT_START] == clock.time_s and not staged.force_disarm)
	var started: Dictionary = _advance(staged, _still(3000))
	_check("the endpoint commits the staged start: countdown 1, staging cleared, one race_countdown event",
		started.race.modes[Director.D_COUNTDOWN] == 1 and started.race.modes[Director.D_STAGED] == 0
		and _types(started.events) == "race_countdown" and started.valid)
	var far: Dictionary = _facts()
	far.east = 0.0
	var refused: Dictionary = Director.stage(race, Director.ACTION_START, far, _course, _rules, clock)
	_check("a start off the pad is refused with its reason and leaves the terminal phase", refused.modes[Director.D_PHASE] == Director.PHASE_IDLE
		and refused.modes[Director.D_REASON] == Director.REASON_START_NOT_ON_PAD and refused.modes[Director.D_ATTEMPT] == 1)
	var at_go: Dictionary = started.race.duplicate(true)
	at_go.modes[Director.D_COUNTDOWN] = 720
	var go_clock := {tick = 3720, time_s = 3720.0 * DT, dt = DT}
	var granted: Dictionary = Director.stage(at_go, Director.ACTION_NONE, _facts(), _course, _rules, go_clock)
	var go: Dictionary = _advance({aux = granted.aux, modes = granted.modes}, _still(3720))
	_check("GO at countdown 720 with armed motors, low throttle and a ready source: RACING from the start of the interval",
		granted.modes[Director.D_PHASE] == Director.PHASE_RACING and granted.aux[Director.A_GO_TIME] == go_clock.time_s
		and granted.aux[Director.A_LAP_START] == go_clock.time_s and _types(go.events) == "race_go"
		and go.events[0].time_s == go_clock.time_s and go.valid)
	var reasons := []
	for facts: Dictionary in [_facts(true, 0.3), _facts(true, 0.0, false), _facts(false, 0.0)]:
		var no_go: Dictionary = Director.stage(at_go, Director.ACTION_NONE, facts, _course, _rules, go_clock)
		reasons.append([no_go.modes[Director.D_PHASE], no_go.modes[Director.D_REASON], no_go.force_disarm])
	_check("refused GO: throttle, source and arm reasons; back to IDLE with the arm authorization dropped",
		reasons == [[0, 3, true], [0, 4, true], [0, 5, true]], str(reasons))
	var early: Dictionary = started.race.duplicate(true)
	early.modes[Director.D_COUNTDOWN] = 719
	var not_yet: Dictionary = Director.stage(early, Director.ACTION_NONE, _facts(), _course, _rules, go_clock)
	_check("no GO decision before countdown tick 720", not_yet.modes[Director.D_PHASE] == Director.PHASE_COUNTDOWN
		and not_yet.modes[Director.D_STAGED] == 0)


func _determinism() -> void:
	var runs: Array = []
	for _run_index in 2:
		var race: Dictionary = _racing(3.0)
		var record: Array = []
		for i in 14:
			var crash: Array = [] if i != 13 else [{type = "crash", time_s = float(800 + 100 * i) * DT + 0.25 * DT, reason = "x"}]
			var out: Dictionary = _advance(race, _through(i % 4, 800 + 100 * i, 0.1, 0.01 * float(i % 3)), crash)
			race = out.race
			record.append([out.aux_suffix, out.modes_suffix, out.events])
		runs.append(var_to_bytes(record))
	_check("determinism: the same inputs give the same bytes", runs[0] == runs[1] and runs[0].size() > 1000)
