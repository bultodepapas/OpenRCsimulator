extends SceneTree

const M = preload("res://physics/math3d.gd")
const Gates = preload("res://sim/race/gate_crossing.gd")
const Track = preload("res://sim/race/track.gd")
const Director = preload("res://sim/race/race_director.gd")
const Fixture = preload("res://tests/test_race_director.gd")

const DT: float = 1.0 / 240.0
var failures: int = 0

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded: Dictionary = Track.load_document(Fixture.square_document(), "A36 R5 unchanged square fixture")
	var flat := func(_n: float, _e: float) -> PackedFloat64Array: return PackedFloat64Array([0.0, 0.0, 0.0])
	var prepared: Dictionary = Track.prepare(loaded.track, Fixture.synthetic_field(), flat) if loaded.ok else {ok = false}
	check("complete synthetic track loads and prepares through production API", loaded.ok and prepared.ok)
	if not prepared.ok:
		quit(1)
		return
	var course: Dictionary = prepared.course
	var rules: Dictionary = Track.ruleset()
	var gate: Dictionary = course.gates[0]
	var a_n: float = 40.0
	var v_n: float = 2.0
	var v_u: float = 40.0
	var y_chord: float = float(gate.w) - 0.001
	var p0: PackedFloat64Array = M.add(gate.c, M.add(M.scale(gate.n, -v_n * DT / 2.0), M.scale(gate.u, y_chord - v_u * DT / 2.0)))
	var p1: PackedFloat64Array = M.add(gate.c, M.add(M.scale(gate.n, v_n * DT / 2.0), M.scale(gate.u, y_chord + v_u * DT / 2.0)))
	var epsilon: float = Gates.chord_bound_m(float(rules.acceleration_envelope_mps2), DT)
	var hit: Dictionary = Gates.crossing(gate, p0, 0.0, p1, DT, epsilon)
	var initial_v_n: float = v_n - a_n * DT / 2.0
	var root: float = v_n * DT / (initial_v_n + sqrt(initial_v_n * initial_v_n + a_n * v_n * DT))
	var actual_u: float = y_chord + v_u * (root - DT / 2.0)
	var curve_residual: float = a_n * DT * DT / 8.0
	check("constant acceleration lies below the declared envelope", a_n < float(rules.acceleration_envelope_mps2))
	check("normal velocity exceeds grazing threshold for the entire interval", initial_v_n > float(rules.min_normal_speed_mps))
	check("the actual curve stays within the same-time chord error bound", curve_residual < epsilon)
	check("production chord test reports inside", hit.status == Gates.STATUS_INSIDE)
	check("analytic curved crossing is outside the strict aperture", actual_u > float(gate.w))
	var aux: PackedFloat64Array = Director.empty_aux(float(course.tag))
	var modes: PackedInt64Array = Director.empty_modes()
	modes[Director.D_PHASE] = Director.PHASE_RACING
	modes[Director.D_ATTEMPT] = 1
	var piece := {p0 = p0, t0 = 0.0, p1 = p1, t1 = DT, qualified = a_n <= float(rules.acceleration_envelope_mps2)}
	var out: Dictionary = Director.advance({aux = aux, modes = modes}, piece, [], course, rules, {tick = 1, time_s = DT, dt = DT})
	check("production director awards one gate for the constructed piece", out.modes_suffix[Director.D_GATES_TOTAL] == 1)
	check("awarded race state passes production suffix validation", Director.validate(out.aux_suffix, out.modes_suffix, course, rules, DT))
	var normal_end: PackedFloat64Array = M.add(gate.c, M.add(M.scale(gate.n, v_n * DT / 2.0), M.scale(gate.u, y_chord)))
	var normal_start: PackedFloat64Array = M.add(gate.c, M.add(M.scale(gate.n, -v_n * DT / 2.0), M.scale(gate.u, y_chord)))
	check("negative control: no tangential speed preserves aperture coordinate", Gates.crossing(gate, normal_start, 0.0, normal_end, DT, epsilon).status == Gates.STATUS_INSIDE)
	var bound_projected: float = epsilon * sqrt(1.0 + v_u * v_u / (v_n * v_n))
	check("projected residual bound marks the witness unresolved", Gates.classify(absf(y_chord), 0.0, float(gate.w), float(gate.h), bound_projected) == Gates.STATUS_UNRESOLVED)
	print("R5_RACE_RESULT " + JSON.stringify({source_scope = "unchanged production track, crossing, director, suffix validator; synthetic constant-acceleration piece; no FPV plant or collision world", hz = 240, acceleration_mps2 = a_n, normal_speed_min_mps = initial_v_n, normal_chord_speed_mps = v_n, tangent_speed_mps = v_u, gate_half_width_m = gate.w, chord_u_m = hit.u_m, epsilon_m = epsilon, true_curve_chord_residual_m = curve_residual, chord_time_s = hit.time_s, analytic_time_s = root, analytic_u_m = actual_u, intersection_error_m = actual_u - y_chord, projected_uncertainty_m = bound_projected, gate_count = out.modes_suffix[Director.D_GATES_TOTAL], event_types = out.events.map(func(e: Dictionary) -> String: return str(e.type))}))
	print("R5 race witness: %d failures" % failures)
	quit(1 if failures else 0)
