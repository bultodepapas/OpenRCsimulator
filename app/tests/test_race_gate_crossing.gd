# DR-25 RACE-04, RACE-05, RACE-06 (straight-piece part): the pure swept rectangular gate geometry of FPV/04 §3 —
# the 40 m/s numerical fixture, the strict aperture edge, rigid-motion invariance, the half-open plane convention,
# wrong-way, coplanar, zero-length and cross-and-return pieces, the uncertainty band and the A·h²/8 chord bound.
# Straight-segment mathematics only; curved-path evidence is the declared chord envelope, not a proof.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Gates := preload("res://sim/race/gate_crossing.gd")

const DT := 1.0 / 240.0

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _gate() -> Dictionary:
	return {c = M.v3(0.0, 0.0, 0.0), n = M.v3(1.0, 0.0, 0.0), u = M.v3(0.0, 1.0, 0.0), v = M.v3(0.0, 0.0, 1.0), w = 0.75, h = 0.75}


func _run() -> void:
	_fixture()
	_invariance()
	_plane_convention()
	_uncertainty_band()
	_bound()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _fixture() -> void:
	var gate: Dictionary = _gate()
	var p0: PackedFloat64Array = M.v3(-0.05, 0.25, 0.4)
	var p1: PackedFloat64Array = M.v3(0.1166666667, 0.25, 0.4)
	var hit: Dictionary = Gates.crossing(gate, p0, 0.0, p1, DT, 0.0)
	_check("RACE-04 the 40 m/s fixture crosses in the allowed direction, inside the aperture",
		hit.crossed and hit.direction_ok and hit.status == Gates.STATUS_INSIDE and absf(hit.normal_speed_mps - 40.0) < 1e-6,
		"%s %.9f m/s" % [hit.status, hit.normal_speed_mps])
	_check("RACE-04 crossing 1.25 ms after the tick start at lambda 0.3", absf(hit.time_s - 0.00125) < 1e-9
		and absf(hit.lambda - 0.3) < 1e-9, "t %.12f s lambda %.12f" % [hit.time_s, hit.lambda])
	_check("RACE-04 tick start underestimates by 1.25 ms, tick end overestimates by 2.9167 ms",
		absf(hit.time_s - 0.0 - 0.00125) < 1e-9 and absf(DT - hit.time_s - 0.0029166667) < 1e-9)
	var q: PackedFloat64Array = hit.point
	_check("RACE-04 crossing point (0, 0.25, 0.4)", absf(q[0]) < 1e-12 and q[1] == 0.25 and q[2] == 0.4,
		"%s" % str(q))
	var edge: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.75, 0.4), 0.0, M.v3(0.1166666667, 0.75, 0.4), DT, 0.0)
	_check("RACE-04 a point exactly on the aperture edge (u = 0.75) is outside under the strict edge rule",
		edge.crossed and edge.direction_ok and edge.status == Gates.STATUS_OUTSIDE)
	var edge_v: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.25, -0.75), 0.0, M.v3(0.1166666667, 0.25, -0.75), DT, 0.0)
	_check("RACE-04 the strict edge holds on the vertical axis too", edge_v.status == Gates.STATUS_OUTSIDE)
	var just_inside: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.7499999, 0.4), 0.0, M.v3(0.1166666667, 0.7499999, 0.4), DT, 0.0)
	_check("a point 0.1 um inside the edge with no declared uncertainty is inside", just_inside.status == Gates.STATUS_INSIDE)


func _invariance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261111
	var base: Dictionary = _gate()
	var cases: Array = [
		[M.v3(-0.05, 0.25, 0.4), M.v3(0.1166666667, 0.25, 0.4)],
		[M.v3(-0.05, 0.75, 0.4), M.v3(0.1166666667, 0.75, 0.4)],
		[M.v3(-0.3, -0.6, 0.2), M.v3(0.4, 0.9, -0.1)],
		[M.v3(0.2, 0.1, 0.1), M.v3(-0.2, 0.1, 0.1)],
	]
	var reference: Array = []
	for pair: Array in cases:
		reference.append(Gates.crossing(base, pair[0], 0.0, pair[1], DT, 0.0))
	var worst := 0.0
	var same := true
	for trial in 24:
		var axis: PackedFloat64Array = M.v3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
		var rotation: PackedFloat64Array = M.q_from_axis_angle(M.scale(axis, 1.0 / M.norm(axis)), rng.randf_range(-PI, PI))
		var shift: PackedFloat64Array = M.v3(rng.randf_range(-500.0, 500.0), rng.randf_range(-500.0, 500.0), rng.randf_range(-50.0, 50.0))
		var moved := {c = M.add(M.q_rotate(rotation, base.c), shift), n = M.q_rotate(rotation, base.n),
			u = M.q_rotate(rotation, base.u), v = M.q_rotate(rotation, base.v), w = base.w, h = base.h}
		for index: int in cases.size():
			var pair: Array = cases[index]
			var hit: Dictionary = Gates.crossing(moved, M.add(M.q_rotate(rotation, pair[0]), shift), 0.0,
				M.add(M.q_rotate(rotation, pair[1]), shift), DT, 0.0)
			var expected: Dictionary = reference[index]
			if hit.crossed != expected.crossed or hit.direction_ok != expected.direction_ok:
				same = false
				continue
			if hit.status != expected.status and absf(absf(expected.u_m) - base.w) > 1e-9:
				same = false
			if hit.crossed:
				var back: PackedFloat64Array = M.add(M.q_rotate(rotation, expected.point), shift)
				worst = maxf(worst, absf(hit.time_s - expected.time_s))
				worst = maxf(worst, absf(hit.u_m - expected.u_m))
				worst = maxf(worst, absf(hit.v_m - expected.v_m))
				worst = maxf(worst, M.norm(M.sub(hit.point, back)))
	_check("RACE-04 a common rigid rotation and translation of gate and piece preserves outcome, time and point (1e-9)",
		same and worst < 1e-9, "worst %s" % String.num_scientific(worst))
	print("    (an exact-edge case may flip by rounding under rotation; it is compared by values only, not by status)")


func _plane_convention() -> void:
	var gate: Dictionary = _gate()
	var wrong: Dictionary = Gates.crossing(gate, M.v3(0.1, 0.2, 0.1), 0.0, M.v3(-0.1, 0.2, 0.1), DT, 0.0)
	_check("RACE-05 wrong-way travel crosses the plane but is never a directed crossing",
		wrong.crossed and not wrong.direction_ok and wrong.normal_speed_mps < 0.0)
	var coplanar: Dictionary = Gates.crossing(gate, M.v3(0.0, -0.3, 0.1), 0.0, M.v3(0.0, 0.3, 0.1), DT, 0.0)
	_check("RACE-05 a coplanar piece never crosses", not coplanar.crossed and coplanar.status == Gates.STATUS_NONE)
	var start_on: Dictionary = Gates.crossing(gate, M.v3(0.0, 0.2, 0.1), 0.0, M.v3(0.1, 0.2, 0.1), DT, 0.0)
	_check("RACE-05 a piece starting on the plane (d0 = 0) does not count", not start_on.crossed)
	var ending: Dictionary = Gates.crossing(gate, M.v3(-0.1, 0.2, 0.1), 0.0, M.v3(0.0, 0.2, 0.1), DT, 0.0)
	var leaving: Dictionary = Gates.crossing(gate, M.v3(0.0, 0.2, 0.1), DT, M.v3(0.1, 0.2, 0.1), 2.0 * DT, 0.0)
	var counted: int = (1 if ending.crossed and ending.direction_ok else 0) + (1 if leaving.crossed and leaving.direction_ok else 0)
	_check("RACE-05 an endpoint exactly on the plane counts once across two consecutive pieces, at the shared time",
		counted == 1 and ending.lambda == 1.0 and ending.time_s == DT and ending.status == Gates.STATUS_INSIDE)
	var still: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.2, 0.1), 0.0, M.v3(-0.05, 0.2, 0.1), DT, 0.0)
	var still_on: Dictionary = Gates.crossing(gate, M.v3(0.0, 0.2, 0.1), 0.0, M.v3(0.0, 0.2, 0.1), DT, 0.0)
	_check("RACE-05 a zero-length piece never crosses, off or on the plane", not still.crossed and not still_on.crossed)
	var out: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.2, 0.1), 0.0, M.v3(0.05, 0.2, 0.1), DT, 0.0)
	var back: Dictionary = Gates.crossing(gate, M.v3(0.05, 0.2, 0.1), DT, M.v3(-0.05, 0.2, 0.1), 2.0 * DT, 0.0)
	var forward: int = (1 if out.direction_ok else 0) + (1 if back.direction_ok else 0)
	_check("RACE-06 cross and return within two pieces counts one forward crossing only", forward == 1 and back.crossed
		and not back.direction_ok)
	var malformed: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.2, 0.1), DT, M.v3(0.05, 0.2, 0.1), DT, 0.0)
	_check("a zero-duration or reversed-time piece is refused as no crossing", not malformed.crossed
		and not Gates.crossing(gate, M.v3(-0.05, NAN, 0.1), 0.0, M.v3(0.05, 0.2, 0.1), DT, 0.0).crossed)


func _uncertainty_band() -> void:
	var gate: Dictionary = _gate()
	var eps := 0.001
	var expected := {0.748: Gates.STATUS_INSIDE, 0.7495: Gates.STATUS_UNRESOLVED, 0.7505: Gates.STATUS_UNRESOLVED,
		0.752: Gates.STATUS_OUTSIDE}
	var horizontal := true
	var vertical := true
	var detail := ""
	for offset: float in expected:
		var across: Dictionary = Gates.crossing(gate, M.v3(-0.05, offset, 0.1), 0.0, M.v3(0.05, offset, 0.1), DT, eps)
		var up: Dictionary = Gates.crossing(gate, M.v3(-0.05, 0.1, -offset), 0.0, M.v3(0.05, 0.1, -offset), DT, eps)
		horizontal = horizontal and across.status == expected[offset]
		vertical = vertical and up.status == expected[offset]
		detail += "%.4f:%s/%s " % [offset, across.status, up.status]
	_check("RACE-06 eps band: w - 2eps inside, w - eps/2 and w + eps/2 unresolved, w + 2eps outside (both axes)",
		horizontal and vertical, detail)
	_check("RACE-06 the band is applied to both axes at once (a corner inside on u but in the band on v is unresolved)",
		Gates.classify(0.1, 0.7495, 0.75, 0.75, eps) == Gates.STATUS_UNRESOLVED
		and Gates.classify(0.7495, 0.76, 0.75, 0.75, eps) == Gates.STATUS_OUTSIDE)


func _bound() -> void:
	var bound: float = Gates.chord_bound_m(100.0, DT)
	_check("chord bound A·h²/8 at A = 100 m/s², h = 1/240 s is 0.217 mm", absf(bound - 0.000217) < 1e-6,
		"%.9f m" % bound)
	var declared: float = Gates.chord_bound_m(250.0, DT)
	_check("the declared 250 m/s² envelope gives about 0.54 mm at 240 Hz", absf(declared - 0.00054253) < 1e-7,
		"%.9f m" % declared)
