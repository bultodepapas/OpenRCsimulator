## Synthetic point trajectories for the production race director, outside the flight kernel and collision model.
extends SceneTree

const Track := preload("res://sim/race/track.gd")
const Director := preload("res://sim/race/race_director.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")
const Field := preload("res://data/field_loader.gd")
const DT := 1.0 / 240.0
const T0 := 4.0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field: Dictionary = Field.load_from()
	var loaded: Dictionary = Track.load_file("res://data/race/tracks/openrc-practice-oval-1.json")
	if not field.ok or not loaded.ok:
		printerr("Cannot load the stock venue")
		quit(1)
		return
	var flat := func(_north: float, _east: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	var prepared: Dictionary = Track.prepare(loaded.track, field.field, flat)
	if not prepared.ok:
		printerr(prepared.errors)
		quit(1)
		return
	var course: Dictionary = prepared.course
	_case(course, "curved oblique", 2.0, 20.0, 50.0, 0.00075, "inside", true, false, 0)
	_case(course, "same endpoints straight", 2.0, 20.0, 0.0, 0.00075, "inside", true, true, 0)
	_case(course, "zero tangential speed", 2.0, 0.0, 50.0, 0.00075, "inside", true, true, 0)
	_case(course, "farther inside", 2.0, 20.0, 50.0, 0.01, "inside", true, true, 0)
	_case(course, "outside chord, true inside", 2.0, -20.0, 50.0, -0.00075, "outside", false, true, 0)
	_case(course, "below normal threshold", 0.75, 0.0, 0.0, 0.01, "inside", false, true, 1)
	_case(course, "near edge", 2.0, 0.0, 0.0, 0.00025, "unresolved", false, true, 1)
	print("R2_GATE_PROJECTION cases=7 failed=%d" % failed)
	quit(1 if failed else 0)


func _case(course: Dictionary, label: String, vn: float, vu: float, acc: float, margin: float,
		expected_status: String, expected_score: bool, expected_true: bool, expected_unresolved: int) -> void:
	var rules: Dictionary = Track.ruleset()
	var gate: Dictionary = course.gates[0]
	var midpoint_u := float(gate.w) - margin
	var p0 := PackedFloat64Array()
	var p1 := PackedFloat64Array()
	for axis in 3:
		p0.append(gate.c[axis] + gate.n[axis] * (-vn * DT / 2.0) + gate.u[axis] * (midpoint_u - vu * DT / 2.0))
		p1.append(gate.c[axis] + gate.n[axis] * (vn * DT / 2.0) + gate.u[axis] * (midpoint_u + vu * DT / 2.0))
	var v0n := vn - acc * DT / 2.0
	var v1n := vn + acc * DT / 2.0
	var envelope: float = rules.acceleration_envelope_mps2
	var piece := {p0 = p0, p1 = p1, t0 = T0, t1 = T0 + DT, qualified = absf(v1n - v0n) / DT <= envelope}
	var epsilon := Gates.chord_bound_m(envelope, float(piece.t1) - T0)
	var chord: Dictionary = Gates.crossing(gate, p0, T0, p1, piece.t1, epsilon)
	var aux := Director.empty_aux(float(course.tag))
	var modes := Director.empty_modes()
	aux[Director.A_GO_TIME] = 3.0
	aux[Director.A_LAP_START] = 3.0
	modes[Director.D_PHASE] = Director.PHASE_RACING
	modes[Director.D_ATTEMPT] = 1
	var result: Dictionary = Director.advance({aux = aux, modes = modes}, piece, [], course, rules, {tick = 961})
	# Bisection on the actual parabola, independent of the director's chord interpolation.
	var lo := -DT / 2.0
	var hi := DT / 2.0
	for _iteration in 70:
		var t := (lo + hi) / 2.0
		var n := vn * t + 0.5 * acc * (t * t - DT * DT / 4.0)
		if n > 0.0:
			hi = t
		else:
			lo = t
	var root_time := (lo + hi) / 2.0
	var true_u := midpoint_u + vu * root_time
	var true_inside := absf(true_u) < float(gate.w)
	var scored: bool = result.modes_suffix[Director.D_GATES_TOTAL] == 1
	var valid := Director.validate(result.aux_suffix, result.modes_suffix, course, rules, piece.t1)
	var ok: bool = piece.qualified and minf(v0n, v1n) > 0.0 and valid and chord.status == expected_status \
			and scored == expected_score and true_inside == expected_true and result.modes_suffix[Director.D_UNRESOLVED] == expected_unresolved
	if not ok:
		failed += 1
	print("%s ok=%s chord=%s chord_u=%.12f true_u=%.12f score=%s unresolved=%d root_offset_us=%.9f" % [
		label, ok, chord.status, chord.u_m, true_u, scored, result.modes_suffix[Director.D_UNRESOLVED], root_time * 1.0e6])
