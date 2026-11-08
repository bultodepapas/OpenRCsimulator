extends SceneTree

const ContactStep := preload("res://sim/electric_contact_step.gd")
const BatteryStep := preload("res://physics/electric_battery_step.gd")
const RPM := 13
const CHARGE := 14
const SIZE := 17
var checks := 0
var failures := 0
var sample_times: Array[float] = []
var fail_after := INF

func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func state(rpm: float, charge: float) -> PackedFloat64Array:
	var s := PackedFloat64Array()
	s.resize(SIZE)
	s[6] = 1.0
	s[RPM] = rpm
	s[CHARGE] = charge
	return s

func rate(s: PackedFloat64Array, at: float) -> PackedFloat64Array:
	sample_times.append(at)
	var result := PackedFloat64Array()
	result.resize(SIZE)
	if at > fail_after:
		result[0] = NAN
		return result
	if s[CHARGE] != 0.0:
		result[CHARGE] = -1.0
		result[15] = 12.0
	if s[RPM] != 0.0: result[RPM] = -100.0
	return result

func project(s: PackedFloat64Array, index: int) -> PackedFloat64Array:
	var out := s.duplicate()
	out[index] = 0.0
	return out

func _initialize() -> void:
	var initial := state(1000.0, 10.0)
	var first := rate(initial, 2.0)
	sample_times.clear()
	var direct := BatteryStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project)
	var one := ContactStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project, 1)
	check("one-piece output is byte-identical", direct.ok and one.ok and var_to_bytes(direct) == var_to_bytes(one))
	sample_times.clear()
	var split := ContactStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project, 2)
	check("two pieces succeed", split.ok, str(split))
	check("supplied first derivative is reused only at first boundary", not sample_times.has(2.0) and sample_times.count(2.5) >= 2, str(sample_times))
	check("two-piece linear state is exact", split.ok and absf(split.state[RPM] - 900.0) < 1e-9 and absf(split.state[CHARGE] - 9.0) < 1e-9)
	var shared := ContactStep.advance(state(100.0, 1.0), 4.0, 2.0, rate, PackedFloat64Array(), RPM, CHARGE, project, 2)
	check("boundary rotor and battery events remain single and ordered", shared.ok and shared.events.size() == 2 and shared.events[0].type == "rotor_stop" and shared.events[1].type == "battery_exhausted", str(shared))
	if shared.ok and shared.events.size() == 2:
		check("simultaneous boundary events keep the same absolute timestamp", absf(float(shared.events[0].time_s) - 5.0) < 1e-10 and shared.events[0].time_s == shared.events[1].time_s)
	var crossed := ContactStep.advance(state(150.0, 0.5), 4.0, 2.0, rate, PackedFloat64Array(), RPM, CHARGE, project, 2)
	check("distinct events straddling pieces are chronological", crossed.ok and crossed.events.size() == 2 and crossed.events[0].type == "battery_exhausted" and crossed.events[1].type == "rotor_stop" and absf(float(crossed.events[0].time_s) - 4.5) < 1e-10 and absf(float(crossed.events[1].time_s) - 5.5) < 1e-10, str(crossed))
	var late := ContactStep.advance(state(0.0, 1.0 / 240.0), 65536.0, 1.0 / 240.0, rate, PackedFloat64Array(), RPM, CHARGE, project, 2)
	check("late-clock endpoint event survives absolute rounding", late.ok and late.events.size() == 1 and late.events[0].type == "battery_exhausted" and absf(float(late.events[0].time_s) - (65536.0 + 1.0 / 240.0)) < 1e-9, str(late))
	var close_start := state(100.0 * (0.001 + 1.4551915228366852e-11), 0.001)
	var close_piece := BatteryStep.advance(close_start, 65536.0, 1.0 / 480.0, rate, PackedFloat64Array(), RPM, CHARGE, project)
	var close_split := ContactStep.advance(close_start, 65536.0, 1.0 / 240.0, rate, PackedFloat64Array(), RPM, CHARGE, project, 2)
	check("late-clock distinct events retain BatteryStep order and timestamps", close_piece.ok and close_piece.events.size() == 2 and close_piece.events[0].type == "battery_exhausted" and close_piece.events[1].type == "rotor_stop" and float(close_piece.events[1].time_s) > float(close_piece.events[0].time_s) and close_split.ok and close_split.events == close_piece.events, str(close_piece) + " / " + str(close_split))
	var joined: Array[Dictionary] = [{"type": "battery_exhausted", "time_s": 65536.0}]
	var rotor := {"type": "rotor_stop", "time_s": 65536.0 - 1.4551915228366852e-11}
	check("rounded cross-piece inversion canonicalizes rotor before battery", ContactStep._append_ordered(joined, rotor, 0, 3e-11) and joined.size() == 2 and joined[0].type == "rotor_stop" and joined[1].type == "battery_exhausted" and joined[0].time_s == joined[1].time_s, str(joined))
	var before := var_to_bytes(initial)
	fail_after = 2.5 + 1e-8
	var failed := ContactStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project, 2)
	check("second-piece failure exposes no partial state or events", not failed.ok and not failed.has("state") and not failed.has("events") and var_to_bytes(initial) == before, str(failed))
	check("invalid piece counts refuse", not ContactStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project, 0).ok and not ContactStep.advance(initial, 2.0, 1.0, rate, first, RPM, CHARGE, project, 17).ok)
	print("ELECTRIC_CONTACT_STEP_TEST %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
